package com.crmapp.mobile

import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telecom.CallAudioState
import android.util.Log

/**
 * Records the calls the CRM dialer handles, into the same recordings folder the employee picked
 * (Settings > Sync Call History > Change Call Recordings Location). The existing recording sync then
 * uploads the file to the CRM and attaches it to the call, exactly as for any other recording.
 *
 * Starts when a call is answered, stops when it ends. Uses [CallRecorder] (microphone), so the other
 * person is only heard when the call is on the loudspeaker; with "Auto speaker" on, the call is
 * routed to the loudspeaker while recording and put back afterwards (the member can still switch it
 * off by hand). Runs whenever the CRM is the Phone app and a recordings folder is chosen, whatever
 * the accessibility "Record calls" switch says. One call at a time.
 */
object DialerCallRecording {
    private const val TAG = "CrmDialerRecording"
    private val main = Handler(Looper.getMainLooper())

    /**
     * Off: measured on a real call (2026-10-03, Android 12), a Phone-role app's microphone recording
     * is pure silence (-91 dB) - Android only lets the system's own dialer capture call audio. Kept
     * so it can be switched on if a phone / ROM allows it.
     */
    private const val ENABLED = false

    private var recorder: CallRecorder? = null
    private var recordingId: String? = null
    private var number: String? = null
    private var routeBefore: Int? = null

    fun onAnswered(tracked: DialerCallRegistry.Tracked) {
        if (!ENABLED || recordingId != null) return
        val service = DialerCallRegistry.service ?: return
        val config = CallRecorderConfig.read(service)
        val folder = config.folderUri
        if (folder == null) return
        val r = recorder ?: CallRecorder(service).also { recorder = it }
        CallRecordingKeepAlive.start(service)
        if (!r.start(Uri.parse(folder))) {
            CallRecordingKeepAlive.stop(service)
            return
        }
        recordingId = tracked.id
        number = tracked.number
        assistSpeaker()
    }

    fun onEnded(tracked: DialerCallRegistry.Tracked) {
        if (recordingId != tracked.id) return
        val service = DialerCallRegistry.service
        main.removeCallbacksAndMessages(null)
        restoreRoute()
        try {
            recorder?.stop(number ?: tracked.number)
        } finally {
            recordingId = null
            number = null
            if (service != null) CallRecordingKeepAlive.stop(service)
        }
    }

    private fun assistSpeaker() {
        val service = DialerCallRegistry.service ?: return
        routeBefore = DialerCallRegistry.audioState?.route
        // The route can be re-set by the system as the call connects, so apply it a few times.
        for (delay in longArrayOf(200, 1_500, 4_000)) {
            main.postDelayed({
                if (recordingId != null) {
                    try {
                        service.setAudioRoute(CallAudioState.ROUTE_SPEAKER)
                    } catch (e: Exception) {
                        Log.w(TAG, "Could not switch to speaker (${e.javaClass.simpleName})")
                    }
                }
            }, delay)
        }
    }

    private fun restoreRoute() {
        val service = DialerCallRegistry.service ?: return
        val before = routeBefore ?: return
        routeBefore = null
        try {
            if (before != CallAudioState.ROUTE_SPEAKER) service.setAudioRoute(before)
        } catch (e: Exception) {
            // The call is ending anyway.
        }
    }
}
