package com.crmapp.mobile

import android.content.Context
import android.content.Intent
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.util.Log
import java.io.File

/**
 * "Share > Sales CRM" for call recordings. Phone apps that keep their recordings private (Google
 * Phone) can still share one; this receives it, keeps a copy in the app's cache and describes it, so
 * the app can attach it to the right call. Nothing is read until the member shares something.
 */
object SharedAudio {
    private const val TAG = "CrmSharedAudio"
    private const val MAX_BYTES = 60L * 1024 * 1024

    @Volatile
    private var pending: Map<String, Any?>? = null

    /** The last shared recording (returned once), or null. */
    fun take(): Map<String, Any?>? = pending.also { pending = null }

    fun intake(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND) return
        val type = intent.type ?: return
        if (!type.startsWith("audio/") && type != "application/ogg") return
        val uri: Uri = streamOf(intent) ?: return
        try {
            val name = displayName(context, uri) ?: "shared_recording"
            val dir = File(context.cacheDir, "shared_recordings").apply { mkdirs() }
            // Old copies are not needed once they have been attached (or were ignored).
            dir.listFiles()?.forEach { if (System.currentTimeMillis() - it.lastModified() > 24 * 3_600_000L) it.delete() }

            val ext = name.substringAfterLast('.', "").lowercase().takeIf { Regex("[a-z0-9]{1,5}").matches(it) } ?: "m4a"
            val out = File(dir, "shared_${System.currentTimeMillis()}.$ext")
            var size = 0L
            context.contentResolver.openInputStream(uri)?.use { input ->
                out.outputStream().use { output -> size = input.copyTo(output) }
            } ?: return
            if (size <= 0L || size > MAX_BYTES) {
                out.delete()
                return
            }
            pending = mapOf(
                "path" to out.absolutePath,
                "name" to name,
                "mimeType" to type,
                "size" to size,
                "durationMillis" to durationMillis(out),
            )
            // So rotating the phone doesn't import the same file again.
            intent.removeExtra(Intent.EXTRA_STREAM)
            Log.i(TAG, "Recording received (${size / 1024} KB)")
        } catch (e: Exception) {
            Log.w(TAG, "Could not read the shared recording (${e.javaClass.simpleName})")
        }
    }

    @Suppress("DEPRECATION")
    private fun streamOf(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri

    private fun displayName(context: Context, uri: Uri): String? = try {
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        }
    } catch (e: Exception) {
        null
    }

    private fun durationMillis(file: File): Long? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(file.absolutePath)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
        } catch (e: Exception) {
            null
        } finally {
            retriever.release()
        }
    }
}
