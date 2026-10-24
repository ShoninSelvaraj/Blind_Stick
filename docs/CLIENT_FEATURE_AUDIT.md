# Client feature audit — BlindStick Companion

This checklist maps the project's functional requirements in the CEBS Group 8 requirements/proposed-system slides to the code on `main`. It distinguishes app-side support from a verified hardware implementation. A green-looking UI or a successful Firestore write does not mean the full physical feature has been tested.

## Requirement-by-requirement status

| Client requirement | Current status on `main` | What is still missing before it can be called complete |
|---|---|---|
| Accessible patient home for blind/low-vision users | **Improved prototype** — Home / Navigate / Connections / Help & SOS tabs, large labelled controls, tab speech when Android accessible-navigation mode is not active, adjustable text, high contrast, TalkBack-compatible controls | Test with actual blind/low-vision users; keyboard/screen-reader walkthrough, contrast and text scaling QA on physical Android devices |
| GPS destination selection and in-app map | **Prototype implemented** — in-app OpenStreetMap map, Nominatim destination search, public walking-routing service, route preview and written maneuver list | Public service uptime/usage constraints, address ambiguity, footpath data coverage, route validation and manual provider/service fallback |
| Turn-by-turn spoken guidance | **Prototype implemented** — estimates distance to maneuvers from live phone GPS, announces turns, speaks warnings, handles poor GPS, pauses on suspected route deviation and offers manual recalculation | Must be tested walking real routes; no guaranteed rerouting, no certified pedestrian crossing guidance, no tested offline support |
| Screen-off/background guidance while a route is active | **Android foreground service option added** — user is prompted to grant background-location access; foreground-only mode warns to keep the app open | Validate runtime permission flow on Android versions/devices and confirm voice/GPS behavior with screen locked, app switched, battery saver and denied permissions |
| Haptic/vibration cues | **Implemented in firmware/app code, hardware unverified** — local ESP32 stop/caution pulse cadences plus approximate camera-left/right/ahead coded pulse counts | Verify the actual motor driver, power, flyback protection, GPIO2 boot behavior, camera alignment, user learnability and patterns on the physical stick |
| Real-time ultrasonic obstacle distance | **Firmware and app path implemented, hardware unverified** — ESP32 firmware reports `range_sensor_status` and `distance_cm`; the phone fails closed on missing/stale values and provides range context to visual obstacle cues | Confirm physical sensor model/wiring, 5V ECHO level shifting, pin map, calibration and whether the sensor points in line with the camera |
| Camera-based object detection/classification | **Android on-device prototype wired** — the app runs quantized SSD MobileNet V1 COCO for common objects and person counts; camera JPEG frames travel over local Wi-Fi and inference stays on the phone. | The ESP32-CAM is a frame source, not the inference processor. COCO recognizes only trained categories; detections, latency and the physical camera path need validation. |
| Traffic-light recognition / walk-stop cue | **Dedicated-model prototype integrated** — an MIT-licensed YOLO26n seven-class TFLite model separately predicts `human_red`, `human_green`, `vehicle_red`, and `vehicle_green`. Dart requires a two-frame agreement and a red baseline before exposing possible green; signal disappearance clears that baseline. | Still experimental, not a certified crossing signal. It never tells the user to cross; predictions need measured latency/accuracy and false-positive testing on the actual camera and target traffic environment. Require confirmation from audible/tactile crossing signals. |
| Crowd-density warning | **Basic prototype implemented** — person count is stabilised using a rolling five-frame median; a high count triggers a cautious slow-down cue | Count is not calibrated density, model may miss people, and thresholds need validation on a representative dataset |
| Live location sharing to caregiver | **Implemented in app code, device test pending** — opt-in live GPS stream while app is open or through Android foreground-location mode with a persistent notification | Force-stop/reboot, revoked permissions, GPS/network loss and Firestore errors can stop updates; validate stale-location timestamps and battery/privacy behavior |
| Pair a caregiver securely | **App-side prototype implemented** — one-time, ten-minute code, one use, Firestore role/link rules; up to two linked caregivers | Must deploy Firestore rules, test owner/caregiver/unrelated-account access, test expiry/concurrent code redemption, and remove/change pairing workflow needs design |
| SOS / emergency alert | **Partly implemented** — SOS saved to Firestore; patient can open SMS composer with a help message and location | SMS is not sent automatically; recipient must be selected and message sent. No zero-billing background push exists. No emergency-service integration or delivery guarantee |
| Background caregiver SOS notification | **Native foreground-service prototype implemented without Cloud Functions** — caregiver opts in, sees a persistent monitoring notification, and receives local Android notifications for new linked-patient SOS records | Requires notification permission, signed-in caregiver, valid pairing and internet; test on physical Android versions, reboot/force-stop/battery restrictions, and Firestore reconnect. This is best-effort, not guaranteed delivery or emergency-service integration |
| Battery/low-power monitoring | **Not implemented** | Current firmware sends no battery level or battery health; requires actual monitor hardware and validation |
| Indoor navigation | **Not implemented** | No indoor positioning infrastructure or local map data available |

