package com.pureswift.swiftandroid.passkeys

import android.os.SystemClock
import java.security.MessageDigest
import java.util.UUID

/** Private process-local capabilities. Process death, expiry and second use fail closed. */
internal class PasskeyRequestRegistry(private val clock: () -> Long) {
    data class Selection(
        val create: Boolean,
        val caller: TrustedPasskeyCaller.Identity,
        val requestJson: String,
        val hash: ByteArray,
        val credentialId: String?,
        val expires: Long
    ) {
        fun matches(create: Boolean, caller: TrustedPasskeyCaller.Identity, json: String, hash: ByteArray?) =
            this.create == create && this.caller == caller && requestJson == json &&
                hash != null && MessageDigest.isEqual(this.hash, hash)
    }
    private val pending = linkedMapOf<String, Selection>()
    @Synchronized fun add(create: Boolean, caller: TrustedPasskeyCaller.Identity, json: String,
                          hash: ByteArray, credentialId: String?, timeoutMillis: Long = 300_000): String {
        val now = clock()
        pending.entries.removeAll { it.value.expires <= now }
        while (pending.size >= 128) pending.remove(pending.keys.first())
        val token = UUID.randomUUID().toString()
        pending[token] = Selection(create, caller, json, hash.copyOf(), credentialId, now + timeoutMillis.coerceIn(1, 300_000))
        return token
    }
    @Synchronized fun take(token: String?): Selection? {
        val value = pending.remove(token) ?: return null
        return value.takeIf { it.expires > clock() }
    }
    @Synchronized fun peek(token: String?): Selection? = pending[token]?.takeIf { it.expires > clock() }
    @Synchronized fun remove(token: String) { pending.remove(token) }
}

internal object PasskeyPendingRequests {
    private val registry = PasskeyRequestRegistry(SystemClock::elapsedRealtime)
    fun add(create: Boolean, caller: TrustedPasskeyCaller.Identity, json: String,
            hash: ByteArray, credentialId: String?, timeoutMillis: Long = 300_000) =
        registry.add(create, caller, json, hash, credentialId, timeoutMillis)
    fun take(token: String?) = registry.take(token)
    fun peek(token: String?) = registry.peek(token)
    fun remove(token: String) = registry.remove(token)
}
