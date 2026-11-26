package com.velksync.velksync

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import java.io.File

/** Instala a atualização do app por uma sessão do PackageInstaller. Do Android
 *  12 em diante, um app que atualiza a si mesmo pode dispensar a tela de
 *  confirmação; o Android ainda pode exigi-la, e só aceita a mesma assinatura.
 *  Instalando por cima, o sistema encerra o app. */
object ApkInstaller {
    /** Para a activity: "confirm" (com a tela do sistema) ou "failed". */
    var listener: ((status: String, detail: Any?) -> Unit)? = null

    /** Sessão em andamento; o resultado de uma abandonada não vale mais. */
    @Volatile
    var current = -1

    /** Copia o APK para a sessão e a confirma. Chamar fora da thread da tela. */
    fun commit(context: Context, apk: File) {
        val installer = context.packageManager.packageInstaller
        current = -1
        // Sobras de uma tentativa interrompida ocupam espaço.
        installer.mySessions.forEach { runCatching { installer.abandonSession(it.sessionId) } }
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
            setAppPackageName(context.packageName)
            setSize(apk.length())
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
            }
        }
        val id = installer.createSession(params)
        current = id
        try {
            installer.openSession(id).use { session ->
                session.openWrite("velksync.apk", 0, apk.length()).use { out ->
                    apk.inputStream().use { it.copyTo(out) }
                    session.fsync(out)
                }
                // Mutável: o sistema acrescenta o resultado. O intent é explícito.
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
                val status = PendingIntent.getBroadcast(context, id, Intent(context, InstallReceiver::class.java), flags)
                session.commit(status.intentSender)
            }
        } catch (e: Exception) {
            runCatching { installer.abandonSession(id) }
            throw e
        }
    }
}

/** Resultado da sessão; não exportado, só o sistema chega aqui pelo PendingIntent. */
class InstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.getIntExtra(PackageInstaller.EXTRA_SESSION_ID, -1) != ApkInstaller.current) return
        when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                @Suppress("DEPRECATION")
                val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                ApkInstaller.listener?.invoke("confirm", confirm)
            }
            PackageInstaller.STATUS_SUCCESS -> Unit // o app já foi encerrado
            else -> ApkInstaller.listener?.invoke("failed", status)
        }
    }
}
