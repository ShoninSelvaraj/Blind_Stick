/*
 * BlindStick Companion — ESP32-CAM BLE bridge
 * Target: AI Thinker ESP32-CAM (classic ESP32), Arduino ESP32 core.
 *
 * IMPORTANT:
 * - This firmware provides BLE telemetry, an ESP32-CAM JPEG endpoint, optional
 *   ultrasonic range measurement and a motor-driver output.
 * - Object detection/crowd estimate and a cautious traffic-lamp colour estimate
 *   run on the Android phone with a downloaded quantized TFLite model. They are
 *   probabilistic prototypes, not safety-certified. Never use this app as the
 *   sole mobility safety aid.
 * - The board photo has no onboard USB connector. Initial flashing requires a
 *   USB-to-TTL adapter connected to 5V, GND, U0R/U0T and GPIO0-to-GND for
 *   download mode. Disconnect GPIO0 from GND and reset for normal boot.
 * - Do not power the camera and motors from a weak USB-TTL adapter. Use a
 *   stable regulated supply and common ground. Never drive a vibration motor
 *   directly from a GPIO.
 *
 * BLE contract: docs/ble_protocol.json
 */
#include <Arduino.h>
#include "esp_camera.h"
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <ArduinoJson.h>
#include <WiFi.h>
#include <WebServer.h>

// AI Thinker ESP32-CAM camera pins
#define PWDN_GPIO_NUM     32
#define RESET_GPIO_NUM    -1
#define XCLK_GPIO_NUM      0
#define SIOD_GPIO_NUM     26
#define SIOC_GPIO_NUM     27
#define Y9_GPIO_NUM       35
#define Y8_GPIO_NUM       34
#define Y7_GPIO_NUM       39
#define Y6_GPIO_NUM       36
#define Y5_GPIO_NUM       21
#define Y4_GPIO_NUM       19
#define Y3_GPIO_NUM       18
#define Y2_GPIO_NUM        5
#define VSYNC_GPIO_NUM    25
#define HREF_GPIO_NUM     23
#define PCLK_GPIO_NUM     22

static const char* SERVICE_UUID = "7b6e0001-7d9a-4b5c-8f4d-6e9a0b000001";
static const char* TELEMETRY_UUID = "7b6e0002-7d9a-4b5c-8f4d-6e9a0b000001";
static const char* COMMAND_UUID = "7b6e0003-7d9a-4b5c-8f4d-6e9a0b000001";

// Local, password-protected camera AP. Connect the phone to this Wi-Fi after
// downloading the on-device model while internet is available.
static const char* CAMERA_AP_SSID = "BlindStick-Camera";
static const char* CAMERA_AP_PASSWORD = "StickAssist#26";

// Optional HC-SR04. Do not use an SD card while these pins are occupied.
static const int ULTRASONIC_TRIG_GPIO = 13; // Shared with microSD D3; not used by this firmware.
static const int ULTRASONIC_ECHO_GPIO = 14; // Shared with microSD CLK; not used by this firmware.
static const int VIBRATION_DRIVER_GPIO = 2; // Drive a transistor/MOSFET gate only; add a 10k pulldown.
static const float STOP_DISTANCE_CM = 35.0f;
static const float CAUTION_DISTANCE_CM = 90.0f;
static const unsigned long SENSOR_PERIOD_MS = 150;
static const unsigned long TELEMETRY_PERIOD_MS = 800;
static const unsigned long MOTOR_PULSE_MS = 220;
static const unsigned long MOTOR_REPEAT_MS = 850;

WebServer cameraServer(80);
float lastDistanceCm = -1.0f;
unsigned long distanceMeasuredAt = 0;
unsigned long lastSensorReadMs = 0;
unsigned long lastMotorPulseMs = 0;
volatile unsigned long requestedVibrationUntilMs = 0;

BLECharacteristic* telemetryCharacteristic = nullptr;
volatile bool clientConnected = false;
volatile bool assistanceEnabled = false;
unsigned long lastTelemetryMs = 0;
unsigned long lastCameraCheckMs = 0;
bool cameraReady = false;
bool cameraFrameAvailable = false;
String lastCommand = "boot";

class ServerCallbacks final : public BLEServerCallbacks {
  void onConnect(BLEServer*) override { clientConnected = true; }
  void onDisconnect(BLEServer* server) override {
    clientConnected = false;
    server->startAdvertising();
  }
};

