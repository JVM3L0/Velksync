package com.velksync.velksync

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.text.format.DateFormat
import android.text.format.DateUtils
import android.view.View
import android.widget.RemoteViews

/** Widget 2×1 "Ligar PC": nome, último estado visto pelo app e botão de ligar. */
class WakeWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) =
        WakeWidget.render(context, manager, ids)
}

/** Redesenho agendado depois do sinal. Não exportado: só o alarme do próprio app chega aqui. */
class WakeWidgetReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == WakeWidget.ACTION_REFRESH) WakeWidget.refresh(context)
    }
}

object WakeWidget {
    const val ACTION_REFRESH = "com.velksync.velksync.widget.REFRESH"
    const val EXTRA_DEVICE = "device_id"
    const val EXTRA_ACTION = "action" // "shutdown": o app abre já no "Desligar?"

    private fun local(context: Context) = context.getSharedPreferences("velksync_widget", Context.MODE_PRIVATE)

    /** Redesenha todos os widgets (o app chama ao ver o estado de um PC mudar). */
    fun refresh(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        render(context, manager, manager.getAppWidgetIds(ComponentName(context, WakeWidgetProvider::class.java)))
    }

    /** Guarda o envio e agenda um redesenho para quando a espera acabar. */
    fun markSent(context: Context, id: String) {
        val now = System.currentTimeMillis()
        local(context).edit().putLong("wake_$id", now).apply()
        val alarm = context.getSystemService(AlarmManager::class.java) ?: return
        val again = PendingIntent.getBroadcast(
            context, 2,
            Intent(context, WakeWidgetReceiver::class.java).setAction(ACTION_REFRESH),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        alarm.set(AlarmManager.RTC, now + WakeWidgetModel.WAKE_WINDOW_MS + 1000, again) // inexato: sem permissão extra
    }

    fun render(context: Context, manager: AppWidgetManager, ids: IntArray) {
        if (ids.isEmpty()) return
        val prefs = Wol.prefs(context)
        val now = System.currentTimeMillis()
        val view = WakeWidgetModel.build(
            prefs.getString("flutter.devices", null),
            prefs.getString("flutter.tile_device", null),
            prefs.getString("flutter.widget_state", null),
            wakeAt = { local(context).getLong("wake_$it", 0L) },
            now = now,
            time = { t ->
                if (DateUtils.isToday(t)) "às ${DateFormat.getTimeFormat(context).format(t)}"
                else "em ${DateUtils.formatDateTime(context, t, DateUtils.FORMAT_SHOW_DATE or DateUtils.FORMAT_NUMERIC_DATE)}"
            },
        )
        val rv = RemoteViews(context.packageName, R.layout.widget_wake)
        rv.setTextViewText(R.id.widget_title, view.title)
        rv.setTextViewText(R.id.widget_status, view.status)
        rv.setViewVisibility(R.id.widget_power, if (view.waking) View.GONE else View.VISIBLE)
        rv.setViewVisibility(R.id.widget_progress, if (view.waking) View.VISIBLE else View.GONE)
        rv.setViewVisibility(R.id.widget_icon, if (view.deviceId == null) View.GONE else View.VISIBLE)
        if (view.deviceId == null) rv.setViewVisibility(R.id.widget_power, View.GONE)
        val active = view.action != WidgetAction.NONE
        rv.setBoolean(R.id.widget_power, "setEnabled", active)
        rv.setInt(R.id.widget_power, "setImageAlpha", if (active) 255 else 97)
        rv.setInt(
            R.id.widget_power, "setBackgroundResource",
            when (view.action) {
                WidgetAction.WAKE -> R.drawable.widget_button_bg
                WidgetAction.SHUTDOWN -> R.drawable.widget_button_bg_danger
                WidgetAction.NONE -> R.drawable.widget_button_bg_off
            },
        )
        rv.setInt(
            R.id.widget_power, "setColorFilter",
            context.getColor(if (view.action == WidgetAction.SHUTDOWN) R.color.widget_on_button_danger else R.color.widget_on_button),
        )
        rv.setContentDescription(
            R.id.widget_power,
            if (view.action == WidgetAction.SHUTDOWN) "Desligar ${view.title}" else "Ligar ${view.title}",
        )

        // Toque no widget: abre o app direto na tela do PC.
        val open = Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_VIEW)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra(EXTRA_DEVICE, view.deviceId)
        val openPi = PendingIntent.getActivity(
            context, 0, open,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        rv.setOnClickPendingIntent(R.id.widget_root, openPi)
        if (view.action == WidgetAction.WAKE && view.deviceId != null) {
            // Ligar pede confirmação, como no app.
            val confirm = Intent(context, ConfirmWakeActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
                .putExtra(EXTRA_DEVICE, view.deviceId)
            rv.setOnClickPendingIntent(
                R.id.widget_power,
                PendingIntent.getActivity(context, 1, confirm, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT),
            )
        } else if (view.action == WidgetAction.SHUTDOWN) {
            // Desligar passa pelo app: ele tem a credencial e pergunta antes.
            val shutdown = Intent(open).putExtra(EXTRA_ACTION, "shutdown")
            rv.setOnClickPendingIntent(
                R.id.widget_power,
                PendingIntent.getActivity(context, 3, shutdown, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT),
            )
        } else {
            rv.setOnClickPendingIntent(R.id.widget_power, openPi)
        }
        manager.updateAppWidget(ids, rv)
    }
}
