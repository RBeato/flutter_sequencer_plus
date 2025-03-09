package com.michaeljperri.flutter_sequencer

import android.Manifest
import android.app.Application
import android.content.Context
import android.content.res.AssetManager
import android.content.pm.PackageManager
import android.os.Build
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.io.FileOutputStream
import java.net.URLDecoder
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private const val CHANNEL_NAME = "flutter_sequencer"
private const val FLUTTER_ASSETS = "flutter_assets"

class FlutterSequencerPlugin: FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private val scope = CoroutineScope(Dispatchers.Main)
    private var activityBinding: ActivityPluginBinding? = null
    private val requiredPermissions = mutableListOf(
        Manifest.permission.MODIFY_AUDIO_SETTINGS,
        Manifest.permission.FOREGROUND_SERVICE,
    ).apply {
        if (Build.VERSION.SDK_INT >= 33) {
            add(Manifest.permission.READ_MEDIA_AUDIO)
            add(Manifest.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK)
        } else {
            add(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
    }
    private val audioEngine: AudioEngine = AudioEngine.getInstance()
    private var lifecycle: FlutterSequencerLifecycle? = null

    init {
        System.loadLibrary("flutter_sequencer")
    }

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
        lifecycle = FlutterSequencerLifecycle(audioEngine)
        
        (context as? Application)?.registerActivityLifecycleCallbacks(lifecycle)
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        lifecycle?.let { lifecycle ->
            (context as? Application)?.unregisterActivityLifecycleCallbacks(lifecycle)
        }
        audioEngine.pause()
        AudioService.stopService(context)
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        try {
            when (call.method) {
                "getPlatformVersion" -> {
                    result.success("Android ${android.os.Build.VERSION.RELEASE}")
                }
                "setupAssetManager" -> {
                    setupAssetManager(context.assets)
                    result.success(null)
                }
                "normalizeAssetDir" -> {
                    scope.launch {
                        try {
                            val assetDir = call.argument<String>("assetDir")
                                ?: throw IllegalArgumentException("assetDir is required")
                            
                            val normalizedPath = withContext(Dispatchers.IO) {
                                normalizeAssetDir(assetDir)
                            }
                            result.success(normalizedPath)
                        } catch (e: Exception) {
                            result.error("NORMALIZE_ERROR", e.message, null)
                        }
                    }
                }
                "listAudioUnits" -> {
                    result.success(emptyList<String>())
                }
                "play" -> {
                    if (checkAndRequestPermissions()) {
                        AudioService.startService(context)
                        audioEngine.play()
                        result.success(null)
                    } else {
                        throw SecurityException("Required permissions not granted")
                    }
                }
                "pause" -> {
                    audioEngine.pause()
                    AudioService.stopService(context)
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        } catch (e: Exception) {
            handleError(result, e)
        }
    }

    private fun normalizeAssetDir(assetDir: String): String? {
        val filesDir = context.filesDir
        return if (copyAssetDirOrFile(assetDir, filesDir)) {
            filesDir.resolve(assetDir).absolutePath
        } else {
            null
        }
    }

    private fun copyAssetFile(assetFilePath: String, outputDir: File): Boolean {
        return try {
            val inputStream = context.assets.open("$FLUTTER_ASSETS/$assetFilePath")
            val decodedAssetFilePath = URLDecoder.decode(assetFilePath, "UTF-8")
            val outputFile = outputDir.resolve(decodedAssetFilePath)

            outputFile.parentFile?.mkdirs()
            outputFile.createNewFile()

            inputStream.use { input ->
                FileOutputStream(outputFile).use { output ->
                    input.copyTo(output, 1024)
                }
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun copyAssetDirOrFile(assetPath: String, outputDir: File): Boolean {
        val paths = context.assets.list("$FLUTTER_ASSETS/$assetPath")
            ?: return false

        return if (paths.isEmpty()) {
            // It's a file
            copyAssetFile(assetPath, outputDir)
        } else {
            // It's a directory
            paths.all { copyAssetDirOrFile("$assetPath/$it", outputDir) }
        }
    }

    private fun checkAndRequestPermissions(): Boolean {
        val activity = activityBinding?.activity ?: return false
        
        val missingPermissions = requiredPermissions.filter {
            ContextCompat.checkSelfPermission(activity, it) != PackageManager.PERMISSION_GRANTED
        }

        return if (missingPermissions.isEmpty()) {
            true
        } else {
            ActivityCompat.requestPermissions(
                activity,
                missingPermissions.toTypedArray(),
                0
            )
            false
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityBinding = binding
    }

    override fun onDetachedFromActivity() {
        activityBinding = null
    }

    private external fun setupAssetManager(assetManager: AssetManager)

    private fun handleError(result: Result, error: Throwable) {
        when (error) {
            is SecurityException -> result.error(
                "PERMISSION_ERROR",
                "Required permissions not granted",
                error.message
            )
            is IllegalStateException -> result.error(
                "AUDIO_ERROR",
                "Audio system error",
                error.message
            )
            else -> result.error(
                "UNKNOWN_ERROR",
                "An unexpected error occurred",
                error.message
            )
        }
    }

    companion object {
        @JvmStatic
        fun registerWith(registrar: io.flutter.plugin.common.PluginRegistry.Registrar) {
            // Legacy V1 plugin registration - not needed for modern plugins
        }
    }
}
