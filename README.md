# BlindStick Companion — zero-budget accessible mobility companion

Flutter Android prototype for a smart-stick project. It is designed for people who are blind or have low vision, with spoken prompts, large controls, adjustable text, high-contrast mode, and TalkBack-compatible controls.

## Zero-cost operating approach

The app does not require Google Maps SDK, Google Maps API keys, paid map APIs, or Firebase Cloud Functions to run the current features.

| Feature | Current zero-cost option | Important limit |
|---|---|---|
| Sign-in and account roles | Firebase Authentication email/password | Subject to Firebase plan and service terms |
| Profiles, pairing, alerts, shared locations | Cloud Firestore on Spark | Read/write/storage limits apply; the service can stop writes if limits are exceeded |
| Map shown inside this app | `flutter_map` + OpenStreetMap tiles | Public tiles are best-effort and usage policy applies |
| Search a typed destination | Public Nominatim geocoder | User-triggered search only, no autocomplete, max 1 request/second per app; results/service can be unavailable |
| Walking route | OpenStreetMap community foot-routing server | Community demo server: no SLA and limited reasonable use; do not treat it as safety-certified |
| Voice guidance | Android text-to-speech through `flutter_tts` | Device voice availability and language settings vary |
| Ultrasonic distance and stick vibration | ESP32 firmware emits explicit range-sensor health over BLE, rejects absent/stale range data in the app, and uses short/repeating stop pulses versus shorter/slower caution pulses | Exact wiring must be verified, 5V ECHO needs level shifting, GPIO2 affects boot, and the physical sensor/motor still need bench testing |
| Emergency alert | Save SOS in Firestore and optionally open the phone's SMS composer | SMS is **not sent automatically**; the user must select a recipient and tap send. Carrier SMS costs may apply |
| Background push notification | Not included in zero-billing mode | Sending FCM push messages requires a trusted sender/server. No automatic background push is claimed |
| Object detection / crowd estimate | Quantized SSD MobileNet V1 COCO runs locally on Android from ESP32-CAM JPEG frames; the crowd cue uses a rolling five-frame median of the person count | Common COCO classes only; count-based crowd level is a rough heuristic, and false negatives/latency remain possible |
| Pedestrian / vehicle signal detection | MIT-licensed YOLO26n seven-class TFLite model classifies human-red, human-green, vehicle-red, and vehicle-green separately, on-device | Experimental classifier; no safe-crossing guarantee, no crossing command, and no field validation for Indian traffic signals |

**Zero budget means no required paid service in this design; it does not mean unlimited capacity or guaranteed availability.** Do not use public community servers for high-volume or mission-critical navigation. If the project grows, self-host OpenStreetMap-derived services on hardware you already control, or use a provider only after checking its terms and price.

## Accessibility

- Register by choosing the task: **Use my smart stick** or **Support someone I care about**. This is an app role, not identity or disability verification.
- After sign-in, the patient interface is separated into four named task areas: **Home**, **Navigate**, **Connections**, and **Help & SOS**. The app bar keeps accessibility settings and sign-out easy to find.
- Primary actions have clear text labels and large touch targets. The app speaks tab changes when Android accessible-navigation mode is not active; standard Flutter controls expose labels to TalkBack without a competing tab announcement.
- Home includes a device-readiness section that explicitly shows missing sensor/model capabilities rather than pretending they work.
- Accessibility settings are reachable before sign-in and from signed-in screens. They offer spoken guidance, text scaling (100–160%) that respects Android text scaling, and high-contrast black/white colors.
- Android TalkBack and system display settings remain available.
- Navigation instructions are available both as readable text and spoken prompts. Tapping an instruction speaks it.
- Sign out is visible on the patient and caregiver home bars and is also available in settings.
- Avoid relying on the map alone. Keep the spoken/written instructions and status messages available to people who cannot see the map.

## Firebase setup — no Cloud Functions

Firebase project: `blindstick001`; Android package: `com.vimal.blindstick`.

1. In Firebase Console, enable **Authentication → Sign-in method → Email/Password** and make sure the Firestore database is created.
2. Download the genuine Android `google-services.json` for package `com.vimal.blindstick` from Project settings, and put it at `android/app/google-services.json`.
3. Sign in to the Firebase CLI and deploy only the rules:

