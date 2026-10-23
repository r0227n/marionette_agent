package com.example.example

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
