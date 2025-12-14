package com.example.morphy

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.util.Log
import androidx.camera.core.ImageProxy
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetector
import com.google.mlkit.vision.face.FaceDetectorOptions
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.support.common.FileUtil
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Gender classification result
 */
data class GenderResult(
    val gender: String,      // "male" or "female"
    val confidence: Float    // 0.0 to 1.0
)

/**
 * Gender classifier using TensorFlow Lite and ML Kit Face Detection
 */
class GenderClassifier(private val context: Context) {
    
    companion object {
        private const val TAG = "GenderClassifier"
        private const val MODEL_FILE = "GenderClass_06_03-20-08.tflite"
        private const val INPUT_SIZE = 224  // MobileNet input size
        private const val PIXEL_SIZE = 3    // RGB
    }
    
    private var interpreter: Interpreter? = null
    private var faceDetector: FaceDetector? = null
    private var isInitialized = false
    
    init {
        try {
            // Load TFLite model
            val modelBuffer = FileUtil.loadMappedFile(context, MODEL_FILE)
            val options = Interpreter.Options().apply {
                setNumThreads(2)
            }
            interpreter = Interpreter(modelBuffer, options)
            
            // Initialize ML Kit Face Detector with fast performance mode
            val faceDetectorOptions = FaceDetectorOptions.Builder()
                .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
                .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_NONE)
                .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_NONE)
                .setMinFaceSize(0.15f)
                .build()
            faceDetector = FaceDetection.getClient(faceDetectorOptions)
            
