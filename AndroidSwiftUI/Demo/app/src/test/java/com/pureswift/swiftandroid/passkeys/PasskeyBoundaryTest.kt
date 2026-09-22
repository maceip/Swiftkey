package com.pureswift.swiftandroid.passkeys

import org.junit.Assert.*
import org.junit.Test

class PasskeyBoundaryTest {
    private val caller = TrustedPasskeyCaller.Identity("browser", "https://example.com", "certificate")
    @Test fun tokenIsOneUseAndCapturesCallerRequestAndHash() {
        val registry = PasskeyRequestRegistry { 100L }
        val hash = ByteArray(32) { 7 }
        val token = registry.add(false, caller, "request", hash, "credential")
        assertSame(registry.peek(token), registry.peek(token))
        hash[0] = 8
        val selected = registry.take(token)!!
        assertTrue(selected.matches(false, caller, "request", ByteArray(32) { 7 }))
        assertEquals("credential", selected.credentialId)
        assertFalse(selected.matches(true, caller, "request", ByteArray(32) { 7 }))
        assertFalse(selected.matches(false, caller.copy(packageName = "impostor"), "request", ByteArray(32) { 7 }))
        assertFalse(selected.matches(false, caller.copy(signingCertificates = "forged"), "request", ByteArray(32) { 7 }))
        assertFalse(selected.matches(false, caller.copy(origin = "https://evil.example"), "request", ByteArray(32) { 7 }))
        assertFalse(selected.matches(false, caller, "substituted", ByteArray(32) { 7 }))
        assertFalse(selected.matches(false, caller, "request", hash))
        assertFalse(selected.matches(false, caller, "request", null))
        assertNull(registry.take(token))
        assertNull(registry.peek(token))
    }
    @Test fun expiredCancelledAndEvictedSelectionsCannotAuthorize() {
        var now = 100L
        val registry = PasskeyRequestRegistry { now }
        fun add() = registry.add(true, caller, "json", ByteArray(32), null)
        val expired = add(); now += 300_000; assertNull(registry.take(expired))
        val short = registry.add(true, caller, "json", ByteArray(32), null, 60_000)
        now += 60_000
        assertNull(registry.peek(short))
        assertNull(registry.take(short))
        val cancelled = add(); registry.remove(cancelled); assertNull(registry.take(cancelled))
        val evicted = add(); repeat(128) { add() }; assertNull(registry.take(evicted))
        assertNull(PasskeyRequestRegistry { now }.take(add()))
    }
    @Test fun onlySecureWebOriginsAndLocalhostAreAccepted() {
        listOf("https://example.com", "https://accounts.example.com:8443", "http://localhost:18202").forEach {
            TrustedPasskeyCaller.validateWebOrigin(it)
        }
        listOf("http://example.com", "https://example.com/", "https://example.com/path", "https://user@example.com",
            "https://example.com?query", "https://example.com#fragment", "android:apk-key-hash:abc",
            "https://example.com:0", "https://example.com:65536", "https://example.com\n").forEach {
            assertThrows(IllegalArgumentException::class.java) { TrustedPasskeyCaller.validateWebOrigin(it) }
        }
    }
}
