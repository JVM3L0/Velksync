package com.velksync.velksync

import android.app.Activity
import android.app.AlertDialog
import android.content.res.Configuration
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import kotlin.concurrent.thread

/**
 * "Ligar <PC>?" ao tocar no botão do widget, como o app pede antes das ações
 * de energia. Só um diálogo sobre a tela inicial, sem abrir o app. Não
 * exportada: só o PendingIntent do widget chega aqui.
 */
class ConfirmWakeActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val id = intent.getStringExtra(WakeWidget.EXTRA_DEVICE)
        val target = Wol.devices(this).firstOrNull { it.id == id && it.mac != null }
        if (target == null) {
            finish()
            return
        }
        val night = (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        val theme = if (night) android.R.style.Theme_DeviceDefault_Dialog_Alert else android.R.style.Theme_DeviceDefault_Light_Dialog_Alert
        AlertDialog.Builder(this, theme)
            .setTitle("Ligar ${target.name}?")
            .setMessage("Envia o sinal de Wake-on-LAN para o PC.")
            .setNegativeButton("Cancelar", null)
            .setPositiveButton("Ligar") { _, _ -> wake(target) }
            .setOnDismissListener { if (!isChangingConfigurations) finish() }
            .show()
    }

    private fun wake(target: Wol.Device) {
        val app = applicationContext
        thread(name = "velksync-widget-wol") {
            val ok = runCatching { Wol.send(target) }.isSuccess
            if (ok) WakeWidget.markSent(app, target.id)
            Handler(Looper.getMainLooper()).post {
                val msg = if (ok) "Sinal enviado a ${target.name}" else "Falha ao enviar o sinal"
                Toast.makeText(app, msg, Toast.LENGTH_SHORT).show()
                WakeWidget.refresh(app)
            }
        }
    }
}
