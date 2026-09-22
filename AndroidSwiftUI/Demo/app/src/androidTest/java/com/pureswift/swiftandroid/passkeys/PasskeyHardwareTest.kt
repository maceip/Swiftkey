package com.pureswift.swiftandroid.passkeys

import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.security.SecureRandom
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Conditional real hardware check. This does not pretend to complete a biometric prompt. */
@RunWith(AndroidJUnit4::class)
class PasskeyHardwareTest {
    @Test fun strongBoxPendingKeyRequiresPerOperationAuthenticationAndCancelsCleanly() {
        assumeTrue("Website passkeys require Android 14+", Build.VERSION.SDK_INT >= 34)
        val store = PasskeyStore(InstrumentationRegistry.getInstrumentation().targetContext)
        val capability = store.capability()
        assumeTrue(capability.message, capability.canCreate)
        val id = encode(ByteArray(32).also { SecureRandom().nextBytes(it) })
        val value = try {
            store.prepareRegistration(id, "instrumentation.invalid", encode(byteArrayOf(1)), "test-only", "Temporary hardware check")
        } catch (error: PasskeyStoreException) {
            assumeTrue("StrongBox creation unavailable: ${error.code}", error.code != "hardwareUnavailable")
            throw error
        }
        try {
            assertNull(store.find(id))
            assertEquals(65, value.publicKeyX963.size)
            // No BiometricPrompt approval was provided. The StrongBox operation
            // must reject signing, even if the screen was recently unlocked.
            try {
                val operation = store.beginRegistrationSignature(value, "unauthenticated-hardware-test".toByteArray())
                store.finishSignature(operation, operation.signature)
                fail("Unauthenticated StrongBox signing unexpectedly succeeded")
            } catch (error: PasskeyStoreException) {
                assertTrue(error.code == "authenticationFailed" || error.code == "keyUnavailable")
            }
        } finally { store.abortRegistration(value) }
        assertNull(store.find(id))
    }
}
