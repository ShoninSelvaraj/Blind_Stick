/*
 * DishaFlow Blind Stick — ESP32-CAM BLE bridge
 * Target: AI Thinker ESP32-CAM (classic ESP32), Arduino ESP32 core.
 *
 * IMPORTANT:
 * - This firmware establishes the app's BLE protocol and camera capture.
 * - It does NOT claim to perform AI object/traffic/crowd detection: no trained
 *   model has been supplied. Detection fields are omitted until a real model
 *   is integrated. Never use this prototype as the sole mobility safety aid.
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
    if (!strcmp(cmd, "stop")) assistanceEnabled = false;
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
  doc["device"] = "dishaflow-esp32cam";
  doc["assistance"] = assistanceEnabled;
  doc["camera_ready"] = cameraReady;
  doc["camera_frame_available"] = cameraFrameAvailable;
  doc["detection_status"] = "model_not_installed";
  // Deliberately omit object, distance_cm, battery, traffic_walk and crowd:
  // no sensor/model can currently provide truthful values on this board alone.
  String packet;
  serializeJson(doc, packet);
  packet += "\n";
  telemetryCharacteristic->setValue(packet.c_str());
  telemetryCharacteristic->notify();
}

void setup() {
  Serial.begin(115200);
  delay(300);
  cameraReady = initCamera();

  BLEDevice::init("DishaFlow Blind Stick");
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

  // Capture a frame to prove the camera path works. This is not object detection.
  if (assistanceEnabled && cameraReady && now - lastCameraCheckMs >= 500) {
    lastCameraCheckMs = now;
    camera_fb_t* frame = esp_camera_fb_get();
    cameraFrameAvailable = frame != nullptr && frame->len > 0;
    if (frame) esp_camera_fb_return(frame);
  }

  if (now - lastTelemetryMs >= 1000) {
    lastTelemetryMs = now;
    publishTelemetry();
  }
  delay(10);
}
