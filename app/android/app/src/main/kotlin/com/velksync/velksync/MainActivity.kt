package com.velksync.velksync

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var launch: Map<String, String?>? = null // toque no widget, até o app pegar

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        launch = intent?.let(::fromWidget)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "velksync/widget").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "refresh" -> {
                        WakeWidget.refresh(this@MainActivity)
                        result.success(null)
                    }
                    "takeLaunch" -> {
                        result.success(launch)
                        launch = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        fromWidget(intent)?.let { channel?.invokeMethod("open", it) }
    }

    /** PC e ação pedidos pelo widget. Qualquer app pode abrir esta activity: o
     *  app só navega e sempre pede confirmação antes de desligar. */
    private fun fromWidget(intent: Intent): Map<String, String?>? {
        val id = intent.getStringExtra(WakeWidget.EXTRA_DEVICE) ?: return null
        return mapOf("device" to id, "action" to intent.getStringExtra(WakeWidget.EXTRA_ACTION))
    }
}
