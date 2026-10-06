package com.crmapp.mobile

import android.Manifest
import android.accessibilityservice.AccessibilityService
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import androidx.core.content.ContextCompat

/**
 * Settings > Sync Call History > "Record calls". An accessibility service only so Android lets the
 * app use the microphone while the phone's dialer is on screen; it reads no screen content.
 *
 * Watches the business SIM's call state and records each call from pick-up to hang-up into the
 * chosen recordings folder (see [CallRecorder]). Configuration comes from the Flutter side via
 * [CallRecorderConfig].
 */
class CallRecorderService : AccessibilityService() {
    private lateinit var recorder: CallRecorder
    private var telephony: TelephonyManager? = null
    private var callback: Any? = null

    // "Auto speaker": the customer's voice only reaches the microphone through the speaker.
    private val handler = Handler(Looper.getMainLooper())
    private var savedSpeaker: Boolean? = null
    private var modeListener: Any? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        recorder = CallRecorder(this)
        listen()
        Log.i(TAG, "Call recorder service connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Not used — the service exists for microphone access during calls.
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        stopRecording()
        unlisten()
        super.onDestroy()
    }

    @SuppressLint("MissingPermission")
    private fun listen() {
        unlisten()
        val config = CallRecorderConfig.read(this)
        if (!config.enabled || config.subscriptionId == null || config.folderUri == null) {
            Log.i(TAG, "Recorder idle: not configured")
            return
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) {
            Log.w(TAG, "Recorder idle: phone permission missing")
            return
        }
        val base = getSystemService(TelephonyManager::class.java) ?: return
        // Only the business SIM's calls.
        val tm = base.createForSubscriptionId(config.subscriptionId)
        telephony = tm
        try {
            if (Build.VERSION.SDK_INT >= 31) {
                val cb = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                    override fun onCallStateChanged(state: Int) = onCallState(state)
                }
                tm.registerTelephonyCallback(mainExecutor, cb)
                callback = cb
            } else {
                @Suppress("DEPRECATION")
                val listener = object : PhoneStateListener() {
                    @Deprecated("Deprecated in Java")
                    override fun onCallStateChanged(state: Int, phoneNumber: String?) = onCallState(state)
                }
                @Suppress("DEPRECATION")
                tm.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
                callback = listener
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "Recorder idle: call state not readable")
        }
    }

    private fun unlisten() {
        val tm = telephony ?: return
        val cb = callback
        try {
            if (Build.VERSION.SDK_INT >= 31 && cb is TelephonyCallback) {
                tm.unregisterTelephonyCallback(cb)
            } else if (cb is PhoneStateListener) {
                @Suppress("DEPRECATION")
                tm.listen(cb, PhoneStateListener.LISTEN_NONE)
            }
        } catch (e: Exception) {
        }
        telephony = null
        callback = null
    }

    private fun onCallState(state: Int) {
        when (state) {
            TelephonyManager.CALL_STATE_OFFHOOK -> startRecording()
            TelephonyManager.CALL_STATE_IDLE -> stopRecording()
        }
    }

    private fun startRecording() {
        if (recorder.isRecording) return
        val config = CallRecorderConfig.read(this)
        val folder = config.folderUri ?: return
        CallRecordingKeepAlive.start(this)
        if (!recorder.start(Uri.parse(folder))) {
            CallRecordingKeepAlive.stop(this)
            return
        }
        if (config.speaker) assistSpeaker()
    }

    private fun stopRecording() {
        if (!::recorder.isInitialized) return
        releaseSpeaker()
        if (!recorder.isRecording) return
        recorder.stop()
        CallRecordingKeepAlive.stop(this)
    }

    /**
     * Puts the call on the loudspeaker for as long as it is recorded, so the microphone hears the
     * customer too. Android re-routes the audio when an outgoing call connects, so it is applied again
     * a few times during the first seconds (and whenever the call becomes active), then left alone so
     * the member can still switch it off by hand.
     */
    @Suppress("DEPRECATION") // isSpeakerphoneOn is the way to read / set it before Android 12.
    private fun assistSpeaker() {
        val audio = getSystemService(AudioManager::class.java) ?: return
        if (savedSpeaker == null) savedSpeaker = audio.isSpeakerphoneOn
        for (delay in longArrayOf(700, 2_000, 4_000, 7_000, 11_000, 16_000, 22_000)) {
            handler.postDelayed({ if (recorder.isRecording) forceSpeaker(audio) }, delay)
        }
        if (Build.VERSION.SDK_INT >= 31) {
            val listener = AudioManager.OnModeChangedListener { mode ->
                if (mode == AudioManager.MODE_IN_CALL && recorder.isRecording) forceSpeaker(audio)
            }
            modeListener = listener
            try {
                audio.addOnModeChangedListener(mainExecutor, listener)
            } catch (e: Exception) {
                modeListener = null
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun forceSpeaker(audio: AudioManager) {
        try {
            var routed = false
            if (Build.VERSION.SDK_INT >= 31) {
                val speaker = audio.availableCommunicationDevices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                routed = speaker != null && audio.setCommunicationDevice(speaker)
            }
            if (!routed) audio.isSpeakerphoneOn = true
            Log.i(TAG, "Speaker requested: communicationDevice=$routed speakerphoneOn=${audio.isSpeakerphoneOn} mode=${audio.mode}")
        } catch (e: Exception) {
            Log.w(TAG, "Could not switch to speaker (${e.javaClass.simpleName})")
        }
    }

    /** Back to how the member had it. */
    @Suppress("DEPRECATION")
    private fun releaseSpeaker() {
        handler.removeCallbacksAndMessages(null)
        val audio = getSystemService(AudioManager::class.java) ?: return
        try {
            if (Build.VERSION.SDK_INT >= 31) {
                (modeListener as? AudioManager.OnModeChangedListener)?.let { audio.removeOnModeChangedListener(it) }
                if (savedSpeaker != null) audio.clearCommunicationDevice()
            }
            savedSpeaker?.let { audio.isSpeakerphoneOn = it }
        } catch (e: Exception) {
            Log.w(TAG, "Could not restore the speaker setting (${e.javaClass.simpleName})")
        }
        savedSpeaker = null
        modeListener = null
    }

    companion object {
        private const val TAG = "CrmCallRecorder"

        /** The running service picks up a new configuration (it re-reads it on reconnect anyway). */
        var instance: CallRecorderService? = null
            private set

        fun isEnabled(context: Context): Boolean {
            val enabled = Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
            val me = "${context.packageName}/${CallRecorderService::class.java.name}"
            val meShort = "${context.packageName}/.${CallRecorderService::class.java.simpleName}"
            return enabled.split(':').any { it.equals(me, true) || it.equals(meShort, true) }
        }

        fun openSettings(context: Context): Boolean = try {
            context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (e: Exception) {
            false
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
    }

    /** Called after the Flutter side saved a new configuration. */
    fun reconfigure() {
        // The channel can call this in the instant between onCreate and onServiceConnected.
        if (!::recorder.isInitialized) return
        if (!recorder.isRecording) listen()
    }
}

/** What to record, saved by the Flutter side (business SIM + folder + on/off). */
data class CallRecorderConfig(val enabled: Boolean, val subscriptionId: Int?, val folderUri: String?, val speaker: Boolean = true) {
    companion object {
        private const val PREFS = "crm_call_recorder"

        fun read(context: Context): CallRecorderConfig {
            val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val sub = p.getInt("subscriptionId", -1)
            return CallRecorderConfig(p.getBoolean("enabled", false), if (sub >= 0) sub else null, p.getString("folderUri", null), p.getBoolean("speaker", true))
        }

        fun write(context: Context, config: CallRecorderConfig) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putBoolean("enabled", config.enabled)
                .putInt("subscriptionId", config.subscriptionId ?: -1)
                .putString("folderUri", config.folderUri)
                .putBoolean("speaker", config.speaker)
                .apply()
        }
    }
}
