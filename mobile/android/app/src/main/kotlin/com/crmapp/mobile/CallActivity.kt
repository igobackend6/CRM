package com.crmapp.mobile

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.telecom.Call
import android.telecom.CallAudioState
import android.telecom.VideoProfile
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.GridLayout
import android.widget.LinearLayout
import android.widget.TextView

/**
 * The CRM's call screen — ringing (Answer / Reject), dialling and in-call (Mute, Speaker, Keypad,
 * End call). Plain native views so it opens instantly, also over the lock screen and when the Flutter
 * app isn't running. Shows the CRM lead's name and status when the number is one of the member's leads.
 */
class CallActivity : Activity() {
    private val main = Handler(Looper.getMainLooper())
    private val refresh: () -> Unit = { main.post { render() } }
    private val ticker = object : Runnable {
        override fun run() {
            render()
            main.postDelayed(this, 1000)
        }
    }

    private lateinit var nameView: TextView
    private lateinit var numberView: TextView
    private lateinit var infoView: TextView
    private lateinit var stateView: TextView
    private lateinit var controls: LinearLayout
    private var showKeypad = false
    private var closing = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        buildLayout()
        DialerCallRegistry.addListener(refresh)
        render()
    }

    override fun onNewIntent(intent: android.content.Intent?) {
        super.onNewIntent(intent)
        render()
    }

    override fun onStart() {
        super.onStart()
        main.post(ticker)
    }

    override fun onStop() {
        main.removeCallbacks(ticker)
        super.onStop()
    }

    override fun onDestroy() {
        DialerCallRegistry.removeListener(refresh)
        main.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        // The call carries on; the member leaves the screen but not the call.
        moveTaskToBack(true)
    }

    // ------------------------------------------------------------------ layout

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    private fun text(size: Float, color: Int, bold: Boolean = false) = TextView(this).apply {
        setTextSize(size)
        setTextColor(color)
        gravity = Gravity.CENTER
        if (bold) typeface = Typeface.DEFAULT_BOLD
    }

    private fun buildLayout() {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(24), dp(72), dp(24), dp(40))
            background = GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(Color.parseColor("#0B1B4D"), Color.parseColor("#1D4ED8")),
            )
        }
        nameView = text(28f, Color.WHITE, true)
        numberView = text(16f, Color.parseColor("#CBD5F5"))
        infoView = text(14f, Color.parseColor("#93C5FD"))
        stateView = text(18f, Color.WHITE)
        root.addView(nameView, matchWrap(top = 0))
        root.addView(numberView, matchWrap(top = dp(6)))
        root.addView(infoView, matchWrap(top = dp(6)))
        root.addView(stateView, matchWrap(top = dp(28)))
        root.addView(View(this), LinearLayout.LayoutParams(1, 0, 1f))
        controls = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
        }
        root.addView(controls, matchWrap(top = 0))
        setContentView(root)
    }

    private fun matchWrap(top: Int) = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
        topMargin = top
    }

    private fun roundButton(label: String, color: Int, size: Int = 72, onClick: () -> Unit): TextView = TextView(this).apply {
        text = label
        setTextColor(Color.WHITE)
        setTextSize(14f)
        gravity = Gravity.CENTER
        typeface = Typeface.DEFAULT_BOLD
        background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(color)
        }
        layoutParams = LinearLayout.LayoutParams(dp(size), dp(size)).apply { setMargins(dp(14), dp(8), dp(14), dp(8)) }
        setOnClickListener { onClick() }
    }

    private fun row(vararg views: View) = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER
        for (v in views) addView(v)
    }

    // ------------------------------------------------------------------ state

    private fun render() {
        val t = DialerCallRegistry.primary()
        if (t == null) {
            finishSoon()
            return
        }
        val match = LeadCache.lookup(this, t.number)
        nameView.text = match?.name ?: "Unknown number"
        numberView.text = t.number ?: ""
        infoView.text = when {
            match == null -> "Not in your CRM leads"
            match.status != null -> "Lead · ${match.status}"
            else -> "CRM lead"
        }
        val ended = t.endedAt != null
        // A new call while the screen is closing: keep it open.
        if (!ended) closing = false
        stateView.text = when {
            ended -> "Call ended" + (duration(t)?.let { " · $it" } ?: "")
            t.call.state == Call.STATE_RINGING -> "Incoming call"
            t.call.state == Call.STATE_ACTIVE -> duration(t) ?: "Connected"
            t.call.state == Call.STATE_HOLDING -> "On hold"
            t.call.state == Call.STATE_DISCONNECTING -> "Ending..."
            else -> "Calling..."
        }
        controls.removeAllViews()
        when {
            ended -> finishSoon()
            t.call.state == Call.STATE_RINGING -> controls.addView(
                row(
                    roundButton("Reject", Color.parseColor("#DC2626"), 84) { safely { t.call.reject(false, null) } },
                    roundButton("Answer", Color.parseColor("#16A34A"), 84) { safely { t.call.answer(VideoProfile.STATE_AUDIO_ONLY) } },
                ),
            )
            else -> addInCallControls(t)
        }
    }

    private fun addInCallControls(t: DialerCallRegistry.Tracked) {
        val audio = DialerCallRegistry.audioState
        val muted = audio?.isMuted == true
        val speaker = audio?.route == CallAudioState.ROUTE_SPEAKER
        if (showKeypad) {
            controls.addView(keypad(t))
        }
        controls.addView(
            row(
                roundButton(if (muted) "Unmute" else "Mute", if (muted) Color.parseColor("#F59E0B") else Color.parseColor("#33FFFFFF")) {
                    safely { DialerCallRegistry.service?.setMuted(!muted) }
                },
                roundButton(if (speaker) "Speaker\non" else "Speaker", if (speaker) Color.parseColor("#F59E0B") else Color.parseColor("#33FFFFFF")) {
                    safely {
                        DialerCallRegistry.service?.setAudioRoute(
                            if (speaker) CallAudioState.ROUTE_EARPIECE else CallAudioState.ROUTE_SPEAKER,
                        )
                    }
                },
                roundButton("Keypad", Color.parseColor("#33FFFFFF")) {
                    showKeypad = !showKeypad
                    render()
                },
            ),
        )
        controls.addView(
            row(roundButton("End\ncall", Color.parseColor("#DC2626"), 84) { safely { t.call.disconnect() } }),
        )
    }

    private fun keypad(t: DialerCallRegistry.Tracked): View {
        val grid = GridLayout(this).apply {
            columnCount = 3
            setPadding(0, dp(4), 0, dp(8))
        }
        for (key in "123456789*0#") {
            val button = TextView(this).apply {
                text = key.toString()
                setTextColor(Color.WHITE)
                setTextSize(22f)
                gravity = Gravity.CENTER
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(Color.parseColor("#33FFFFFF"))
                }
                layoutParams = GridLayout.LayoutParams().apply {
                    width = dp(60)
                    height = dp(60)
                    setMargins(dp(10), dp(4), dp(10), dp(4))
                }
                setOnTouchListener { _, event ->
                    when (event.action) {
                        MotionEvent.ACTION_DOWN -> safely { t.call.playDtmfTone(key) }
                        MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> safely { t.call.stopDtmfTone() }
                    }
                    true
                }
            }
            grid.addView(button)
        }
        return grid
    }

    private fun duration(t: DialerCallRegistry.Tracked): String? {
        val from = t.answeredAt ?: return null
        val seconds = (((t.endedAt ?: System.currentTimeMillis()) - from) / 1000).coerceAtLeast(0)
        return "%02d:%02d".format(seconds / 60, seconds % 60)
    }

    private fun finishSoon() {
        if (closing) return
        closing = true
        main.postDelayed({ if (!isFinishing) finish() }, 1500)
    }

    private inline fun safely(block: () -> Unit) {
        try {
            block()
        } catch (e: Exception) {
            Log.w("CrmDialer", "Call action failed (${e.javaClass.simpleName})")
        }
    }
}
