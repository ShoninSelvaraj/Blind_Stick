# ESP32-CAM firmware and wiring

This folder targets the **AI Thinker ESP32-CAM-style board shown in the project photo**. Confirm the board revision and camera sensor marking before flashing.

## What the starter firmware does

- Initializes the OV2640-compatible camera using AI Thinker pin assignments.
- Advertises the BLE GATT service and characteristic UUIDs used by the Flutter app.
- Accepts `hello`, `start`, and `stop` commands.
- Captures a camera frame while assistance is enabled.
- Reports honest device/camera status without inventing object, traffic, crowd, distance, or battery data.

## What it does not do yet

It is not the finished AI firmware. The repository does not contain a trained object detector or traffic-light/crowd model, and the board photo alone cannot tell us which ultrasonic sensor, battery monitor, vibration motor driver, or wiring has been fitted. Those features must not be represented as working until their hardware/model is integrated and tested.

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

See `../docs/ble_protocol.json`. Telemetry is newline-terminated UTF-8 JSON. The app should show “AI model not installed” rather than claiming detections while the detector is absent.

## Build

Install Arduino IDE or PlatformIO, Espressif ESP32 board support, and the ArduinoJson library. Select the exact ESP32-CAM board profile and confirm the ESP32 core version: the camera config fields vary across core versions. This firmware has not been compiled or flashed on the physical board in this environment.
