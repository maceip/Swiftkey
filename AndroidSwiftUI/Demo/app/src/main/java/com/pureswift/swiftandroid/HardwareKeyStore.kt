package com.pureswift.swiftandroid

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.Base64
import android.util.Log
import androidx.annotation.Keep
import androidx.annotation.RequiresApi
import java.math.BigInteger
import java.security.AlgorithmParameters
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.SecureRandom
import java.security.Signature
import java.security.cert.X509Certificate
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.ECParameterSpec
import org.json.JSONArray
import org.json.JSONObject

/** JNI entry point for the device's persistent StrongBox P-256 identity. */
@Keep
object HardwareKeyStore {
    private const val ALIAS = "swiftkey.device-root.v1"
    private const val ATTESTED_ALIAS = "swiftkey.attested-root.v1"
    private const val V2_ATTESTED_ALIAS = "swiftkey.attested-root.v2"
    private const val ATTESTATION_EXTENSION = "1.3.6.1.4.1.11129.2.1.17"
    private const val PROVIDER = "AndroidKeyStore"
    private const val TAG = "SwiftKeyHardware"
    private const val HEX = "0123456789abcdef"

    @Volatile
    private var applicationContext: Context? = null

    @JvmStatic
    fun initialize(context: Context) {
        applicationContext = context.applicationContext
    }

    /** Existing roots keep their original challenge and certificate chain. */
    @JvmStatic
    @Synchronized
    fun enroll(challengeBase64: String): String = enrollAlias(ATTESTED_ALIAS, challengeBase64)

    /** V2 uses a separate retained root; opening the flow never calls this. */
    @JvmStatic
    @Synchronized
    fun enrollV2(challengeBase64: String): String = enrollAlias(V2_ATTESTED_ALIAS, challengeBase64)

    private fun enrollAlias(alias: String, challengeBase64: String): String = protocolResult {
        requireStrongBox()
        val challenge = decodeBase64(challengeBase64, 32)
        if (challenge.size != 32) {
            throw KeyValidationFailure("enrollment challenge must contain exactly 32 bytes")
        }
        val keyStore = KeyStore.getInstance(PROVIDER).apply { load(null) }
        if (!keyStore.containsAlias(alias)) {
            generateKey(alias, challenge)
        }
        val entry = validatedEntry(keyStore, alias)
        val chain = keyStore.getCertificateChain(alias)
            ?: throw KeyValidationFailure("attestation certificate chain is unavailable")
        if (chain.size !in 2..16 || chain.any { it !is X509Certificate } ||
            chain.none { (it as X509Certificate).getExtensionValue(ATTESTATION_EXTENSION) != null }
        ) {
            throw KeyValidationFailure("stored root does not have an attestation certificate chain")
        }
        if (!chain.first().publicKey.encoded.contentEquals(entry.certificate.publicKey.encoded)) {
            throw KeyValidationFailure("attestation certificate does not match the stored root")
        }
        val certificates = JSONArray()
        var totalBytes = 0
        for (certificate in chain) {
            val der = certificate.encoded
            totalBytes += der.size
            if (der.size > 64 * 1024 || totalBytes > 512 * 1024) {
                throw KeyValidationFailure("attestation certificate chain is too large")
            }
            certificates.put(Base64.encodeToString(der, Base64.NO_WRAP))
        }
        val publicBytes = publicBytes(entry.certificate.publicKey as ECPublicKey)
        Log.i(TAG, "securityLevel=STRONGBOX attestationChainPrepared=true signVerify=true")
        // Trust-chain, challenge, app identity, and revocation verification belong
        // on the server. This response only transports the hardware's evidence.
        JSONObject()
            .put("publicKey", Base64.encodeToString(publicBytes, Base64.NO_WRAP))
            .put("certificateChain", certificates)
            .put("platform", "androidStrongBox")
    }

    /** Signs the raw canonical operation once; SHA256withECDSA hashes it internally. */
    @JvmStatic
    @Synchronized
    fun rootSign(messageBase64: String): String = signAlias(ATTESTED_ALIAS, messageBase64)

    @JvmStatic
    @Synchronized
    fun rootSignV2(messageBase64: String): String = signAlias(V2_ATTESTED_ALIAS, messageBase64)

