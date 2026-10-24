package com.vimal.blindstick

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.content.pm.ServiceInfo
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.core.app.NotificationCompat
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import org.tensorflow.lite.DataType
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.Tensor
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.Locale
import java.util.zip.ZipInputStream
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    private val visionChannelName = "blindstick_companion/vision"
    private val modelZipUrl =
        "https://storage.googleapis.com/download.tensorflow.org/models/tflite/coco_ssd_mobilenet_v1_1.0_quant_2018_06_29.zip"
    // MIT-licensed 7-class YOLO26n model distinguishes pedestrian-signal red/green
    // from vehicle-signal red/green. Its checksum is pinned to the upstream notice.
    private val pedestrianSignalModelUrl =
        "https://raw.githubusercontent.com/25-p-project-team-6/VIA-Safe-Crosswalk/main/app/src/main/assets/best_yolo26n_7cls_v2_raw_int8_320.tflite"
    private val pedestrianSignalSha256 =
        "36243860db3e4c08346c9be4a13c1be36a5e01e2088b11eca7ad7233938a40ef"
    private val worker = java.util.concurrent.Executors.newSingleThreadExecutor()
    @Volatile private var interpreter: Interpreter? = null
    @Volatile private var pedestrianSignalInterpreter: Interpreter? = null
    private data class SignalCandidate(
        val label: String,
        val confidence: Float,
        val left: Float,
        val top: Float,
        val right: Float,
        val bottom: Float
    )

    private val cocoLabels = mapOf(
        1 to "person", 2 to "bicycle", 3 to "car", 4 to "motorcycle",
        5 to "airplane", 6 to "bus", 7 to "train", 8 to "truck", 9 to "boat",
        10 to "traffic light", 11 to "fire hydrant", 13 to "stop sign",
        14 to "parking meter", 15 to "bench", 16 to "bird", 17 to "cat",
        18 to "dog", 19 to "horse", 20 to "sheep", 21 to "cow", 22 to "elephant",
        23 to "bear", 24 to "zebra", 25 to "giraffe", 27 to "backpack",
        28 to "umbrella", 31 to "handbag", 32 to "tie", 33 to "suitcase",
        34 to "frisbee", 35 to "skis", 36 to "snowboard", 37 to "sports ball",
        38 to "kite", 39 to "baseball bat", 40 to "baseball glove",
        41 to "skateboard", 42 to "surfboard", 43 to "tennis racket",
        44 to "bottle", 46 to "wine glass", 47 to "cup", 48 to "fork",
        49 to "knife", 50 to "spoon", 51 to "bowl", 52 to "banana",
        53 to "apple", 54 to "sandwich", 55 to "orange", 56 to "broccoli",
        57 to "carrot", 58 to "hot dog", 59 to "pizza", 60 to "donut",
        61 to "cake", 62 to "chair", 63 to "couch", 64 to "potted plant",
        65 to "bed", 67 to "dining table", 70 to "toilet", 72 to "tv",
        73 to "laptop", 74 to "mouse", 75 to "remote", 76 to "keyboard",
        77 to "cell phone", 78 to "microwave", 79 to "oven", 80 to "toaster",
        81 to "sink", 82 to "refrigerator", 84 to "book", 85 to "clock",
        86 to "vase", 87 to "scissors", 88 to "teddy bear", 89 to "hair drier",
        90 to "toothbrush"
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "blindstick_companion_emergency_alerts",
                "BlindStick Companion emergency alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Urgent SOS alerts from a person linked to your BlindStick Companion account"
                enableVibration(true)
                setShowBadge(true)
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "blindstick_companion/alerts")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startCaregiverAlertMonitor" -> {
                        try {
                            val serviceIntent = Intent(this, CaregiverAlertMonitorService::class.java)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(serviceIntent)
                            } else {
                                startService(serviceIntent)
                            }
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("ALERT_MONITOR_START", error.message, null)
                        }
                    }
                    "stopCaregiverAlertMonitor" -> result.success(
                        stopService(Intent(this, CaregiverAlertMonitorService::class.java))
                    )
                    "isCaregiverAlertMonitorRunning" -> result.success(
                        CaregiverAlertMonitorService.isRunning
                    )
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, visionChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openWifiSettings" -> {
                        try {
                            startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("WIFI_SETTINGS", error.message, null)
                        }
                    }
                    "cameraHttpGet" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank()) {
                            result.error("CAMERA_URL", "A camera URL is required", null)
                        } else if (!url.startsWith("http://192.168.4.1/")) {
                            result.error("CAMERA_URL", "Only the local ESP32-CAM endpoint can use Wi-Fi-bound requests", null)
                        } else {
                            worker.execute {
                                try {
                                    val response = getCameraResponseOnWifi(url)
                                    runOnUiThread { result.success(response) }
                                } catch (error: Exception) {
                                    runOnUiThread { result.error("CAMERA_NETWORK", error.message ?: "Camera request failed", null) }
                                }
                            }
                        }
                    }
                    "visionModelReady" -> result.success(
                        modelFile().let { it.exists() && it.length() > 100_000 } &&
                        pedestrianSignalModelFile().let {
                            it.exists() && it.length() > 2_000_000 &&
                                runCatching { sha256(it) == pedestrianSignalSha256 }.getOrDefault(false)
                        }
                    )
                    "prepareVisionModel" -> worker.execute {
                        try {
                            val file = ensureModelFile()
                            getInterpreter(file)
                            val signalFile = ensurePedestrianSignalModelFile()
                            getPedestrianSignalInterpreter(signalFile)
                            runOnUiThread {
                                result.success(
                                    mapOf(
                                        "ready" to true,
                                        "model" to "SSD MobileNet COCO + YOLO26n pedestrian signal",
                                        "bytes" to file.length() + signalFile.length()
                                    )
                                )
                            }
                        } catch (error: Exception) {
                            runOnUiThread { result.error("VISION_MODEL", error.message ?: "Model download failed", null) }
                        }
                    }
                    "detectObjects" -> {
                        val jpeg = call.argument<ByteArray>("jpegBytes")
                        if (jpeg == null || jpeg.isEmpty()) {
                            result.error("VISION_FRAME", "No camera JPEG bytes were supplied", null)
                        } else {
                            worker.execute {
                                try {
                                    val output = detectJpeg(jpeg)
                                    runOnUiThread { result.success(output) }
                                } catch (error: Exception) {
                                    runOnUiThread { result.error("VISION_INFERENCE", error.message ?: "Inference failed", null) }
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun getCameraResponseOnWifi(url: String): Map<String, Any> {
        val manager = getSystemService(ConnectivityManager::class.java)
            ?: throw IllegalStateException("Android network manager is unavailable.")
        val wifi = manager.allNetworks.firstOrNull { network: Network ->
            manager.getNetworkCapabilities(network)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        } ?: throw IllegalStateException(
            "No active Wi-Fi network is available. Connect to BlindStick-Camera Wi-Fi and retry."
        )

        // Bind only this HTTP connection to the Wi-Fi network. Do not bind the
        // whole process: Firebase, map search and routing must keep using Android's
        // normal internet route (usually mobile data when the camera AP has no internet).
        val connection = (wifi.openConnection(URL(url)) as HttpURLConnection).apply {
            connectTimeout = 4_000
            readTimeout = 5_000
            requestMethod = "GET"
            setRequestProperty("Cache-Control", "no-cache")
            setRequestProperty("Connection", "close")
        }
        try {
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val bytes = stream?.use { it.readBytes() } ?: ByteArray(0)
            if (bytes.size > 2 * 1024 * 1024) {
                throw IllegalStateException("Camera response exceeded the 2 MB safety limit.")
            }
            val contentType = connection.contentType.orEmpty()
            val response = mutableMapOf<String, Any>(
                "statusCode" to status,
                "bodyBytes" to bytes
            )
            if (contentType.contains("json", ignoreCase = true) || status >= 400) {
                response["body"] = bytes.toString(Charsets.UTF_8)
            }
            return response
        } finally {
            connection.disconnect()
        }
    }

    private fun modelFile(): File {
        val folder = File(filesDir, "vision-model")
        if (!folder.exists()) folder.mkdirs()
        return File(folder, "detect.tflite")
    }

    private fun pedestrianSignalModelFile(): File {
        val folder = File(filesDir, "vision-model")
        if (!folder.exists()) folder.mkdirs()
        return File(folder, "pedestrian-signal-yolo26n-7cls-int8-320.tflite")
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { input ->
            val block = ByteArray(32 * 1024)
            while (true) {
                val read = input.read(block)
                if (read <= 0) break
                digest.update(block, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun ensurePedestrianSignalModelFile(): File {
        val destination = pedestrianSignalModelFile()
        if (destination.exists() && destination.length() > 2_000_000) {
            if (sha256(destination) == pedestrianSignalSha256) return destination
            destination.delete()
        }

        val temporary = File(destination.parentFile, "pedestrian-signal.tflite.part")
        val connection = (URL(pedestrianSignalModelUrl).openConnection() as HttpURLConnection).apply {
            connectTimeout = 20_000
            readTimeout = 60_000
            requestMethod = "GET"
            setRequestProperty("User-Agent", "BlindStick-Companion/1.0")
        }
        try {
            connection.connect()
            if (connection.responseCode !in 200..299) {
                throw IllegalStateException("Pedestrian-signal model download returned HTTP ${connection.responseCode}.")
            }
            BufferedInputStream(connection.inputStream).use { input ->
                BufferedOutputStream(FileOutputStream(temporary)).use { output -> input.copyTo(output) }
            }
        } finally {
            connection.disconnect()
        }

        if (temporary.length() < 2_000_000 || sha256(temporary) != pedestrianSignalSha256) {
            temporary.delete()
            throw IllegalStateException("Pedestrian-signal model failed the pinned SHA-256 integrity check.")
        }
        FileInputStream(temporary).use { input ->
            val bytes = ByteArray(8)
            if (input.read(bytes) != bytes.size || String(bytes, 4, 4, Charsets.US_ASCII) != "TFL3") {
                temporary.delete()
                throw IllegalStateException("Pedestrian-signal model is not a valid TFLite file.")
            }
        }
        if (destination.exists()) destination.delete()
        if (!temporary.renameTo(destination)) {
            temporary.copyTo(destination, overwrite = true)
            temporary.delete()
        }
        return destination
    }

    private fun ensureModelFile(): File {
        val destination = modelFile()
        if (destination.exists() && destination.length() > 100_000) return destination
        val zipFile = File(cacheDir, "coco-ssd-mobile-net.zip")
        val connection = (URL(modelZipUrl).openConnection() as HttpURLConnection).apply {
            connectTimeout = 20_000
            readTimeout = 60_000
            requestMethod = "GET"
            setRequestProperty("User-Agent", "BlindStick-Companion/1.0")
        }
        try {
            connection.connect()
            if (connection.responseCode !in 200..299) {
                throw IllegalStateException("Model download returned HTTP ${connection.responseCode}. Connect to the internet and try again.")
            }
            BufferedInputStream(connection.inputStream).use { input ->
                BufferedOutputStream(FileOutputStream(zipFile)).use { output -> input.copyTo(output) }
            }
        } finally {
            connection.disconnect()
        }

        var extracted = false
        val temporary = File(destination.parentFile, "detect.tflite.part")
        ZipInputStream(BufferedInputStream(FileInputStream(zipFile))).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                if (!entry.isDirectory && entry.name.lowercase(Locale.US).endsWith(".tflite")) {
                    BufferedOutputStream(FileOutputStream(temporary)).use { output -> zip.copyTo(output) }
                    zip.closeEntry()
                    if (temporary.length() > 100_000) {
                        if (destination.exists()) destination.delete()
                        if (!temporary.renameTo(destination)) {
                            temporary.copyTo(destination, overwrite = true)
                            temporary.delete()
                        }
                        extracted = true
                        break
                    }
                }
                zip.closeEntry()
            }
        }
        zipFile.delete()
        if (!extracted || !destination.exists() || destination.length() < 100_000) {
            temporary.delete()
            throw IllegalStateException("The downloaded archive did not contain a valid TFLite model.")
        }
        // TFLite FlatBuffer files start with the TFL3 identifier at byte offset 4.
        FileInputStream(destination).use { input ->
            val bytes = ByteArray(8)
            if (input.read(bytes) != bytes.size || String(bytes, 4, 4, Charsets.US_ASCII) != "TFL3") {
                destination.delete()
                throw IllegalStateException("The downloaded model failed its file integrity check.")
            }
        }
        return destination
    }

    @Synchronized
    private fun getInterpreter(file: File = modelFile()): Interpreter {
        val existing = interpreter
        if (existing != null) return existing
        if (!file.exists() || file.length() < 100_000) {
            throw IllegalStateException("General object-detection model not prepared. Connect to the internet and tap Prepare on-device AI first.")
        }
        val options = Interpreter.Options().apply { setNumThreads(2) }
        return Interpreter(file, options).also { interpreter = it }
    }

    @Synchronized
    private fun getPedestrianSignalInterpreter(file: File = pedestrianSignalModelFile()): Interpreter {
        val existing = pedestrianSignalInterpreter
        if (existing != null) return existing
        if (!file.exists() || file.length() < 2_000_000 || sha256(file) != pedestrianSignalSha256) {
            throw IllegalStateException("Pedestrian-signal model is missing or failed integrity verification. Prepare the on-device models again.")
        }
        val options = Interpreter.Options().apply { setNumThreads(2) }
        return Interpreter(file, options).also { pedestrianSignalInterpreter = it }
    }

    private fun detectJpeg(jpeg: ByteArray): Map<String, Any> {
        val source = BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size)
            ?: throw IllegalStateException("The camera endpoint did not return a decodable JPEG image.")
        if (source.width < 32 || source.height < 32) {
            source.recycle()
            throw IllegalStateException("The camera frame is too small to run object detection.")
        }
        val model = getInterpreter()
        val resized = Bitmap.createScaledBitmap(source, 300, 300, true)
        val inputTensor = model.getInputTensor(0)
        val input = ByteBuffer.allocateDirect(inputTensor.numBytes()).order(ByteOrder.nativeOrder())
        val pixels = IntArray(300 * 300)
        resized.getPixels(pixels, 0, 300, 0, 0, 300, 300)
        val inputType = inputTensor.dataType()
        val inputQuant = inputTensor.quantizationParams()
        for (pixel in pixels) {
            val red = (pixel shr 16) and 0xFF
            val green = (pixel shr 8) and 0xFF
            val blue = pixel and 0xFF
            when (inputType) {
                DataType.FLOAT32 -> {
                    input.putFloat(red / 255f)
                    input.putFloat(green / 255f)
                    input.putFloat(blue / 255f)
                }
                DataType.UINT8 -> {
                    input.put(red.toByte()); input.put(green.toByte()); input.put(blue.toByte())
                }
                DataType.INT8 -> {
                    val scale = if (inputQuant.scale > 0f) inputQuant.scale else (1f / 255f)
                    val zero = inputQuant.zeroPoint
                    input.put(((red / 255f / scale + zero).roundToInt()).coerceIn(-128, 127).toByte())
                    input.put(((green / 255f / scale + zero).roundToInt()).coerceIn(-128, 127).toByte())
                    input.put(((blue / 255f / scale + zero).roundToInt()).coerceIn(-128, 127).toByte())
                }
                else -> throw IllegalStateException("Unsupported model input type: $inputType")
            }
        }
        input.rewind()

        val outputs = HashMap<Int, Any>()
        val buffers = HashMap<Int, ByteBuffer>()
        for (index in 0 until model.outputTensorCount) {
            val buffer = ByteBuffer.allocateDirect(model.getOutputTensor(index).numBytes()).order(ByteOrder.nativeOrder())
            buffers[index] = buffer
            outputs[index] = buffer
        }
        model.runForMultipleInputsOutputs(arrayOf(input), outputs)

        fun outputFloats(index: Int, dequantize: Boolean = true): FloatArray {
            val tensor = model.getOutputTensor(index)
            val buffer = buffers[index]!!.apply { rewind() }
            return when (tensor.dataType()) {
                DataType.FLOAT32 -> FloatArray(tensor.numElements()) { buffer.float }
                DataType.UINT8 -> FloatArray(tensor.numElements()) {
                    val raw = (buffer.get().toInt() and 0xFF).toFloat()
                    if (dequantize && tensor.quantizationParams().scale > 0f) {
                        (raw - tensor.quantizationParams().zeroPoint) * tensor.quantizationParams().scale
                    } else raw
                }
                DataType.INT8 -> FloatArray(tensor.numElements()) {
                    val raw = buffer.get().toInt().toFloat()
                    if (dequantize && tensor.quantizationParams().scale > 0f) {
                        (raw - tensor.quantizationParams().zeroPoint) * tensor.quantizationParams().scale
                    } else raw
                }
                DataType.INT32 -> FloatArray(tensor.numElements()) { buffer.int.toFloat() }
                else -> throw IllegalStateException("Unsupported output tensor type: ${tensor.dataType()}")
            }
        }

        val boxesIndex = (0 until model.outputTensorCount).firstOrNull {
            val shape = model.getOutputTensor(it).shape()
            shape.size == 3 && shape.last() == 4
        } ?: 0
        val classIndex = (0 until model.outputTensorCount).firstOrNull {
            model.getOutputTensor(it).name().lowercase(Locale.US).contains("class")
        } ?: 1
        val scoreIndex = (0 until model.outputTensorCount).firstOrNull {
            model.getOutputTensor(it).name().lowercase(Locale.US).contains("score")
        } ?: 2
        val countIndex = (0 until model.outputTensorCount).firstOrNull {
            val name = model.getOutputTensor(it).name().lowercase(Locale.US)
            name.contains("num_detections") || model.getOutputTensor(it).shape().contentEquals(intArrayOf(1))
        } ?: 3

        val boxes = outputFloats(boxesIndex)
        val classes = outputFloats(classIndex, dequantize = false)
        val scores = outputFloats(scoreIndex)
        val countRaw = outputFloats(countIndex, dequantize = false).firstOrNull()?.roundToInt() ?: scores.size
        val detectionLimit = min(countRaw.coerceAtLeast(0), min(scores.size, classes.size))
        val detections = ArrayList<Map<String, Any>>(detectionLimit)
        var people = 0
        for (index in 0 until detectionLimit) {
            val score = scores[index]
            if (!score.isFinite() || score < 0.35f) continue
            val classId = classes[index].roundToInt()
            val label = cocoLabels[classId] ?: continue
            val offset = index * 4
            if (offset + 3 >= boxes.size) continue
            val top = boxes[offset].coerceIn(0f, 1f)
            val left = boxes[offset + 1].coerceIn(0f, 1f)
            val bottom = boxes[offset + 2].coerceIn(0f, 1f)
            val right = boxes[offset + 3].coerceIn(0f, 1f)
            if (bottom <= top || right <= left) continue

            val trafficState = if (label == "traffic light") {
                classifyTrafficLamp(source, left, top, right, bottom)
            } else "not_applicable"

            detections.add(mapOf(
                "label" to label,
                "confidence" to score.toDouble(),
                "box" to listOf(top.toDouble(), left.toDouble(), bottom.toDouble(), right.toDouble()),
                "trafficState" to trafficState
            ))
            if (label == "person" && score >= 0.40f) people++
        }

        val pedestrianSignals = try {
            detectPedestrianSignals(source)
        } catch (_: Exception) {
            // An independent signal-model failure must not suppress common-object detection.
            emptyList()
        }

        if (resized !== source) resized.recycle()
        source.recycle()
        return mapOf(
            "model" to "SSD MobileNet V1 COCO (quantized)",
            "detections" to detections,
            "personCount" to people,
            "crowdLevel" to when { people >= 5 -> "high"; people >= 3 -> "medium"; else -> "low" },
            "pedestrianSignals" to pedestrianSignals
        )
    }

    private fun detectPedestrianSignals(bitmap: Bitmap): List<Map<String, Any>> {
        val model = getPedestrianSignalInterpreter()
        val inputTensor = model.getInputTensor(0)
        val inputShape = inputTensor.shape()
        if (inputShape.size != 4 || inputShape[0] != 1 || inputShape[3] != 3) {
            throw IllegalStateException("Unexpected pedestrian-signal model input shape: ${inputShape.contentToString()}")
        }
        val height = inputShape[1]
        val width = inputShape[2]
        val outputTensor = model.getOutputTensor(0)
        val outputShape = outputTensor.shape()
        if (outputShape.size != 3 || outputShape[0] != 1 || outputShape[1] != 11) {
            throw IllegalStateException("Unexpected pedestrian-signal model output shape: ${outputShape.contentToString()}")
        }
        val anchors = outputShape[2]

        // Match the upstream Ultralytics preprocessing: keep the camera aspect ratio
        // and pad to a square instead of stretching a 4:3 frame into 1:1.
        val scale = min(width.toFloat() / bitmap.width, height.toFloat() / bitmap.height)
        val scaledWidth = (bitmap.width * scale).roundToInt().coerceIn(1, width)
        val scaledHeight = (bitmap.height * scale).roundToInt().coerceIn(1, height)
        val padLeft = (width - scaledWidth) / 2
        val padTop = (height - scaledHeight) / 2
        val resized = Bitmap.createScaledBitmap(bitmap, scaledWidth, scaledHeight, true)
        val resizedPixels = IntArray(scaledWidth * scaledHeight)
        resized.getPixels(resizedPixels, 0, scaledWidth, 0, 0, scaledWidth, scaledHeight)
        val pixels = IntArray(width * height) { android.graphics.Color.rgb(114, 114, 114) }
        for (row in 0 until scaledHeight) {
            System.arraycopy(
                resizedPixels,
                row * scaledWidth,
                pixels,
                (row + padTop) * width + padLeft,
                scaledWidth
            )
        }

        val input = ByteBuffer.allocateDirect(inputTensor.numBytes()).order(ByteOrder.nativeOrder())
        val inputQuant = inputTensor.quantizationParams()
        for (pixel in pixels) {
            val channels = intArrayOf((pixel shr 16) and 0xFF, (pixel shr 8) and 0xFF, pixel and 0xFF)
            for (channel in channels) {
                val normal = channel / 255.0f
                when (inputTensor.dataType()) {
                    DataType.FLOAT32 -> input.putFloat(normal)
                    DataType.UINT8 -> input.put(channel.toByte())
                    DataType.INT8 -> {
                        val qScale = if (inputQuant.scale > 0f) inputQuant.scale else (1f / 255f)
                        input.put(((normal / qScale + inputQuant.zeroPoint).roundToInt()).coerceIn(-128, 127).toByte())
                    }
                    else -> throw IllegalStateException("Unsupported signal-model input type: ${inputTensor.dataType()}")
                }
            }
        }
        input.rewind()

        val outputBuffer = ByteBuffer.allocateDirect(outputTensor.numBytes()).order(ByteOrder.nativeOrder())
        model.run(input, outputBuffer)
        outputBuffer.rewind()
        val output = when (outputTensor.dataType()) {
            DataType.FLOAT32 -> FloatArray(outputTensor.numElements()) { outputBuffer.float }
            DataType.UINT8 -> {
                val q = outputTensor.quantizationParams()
                FloatArray(outputTensor.numElements()) { ((outputBuffer.get().toInt() and 0xFF) - q.zeroPoint) * q.scale }
            }
            DataType.INT8 -> {
                val q = outputTensor.quantizationParams()
                FloatArray(outputTensor.numElements()) { (outputBuffer.get().toInt() - q.zeroPoint) * q.scale }
            }
            else -> throw IllegalStateException("Unsupported signal-model output type: ${outputTensor.dataType()}")
        }
        if (resized !== bitmap) resized.recycle()

        val labels = listOf("bicycle", "motorcycle", "vehicle", "human_green", "human_red", "vehicle_green", "vehicle_red")
        val candidates = ArrayList<SignalCandidate>()
        fun value(channel: Int, anchor: Int): Float = output[channel * anchors + anchor]
        for (anchor in 0 until anchors) {
            var classIndex = -1
            var bestScore = 0f
            for (classOffset in labels.indices) {
                val score = value(4 + classOffset, anchor)
                if (score > bestScore) {
                    bestScore = score
                    classIndex = classOffset
                }
            }
            if (classIndex !in labels.indices || bestScore < 0.38f) continue

            val cxRaw = value(0, anchor)
            val cyRaw = value(1, anchor)
            val widthRaw = value(2, anchor)
            val heightRaw = value(3, anchor)
            // The upstream parser treats the four box values as one coordinate unit:
            // if any are pixels, divide all four by the input dimensions.
            val coordinatesArePixels =
                cxRaw > 1f || cyRaw > 1f || widthRaw > 1f || heightRaw > 1f
            val cx = if (coordinatesArePixels) cxRaw / width else cxRaw
            val cy = if (coordinatesArePixels) cyRaw / height else cyRaw
            val boxWidth = if (coordinatesArePixels) widthRaw / width else widthRaw
            val boxHeight = if (coordinatesArePixels) heightRaw / height else heightRaw

            val squareLeft = cx - boxWidth / 2f
            val squareTop = cy - boxHeight / 2f
            val squareRight = cx + boxWidth / 2f
            val squareBottom = cy + boxHeight / 2f

            // Remove the letterbox padding and map the box to normalized coordinates
            // in the original camera image. Invalid/padding-only boxes are discarded.
            val left = (((squareLeft * width) - padLeft) / scale / bitmap.width).coerceIn(0f, 1f)
            val top = (((squareTop * height) - padTop) / scale / bitmap.height).coerceIn(0f, 1f)
            val right = (((squareRight * width) - padLeft) / scale / bitmap.width).coerceIn(0f, 1f)
            val bottom = (((squareBottom * height) - padTop) / scale / bitmap.height).coerceIn(0f, 1f)
            if (right <= left || bottom <= top) continue
            candidates.add(SignalCandidate(labels[classIndex], bestScore, left, top, right, bottom))
        }

        fun intersectionOverUnion(a: SignalCandidate, b: SignalCandidate): Float {
            val intersectionWidth = max(0f, min(a.right, b.right) - max(a.left, b.left))
            val intersectionHeight = max(0f, min(a.bottom, b.bottom) - max(a.top, b.top))
            val intersection = intersectionWidth * intersectionHeight
            val areaA = (a.right - a.left) * (a.bottom - a.top)
            val areaB = (b.right - b.left) * (b.bottom - b.top)
            val union = areaA + areaB - intersection
            return if (union <= 0f) 0f else intersection / union
        }
        val kept = ArrayList<SignalCandidate>()
        for (candidate in candidates.sortedByDescending { it.confidence }) {
            if (kept.any { it.label == candidate.label && intersectionOverUnion(it, candidate) > 0.45f }) continue
            kept.add(candidate)
            if (kept.size >= 20) break
        }
        return kept.map {
            mapOf(
                "label" to it.label,
                "confidence" to it.confidence.toDouble(),
                "box" to listOf(it.top.toDouble(), it.left.toDouble(), it.bottom.toDouble(), it.right.toDouble())
            )
        }
    }

    private fun classifyTrafficLamp(bitmap: Bitmap, left: Float, top: Float, right: Float, bottom: Float): String {
        val x0 = (left * bitmap.width).toInt().coerceIn(0, bitmap.width - 1)
        val y0 = (top * bitmap.height).toInt().coerceIn(0, bitmap.height - 1)
        val x1 = (right * bitmap.width).toInt().coerceIn(x0 + 1, bitmap.width)
        val y1 = (bottom * bitmap.height).toInt().coerceIn(y0 + 1, bitmap.height)
        val width = x1 - x0
        val height = y1 - y0
        if (width < 3 || height < 3) return "unknown"
        var red = 0; var amber = 0; var green = 0
        // Sample the interior only; tiny distant lamps will intentionally remain unknown.
        val leftInner = x0 + (width * 0.20f).toInt()
        val rightInner = max(leftInner + 1, x1 - (width * 0.20f).toInt())
        val topInner = y0 + (height * 0.10f).toInt()
        val bottomInner = max(topInner + 1, y1 - (height * 0.10f).toInt())
        var samples = 0
        val stepX = max(1, width / 18)
        val stepY = max(1, height / 28)
        for (y in topInner until bottomInner step stepY) {
            for (x in leftInner until rightInner step stepX) {
                val pixel = bitmap.getPixel(x, y)
                val r = (pixel shr 16) and 0xFF
                val g = (pixel shr 8) and 0xFF
                val b = pixel and 0xFF
                if (max(r, max(g, b)) < 90) continue
                samples++
                if (r > 115 && r > g * 1.30 && r > b * 1.25) red++
                if (r > 110 && g > 75 && b < min(r, g) * 0.75 && abs(r - g) < 95) amber++
                if (g > 105 && g > r * 1.20 && g > b * 0.90) green++
            }
        }
        if (samples < 4) return "unknown"
        val counts = mapOf("red" to red, "amber" to amber, "green" to green)
        val winner = counts.maxByOrNull { it.value } ?: return "unknown"
        val totalLampPixels = red + amber + green
        if (winner.value < 3 || totalLampPixels < 4 || winner.value < totalLampPixels * 0.50) return "unknown"
        return winner.key
    }

    override fun onDestroy() {
        super.onDestroy()
        worker.shutdown()
        interpreter?.close()
        pedestrianSignalInterpreter?.close()
        interpreter = null
        pedestrianSignalInterpreter = null
    }
}

/**
 * Zero-billing caregiver alert monitor. A user explicitly starts this visible
 * foreground service while signed in; it listens only to the currently paired
 * patient's SOS collection and displays local Android notifications. It is not
 * FCM and Android may still stop it under force-stop or battery restrictions.
 */
class CaregiverAlertMonitorService : Service() {
    companion object {
        @Volatile var isRunning: Boolean = false
            private set
        private const val MONITOR_CHANNEL = "blindstick_companion_monitor"
        private const val MONITOR_NOTIFICATION_ID = 9101
        private const val SOS_CHANNEL = "blindstick_companion_emergency_alerts"
    }

    private var claimListener: ListenerRegistration? = null
    private var alertsListener: ListenerRegistration? = null
    private var activePatientUid: String? = null
    private var alertsPrimed = false
    private val seenAlertIds = mutableSetOf<String>()

    override fun onCreate() {
        super.onCreate()
        createChannels()
        val notification = monitorNotification("Waiting for the linked person's account")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                MONITOR_NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(MONITOR_NOTIFICATION_ID, notification)
        }
        isRunning = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val uid = FirebaseAuth.getInstance().currentUser?.uid
        if (uid.isNullOrBlank()) {
            stopSelf()
            return START_NOT_STICKY
        }
        claimListener?.remove()
        claimListener = FirebaseFirestore.getInstance()
            .collection("pairingClaims")
            .document(uid)
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    updateMonitorNotification("Connection issue. Open the app to check alert monitoring.")
                    return@addSnapshotListener
                }
                val patientUid = snapshot?.getString("patientUid")
                if (patientUid.isNullOrBlank()) {
                    stopPatientAlertListener()
                    updateMonitorNotification("No linked person yet. Pair with someone in the app.")
                } else if (patientUid != activePatientUid) {
                    listenForPatient(patientUid)
                }
            }
        return START_STICKY
    }

    private fun listenForPatient(patientUid: String) {
        stopPatientAlertListener()
        activePatientUid = patientUid
        alertsPrimed = false
        seenAlertIds.clear()
        updateMonitorNotification("Monitoring SOS alerts from your linked person")
        alertsListener = FirebaseFirestore.getInstance()
            .collection("patients")
            .document(patientUid)
            .collection("alerts")
            .orderBy("createdAt", com.google.firebase.firestore.Query.Direction.DESCENDING)
            .limit(20)
            .addSnapshotListener { snapshot, error ->
                if (error != null || snapshot == null) {
                    updateMonitorNotification("Alert connection interrupted. Open the app to check status.")
                    return@addSnapshotListener
                }
                if (!alertsPrimed) {
                    seenAlertIds.addAll(snapshot.documents.map { it.id })
                    alertsPrimed = true
                    return@addSnapshotListener
                }
                for (change in snapshot.documentChanges) {
                    if (change.type != com.google.firebase.firestore.DocumentChange.Type.ADDED) continue
                    val document = change.document
                    if (!seenAlertIds.add(document.id)) continue
                    if (document.getString("type") != "sos") continue
                    val detail = document.getString("message") ?: "Emergency assistance requested"
                    val latitude = document.getDouble("latitude")
                    val longitude = document.getDouble("longitude")
                    showEmergencyNotification(detail, latitude, longitude)
                }
            }
    }

    private fun stopPatientAlertListener() {
        alertsListener?.remove()
        alertsListener = null
        activePatientUid = null
        alertsPrimed = false
        seenAlertIds.clear()
    }

    private fun createChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                MONITOR_CHANNEL,
                "Caregiver SOS monitoring",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Persistent status while background caregiver alert monitoring is enabled"
                setShowBadge(false)
            }
        )
        manager.createNotificationChannel(
            NotificationChannel(
                SOS_CHANNEL,
                "BlindStick Companion emergency alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Emergency alerts from a person linked to your account"
                enableVibration(true)
                setShowBadge(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PRIVATE
            }
        )
    }

    private fun monitorNotification(message: String) =
        NotificationCompat.Builder(this, MONITOR_CHANNEL)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("BlindStick Companion")
            .setContentText(message)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setContentIntent(openAppPendingIntent())
            .build()

    private fun updateMonitorNotification(message: String) {
        getSystemService(NotificationManager::class.java)
            .notify(MONITOR_NOTIFICATION_ID, monitorNotification(message))
    }

    private fun showEmergencyNotification(
        detail: String,
        latitude: Double?,
        longitude: Double?
    ) {
        val location = if (latitude != null && longitude != null) {
            " Shared coordinates are available in the app."
        } else {
            " No coordinates were attached to this alert."
        }
        val notification = NotificationCompat.Builder(this, SOS_CHANNEL)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle("BlindStick Companion: SOS alert")
            .setContentText("Your linked person requested help. Open the app to check.")
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .bigText("$detail$location Open BlindStick Companion and contact the person.")
            )
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setAutoCancel(true)
            .setVibrate(longArrayOf(0, 500, 180, 500))
            .setContentIntent(openAppPendingIntent())
            .build()
        val notificationId = (System.currentTimeMillis() and 0x7fffffff).toInt()
        getSystemService(NotificationManager::class.java).notify(notificationId, notification)
    }

    private fun openAppPendingIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        return PendingIntent.getActivity(this, 9101, intent, flags)
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        claimListener?.remove()
        claimListener = null
        stopPatientAlertListener()
        isRunning = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
