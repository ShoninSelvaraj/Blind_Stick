# Saathi — accessible blind-stick companion

Flutter Android app for the Saathi blind-stick prototype. It uses Firebase Email/Password Authentication, Cloud Firestore, BLE, GPS-based Maps hand-off, spoken and haptic feedback, optional location sharing, and SOS alerts.

## Respectful onboarding

Registration asks **what you want to do with Saathi**, not how to describe yourself:

- **Use my Saathi stick** — navigation, device status, safety alerts and SOS.
- **Support someone I care about** — view updates only after the other person chooses to share access.

The app uses clear wording, TalkBack-compatible controls, spoken pairing-code output, large primary actions, high contrast, and a saved text-size control (100–160%). Voice guidance can be turned off separately.

## Firebase configuration

Project: `blindstick001`, Android package: `com.vimal.blindstick`. The Firebase Android config is `android/app/google-services.json`.

In Firebase Console, enable **Authentication → Sign-in method → Email/Password** and create/enable your Firestore database. Deploy the rules and server function when you're ready:

```bash
npm install -g firebase-tools
firebase login
firebase use blindstick001
firebase deploy --only firestore:rules,functions
```

The deployment needs an eligible Firebase/Google Cloud billing setup for Cloud Functions. Confirm that the active Firebase CLI account and target project are correct before deployment.

To build/run the mobile app:

```bash
git pull origin main
flutter clean
flutter pub get
flutter analyze
flutter run
flutter build apk --release
```

The repository's GitHub Actions workflow runs Dart analysis and a debug Android build on pushes to `main`.

## Role and pairing flow

Users choose their app role during registration. This choice changes the experience; it is not identity verification.

### Person using the stick
1. Create an account and choose **Use my Saathi stick**.
2. The app creates `patients/{yourFirebaseUid}`.
3. Under **Connect someone you trust**, create a pairing code. It is 8 digits, expires after 10 minutes, can be used once, and can be copied or spoken.
4. Share the code only with someone you want to authorize.

### Person supporting someone
1. Create an account and choose **Support someone I care about**.
2. Enter the pairing code the other person shared.
3. The app atomically redeems it and links the accounts.
4. The caregiver screen streams the linked patient's location, device status and alerts from Firestore.

Each patient can have at most **two linked caregivers**. This version lets a caregiver account connect to one patient at a time. A patient controls whom to pair with by deciding whether to share the code; an account that merely selects the caregiver role cannot read anyone's data.

## Firestore data and security

- `users/{uid}`: personal profile and self-selected role; users can read only their own profile.
- `users/{uid}/fcmTokens/primary`: that signed-in user's FCM token; only that account can read/write it.
- `patients/{patientUid}`: patient owner UID, display name, caregiver UID list, latest shared location and device status.
- `patients/{patientUid}/locations/{locationId}`: location history. Only the patient can write; patient and linked caregivers can read.
- `patients/{patientUid}/alerts/{alertId}`: SOS and system events. Only the patient can create; patient and linked caregivers can read.
- `pairingCodes/{code}`: single-use, expiring codes; listing is denied.
- `pairingClaims/{caregiverUid}`: one active pairing claim per caregiver; accessible only to that caregiver.

The deployed `firestore.rules` limits the caregiver list to two and ties reads to Auth UIDs. Test the rules with a patient, two linked caregivers, and an unrelated third account before field use. Firebase project owners/admins can still access data through privileged administrative tools, so restrict console/admin access.

## Navigation

The app opens Google Maps walking navigation immediately with the destination, using the native Maps navigation URI and falling back to a web directions link if needed. Maps itself handles live GPS, turn-by-turn voice guidance and rerouting. This avoids waiting for an additional app-side location fix before opening directions, but **zero lag cannot be guaranteed**: GPS availability, network quality, phone performance and Maps availability still matter. Download offline maps in Google Maps ahead of time for areas with unreliable connectivity.

## Location sharing and SOS alerts

Location sharing is opt-in. While Saathi remains open, it uploads a GPS point about every 30 seconds when location permission and Firestore access are available. It is not a guaranteed background tracking service.

An SOS is first saved in `patients/{patientUid}/alerts`. If the Cloud Function has been deployed and the caregiver has a valid FCM token, the function attempts a push notification for the linked caregivers only. The alert records delivery-attempt status/counts. FCM cannot guarantee that a phone receives the message or that the person sees it; notification permissions, battery restrictions and connectivity matter. The patient is warned to use their usual emergency contact method as well.

To deploy notifications, use the root `firebase.json` and `functions/index.js`:

```bash
firebase deploy --only firestore:rules,functions
```

Check `functions/README.md` for deployment notes. Do not treat an accepted Firestore write as proof an emergency responder was contacted.

## BLE and the photographed ESP32-CAM board

BLE service UUID: `7b6e0001-7d9a-4b5c-8f4d-6e9a0b000001`

- Telemetry Notify: `7b6e0002-7d9a-4b5c-8f4d-6e9a0b000001`
- Command Write: `7b6e0003-7d9a-4b5c-8f4d-6e9a0b000001`

The repository includes a starter camera/BLE bridge in `firmware/esp32_cam/esp32_cam_ble_bridge.ino`. It initializes the camera, captures frames and sends honest device status. It does **not** contain a trained model for object detection, traffic-light recognition or crowd classification. The app displays that status instead of inventing predictions.

Ultrasonic distance, battery telemetry and a physical vibration motor also need the actual sensors, confirmed pin assignments and driver circuit. The image appears to show an ESP32-CAM-style board with no USB port; initial programming typically needs a USB-to-TTL adapter. Follow `firmware/esp32_cam/README.md` and confirm the exact board revision before wiring. This project has not been physically tested against your hardware.

## Verification boundary

GitHub Actions checks that Dart analysis is clean and the Android debug app builds. Those automated checks do not verify BLE pairing, GPS accuracy, physical sensors, camera AI, notification delivery, or accessibility with real users. The stick still needs BLE bonding/owner authorization; Firestore rules do not protect the Bluetooth radio itself.

Saathi is a prototype companion, not a certified mobility aid. Do not use it as the only means of obstacle avoidance, road-crossing decisions, or emergency response before complete physical and supervised safety testing.
