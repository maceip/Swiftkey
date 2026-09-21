package com.pureswift.swiftandroid

import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Looper
import android.system.Os
import android.util.AtomicFile
import android.util.Base64
import android.util.JsonReader
import android.util.JsonToken
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileNotFoundException
import java.io.FileOutputStream
import java.io.InputStream
import java.io.StringReader
import java.net.HttpURLConnection
import java.net.URI
import java.net.SocketTimeoutException
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import org.json.JSONObject

/** V2 transport and durable journal, isolated from v1 files and Android backup. */
internal object PhoneProtocolIO {
    private const val CONFIG = "swiftkey-pairing-v2-config.json"
    private const val STATE = "swiftkey-pairing-v2-state.json"
    private const val MAX_BYTES = 2 * 1024 * 1024

    @Synchronized fun readConfiguration(context: Context): String = safe { read(context, CONFIG) }
    @Synchronized fun readState(context: Context): String = safe { read(context, STATE) }
    @Synchronized fun writeState(context: Context, json: String): String = safe { write(context, STATE, json) }
    @Synchronized fun saveConfiguration(context: Context, json: String): String = safe {
        val config = JSONObject(validateJSON(json))
        val debug = isDebug(context)
        val origin = PhoneHostPolicy.canonicalOrigin(config.getString("serverURL"), debug)
        val key = Base64.decode(config.getString("serverPublicKey"), Base64.NO_WRAP)
        require(key.size == 65 && key[0] == 4.toByte())
        require(Base64.encodeToString(key, Base64.NO_WRAP) == config.getString("serverPublicKey"))
        val audience = config.optString("audience", "swiftkey-authority-v2")
        val workload = config.optString("workloadAudience", "swiftkey.local")
        require(audience == "swiftkey-authority-v2")
        require(workload.isNotBlank() && workload.toByteArray(Charsets.UTF_8).size <= 256 && workload.none { it.code < 0x20 })
        require(config.keys().asSequence().all { it in setOf("serverURL", "serverPublicKey", "audience", "workloadAudience") })
        config.put("serverURL", origin).put("audience", audience).put("workloadAudience", workload)
        val previous = JSONObject(read(context, CONFIG))
        val unchanged = previous.optString("serverURL") == origin && previous.optString("serverPublicKey") == config.getString("serverPublicKey")
            && previous.optString("audience", "swiftkey-authority-v2") == audience && previous.optString("workloadAudience", "swiftkey.local") == workload
        // Never rebind a retained identity/journal to a different authority.
        val hasRoot = JSONObject(HardwareKeyStore.rootStatusV2()).getBoolean("exists")
        if ((hasRoot || JSONObject(read(context, STATE)).length() != 0) && !unchanged) {
            return@safe error("configurationLocked")
        }
        write(context, CONFIG, config.toString())
    }
    fun post(context: Context, url: String, body: String, bearer: String): String {
        var connection: HttpURLConnection? = null
        return try {
            require(Looper.myLooper() != Looper.getMainLooper())
            val config = JSONObject(readConfiguration(context))
            PhoneHostPolicy.validateEndpoint(url, config.getString("serverURL"), isDebug(context))
            require(bearer.length <= 8192 && bearer.all { it.code in 0x21..0x7e })
            val payload = validateJSON(body).toByteArray(Charsets.UTF_8)
            connection = URI(url).toURL().openConnection() as HttpURLConnection
            connection.apply {
                requestMethod = "POST"
                instanceFollowRedirects = false
                connectTimeout = 10_000; readTimeout = 20_000
                useCaches = false; doOutput = true
                setRequestProperty("Content-Type", "application/json; charset=utf-8")
                setRequestProperty("Accept", "application/json")
                if (bearer.isNotEmpty()) setRequestProperty("Authorization", "Bearer $bearer")
                setFixedLengthStreamingMode(payload.size)
            }
            connection.outputStream.use { it.write(payload) }
            val status = connection.responseCode
            if (status !in 200..299) {
                val code = try {
                    val response = connection.errorStream?.use { JSONObject(readJSON(it, 8192)) }
                    PhoneHostPolicy.authorityErrorCode(status, response?.opt("code") as? String,
                        response?.opt("error") is String, body, bearer)
                } catch (_: Exception) { null }
                if (code != null) JSONObject().put("code", code).put("error", code).put("httpStatus", status).toString()
                else JSONObject().put("error", "httpFailure").put("httpStatus", status).toString()
            } else {
                require(connection.contentLengthLong <= MAX_BYTES)
                connection.inputStream.use { readJSON(it) }
            }
        } catch (_: SocketTimeoutException) { error("requestTimedOut") }
        catch (_: Exception) { error("networkUnavailable") }
        finally { connection?.disconnect() }
    }
    private fun isDebug(context: Context): Boolean = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
    private fun read(context: Context, name: String): String {
        val base = File(context.noBackupFilesDir, name)
        return try { AtomicFile(base).openRead().use { readJSON(it) } }
        catch (failure: FileNotFoundException) {
            if (base.exists() || File(base.path + ".bak").exists()) throw failure
            "{}"
        }
    }
    private fun write(context: Context, name: String, json: String): String {
        val bytes = validateJSON(json).toByteArray(Charsets.UTF_8)
        val file = AtomicFile(File(context.noBackupFilesDir, name))
        var stream: FileOutputStream? = null
        try {
            stream = file.startWrite()
            Os.fchmod(stream.fd, 0x180)
            stream.write(bytes); stream.fd.sync(); file.finishWrite(stream); stream = null
            check(file.openRead().use { readJSON(it) } == json)
            return JSONObject().put("ok", true).toString()
        } finally { if (stream != null) file.failWrite(stream) }
    }
    private fun readJSON(input: InputStream, maximum: Int = MAX_BYTES): String {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val size = input.read(buffer)
            if (size < 0) break
            require(output.size() + size <= maximum)
            output.write(buffer, 0, size)
        }
        val text = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(output.toByteArray())).toString()
        return validateJSON(text)
    }
    private fun validateJSON(text: String): String {
        require(text.toByteArray(Charsets.UTF_8).size <= MAX_BYTES)
        JsonReader(StringReader(text)).use {
            it.isLenient = false
            require(it.peek() == JsonToken.BEGIN_OBJECT); it.skipValue(); require(it.peek() == JsonToken.END_DOCUMENT)
        }
        return text
    }
    private fun safe(block: () -> String): String = try { block() } catch (_: Exception) { error("storageUnavailable") }
    private fun error(code: String): String = JSONObject().put("error", code).toString()
}
