package com.velksync.velksync

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class WidgetThemeTest {
    // Color.parseColor é do Android; aqui, um parser simples de #AARRGGBB.
    private val parse: (String) -> Int = { it.removePrefix("#").toLong(16).toInt() }

    private fun colors(prefix: String) = listOf(
        "bg", "text", "subtext", "icon_bg", "icon", "button", "on_button",
        "button_off", "on_button_off", "danger", "on_danger",
    ).withIndex().joinToString(",") { (i, k) -> "\"$k\":\"#ff${prefix}000${i.toString(16)}\"" }

    private fun json(mode: String) = "{\"mode\":\"$mode\",\"light\":{${colors("aa")}},\"dark\":{${colors("11")}}}"

    @Test
    fun followsTheModeChosenInTheApp() {
        assertEquals(parse("#ff11000" + "0"), WidgetTheme.pick(json("dark"), systemDark = false, parse)!!.bg)
        assertEquals(parse("#ffaa000" + "0"), WidgetTheme.pick(json("light"), systemDark = true, parse)!!.bg)
    }

    @Test
    fun systemModeUsesTheDeviceNightSetting() {
        assertEquals(parse("#ff11000a"), WidgetTheme.pick(json("system"), systemDark = true, parse)!!.onDanger)
        assertEquals(parse("#ffaa0005"), WidgetTheme.pick(json("system"), systemDark = false, parse)!!.button)
    }

    @Test
    fun noThemeOrBrokenJsonKeepsSystemColors() {
        assertNull(WidgetTheme.pick(null, systemDark = true, parse))
        assertNull(WidgetTheme.pick("", systemDark = true, parse))
        assertNull(WidgetTheme.pick("{lixo", systemDark = true, parse))
        assertNull(WidgetTheme.pick("{\"mode\":\"dark\",\"dark\":{\"bg\":\"#ff000000\"}}", systemDark = true, parse))
    }
}
