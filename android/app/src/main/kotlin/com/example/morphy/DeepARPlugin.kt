package com.example.morphy
import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.media.Image
import android.net.Uri
import android.os.Environment
import android.util.Size
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.TextureRegistry
import ai.deepar.ar.*
import com.google.common.util.concurrent.ListenableFuture
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
class DeepARPlugin : FlutterPlugin, MethodCallHandler, ActivityAware, AREventListener {
    
    private lateinit var channel: MethodChannel
    private lateinit var textureRegistry: TextureRegistry
    private var activity: Activity? = null
    private var context: Context? = null
    private var deepAR: DeepAR? = null
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var cameraProviderFuture: ListenableFuture<ProcessCameraProvider>? = null
    
    private var lensFacing = CameraSelector.LENS_FACING_FRONT
    private var buffers: Array<ByteBuffer>? = null
    private var currentBuffer = 0
    private val NUMBER_OF_BUFFERS = 2
    
    private var isDeepARInitialized = false
    private var recording = false
    private var videoFileName: File? = null
    
    // Gender classification
    private var genderClassifier: GenderClassifier? = null
    private var classificationEnabled = true
    private var frameCount = 0
    private val CLASSIFY_EVERY_N_FRAMES = 10
    private val classificationExecutor = Executors.newSingleThreadExecutor()
    
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        textureRegistry = binding.textureRegistry
        channel = MethodChannel(binding.binaryMessenger, "deepar_plugin")
        channel.setMethodCallHandler(this)
    }
    
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
    
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        // Initialize gender classifier
        try {
            genderClassifier = GenderClassifier(binding.activity)
        } catch (e: Exception) {
            android.util.Log.e("DeepARPlugin", "Failed to init GenderClassifier: ${e.message}")
        }
    }
    
    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }
    
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }
    
    override fun onDetachedFromActivity() {
        cleanup()
        activity = null
    }
    
    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "initialize" -> {
                val licenseKey = call.argument<String>("licenseKey") ?: ""
                initialize(licenseKey, result)
            }
            "startCamera" -> {
                startCamera(result)
            }
            "switchCamera" -> {
                switchCamera(result)
            }
            "switchEffect" -> {
                val effectName = call.argument<String>("effectName")
                switchEffect(effectName, result)
            }
            // nextEffect and previousEffect removed - all effect switching
            // is now handled dynamically from Flutter via switchEffect
            "takeScreenshot" -> {
                takeScreenshot(result)
            }
            "startRecording" -> {
                startRecording(result)
            }
            "stopRecording" -> {
                stopRecording(result)
            }
            "dispose" -> {
                cleanup()
                result.success(null)
            }
            "setClassificationEnabled" -> {
                classificationEnabled = call.argument<Boolean>("enabled") ?: true
                result.success(true)
            }
            else -> {
                result.notImplemented()
            }
        }
    }
    
    private fun initialize(licenseKey: String, result: Result) {
        try {
            activity?.let { act ->
                deepAR = DeepAR(act)
                deepAR?.setLicenseKey(licenseKey)
                deepAR?.initialize(act, this)
                result.success(true)
            } ?: result.error("NO_ACTIVITY", "Activity not available", null)
        } catch (e: Exception) {
            result.error("INIT_ERROR", e.message, null)
        }
    }
    
    private fun startCamera(result: Result) {
        activity?.let { act ->
            // Create texture for rendering - use PORTRAIT dimensions (1080x1920)
            textureEntry = textureRegistry.createSurfaceTexture()
            val surfaceTexture = textureEntry!!.surfaceTexture()
            surfaceTexture.setDefaultBufferSize(1080, 1920)
            
            // Set DeepAR to render to this surface in PORTRAIT mode
            deepAR?.setRenderSurface(android.view.Surface(surfaceTexture), 1080, 1920)
            
            cameraProviderFuture = ProcessCameraProvider.getInstance(act)
            cameraProviderFuture?.addListener({
                try {
                    val cameraProvider = cameraProviderFuture?.get()
                    cameraProvider?.let { bindCamera(it) }
                    // Return texture ID and PORTRAIT dimensions to Flutter
                    result.success(mapOf(
                        "textureId" to textureEntry!!.id().toInt(),
                        "width" to 1080,
                        "height" to 1920
                    ))
                } catch (e: ExecutionException) {
                    result.error("CAMERA_ERROR", e.message, null)
                } catch (e: InterruptedException) {
                    result.error("CAMERA_ERROR", e.message, null)
                }
            }, ContextCompat.getMainExecutor(act))
        } ?: result.error("NO_ACTIVITY", "Activity not available", null)
    }
    
    private fun bindCamera(cameraProvider: ProcessCameraProvider) {
        // Request portrait-oriented resolution (will be rotated by device)
        val cameraResolution = Size(1080, 1920)
        val cameraSelector = CameraSelector.Builder()
            .requireLensFacing(lensFacing)
            .build()
        
        // Initialize buffers for camera frames
        buffers = Array(NUMBER_OF_BUFFERS) {
            ByteBuffer.allocateDirect(cameraResolution.width * cameraResolution.height * 4).apply {
                order(ByteOrder.nativeOrder())
                position(0)
            }
        }
        
        val imageAnalysis = ImageAnalysis.Builder()
            .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
            .setTargetResolution(cameraResolution)
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .setTargetRotation(android.view.Surface.ROTATION_0) // Portrait orientation
            .build()
        
        imageAnalysis.setAnalyzer(ContextCompat.getMainExecutor(activity!!)) { image ->
            processImage(image)
        }
        
        cameraProvider.unbindAll()
        cameraProvider.bindToLifecycle(
            activity as LifecycleOwner,
            cameraSelector,
            imageAnalysis
        )
    }
    
    private fun processImage(image: ImageProxy) {
        // Only process frames if DeepAR is initialized
        if (!isDeepARInitialized) {
            image.close()
            return
        }
        
        val buffer = image.planes[0].buffer
        buffer.rewind()
        
        // Copy bitmap data for classification BEFORE any processing
        var classificationBitmap: Bitmap? = null
        frameCount++
        if (classificationEnabled && frameCount % CLASSIFY_EVERY_N_FRAMES == 0) {
            classificationBitmap = imageProxyToBitmap(image)
        }
        
        buffers?.let { bufs ->
            bufs[currentBuffer].clear()
            bufs[currentBuffer].put(buffer)
            bufs[currentBuffer].position(0)
            
            deepAR?.receiveFrame(
                bufs[currentBuffer],
                image.width,
                image.height,
                image.imageInfo.rotationDegrees,
                lensFacing == CameraSelector.LENS_FACING_FRONT,
                DeepARImageFormat.RGBA_8888,
                image.planes[0].pixelStride
            )
            
            currentBuffer = (currentBuffer + 1) % NUMBER_OF_BUFFERS
        }
        
        // Close image AFTER copying bitmap data
        image.close()
        
        // Gender classification (runs on background thread with already-copied bitmap)
        classificationBitmap?.let { bitmap ->
            classificationExecutor.execute {
                try {
                    genderClassifier?.classifyBitmap(bitmap)?.let { result ->
                        activity?.runOnUiThread {
                            channel.invokeMethod("onGenderClassified", mapOf(
                                "gender" to result.gender,
                                "confidence" to result.confidence
                            ))
                        }
                    }
                } catch (e: Exception) {
                    android.util.Log.e("DeepARPlugin", "Classification error: ${e.message}")
                } finally {
                    bitmap.recycle()
                }
            }
        }
    }
    
    /**
     * Convert ImageProxy (RGBA_8888) to Bitmap - must be called before image.close()
     * Applies rotation and mirroring for correct face orientation during classification
     */
    private fun imageProxyToBitmap(imageProxy: ImageProxy): Bitmap? {
        return try {
            val buffer = imageProxy.planes[0].buffer
            buffer.rewind()
            val bytes = ByteArray(buffer.remaining())
            buffer.get(bytes)
            
            var bitmap = Bitmap.createBitmap(
                imageProxy.width,
                imageProxy.height,
                Bitmap.Config.ARGB_8888
            )
            
            val pixelBuffer = ByteBuffer.wrap(bytes)
            bitmap.copyPixelsFromBuffer(pixelBuffer)
            
            // Apply rotation and mirroring for correct face orientation
            val rotationDegrees = imageProxy.imageInfo.rotationDegrees
            val needsTransform = rotationDegrees != 0 || lensFacing == CameraSelector.LENS_FACING_FRONT
            
            if (needsTransform) {
                val matrix = android.graphics.Matrix()
                
                // Apply rotation to correct for camera sensor orientation
                if (rotationDegrees != 0) {
                    matrix.postRotate(rotationDegrees.toFloat())
                }
                
                // Mirror for front camera (selfie mode)
                if (lensFacing == CameraSelector.LENS_FACING_FRONT) {
                    // Mirror horizontally after rotation
                    val newWidth = if (rotationDegrees == 90 || rotationDegrees == 270) bitmap.height else bitmap.width
                    matrix.postScale(-1f, 1f, newWidth / 2f, 0f)
                }
                
                val transformedBitmap = Bitmap.createBitmap(
                    bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true
                )
                
                // Recycle original if a new bitmap was created
                if (transformedBitmap != bitmap) {
                    bitmap.recycle()
                }
                
                android.util.Log.d("DeepARPlugin", "Bitmap transformed: rotation=$rotationDegrees, front=${ lensFacing == CameraSelector.LENS_FACING_FRONT}, size=${transformedBitmap.width}x${transformedBitmap.height}")
                transformedBitmap
            } else {
                bitmap
            }
        } catch (e: Exception) {
            android.util.Log.e("DeepARPlugin", "Failed to convert ImageProxy to Bitmap: ${e.message}")
            null
        }
    }
    
    private fun switchCamera(result: Result) {
        lensFacing = if (lensFacing == CameraSelector.LENS_FACING_FRONT) {
            CameraSelector.LENS_FACING_BACK
        } else {
            CameraSelector.LENS_FACING_FRONT
        }
        
        try {
            val cameraProvider = cameraProviderFuture?.get()
            cameraProvider?.unbindAll()
            cameraProvider?.let { bindCamera(it) }
            result.success(true)
        } catch (e: Exception) {
            result.error("SWITCH_ERROR", e.message, null)
        }
    }
    
    private fun getFilterPath(filterName: String): String? {
        // Handle 'none' for no effect
        if (filterName == "none") {
            android.util.Log.d("DeepARPlugin", "getFilterPath: 'none' - clearing effect")
            return null
        }
        
        android.util.Log.d("DeepARPlugin", "getFilterPath input: $filterName")
        
        // Check if this is already an absolute path (from synced assets)
        // Absolute paths start with / or contain :// (like file://)
        if (filterName.startsWith("/") || filterName.contains("://")) {
            // For absolute paths, use file:// protocol if not already present
            val result = if (filterName.startsWith("file://")) {
                filterName
            } else {
                "file://$filterName"
            }
            android.util.Log.d("DeepARPlugin", "getFilterPath absolute result: $result")
            
            // Verify file exists
            val filePath = result.removePrefix("file://")
            val file = java.io.File(filePath)
            android.util.Log.d("DeepARPlugin", "File exists: ${file.exists()}, readable: ${file.canRead()}, size: ${if(file.exists()) file.length() else 0}")
            
            return result
        }
        
        // For relative paths (bundled assets), prepend the flutter assets path
        // The filterName includes the subdirectory (e.g., "male/beard.deepar")
        val result = "file:///android_asset/flutter_assets/assets/effects/$filterName"
        android.util.Log.d("DeepARPlugin", "getFilterPath bundled result: $result")
        return result
    }
    
    private fun switchEffect(effectName: String?, result: Result) {
        android.util.Log.d("DeepARPlugin", "switchEffect called with: $effectName")
        effectName?.let {
            val path = getFilterPath(it)
            android.util.Log.d("DeepARPlugin", "switchEffect path: $path")
            deepAR?.switchEffect("effect", path)
            result.success(true)
        } ?: result.error("INVALID_EFFECT", "Effect name is null", null)
    }
    
    // nextEffect and previousEffect methods removed
    // All effect management is now handled dynamically from Flutter
    // via GenderEffectsService which loads effects from assets/effects/
    
    private fun takeScreenshot(result: Result) {
        deepAR?.takeScreenshot()
        result.success(true)
    }
    
    private fun startRecording(result: Result) {
        if (!recording) {
            val timestamp = SimpleDateFormat("yyyy_MM_dd_HH_mm_ss", Locale.getDefault()).format(Date())
            videoFileName = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES),
                "deepar_video_$timestamp.mp4"
            )
            
            deepAR?.startVideoRecording(videoFileName.toString(), 1920 / 2, 1080 / 2)
            recording = true
            result.success(videoFileName?.absolutePath)
        } else {
            result.error("ALREADY_RECORDING", "Already recording", null)
        }
    }
    
    private fun stopRecording(result: Result) {
        if (recording) {
            deepAR?.stopVideoRecording()
            recording = false
            result.success(videoFileName?.absolutePath)
        } else {
            result.error("NOT_RECORDING", "Not currently recording", null)
        }
    }
    
    private fun cleanup() {
        try {
            val cameraProvider = cameraProviderFuture?.get()
            cameraProvider?.unbindAll()
        } catch (e: Exception) {
            // Ignore
        }
        
        isDeepARInitialized = false
        deepAR?.setAREventListener(null)
        deepAR?.release()
        deepAR = null
        
        textureEntry?.release()
        textureEntry = null
        
        // Cleanup gender classifier
        genderClassifier?.close()
        genderClassifier = null
        classificationExecutor.shutdown()
    }
    
    // AREventListener implementations
    // All callbacks are called from background threads, so we need to use runOnUiThread
    // to invoke Flutter method channel calls on the main thread
    
    override fun screenshotTaken(bitmap: Bitmap?) {
        bitmap?.let {
            val timestamp = SimpleDateFormat("yyyy_MM_dd_HH_mm_ss", Locale.getDefault()).format(Date())
            val imageFile = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
                "deepar_image_$timestamp.jpg"
            )
            
            try {
                val outputStream = FileOutputStream(imageFile)
                it.compress(Bitmap.CompressFormat.JPEG, 100, outputStream)
                outputStream.flush()
                outputStream.close()
                
                activity?.runOnUiThread {
                    channel.invokeMethod("onScreenshotTaken", mapOf("path" to imageFile.absolutePath))
                }
            } catch (e: Exception) {
                activity?.runOnUiThread {
                    channel.invokeMethod("onError", mapOf("error" to e.message))
                }
            }
        }
    }
    
    override fun videoRecordingStarted() {
        activity?.runOnUiThread {
            channel.invokeMethod("onVideoRecordingStarted", null)
        }
    }
    
    override fun videoRecordingFinished() {
        activity?.runOnUiThread {
            channel.invokeMethod("onVideoRecordingFinished", null)
        }
    }
    
    override fun videoRecordingFailed() {
        activity?.runOnUiThread {
            channel.invokeMethod("onVideoRecordingFailed", null)
        }
    }
    
    override fun videoRecordingPrepared() {
        activity?.runOnUiThread {
            channel.invokeMethod("onVideoRecordingPrepared", null)
        }
    }
    
    override fun shutdownFinished() {
        activity?.runOnUiThread {
            channel.invokeMethod("onShutdownFinished", null)
        }
    }
    
    override fun initialized() {
        isDeepARInitialized = true
        // Don't apply any default effect - Flutter will handle effect selection
        // based on gender classification via GenderEffectsService
        activity?.runOnUiThread {
            channel.invokeMethod("onInitialized", null)
        }
    }
    
    override fun faceVisibilityChanged(visible: Boolean) {
        activity?.runOnUiThread {
            channel.invokeMethod("onFaceVisibilityChanged", mapOf("visible" to visible))
        }
    }
    
    override fun imageVisibilityChanged(gameObject: String?, visible: Boolean) {
        activity?.runOnUiThread {
            channel.invokeMethod("onImageVisibilityChanged", mapOf(
                "gameObject" to gameObject,
                "visible" to visible
            ))
        }
    }
    
    override fun frameAvailable(image: Image?) {
        // Not used in this implementation
    }
    
    override fun error(errorType: ARErrorType?, errorMessage: String?) {
        activity?.runOnUiThread {
            channel.invokeMethod("onError", mapOf(
                "errorType" to errorType?.toString(),
                "errorMessage" to errorMessage
            ))
        }
    }
    
    override fun effectSwitched(effectName: String?) {
        activity?.runOnUiThread {
            channel.invokeMethod("onEffectSwitched", mapOf("effectName" to effectName))
        }
    }
}