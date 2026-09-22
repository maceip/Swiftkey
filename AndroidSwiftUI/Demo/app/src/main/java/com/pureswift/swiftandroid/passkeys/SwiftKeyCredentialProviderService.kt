package com.pureswift.swiftandroid.passkeys

import android.app.PendingIntent
import android.content.Intent
import android.net.Uri
import android.os.CancellationSignal
import android.os.OutcomeReceiver
import androidx.annotation.RequiresApi
import androidx.credentials.exceptions.*
import androidx.credentials.provider.*
import java.util.concurrent.Executors

/** The query phase only lists capabilities and matching credentials. It never mints or signs. */
@RequiresApi(34)
class SwiftKeyCredentialProviderService : CredentialProviderService() {
    private val worker = Executors.newSingleThreadExecutor()

    override fun onBeginCreateCredentialRequest(request: BeginCreateCredentialRequest,
        cancellationSignal: CancellationSignal,
        callback: OutcomeReceiver<BeginCreateCredentialResponse, CreateCredentialException>) {
        worker.execute {
            try {
                if (cancellationSignal.isCanceled) return@execute
                val publicKey = request as? BeginCreatePublicKeyCredentialRequest
                    ?: throw IllegalArgumentException("Only website passkeys are supported.")
                val caller = TrustedPasskeyCaller.verify(this, request.callingAppInfo, publicKey.clientDataHash)
                val parsed = WebAuthn.parseCreate(publicKey.requestJson)
                val capability = PasskeyStore(this).capability()
                if (!capability.canCreate) throw IllegalArgumentException(capability.message)
                val token = PasskeyPendingRequests.add(true, caller, publicKey.requestJson,
                    publicKey.clientDataHash!!, null, parsed.timeoutMillis)
                cancellationSignal.setOnCancelListener { PasskeyPendingRequests.remove(token) }
                if (!cancellationSignal.isCanceled) callback.onResult(BeginCreateCredentialResponse(
                    listOf(CreateEntry("This phone", pendingIntent(token, true),
                        description = "SwiftKey · device-bound passkey"))))
            } catch (_: Exception) {
                if (!cancellationSignal.isCanceled) callback.onError(CreateCredentialUnsupportedException(
                    "SwiftKey requires Android 14, StrongBox and a trusted browser request."))
            }
        }
    }

    override fun onBeginGetCredentialRequest(request: BeginGetCredentialRequest,
        cancellationSignal: CancellationSignal,
        callback: OutcomeReceiver<BeginGetCredentialResponse, GetCredentialException>) {
        worker.execute {
            val tokens = mutableListOf<String>()
            cancellationSignal.setOnCancelListener { synchronized(tokens) { tokens.forEach(PasskeyPendingRequests::remove) } }
            try {
                val entries = mutableListOf<CredentialEntry>()
                val seen = mutableSetOf<Pair<String, String>>()
                val store = PasskeyStore(this)
                for (option in request.beginGetCredentialOptions.filterIsInstance<BeginGetPublicKeyCredentialOption>().take(16)) {
                    if (cancellationSignal.isCanceled) return@execute
                    // One unsupported option must not hide another valid browser option.
                    try {
                        val caller = TrustedPasskeyCaller.verify(this, request.callingAppInfo, option.clientDataHash)
                        val parsed = WebAuthn.parseGet(option.requestJson)
                        for (record in WebAuthn.matchingCredentials(parsed, store.list(parsed.rpId))) {
                            // Keep one response below both Binder and pending-selection capacity.
                            if (entries.size >= 64) break
                            if (!seen.add(option.id to record.id)) continue
                            val token = PasskeyPendingRequests.add(false, caller, option.requestJson,
                                option.clientDataHash!!, record.id, parsed.timeoutMillis)
                            synchronized(tokens) { tokens.add(token) }
                            if (cancellationSignal.isCanceled) { PasskeyPendingRequests.remove(token); return@execute }
                            entries.add(PublicKeyCredentialEntry(this, record.userName,
                                pendingIntent(token, false), option, displayName = record.displayName,
                                isAutoSelectAllowed = false))
                        }
                    } catch (_: IllegalArgumentException) { /* No entry for an untrusted/unsupported caller. */ }
                }
                if (!cancellationSignal.isCanceled) callback.onResult(BeginGetCredentialResponse(entries))
            } catch (_: Exception) {
                synchronized(tokens) { tokens.forEach(PasskeyPendingRequests::remove) }
                if (!cancellationSignal.isCanceled) callback.onError(GetCredentialUnknownException(
                    "SwiftKey could not read this phone's passkeys."))
            }
        }
    }

    private fun pendingIntent(token: String, create: Boolean): PendingIntent {
        val intent = Intent(this, PasskeyActivity::class.java)
            .setAction(if (create) PasskeyActivity.CREATE else PasskeyActivity.GET)
            .setData(Uri.parse("swiftkey-passkey://selection/$token"))
        // Explicit private component + unique data prevent entry collisions. Android must add its request.
        return PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_MUTABLE)
    }

    override fun onClearCredentialStateRequest(request: ProviderClearCredentialStateRequest,
        cancellationSignal: CancellationSignal,
        callback: OutcomeReceiver<Void?, ClearCredentialException>) {
        // No signed-in provider session is cached. Website sign-out must never delete passkeys.
        if (!cancellationSignal.isCanceled) callback.onResult(null)
    }

    override fun onDestroy() { worker.shutdown(); super.onDestroy() }
}
