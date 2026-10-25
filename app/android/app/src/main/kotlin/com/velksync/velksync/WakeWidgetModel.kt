package com.velksync.velksync

import org.json.JSONObject

/** O que o botão do widget faz. */
enum class WidgetAction { WAKE, SHUTDOWN, NONE }

/** O que o widget mostra; separado do Android para ser testável. */
data class WidgetView(
    val deviceId: String?,
    val title: String,
    val status: String,
    val action: WidgetAction,
    val waking: Boolean,
)

object WakeWidgetModel {
    /** Depois de mandar o sinal, mostra "enviado" por este tempo (o mesmo que o app espera). */
    const val WAKE_WINDOW_MS = 120_000L

    /**
     * [stateJson] é o que o app grava em `widget_state`:
     * `{"<id>": {"power": "online|awaitingLogin|offline", "at": <epoch ms>}}`.
     * O widget não pergunta ao PC: mostra o último estado que o app viu e quando.
     * [time] formata um instante já com a preposição ("às 16:40", "em 24/10").
     */
    fun build(
        devicesJson: String?,
        chosen: String?,
        stateJson: String?,
        wakeAt: (String) -> Long,
        now: Long,
        time: (Long) -> String,
    ): WidgetView {
        val devices = Wol.parseDevices(devicesJson)
        val d = devices.firstOrNull { it.id == chosen }
            ?: devices.firstOrNull { it.mac != null }
            ?: devices.firstOrNull()
            ?: return WidgetView(null, "Adicionar PC", "Toque para abrir o Velksync", WidgetAction.NONE, waking = false)
        val st = runCatching { JSONObject(stateJson ?: "{}").optJSONObject(d.id) }.getOrNull()
        val power = st?.optString("power").orEmpty()
        val at = st?.optLong("at") ?: 0L
        val on = power == "online" || power == "awaitingLogin"
        val sent = wakeAt(d.id)
        // Sinal recente e o app ainda não viu o PC ligado depois dele.
        val waking = d.mac != null && sent > 0 && now - sent < WAKE_WINDOW_MS && !(on && at >= sent)
        val status = when {
            waking -> "Sinal enviado ${time(sent)}"
            at == 0L -> if (d.mac == null) "Abra o app com o PC ligado" else "Toque no botão para ligar"
            power == "online" -> "● Ligado · visto ${time(at)}"
            power == "awaitingLogin" -> "Aguardando login · visto ${time(at)}"
            else -> "○ Desligado · visto ${time(at)}"
        }
        // Ligado: desligar (o app confirma e confere o estado de verdade).
        // Aguardando login: o agente não roda, então não há o que fazer daqui.
        val action = when {
            waking -> WidgetAction.NONE
            power == "online" -> WidgetAction.SHUTDOWN
            !on && d.mac != null -> WidgetAction.WAKE
            else -> WidgetAction.NONE
        }
        return WidgetView(d.id, d.name, status, action, waking = waking)
    }
}
