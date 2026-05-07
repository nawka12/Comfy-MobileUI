package com.kayfahaarukku.comfymobile

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.ContentValues
import android.os.Environment
import android.provider.MediaStore
import java.io.File

class MainActivity : FlutterActivity() {
    private val saveImageChannel = "com.kayfahaarukku.comfymobile/save_image"
    private val serviceChannel = "com.kayfahaarukku.comfymobile/foreground_service"
    private val secureWindowChannel = "com.kayfahaarukku.comfymobile/secure_window"
    private var pendingServiceResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Apply the persisted secure-window setting before the first frame so
        // the system snapshot used in the app switcher is already redacted.
        val prefs = getSharedPreferences(SECURE_PREFS, Context.MODE_PRIVATE)
        if (prefs.getBoolean(SECURE_PREF_KEY, false)) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE,
            )
        }
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, saveImageChannel).setMethodCallHandler { call, result ->
            if (call.method == "saveToPublicGallery") {
                val sourcePath = call.argument<String>("sourcePath") ?: ""
                val destPath = saveToPublicGallery(sourcePath)
                result.success(destPath)
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, serviceChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    pendingServiceResult = result
                    startForegroundService()
                }
                "stop" -> {
                    val intent = Intent(this, ForegroundService::class.java)
                    intent.action = ForegroundService.ACTION_STOP
                    startService(intent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, secureWindowChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecure" -> {
                    val secure = call.argument<Boolean>("secure") ?: false
                    runOnUiThread {
                        if (secure) {
                            window.setFlags(
                                WindowManager.LayoutParams.FLAG_SECURE,
                                WindowManager.LayoutParams.FLAG_SECURE,
                            )
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                    }
                    getSharedPreferences(SECURE_PREFS, Context.MODE_PRIVATE)
                        .edit()
                        .putBoolean(SECURE_PREF_KEY, secure)
                        .apply()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                doStartService()
                pendingServiceResult?.success(true)
            } else {
                pendingServiceResult?.success(false)
            }
            pendingServiceResult = null
        }
    }

    private fun startForegroundService() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
                doStartService()
                pendingServiceResult?.success(true)
                pendingServiceResult = null
            } else {
                requestPermissions(
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    PERMISSION_REQUEST_CODE
                )
            }
        } else {
            doStartService()
            pendingServiceResult?.success(true)
            pendingServiceResult = null
        }
    }

    private fun doStartService() {
        val intent = Intent(this, ForegroundService::class.java)
        startForegroundService(intent)
    }

    // ---- image save helpers ----

    private fun saveToPublicGallery(sourcePath: String): String? {
        val sourceFile = File(sourcePath)
        if (!sourceFile.exists()) return null

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveViaMediaStore(sourceFile)
        } else {
            saveViaLegacyStorage(sourceFile)
        }
    }

    private fun saveViaMediaStore(sourceFile: File): String? {
        return try {
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, sourceFile.name)
                put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/ComfyMobile")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            if (uri != null) {
                contentResolver.openOutputStream(uri)?.use { outputStream ->
                    sourceFile.inputStream().use { inputStream ->
                        inputStream.copyTo(outputStream)
                    }
                }
                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
                contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val data = cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATA))
                        return data
                    }
                }
            }
            null
        } catch (_: Exception) {
            null
        }
    }

    private fun saveViaLegacyStorage(sourceFile: File): String? {
        return try {
            val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
            val targetDir = File(dir, "ComfyMobile")
            targetDir.mkdirs()
            val destFile = File(targetDir, sourceFile.name)
            sourceFile.copyTo(destFile, overwrite = true)
            destFile.absolutePath
        } catch (_: Exception) {
            null
        }
    }

    companion object {
        private const val PERMISSION_REQUEST_CODE = 1001
        private const val SECURE_PREFS = "secure_window_prefs"
        private const val SECURE_PREF_KEY = "secure_window_enabled"
    }
}
