package com.crmapp.mobile

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import org.json.JSONObject

/**
 * Settings > Never Attended Call Reminder: a phone alert, per lead, at the time the "call back"
 * follow-up is due ("Call back Suguna — missed call at 3:10 PM"). Tapping it opens that lead.
 *
 * One alarm per lead (a newer one replaces the older). Kept in SharedPreferences so they survive a
 * reboot. Inexact alarms: no special permission. Holds only the lead id, the title and the text.
 */
object CallBackReminders {
    const val ACTION_FIRE = "com.crmapp.mobile.CALL_BACK_REMINDER"
    const val EXTRA_LEAD = "leadId"
    private const val PREFS = "crm_call_back_reminders"
    private const val KEY_ITEMS = "items"
    private const val CHANNEL = "call_back_reminder"
    private const val TAG = "CrmCallBack"

    @Synchronized
    fun schedule(context: Context, leadId: String, triggerAtMillis: Long, title: String, text: String) {
        val items = load(context)
        items.put(leadId, JSONObject().put("at", triggerAtMillis).put("title", title).put("text", text))
        save(context, items)
        arm(context, leadId, triggerAtMillis)
    }

    @Synchronized
    fun cancel(context: Context, leadId: String) {
        val items = load(context)
        if (items.has(leadId)) {
            items.remove(leadId)
            save(context, items)
        }
        alarms(context)?.cancel(pending(context, leadId))
    }

    @Synchronized
    fun cancelAll(context: Context) {
        val items = load(context)
        val keys = items.keys()
        while (keys.hasNext()) alarms(context)?.cancel(pending(context, keys.next()))
        save(context, JSONObject())
    }

    @Synchronized
    internal fun onFire(context: Context, leadId: String) {
        val items = load(context)
        val item = items.optJSONObject(leadId) ?: return // Cancelled in the meantime.
        items.remove(leadId)
        save(context, items)
        show(context, leadId, item.optString("title"), item.optString("text"))
    }

    /** After a reboot or app update the alarms are gone: set the saved ones again (overdue ones soon). */
    @Synchronized
    internal fun restore(context: Context) {
        val items = load(context)
        val now = System.currentTimeMillis()
        val keys = items.keys()
        while (keys.hasNext()) {
            val leadId = keys.next()
            val at = items.optJSONObject(leadId)?.optLong("at", 0L) ?: continue
            arm(context, leadId, if (at <= now) now + 60_000L else at)
        }
    }

    private fun arm(context: Context, leadId: String, triggerAtMillis: Long) {
        val manager = alarms(context) ?: return
        manager.cancel(pending(context, leadId))
        try {
            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pending(context, leadId))
        } catch (e: Exception) {
            Log.w(TAG, "Could not set a call-back alarm (${e.javaClass.simpleName})")
        }
    }

    private fun show(context: Context, leadId: String, title: String, text: String) {
        if (!NotSyncReminder.notificationsAllowed(context)) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL, "Call back reminders", NotificationManager.IMPORTANCE_HIGH))
        }
        val open = context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
            it.putExtra(EXTRA_LEAD, leadId)
            PendingIntent.getActivity(
                context,
                leadId.hashCode(),
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL) else @Suppress("DEPRECATION") Notification.Builder(context)
        val notification = builder
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.sym_call_missed)
            .setAutoCancel(true)
            .setContentIntent(open)
            .build()
        try {
            manager.notify(leadId.hashCode(), notification)
        } catch (e: SecurityException) {
            Log.w(TAG, "Call-back reminder not shown: permission missing")
        }
    }

    private fun alarms(context: Context) = context.getSystemService(AlarmManager::class.java)

    // The data URI keeps each lead's PendingIntent distinct (extras alone don't).
    private fun pending(context: Context, leadId: String): PendingIntent = PendingIntent.getBroadcast(
        context,
        leadId.hashCode(),
        Intent(context, CallBackReceiver::class.java)
            .setAction(ACTION_FIRE)
            .setData(Uri.parse("crm://call-back/$leadId"))
            .putExtra(EXTRA_LEAD, leadId),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun load(context: Context): JSONObject = try {
        JSONObject(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_ITEMS, "{}") ?: "{}")
    } catch (e: Exception) {
        JSONObject()
    }

    private fun save(context: Context, items: JSONObject) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_ITEMS, items.toString()).apply()
    }
}

/** Receives the call-back alarms, and the reboot / app-update broadcasts that clear them. */
class CallBackReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            CallBackReminders.ACTION_FIRE -> intent.getStringExtra(CallBackReminders.EXTRA_LEAD)?.let { CallBackReminders.onFire(context, it) }
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> CallBackReminders.restore(context)
        }
    }
}

/** The lead a tapped call-back notification asked to open; the app takes it once it is running. */
object LaunchTarget {
    @Volatile
    var leadId: String? = null

    /** A number another app asked the dialer to show (ACTION_DIAL / tel: link). */
    @Volatile
    var dialNumber: String? = null

    fun take(): String? = leadId.also { leadId = null }

    fun takeDial(): String? = dialNumber.also { dialNumber = null }
}