    private fun signAlias(alias: String, messageBase64: String): String = protocolResult {
        requireStrongBox()
        val message = decodeBase64(messageBase64, 1024 * 1024)
        if (message.isEmpty()) throw KeyValidationFailure("operation message is empty")
        val keyStore = KeyStore.getInstance(PROVIDER).apply { load(null) }
        val entry = validatedEntry(keyStore, alias)
        val signature = Signature.getInstance("SHA256withECDSA").run {
            initSign(entry.privateKey)
            update(message)
            sign()
        }
        val verified = Signature.getInstance("SHA256withECDSA").run {
            initVerify(entry.certificate.publicKey)
            update(message)
            verify(signature)
        }
        if (!verified) throw KeyValidationFailure("operation signature verification failed")
        JSONObject().put("signature", Base64.encodeToString(signature, Base64.NO_WRAP))
    }

    /** Presence only; enroll/rootSign still validate the stored key before use. */
    @JvmStatic
    @Synchronized
    fun hasAttestedRoot(): Boolean = try {
        KeyStore.getInstance(PROVIDER).apply { load(null) }.containsAlias(ATTESTED_ALIAS)
    } catch (_: Exception) {
        // A false result never authorizes replacement: enroll rechecks the alias.
        false
    }

    @JvmStatic
    @Synchronized
    fun rootStatusV2(): String = protocolResult {
        JSONObject().put("exists", KeyStore.getInstance(PROVIDER).apply { load(null) }.containsAlias(V2_ATTESTED_ALIAS))
    }

    @JvmStatic
    fun postJSON(url: String, body: String, bootstrapToken: String): String =
        ProtocolIO.postJSON(applicationContext, url, body, bootstrapToken)

    @JvmStatic
    fun readClientConfiguration(): String = ProtocolIO.readConfiguration(applicationContext)

    @JvmStatic
    fun readClientState(): String = ProtocolIO.readState(applicationContext)

    @JvmStatic
    fun writeClientState(json: String): String = ProtocolIO.writeState(applicationContext, json)

