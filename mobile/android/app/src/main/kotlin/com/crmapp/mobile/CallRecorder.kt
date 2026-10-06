package com.crmapp.mobile

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import android.provider.CallLog
import android.provider.DocumentsContract
import android.util.Log
import androidx.core.content.ContextCompat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Records one phone call at a time from the microphone into the folder the employee picked
 * (Settings > Change Call Recordings Location). Android doesn't let apps capture the call's own
 * audio stream, so — like other call recorders — this records what the phone's microphone hears;
 * how clearly the other person comes through depends on the phone (best on speaker).
 *
 * Files are named `CRM_<number>_<yyyyMMdd_HHmmss>.m4a` so the call-sync matcher can pair them
 * with the right call. Never logs numbers.
 */
class CallRecorder(private val context: Context) {
    private var recorder: MediaRecorder? = null
    private var output: ParcelFileDescriptor? = null
    private var document: Uri? = null
    private var startedAt = 0L

    val isRecording get() = recorder != null

    fun start(folderTree: Uri): Boolean {
        if (recorder != null) return true
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            Log.w(TAG, "Not recording: microphone permission missing")
            return false
        }
        startedAt = System.currentTimeMillis()
        val doc = try {
            val parent = DocumentsContract.buildDocumentUriUsingTree(folderTree, DocumentsContract.getTreeDocumentId(folderTree))
            DocumentsContract.createDocument(context.contentResolver, parent, "audio/mp4", "CRM_call_${stamp(startedAt)}.m4a")
        } catch (e: Exception) {
            Log.w(TAG, "Not recording: can't create a file in the folder (${e.javaClass.simpleName})")
            null
        } ?: return false

        // VOICE_RECOGNITION first: measured on a real call, it is the source Android still lets an app
        // record during a call (the plain MIC source recorded pure silence, 2026-10-02). It only
        // carries the member's own voice, plus the customer's when that comes out of the speaker.
        for (source in intArrayOf(MediaRecorder.AudioSource.VOICE_RECOGNITION, MediaRecorder.AudioSource.MIC)) {
            val pfd = try {
                context.contentResolver.openFileDescriptor(doc, "rw")
            } catch (e: Exception) {
                null
            } ?: break
            val r = newRecorder()
            try {
                r.setAudioSource(source)
                r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                r.setAudioChannels(1)
                r.setAudioSamplingRate(16000)
                r.setAudioEncodingBitRate(48000)
                r.setOutputFile(pfd.fileDescriptor)
                r.prepare()
                r.start()
                recorder = r
                output = pfd
                document = doc
                Log.i(TAG, "Recording started (source $source)")
                return true
            } catch (e: Exception) {
                Log.w(TAG, "Recorder source $source failed (${e.javaClass.simpleName})")
                r.release()
                pfd.close()
            }
        }
        deleteQuietly(doc)
        return false
    }

    /** Stops and finalises the file, then renames it with the call's number from the call log. */
    fun stop(knownNumber: String? = null) {
        val r = recorder ?: return
        val doc = document
        var ok = true
        try {
            r.stop()
        } catch (e: RuntimeException) {
            // Thrown when nothing was captured (call ended instantly).
            ok = false
        } finally {
            r.release()
            output?.close()
            recorder = null
            output = null
            document = null
        }
        if (doc == null) return
        if (!ok) {
            deleteQuietly(doc)
            Log.i(TAG, "Recording discarded (too short)")
            return
        }
        Log.i(TAG, "Recording saved")
        // The CRM dialer knows the number, so no call-log lookup is needed.
        val digits = knownNumber?.filter { it.isDigit() }?.takeLast(12)
        if (!digits.isNullOrEmpty()) {
            try {
                DocumentsContract.renameDocument(context.contentResolver, doc, "CRM_${digits}_${stamp(startedAt)}.m4a")
            } catch (e: Exception) {
                // Keeps the time-only name; the matcher still pairs it by time.
            }
            return
        }
        finishFile(doc, startedAt)
    }

    private class CallRow(val number: String?, val type: Int, val date: Long, val duration: Long)

    /**
     * Once the call log has the call: delete the file if it was an outgoing call nobody picked up
     * (it only holds ringing), otherwise put the number in its name so the sync can match it.
     */
    @SuppressLint("MissingPermission")
    private fun finishFile(doc: Uri, callStart: Long) {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CALL_LOG) != PackageManager.PERMISSION_GRANTED) return
        Thread {
            try {
                // The call log row is written a moment after hang-up.
                var row: CallRow? = null
                for (attempt in 0 until 4) {
                    Thread.sleep(if (attempt == 0) 2500L else 2000L)
                    row = latestCallSince(callStart - 120_000)
                    if (row != null) break
                }
                val found = row ?: return@Thread
                if (found.type == CallLog.Calls.OUTGOING_TYPE && found.duration == 0L && Math.abs(found.date - callStart) < 20_000) {
                    deleteQuietly(doc)
                    Log.i(TAG, "Recording deleted (call was not answered)")
                    return@Thread
                }
                val digits = found.number?.filter { it.isDigit() }?.takeLast(12)
                if (!digits.isNullOrEmpty()) {
                    DocumentsContract.renameDocument(context.contentResolver, doc, "CRM_${digits}_${stamp(callStart)}.m4a")
                }
            } catch (e: Exception) {
                // Keeps the time-only name; the matcher still pairs it by time.
            }
        }.start()
    }

    @SuppressLint("MissingPermission")
    private fun latestCallSince(sinceMillis: Long): CallRow? {
        context.contentResolver.query(
            CallLog.Calls.CONTENT_URI,
            arrayOf(CallLog.Calls.NUMBER, CallLog.Calls.TYPE, CallLog.Calls.DATE, CallLog.Calls.DURATION),
            "${CallLog.Calls.DATE} >= ?",
            arrayOf(sinceMillis.toString()),
            "${CallLog.Calls.DATE} DESC",
        )?.use { c ->
            if (c.moveToFirst()) return CallRow(c.getString(0), c.getInt(1), c.getLong(2), c.getLong(3))
        }
        return null
    }

    private fun deleteQuietly(doc: Uri) {
        try {
            DocumentsContract.deleteDocument(context.contentResolver, doc)
        } catch (e: Exception) {
        }
    }

    @Suppress("DEPRECATION")
    private fun newRecorder(): MediaRecorder = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(context) else MediaRecorder()

    private fun stamp(millis: Long) = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date(millis))

    companion object {
        private const val TAG = "CrmCallRecorder"
    }
}
