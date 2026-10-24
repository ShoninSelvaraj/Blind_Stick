import 'package:flutter_test/flutter_test.dart';
import 'package:blindstick_companion/main.dart';

void main() {
  group('StickTelemetry', () {
    test('accepts only the firmware protocol and device identity', () {
      expect(
        isCompatibleStickTelemetry({
          'protocol': 1,
          'device': 'blindstick_companion-esp32cam',
        }),
        isTrue,
      );
      expect(
        isCompatibleStickTelemetry({
          'protocol': 2,
          'device': 'blindstick_companion-esp32cam',
        }),
        isFalse,
      );
      expect(
        isCompatibleStickTelemetry({
          'protocol': 1,
          'device': 'some-other-device',
        }),
        isFalse,
      );
    });

    test('does not invent a battery percentage when firmware says unavailable', () {
      final telemetry = StickTelemetry();
      telemetry.fromJson({'battery_status': 'unavailable'});
      expect(telemetry.battery, isNull);
    });

    test('accepts a valid fresh distance and classifies urgency', () {
      final telemetry = StickTelemetry();

      telemetry.fromJson({
        'distance_cm': 28,
        'range_sensor_status': 'fresh',
      });

      expect(telemetry.distanceCm, 28);
      expect(telemetry.rangeSensorStatus, 'fresh');
      expect(telemetry.urgent, isTrue);
      expect(telemetry.caution, isTrue);
      expect(telemetry.distanceReceivedAt, isNotNull);
    });

    test('rejects distances outside the ultrasonic sensor range', () {
      final telemetry = StickTelemetry();

      telemetry.fromJson({
        'distance_cm': 0,
        'range_sensor_status': 'fresh',
      });

      expect(telemetry.distanceCm, isNull);
      expect(telemetry.distanceReceivedAt, isNull);
      expect(telemetry.rangeSensorStatus, 'unavailable');
      expect(telemetry.urgent, isFalse);
      expect(telemetry.caution, isFalse);
    });

    test('does not treat missing range data as a clear path', () {
      final telemetry = StickTelemetry();

      telemetry.fromJson({
        'range_sensor_status': 'fresh',
      });

      expect(telemetry.distanceCm, isNull);
      expect(telemetry.rangeSensorStatus, 'unavailable');
    });

    test('accepts only valid battery percentages', () {
      final telemetry = StickTelemetry();

      telemetry.fromJson({'battery_percent': 72});
      expect(telemetry.battery, 72);

      telemetry.fromJson({'battery_percent': 101});
      expect(telemetry.battery, isNull);

      telemetry.fromJson({'battery_percent': -1});
      expect(telemetry.battery, isNull);

      telemetry.fromJson({'battery_percent': 'unknown'});
      expect(telemetry.battery, isNull);
    });

    test('rejects non-numeric distance telemetry', () {
      final telemetry = StickTelemetry();

      telemetry.fromJson({
        'distance_cm': 'unknown',
      });

      expect(telemetry.distanceCm, isNull);
      expect(telemetry.rangeSensorStatus, 'unavailable');
    });
  });
}
