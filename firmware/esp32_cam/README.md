# ESP32-CAM firmware and wiring

This folder targets the **AI Thinker ESP32-CAM-style board shown in the project photo**. Confirm the board revision and camera sensor marking before flashing.

## What the starter firmware does

- Initializes the OV2640-compatible camera using AI Thinker pin assignments.
- Advertises the BLE GATT service and characteristic UUIDs used by the Flutter app.
- Accepts `hello`, `start`, `stop`, and `vibrate` BLE commands.
- Captures a camera frame while assistance is enabled.
- Runs a password-protected Wi-Fi AP named BlindStick-Camera and serves /status plus one JPEG frame from /capture while assistance is active.
- Can read an optional HC-SR04 ultrasonic sensor and publish both `range_sensor_status` (`fresh` / `unavailable`) and `distance_cm` over BLE.
- Drives an optional vibration motor through a transistor/MOSFET driver for local distance alerts, including if BLE disconnects after assistance has started. Close obstacles use longer/faster pulses; the wider caution range uses shorter/slower pulses.
- Object detection, people-count/crowd estimate, and traffic-lamp colour estimate run locally on the Android phone from camera JPEGs; no paid cloud inference API is used.

## What it does not do yet

The ESP32 itself does not run AI; it supplies camera frames and sensor readings while Android performs inference. Both models are now integrated in app source, but the complete hardware/software chain has not been physically tested on this board. The board photo alone cannot confirm an HC-SR04 module or vibration driver is fitted. Battery monitoring remains absent.

## Initial programming (board has no USB port)

For the common AI Thinker ESP32-CAM, use a USB-to-TTL serial adapter with 3.3V UART logic:

| Adapter / board | Connection |
|---|---|
| Adapter TX | U0R / GPIO3 |
| Adapter RX | U0T / GPIO1 |
| Adapter GND | GND |
| Stable regulated supply | 5V pin, sized for camera current |
| GPIO0 | Connect to GND only while entering serial download mode |

Power down before changing wiring. Start download mode by holding GPIO0 low while resetting/powering the board; flash from Arduino IDE, then disconnect GPIO0 from GND and reset to run. Adapter TX/RX labels refer to signal direction (TX goes to board RX). Do not connect 5V to the UART pins. Some adapters expose a 3.3V output that cannot supply enough current for the camera; use a suitable stable supply with common ground.

Normal operation is wireless over BLE; the serial adapter is only for programming/debugging.

## Camera pin use and sensor warning

The camera occupies many GPIOs. Do **not** assume arbitrary pins are free for an ultrasonic sensor or motor. Confirm the exact board pinout and avoid camera pins, boot-strapping pins, flash/PSRAM pins, and input-only pins for outputs. A vibration motor requires a transistor/MOSFET driver and appropriate flyback protection if applicable; never connect a motor directly to an ESP32 GPIO. An ultrasonic module with a 5V ECHO output needs level shifting/dividing before a 3.3V ESP32 input.

## Protocol

See `../../docs/ble_protocol.json`. Telemetry is newline-terminated UTF-8 JSON. The Android app prepares both on-device models on the Home screen. Missing models, unreachable camera frames or absent sensor telemetry must be reported as unavailable rather than converted to guessed detections.

## Build

Install Arduino IDE or PlatformIO, Espressif ESP32 board support, and the ArduinoJson library. Select the exact ESP32-CAM board profile and confirm the ESP32 core version: the camera config fields vary across core versions. The source successfully compiles in the repository's Arduino CLI ESP32-CAM CI check. It has not been flashed to or hardware-tested on the physical board in this environment.

## Camera Wi-Fi setup for the Android app

When the board boots, it advertises:

- SSID: BlindStick-Camera
- Default password: StickAssist#26
- Camera/status base URL: http://192.168.4.1
- Status: GET /status
- JPEG frame: GET /capture

The app first downloads the quantized SSD MobileNet COCO model from the official TensorFlow model archive while the phone has internet access. The model is cached in app-private storage. Then connect the phone to the camera AP in Android Wi-Fi settings, return to BlindStick Companion, connect BLE, and start assistance. The camera AP has no internet access; Android may display “No internet”. The local camera connection can still work. Online map search/routing may not work while connected to the AP unless the phone keeps mobile data active.

Security: the password above is a development default. Change it in firmware before sharing the hardware outside the test group. The current AP and HTTP endpoint are a local prototype and do not provide per-user camera authentication or encrypted image transport.

## Sensor and motor wiring used by this starter

Leave the microSD card unused because its pins are shared with the sensor inputs.

| Part | ESP32-CAM pin | Wiring notes |
|---|---:|---|
| HC-SR04 TRIG | GPIO 13 | ESP32 3.3V output to sensor TRIG |
| HC-SR04 ECHO | GPIO 14 | Do not connect 5V ECHO directly. Use a level shifter or resistor divider to keep the input at 3.3V or less |
| Vibration-driver control | GPIO 2 | Drive only a transistor/MOSFET gate circuit, never the motor directly. Add a 10kΩ pulldown to keep GPIO2 low during boot and use a suitable flyback diode for an inductive motor |

Use a stable power supply sized for the ESP32-CAM, camera, and sensor, with a shared ground. This pin mapping is a starter assumption and must be checked against the exact board revision. GPIO2 is a boot-strapping pin, so incorrect external circuitry can prevent startup. If the board fails to boot, disconnect the driver input and retest before changing pins.

The firmware provides local vibration for fresh distance measurements below the caution/stop thresholds. Urgent close obstacles pulse for 300 ms approximately every 450 ms; caution-range obstacles pulse for 100 ms approximately every 1400 ms. These defaults are only starting values for bench tuning, not validated safety thresholds. Unknown, invalid, timed-out, or stale measurements are reported as unavailable, and the phone speaks a warning rather than treating them as a clear path. The phone also provides haptic cues for camera detections and turn proximity when BLE assistance is connected.

## On-device vision model and limitations

The Android app downloads two models while the phone has internet access:

1. Quantized SSD MobileNet V1 COCO, downloaded from TensorFlow's model archive, detects common objects and people.
2. The MIT-licensed YOLO26n seven-class TFLite model from [VIA-Safe-Crosswalk](https://github.com/25-p-project-team-6/VIA-Safe-Crosswalk) distinguishes `human_red`, `human_green`, `vehicle_red`, and `vehicle_green`. The app pins the expected SHA-256 in Android code and verifies it after download. See the repository's `THIRD_PARTY_NOTICES.md` for attribution.

Camera frames are fetched over the local Wi-Fi AP and stay on the phone. Crowd level is a count-based estimate of people detected in one frame. The signal model is experimental: it needs further validation on the actual ESP32-CAM image stream and Indian crossings. The app requires repeated predictions and a red baseline before reporting a possible green pedestrian signal; loss of signal visibility clears that baseline. It never tells the user to cross based on inference. A `human_green` prediction is not proof the crossing is safe. Users must confirm with established audible/tactile crossing cues and mobility practices. This prototype must not be the sole mobility aid.
