package com.pureswift.swiftandroid.passkeys

import android.content.Context
import androidx.credentials.provider.CallingAppInfo
import com.pureswift.swiftandroid.R
import java.net.URI
import java.security.MessageDigest

/** Only OS-authenticated privileged browser/hybrid callers may supply web origins. */
internal object TrustedPasskeyCaller {
    data class Identity(val packageName: String, val origin: String, val signingCertificates: String)

    fun verify(context: Context, caller: CallingAppInfo?, hash: ByteArray?): Identity {
        require(hash?.size == 32) { "A browser client-data hash is required." }
        requireNotNull(caller) { "The browser identity is unavailable." }
        val allowlist = context.resources.openRawResource(R.raw.passkey_privileged_apps)
            .bufferedReader().use { it.readText() }
        val origin = caller.getOrigin(allowlist)
            ?: throw IllegalArgumentException("Native application passkeys are not supported yet.")
        validateWebOrigin(origin)
        val certificates = caller.signingInfoCompat.apkContentsSigners
            .map { certificate -> MessageDigest.getInstance("SHA-256").digest(certificate.toByteArray())
                .joinToString("") { "%02x".format(it) } }.sorted().joinToString(":")
        require(certificates.isNotEmpty())
        return Identity(caller.packageName, origin, certificates)
    }

    fun validateWebOrigin(origin: String) {
        require(origin.length <= 2048 && origin.all { it.code in 33..126 })
        val uri = URI(origin)
        require(uri.rawUserInfo == null && uri.rawQuery == null && uri.rawFragment == null)
        require(uri.rawPath.isNullOrEmpty() && !uri.host.isNullOrEmpty())
        require(uri.scheme == "https" || (uri.scheme == "http" && uri.host == "localhost"))
        require(uri.port == -1 || uri.port in 1..65535)
        // The trusted browser checks RP authorization, including Related Origin Requests.
        // A suffix-only RP/origin comparison here would reject valid browser-authorized ROR.
    }
}
