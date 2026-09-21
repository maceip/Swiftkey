package com.pureswift.swiftandroid

import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Looper
import android.system.Os
import android.util.AtomicFile
import android.util.JsonReader
import android.util.JsonToken
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileNotFoundException
import java.io.FileOutputStream
import java.io.InputStream
import java.io.StringReader
import java.net.HttpURLConnection
import java.net.Proxy
import java.net.URI
import java.net.SocketTimeoutException
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import org.json.JSONObject

/** App-private protocol state and the explicitly scoped adb-reverse demo transport. */
internal object ProtocolIO {
    private const val MAXIMUM_BYTES = 1024 * 1024
    private const val MAXIMUM_ERROR_BYTES = 4096
    private const val STATE_FILE = "swiftkey-protocol-state.json"
    private const val CONFIG_FILE = "swiftkey-client.json"
    private val ERROR_CODE = Regex("[A-Za-z][A-Za-z0-9_.:-]{0,127}")

    fun postJSON(context: Context?, url: String, body: String, bootstrapToken: String): String {
        var connection: HttpURLConnection? = null
        return try {
            if (Looper.myLooper() == Looper.getMainLooper()) {
                throw InputFailure("network requests must run on a worker thread")
            }
            val app = context ?: throw InputFailure("application context is not initialized")
            if ((app.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) == 0) {
                throw InputFailure("loopback demo transport is available only in a debug app")
            }
            val uri = URI(url)
            if (uri.scheme != "http" || uri.host != "127.0.0.1" || uri.port !in 1..65535 ||
                uri.rawAuthority != "127.0.0.1:${uri.port}" || uri.rawFragment != null ||
                uri.rawUserInfo != null || uri.rawQuery != null
            ) {
                throw InputFailure("demo URL must use http://127.0.0.1 with an explicit port")
            }
            if (bootstrapToken.length > 4096 || bootstrapToken.any { it.code !in 0x21..0x7e }) {
                throw InputFailure("bootstrap token format is invalid")
            }
            val request = jsonBytes(body)
            connection = uri.toURL().openConnection(Proxy.NO_PROXY) as HttpURLConnection
            connection.apply {
                requestMethod = "POST"
                instanceFollowRedirects = false
                connectTimeout = 10_000
                readTimeout = 20_000
                useCaches = false
                doOutput = true
                setRequestProperty("Content-Type", "application/json; charset=utf-8")
                setRequestProperty("Accept", "application/json")
                if (bootstrapToken.isNotEmpty()) {
                    setRequestProperty("Authorization", "Bearer $bootstrapToken")
                }
                setFixedLengthStreamingMode(request.size)
            }
            connection.outputStream.use { it.write(request) }
            val status = connection.responseCode
            if (status !in 200..299) {
                responseError(connection, status, bootstrapToken)
            } else {
                if (connection.contentLengthLong > MAXIMUM_BYTES) {
                    throw InputFailure("server response exceeds 1 MiB")
                }
                connection.inputStream.use { readJSON(it) }
            }
        } catch (error: InputFailure) {
            errorJSON(error.message ?: "invalid protocol input")
        } catch (_: SocketTimeoutException) {
            errorJSON("loopback server request timed out")
        } catch (_: Exception) {
            errorJSON("loopback server request failed")
        } finally {
            connection?.disconnect()
        }
    }

    @Synchronized
    fun readConfiguration(context: Context?): String = readFile(context, CONFIG_FILE)

    @Synchronized
    fun readState(context: Context?): String = readFile(context, STATE_FILE)

    @Synchronized
    fun writeState(context: Context?, json: String): String {
        var file: AtomicFile? = null
        var stream: FileOutputStream? = null
        return try {
            val app = context ?: throw InputFailure("application context is not initialized")
            val bytes = jsonBytes(json)
            file = AtomicFile(File(app.filesDir, STATE_FILE))
            stream = file.startWrite()
            Os.fchmod(stream.fd, 0x180) // 0600: readable/writable only by the app UID.
            stream.write(bytes)
            stream.fd.sync()
            file.finishWrite(stream)
            stream = null
            // AtomicFile can log a failed sync/rename instead of throwing. Do
            // not report saved state until the committed file can be read back.
            if (file.openRead().use { readJSON(it) } != json) {
                throw InputFailure("protocol state was not committed")
            }
            JSONObject().put("ok", true).toString()
        } catch (error: InputFailure) {
            errorJSON(error.message ?: "invalid state JSON")
        } catch (_: Exception) {
            errorJSON("could not persist protocol state")
        } finally {
            if (stream != null) file?.failWrite(stream)
        }
    }

    private fun readFile(context: Context?, name: String): String = try {
        val app = context ?: throw InputFailure("application context is not initialized")
        val base = File(app.filesDir, name)
        try {
            AtomicFile(base).openRead().use { readJSON(it) }
        } catch (error: FileNotFoundException) {
            // An inaccessible existing file is a failure, not empty client state.
            if (base.exists() || File(base.path + ".bak").exists()) throw error
            "{}"
        }
    } catch (error: InputFailure) {
        errorJSON(error.message ?: "invalid stored JSON")
    } catch (_: Exception) {
        errorJSON("could not read protocol state or configuration")
    }

    private fun responseError(connection: HttpURLConnection, status: Int, token: String): String {
        val code = try {
            connection.errorStream?.use { stream ->
                val response = JSONObject(readJSON(stream, MAXIMUM_ERROR_BYTES))
                sequenceOf(response.opt("code"), response.opt("error"))
                    .filterIsInstance<String>()
                    .firstOrNull {
                        ERROR_CODE.matches(it) && (token.isEmpty() || !it.contains(token))
                    }
            }
        } catch (_: Exception) {
            null
        }
        // Retain stable protocol codes for replay/error handling, never arbitrary
        // server prose, response bodies, or credentials. HTTP status survives even
        // an invalid or interrupted error response.
        return JSONObject()
            .put("error", code ?: "server returned HTTP $status")
            .put("httpStatus", status)
            .toString()
    }

    private fun readJSON(input: InputStream, maximumBytes: Int = MAXIMUM_BYTES): String {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val count = input.read(buffer)
            if (count == -1) break
            if (output.size() + count > maximumBytes) {
                throw InputFailure("JSON object exceeds the allowed size")
            }
            output.write(buffer, 0, count)
        }
        val text = Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(output.toByteArray()))
            .toString()
        jsonBytes(text)
        return text
    }

    private fun jsonBytes(text: String): ByteArray {
        if (text.length > MAXIMUM_BYTES) throw InputFailure("JSON object exceeds 1 MiB")
        val bytes = text.toByteArray(Charsets.UTF_8)
        if (bytes.size > MAXIMUM_BYTES) throw InputFailure("JSON object exceeds 1 MiB")
        try {
            JsonReader(StringReader(text)).use { reader ->
                reader.isLenient = false
                if (reader.peek() != JsonToken.BEGIN_OBJECT) {
                    throw InputFailure("protocol value must be one JSON object")
                }
                reader.skipValue()
                if (reader.peek() != JsonToken.END_DOCUMENT) {
                    throw InputFailure("protocol value must be one JSON object")
                }
            }
        } catch (_: java.io.IOException) {
            throw InputFailure("protocol value is invalid JSON")
        }
        return bytes
    }

    private fun errorJSON(message: String): String = JSONObject().put("error", message).toString()

    private class InputFailure(message: String) : Exception(message)
}
