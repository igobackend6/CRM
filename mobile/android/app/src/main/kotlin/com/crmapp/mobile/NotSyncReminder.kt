package com.crmapp.mobile

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

/**
 * Settings > Not Sync Notification: a reminder that call history hasn't synced for the chosen number
 * of hours.
 *
 * One alarm is kept for "last successful sync + N hours". The app pushes it forward after every
 * successful sync, so it only ever fires when sync has really stalled — even with the app closed.
 * After it fires it sets the next one N hours later, so the reminder repeats until a sync succeeds.
 * Survives a reboot (see [NotSyncReceiver]). Uses an inexact alarm, so it needs no special permission.
 */
object NotSyncReminder {
    const val ACTION_FIRE = "com.crmapp.mobile.NOT_SYNC_REMINDER"
    private const val PREFS = "crm_not_sync_reminder"
    private const val KEY_TRIGGER = "triggerAtMillis"
    private const val KEY_HOURS = "hours"
    private const val REQUEST_CODE = 4108
    private const val CHANNEL = "call_sync_reminder"
    private const val NOTIFICATION_ID = 4109
    private const val TAG = "CrmNotSync"

    fun schedule(context: Context, triggerAtMillis: Long, hours: Int) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putLong(KEY_TRIGGER, triggerAtMillis)
            .putInt(KEY_HOURS, hours)
            .apply()
        arm(context, triggerAtMillis)
    }

    fun cancel(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
        alarmManager(context)?.cancel(pending(context))
    }

    private fun arm(context: Context, triggerAtMillis: Long) {
        val alarms = alarmManager(context) ?: return
        alarms.cancel(pending(context))
        try {
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pending(context))
        } catch (e: Exception) {
            Log.w(TAG, "Could not set the reminder alarm (${e.javaClass.simpleName})")
        }
    }

    /** Called when the alarm fires (or after a reboot): shows the notification and sets the next alarm. */
    internal fun onFire(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val hours = prefs.getInt(KEY_HOURS, 0)
        if (hours <= 0) return // Cancelled in the meantime.
        notifyNotSynced(context, hours)
        schedule(context, System.currentTimeMillis() + hours * HOUR, hours)
    }

    /** After a reboot or an app update, alarms are gone: set the saved one again. */
    internal fun restore(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val hours = prefs.getInt(KEY_HOURS, 0)
        val saved = prefs.getLong(KEY_TRIGGER, 0L)
        if (hours <= 0 || saved <= 0L) return
        val now = System.currentTimeMillis()
        var next = saved
        // Missed while the phone was off: remind soon, then carry on every N hours.
        if (next <= now) next = now + 2 * 60 * 1000L
        schedule(context, next, hours)
    }

    fun notificationsAllowed(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        return NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    /** Shows the reminder now (the screen's "Send test reminder"); false if Android won't show it. */
    fun showNow(context: Context, hours: Int): Boolean = notifyNotSynced(context, hours)

    private fun notifyNotSynced(context: Context, hours: Int): Boolean {
        if (!notificationsAllowed(context)) return false
        val manager = context.getSystemService(NotificationManager::class.java) ?: return false
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL, "Call sync reminders", NotificationManager.IMPORTANCE_DEFAULT))
        }
        val open = context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
            PendingIntent.getActivity(context, REQUEST_CODE, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL) else @Suppress("DEPRECATION") Notification.Builder(context)
        val notification = builder
            .setContentTitle("Call history not synced")
            .setContentText("Your calls haven't synced for $hours ${if (hours == 1) "hour" else "hours"}. Open Sales CRM to sync them.")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setAutoCancel(true)
            .setContentIntent(open)
            .build()
        return try {
            manager.notify(NOTIFICATION_ID, notification)
            true
        } catch (e: SecurityException) {
            Log.w(TAG, "Notification not shown: permission missing")
            false
        }
    }

    private fun alarmManager(context: Context) = context.getSystemService(AlarmManager::class.java)

    private fun pending(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        REQUEST_CODE,
        Intent(context, NotSyncReceiver::class.java).setAction(ACTION_FIRE),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private const val HOUR = 3_600_000L
}

/** Receives the reminder alarm, and the reboot / app-update broadcasts that clear alarms. */
class NotSyncReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            NotSyncReminder.ACTION_FIRE -> NotSyncReminder.onFire(context)
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> NotSyncReminder.restore(context)
        }
    }
}
