# Client feature audit — BlindStick Companion

This checklist maps the project's functional requirements in the CEBS Group 8 requirements/proposed-system slides to the code on `main`. It distinguishes app-side support from a verified hardware implementation. A green-looking UI or a successful Firestore write does not mean the full physical feature has been tested.

## Requirement-by-requirement status

| Client requirement | Current status on `main` | What is still missing before it can be called complete |
|---|---|---|
| Accessible patient home for blind/low-vision users | **Improved prototype** — Home / Navigate / Connections / Help & SOS tabs, large labelled controls, tab speech when Android accessible-navigation mode is not active, adjustable text, high contrast, TalkBack-compatible controls | Test with actual blind/low-vision users; keyboard/screen-reader walkthrough, contrast and text scaling QA on physical Android devices |
| GPS destination selection and in-app map | **Prototype implemented** — in-app OpenStreetMap map, Nominatim destination search, public walking-routing service, route preview and written maneuver list | Public service uptime/usage constraints, address ambiguity, footpath data coverage, route validation and manual provider/service fallback |
| Turn-by-turn spoken guidance | **Prototype implemented** — estimates distance to maneuvers from live phone GPS, announces turns, speaks warnings, handles poor GPS, pauses on suspected route deviation and offers manual recalculation | Must be tested walking real routes; no guaranteed rerouting, no certified pedestrian crossing guidance, no tested offline support |
| Screen-off/background guidance while a route is active | **Android foreground service option added** — user is prompted to grant background-location access; foreground-only mode warns to keep the app open | Validate runtime permission flow on Android versions/devices and confirm voice/GPS behavior with screen locked, app switched, battery saver and denied permissions |
| Haptic/vibration cues | **Phone haptics only** — app triggers haptic feedback for supported stick warnings and turn proximity | The ESP32 firmware does not drive a physical cane-mounted vibration motor. Needs confirmed motor/driver wiring, safe power design, firmware output protocol and hardware testing |
| Real-time ultrasonic obstacle distance | **Not implemented end-to-end** — the app can parse a `distance_cm` telemetry field and warn if one is actually received | Current ESP32 firmware does not read an ultrasonic sensor and sends no distance value. Needs sensor model, confirmed safe pins/level shifting as applicable, firmware, bench calibration and real-world tests |
| Camera-based object detection/classification | **Not implemented** — ESP32-CAM initializes and captures a frame; app correctly shows that the AI model is missing | No trained/converted model, inference pipeline, confidence handling, false-positive/false-negative testing, object warning protocol or validated latency |
| Traffic-light recognition / walk-stop cue | **Not implemented** — UI explains it is unavailable | No model or signal-state classifier exists. It must not advise the user to cross; implement/test with cautious uncertainty handling and nonvisual confirmation only after model validation |
| Crowd-density warning | **Not implemented** — UI explains it is unavailable | No crowd model/classifier or telemetry currently exists |
| Live location sharing to caregiver | **Partly implemented** — opt-in updates roughly every 30 seconds while the patient app is open; linked caregiver sees Firestore changes | It is not continuous background tracking; handle app/process suspension, offline queue/recovery, stale-location status and battery/privacy testing |
| Pair a caregiver securely | **App-side prototype implemented** — one-time, ten-minute code, one use, Firestore role/link rules; up to two linked caregivers | Must deploy Firestore rules, test owner/caregiver/unrelated-account access, test expiry/concurrent code redemption, and remove/change pairing workflow needs design |
| SOS / emergency alert | **Partly implemented** — SOS saved to Firestore; patient can open SMS composer with a help message and location | SMS is not sent automatically; recipient must be selected and message sent. No zero-billing background push exists. No emergency-service integration or delivery guarantee |
| Background push notification | **Disabled in zero-billing mode** | The Cloud Function reference remains in the repository but is excluded from root `firebase.json`; deploy only if project owner later authorizes a billing-enabled server approach |
| Battery/low-power monitoring | **Not implemented** | Current firmware sends no battery level or battery health; requires actual monitor hardware and validation |
| Indoor navigation | **Not implemented** | No indoor positioning infrastructure or local map data available |

## What the current ESP32-CAM firmware actually does

File: `firmware/esp32_cam/esp32_cam_ble_bridge.ino`

- Initializes the AI-Thinker-style camera mapping, attempts frame capture, advertises the BLE service and reports camera/device status.
- Accepts `hello`, `start`, and `stop` commands.
- Reports `detection_status: model_not_installed`.
- Does **not** send any object classification, traffic-light state, crowd density, ultrasonic distance, battery reading or physical motor command.

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
4. Bench-test the ESP32 camera/BLE bridge; only then integrate one sensor at a time with confirmed pins and voltage limits.
5. Implement on-device object detection and verify it on a test corpus; only then expose detections as user-facing advice.
6. Test SMS compose fallback and explain to users that it must be sent manually.

**Safety boundary:** This is a companion prototype, not a certified mobility aid. It must not be the user's only means of obstacle avoidance, road-crossing decisions, or emergency communication.