```powershell
firebase.cmd login
firebase.cmd use blindstick001
firebase.cmd deploy --only firestore:rules
```

The root `firebase.json` intentionally excludes Cloud Functions so the recommended deploy command does not trigger a billing-plan upgrade. Do **not** run `firebase deploy --only functions` in the zero-billing setup.

## Account pairing

### Person using the stick

1. Create an account and choose **Use my smart stick**.
2. The app creates `patients/{yourFirebaseUid}`.
3. Under **Connect someone you trust**, create a private 8-digit pairing code.
4. The code expires after 10 minutes and can be used once. Speak or copy it and share it only with the person you authorize.

### Caregiver

1. Create an account and choose **Support someone I care about**.
2. Enter the code the patient shared.
3. The accounts link, and the caregiver can view the shared patient location and alert records.

A patient can link at most two caregivers. A caregiver account can connect to one patient at a time in this version. A caregiver role alone does not grant access.

## Live caregiver location sharing

In the patient app, open **Connections → Share my location**. The user chooses either app-open-only updates or background sharing. Background mode requests Android background location and uses a foreground location service with a persistent notification while enabled. Turning sharing off cancels the location stream. Force-stopping the app, rebooting, revoking permission, losing GPS/network, Android battery policy or Firestore errors can stop uploads; caregivers must treat timestamps as important and not assume a last known location is live.

## In-app map and navigation

The map and route preview are rendered inside BlindStick Companion using the open-source Flutter map client and OpenStreetMap-derived services. Patient navigation and the caregiver's shared-location action open this in-app view rather than switching to Google Maps.

