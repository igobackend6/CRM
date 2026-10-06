package com.crmapp.mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log

/**
 * A foreground service with type "microphone" that runs only while a call is being recorded. It
 * shows the "Recording call" notification and keeps Android from muting the microphone for a
 * background app. If Android won't let it start, recording still goes ahead from the
 * accessibility service.
 */
class CallRecordingKeepAlive : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager?.createNotificationChannel(NotificationChannel(CHANNEL, "Call recording", NotificationManager.IMPORTANCE_LOW))
        }
        val notification = (if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else @Suppress("DEPRECATION") Notification.Builder(this))
            .setContentTitle("Recording call")
            .setContentText("Sales CRM is recording this business call.")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .build()
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            } else {
                startForeground(ID, notification)
            }
        } catch (e: Exception) {
            Log.w("CrmCallRecorder", "Keep-alive couldn't go foreground (${e.javaClass.simpleName})")
            stopSelf()
        }
        return START_NOT_STICKY
    }

    companion object {
        private const val CHANNEL = "call_recording"
        private const val ID = 4107

        fun start(context: Context) {
            try {
                val intent = Intent(context, CallRecordingKeepAlive::class.java)
                if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
            } catch (e: Exception) {
                // e.g. ForegroundServiceStartNotAllowedException — record without it.
                Log.w("CrmCallRecorder", "Keep-alive not started (${e.javaClass.simpleName})")
            }
        }

        fun stop(context: Context) {
            try {
                context.stopService(Intent(context, CallRecordingKeepAlive::class.java))
            } catch (e: Exception) {
            }
        }
    }
}