## What the current ESP32-CAM firmware actually does

File: `firmware/esp32_cam/esp32_cam_ble_bridge.ino`

- Initializes the AI-Thinker-style camera map, advertises BLE, starts the local camera AP and serves a JPEG on request.
- Accepts `hello`, `start`, `stop`, and `vibrate` commands.
- Reads an optional HC-SR04-style sensor and reports `range_sensor_status` plus a fresh `distance_cm` over BLE.
- Uses distinct local motor patterns for urgent close obstacles and the wider caution range, as well as phone-issued vibration commands.
- The Android app performs on-device COCO object inference plus the dedicated YOLO26n seven-class pedestrian/vehicle signal inference from captured JPEGs. The colour heuristic is still available only as a general vehicle-lamp estimate, not as the pedestrian-signal source. Battery level is still not reported.

Do not demo any unavailable camera/sensor function as working. A successful BLE connection only proves that the phone and firmware can communicate.

## Zero-budget constraints

- Firebase Auth and Firestore are retained within their Spark quotas.
- The app's root `firebase.json` deploys only `firestore.rules`, not Cloud Functions.
- Camera/range fusion is advisory: the ultrasonic value is not calibrated to a particular visual bounding box.
- One/two/three short motor pulses represent approximate camera-left/right/ahead only when the range is not urgent; a fresh close-range reading overrides direction coding with one longer stop-priority pulse. This single-motor code is not a precise spatial actuator.
- Mapping, geocoding and routing use open-source clients/public community services. Public endpoints have policies, limits and no uptime guarantee; the current endpoint settings can be changed in the app's advanced settings. Local camera HTTP requests use a Wi-Fi-bound Android connection so the whole app is not process-bound to the camera AP; online map access still depends on Android selecting a working internet route, normally mobile data.
- No map tile or routing data is promised to work offline.
- Do not put safety-critical navigation or emergency reliance on these public prototype services until there is a separately reviewed and tested plan.

## Suggested validation order

1. Pull main, build, and verify login/registration, sign-out, tab order, TalkBack labels, text scaling and contrast.
2. Deploy Firestore rules and test patient/caregiver pairing with an unrelated third account.
3. Walk a short, supervised route and test GPS loss, poor accuracy, turn prompts, stopping, back navigation, screen lock permission modes and route-deviation warnings.
4. Bench-test the ESP32 camera/BLE bridge, camera Wi-Fi endpoint, ultrasonic input and motor-driver pulse output with confirmed pins and voltage limits.
5. Verify both model downloads, pinned SHA-256, frame transfer and TensorFlow Lite inference on a physical Android phone; measure latency and test false positives/negatives in controlled conditions.
6. Validate the dedicated `human_red`/`human_green` model on representative scenes. Never interpret its prediction as permission to cross. Test unknown/lost-signal behavior and the audible/tactile confirmation workflow.
7. Test crowd cue thresholds with representative scenes, opt-in background caregiver monitoring, and SMS compose fallback (the user must send it manually).

**Safety boundary:** This is a companion prototype, not a certified mobility aid. It must not be the user's only means of obstacle avoidance, road-crossing decisions, or emergency communication.
