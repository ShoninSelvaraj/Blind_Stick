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
| Emergency alert | Save SOS in Firestore and optionally open the phone's SMS composer | SMS is **not sent automatically**; the user must select a recipient and tap send. Carrier SMS costs may apply |
| Background push notification | Not included in zero-billing mode | Sending FCM push messages requires a trusted sender/server. No automatic background push is claimed |
| Object / traffic-light / crowd AI | Not yet implemented in this prototype | Current ESP32-CAM firmware is a camera/BLE bridge, not a trained detection model |

**Zero budget means no required paid service in this design; it does not mean unlimited capacity or guaranteed availability.** Do not use public community servers for high-volume or mission-critical navigation. If the project grows, self-host OpenStreetMap-derived services on hardware you already control, or use a provider only after checking its terms and price.

## Accessibility

- Register by choosing the task: **Use my smart stick** or **Support someone I care about**. This is an app role, not identity or disability verification.
- After sign-in, the patient interface is separated into four named task areas: **Home**, **Navigate**, **Connections**, and **Help & SOS**. The app bar keeps accessibility settings and sign-out easy to find.
- Primary actions have clear text labels and large touch targets. Tab changes are announced through speech, and standard Flutter controls expose labels to TalkBack.
- Home includes a device-readiness section that explicitly shows missing sensor/model capabilities rather than pretending they work.
- Settings offers spoken guidance, text scaling (100–160%) that respects Android text scaling, and high-contrast black/white colors.
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

The current firmware initializes the camera, captures frames and reports device status. It **does not** include a trained model for object detection, traffic-light recognition or crowd classification. Ultrasonic distance, battery telemetry and physical vibration also require confirmed sensors, wiring and firmware. No results should be treated as real unless the connected hardware transmits them. The board and app have not been physically validated together.

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