class CommandCallbacks final : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    String value = characteristic->getValue().c_str();
    value.trim();
    if (value.isEmpty()) return;

    JsonDocument doc;
    if (deserializeJson(doc, value)) return;
    const char* cmd = doc["cmd"] | "";
    lastCommand = cmd;

    if (!strcmp(cmd, "hello")) {
      // The app's handshake is accepted; protocol version is currently 1.
      return;
    }
    if (!strcmp(cmd, "start")) assistanceEnabled = true;
    if (!strcmp(cmd, "stop")) {
      assistanceEnabled = false;
      requestedVibrationUntilMs = 0;
    }
    if (!strcmp(cmd, "vibrate")) {
      int durationMs = doc["duration_ms"] | 180;
      durationMs = constrain(durationMs, 60, 500);
      requestedVibrationUntilMs = millis() + (unsigned long)durationMs;
    }
  }
};

bool initCamera() {
  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_sccb_sda = SIOD_GPIO_NUM;
  config.pin_sccb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;
  config.pixel_format = PIXFORMAT_JPEG;
  config.frame_size = FRAMESIZE_QVGA;
  config.jpeg_quality = 14;
  config.fb_count = psramFound() ? 2 : 1;
  config.grab_mode = CAMERA_GRAB_LATEST;
  config.fb_location = psramFound() ? CAMERA_FB_IN_PSRAM : CAMERA_FB_IN_DRAM;

  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("Camera init failed: 0x%x\n", err);
    return false;
  }
  return true;
}

void publishTelemetry() {
  if (!clientConnected || telemetryCharacteristic == nullptr) return;

  JsonDocument doc;
  doc["protocol"] = 1;
  doc["device"] = "blindstick_companion-esp32cam";
  doc["assistance"] = assistanceEnabled;
  doc["camera_ready"] = cameraReady;
  doc["camera_frame_available"] = cameraFrameAvailable;
  doc["detection_status"] = "runs_on_android_phone";
  doc["camera_ap_ssid"] = CAMERA_AP_SSID;
  doc["camera_endpoint"] = "http://192.168.4.1";
  if (lastDistanceCm >= 0 && millis() - distanceMeasuredAt < 1500) {
    doc["distance_cm"] = lastDistanceCm;
  }
  // Object detection, person counts, and traffic-light colour estimates are
  // computed on the phone from a requested camera frame. Never emit them here.
  String packet;
  serializeJson(doc, packet);
  packet += "\n";
  telemetryCharacteristic->setValue(packet.c_str());
  telemetryCharacteristic->notify();
}

void handleCameraStatus() {
  JsonDocument doc;
  doc["device"] = "BlindStick Companion";
  doc["camera_ready"] = cameraReady;
  doc["assistance"] = assistanceEnabled;
  doc["frame_endpoint"] = "/capture";
  doc["model_inference"] = "runs_on_android_phone";
  if (lastDistanceCm >= 0 && millis() - distanceMeasuredAt < 1500) {
    doc["distance_cm"] = lastDistanceCm;
  }
  String payload;
  serializeJson(doc, payload);
  cameraServer.sendHeader("Cache-Control", "no-store");
  cameraServer.sendHeader("Access-Control-Allow-Origin", "*");
  cameraServer.send(200, "application/json", payload);
}

void handleCameraCapture() {
  if (!assistanceEnabled) {
    cameraServer.send(409, "application/json",
      "{\"error\":\"Assistance is paused. Start assistance in the app first.\"}");
    return;
  }
  if (!cameraReady) {
    cameraServer.send(503, "application/json",
      "{\"error\":\"Camera is not ready\"}");
    return;
  }
  camera_fb_t* frame = esp_camera_fb_get();
  if (frame == nullptr || frame->len == 0) {
    if (frame) esp_camera_fb_return(frame);
    cameraServer.send(503, "application/json",
      "{\"error\":\"Could not capture a camera frame\"}");
    return;
  }
  WiFiClient client = cameraServer.client();
  client.setNoDelay(true);
  client.printf(
    "HTTP/1.1 200 OK\\r\\n"
    "Content-Type: image/jpeg\\r\\n"
    "Cache-Control: no-store\\r\\n"
    "Access-Control-Allow-Origin: *\\r\\n"
    "Content-Length: %u\\r\\n"
    "Connection: close\\r\\n\\r\\n",
    (unsigned int)frame->len);
  const size_t written = client.write(frame->buf, frame->len);
  cameraFrameAvailable = written == frame->len;
  esp_camera_fb_return(frame);
  client.stop();
}

