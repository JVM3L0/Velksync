package com.velksync.velksync

import android.os.Build
import android.os.Handler
import android.os.Looper
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.widget.Toast
import kotlin.concurrent.thread

/**
 * Bloco "Ligar PC" das Configurações rápidas: manda o Wake-on-LAN direto do
 * Android, sem abrir o app. Só liga (ver [Wol]).
 */
class WakeTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        val target = Wol.target(this)
        qsTile?.apply {
            state = if (target == null) Tile.STATE_UNAVAILABLE else Tile.STATE_INACTIVE
            label = target?.let { "Ligar ${it.name}" } ?: "Ligar PC"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                subtitle = if (target == null) "Cadastre um PC com MAC" else null
            }
            updateTile()
        }
    }

    override fun onClick() {
        super.onClick()
        val target = Wol.target(this) ?: return
        thread(name = "velksync-wol") {
            val ok = runCatching { Wol.send(target) }.isSuccess
            val msg = if (ok) "Sinal enviado a ${target.name}" else "Falha ao enviar o sinal"
            Handler(Looper.getMainLooper()).post { Toast.makeText(this, msg, Toast.LENGTH_SHORT).show() }
        }
    }
}
