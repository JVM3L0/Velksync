package com.velksync.velksync

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var launch: Map<String, String?>? = null // toque no widget, até o app pegar
    private var shared: String? = null // texto do menu Compartilhar, até o app pegar
    private var shareChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        launch = intent?.let(::fromWidget)
        shared = intent?.let(::sharedText)
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "velksync/share").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "take" -> {
                        result.success(shared)
                        shared = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "velksync/update").setMethodCallHandler { call, result ->
            when (call.method) {
                "abis" -> result.success(Build.SUPPORTED_ABIS.toList())
                "dir" -> result.success(updatesDir().path)
                "install" -> result.success(install(call.argument<String>("path")))
                else -> result.notImplemented()
            }
        }
    }

    private fun updatesDir() = File(cacheDir, "updates").apply { mkdirs() }

    /** Abre o instalador do Android com um APK da pasta de atualizações. Sem a
     *  permissão de instalar apps desta fonte, abre a tela para liberar e
     *  devolve false. */
    private fun install(path: String?): Boolean {
        val file = path?.let { File(it).canonicalFile }
        require(file != null && file.isFile && file.name.endsWith(".apk") &&
            file.parentFile == updatesDir().canonicalFile) { "APK fora da pasta de atualizações" }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
            return false
        }
        val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
        startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
        )
        return true
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        fromWidget(intent)?.let { channel?.invokeMethod("open", it) }
        sharedText(intent)?.let { shareChannel?.invokeMethod("shared", it) }
    }

    /** Texto vindo do menu Compartilhar de outro app. Qualquer app pode mandar:
     *  o Velksync só mostra a escolha do PC; nada sai sem a pessoa confirmar. */
    private fun sharedText(intent: Intent): String? {
        if (intent.action != Intent.ACTION_SEND || intent.type != "text/plain") return null
        return intent.getStringExtra(Intent.EXTRA_TEXT)?.takeIf { it.isNotBlank() }?.take(64 * 1024)
    }

    /** PC e ação pedidos pelo widget. Qualquer app pode abrir esta activity: o
     *  app só navega e sempre pede confirmação antes de desligar. */
    private fun fromWidget(intent: Intent): Map<String, String?>? {
        val id = intent.getStringExtra(WakeWidget.EXTRA_DEVICE) ?: return null
        return mapOf("device" to id, "action" to intent.getStringExtra(WakeWidget.EXTRA_ACTION))
    }
}
