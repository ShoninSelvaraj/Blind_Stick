# Client feature audit — BlindStick Companion

This checklist maps the project's functional requirements in the CEBS Group 8 requirements/proposed-system slides to the code on `main`. It distinguishes app-side support from a verified hardware implementation. A green-looking UI or a successful Firestore write does not mean the full physical feature has been tested.

## Requirement-by-requirement status

| Client requirement | Current status on `main` | What is still missing before it can be called complete |
|---|---|---|
| Accessible patient home for blind/low-vision users | **Improved prototype** — Home / Navigate / Connections / Help & SOS tabs, large labelled controls, tab speech when Android accessible-navigation mode is not active, adjustable text, high contrast, TalkBack-compatible controls | Test with actual blind/low-vision users; keyboard/screen-reader walkthrough, contrast and text scaling QA on physical Android devices |
| GPS destination selection and in-app map | **Prototype implemented** — in-app OpenStreetMap map, Nominatim destination search, public walking-routing service, route preview and written maneuver list | Public service uptime/usage constraints, address ambiguity, footpath data coverage, route validation and manual provider/service fallback |
| Turn-by-turn spoken guidance | **Prototype implemented** — estimates distance to maneuvers from live phone GPS, announces turns, speaks warnings, handles poor GPS, pauses on suspected route deviation and offers manual recalculation | Must be tested walking real routes; no guaranteed rerouting, no certified pedestrian crossing guidance, no tested offline support |
| Screen-off/background guidance while a route is active | **Android foreground service option added** — user is prompted to grant background-location access; foreground-only mode warns to keep the app open | Validate runtime permission flow on Android versions/devices and confirm voice/GPS behavior with screen locked, app switched, battery saver and denied permissions |
| Haptic/vibration cues | **Prototype implemented in code** — app haptics and a BLE `vibrate` command; ESP32 firmware pulses a configured driver output and local ultrasonic alerts do not require the phone | Verify the actual motor driver, power, flyback protection, GPIO2 boot behavior and feedback patterns on the physical stick |
| Real-time ultrasonic obstacle distance | **Firmware and app path implemented, hardware unverified** — ESP32 firmware reads an HC-SR04-style sensor, reports fresh `distance_cm` over BLE, and can pulse the motor locally | Confirm physical sensor model/wiring, 5V ECHO level shifting, pin map, calibration, stale-data behavior and real-world tests |
| Camera-based object detection/classification | **Android on-device prototype wired** — the app downloads quantized SSD MobileNet V1 COCO, fetches camera JPEGs over local Wi-Fi, and runs TensorFlow Lite inference on the phone | The ESP32-CAM is a frame source, not the inference processor. COCO only recognises known classes, up to 10 detections/frame; accuracy, latency, object warnings and physical camera path still require validation |
| Traffic-light recognition / walk-stop cue | **Limited prototype** — COCO detects traffic-light-shaped objects, then phone code estimates dominant red/amber/green pixels in the detected box | Not a pedestrian signal classifier. Must never tell the user to cross. Validate false detections, unknown states, lighting conditions and user-safe wording; use a dedicated pedestrian signal model if the requirement demands actual WALK/STOP recognition |
| Crowd-density warning | **Basic prototype implemented** — person detections in a single camera frame are counted; high count triggers a cautious slow-down cue | One frame count is not calibrated crowd density; model only returns a limited set of boxes and may miss people. Needs validation and tuning on a representative dataset |
| Live location sharing to caregiver | **Partly implemented** — opt-in updates roughly every 30 seconds while the patient app is open; linked caregiver sees Firestore changes | It is not continuous background tracking; handle app/process suspension, offline queue/recovery, stale-location status and battery/privacy testing |
| Pair a caregiver securely | **App-side prototype implemented** — one-time, ten-minute code, one use, Firestore role/link rules; up to two linked caregivers | Must deploy Firestore rules, test owner/caregiver/unrelated-account access, test expiry/concurrent code redemption, and remove/change pairing workflow needs design |
| SOS / emergency alert | **Partly implemented** — SOS saved to Firestore; patient can open SMS composer with a help message and location | SMS is not sent automatically; recipient must be selected and message sent. No zero-billing background push exists. No emergency-service integration or delivery guarantee |
| Background push notification | **Disabled in zero-billing mode** | The Cloud Function reference remains in the repository but is excluded from root `firebase.json`; deploy only if project owner later authorizes a billing-enabled server approach |
| Battery/low-power monitoring | **Not implemented** | Current firmware sends no battery level or battery health; requires actual monitor hardware and validation |
| Indoor navigation | **Not implemented** | No indoor positioning infrastructure or local map data available |

## What the current ESP32-CAM firmware actually does

File: `firmware/esp32_cam/esp32_cam_ble_bridge.ino`

- Initializes the AI-Thinker-style camera map, advertises BLE, starts the local camera AP and serves a JPEG on request.
- Accepts `hello`, `start`, `stop`, and `vibrate` commands.
- Reads an optional HC-SR04-style sensor and reports a fresh `distance_cm` over BLE.
- Pulses a motor-driver output from local distance thresholds and phone-issued vibration commands.
- The Android app performs on-device COCO object inference and a limited traffic-lamp colour heuristic from captured JPEGs. Battery level is still not reported.

Do not demo any unavailable camera/sensor function as working. A successful BLE connection only proves that the phone and firmware can communicate.

## Zero-budget constraints

- Firebase Auth and Firestore are retained within their Spark quotas.
- The app's root `firebase.json` deploys only `firestore.rules`, not Cloud Functions.
- Mapping, geocoding and routing use open-source clients/public community services. Public endpoints have policies, limits and no uptime guarantee; the current endpoint settings can be changed in the app's advanced settings.
- No map tile or routing data is promised to work offline.
- Do not put safety-critical navigation or emergency reliance on these public prototype services until there is a separately reviewed and tested plan.

## Suggested validation order

1. Pull main, build, and verify login/registration, sign-out, tab order, TalkBack labels, text scaling and contrast.
2. Deploy Firestore rules and test patient/caregiver pairing with an unrelated third account.
3. Walk a short, supervised route and test GPS loss, poor accuracy, turn prompts, stopping, back navigation, screen lock permission modes and route-deviation warnings.
4. Bench-test the ESP32 camera/BLE bridge, camera Wi-Fi endpoint, ultrasonic input and motor-driver pulse output with confirmed pins and voltage limits.
5. Verify model download, frame transfer and TensorFlow Lite inference on a physical Android phone; measure latency and test false positives/negatives in controlled conditions.
6. Validate traffic-lamp colour estimation only as a non-authoritative warning; never claim it recognises pedestrian WALK/STOP. Test crowd cue thresholds with representative scenes.
7. Test SMS compose fallback and explain to users that it must be sent manually.

**Safety boundary:** This is a companion prototype, not a certified mobility aid. It must not be the user's only means of obstacle avoidance, road-crossing decisions, or emergency communication.
