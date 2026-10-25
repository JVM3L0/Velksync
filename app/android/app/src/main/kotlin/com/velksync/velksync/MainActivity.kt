package com.velksync.velksync

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var launchDevice: String? = null // PC tocado no widget, até o app pegar

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        launchDevice = intent?.getStringExtra(WakeWidget.EXTRA_DEVICE)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "velksync/widget").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "refresh" -> {
                        WakeWidget.refresh(this@MainActivity)
                        result.success(null)
                    }
                    "takeLaunchDevice" -> {
                        result.success(launchDevice)
                        launchDevice = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intent.getStringExtra(WakeWidget.EXTRA_DEVICE)?.let { channel?.invokeMethod("openDevice", it) }
    }
}
