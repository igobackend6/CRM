package com.crmapp.mobile

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.CallLog
import android.provider.DocumentsContract
import android.provider.Settings
import android.telecom.TelecomManager
import android.telephony.TelephonyManager
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Settings > Sync Call History and the call-recordings folder.
 *
 * Read-only access to (1) the phone's call log, and (2) the folder the employee picked where the
 * phone's own call recorder saves its files (Android doesn't let third-party apps record calls,
 * so recordings are picked up from there). Never logs numbers.
 */
class CallSyncChannel(private val activity: FragmentActivity) {
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private var pendingPermission: MethodChannel.Result? = null
    private var pendingFolder: MethodChannel.Result? = null
    private var pendingMic: MethodChannel.Result? = null
    private var pendingNotifications: MethodChannel.Result? = null

    private val notificationsLauncher =
        activity.registerForActivityResult(ActivityResultContracts.RequestPermission()) {
            val result = pendingNotifications
            pendingNotifications = null
            result?.success(NotSyncReminder.notificationsAllowed(activity))
        }

    private val micLauncher =
        activity.registerForActivityResult(ActivityResultContracts.RequestPermission()) {
            val result = pendingMic
            pendingMic = null
            result?.success(recorderStatus())
        }

    private val permissionLauncher =
        activity.registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
            val result = pendingPermission
            pendingPermission = null
            result?.success(permissionStatus())
        }

    private val folderLauncher =
        activity.registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
            val result = pendingFolder
            pendingFolder = null
            if (uri == null) {
                result?.success(null)
                return@registerForActivityResult
            }
            try {
                // Keep access across restarts: read (to upload recordings) and write (the CRM's own
                // recorder saves into this folder).
                activity.contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
                result?.success(mapOf("uri" to uri.toString(), "name" to folderName(uri)))
            } catch (e: Exception) {
                result?.error("folder_failed", e.javaClass.simpleName, null)
            }
        }

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPermissionStatus" -> result.success(permissionStatus())
                "requestPermission" -> requestPermission(result)
                "readCallLog" -> background(result) { readCallLog((call.argument<Number>("sinceMillis") ?: 0).toLong()) }
                "pickRecordingFolder" -> pickFolder(result)
                "hasFolderAccess" -> result.success(hasFolderAccess(call.argument<String>("uri")))
                "listRecordings" -> background(result) {
                    listRecordings(Uri.parse(call.argument<String>("uri")!!), (call.argument<Number>("sinceMillis") ?: 0).toLong())
                }
                "readFile" -> background(result) { readFile(Uri.parse(call.argument<String>("uri")!!)) }
                "recordingsDirectory" -> result.success(recordingsDirectory())
                "scheduleNotSyncReminder" -> {
                    NotSyncReminder.schedule(
                        activity,
                        (call.argument<Number>("triggerAtMillis") ?: 0).toLong(),
                        call.argument<Int>("hours") ?: 0,
                    )
                    result.success(true)
                }
                "cancelNotSyncReminder" -> {
                    NotSyncReminder.cancel(activity)
                    result.success(true)
                }
                "scheduleCallBack" -> {
                    CallBackReminders.schedule(
                        activity,
                        call.argument<String>("leadId") ?: "",
                        (call.argument<Number>("triggerAtMillis") ?: 0).toLong(),
                        call.argument<String>("title") ?: "",
                        call.argument<String>("text") ?: "",
                    )
                    result.success(true)
                }
                "cancelCallBack" -> {
                    CallBackReminders.cancel(activity, call.argument<String>("leadId") ?: "")
                    result.success(true)
                }
                "cancelAllCallBacks" -> {
                    CallBackReminders.cancelAll(activity)
                    result.success(true)
                }
                "takeSharedAudio" -> result.success(SharedAudio.take())
                "takeLaunchLead" -> result.success(LaunchTarget.take())
                "showNotSyncReminderNow" -> result.success(NotSyncReminder.showNow(activity, call.argument<Int>("hours") ?: 2))
                "notificationsAllowed" -> result.success(NotSyncReminder.notificationsAllowed(activity))
                "requestNotifications" -> requestNotifications(result)
                "openNotificationSettings" -> result.success(openNotificationSettings())
                "recorderStatus" -> result.success(recorderStatus())
                "requestMicrophone" -> requestMicrophone(result)
                "openAccessibilitySettings" -> result.success(CallRecorderService.openSettings(activity))
                "configureRecorder" -> {
                    CallRecorderConfig.write(
                        activity,
                        CallRecorderConfig(
                            call.argument<Boolean>("enabled") ?: false,
                            call.argument<Int>("subscriptionId"),
                            call.argument<String>("folderUri"),
                            call.argument<Boolean>("speaker") ?: true,
                        ),
                    )
                    CallRecorderService.instance?.reconfigure()
                    result.success(recorderStatus())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        io.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: SecurityException) {
                main.post { result.error("permission_denied", e.javaClass.simpleName, null) }
            } catch (e: Exception) {
                main.post { result.error("read_failed", e.javaClass.simpleName, null) }
            }
        }
    }

    // ---------------------------------------------------------------- permission

    private fun isGranted(permission: String) =
        ContextCompat.checkSelfPermission(activity, permission) == PackageManager.PERMISSION_GRANTED

    private val prefs get() = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** granted | notRequested | denied | permanentlyDenied — same meanings as SimChannel. */
    private fun permissionStatus(): String {
        if (isGranted(Manifest.permission.READ_CALL_LOG)) return "granted"
        if (!prefs.getBoolean(KEY_REQUESTED, false)) return "notRequested"
        return if (activity.shouldShowRequestPermissionRationale(Manifest.permission.READ_CALL_LOG)) "denied" else "permanentlyDenied"
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (isGranted(Manifest.permission.READ_CALL_LOG)) {
            result.success("granted")
            return
        }
        if (pendingPermission != null) {
            result.error("busy", "A permission request is already showing", null)
            return
        }
        prefs.edit().putBoolean(KEY_REQUESTED, true).apply()
        pendingPermission = result
        try {
            permissionLauncher.launch(arrayOf(Manifest.permission.READ_CALL_LOG))
        } catch (e: Exception) {
            pendingPermission = null
            result.error("request_failed", e.javaClass.simpleName, null)
        }
    }

    // ---------------------------------------------------------------- recorder

    /** {microphone, accessibility, folderWritable} for Settings > Sync Call History > Record calls. */
    private fun recorderStatus(): Map<String, Any?> {
        val folder = CallRecorderConfig.read(activity).folderUri
        return mapOf(
            "microphone" to isGranted(Manifest.permission.RECORD_AUDIO),
            "microphoneAskedBefore" to prefs.getBoolean(KEY_MIC_REQUESTED, false),
            "microphoneRationale" to activity.shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO),
            "accessibility" to CallRecorderService.isEnabled(activity),
            "folderWritable" to (folder != null && activity.contentResolver.persistedUriPermissions.any {
                it.uri.toString() == folder && it.isWritePermission
            }),
        )
    }

    private fun requestNotifications(result: MethodChannel.Result) {
        if (NotSyncReminder.notificationsAllowed(activity) || Build.VERSION.SDK_INT < 33) {
            result.success(NotSyncReminder.notificationsAllowed(activity))
            return
        }
        if (pendingNotifications != null) {
            result.error("busy", "A permission request is already showing", null)
            return
        }
        pendingNotifications = result
        try {
            notificationsLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        } catch (e: Exception) {
            pendingNotifications = null
            result.error("request_failed", e.javaClass.simpleName, null)
        }
    }

    private fun openNotificationSettings(): Boolean = try {
        activity.startActivity(
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        true
    } catch (e: Exception) {
        false
    }

    private fun requestMicrophone(result: MethodChannel.Result) {
        if (isGranted(Manifest.permission.RECORD_AUDIO)) {
            result.success(recorderStatus())
            return
        }
        if (pendingMic != null) {
            result.error("busy", "A permission request is already showing", null)
            return
        }
        prefs.edit().putBoolean(KEY_MIC_REQUESTED, true).apply()
        pendingMic = result
        try {
            micLauncher.launch(Manifest.permission.RECORD_AUDIO)
        } catch (e: Exception) {
            pendingMic = null
            result.error("request_failed", e.javaClass.simpleName, null)
        }
    }

    // ---------------------------------------------------------------- call log

    @SuppressLint("MissingPermission") // READ_CALL_LOG checked below; READ_PHONE_STATE checked where used.
    private fun readCallLog(sinceMillis: Long): List<Map<String, Any?>> {
        if (!isGranted(Manifest.permission.READ_CALL_LOG)) throw SecurityException("READ_CALL_LOG")
        val accounts = phoneAccountSubscriptions()
        val projection = arrayOf(
            CallLog.Calls._ID,
            CallLog.Calls.NUMBER,
            CallLog.Calls.TYPE,
            CallLog.Calls.DATE,
            CallLog.Calls.DURATION,
            CallLog.Calls.PHONE_ACCOUNT_ID,
        )
        val rows = mutableListOf<Map<String, Any?>>()
        activity.contentResolver.query(
            CallLog.Calls.CONTENT_URI,
            projection,
            "${CallLog.Calls.DATE} >= ?",
            arrayOf(sinceMillis.toString()),
            "${CallLog.Calls.DATE} ASC",
        )?.use { c ->
            val id = c.getColumnIndexOrThrow(CallLog.Calls._ID)
            val number = c.getColumnIndexOrThrow(CallLog.Calls.NUMBER)
            val type = c.getColumnIndexOrThrow(CallLog.Calls.TYPE)
            val date = c.getColumnIndexOrThrow(CallLog.Calls.DATE)
            val duration = c.getColumnIndexOrThrow(CallLog.Calls.DURATION)
            val account = c.getColumnIndexOrThrow(CallLog.Calls.PHONE_ACCOUNT_ID)
            while (c.moveToNext()) {
                val accountId = if (c.isNull(account)) null else c.getString(account)
                rows.add(
                    mapOf(
                        "id" to c.getLong(id),
                        "number" to (if (c.isNull(number)) null else c.getString(number)),
                        "type" to c.getInt(type),
                        "date" to c.getLong(date),
                        "duration" to c.getLong(duration),
                        "subscriptionId" to (accountId?.let { accounts[it] ?: it.toIntOrNull() }),
                    ),
                )
            }
        }
        return rows
    }

    /** PhoneAccountHandle id -> subscription id, so a call can be tied to the SIM it used. */
    @SuppressLint("MissingPermission")
    private fun phoneAccountSubscriptions(): Map<String, Int> {
        val map = mutableMapOf<String, Int>()
        if (Build.VERSION.SDK_INT < 30 || !isGranted(Manifest.permission.READ_PHONE_STATE)) return map
        try {
            val telecom = activity.getSystemService(TelecomManager::class.java) ?: return map
            val tm = activity.getSystemService(TelephonyManager::class.java) ?: return map
            for (handle in telecom.callCapablePhoneAccounts) {
                val subId = tm.getSubscriptionId(handle)
                if (subId >= 0) map[handle.id] = subId
            }
        } catch (e: Exception) {
            // Falls back to a numeric PHONE_ACCOUNT_ID, else "unknown SIM".
        }
        return map
    }

    // ---------------------------------------------------------------- recordings folder

    private fun pickFolder(result: MethodChannel.Result) {
        if (pendingFolder != null) {
            result.error("busy", "The folder picker is already showing", null)
            return
        }
        pendingFolder = result
        try {
            folderLauncher.launch(null)
        } catch (e: Exception) {
            pendingFolder = null
            result.error("picker_failed", e.javaClass.simpleName, null)
        }
    }

    private fun hasFolderAccess(uri: String?): Boolean {
        if (uri == null) return false
        return activity.contentResolver.persistedUriPermissions.any { it.uri.toString() == uri && it.isReadPermission }
    }

    private fun folderName(tree: Uri): String = try {
        val docId = DocumentsContract.getTreeDocumentId(tree)
        // "primary:Music/Recordings/Call Recordings" -> "Music/Recordings/Call Recordings"
        docId.substringAfter(':', docId).ifEmpty { "Internal storage" }
    } catch (e: Exception) {
        "Selected folder"
    }

    /** Audio files under the picked folder (up to 4 levels deep) modified since [sinceMillis]. */
    private fun listRecordings(tree: Uri, sinceMillis: Long): List<Map<String, Any?>> {
        val files = mutableListOf<Map<String, Any?>>()
        val rootDoc = DocumentsContract.getTreeDocumentId(tree)
        walk(tree, rootDoc, 0, sinceMillis, files)
        return files
    }

    private fun walk(tree: Uri, docId: String, depth: Int, sinceMillis: Long, out: MutableList<Map<String, Any?>>) {
        if (depth > 4 || out.size >= 5000) return
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, docId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        val c = activity.contentResolver.query(children, projection, null, null, null) ?: return
        val subfolders = mutableListOf<String>()
        try {
            while (c.moveToNext()) {
                val childId = c.getString(0)
                val name = c.getString(1)
                val mime = c.getString(2) ?: ""
                if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                    subfolders.add(childId)
                    continue
                }
                val modified = if (c.isNull(4)) 0L else c.getLong(4)
                val audioMime = if (name == null) null else audioMimeFor(name, mime)
                if (name == null || audioMime == null || modified < sinceMillis) continue
                out.add(
                    mapOf(
                        "uri" to DocumentsContract.buildDocumentUriUsingTree(tree, childId).toString(),
                        "name" to name,
                        "mimeType" to audioMime,
                        "size" to (if (c.isNull(3)) 0L else c.getLong(3)),
                        "lastModified" to modified,
                    ),
                )
            }
        } finally {
            c.close()
        }
        for (sub in subfolders) walk(tree, sub, depth + 1, sinceMillis, out)
    }

    // The file's own extension is more reliable than the folder provider's guess (some report .m4a as mp3).
    private fun audioMimeFor(name: String, mime: String): String? {
        val byExtension = when (name.substringAfterLast('.', "").lowercase()) {
            "m4a", "mp4", "aac" -> "audio/mp4"
            "amr" -> "audio/amr"
            "mp3" -> "audio/mpeg"
            "wav" -> "audio/wav"
            "ogg", "opus" -> "audio/ogg"
            "3gp" -> "audio/3gpp"
            else -> null
        }
        return byExtension ?: if (mime.startsWith("audio/")) mime else null
    }

    private fun readFile(uri: Uri): ByteArray {
        activity.contentResolver.openInputStream(uri).use { input ->
            if (input == null) throw IllegalStateException("No stream")
            return input.readBytes()
        }
    }

    /** Where the app keeps its own copies of recordings (app-specific storage, no permission needed). */
    private fun recordingsDirectory(): String {
        val base = activity.getExternalFilesDir(Environment.DIRECTORY_MUSIC) ?: activity.filesDir
        val dir = File(base, "CallRecordings")
        dir.mkdirs()
        return dir.absolutePath
    }

    companion object {
        const val CHANNEL = "com.crmapp.mobile/call_sync"
        private const val PREFS = "crm_call_sync_channel"
        private const val KEY_REQUESTED = "call_log_permission_requested"
        private const val KEY_MIC_REQUESTED = "microphone_permission_requested"
    }
}
