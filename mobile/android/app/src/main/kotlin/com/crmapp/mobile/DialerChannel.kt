package com.crmapp.mobile

import android.Manifest
import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.telephony.TelephonyManager
import android.util.Log
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Settings > Default Dialer and the CRM's own calling: whether the CRM is the phone app, asking for
 * the role, listing SIM accounts, placing a call through Android's Telecom framework, and streaming
 * call events to Flutter. A normal carrier call: no VoIP.
 */
class DialerChannel(private val activity: FragmentActivity) {
    private val main = Handler(Looper.getMainLooper())
    private var pendingRole: MethodChannel.Result? = null
    private var pendingPermission: MethodChannel.Result? = null

    private val roleLauncher =
        activity.registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
            val result = pendingRole
            pendingRole = null
            result?.success(isDefaultDialer())
        }

    private val permissionLauncher =
        activity.registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            val result = pendingPermission
            pendingPermission = null
            result?.success(granted)
        }

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "status" -> result.success(status())
                    "requestDefaultDialer" -> requestRole(result)
                    "openDefaultAppsSettings" -> result.success(openDefaultAppsSettings())
                    "getPhoneAccounts" -> result.success(phoneAccounts())
                    "hasCallPermission" -> result.success(hasCallPermission())
                    "requestCallPermission" -> requestCallPermission(result)
                    "placeCall" -> placeCall(call.argument<String>("number"), call.argument<Int>("subscriptionId"), result)
                    "getCurrentCall" -> result.success(DialerCallRegistry.primary()?.let { DialerCallRegistry.toMap(it) })
                    "updateLeadCache" -> {
                        @Suppress("UNCHECKED_CAST")
                        LeadCache.replace(activity, (call.argument<List<Map<String, Any?>>>("leads")) ?: emptyList())
                        result.success(true)
                    }
                    "takeDialNumber" -> result.success(LaunchTarget.takeDial())
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                Log.w(TAG, "Dialer call ${call.method} failed (${e.javaClass.simpleName})")
                result.error("dialer_failed", e.javaClass.simpleName, null)
            }
        }
        EventChannel(messenger, EVENTS).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                DialerCallRegistry.eventSink = { event -> main.post { events?.success(event) } }
            }

            override fun onCancel(arguments: Any?) {
                DialerCallRegistry.eventSink = null
            }
        })
    }

    // ------------------------------------------------------------------ role

    private fun telecom() = activity.getSystemService(TelecomManager::class.java)

    private fun isDefaultDialer(): Boolean = telecom()?.defaultDialerPackage == activity.packageName

    /** {isDefault, available}: available = this phone offers the Phone role to apps. */
    private fun status(): Map<String, Any?> {
        val available = if (Build.VERSION.SDK_INT >= 29) {
            activity.getSystemService(RoleManager::class.java)?.isRoleAvailable(RoleManager.ROLE_DIALER) == true
        } else {
            telecom() != null
        }
        return mapOf(
            "isDefault" to isDefaultDialer(),
            "available" to available,
            "sdk" to Build.VERSION.SDK_INT,
        )
    }

    private fun requestRole(result: MethodChannel.Result) {
        if (isDefaultDialer()) {
            result.success(true)
            return
        }
        if (pendingRole != null) {
            result.error("busy", "A request is already showing", null)
            return
        }
        val intent = if (Build.VERSION.SDK_INT >= 29) {
            activity.getSystemService(RoleManager::class.java).createRequestRoleIntent(RoleManager.ROLE_DIALER)
        } else {
            Intent(TelecomManager.ACTION_CHANGE_DEFAULT_DIALER).putExtra(TelecomManager.EXTRA_CHANGE_DEFAULT_DIALER_PACKAGE_NAME, activity.packageName)
        }
        pendingRole = result
        try {
            roleLauncher.launch(intent)
        } catch (e: Exception) {
            pendingRole = null
            result.error("request_failed", e.javaClass.simpleName, null)
        }
    }

    /** Android has no way for an app to give the Phone role back: the member picks another app here. */
    private fun openDefaultAppsSettings(): Boolean = try {
        activity.startActivity(Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: Exception) {
        false
    }

    // ------------------------------------------------------------------ SIM accounts

    private fun phoneAccounts(): List<Map<String, Any?>> {
        val telecom = telecom() ?: return emptyList()
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) {
            return emptyList()
        }
        val tm = activity.getSystemService(TelephonyManager::class.java)
        return try {
            telecom.callCapablePhoneAccounts.mapIndexed { index, handle ->
                val account = telecom.getPhoneAccount(handle)
                val sub = if (Build.VERSION.SDK_INT >= 30) tm?.getSubscriptionId(handle) else null
                mapOf(
                    "id" to handle.id,
                    "label" to (account?.label?.toString() ?: "SIM ${index + 1}"),
                    "subscriptionId" to sub?.takeIf { it >= 0 },
                    "index" to index,
                )
            }
        } catch (e: SecurityException) {
            emptyList()
        }
    }

    private fun handleFor(subscriptionId: Int?): PhoneAccountHandle? {
        if (subscriptionId == null || Build.VERSION.SDK_INT < 30) return null
        val telecom = telecom() ?: return null
        val tm = activity.getSystemService(TelephonyManager::class.java) ?: return null
        return try {
            telecom.callCapablePhoneAccounts.firstOrNull { tm.getSubscriptionId(it) == subscriptionId }
        } catch (e: SecurityException) {
            null
        }
    }

    // ------------------------------------------------------------------ calling

    private fun hasCallPermission() =
        ContextCompat.checkSelfPermission(activity, Manifest.permission.CALL_PHONE) == PackageManager.PERMISSION_GRANTED

    private fun requestCallPermission(result: MethodChannel.Result) {
        if (hasCallPermission()) {
            result.success(true)
            return
        }
        if (pendingPermission != null) {
            result.error("busy", "A permission request is already showing", null)
            return
        }
        pendingPermission = result
        try {
            permissionLauncher.launch(Manifest.permission.CALL_PHONE)
        } catch (e: Exception) {
            pendingPermission = null
            result.error("request_failed", e.javaClass.simpleName, null)
        }
    }

    private fun placeCall(number: String?, subscriptionId: Int?, result: MethodChannel.Result) {
        val clean = number?.filter { it.isDigit() || it == '+' || it == '*' || it == '#' }
        if (clean.isNullOrEmpty()) {
            result.success("invalid_number")
            return
        }
        if (!hasCallPermission()) {
            result.success("permission_denied")
            return
        }
        val telecom = telecom()
        if (telecom == null) {
            result.success("unavailable")
            return
        }
        val extras = Bundle()
        handleFor(subscriptionId)?.let { extras.putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, it) }
        try {
            telecom.placeCall(Uri.fromParts("tel", clean, null), extras)
            result.success("placed")
        } catch (e: SecurityException) {
            result.success("permission_denied")
        }
    }

    companion object {
        const val CHANNEL = "com.crmapp.mobile/dialer"
        const val EVENTS = "com.crmapp.mobile/dialer_events"
        private const val TAG = "CrmDialer"
    }
}
