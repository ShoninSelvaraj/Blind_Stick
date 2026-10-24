# BlindStick device/app interface contract

This document describes the interfaces actually implemented in the current firmware and Flutter app. It is intentionally explicit about unsupported sensors so that missing hardware is never represented as a working sensor.

## Implemented hardware path

| Capability | Physical interface | Firmware output | App handling |
|---|---|---|---|
| Obstacle range | HC-SR04-style TRIG GPIO13 / ECHO GPIO14 | `range_sensor_status` and, only when valid/fresh, `distance_cm` | Accepts 2–400 cm; clears invalid/missing/stale readings; missing range is not a clear path |
| Camera | AI Thinker ESP32-CAM camera pins / camera driver | `camera_ready`, `camera_frame_available`, `camera_endpoint` | Fetches JPEG from the local camera AP; on-device models run on Android |
| Vibration motor | GPIO2 control to external transistor/MOSFET driver | Local stop/caution patterns; accepts app `vibrate` command | App can request a short pulse; device-local range warning continues if BLE disconnects after assistance was enabled |
| Battery monitor | **Not wired or implemented** | `battery_status: unavailable`; no percentage is emitted | Battery percentage remains null/unavailable; never estimate it |
| Other sensors | **Not defined in current firmware** | No telemetry fields are emitted | Do not invent readings or treat absent fields as a sensor failure that means safe |

Confirm the actual board revision and sensor modules before wiring. HC-SR04 ECHO is commonly 5 V and must be level-shifted to 3.3 V or less. GPIO2 is a boot-strapping pin. Never drive a motor directly from an ESP32 GPIO. Do not use the microSD socket while GPIO13/14 are assigned to the ultrasonic sensor.

## BLE contract

- Service UUID: `7b6e0001-7d9a-4b5c-8f4d-6e9a0b000001`
- Telemetry notify UUID: `7b6e0002-7d9a-4b5c-8f4d-6e9a0b000001`
- Command write UUID: `7b6e0003-7d9a-4b5c-8f4d-6e9a0b000001`
- Protocol version: `1`
- Telemetry: newline-terminated UTF-8 JSON. The app and firmware request/support an ATT MTU of 384 so the JSON notification is not cut at the default 20-byte payload.
- Commands: `hello`, `start`, `stop`, `vibrate`. The app only accepts telemetry with protocol version 1 and device ID `blindstick_companion-esp32cam`.

Example telemetry when range is valid:

```json
{"protocol":1,"device":"blindstick_companion-esp32cam","assistance":true,"camera_ready":true,"camera_frame_available":false,"detection_status":"runs_on_android_phone","camera_ap_ssid":"BlindStick-Camera","camera_endpoint":"http://192.168.4.1","battery_status":"unavailable","range_sensor_status":"fresh","distance_cm":42}
```

When range is invalid or stale, the firmware omits `distance_cm` and sends `range_sensor_status: "unavailable"`. The app clears the last distance and warns rather than carrying forward a stale value.

## Bench test sequence for the physical stick

1. Flash the matching firmware and verify the board advertises the service UUID.
2. Connect from the Android app; confirm telemetry packets continue arriving and the device identity/protocol check passes.
3. Start assistance; confirm the next telemetry reports `assistance: true`. Stop assistance and confirm `false`.
4. Measure known distances from 2–400 cm; compare displayed values. Remove/disconnect the sensor and confirm the app reports unavailable, never a clear path.
5. Request a vibration pulse; verify only the driver circuit is energized. Check local stop/caution pulses with BLE disconnected while assistance is active.
6. Request a camera frame; confirm `/status` works and `/capture` returns a JPEG while assistance is active. Confirm model inference occurs on the phone.
7. Reboot with the motor driver attached and verify the board still boots reliably.
8. Do not mark battery monitoring complete until a voltage measurement circuit, safe input range, battery chemistry, and calibration are implemented and tested.

Software tests and firmware compilation cannot replace these physical measurements. This prototype is not a certified mobility aid and must not be the user's only obstacle-avoidance or road-crossing method.
