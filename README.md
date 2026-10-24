# Saathi — Blind Stick Companion

Flutter Android app for a patient and their authorized caregiver, using Firebase Authentication + Cloud Firestore and a BLE connection to the stick.

## Firebase configuration

The Android Firebase client configuration is in `android/app/google-services.json` for project `blindstick001` and Android package `com.vimal.blindstick`. Firebase Email/Password sign-in must be enabled in Firebase Console → Authentication → Sign-in method.

After pulling changes, run:

```bash
flutter clean
flutter pub get
flutter analyze
flutter run
```

The project uses Firebase native initialization through the Google Services Gradle plugin. If you change the Android application ID, register that exact package in Firebase and replace `google-services.json`.

## Roles, pairing and access limit

**Do not let the client choose its own role.** New registrations create `users/{uid}` with `role: "pending"`. They cannot access the patient or caregiver screens until an administrator assigns a role in Firebase Console.

Firestore collections:

- `users/{uid}`: `uid`, `email`, `displayName`, `role` (`pending`, `patient`, or `caregiver`). User documents are readable only by that user; client writes after initial registration are denied.
- `patients/{patientUid}`: `ownerUid` must equal the patient's Firebase Auth UID; `caregiverUids` is an array of approved caregiver Auth UIDs. The rules permit a maximum of **two caregivers** at patient-record creation and block client-side changes to this list.
- `patients/{patientUid}/locations/{locationId}`: patient location history; only the patient can write, and only the patient or linked caregivers can read.
- `patients/{patientUid}/alerts/{alertId}`: SOS/device alerts; only the patient can create, and only the patient or linked caregivers can read.

### One-time administrator setup

1. In Firebase Console → Authentication, confirm Email/Password is enabled.
2. Deploy `firestore.rules` to the Firestore database. Do not leave Firestore in test mode.
3. Create a patient and caregiver account from the app. Copy each account's UID from Firebase Authentication.
4. In Firestore Console, edit `users/{patientUid}` and change `role` from `pending` to `patient`. Edit `users/{caregiverUid}` and set `role` to `caregiver`. These role changes are admin-only.
5. Sign in once as the patient so the app creates `patients/{patientUid}` with `ownerUid` and an empty `caregiverUids` list. If it already exists, do not recreate it.
6. In `patients/{patientUid}`, set `caregiverUids` to an array containing the approved caregiver UID(s), up to two. This pairing change is admin-managed. Give the caregiver the patient UID to enter in the caregiver screen.
7. Use the Firebase Rules Playground / Emulator Suite to verify that an unrelated account cannot read the patient, location or alert documents.

The app cannot enforce a limit on Firebase project admins; administrators can always change console data. The two-caregiver limit is a client-access policy enforced by the deployed Firestore rules for normal app clients.

## What the app currently does

- Firebase email/password registration, sign-in, sign-out and password reset.
- Newly registered accounts remain pending until an administrator assigns a role.
- Patient location and SOS alert records are stored in Firestore.
- Caregiver screen reads a patient record and latest alert only when Firestore rules authorize the UID.
- Caregiver count policy: up to two linked caregiver UIDs per patient record.
- BLE scan/connect using the Saathi GATT UUIDs; no fabricated sensor values.
- Walking directions hand off immediately to Google Maps using the native navigation URI, with a web directions fallback. Google Maps obtains the current location and supplies turn-by-turn guidance; the app does not calculate a route itself.
- Spoken/haptic feedback from actual telemetry packets.

## Navigation expectations

The app launches an external maps app rather than running its own routing engine. This keeps routing and turn-by-turn recalculation in Google Maps, avoiding a custom route engine that could lag or become stale. Actual reliability still depends on device GPS, Maps availability, permissions and connectivity. Offline maps must be downloaded in Maps in advance if internet may be unavailable. No software can guarantee zero latency in every GPS/network environment.

## BLE protocol

- Service UUID: `7b6e0001-7d9a-4b5c-8f4d-6e9a0b000001`
- Telemetry Notify: `7b6e0002-7d9a-4b5c-8f4d-6e9a0b000001`
- Command Write: `7b6e0003-7d9a-4b5c-8f4d-6e9a0b000001`

The ESP32 firmware must advertise this service and send newline-delimited JSON. The repository starter firmware captures camera frames but does not yet contain a trained object, traffic-light or crowd-detection model. Ultrasonic distance, battery telemetry and vibration feedback also require the corresponding sensors/driver and confirmed wiring.

**Important BLE security boundary:** Firestore rules protect cloud data, not radio access. The current BLE starter does not yet implement authenticated/bonded device pairing or an owner allowlist. Until that firmware security layer is implemented and physically tested, another compatible nearby BLE client may be able to connect to the stick. Do not treat the Firestore caregiver limit as a BLE-device access limit.

## SOS delivery limitation

SOS is written to Firestore and becomes visible to an authorized caregiver when the caregiver screen refreshes. Firebase Email/Password and Firestore alone do not send push notifications. FCM/APNs setup plus a trusted server/Cloud Function is still required for background push alerts and delivery receipts. The app tells the user when it cannot save the alert; a successful Firestore write does not prove the caregiver has seen it.

## Safety and privacy

Location sharing is opt-in and currently runs while the patient screen is active; it is not a guaranteed background tracking service. Use consent, a data-retention policy, verified authorization rules, and real-device tests. This is not a certified mobility aid and must not be the sole source of obstacle or crossing safety.