            isInitialized = true
            Log.d(TAG, "GenderClassifier initialized successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize GenderClassifier: ${e.message}")
            isInitialized = false
        }
    }
    
    /**
     * Classify gender from an ImageProxy (CameraX frame)
     * This method is synchronous and should be called from a background thread
     * @deprecated Use classifyBitmap instead for thread safety
     */
    fun classify(imageProxy: ImageProxy): GenderResult? {
        if (!isInitialized) {
            Log.w(TAG, "Classifier not initialized")
            return null
        }
        
        try {
            // Convert ImageProxy to Bitmap
            val bitmap = imageProxyToBitmap(imageProxy) ?: return null
            return classifyBitmap(bitmap)
        } catch (e: Exception) {
            Log.e(TAG, "Classification failed: ${e.message}")
            return null
        }
    }
    
    /**
     * Classify gender from a Bitmap
     * This is the preferred method - the bitmap should be created before ImageProxy is closed
     */
    fun classifyBitmap(bitmap: Bitmap): GenderResult? {
        if (!isInitialized) {
            Log.w(TAG, "Classifier not initialized")
            return null
        }
        
        Log.d(TAG, "classifyBitmap called, bitmap size: ${bitmap.width}x${bitmap.height}")
        
        try {
            // Create InputImage for ML Kit
            val inputImage = InputImage.fromBitmap(bitmap, 0)
            Log.d(TAG, "InputImage created successfully")
            
            // Detect faces synchronously using a latch
            val latch = CountDownLatch(1)
            var detectedFaces: List<Face>? = null
            
            faceDetector?.process(inputImage)
                ?.addOnSuccessListener { faces ->
                    Log.d(TAG, "Face detection success: found ${faces.size} faces")
                    detectedFaces = faces
                    latch.countDown()
                }
                ?.addOnFailureListener { e ->
                    Log.e(TAG, "Face detection failed: ${e.message}")
                    latch.countDown()
                }
            
            // Wait for face detection (max 500ms)
            if (!latch.await(500, TimeUnit.MILLISECONDS)) {
                Log.w(TAG, "Face detection timed out")
                return null
            }
            
            Log.d(TAG, "Face detection completed, faces: ${detectedFaces?.size ?: 0}")
            
            // Get the largest face
            val face = detectedFaces?.maxByOrNull { 
                it.boundingBox.width() * it.boundingBox.height() 
            }
            
            if (face == null) {
                Log.d(TAG, "No face found in frame")
                return null
            }
            
            Log.d(TAG, "Face found at: ${face.boundingBox}")
            
            // Crop face region
            val faceBitmap = cropFace(bitmap, face.boundingBox)
            if (faceBitmap == null) {
                Log.e(TAG, "Failed to crop face")
                return null
            }
            
            Log.d(TAG, "Face cropped: ${faceBitmap.width}x${faceBitmap.height}")
            
            // Preprocess for model
            val inputBuffer = preprocessImage(faceBitmap)
            Log.d(TAG, "Image preprocessed")
            
            // Run inference
            val outputBuffer = Array(1) { FloatArray(2) }  // [female, male] probabilities
            interpreter?.run(inputBuffer, outputBuffer)
            
            // Get result - Index 0 = female, Index 1 = male (from original Python code)
            val femaleProb = outputBuffer[0][0]
            val maleProb = outputBuffer[0][1]
            
            val gender = if (maleProb > femaleProb) "male" else "female"
            val confidence = maxOf(maleProb, femaleProb)
            
            Log.d(TAG, "Classification: $gender (confidence: $confidence, male=$maleProb, female=$femaleProb)")
            return GenderResult(gender, confidence)
            
        } catch (e: Exception) {
            Log.e(TAG, "Classification failed: ${e.message}")
            e.printStackTrace()
            return null
        }
    }
    
    /**
     * Convert ImageProxy (RGBA_8888) to Bitmap
     */
    private fun imageProxyToBitmap(imageProxy: ImageProxy): Bitmap? {
        return try {
            val buffer = imageProxy.planes[0].buffer
            val bytes = ByteArray(buffer.remaining())
            buffer.get(bytes)
            
            val bitmap = Bitmap.createBitmap(
                imageProxy.width,
                imageProxy.height,
                Bitmap.Config.ARGB_8888
            )
            
            val pixelBuffer = ByteBuffer.wrap(bytes)
            bitmap.copyPixelsFromBuffer(pixelBuffer)
            bitmap
        } catch (e: Exception) {
            Log.e(TAG, "Failed to convert ImageProxy to Bitmap: ${e.message}")
            null
        }
    }
    
    /**
     * Crop face region from bitmap with padding
     */
    private fun cropFace(bitmap: Bitmap, boundingBox: Rect): Bitmap? {
        return try {
            // Add 20% padding around the face
            val padding = (boundingBox.width() * 0.2f).toInt()
            
            val left = maxOf(0, boundingBox.left - padding)
            val top = maxOf(0, boundingBox.top - padding)
            val right = minOf(bitmap.width, boundingBox.right + padding)
            val bottom = minOf(bitmap.height, boundingBox.bottom + padding)
            
            val width = right - left
            val height = bottom - top
            
            if (width <= 0 || height <= 0) return null
            
            Bitmap.createBitmap(bitmap, left, top, width, height)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to crop face: ${e.message}")
            null
        }
    }
    
    /**
     * Preprocess image for MobileNet model
     * Resize to 224x224 and normalize pixel values
     * Uses BGR order to match OpenCV (cv2.imread) used in training
     */
    private fun preprocessImage(bitmap: Bitmap): ByteBuffer {
        val scaledBitmap = Bitmap.createScaledBitmap(bitmap, INPUT_SIZE, INPUT_SIZE, true)
        
        val inputBuffer = ByteBuffer.allocateDirect(4 * INPUT_SIZE * INPUT_SIZE * PIXEL_SIZE)
        inputBuffer.order(ByteOrder.nativeOrder())
        inputBuffer.rewind()
        
        val pixels = IntArray(INPUT_SIZE * INPUT_SIZE)
        scaledBitmap.getPixels(pixels, 0, INPUT_SIZE, 0, 0, INPUT_SIZE, INPUT_SIZE)
        
        for (pixel in pixels) {
            // Extract BGR (not RGB!) and normalize to [0, 1]
            // OpenCV uses BGR order, which was used to train the model
            val r = ((pixel shr 16) and 0xFF) / 255.0f
            val g = ((pixel shr 8) and 0xFF) / 255.0f
            val b = (pixel and 0xFF) / 255.0f
            
            // Write in BGR order to match training data
            inputBuffer.putFloat(b)
            inputBuffer.putFloat(g)
            inputBuffer.putFloat(r)
        }
        
        return inputBuffer
    }
    
    /**
     * Release resources
     */
    fun close() {
        try {
            interpreter?.close()
            faceDetector?.close()
            isInitialized = false
            Log.d(TAG, "GenderClassifier closed")
        } catch (e: Exception) {
            Log.e(TAG, "Error closing GenderClassifier: ${e.message}")
        }
    }
}
