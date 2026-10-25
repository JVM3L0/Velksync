package com.velksync.velksync

import android.os.Build
import android.os.Handler
import android.os.Looper
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.widget.Toast
import org.json.JSONArray
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import kotlin.concurrent.thread

/**
 * Bloco "Ligar PC" das Configurações rápidas: manda o Wake-on-LAN direto do
 * Android, sem abrir o app. De propósito só liga: lê apenas nome, MAC e
 * broadcast (nada de token) e não tem como desligar ou executar comandos.
 */
class WakeTileService : TileService() {
    private data class Target(val name: String, val mac: ByteArray, val broadcast: String)

    override fun onStartListening() {
        super.onStartListening()
        val target = target()
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
        val target = target() ?: return
        thread(name = "velksync-wol") {
            val ok = runCatching { sendMagicPacket(target) }.isSuccess
            val msg = if (ok) "Sinal enviado a ${target.name}" else "Falha ao enviar o sinal"
            Handler(Looper.getMainLooper()).post { Toast.makeText(this, msg, Toast.LENGTH_SHORT).show() }
        }
    }

    /** O PC escolhido nas configurações do app, ou o primeiro com MAC. */
    private fun target(): Target? {
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val chosen = prefs.getString("flutter.tile_device", null)
        val list = runCatching { JSONArray(prefs.getString("flutter.devices", null) ?: return null) }.getOrNull()
            ?: return null
        val devices = (0 until list.length()).mapNotNull { list.optJSONObject(it) }
            .filter { parseMac(it.optString("mac")) != null }
        val d = devices.firstOrNull { it.optString("id") == chosen } ?: devices.firstOrNull() ?: return null
        return Target(
            d.optString("name", "PC"),
            parseMac(d.optString("mac"))!!,
            d.optString("broadcast").ifEmpty { "255.255.255.255" },
        )
    }

    private fun parseMac(mac: String): ByteArray? {
        val hex = mac.filter { it.isLetterOrDigit() }
        if (hex.length != 12 || !hex.all { it in '0'..'9' || it.lowercaseChar() in 'a'..'f' }) return null
        return ByteArray(6) { hex.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
    }

    /** Mesmo pacote do app: 6 x 0xFF e o MAC 16 vezes, repetido nas portas 9 e 7. */
    private fun sendMagicPacket(t: Target) {
        val packet = ByteArray(6) { 0xFF.toByte() } + (1..16).flatMap { t.mac.toList() }
        DatagramSocket().use { socket ->
            socket.broadcast = true
            val targets = setOf(t.broadcast, "255.255.255.255").map(InetAddress::getByName)
            repeat(3) {
                for (addr in targets) {
                    for (port in intArrayOf(9, 7)) socket.send(DatagramPacket(packet, packet.size, addr, port))
                }
                Thread.sleep(100)
            }
        }
    }
}
