# Client requirements implementation status — BlindStick Companion

This document separates code-backed features from capabilities that need hardware, deployment or field validation. Do not describe a prototype or a model prediction as a safety guarantee.

## Requirements found in the repository

The requirements baseline is `docs/CLIENT_FEATURE_AUDIT.md`, cross-checked against the current Flutter, Kotlin and ESP32-CAM source.

| Client requirement | Existing source implementation | Remaining gap / acceptance check |
|---|---|---|
| Accessible patient interface | Four task tabs, labelled large controls, TalkBack-compatible controls, adjustable text/high contrast and TTS | Test with screen reader, 200% font scaling/system settings, contrast and blind/low-vision users on real devices |
| Destination search, map and pedestrian route | In-app OpenStreetMap, user-triggered Nominatim query, public foot-router, route instructions | Address ambiguity, endpoint failures, road/footpath coverage; safely test on known supervised routes |
| Turn-by-turn spoken guidance | GPS stream, maneuver-distance bands, haptic prompts, GPS accuracy checks and route-deviation pause/manual recalculation | Screen-off/device power behavior, permissions, GPS loss and real-route testing; no certified crossing or guaranteed reroute |
| Background guidance | Android foreground location configuration while navigation screen is active | Confirm permissions and behavior on supported Android versions and battery policies |
| Stick BLE connection and vibration | BLE protocol, ESP32 camera access, phone-issued vibration commands and local stop/caution motor patterns | Physical bench test of board pinout, driver, power, boot behavior and distinguishability of patterns |
| Ultrasonic obstacle distance | Firmware distance telemetry, freshness timeouts, fail-closed app warnings | Confirm sensor wiring, calibration, aim and 5V ECHO level shifting. Missing/stale measurements must never mean “clear” |
| Common-object and people detection | Quantized SSD MobileNet COCO on Android from ESP32-CAM JPEG frames; rolling median for people count | Test false negatives/latency and realistic scenes; crowd count is not calibrated crowd density |
| Pedestrian/vehicle signal model | MIT-licensed YOLO26n TFLite model, pinned SHA-256, two-frame confirmation and red-baseline logic | Extensive field evaluation; unknown/lost signal remains unknown; never make crossing decisions from model output |
| Caregiver pairing/location | One-time 8-digit code, 10-minute expiry, Firestore rules, opt-in location sharing and stale timestamp UI | Deploy rules; verify patient/caregiver/unrelated-account access, expiry and concurrent code redemption |
| SOS and caregiver alerts | Firestore SOS record, optional SMS composer, foreground caregiver alert monitor | A save is not delivery. SMS requires user to send. Foreground monitoring is best-effort and can be stopped by Android/network limits |
| Battery/low power | Telemetry model has a nullable battery field, but the ESP32-CAM firmware does not measure or transmit battery state | Requires battery-voltage monitor/ADC wiring, divider/protection, calibration and a known power source; do not display a fabricated percentage |
| Indoor navigation | No indoor positioning system or local indoor map present | Requires indoor positioning infrastructure (e.g. BLE beacons/UWB/Wi-Fi RTT) and mapped building data; do not fake it using GPS |

## Zero-budget implementation policy

- Keep Firebase Authentication and Firestore, within the free Spark plan quotas.
- Do not introduce paid Maps APIs, cloud AI inference, paid push services, or required Cloud Functions.
- Reuse the on-device SSD MobileNet COCO and MIT-licensed YOLO26n model already wired into Android. They avoid per-frame API billing. TensorFlow's Android examples document the supported quantized MobileNet SSD approach: https://github.com/tensorflow/examples/tree/master/lite/examples/object_detection/android
- Use public OpenStreetMap community services only as a low-volume prototype, respect their usage policies, and keep written/spoken warnings when the service fails.
- Never invent sensor data, infer a battery percentage without a connected monitor, or call an SOS “delivered” without an acknowledged delivery channel.

## Acceptance test checklist

### App / accessibility
- [ ] Create patient and caregiver accounts, sign in, reset password and sign out.
- [ ] Test large touch targets, TalkBack labels/order, high contrast and text scaling.
- [ ] Verify that every disabled/unavailable control states what the user needs to do.

### Smart-stick hardware
- [ ] Check BLE pairing, start/stop commands and recovery after disconnect.
- [ ] Check camera frame stream and model preparation while on internet.
- [ ] Connect to the camera AP and verify local camera access without breaking the normal internet path.
- [ ] Confirm ultrasonic measurement using known distances; test missing/stale readings.
- [ ] Bench-test vibration patterns with appropriate transistor/MOSFET driver and protection.
- [ ] Verify battery monitoring only after the actual battery chemistry, safe measurement circuit and calibration are defined.

### Navigation
- [ ] Walk only a short, supervised, familiar route with a sighted safety companion.
- [ ] Test poor GPS, network failure, wrong destination, route departure, screen lock and manual recalculation.
- [ ] Treat every traffic-signal estimate as unknown unless confirmed by an established audible/tactile crossing signal and the user's normal mobility practice.

### Caregiver / security
- [ ] Deploy Firestore rules and test three accounts: patient, paired caregiver and unrelated account.
- [ ] Test pairing expiration, one-use redemption and caregiver limit.
- [ ] Confirm location opt-in/off, last-update timestamp, revoked permission and network loss behavior.
- [ ] Confirm local SOS notification with the caregiver app/service active; verify SMS is manually sent and never claim emergency services were contacted.

## Safety boundary

This is an assistive prototype, not a certified mobility aid. Do not rely on it as the sole means of obstacle avoidance, road-crossing decisions, indoor wayfinding, or emergency contact. The app and hardware chain still requires supervised device testing and a documented safety review.
