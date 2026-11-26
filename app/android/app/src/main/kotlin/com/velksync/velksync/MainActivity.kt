package com.velksync.velksync

import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var launch: Map<String, String?>? = null // toque no widget, até o app pegar
    private var shared: String? = null // texto do menu Compartilhar, até o app pegar
    private var shareChannel: MethodChannel? = null
    private var updateChannel: MethodChannel? = null
    private var resumed = false
    private var confirmInstall: Intent? = null // tela do sistema esperando o app voltar

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
        updateChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "velksync/update").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "abis" -> result.success(Build.SUPPORTED_ABIS.toList())
                    "dir" -> result.success(updatesDir().path)
                    "install" -> install(call.argument<String>("path"), result)
                    else -> result.notImplemented()
                }
            }
        }
        ApkInstaller.listener = ::onInstallStatus
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        ApkInstaller.listener = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onResume() {
        super.onResume()
        resumed = true
        confirmInstall?.let(::askToInstall)
    }

    override fun onPause() {
        resumed = false
        super.onPause()
    }

    private fun updatesDir() = File(cacheDir, "updates").apply { mkdirs() }

    /** Instala um APK da pasta de atualizações. Sem a permissão de instalar
     *  apps desta fonte, abre a tela para liberar e responde false. true: a
     *  sessão foi entregue ao Android e o resto chega por "status". */
    private fun install(path: String?, result: MethodChannel.Result) {
        val file = path?.let { File(it).canonicalFile }
        require(file != null && file.isFile && file.name.endsWith(".apk") &&
            file.parentFile == updatesDir().canonicalFile) { "APK fora da pasta de atualizações" }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
            result.success(false)
            return
        }
        confirmInstall = null
        val context = applicationContext
        thread {
            try {
                ApkInstaller.commit(context, file)
                runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                runOnUiThread { result.error("install", e.message, null) }
            }
        }
    }

    private fun onInstallStatus(status: String, detail: Any?) {
        if (status == "confirm") {
            val confirm = detail as? Intent ?: return sendStatus("failed", "O Android não abriu a confirmação")
            // Avisa já (o Android respondeu); a tela abre quando o app voltar.
            sendStatus("confirm", null)
            if (resumed) askToInstall(confirm) else confirmInstall = confirm
            return
        }
        sendStatus(
            "failed",
            when (detail) {
                PackageInstaller.STATUS_FAILURE_ABORTED -> "A instalação foi cancelada"
                PackageInstaller.STATUS_FAILURE_BLOCKED -> "O Android ou o Play Protect bloqueou a instalação"
                PackageInstaller.STATUS_FAILURE_CONFLICT -> "O app instalado tem outra assinatura"
                PackageInstaller.STATUS_FAILURE_INCOMPATIBLE -> "Esta versão não serve para este celular"
                PackageInstaller.STATUS_FAILURE_INVALID -> "O arquivo foi recusado como inválido"
                PackageInstaller.STATUS_FAILURE_STORAGE -> "Falta espaço no celular"
                else -> "O Android não conseguiu instalar"
            },
        )
    }

    private fun askToInstall(confirm: Intent) {
        confirmInstall = null
        try {
            startActivity(confirm)
        } catch (e: Exception) {
            sendStatus("failed", "O Android não abriu a confirmação")
        }
    }

    private fun sendStatus(status: String, message: String?) {
        updateChannel?.invokeMethod("status", mapOf("status" to status, "message" to message))
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
