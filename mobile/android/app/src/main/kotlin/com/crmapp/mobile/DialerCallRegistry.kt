package com.crmapp.mobile

import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telecom.Call
import android.telecom.CallAudioState
import android.telecom.DisconnectCause
import android.telecom.InCallService
import android.util.Log
import java.util.UUID
import java.util.concurrent.CopyOnWriteArraySet

/**
 * Every call Android's Telecom framework hands to [CrmInCallService], with the facts the CRM needs:
 * direction, the moments it started / was answered / ended, and how it ended. Calls and callbacks
 * arrive on the main thread. Never logs phone numbers.
 */
object DialerCallRegistry {
    private const val TAG = "CrmDialer"

    class Tracked(val id: String, val call: Call, val direction: String, val startedAt: Long) {
        var answeredAt: Long? = null
        var endedAt: Long? = null
        var status: String? = null
        var callback: Call.Callback? = null

        val number: String? get() = call.details?.handle?.schemeSpecificPart?.takeIf { it.isNotBlank() }

        val state: String get() = stateName(call.state)
    }

    private val calls = LinkedHashMap<String, Tracked>()
    private val listeners = CopyOnWriteArraySet<() -> Unit>()
    private val main = Handler(Looper.getMainLooper())

    /** The running service (needed for mute / speaker). Null when no call is being handled. */
    @Volatile
    var service: InCallService? = null

    /** Flutter's event stream, when the app is running. */
    @Volatile
    var eventSink: ((Map<String, Any?>) -> Unit)? = null

    @Volatile
    var audioState: CallAudioState? = null

    fun addListener(l: () -> Unit) {
        listeners.add(l)
    }

    fun removeListener(l: () -> Unit) {
        listeners.remove(l)
    }

    /** The call the screen should show: a ringing one first, else the first still in progress. */
    fun primary(): Tracked? {
        val live = calls.values.filter { it.endedAt == null }
        return live.firstOrNull { it.call.state == Call.STATE_RINGING } ?: live.firstOrNull() ?: calls.values.lastOrNull()
    }

    fun hasLiveCall(): Boolean = calls.values.any { it.endedAt == null }

    fun add(call: Call): Tracked {
        val tracked = Tracked(UUID.randomUUID().toString(), call, directionOf(call), System.currentTimeMillis())
        calls[tracked.id] = tracked
        if (call.state == Call.STATE_ACTIVE) tracked.answeredAt = tracked.startedAt
        val callback = object : Call.Callback() {
            override fun onStateChanged(call: Call, state: Int) {
                if (state == Call.STATE_ACTIVE && tracked.answeredAt == null) tracked.answeredAt = System.currentTimeMillis()
                if (state == Call.STATE_ACTIVE) startRecording(tracked)
                if (state == Call.STATE_DISCONNECTED) finish(tracked, call.details?.disconnectCause)
                publish(tracked)
            }

            override fun onDetailsChanged(call: Call, details: Call.Details) {
                publish(tracked)
            }
        }
        tracked.callback = callback
        call.registerCallback(callback)
        if (call.state == Call.STATE_ACTIVE) startRecording(tracked)
        if (call.state == Call.STATE_DISCONNECTED) finish(tracked, call.details?.disconnectCause)
        publish(tracked)
        return tracked
    }

    fun remove(call: Call) {
        val tracked = calls.values.firstOrNull { it.call == call } ?: return
        try {
            tracked.callback?.let { call.unregisterCallback(it) }
        } catch (e: Exception) {
            // Already unregistered.
        }
        if (tracked.endedAt == null) finish(tracked, call.details?.disconnectCause)
        publish(tracked)
        // Kept for a moment so the screen can show "Call ended", then forgotten (no leak).
        main.postDelayed({ calls.remove(tracked.id); notifyListeners() }, 4000)
    }

    fun onAudioState(state: CallAudioState) {
        audioState = state
        notifyListeners()
    }

    private fun finish(tracked: Tracked, cause: DisconnectCause?) {
        if (tracked.endedAt != null) return
        tracked.endedAt = System.currentTimeMillis()
        tracked.status = statusOf(tracked, cause)
        Log.i(TAG, "Call ended: ${tracked.direction} ${tracked.status}")
        try {
            DialerCallRecording.onEnded(tracked)
        } catch (e: Exception) {
            Log.w(TAG, "Recording stop failed (${e.javaClass.simpleName})")
        }
    }

    /** A recording problem must never affect the call itself. */
    private fun startRecording(tracked: Tracked) {
        try {
            DialerCallRecording.onAnswered(tracked)
        } catch (e: Exception) {
            Log.w(TAG, "Recording start failed (${e.javaClass.simpleName})")
        }
    }

    private fun publish(tracked: Tracked) {
        notifyListeners()
        val sink = eventSink ?: return
        try {
            sink(toMap(tracked))
        } catch (e: Exception) {
            Log.w(TAG, "Could not send a call event (${e.javaClass.simpleName})")
        }
    }

    private fun notifyListeners() {
        for (l in listeners) {
            try {
                l()
            } catch (e: Exception) {
                // One broken listener must not stop the others.
            }
        }
    }

    fun toMap(t: Tracked): Map<String, Any?> = mapOf(
        "callId" to t.id,
        "phoneNumber" to t.number,
        "direction" to t.direction,
        "state" to t.state,
        "status" to t.status,
        "startedAt" to t.startedAt,
        "answeredAt" to t.answeredAt,
        "endedAt" to t.endedAt,
    )

    private fun directionOf(call: Call): String {
        if (Build.VERSION.SDK_INT >= 29) {
            when (call.details?.callDirection) {
                Call.Details.DIRECTION_INCOMING -> return "incoming"
                Call.Details.DIRECTION_OUTGOING -> return "outgoing"
            }
        }
        return if (call.state == Call.STATE_RINGING) "incoming" else "outgoing"
    }

    /** completed | missed | rejected | busy | failed | cancelled — never guessed from timing alone. */
    private fun statusOf(t: Tracked, cause: DisconnectCause?): String = when (cause?.code) {
        DisconnectCause.MISSED -> "missed"
        DisconnectCause.REJECTED -> "rejected"
        DisconnectCause.BUSY -> "busy"
        DisconnectCause.ERROR, DisconnectCause.RESTRICTED, DisconnectCause.CONNECTION_MANAGER_NOT_SUPPORTED -> "failed"
        DisconnectCause.CANCELED -> "cancelled"
        else -> when {
            t.answeredAt != null -> "completed"
            t.direction == "incoming" -> "rejected"
            else -> "cancelled"
        }
    }

    fun stateName(state: Int): String = when (state) {
        Call.STATE_NEW -> "new"
        Call.STATE_RINGING -> "ringing"
        Call.STATE_DIALING -> "dialing"
        Call.STATE_CONNECTING -> "connecting"
        Call.STATE_ACTIVE -> "active"
        Call.STATE_HOLDING -> "holding"
        Call.STATE_DISCONNECTING -> "disconnecting"
        Call.STATE_DISCONNECTED -> "disconnected"
        Call.STATE_SELECT_PHONE_ACCOUNT -> "selecting_account"
        else -> "unknown"
    }
}