- Map tiles: [OpenStreetMap Tile Usage Policy](https://operations.osmfoundation.org/policies/tiles/). Visible attribution must remain on the map. The official tile server is community funded, best-effort, and may block abusive or excessive usage.
- Destination search: [Nominatim Usage Policy](https://operations.osmfoundation.org/policies/nominatim/). The app requests a search only after the user taps Search; it does not autocomplete and caches repeated searches during the app session. Public Nominatim limits apply across all users of the app, so this is only suitable for low-volume prototype use. The **Accessibility & settings → Map services (advanced)** section lets the developer switch the tile, geocoder, and foot-router endpoints without releasing an app update. Before use at larger scale, switch to a self-hosted or appropriately licensed service and ensure the deployment meets the new provider's terms.
- Walking directions: the public [OpenStreetMap routing service](https://routing.openstreetmap.de/). This is a community service with no uptime or latency guarantee. Access and policy may change.

The navigation screen provides a route preview, written turn steps, spoken distance-to-maneuver guidance, phone haptic cues near turns, GPS-quality warnings, and a basic route-deviation warning based on phone GPS. If a deviation is suspected, turn prompts pause; the user must stop somewhere safe and manually recalculate the route. It does **not** promise reliable automatic rerouting, safe crossings, or accurate footpaths. GPS, network availability and public map services can fail. **Do not rely on this prototype as the sole mobility aid.** It has not been validated with blind/low-vision users or physically tested on real walking routes; use supervised testing before any field use.

On Android, starting spoken directions asks whether to enable background guidance. If the user allows it, the app uses Geolocator's foreground location service with a persistent notification while this route is active. If background permission is declined, the app gives foreground-only guidance and instructs the user to keep the app open and screen on. Leaving the navigation screen stops its location stream; stop or finish the route before leaving.

## SOS behavior without paid backend

When the patient taps SOS, the app attempts to save an alert record to Firestore. When the caregiver app is open and connected, its Firestore listener can show the alert. This is not the same as a background push notification and does not mean the caregiver has seen it.

After a successful save, **Share by SMS** opens the device's SMS composer with a help message and the current coordinates if available. The patient must select a contact and send the message. If the person cannot do that safely, use their established emergency-contact method. The app does not call emergency services and cannot confirm that help has been dispatched.

Firebase Cloud Messaging itself has a no-cost tier, but sending notifications requires a trusted server or sender. Cloud Functions deployment is intentionally omitted because this project requires a no-billing setup.

## BLE and ESP32-CAM status

BLE service UUID: `7b6e0001-7d9a-4b5c-8f4d-6e9a0b000001`

- Telemetry Notify: `7b6e0002-7d9a-4b5c-8f4d-6e9a0b000001`
- Command Write: `7b6e0003-7d9a-4b5c-8f4d-6e9a0b000001`

Firmware path: `firmware/esp32_cam/esp32_cam_ble_bridge.ino`.

The firmware advertises BLE, creates a password-protected `BlindStick-Camera` Wi-Fi AP, serves `/status` and JPEG frames from `/capture`, reads an optional HC-SR04-style ultrasonic sensor, reports `range_sensor_status` as `fresh` or `unavailable`, and provides a driver output for a vibration motor. The phone warns if BLE telemetry or fresh range data stops, rather than treating missing measurements as a clear path. Camera obstacle cues use the newest fresh ultrasonic reading as supporting context, but do not claim that the distance value belongs to the particular detected object. When a camera object is estimated on the left/right/center of the image, the single motor can use one/two/three short pulse counts for approximate direction and longer pulses for urgency; this code needs training and physical testing. The Android app downloads and runs two on-device models: quantized SSD MobileNet V1 COCO for common objects/person count and an MIT-licensed YOLO26n seven-class model that distinguishes `human_red`/`human_green` pedestrian indications from `vehicle_red`/`vehicle_green` signals. The app uses temporal confirmation and a red-baseline rule before describing a green pedestrian-signal estimate; it still never instructs a user to cross. All outputs remain **experimental predictions**, not certified safety outputs. Battery monitoring is absent, and the physical board, sensor, motor driver and app have not been validated together.

### Camera/AI setup

1. With the phone on normal internet, open **Home → Device readiness** and tap **Prepare on-device AI model**. The app downloads two models once into private app storage: quantized COCO SSD MobileNet for general objects and a 320×320 YOLO26n seven-class pedestrian/vehicle signal detector. The app verifies the downloaded pedestrian-model SHA-256 against `THIRD_PARTY_NOTICES.md`. No per-frame cloud inference is used.
2. Connect the phone to the Wi-Fi network **BlindStick-Camera**. The firmware's development password is `StickAssist#26`; change it before sharing the device.
3. Return to BlindStick Companion, pair/connect over Bluetooth, and start assistance. The app fetches JPEG frames from `http://192.168.4.1/capture` and runs inference on the phone. Some phones may say the camera AP has no internet; local camera traffic can still work, but public map search/routing may lose internet access.
4. The default firmware wiring assumes HC-SR04 TRIG on GPIO13, ECHO on GPIO14 through a suitable 5V-to-3.3V divider/level shifter, and a motor driver on GPIO2. Do not connect a motor directly to the GPIO. See `firmware/esp32_cam/README.md` before wiring; GPIO2 is a boot-strapping pin and the microSD pins are repurposed.

**Important:** The dedicated signal model can predict `human_red` or `human_green` separately from vehicle lights, but its predictions can still be wrong due to camera angle, occlusion, glare, distance, weather, flicker, or domain mismatch. The app requires repeated frames and a red baseline before it reports a possible green state, and resets that baseline if the signal disappears. It still never tells the user to cross. Confirm with an audible/tactile crossing signal and established mobility methods. See `THIRD_PARTY_NOTICES.md` for model attribution and checksum.

See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) for the MIT notice, model source, expected input/output, pinned SHA-256 and limitations.

## Run the app

```powershell
git pull origin main
flutter clean
flutter pub get
flutter analyze
flutter run
```

To build a release APK:

```powershell
flutter build apk --release
```

GitHub Actions checks Dart analysis and Android buildability. CI cannot verify GPS accuracy, map server availability, BLE security, physical sensors, TTS accessibility for individual users, or emergency-message delivery. Conduct supervised accessibility and safety tests before any real-world use.

## Data security notes

Firestore rules restrict user profile access, patient location and alert reads, one-time pairing codes, and caregiver pairing. Test with the patient account, linked caregiver account(s), and an unrelated account. Keep Firebase console/admin access restricted because project administrators can access data through privileged tools. BLE bonding and radio-level owner authorization are not yet implemented.
