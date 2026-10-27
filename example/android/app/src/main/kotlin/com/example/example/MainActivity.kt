package com.example.example

import android.content.ContentValues
import android.graphics.Bitmap
import android.graphics.Color
import android.Manifest
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.os.Build
import android.provider.MediaStore
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) return
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "marionette.example/nativeCapture")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "permission" -> requestPermissions(arrayOf(Manifest.permission.CAMERA), 57)
                    "seedPhoto" -> {
                        val values = ContentValues().apply {
                            put(MediaStore.Images.Media.DISPLAY_NAME, "marionette-dummy-${System.currentTimeMillis()}.png")
                            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                            put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Marionette")
                        }
                        if (Build.VERSION.SDK_INT < 29) {
                            result.error("UNSUPPORTED", "Dummy image fixture requires API 29", null)
                            return@setMethodCallHandler
                        }
                        val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                            ?: throw IllegalStateException("Cannot create fixture image")
                        val bitmap = Bitmap.createBitmap(64, 64, Bitmap.Config.ARGB_8888)
                        try {
                            bitmap.eraseColor(Color.rgb(30, 120, 210))
                            contentResolver.openOutputStream(uri)!!.use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                        } finally { bitmap.recycle() }
                    }
                    "photoPicker" -> {
                        if (Build.VERSION.SDK_INT < 33) {
                            result.error("UNSUPPORTED", "Photo Picker requires API 33", null)
                            return@setMethodCallHandler
                        }
                        startActivityForResult(Intent(MediaStore.ACTION_PICK_IMAGES).setType("image/*"), 58)
                    }
                    "documentPicker" -> startActivityForResult(
                        Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("image/*"), 59)
                    "secureOn" -> window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    "secureOff" -> window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    else -> { result.notImplemented(); return@setMethodCallHandler }
                }
                result.success(null)
            }
    }
}
