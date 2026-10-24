Third-party model and code attribution

1. Pedestrian-signal detection model

Project: VIA-Safe-Crosswalk
Source repository: https://github.com/25-p-project-team-6/VIA-Safe-Crosswalk
License: MIT (upstream LICENSE)
Model file: best_yolo26n_7cls_v2_raw_int8_320.tflite
Source URL: https://raw.githubusercontent.com/25-p-project-team-6/VIA-Safe-Crosswalk/main/app/src/main/assets/best_yolo26n_7cls_v2_raw_int8_320.tflite
SHA-256: 36243860db3e4c08346c9be4a13c1be36a5e01e2088b11eca7ad7233938a40ef
Expected input: [1, 320, 320, 3], FLOAT32
Expected output: [1, 11, 2100], FLOAT32 raw output (4 box coordinates + 7 class scores per anchor)
Class order: bicycle, motorcycle, vehicle, human_green, human_red, vehicle_green, vehicle_red.

The upstream project reports validation on its own mixed_dataset_human_vehicle_signal_7cls_v2 dataset. Those results are not proof of performance on Indian intersections, the target camera mounting, lighting, weather, or a particular user's routes. This project treats the detector as an experimental advisory only. It never issues a crossing command.

MIT License

Copyright (c) 2026 25-P-Project-Team-6

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

2. General object detection model

Model: quantized SSD MobileNet V1 trained for the COCO object classes.
Source: TensorFlow Lite hosted model archive
URL: https://storage.googleapis.com/download.tensorflow.org/models/tflite/coco_ssd_mobilenet_v1_1.0_quant_2018_06_29.zip
License: Apache 2.0, consistent with TensorFlow's published SSD MobileNet V1 TFLite model listing: https://www.kaggle.com/models/tensorflow/ssd-mobilenet-v1/tfLite

This project downloads and caches the general detector in app-private storage. The downloaded file is checked for a valid TFLite FlatBuffer header; unlike the pedestrian-signal model, the current general-model download does not yet pin a SHA-256 checksum.

Important usage boundary

These models are probabilistic and have not been independently safety-validated with BlindStick Companion, this ESP32-CAM, an ultrasonic sensor, or Indian pedestrian crossings. Object detections can miss hazards; traffic-signal detections can be wrong. A “human_green” prediction is not proof that it is safe to cross. Use established mobility techniques and audible/tactile crossing cues; this prototype must not be a user's only mobility aid.