float readUltrasonicDistanceCm() {
  digitalWrite(ULTRASONIC_TRIG_GPIO, LOW);
  delayMicroseconds(3);
  digitalWrite(ULTRASONIC_TRIG_GPIO, HIGH);
  delayMicroseconds(10);
  digitalWrite(ULTRASONIC_TRIG_GPIO, LOW);
  const unsigned long duration = pulseIn(ULTRASONIC_ECHO_GPIO, HIGH, 25000UL);
  if (duration == 0) return -1.0f;
  const float cm = static_cast<float>(duration) / 58.0f;
  if (cm < 2.0f || cm > 400.0f) return -1.0f;
  return cm;
}

void updateSensorsAndHaptics(unsigned long now) {
  if (now - lastSensorReadMs >= SENSOR_PERIOD_MS) {
    lastSensorReadMs = now;
    if (assistanceEnabled) {
      const float distance = readUltrasonicDistanceCm();
      if (distance >= 0) {
        lastDistanceCm = distance;
        distanceMeasuredAt = now;
      } else if (now - distanceMeasuredAt > 1500) {
        lastDistanceCm = -1.0f;
      }
    } else {
      lastDistanceCm = -1.0f;
    }
  }

  const bool freshDistance = lastDistanceCm >= 0 &&
    now - distanceMeasuredAt < 1500;
  if (assistanceEnabled && freshDistance &&
      now - lastMotorPulseMs >= MOTOR_REPEAT_MS) {
    if (lastDistanceCm < STOP_DISTANCE_CM) {
      // High urgency: repeat a short pulse at a steady cadence.
      requestedVibrationUntilMs = now + MOTOR_PULSE_MS;
      lastMotorPulseMs = now;
    } else if (lastDistanceCm < CAUTION_DISTANCE_CM) {
      // Lower urgency: same pulse duration, with a slower cadence.
      requestedVibrationUntilMs = now + MOTOR_PULSE_MS;
      lastMotorPulseMs = now;
    }
  }

  const bool commandPulseActive = assistanceEnabled &&
    requestedVibrationUntilMs != 0 &&
    static_cast<long>(requestedVibrationUntilMs - now) > 0;
  digitalWrite(VIBRATION_DRIVER_GPIO, commandPulseActive ? HIGH : LOW);
}

void setup() {
  Serial.begin(115200);
  delay(300);

  pinMode(ULTRASONIC_TRIG_GPIO, OUTPUT);
  digitalWrite(ULTRASONIC_TRIG_GPIO, LOW);
  pinMode(ULTRASONIC_ECHO_GPIO, INPUT);
  pinMode(VIBRATION_DRIVER_GPIO, OUTPUT);
  digitalWrite(VIBRATION_DRIVER_GPIO, LOW);

  cameraReady = initCamera();

  WiFi.mode(WIFI_AP);
  const bool apStarted = WiFi.softAP(CAMERA_AP_SSID, CAMERA_AP_PASSWORD, 6, false, 1);
  Serial.printf("Camera AP %s: %s at %s\\n",
    CAMERA_AP_SSID, apStarted ? "started" : "FAILED",
    WiFi.softAPIP().toString().c_str());
  cameraServer.on("/status", HTTP_GET, handleCameraStatus);
  cameraServer.on("/capture", HTTP_GET, handleCameraCapture);
  cameraServer.on("/", HTTP_GET, []() {
    cameraServer.send(200, "text/plain",
      "BlindStick Companion local camera. GET /status for device status and /capture for one JPEG frame.");
  });
  cameraServer.begin();

  BLEDevice::init("BlindStick Companion");
  BLEServer* server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());
  BLEService* service = server->createService(SERVICE_UUID);

  telemetryCharacteristic = service->createCharacteristic(
    TELEMETRY_UUID,
    BLECharacteristic::PROPERTY_NOTIFY
  );
  telemetryCharacteristic->addDescriptor(new BLE2902());

  BLECharacteristic* commandCharacteristic = service->createCharacteristic(
    COMMAND_UUID,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
  );
  commandCharacteristic->setCallbacks(new CommandCallbacks());

  service->start();
  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->start();

  Serial.printf("BLE advertising. Camera ready: %s\n", cameraReady ? "yes" : "no");
}

void loop() {
  const unsigned long now = millis();

  cameraServer.handleClient();
  updateSensorsAndHaptics(now);

  // A JPEG is captured when the phone requests /capture. This avoids discarding
  // frames every loop while allowing the phone's TFLite model to run inference.
  if (now - lastTelemetryMs >= TELEMETRY_PERIOD_MS) {
    lastTelemetryMs = now;
    publishTelemetry();
  }
  delay(2);
}
