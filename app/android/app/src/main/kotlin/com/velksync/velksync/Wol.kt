package com.velksync.velksync

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress

/**
 * Wake-on-LAN e a lista de PCs, compartilhados pelo bloco das Configurações
 * rápidas e pelo widget. De propósito lê só id, nome, MAC e broadcast do que
 * o app salva (o token fica no armazenamento seguro): daqui só dá para ligar.
 */
object Wol {
    class Device(val id: String, val name: String, val mac: ByteArray?, val broadcast: String)

    fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    fun devices(context: Context): List<Device> = parseDevices(prefs(context).getString("flutter.devices", null))

    /** O PC escolhido nas configurações do app, ou o primeiro com MAC. */
    fun target(context: Context): Device? {
        val withMac = devices(context).filter { it.mac != null }
        val chosen = prefs(context).getString("flutter.tile_device", null)
        return withMac.firstOrNull { it.id == chosen } ?: withMac.firstOrNull()
    }

    fun parseDevices(json: String?): List<Device> {
        val list = runCatching { JSONArray(json ?: return emptyList()) }.getOrNull() ?: return emptyList()
        return (0 until list.length()).mapNotNull { list.optJSONObject(it) }.map {
            Device(
                it.optString("id"),
                it.optString("name", "PC").ifEmpty { "PC" },
                parseMac(it.optString("mac")),
                it.optString("broadcast").ifEmpty { "255.255.255.255" },
            )
        }
    }

    fun parseMac(mac: String): ByteArray? {
        val hex = mac.filter { it.isLetterOrDigit() }
        if (hex.length != 12 || !hex.all { it in '0'..'9' || it.lowercaseChar() in 'a'..'f' }) return null
        return ByteArray(6) { hex.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
    }

    /** Mesmo pacote do app: 6 x 0xFF e o MAC 16 vezes, repetido nas portas 9 e 7. Bloqueia: chame fora da thread principal. */
    fun send(d: Device) {
        val mac = requireNotNull(d.mac) { "PC sem MAC" }
        val packet = ByteArray(6) { 0xFF.toByte() } + (1..16).flatMap { mac.toList() }
        DatagramSocket().use { socket ->
            socket.broadcast = true
            val targets = setOf(d.broadcast, "255.255.255.255").map(InetAddress::getByName)
            repeat(3) {
                for (addr in targets) {
                    for (port in intArrayOf(9, 7)) socket.send(DatagramPacket(packet, packet.size, addr, port))
                }
                Thread.sleep(100)
            }
        }
    }
}
