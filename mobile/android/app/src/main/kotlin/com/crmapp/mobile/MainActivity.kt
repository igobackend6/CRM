package com.crmapp.mobile

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// local_auth (the App Security lock) needs a FragmentActivity for the system biometric/PIN prompt.
class MainActivity : FlutterFragmentActivity() {
    // Settings > Connected SIM Details. Created with the activity so its permission launcher is
    // registered before the activity starts.
    private val simChannel = SimChannel(this)

    // Settings > Sync Call History / call-recordings folder. Same reason for creating it here.
    private val callSyncChannel = CallSyncChannel(this)

    // Settings > Default Dialer: the CRM as the phone app (role, SIM accounts, placing calls).
    private val dialerChannel = DialerChannel(this)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        forgetPhoneLinkDefault()
        rememberLead(intent)
        rememberDial(intent)
        SharedAudio.intake(this, intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        rememberLead(intent)
        rememberDial(intent)
        SharedAudio.intake(this, intent)
    }

    // An accidental "Always open with Sales CRM" for phone links would make every Call button open
    // the CRM dialer instead of the phone. Dropping the app's own saved choices is harmless.
    @Suppress("DEPRECATION")
    private fun forgetPhoneLinkDefault() {
        try {
            packageManager.clearPackagePreferredActivities(packageName)
        } catch (e: Exception) {
            // Nothing to clear, or not allowed: the Call buttons still work.
        }
    }

    // Another app (or a tel: link) asked the dialer to show a number. Nothing is dialled until the
    // member taps Call.
    private fun rememberDial(intent: Intent?) {
        if (intent?.action != Intent.ACTION_DIAL && intent?.action != Intent.ACTION_VIEW) return
        val uri = intent.data ?: return
        if (uri.scheme != "tel") return
        LaunchTarget.dialNumber = uri.schemeSpecificPart?.takeIf { it.isNotBlank() }
    }

    // A tapped "call back" notification carries the lead to open.
    private fun rememberLead(intent: Intent?) {
        val leadId = intent?.getStringExtra(CallBackReminders.EXTRA_LEAD) ?: return
        LaunchTarget.leadId = leadId
        intent.removeExtra(CallBackReminders.EXTRA_LEAD)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        simChannel.attach(flutterEngine.dartExecutor.binaryMessenger)
        callSyncChannel.attach(flutterEngine.dartExecutor.binaryMessenger)
        dialerChannel.attach(flutterEngine.dartExecutor.binaryMessenger)
    }
}
