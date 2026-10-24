import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Pulls frames from the ESP32-CAM's local AP and runs an on-device TFLite model
/// through the Android platform channel. No image inference API or cloud backend
/// is used. This is a prototype: detections are probabilistic and are not safety-certified.
class CameraVisionService extends ChangeNotifier {
  CameraVisionService({
    required this.speak,
    required this.vibrate,
    required this.logEvent,
  });

  static const MethodChannel _channel = MethodChannel('blindstick_companion/vision');
  static const String defaultEndpoint = 'http://192.168.4.1';

  final Future<void> Function(String message) speak;
  final Future<void> Function(int durationMs) vibrate;
  final Future<void> Function(String message) logEvent;

  Timer? _timer;
  bool _processing = false;
  bool _running = false;
  bool _modelReady = false;
  bool preparing = false;
  bool _cameraReachable = false;
  int _failedFrames = 0;
  DateTime _lastCueAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastCueKey = '';
  DateTime _lastLoggedAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastLoggedCueKey = '';

  String endpoint = defaultEndpoint;
  String status = 'On-device AI model not prepared';
  String crowdLevel = 'unknown';
  String trafficState = 'not_detected';
  String pedestrianSignalState = 'unknown';
  String vehicleSignalState = 'unknown';
  bool pedestrianSignalLost = false;
  bool _seenPedestrianRedBaseline = false;
  String _pedestrianCandidate = 'unknown';
  int _pedestrianCandidateFrames = 0;
  int _pedestrianMissingFrames = 0;
  int personCount = 0;
  final List<int> _personCountSamples = <int>[];
  bool _frameStreamWarningSpoken = false;
  double? _ultrasonicDistanceCm;
  DateTime? _ultrasonicReceivedAt;
  String _rangeSensorStatus = 'unknown';
  List<Map<String, dynamic>> pedestrianSignals = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> detections = <Map<String, dynamic>>[];

  bool get modelReady => _modelReady;
  bool get cameraReachable => _cameraReachable;
  bool get running => _running;

  /// Supplies a fresh range sample from the BLE telemetry path for cautious sensor fusion.
  /// A distance value is not assigned to a particular visual detection; it is only
  /// combined with a central/lower camera-region candidate as supporting context.
  void updateRangeReading(
    double? distanceCm, {
    required DateTime? receivedAt,
    required String sensorStatus,
  }) {
    _rangeSensorStatus = sensorStatus;
    if (distanceCm != null &&
        distanceCm.isFinite &&
        distanceCm >= 2 &&
        distanceCm <= 400 &&
        receivedAt != null &&
        DateTime.now().difference(receivedAt) <= const Duration(seconds: 3) &&
        sensorStatus == 'fresh') {
      _ultrasonicDistanceCm = distanceCm;
      _ultrasonicReceivedAt = receivedAt;
    } else {
      _ultrasonicDistanceCm = null;
      _ultrasonicReceivedAt = null;
    }
  }

  double? get _freshUltrasonicDistance {
    final value = _ultrasonicDistanceCm;
    final receivedAt = _ultrasonicReceivedAt;
    if (_rangeSensorStatus != 'fresh' ||
        value == null ||
        receivedAt == null ||
        DateTime.now().difference(receivedAt) > const Duration(seconds: 3)) {
      return null;
    }
    return value;
  }

  Future<void> initialize() async {
    final preferences = await SharedPreferences.getInstance();
    endpoint = _normalizeEndpoint(
      preferences.getString('camera_base_url') ?? defaultEndpoint,
    );
    try {
      _modelReady = await _channel.invokeMethod<bool>('visionModelReady') ?? false;
      status = _modelReady
          ? 'On-device AI model ready'
          : 'AI model not downloaded yet. Prepare it while internet is available.';
    } catch (_) {
      status = 'On-device AI runtime is unavailable in this build';
    }
    notifyListeners();
  }

  String _normalizeEndpoint(String value) =>
      value.trim().replaceAll(RegExp(r'/+$'), '');

