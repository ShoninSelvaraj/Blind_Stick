# Saathi — Blind Stick Companion (Flutter)

An accessible Android companion app for the AI-powered blind-stick project. This version removes the simulated sensor generator and uses real BLE telemetry when a compatible stick is connected. It also includes GPS-based hand-off to real walking navigation, spoken safety alerts, SOS/API integration, caregiver status/location retrieval, and configurable backend settings.

## Demo sign-in

- Patient: `patient` / `1234`
- Caregiver: `caregiver` / `1234`

These are hard-coded prototype credentials only. They are not secure and must be replaced with your authentication provider before real deployment.

## Run / build

Install Flutter stable, Android Studio and the Android SDK. From this folder:

```bash
flutter pub get
flutter analyze
flutter run
flutter build apk --release
```

APK output: `build/app/outputs/flutter-apk/app-release.apk`.

The current environment used to prepare this source did not have Flutter/Dart installed, so a compiled APK or successful `flutter analyze` result is **not** claimed. Run the commands above on a Flutter workstation and resolve any SDK-specific warnings before field testing.

## Features implemented in the app

- Patient and caregiver role-specific screens, with hard-coded demo sign-in.
- Large, high-contrast controls and accessible plain-language status.
- Real BLE scan/connect/disconnect using the Saathi GATT service UUIDs below; the app does not generate fake distance, camera, battery or traffic data.
- JSON telemetry parsing for ultrasonic distance, object label, battery, traffic-crossing cue and crowd level.
- Start/pause commands sent to the stick, if firmware implements those commands.
- Spoken safety cues and haptic feedback when incoming telemetry indicates an urgent obstacle, caution distance, stop signal or high crowd density.
- Current phone GPS position with runtime permission handling.
- Destination input and hand-off to Google Maps walking navigation. Turn-by-turn route computation/voice navigation is supplied by Maps, not reimplemented inside this app. An installed/available Maps handler and internet may be needed.
- Consent-controlled location sharing attempts every 30 seconds while the patient screen is open. This is foreground sharing, not a guaranteed background service.
- SOS confirmation and REST submission with current coordinates when available.
- Caregiver screen retrieves patient status, last location and recent alerts from the configured backend. It displays no fabricated location or alert data.
- Persistent backend URL/token and voice-guidance preference.

## Hardware communication contract (must match firmware)

The app scans for a BLE peripheral advertising this service:

- Service UUID: `7b6e0001-7d9a-4b5c-8f4d-6e9a0b000001`
- Telemetry characteristic (Notify): `7b6e0002-7d9a-4b5c-8f4d-6e9a0b000001`
- Command characteristic (Write): `7b6e0003-7d9a-4b5c-8f4d-6e9a0b000001`

Telemetry must be UTF-8 JSON, newline-delimited. Example:

```json
{"distance_cm":42,"object":"person ahead","battery":78,"traffic_walk":false,"crowd":"medium"}
```

Supported telemetry fields:

- `distance_cm` (number; ultrasonic range in cm)
- `object` or `detected_object` or `label` (string from camera inference)
- `battery` or `battery_percent` (number)
- `traffic_walk` (boolean; only emit when a validated traffic-light model can determine a safe crossing cue)
- `crowd` (string such as `low`, `medium`, `high`)

Commands are newline-delimited JSON written to the command characteristic:

```json
{"cmd":"hello","protocol":1}
{"cmd":"start"}
{"cmd":"stop"}
```

**No firmware has been provided and no AI model has been trained/selected.** The app-side BLE client is implemented against the contract above, but it cannot connect until your ESP32 firmware advertises these UUIDs and sends the specified packet format. The app cannot make an ESP32-CAM detect objects, traffic signals or crowd density without suitable firmware/model output. Traffic-light cues are safety-sensitive; do not use them as a substitute for checking the crossing and obeying local signals.

### Hardware notes

- A wireless BLE link does not require a USB-C port during normal use. Initial programming/debugging still requires a supported programming path for the exact board (for example its serial programming pins/adapter or onboard USB if present).
- Classic ESP32-CAM boards have constrained RAM and GPIO availability. Camera inference model, camera pins, ultrasonic pins, battery monitoring and any vibration motor driver must be selected for the exact board/revision before writing deployable firmware. Do not connect a motor directly to a GPIO.
- The stick itself should provide local obstacle feedback independently of the phone so a phone crash/disconnect does not remove all warnings.

## Backend contract (database intentionally left to you)

Set the API base URL in **Settings → Backend connection**. The app sends JSON and optionally a `Bearer <token>` authorization header. Implement these endpoints on your server and connect them to your own database/auth provider:

### `POST /api/locations`

Request:

```json
{"patient_id":"patient","latitude":12.345,"longitude":76.789,"accuracy_m":8.0,"recorded_at":"2026-10-23T10:00:00Z"}
```

Return any 2xx response when accepted. Persist only with user consent and define a retention policy.

### `POST /api/sos`

Request:

```json
{"patient_id":"patient","message":"Patient requested emergency assistance","latitude":12.345,"longitude":76.789,"created_at":"2026-10-23T10:00:00Z"}
```

Return 2xx only after the server accepts the event. Your backend must actually notify linked caregivers (push/SMS/email according to your setup), record delivery status, and handle retries. A 2xx response from the API only means accepted by the server, not that a caregiver saw the alert.

### `POST /api/events`

Request:

```json
{"patient_id":"patient","type":"sos","detail":"SOS submitted to backend","created_at":"2026-10-23T10:00:00Z"}
```

### `GET /api/patients/{patient_id}/status`

Expected response shape:

```json
{
  "patient_id":"patient",
  "status":"online",
  "last_location":{"latitude":12.345,"longitude":76.789,"recorded_at":"2026-10-23T10:00:00Z"},
  "recent_alerts":[{"type":"sos","created_at":"2026-10-23T10:00:00Z","message":"Help requested"}]
}
```

The caregiver app uses `last_location.latitude`, `last_location.longitude`, and the first item in `recent_alerts`. Protect the endpoint so only the paired/authorized caregiver can read a patient's location and alerts.

### Authentication and pairing

The demo login is local only; the optional bearer token field is a single static token and is **not** a complete authentication system. Before real deployment, implement real sign-in, caregiver/patient pairing, authorization, token refresh/revocation, account recovery, consent, and server-side access checks. Do not ship shared demo credentials or one shared token to production.

## Current boundaries — important

- This project has not been physically tested against your ESP32 because the firmware/board details are not available.
- Object detection, traffic-light recognition, and crowd-density classification are parsed from firmware telemetry; they are not inferred by the Flutter app.
- Navigation launches Google Maps walking directions with the phone's current coordinates. Route calculation and live turn-by-turn guidance are handled by Maps.
- Location sharing only runs while the patient screen remains active; background tracking needs additional Android foreground-service/background-location work and user consent.
- The caregiver dashboard polls the status endpoint every 45 seconds while open; push notifications are not yet integrated into the app. Backend SOS delivery must be implemented and tested separately.
- No database is included, per request. The app contains REST integration and a concrete API contract so the backend/database can be implemented separately.
- This is a prototype, not a certified mobility aid. Never rely on it as the sole means of obstacle detection or crossing safety. Physical testing, intended-user accessibility testing, emergency-delivery testing, privacy/security review and supervised safety validation are required before real-world reliance.
"# Blind_Stick" 
