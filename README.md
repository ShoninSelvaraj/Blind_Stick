# Saathi — accessible blind-stick companion

Flutter Android companion app for the Saathi blind-stick prototype. The app uses Firebase Email/Password Authentication, Cloud Firestore, BLE, Android GPS permissions, spoken feedback and external walking navigation.

## User experience

The registration screen asks what a person wants to do, not whether they are blind:

- **Use my Saathi stick** — navigation, device status, safety alerts and SOS.
- **Support someone I care about** — connect only after the person shares a one-time pairing code.

The app supports TalkBack through standard accessible controls and semantic labels, spoken safety guidance, a text-size setting, high-contrast UI, and large primary actions. There are no shared demo credentials.

## Firebase setup

This project is configured for Firebase project `blindstick001` and Android package `com.vimal.blindstick`. Its client configuration lives at `android/app/google-services.json`.

In Firebase Console:
1. Enable **Authentication → Sign-in method → Email/Password**.
2. Create/enable the Firestore database.
3. Deploy the repository rules (never use open/test rules in production):

```bash
npm install -g firebase-tools
firebase login
firebase deploy --only firestore:rules
```

The included `.firebaserc` targets `blindstick001`. Confirm you are logged into the correct Firebase account before deploying.

Build/run:

```bash
git pull origin main
flutter clean
flutter pub get
flutter analyze
flutter run
```

GitHub Actions runs `flutter analyze` and builds a debug APK on pushes to `main`.

## Account creation and access

Users choose their intended use during account creation. The selected role is written once to `users/{uid}`; client-side role changes are denied. This is appropriate for choosing the app experience, but it is not a strong identity check—never treat the role alone as proof of a person's real-world status.

### Patient / stick owner
On first sign-in, the app creates `patients/{patientUid}` with the patient's Firebase Auth UID as owner. Under **Connect someone you trust**, the patient can generate an eight-digit pairing code. It expires after 10 minutes and can be redeemed once. It is shown on-screen and can be spoken or copied.

### Caregiver
Choose **Support someone I care about** when creating an account, then enter the code the patient shares. The app atomically claims the code and links the caregiver to the patient. The caregiver dashboard subscribes to Firestore for live location/status updates and new alerts while open. Each patient record allows at most **two linked caregivers**. This MVP allows each caregiver account to pair with one patient at a time.

### Where the data lives

- `users/{uid}`: minimal account profile and selected app role; each user can read only their own profile.
- `patients/{patientUid}`: owner UID, display name, caregiver UID list, latest shared location and device status.
- `patients/{patientUid}/locations/{locationId}`: consent-based location history.
- `patients/{patientUid}/alerts/{alertId}`: SOS and device/system events.
- `pairingCodes/{8 digits}`: short-lived, single-use pairing records; individual gets only, no listing.
- `pairingClaims/{caregiverUid}`: the caregiver's own link record, used by the app to find their linked patient.

### Security properties and limits

- Firestore rules require sign-in; no collection is publicly readable.
- Role is set at account creation and cannot be edited from the app.
- A patient can share only with caregivers who redeem their live code.
- Codes expire, are single-use and are redeemed in an atomic Firestore transaction.
- Patient/caregiver access to patient documents, locations and alerts is checked by UID; the cap is two linked caregivers.
- Only the patient can write location and SOS events for their patient record. Caregiver access is read-only.
- Users cannot list pairing codes or pairing claims.
- Firestore rules do not secure BLE itself. The ESP32 firmware still needs BLE bonding/authentication or another device allowlist before preventing arbitrary nearby Bluetooth clients from connecting.

Review `firestore.rules` before deployment and test access with two linked accounts plus a third unrelated account. Firebase project owners/admins can bypass client rules through trusted Admin SDKs/console access, so restrict project admin access carefully.

## Navigation

The app hands off immediately to native Google Maps walking navigation (`google.navigation`), then falls back to the web directions URL if needed. Maps performs live GPS updates, route calculation, rerouting and turn-by-turn voice guidance. This avoids blocking the app on an extra GPS lookup before directions open. Actual latency depends on the phone, GPS signal, Maps availability and network; no app can promise zero lag. Download offline maps in Maps in advance if connectivity may be unreliable.

## BLE and physical hardware

Service UUID: `7b6e0001-7d9a-4b5c-8f4d-6e9a0b000001`

- Telemetry Notify: `7b6e0002-7d9a-4b5c-8f4d-6e9a0b000001`
- Command Write: `7b6e0003-7d9a-4b5c-8f4d-6e9a0b000001`

The app requires newline-delimited UTF-8 JSON telemetry and will not fabricate distance/object/traffic/crowd results. The repository includes a starter ESP32-CAM BLE bridge, but no trained computer-vision model has been provided. The starter firmware captures camera frames and reports camera/model status; object detection, traffic-light recognition and crowd classification require real model inference. Ultrasonic distance, battery sensing and stick-mounted vibration require corresponding hardware and confirmed wiring. The photographed ESP32-CAM has no built-in USB port; initial programming commonly uses a USB-to-TTL adapter. Follow `firmware/esp32_cam/README.md` and confirm board revision before wiring.

## SOS delivery

SOS is written to Firestore and appears as a live alert in an open, authorized caregiver dashboard. Firebase Authentication + Firestore alone do **not** guarantee a background push notification or emergency dispatch. For unattended notifications, configure Firebase Cloud Messaging and a trusted Cloud Function/server-side delivery provider, including delivery receipts and retries. A saved alert does not mean a caregiver has seen it.

## Safety boundary

Location sharing is opt-in and currently runs while the patient screen is open; it is not a guaranteed background location service. Physical validation, screen-reader testing with intended users, Firestore rules tests, secure BLE pairing, AI-model validation and emergency-notification tests are required before real-world reliance. Saathi is a prototype companion, not a certified mobility aid; do not use it as the sole method for obstacle avoidance or crossing decisions.