  Future<void> prepareModel() async {
    if (_modelReady || preparing) {
      if (_modelReady) status = 'On-device AI model already downloaded';
      notifyListeners();
      return;
    }
    preparing = true;
    status = 'Downloading the one-time AI model. Keep internet available…';
    notifyListeners();
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'prepareVisionModel',
      );
      _modelReady = result?['ready'] == true;
      status = _modelReady
          ? 'On-device AI ready. Connect the stick camera Wi-Fi to begin.'
          : 'Model download did not complete. Reconnect to the internet and retry.';
    } on PlatformException catch (error) {
      _modelReady = false;
      status = 'AI setup failed: ${error.message ?? error.code}';
    } catch (error) {
      _modelReady = false;
      status = 'AI setup failed: $error';
    } finally {
      preparing = false;
      notifyListeners();
      if (_modelReady && _running) {
        _timer ??= Timer.periodic(const Duration(milliseconds: 900), (_) => _processFrame());
        await _processFrame();
      }
    }
  }

  Future<void> saveEndpoint(String value) async {
    final parsed = Uri.tryParse(value.trim());
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty ||
        !(parsed.scheme == 'https' ||
          (parsed.scheme == 'http' && parsed.host == '192.168.4.1'))) {
      throw const FormatException(
        'Use https:// for remote endpoints, or the local camera URL http://192.168.4.1. Other cleartext HTTP hosts are blocked by Android network security.',
      );
    }
    endpoint = _normalizeEndpoint(parsed.toString());
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('camera_base_url', endpoint);
    _cameraReachable = false;
    status = 'Camera endpoint saved. Check the camera connection.';
    notifyListeners();
  }

  Future<void> openWifiSettings() async {
    try {
      await _channel.invokeMethod<bool>('openWifiSettings');
    } on PlatformException catch (error) {
      status = 'Could not open Wi-Fi settings: ${error.message ?? error.code}';
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> _cameraGet(String path) async {
    if (endpoint == defaultEndpoint) {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'cameraHttpGet',
        <String, Object>{'url': '$endpoint$path'},
      ).timeout(const Duration(seconds: 6));
      if (response == null) throw StateError('The camera request returned no response.');
      final statusCode = (response['statusCode'] as num?)?.toInt() ?? 0;
      final bodyBytes = response['bodyBytes'] as List<int>? ?? <int>[];
      final body = response['body']?.toString() ?? '';
      return <String, dynamic>{
        'statusCode': statusCode,
        'bodyBytes': bodyBytes,
        'body': body,
      };
    }
    final response = await http
        .get(Uri.parse('$endpoint$path'))
        .timeout(const Duration(seconds: 5));
    return <String, dynamic>{
      'statusCode': response.statusCode,
      'bodyBytes': response.bodyBytes,
      'body': response.body,
    };
  }

  Future<void> checkCamera() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      endpoint = _normalizeEndpoint(
        preferences.getString('camera_base_url') ?? endpoint,
      );
      final response = await _cameraGet('/status');
      if (response['statusCode'] != 200) {
        throw StateError('Camera returned HTTP ${response['statusCode']}.');
      }
      final data = jsonDecode(response['body'] as String) as Map<String, dynamic>;
      _cameraReachable = true;
      final assistanceActive = data['assistance'] == true;
      status = data['camera_ready'] == true
          ? (assistanceActive
              ? 'Camera connected. Assistance is active.'
              : 'Camera connected. Start assistance to enable live frames.')
          : 'Camera Wi-Fi connected, but the camera is not ready.';
    } catch (_) {
      _cameraReachable = false;
      status =
          'Camera not reachable. Connect to BlindStick-Camera Wi-Fi, then retry.';
    }
    notifyListeners();
  }

  Future<void> start() async {
    if (_running) return;
    if (!_modelReady) {
      status = 'Prepare the on-device AI model while internet is available first.';
      notifyListeners();
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    endpoint = _normalizeEndpoint(
      preferences.getString('camera_base_url') ?? endpoint,
    );
    _running = true;
    _failedFrames = 0;
    _frameStreamWarningSpoken = false;
    _personCountSamples.clear();
    personCount = 0;
    crowdLevel = 'unknown';
    pedestrianSignalState = 'unknown';
    vehicleSignalState = 'unknown';
    pedestrianSignalLost = false;
    _seenPedestrianRedBaseline = false;
    _pedestrianCandidate = 'unknown';
    _pedestrianCandidateFrames = 0;
    _pedestrianMissingFrames = 0;
    status = 'Starting camera detection…';
    _timer = Timer.periodic(const Duration(milliseconds: 900), (_) => _processFrame());
    notifyListeners();
    await _processFrame();
  }

  void stop() {
    if (!_running && _timer == null) return;
    _timer?.cancel();
    _timer = null;
    _running = false;
    _processing = false;
    if (status.startsWith('Detecting') || status.startsWith('Starting camera')) {
      status = _cameraReachable
          ? 'Vision paused'
          : 'Vision paused. Camera connection not confirmed.';
    }
    notifyListeners();
  }

  Future<void> _processFrame() async {
    if (!_running || _processing || !_modelReady) return;
    _processing = true;
    try {
      final response = await _cameraGet('/capture');
      if (response['statusCode'] != 200) {
        if (response['statusCode'] == 409) {
          throw StateError('Start stick assistance before requesting camera frames.');
        }
        throw StateError('Camera frame request returned HTTP ${response['statusCode']}.');
      }
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'detectObjects',
        <String, Object>{'jpegBytes': response['bodyBytes'] as List<int>},
      );
      if (result == null) throw StateError('The on-device model returned no result.');
      final rawDetections = result['detections'] as List<dynamic>? ?? <dynamic>[];
      detections = rawDetections.whereType<Map>().map((item) {
        return item.map((key, value) => MapEntry(key.toString(), value));
      }).toList(growable: false);
      personCount = ((result['personCount'] as num?)?.toInt() ?? 0).clamp(0, 100).toInt();
      _personCountSamples.add(personCount);
      if (_personCountSamples.length > 5) _personCountSamples.removeAt(0);
      final sortedPersonCounts = List<int>.of(_personCountSamples)..sort();
      final stabilizedPersonCount = sortedPersonCounts[sortedPersonCounts.length ~/ 2];
      crowdLevel = stabilizedPersonCount >= 5
          ? 'high'
          : stabilizedPersonCount >= 3
              ? 'medium'
              : 'low';
      final wasRecoveringFromFrameLoss = _failedFrames >= 3;
      _failedFrames = 0;
      if (wasRecoveringFromFrameLoss && _frameStreamWarningSpoken) {
        _frameStreamWarningSpoken = false;
        speak('Camera frames have resumed. Treat any new detection as an estimate and confirm your surroundings using your usual mobility method.').catchError((_) {});
      }
      final signalRows = result['pedestrianSignals'] as List<dynamic>? ?? <dynamic>[];
      pedestrianSignals = signalRows.whereType<Map>().map((item) {
        return item.map((key, value) => MapEntry(key.toString(), value));
      }).toList(growable: false);
      _updatePedestrianSignalState();
      final trafficDetections =
          detections.where((d) => d['label'] == 'traffic light');
      trafficState = trafficDetections.isEmpty
          ? 'not_detected'
          : (trafficDetections.first['trafficState'] ?? 'unknown').toString();
      _cameraReachable = true;
      _failedFrames = 0;
      status =
          'Detecting locally • ${detections.length} objects • $personCount people • crowd $crowdLevel';
      _processSafetyCue();
    } catch (error) {
      _failedFrames++;
      if (_failedFrames >= 3) {
        final previouslyHadSignal = pedestrianSignalState != 'unknown' ||
            pedestrianSignals.isNotEmpty;
        detections = <Map<String, dynamic>>[];
        pedestrianSignals = <Map<String, dynamic>>[];
        personCount = 0;
        crowdLevel = 'unknown';
        trafficState = 'not_detected';
        vehicleSignalState = 'unknown';
        pedestrianSignalState = 'unknown';
        if (previouslyHadSignal) pedestrianSignalLost = true;
        _personCountSamples.clear();
        if (!_frameStreamWarningSpoken) {
          _frameStreamWarningSpoken = true;
          HapticFeedback.heavyImpact();
          vibrate(300).catchError((_) {});
          speak('Warning. Camera frame updates have stopped. Object, crowd and signal estimates are unavailable. Stop somewhere safe and do not rely on the last camera result.').catchError((_) {});
          logEvent('Camera frame stream lost; AI detections marked unavailable').catchError((_) {});
        }
      }
      if (_failedFrames == 1 || _failedFrames % 4 == 0) {
        _cameraReachable = false;
        status =
            'Vision frame unavailable: ${error.toString().replaceFirst('Bad state: ', '')}';
      }
    } finally {
      _processing = false;
      notifyListeners();
    }
  }

  void _updatePedestrianSignalState() {
    final pedestrianCandidates = pedestrianSignals.where((d) {
      final label = d['label'];
      final score = (d['confidence'] as num? ?? 0).toDouble();
      return (label == 'human_red' || label == 'human_green') && score >= 0.45;
    }).toList()
      ..sort((a, b) =>
          ((b['confidence'] as num?) ?? 0).compareTo((a['confidence'] as num?) ?? 0));

    final vehicleCandidates = pedestrianSignals.where((d) {
      final label = d['label'];
      return label == 'vehicle_red' || label == 'vehicle_green';
    }).toList()
      ..sort((a, b) =>
          ((b['confidence'] as num?) ?? 0).compareTo((a['confidence'] as num?) ?? 0));
    vehicleSignalState = vehicleCandidates.isEmpty
        ? 'unknown'
        : (vehicleCandidates.first['label'] == 'vehicle_green' ? 'green' : 'red');

    if (pedestrianCandidates.isNotEmpty) {
      final candidate = pedestrianCandidates.first['label'] == 'human_red'
          ? 'red'
          : 'green';
      _pedestrianMissingFrames = 0;
      pedestrianSignalLost = false;
      if (candidate == _pedestrianCandidate) {
        _pedestrianCandidateFrames++;
      } else {
        _pedestrianCandidate = candidate;
        _pedestrianCandidateFrames = 1;
      }

      // Require a repeated result across frames before exposing a state to speech/UI.
      if (_pedestrianCandidateFrames >= 2) {
        if (candidate == 'red') {
          _seenPedestrianRedBaseline = true;
          pedestrianSignalState = 'red';
        } else {
          pedestrianSignalState =
              _seenPedestrianRedBaseline ? 'green' : 'green_unconfirmed';
        }
      }
      return;
    }

    _pedestrianCandidate = 'unknown';
    _pedestrianCandidateFrames = 0;
    _pedestrianMissingFrames++;
    if (_pedestrianMissingFrames >= 3 &&
        pedestrianSignalState != 'unknown' &&
        !pedestrianSignalLost) {
      pedestrianSignalLost = true;
      pedestrianSignalState = 'unknown';
      // Do not carry a red baseline across a long loss of visual contact;
      // the next signal could belong to another crossing.
      _seenPedestrianRedBaseline = false;
    } else if (_pedestrianMissingFrames >= 3) {
      pedestrianSignalState = 'unknown';
    }
  }

  /// Coded single-motor feedback: one short/long pulse = camera-left,
  /// two = camera-right, three = ahead/center. Longer pulses are urgent-stop
  /// priority; this is approximate camera geometry, not a measured 3-D direction.
  Future<void> _deliverObstaclePattern({
    required String side,
    required bool urgent,
  }) async {
    // Urgent range readings override side coding: one long pulse avoids
    // ambiguous multi-pulse cues while the local stop pattern is active.
    final count = urgent ? 1 : side == 'left' ? 1 : side == 'right' ? 2 : 3;
    final pulseMs = urgent ? 260 : 100;
    for (var i = 0; i < count; i++) {
      await vibrate(pulseMs);
      if (i + 1 < count) {
        await Future<void>.delayed(Duration(milliseconds: urgent ? 110 : 180));
      }
    }
  }

  void _processSafetyCue() {
    final highConfidence = detections.where((d) {
      return (d['confidence'] as num? ?? 0).toDouble() >= 0.48;
    }).toList();

    Map<String, dynamic>? obstacle;
    String obstacleSide = 'ahead';
    const obstacleLabels = <String>{
      'person',
      'bicycle',
      'car',
      'motorcycle',
      'bus',
      'truck',
      'dog',
      'bench',
      'chair',
      'stop sign',
      'fire hydrant',
      'potted plant',
    };
    for (final detection in highConfidence) {
      if (!obstacleLabels.contains(detection['label'])) continue;
      final value = detection['box'];
      if (value is! List || value.length != 4 || value.any((v) => v is! num)) continue;
      final top = (value[0] as num).toDouble();
      final left = (value[1] as num).toDouble();
      final bottom = (value[2] as num).toDouble();
      final right = (value[3] as num).toDouble();
      final centerX = (left + right) / 2;
      if (bottom > 0.62 && centerX > 0.12 && centerX < 0.88 && top < 0.92) {
        obstacle = detection;
        obstacleSide = centerX < 0.40 ? 'left' : centerX > 0.60 ? 'right' : 'ahead';
        break;
      }
    }

    final trafficOptions =
        highConfidence.where((d) => d['label'] == 'traffic light').toList();
    final Map<String, dynamic>? traffic =
        trafficOptions.isEmpty ? null : trafficOptions.first;

    final String cueKey;
    final String spoken;
    if (obstacle != null) {
      final label = obstacle['label'].toString();
      final range = _freshUltrasonicDistance;
      final rangeBand = range == null ? 'unknown' : range < 35 ? 'stop' : range < 90 ? 'caution' : 'far';
      cueKey = 'obstacle:$label:$obstacleSide:$rangeBand';
      if (range != null && range < 35) {
        spoken = 'Stop. The camera estimates a $label $obstacleSide and the ultrasonic sensor reports about ${range.round()} centimetres ahead. This reading may not belong to that exact object. Use your cane and stop if uncertain.';
      } else if (range != null && range < 90) {
        spoken = 'Caution. The camera estimates a $label $obstacleSide and the ultrasonic sensor reports about ${range.round()} centimetres ahead. Keep using your cane and slow down.';
      } else {
        spoken = 'Potential obstacle $obstacleSide: $label. No fresh matching distance estimate is available for this object. Use your cane and stop if uncertain.';
      }
    } else if (pedestrianSignalLost) {
      cueKey = 'pedestrian-signal-lost';
      spoken =
          'The pedestrian signal is no longer clearly visible. I cannot confirm the crossing indication. Stop in a safe place and verify using the audible or tactile crossing signal.';
    } else if (pedestrianSignalState == 'red') {
      cueKey = 'pedestrian-signal-red';
      spoken =
          'The model estimates a red pedestrian signal. Stop at the crossing and confirm with the audible or tactile signal. Do not rely on this camera alone.';
    } else if (pedestrianSignalState == 'green') {
      cueKey = 'pedestrian-signal-green';
      spoken =
          'The model estimates a green pedestrian signal after a previously observed red signal. This is not permission to cross. Confirm with the audible or tactile signal and check the crossing.';
    } else if (pedestrianSignalState == 'green_unconfirmed') {
      cueKey = 'pedestrian-signal-green-unconfirmed';
      spoken =
          'The model estimates a green pedestrian signal, but no red baseline has been observed in this session. Do not cross based on this app. Verify with the audible or tactile signal.';
    } else if (traffic != null) {
      final colour = (traffic['trafficState'] ?? 'unknown').toString();
      cueKey = 'vehicle-traffic-light:$colour';
      switch (colour) {
        case 'red':
          spoken =
              'A traffic light appears red. This cannot confirm the pedestrian signal or crossing safety.';
          break;
        case 'amber':
          spoken =
              'A traffic light appears amber. Wait in a safe place and check the pedestrian signal. Do not cross based on this camera estimate.';
          break;
        case 'green':
          spoken =
              'A traffic light appears green, but this does not confirm a pedestrian walk signal. Do not cross based on this app alone.';
          break;
        default:
          spoken =
              'Traffic light detected, but the signal colour is unclear. Do not cross based on this app.';
      }
    } else if (crowdLevel == 'high') {
      cueKey = 'crowd:high';
      spoken =
          'Several people are visible. The area may be crowded. Slow down and use your usual mobility technique.';
    } else {
      _lastCueKey = '';
      return;
    }

    final now = DateTime.now();
    final isNewCue = cueKey != _lastCueKey;
    final elapsed = now.difference(_lastCueAt);
    final shouldAnnounce = obstacle != null
        ? (isNewCue || elapsed >= const Duration(seconds: 4))
        : ((isNewCue || elapsed >= const Duration(seconds: 12)) &&
            elapsed >= const Duration(seconds: 4));
    if (shouldAnnounce) {
      _lastCueKey = cueKey;
      _lastCueAt = now;
      HapticFeedback.heavyImpact();
      if (obstacle != null) {
        _deliverObstaclePattern(
          side: obstacleSide,
          urgent: (_freshUltrasonicDistance ?? double.infinity) < 35,
        ).catchError((_) {});
      } else {
        vibrate(180).catchError((_) {});
      }
      speak(spoken).catchError((_) {});
      if (cueKey != _lastLoggedCueKey ||
          now.difference(_lastLoggedAt) >= const Duration(seconds: 30)) {
        _lastLoggedCueKey = cueKey;
        _lastLoggedAt = now;
        logEvent(spoken).catchError((_) {});
      }
    }
  }
}
