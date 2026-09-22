package com.pureswift.swiftandroid.passkeys

/** Public credential metadata. Private key material never leaves AndroidKeyStore. */
data class PasskeyRecord(
    val id: String,
    val rpId: String,
    val userHandle: String,
    val userName: String,
    val displayName: String,
    val keyAlias: String,
    val createdAt: Long,
)

data class PasskeyAvailability(val canCreate: Boolean, val message: String)

class PasskeyStoreException(val code: String, message: String, cause: Throwable? = null) :
    Exception(message, cause)

/** A process-local reservation; it is not selectable until authenticated commit. */
class PendingPasskey internal constructor(
    val record: PasskeyRecord,
    internal val token: String,
    internal val publicKey: java.security.interfaces.ECPublicKey,
) {
    val publicKeyX963: ByteArray get() = passkeyPublicBytes(publicKey)
}

/** Pass this exact Signature to BiometricPrompt.CryptoObject. Do not sign it directly. */
class PasskeySigningOperation internal constructor(
    val record: PasskeyRecord,
    val signature: java.security.Signature,
    internal val token: String,
    internal val pendingToken: String?,
    internal val payload: ByteArray,
    internal val publicKey: java.security.interfaces.ECPublicKey,
    internal val createdAt: Long,
)

/** Constructed only after an auth-gated signature verifies over the original bytes. */
class PasskeySignedResult internal constructor(
    internal val operation: PasskeySigningOperation,
    private val bytes: ByteArray,
) {
    val signatureDer: ByteArray get() = bytes.copyOf()
}
