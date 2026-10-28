package com.velksync.velksync

import android.graphics.Color
import org.json.JSONObject

/** Cores do widget vindas do tema do app (prefs "widget_theme"). */
data class WidgetColors(
    val bg: Int,
    val text: Int,
    val subtext: Int,
    val iconBg: Int,
    val icon: Int,
    val button: Int,
    val onButton: Int,
    val buttonOff: Int,
    val onButtonOff: Int,
    val danger: Int,
    val onDanger: Int,
)

object WidgetTheme {
    /** As cores do modo atual; null sem tema gravado (dinâmico) ou com JSON
     *  inválido: o widget fica com as cores do sistema. [systemDark] é o modo
     *  do aparelho, usado quando o app segue o sistema. */
    fun pick(json: String?, systemDark: Boolean, parse: (String) -> Int = Color::parseColor): WidgetColors? {
        if (json.isNullOrBlank()) return null
        return runCatching {
            val o = JSONObject(json)
            val dark = when (o.optString("mode")) {
                "dark" -> true
                "light" -> false
                else -> systemDark
            }
            val c = o.getJSONObject(if (dark) "dark" else "light")
            fun col(k: String) = parse(c.getString(k))
            WidgetColors(
                bg = col("bg"), text = col("text"), subtext = col("subtext"),
                iconBg = col("icon_bg"), icon = col("icon"),
                button = col("button"), onButton = col("on_button"),
                buttonOff = col("button_off"), onButtonOff = col("on_button_off"),
                danger = col("danger"), onDanger = col("on_danger"),
            )
        }.getOrNull()
    }
}