    /**
     * Returns 04 || X || Y as 130 lowercase hexadecimal characters after a
     * fresh signing check. Failure returns a readable "StrongBox key unavailable:"
     * message. Call on a worker thread: generation and signing use secure hardware.
     * Once an attested root exists, display that root even without configuration
     * or network access. An invalid attested root never falls back to another key.
     */
    @JvmStatic
    @Synchronized
    fun publicKeyHex(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return failure("Android 12 or later is required to verify StrongBox")
        }
        val context = applicationContext
            ?: return failure("application context is not initialized")
        if (!context.packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE)) {
            return failure("this device does not provide StrongBox")
        }
        return verifiedPublicKeyHex()
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun verifiedPublicKeyHex(): String {
        return try {
            val keyStore = KeyStore.getInstance(PROVIDER).apply { load(null) }
            val alias = if (keyStore.containsAlias(ATTESTED_ALIAS)) {
                ATTESTED_ALIAS
            } else {
                if (!keyStore.containsAlias(ALIAS)) generateKey(ALIAS, null)
                ALIAS
            }
            val entry = validatedEntry(keyStore, alias)
            val bytes = publicBytes(entry.certificate.publicKey as ECPublicKey)
            val hex = buildString(bytes.size * 2) {
                for (byte in bytes) {
                    val value = byte.toInt() and 0xff
                    append(HEX[value ushr 4])
                    append(HEX[value and 0x0f])
                }
            }
            // Only public material and locally observed validation results are logged.
            Log.i(TAG, "securityLevel=STRONGBOX publicKeyHex=$hex signVerify=true")
            hex
        } catch (error: KeyValidationFailure) {
            failure(error.message ?: "stored key validation failed")
        } catch (_: StrongBoxUnavailableException) {
            failure("StrongBox could not generate the P-256 key")
        } catch (error: Exception) {
            Log.w(TAG, "StrongBox operation failed; errorType=${error.javaClass.simpleName}")
            failure("secure hardware key access or signing failed")
        }
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun generateKey(alias: String, challenge: ByteArray?) {
        val spec = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY,
        )
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setIsStrongBoxBacked(true)
            .setAttestationChallenge(challenge)
            .build()
        KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, PROVIDER).apply {
            initialize(spec)
        }.generateKeyPair()
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun validatedEntry(keyStore: KeyStore, alias: String): KeyStore.PrivateKeyEntry {
        // Never replace an unexpected existing entry or downgrade its protection.
        val entry = keyStore.getEntry(alias, null) as? KeyStore.PrivateKeyEntry
            ?: throw KeyValidationFailure("stored root is unavailable or is not a private key")
        val privateKey = entry.privateKey
        val publicKey = entry.certificate.publicKey as? ECPublicKey
            ?: throw KeyValidationFailure("stored public key is not P-256")
        val info = KeyFactory.getInstance(KeyProperties.KEY_ALGORITHM_EC, PROVIDER)
            .getKeySpec(privateKey, KeyInfo::class.java)
        if (info.securityLevel != KeyProperties.SECURITY_LEVEL_STRONGBOX) {
            throw KeyValidationFailure("stored key is not protected by StrongBox")
        }
        if (info.origin != KeyProperties.ORIGIN_GENERATED) {
            throw KeyValidationFailure("stored key was not generated inside the keystore")
        }
        if (privateKey.encoded != null) {
            throw KeyValidationFailure("stored private key is exportable")
        }
        val purposes = KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY
        if (info.keySize != 256 || (info.purposes and purposes) != purposes ||
            KeyProperties.DIGEST_SHA256 !in info.digests
        ) {
            throw KeyValidationFailure("stored key does not support P-256 SHA-256 signing")
        }
        verifyP256Parameters(publicKey.params)
        val challenge = ByteArray(32).also { SecureRandom().nextBytes(it) }
        val signature = Signature.getInstance("SHA256withECDSA").run {
            initSign(privateKey)
            update(challenge)
            sign()
        }
        val valid = Signature.getInstance("SHA256withECDSA").run {
            initVerify(publicKey)
            update(challenge)
            verify(signature)
        }
        if (!valid) throw KeyValidationFailure("fresh signature verification failed")
        return entry
    }

    private fun publicBytes(publicKey: ECPublicKey): ByteArray =
        byteArrayOf(0x04) + coordinate(publicKey.w.affineX) + coordinate(publicKey.w.affineY)

    private fun requireStrongBox() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            throw KeyValidationFailure("Android 12 or later is required to verify StrongBox")
        }
        val context = applicationContext
            ?: throw KeyValidationFailure("application context is not initialized")
        if (!context.packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE)) {
            throw KeyValidationFailure("this device does not provide StrongBox")
        }
    }

    private fun decodeBase64(text: String, maximumBytes: Int): ByteArray {
        if (text.length > ((maximumBytes + 2) / 3) * 4) {
            throw KeyValidationFailure("base64 value exceeds the allowed size")
        }
        val decoded = try {
            Base64.decode(text, Base64.NO_WRAP)
        } catch (_: IllegalArgumentException) {
            throw KeyValidationFailure("base64 value is invalid")
        }
        if (decoded.size > maximumBytes || Base64.encodeToString(decoded, Base64.NO_WRAP) != text) {
            throw KeyValidationFailure("base64 value must use the standard padded encoding")
        }
        return decoded
    }

    private fun protocolResult(operation: () -> JSONObject): String = try {
        operation().toString()
    } catch (error: KeyValidationFailure) {
        JSONObject().put("error", error.message ?: "hardware key validation failed").toString()
    } catch (_: StrongBoxUnavailableException) {
        JSONObject().put("error", "StrongBox could not generate the attested P-256 key").toString()
    } catch (error: Exception) {
        Log.w(TAG, "Hardware protocol operation failed; errorType=${error.javaClass.simpleName}")
        JSONObject().put("error", "hardware key operation failed").toString()
    }

    private fun verifyP256Parameters(actual: ECParameterSpec) {
        val expected = AlgorithmParameters.getInstance("EC").apply {
            init(ECGenParameterSpec("secp256r1"))
        }.getParameterSpec(ECParameterSpec::class.java)
        if (actual.curve != expected.curve || actual.generator != expected.generator ||
            actual.order != expected.order || actual.cofactor != expected.cofactor
        ) {
            throw KeyValidationFailure("stored public key does not use the P-256 curve")
        }
    }

    private fun coordinate(value: BigInteger): ByteArray {
        if (value.signum() < 0 || value.bitLength() > 256) {
            throw KeyValidationFailure("public key coordinate is invalid")
        }
        // BigInteger is signed; discard only its optional leading sign byte and
        // retain leading zero padding so each coordinate is exactly 32 bytes.
        val source = value.toByteArray()
        val count = minOf(source.size, 32)
        return ByteArray(32).also {
            source.copyInto(it, 32 - count, source.size - count, source.size)
        }
    }

    private fun failure(reason: String): String {
        val message = "StrongBox key unavailable: $reason"
        Log.w(TAG, message)
        return message
    }

    private class KeyValidationFailure(message: String) : Exception(message)
}
