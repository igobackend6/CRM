package com.crmapp.mobile

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.telephony.SubscriptionInfo
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Settings > Connected SIM Details: reads the phone's active SIM subscriptions, read-only.
 *
 * Exposes only what Android itself reports (no ICCID/IMEI, nothing inferred). Every field may be
 * null. Never logs SIM numbers.
 */
class SimChannel(private val activity: FragmentActivity) {
    private var pendingPermissionResult: MethodChannel.Result? = null

    // Registered while the activity is being constructed, as registerForActivityResult requires.
    private val permissionLauncher =
        activity.registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
            val result = pendingPermissionResult
            pendingPermissionResult = null
            result?.success(permissionStatus())
        }

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPermissionStatus" -> result.success(permissionStatus())
                "requestPermission" -> requestPermission(result)
                "getActiveSubscriptions" -> readSubscriptions(result)
                "openAppSettings" -> result.success(openAppSettings())
                else -> result.notImplemented()
            }
        }
    }

    private fun hasTelephony(): Boolean {
        val pm = activity.packageManager
        return if (Build.VERSION.SDK_INT >= 33) {
            pm.hasSystemFeature(PackageManager.FEATURE_TELEPHONY_SUBSCRIPTION)
        } else {
            pm.hasSystemFeature(PackageManager.FEATURE_TELEPHONY)
        }
    }

    private fun isGranted(permission: String) =
        ContextCompat.checkSelfPermission(activity, permission) == PackageManager.PERMISSION_GRANTED

    private val prefs get() = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** granted | notRequested | denied | permanentlyDenied | unavailable */
    private fun permissionStatus(): String {
        if (!hasTelephony()) return "unavailable"
        if (isGranted(Manifest.permission.READ_PHONE_STATE)) return "granted"
        if (!prefs.getBoolean(KEY_REQUESTED, false)) return "notRequested"
        // After a request, Android stops offering the rationale once the member has chosen
        // "Don't allow" twice (or "Don't ask again"); only Android Settings can grant it then.
        return if (activity.shouldShowRequestPermissionRationale(Manifest.permission.READ_PHONE_STATE)) {
            "denied"
        } else {
            "permanentlyDenied"
        }
    }

    private fun requestPermission(result: MethodChannel.Result) {
        val status = permissionStatus()
        if (status == "granted" || status == "unavailable") {
            result.success(status)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("busy", "A permission request is already showing", null)
            return
        }
        prefs.edit().putBoolean(KEY_REQUESTED, true).apply()
        pendingPermissionResult = result
        val permissions = mutableListOf(Manifest.permission.READ_PHONE_STATE)
        // Only for showing the SIM's own number when the carrier stored one.
        if (Build.VERSION.SDK_INT >= 26) permissions.add(Manifest.permission.READ_PHONE_NUMBERS)
        try {
            permissionLauncher.launch(permissions.toTypedArray())
        } catch (e: Exception) {
            pendingPermissionResult = null
            result.error("request_failed", e.javaClass.simpleName, null)
        }
    }

    @SuppressLint("MissingPermission") // Checked at the top.
    private fun readSubscriptions(result: MethodChannel.Result) {
        if (!hasTelephony()) {
            result.error("unavailable", "No telephony on this device", null)
            return
        }
        if (!isGranted(Manifest.permission.READ_PHONE_STATE)) {
            result.error("permission_denied", "READ_PHONE_STATE not granted", null)
            return
        }
        try {
            val sm = activity.getSystemService(SubscriptionManager::class.java)
            if (sm == null) {
                result.error("unavailable", "No SubscriptionManager", null)
                return
            }
            val tm = activity.getSystemService(TelephonyManager::class.java)
            val infos: List<SubscriptionInfo> = sm.activeSubscriptionInfoList ?: emptyList()
            result.success(infos.map { info -> toMap(sm, tm, info) })
        } catch (e: SecurityException) {
            result.error("permission_denied", e.javaClass.simpleName, null)
        } catch (e: Exception) {
            result.error("read_failed", e.javaClass.simpleName, null)
        }
    }

    private fun toMap(sm: SubscriptionManager, tm: TelephonyManager?, info: SubscriptionInfo): Map<String, Any?> {
        val slot = info.simSlotIndex.takeIf { it >= 0 }
        return mapOf(
            "subscriptionId" to info.subscriptionId,
            "slotIndex" to slot,
            "carrierName" to info.carrierName?.toString()?.trim()?.takeIf { it.isNotEmpty() },
            "displayName" to info.displayName?.toString()?.trim()?.takeIf { it.isNotEmpty() },
            "phoneNumber" to phoneNumber(sm, info),
            "simState" to simState(tm, slot),
            // Everything returned by getActiveSubscriptionInfoList is active by definition.
            "isActive" to true,
        )
    }

    @SuppressLint("MissingPermission")
    private fun phoneNumber(sm: SubscriptionManager, info: SubscriptionInfo): String? = try {
        val number = if (Build.VERSION.SDK_INT >= 33) {
            sm.getPhoneNumber(info.subscriptionId)
        } else {
            @Suppress("DEPRECATION")
            info.number
        }
        number?.trim()?.takeIf { it.isNotEmpty() }
    } catch (e: Exception) {
        // READ_PHONE_NUMBERS not granted, or the OEM build refuses: the number is simply unavailable.
        null
    }

    private fun simState(tm: TelephonyManager?, slot: Int?): String? {
        if (tm == null || slot == null || Build.VERSION.SDK_INT < 26) return null
        return try {
            when (tm.getSimState(slot)) {
                TelephonyManager.SIM_STATE_READY -> "ready"
                TelephonyManager.SIM_STATE_ABSENT -> "absent"
                TelephonyManager.SIM_STATE_PIN_REQUIRED -> "pinRequired"
                TelephonyManager.SIM_STATE_PUK_REQUIRED -> "pukRequired"
                TelephonyManager.SIM_STATE_NETWORK_LOCKED -> "networkLocked"
                TelephonyManager.SIM_STATE_NOT_READY -> "notReady"
                TelephonyManager.SIM_STATE_PERM_DISABLED -> "disabled"
                TelephonyManager.SIM_STATE_CARD_IO_ERROR -> "cardError"
                TelephonyManager.SIM_STATE_CARD_RESTRICTED -> "restricted"
                else -> "unknown"
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun openAppSettings(): Boolean = try {
        activity.startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", activity.packageName, null))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        true
    } catch (e: Exception) {
        false
    }

    companion object {
        const val CHANNEL = "com.crmapp.mobile/sim"
        private const val PREFS = "crm_sim_channel"
        private const val KEY_REQUESTED = "phone_permission_requested"
    }
}
