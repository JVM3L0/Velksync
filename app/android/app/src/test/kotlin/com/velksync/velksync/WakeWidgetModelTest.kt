package com.velksync.velksync

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Lê os mesmos arquivos que o teste do app (test/fixtures) gera e confere. */
class WakeWidgetModelTest {
    private fun fixture(name: String) = File("../../test/fixtures/$name").readText()
    private val devices = fixture("devices.json")
    private val state = fixture("widget_state.json")
    private val seen = 1761400000000L
    private val time = { t: Long -> if (t == seen) "às 16:40" else "às 16:45" }

    private fun build(chosen: String?, wakeAt: Long = 0L, now: Long = seen + 60_000, st: String? = state) =
        WakeWidgetModel.build(devices, chosen, st, { wakeAt }, now, time)

    @Test fun ligadoComBotaoApagado() {
        val v = build("pc1")
        assertEquals("Velkhyro", v.title)
        assertEquals("● Ligado · visto às 16:40", v.status)
        assertFalse(v.canWake)
    }

    @Test fun desligadoSemMacNaoLiga() {
        val v = build("pc2")
        assertEquals("○ Desligado · visto às 16:40", v.status)
        assertFalse("sem MAC não há como ligar", v.canWake)
    }

    @Test fun desligadoComMacLiga() {
        val off = state.replace("\"online\"", "\"offline\"")
        assertTrue(build("pc1", st = off).canWake)
    }

    @Test fun sinalEnviadoMostraEsperaAteOAppVerOPcLigado() {
        val off = state.replace("\"online\"", "\"offline\"")
        val sent = seen + 300_000
        val v = build("pc1", wakeAt = sent, now = sent + 10_000, st = off)
        assertTrue(v.waking)
        assertEquals("Sinal enviado às 16:45", v.status)
        val later = build("pc1", wakeAt = sent, now = sent + WakeWidgetModel.WAKE_WINDOW_MS + 1, st = off)
        assertFalse("depois de 2 min volta ao normal", later.waking)
    }

    @Test fun semEscolhaUsaOPrimeiroComMac() = assertEquals("pc1", build(null).deviceId)

    @Test fun semPcCadastrado() {
        val v = WakeWidgetModel.build(null, null, null, { 0L }, seen, time)
        assertNull(v.deviceId)
        assertEquals("Adicionar PC", v.title)
    }

    @Test fun estadoCorrompidoNaoQuebra() {
        val v = build("pc1", st = "{lixo")
        assertEquals("Toque no botão para ligar", v.status)
    }
}
