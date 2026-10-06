package com.crmapp.mobile

import android.content.Context
import org.json.JSONObject

/**
 * A small copy of the member's leads (name, last 10 digits, status), kept for ONE reason: an incoming
 * call can arrive while the app isn't running, and the call screen should still show who it is. The
 * app refreshes it whenever it opens. Stored in the app's private storage; never logged.
 */
object LeadCache {
    class Match(val name: String, val status: String?)

    private const val PREFS = "crm_dialer_leads"
    private const val KEY = "leads"
    private const val MAX = 500

    fun key(number: String?): String? {
        val digits = number?.filter { it.isDigit() } ?: return null
        return if (digits.length >= 10) digits.takeLast(10) else null
    }

    fun replace(context: Context, leads: List<Map<String, Any?>>) {
        val out = JSONObject()
        for (lead in leads.take(MAX)) {
            val k = key(lead["phone"]?.toString()) ?: continue
            val name = lead["name"]?.toString()?.takeIf { it.isNotBlank() } ?: continue
            out.put(k, JSONObject().put("name", name).put("status", lead["status"]?.toString()))
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, out.toString()).apply()
    }

    fun lookup(context: Context, number: String?): Match? {
        val k = key(number) ?: return null
        return try {
            val json = JSONObject(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, "{}") ?: "{}")
            val item = json.optJSONObject(k) ?: return null
            Match(item.optString("name"), item.optString("status").takeIf { it.isNotBlank() && it != "null" })
        } catch (e: Exception) {
            null
        }
    }

}
