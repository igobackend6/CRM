package com.crmapp.mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.telecom.Call
import android.telecom.CallAudioState
import android.telecom.InCallService
import android.util.Log

/**
 * The CRM's side of Android's phone stack. Android binds this service to hand over every call
 * (placed or received) while the CRM is the default phone app; the CRM's [CallActivity] is the call
 * screen. Android itself plays the ringtone (IN_CALL_SERVICE_RINGING = false) and handles emergency
 * calls, so a bug here can never silence a call or block 112.
 */
class CrmInCallService : InCallService() {
    override fun onCreate() {
        super.onCreate()
        DialerCallRegistry.service = this
    }

    override fun onDestroy() {
        if (DialerCallRegistry.service === this) DialerCallRegistry.service = null
        super.onDestroy()
    }

    override fun onCallAdded(call: Call) {
        super.onCallAdded(call)
        try {
            val tracked = DialerCallRegistry.add(call)
            showCallScreen(tracked)
        } catch (e: Exception) {
            // Never let a CRM problem stop the call: Android keeps handling it.
            Log.w(TAG, "Could not show the call screen (${e.javaClass.simpleName})")
        }
    }

    override fun onCallRemoved(call: Call) {
        super.onCallRemoved(call)
        try {
            DialerCallRegistry.remove(call)
        } catch (e: Exception) {
            Log.w(TAG, "Could not close a call (${e.javaClass.simpleName})")
        }
        if (!DialerCallRegistry.hasLiveCall()) cancelRingingNotification()
    }

    override fun onCallAudioStateChanged(audioState: CallAudioState) {
        super.onCallAudioStateChanged(audioState)
        DialerCallRegistry.onAudioState(audioState)
    }

    private fun showCallScreen(tracked: DialerCallRegistry.Tracked) {
        val intent = Intent(this, CallActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        if (tracked.direction == "incoming") {
            // A heads-up notification with a full-screen intent, for a phone that blocks background
            // activity starts; the activity start below is the primary route.
            showRingingNotification(intent, tracked)
        }
        try {
            startActivity(intent)
        } catch (e: Exception) {
            Log.w(TAG, "Call screen start was blocked (${e.javaClass.simpleName}); the notification will show it")
        }
    }

    private fun showRingingNotification(intent: Intent, tracked: DialerCallRegistry.Tracked) {
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL, "Incoming calls", NotificationManager.IMPORTANCE_HIGH).apply {
                setSound(null, null) // Android already rings.
            })
        }
        val pending = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val label = LeadCache.lookup(this, tracked.number)?.name ?: tracked.number ?: "Unknown number"
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else @Suppress("DEPRECATION") Notification.Builder(this)
        val notification = builder
            .setContentTitle("Incoming call")
            .setContentText(label)
            .setSmallIcon(android.R.drawable.sym_call_incoming)
            .setCategory(Notification.CATEGORY_CALL)
            .setOngoing(true)
            .setFullScreenIntent(pending, true)
            .setContentIntent(pending)
            .build()
        try {
            manager.notify(NOTIFICATION_ID, notification)
        } catch (e: SecurityException) {
            Log.w(TAG, "Incoming-call notification not shown")
        }
    }

    private fun cancelRingingNotification() {
        getSystemService(NotificationManager::class.java)?.cancel(NOTIFICATION_ID)
    }

    companion object {
        private const val TAG = "CrmDialer"
        private const val CHANNEL = "incoming_call"
        private const val NOTIFICATION_ID = 4120
    }
}
