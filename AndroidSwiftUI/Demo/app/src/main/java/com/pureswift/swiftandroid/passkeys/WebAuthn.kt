package com.pureswift.swiftandroid.passkeys

import java.io.ByteArrayOutputStream
import java.math.BigInteger
import java.net.URI
import java.security.AlgorithmParameters
import java.security.KeyFactory
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.spec.ECGenParameterSpec
import java.security.spec.ECParameterSpec
import java.security.spec.ECPoint
import java.security.spec.ECPublicKeySpec
import java.util.Base64
import java.util.Locale
import org.json.JSONArray
import org.json.JSONObject

class WebAuthnException(val code: String, message: String) : IllegalArgumentException(message)

sealed interface WebAuthnRequest {
    val rpId: String
    val challenge: String
    val timeoutMillis: Long
    val userVerification: String
}

data class WebAuthnCredentialDescriptor internal constructor(val id: String, val transports: List<String>)

data class WebAuthnCreateRequest internal constructor(
    override val rpId: String,
    val rpName: String,
    override val challenge: String,
    val userHandle: String,
    val userName: String,
    val displayName: String,
    val excludeCredentials: List<WebAuthnCredentialDescriptor>,
    override val timeoutMillis: Long,
    override val userVerification: String,
    val authenticatorAttachment: String?,
    val residentKey: String,
    val credentialPropertiesRequested: Boolean,
) : WebAuthnRequest

data class WebAuthnGetRequest internal constructor(
    override val rpId: String,
    override val challenge: String,
    val allowCredentials: List<WebAuthnCredentialDescriptor>,
    override val timeoutMillis: Long,
    override val userVerification: String,
) : WebAuthnRequest

/** Set only after the host's actual consent and device-verification ceremony. */
data class WebAuthnUserAuthorization(val userPresent: Boolean, val userVerified: Boolean)

class WebAuthnClientData internal constructor(
    private val rpId: String,
    private val challenge: String,
    private val type: String,
    val clientDataJSON: String,
    hash: ByteArray,
) {
    private val storedHash = hash.copyOf()
    val clientDataHash: ByteArray get() = storedHash.copyOf()
    internal fun requireBinding(request: WebAuthnRequest) {
        if (rpId != request.rpId || challenge != request.challenge || type != WebAuthn.ceremonyType(request))
            throw WebAuthnException("bindingMismatch", "Client data does not match this request.")
    }
}

/** Captures the exact reviewed credential and bytes before platform authentication. */
class WebAuthnAssertion internal constructor(
    private val credentialId: String,
    private val userHandle: String,
    private val clientDataJSON: String,
    authenticatorData: ByteArray,
    clientDataHash: ByteArray,
) {
    private val storedAuthenticatorData = authenticatorData.copyOf()
    private val storedSigningPayload = authenticatorData + clientDataHash
    val signingPayload: ByteArray get() = storedSigningPayload.copyOf()
    val authenticatorData: ByteArray get() = storedAuthenticatorData.copyOf()

    /** The hardware layer must verify that this signature uses this credential and payload. */
    fun response(signatureDer: ByteArray, authorization: WebAuthnUserAuthorization): String {
        WebAuthn.requireAuthorization(authorization)
        val signature = signatureDer.copyOf()
        WebAuthn.validateSignature(signature)
        return JSONObject().put("id", credentialId).put("rawId", credentialId).put("type", "public-key")
            .put("clientExtensionResults", JSONObject())
            .put("response", JSONObject().put("clientDataJSON", clientDataJSON)
                .put("authenticatorData", WebAuthn.base64Url(storedAuthenticatorData))
                .put("signature", WebAuthn.base64Url(signature)).put("userHandle", userHandle)).toString()
    }
}

/**
 * Transport-independent, device-bound ES256 WebAuthn operations. Caller/RP authorization
 * belongs to the OS provider boundary, not this parser. No network or key generation occurs
 * here. All stored credentials are discoverable, require user verification, and cannot be
 * backed up (BE/BS false). There is no signature counter (signCount is honestly zero).
 *
 * Only credProps is implemented. Unsupported optional extensions produce no output, as
 * WebAuthn specifies; explicit protection enforcement, required large blobs and payment
 * ceremonies fail instead of claiming an unsupported capability.
 */
object WebAuthn {
    private val random = SecureRandom()
    private val p256Prime = BigInteger("ffffffff00000001000000000000000000000000ffffffffffffffffffffffff", 16)
    private val p256B = BigInteger("5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b", 16)
    private val p256Order = BigInteger("ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551", 16)

    fun parseCreate(json: String): WebAuthnCreateRequest {
        val root = WebAuthnJson.objectValue(json)
        val rp = root.objectRequired("rp")
        val rpId = validateRpId(rp.stringRequired("id", 253))
        val user = root.objectRequired("user")
        val challenge = canonicalBase64(root.stringRequired("challenge", 1366), 16, 1024)
        val userHandle = canonicalBase64(user.stringRequired("id", 86), 1, 64)
        val parameters = root.arrayRequired("pubKeyCredParams", 1, 32)
        var es256 = false
        for (index in 0 until parameters.length()) {
            val parameter = parameters.objectAt(index)
            val type = parameter.stringRequired("type", 64)
            val algorithm = parameter.integerRequired("alg")
            if (type == "public-key" && algorithm == -7L) es256 = true
        }
        if (!es256) unsupported("Only ES256 public-key credentials are supported.")
        val selection = root.objectOptional("authenticatorSelection") ?: JSONObject()
        val attachment = selection.enumOptional("authenticatorAttachment", setOf("platform", "cross-platform"))
        val residentKey = selection.enumOptional("residentKey", setOf("required", "preferred", "discouraged"))
            ?: if (selection.booleanOptional("requireResidentKey") == true) "required" else "discouraged"
        // Even when residentKey is explicit, validate the legacy member's JSON type.
        selection.booleanOptional("requireResidentKey")
        val verification = selection.enumOptional("userVerification", verificationValues) ?: "preferred"
        val attestation = root.enumOptional("attestation", setOf("none", "direct", "indirect", "enterprise")) ?: "none"
        if (attestation == "enterprise") unsupported("Enterprise attestation is not supported.")
        root.stringArrayOptional("attestationFormats", 16, 64)
        root.stringArrayOptional("hints", 16, 64)
        val extensions = validateExtensions(root, create = true)
        return WebAuthnCreateRequest(rpId, rp.stringOptional("name", 256) ?: rpId, challenge, userHandle,
            user.stringRequired("name", 256), user.stringRequired("displayName", 256),
            descriptors(root, "excludeCredentials"), timeout(root), verification, attachment, residentKey, extensions)
    }

    fun parseGet(json: String): WebAuthnGetRequest {
        val root = WebAuthnJson.objectValue(json)
        val rpId = validateRpId(root.stringRequired("rpId", 253))
        val challenge = canonicalBase64(root.stringRequired("challenge", 1366), 16, 1024)
        root.stringArrayOptional("hints", 16, 64)
        validateExtensions(root, create = false)
        return WebAuthnGetRequest(rpId, challenge, descriptors(root, "allowCredentials"), timeout(root),
            root.enumOptional("userVerification", verificationValues) ?: "preferred")
    }

    fun newCredentialId(): String = base64Url(ByteArray(32).also(random::nextBytes))

    /** origin is already authorized by CallingAppInfo / the native caller policy. */
    fun clientData(request: WebAuthnRequest, origin: String, suppliedClientDataHash: ByteArray? = null): WebAuthnClientData {
        val type = ceremonyType(request)
        validateOrigin(origin)
        if (suppliedClientDataHash != null) {
            if (suppliedClientDataHash.size != 32) invalid("Client data hash must contain 32 bytes.")
            // Browsers own their clientDataJSON, including crossOrigin/topOrigin. Android
            // requires an empty placeholder rather than fabricated JSON for their hash.
            return WebAuthnClientData(request.rpId, request.challenge, type, "", suppliedClientDataHash)
        }
        if (!origin.startsWith("android:apk-key-hash:"))
            invalid("Browser requests require the OS-supplied client data hash.")
        val bytes = JSONObject().put("type", type).put("challenge", request.challenge)
            .put("origin", origin).put("crossOrigin", false).toString().toByteArray(Charsets.UTF_8)
        return WebAuthnClientData(request.rpId, request.challenge, type, base64Url(bytes), sha256(bytes))
    }

    fun excludedCredentials(request: WebAuthnCreateRequest, records: List<PasskeyRecord>): List<PasskeyRecord> {
        val excluded = request.excludeCredentials.map { it.id }.toSet()
        return records.filter { it.rpId == request.rpId && it.id in excluded }
    }

    fun matchingCredentials(request: WebAuthnGetRequest, records: List<PasskeyRecord>): List<PasskeyRecord> {
        val allowed = request.allowCredentials.map { it.id }.toSet()
        return records.filter { it.rpId == request.rpId && (allowed.isEmpty() || it.id in allowed) }
    }

    fun registrationResponse(request: WebAuthnCreateRequest, record: PasskeyRecord, publicKeyX963: ByteArray,
                             clientData: WebAuthnClientData, authorization: WebAuthnUserAuthorization): String {
        requireAuthorization(authorization); clientData.requireBinding(request); validateRecord(record)
        if (record.rpId != request.rpId || record.userHandle != request.userHandle ||
            record.userName != request.userName || record.displayName != request.displayName)
            binding("Registration metadata does not match the request.")
        if (request.excludeCredentials.any { it.id == record.id })
            throw WebAuthnException("credentialExcluded", "This credential is excluded by the request.")
        val key = publicKeyX963.copyOf()
        val encodedPublicKey = publicKey(key)
        val credentialId = decodeBase64Url(record.id, 32, 32)
        val cose = Cbor.map(listOf(1 to 2, 3 to -7, -1 to 1, -2 to key.copyOfRange(1, 33), -3 to key.copyOfRange(33, 65)))
        val authData = authenticatorData(request.rpId, registration = true) + ByteArray(16) +
            byteArrayOf(0, credentialId.size.toByte()) + credentialId + cose
        val attestation = Cbor.map(listOf("fmt" to "none", "attStmt" to emptyMap<String, Any>(), "authData" to authData))
        val extensionResults = JSONObject()
        if (request.credentialPropertiesRequested) extensionResults.put("credProps", JSONObject().put("rk", true))
        val response = JSONObject().put("clientDataJSON", clientData.clientDataJSON)
            .put("attestationObject", base64Url(attestation)).put("authenticatorData", base64Url(authData))
            .put("publicKeyAlgorithm", -7).put("publicKey", base64Url(encodedPublicKey))
            .put("transports", JSONArray(listOf("internal", "hybrid")))
        return JSONObject().put("id", record.id).put("rawId", record.id).put("type", "public-key")
            .put("response", response).put("clientExtensionResults", extensionResults).toString()
    }

    /** Unsigned draft only: the host must gate signing and response release on actual UV. */
    fun prepareAssertion(request: WebAuthnGetRequest, record: PasskeyRecord, clientData: WebAuthnClientData): WebAuthnAssertion {
        clientData.requireBinding(request); validateRecord(record)
        if (record.rpId != request.rpId) binding("The selected credential belongs to a different relying party.")
        if (request.allowCredentials.isNotEmpty() && request.allowCredentials.none { it.id == record.id })
            throw WebAuthnException("noCredentials", "The selected credential is not allowed by this request.")
        return WebAuthnAssertion(record.id, record.userHandle, clientData.clientDataJSON,
            authenticatorData(request.rpId, registration = false), clientData.clientDataHash)
    }

    fun base64Url(value: ByteArray): String = Base64.getUrlEncoder().withoutPadding().encodeToString(value)
    fun decodeBase64Url(value: String, minimumBytes: Int = 0, maximumBytes: Int = 1024): ByteArray {
        if (minimumBytes < 0 || maximumBytes < minimumBytes || value.length > (maximumBytes * 4L + 2) / 3 ||
            value.any { it !in 'A'..'Z' && it !in 'a'..'z' && it !in '0'..'9' && it != '_' && it != '-' } || value.length % 4 == 1)
            invalid("Invalid canonical base64url value.")
        val bytes = try { Base64.getUrlDecoder().decode(value) } catch (_: IllegalArgumentException) { invalid("Invalid base64url value.") }
        if (bytes.size !in minimumBytes..maximumBytes || base64Url(bytes) != value) invalid("Invalid canonical base64url value.")
        return bytes
    }

    internal fun ceremonyType(request: WebAuthnRequest): String = when (request) {
        is WebAuthnCreateRequest -> "webauthn.create"
        is WebAuthnGetRequest -> "webauthn.get"
    }

    internal fun validateSignature(signature: ByteArray) {
        fun malformed(): Nothing = throw WebAuthnException("invalidSignature", "The credential signature is invalid.")
        if (signature.size !in 8..72 || signature[0] != 0x30.toByte() || signature[1].toInt() != signature.size - 2) malformed()
        var position = 2
        repeat(2) {
            if (position + 2 > signature.size || signature[position++] != 0x02.toByte()) malformed()
            val size = signature[position++].toInt() and 0xff
            if (size !in 1..33 || position + size > signature.size) malformed()
            val integer = signature.copyOfRange(position, position + size); position += size
            if (integer[0].toInt() < 0 || (size > 1 && integer[0] == 0.toByte() && integer[1].toInt() >= 0)) malformed()
            val number = BigInteger(1, integer)
            if (number.signum() == 0 || number >= p256Order) malformed()
        }
        if (position != signature.size) malformed()
    }

    private val verificationValues = setOf("required", "preferred", "discouraged")
    internal fun requireAuthorization(value: WebAuthnUserAuthorization) {
        if (!value.userPresent || !value.userVerified)
            throw WebAuthnException("userVerificationRequired", "Confirm this operation with device authentication.")
    }
    private fun validateRecord(record: PasskeyRecord) {
        canonicalBase64(record.id, 32, 32); canonicalBase64(record.userHandle, 1, 64); validateRpId(record.rpId)
        if (record.keyAlias.isEmpty()) binding("The selected credential has no hardware key.")
    }
    private fun authenticatorData(rpId: String, registration: Boolean): ByteArray =
        sha256(rpId.toByteArray(Charsets.UTF_8)) + byteArrayOf(if (registration) 0x45 else 0x05) + ByteArray(4)
    private fun canonicalBase64(value: String, minimum: Int, maximum: Int): String {
        decodeBase64Url(value, minimum, maximum); return value
    }
    private fun validateRpId(value: String): String {
        val label = Regex("[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?")
        if (value.length !in 1..253 || value != value.lowercase(Locale.ROOT) || value.split('.').any { !label.matches(it) })
            invalid("Invalid relying party identifier.")
        return value
    }
    private fun validateOrigin(origin: String) {
        if (origin.startsWith("android:apk-key-hash:")) {
            canonicalBase64(origin.removePrefix("android:apk-key-hash:"), 32, 32); return
        }
        if (origin.length > 2048 || origin.any { it.code <= 0x20 || it.code >= 0x7f }) invalid("Invalid caller origin.")
        val uri = try { URI(origin) } catch (_: Exception) { invalid("Invalid caller origin.") }
        val secureScheme = uri.scheme == "https" || (uri.scheme == "http" && uri.host == "localhost")
        if (!secureScheme || uri.host.isNullOrEmpty() || uri.rawUserInfo != null || uri.rawQuery != null ||
            uri.rawFragment != null || !uri.rawPath.isNullOrEmpty() || uri.port !in -1..65535 || uri.port == 0)
            invalid("Invalid caller origin.")
    }
    private fun timeout(root: JSONObject): Long {
        if (!root.has("timeout")) return 60_000
        val value = root.integerRequired("timeout")
        if (value !in 0..0xffff_ffffL) invalid("Invalid timeout.")
        return value.coerceIn(1000, 120_000)
    }
    private fun descriptors(root: JSONObject, name: String): List<WebAuthnCredentialDescriptor> {
        if (!root.has(name)) return emptyList()
        val array = root.arrayRequired(name, 0, 128)
        return List(array.length()) { index ->
            val descriptor = array.objectAt(index)
            if (descriptor.stringRequired("type", 64) != "public-key") unsupported("Unsupported credential type.")
            WebAuthnCredentialDescriptor(canonicalBase64(descriptor.stringRequired("id", 1366), 1, 1024),
                descriptor.stringArrayOptional("transports", 16, 64) ?: emptyList())
        }.distinctBy { it.id }
    }

    private fun validateExtensions(root: JSONObject, create: Boolean): Boolean {
        val extensions = root.objectOptional("extensions") ?: return false
        val credProps = extensions.booleanOptional("credProps") ?: false
        for (name in listOf("uvm", "hmacCreateSecret", "getCredBlob", "minPinLength")) extensions.booleanOptional(name)
        extensions.stringOptional("appid", 2048); extensions.stringOptional("appidExclude", 2048)
        extensions.stringOptional("credBlob", 1366)?.let { decodeBase64Url(it, 0, 1024) }
        val policy = extensions.enumOptional("credentialProtectionPolicy", setOf("userVerificationOptional", "userVerificationOptionalWithCredentialIDList", "userVerificationRequired"))
        if (extensions.booleanOptional("enforceCredentialProtectionPolicy") == true) {
            if (policy == null) invalid("Credential protection enforcement requires a policy.")
            unsupported("Enforced credential protection extensions are not supported.")
        }
        extensions.objectOptional("largeBlob")?.let { blob ->
            val support = blob.enumOptional("support", setOf("required", "preferred"))
            blob.booleanOptional("read")
            blob.stringOptional("write", 8192, allowEmpty = true)?.let { decodeBase64Url(it, 0, 6144) }
            if (create && support == "required") unsupported("Required large-blob storage is not supported.")
            if (create && (blob.has("read") || blob.has("write"))) invalid("Large-blob read and write are authentication options.")
            if (!create && support != null) invalid("Large-blob support is a registration option.")
            if (blob.has("read") && blob.has("write")) invalid("A large-blob operation cannot read and write together.")
        }
        extensions.objectOptional("prf")?.let { prf ->
            prf.objectOptional("eval")?.let(::validatePrfInputs)
            prf.objectOptional("evalByCredential")?.let { byCredential ->
                val keys = byCredential.keys()
                var count = 0
                while (keys.hasNext()) {
                    if (++count > 128) invalid("Too many PRF credential entries.")
                    val id = keys.next(); decodeBase64Url(id, 1, 1024)
                    validatePrfInputs(byCredential.objectRequired(id))
                }
            }
        }
        if (extensions.has("payment") || extensions.booleanOptional("thirdPartyPayment") == true)
            unsupported("Payment confirmation is not supported.")
        return create && credProps
    }
    private fun validatePrfInputs(value: JSONObject) {
        decodeBase64Url(value.stringRequired("first", 1366, allowEmpty = true), 0, 1024)
        value.stringOptional("second", 1366, allowEmpty = true)?.let { decodeBase64Url(it, 0, 1024) }
    }

    private fun publicKey(bytes: ByteArray): ByteArray {
        if (bytes.size != 65 || bytes[0] != 4.toByte()) invalid("Expected an uncompressed P-256 public key.")
        val x = BigInteger(1, bytes.copyOfRange(1, 33)); val y = BigInteger(1, bytes.copyOfRange(33, 65))
        if (x >= p256Prime || y >= p256Prime || y.modPow(BigInteger.valueOf(2), p256Prime) !=
            (x.modPow(BigInteger.valueOf(3), p256Prime) - x * BigInteger.valueOf(3) + p256B).mod(p256Prime))
            invalid("The credential public key is not on P-256.")
        return try {
            val parameters = AlgorithmParameters.getInstance("EC").apply { init(ECGenParameterSpec("secp256r1")) }
                .getParameterSpec(ECParameterSpec::class.java)
            KeyFactory.getInstance("EC").generatePublic(ECPublicKeySpec(ECPoint(x, y), parameters)).encoded
        } catch (_: Exception) { invalid("The credential public key could not be encoded.") }
    }

    private fun sha256(bytes: ByteArray): ByteArray = MessageDigest.getInstance("SHA-256").digest(bytes)
    private fun invalid(message: String): Nothing = throw WebAuthnException("invalidRequest", message)
    private fun unsupported(message: String): Nothing = throw WebAuthnException("notSupported", message)
    private fun binding(message: String): Nothing = throw WebAuthnException("bindingMismatch", message)

    private fun JSONObject.objectRequired(name: String): JSONObject = opt(name) as? JSONObject ?: invalid("Expected an object for $name.")
    private fun JSONObject.objectOptional(name: String): JSONObject? = if (has(name)) objectRequired(name) else null
    private fun JSONObject.stringRequired(name: String, maxBytes: Int, allowEmpty: Boolean = false): String {
        val value = opt(name) as? String ?: invalid("Expected text for $name.")
        if ((!allowEmpty && value.isEmpty()) || value.toByteArray(Charsets.UTF_8).size > maxBytes || value.any { it.code < 0x20 || it.code == 0x7f })
            invalid("Invalid text for $name.")
        return value
    }
    private fun JSONObject.stringOptional(name: String, maxBytes: Int, allowEmpty: Boolean = false): String? = if (has(name)) stringRequired(name, maxBytes, allowEmpty) else null
    private fun JSONObject.booleanOptional(name: String): Boolean? = if (has(name)) opt(name) as? Boolean ?: invalid("Expected a Boolean for $name.") else null
    private fun JSONObject.integerRequired(name: String): Long {
        val value = opt(name)
        if (value is Long) return value
        if (value is Int) return value.toLong()
        if (value is Double && value.isFinite() && value >= Long.MIN_VALUE.toDouble() && value < Long.MAX_VALUE.toDouble() && value == value.toLong().toDouble()) return value.toLong()
        invalid("Expected an integer for $name.")
    }
    private fun JSONObject.enumOptional(name: String, values: Set<String>): String? {
        val value = stringOptional(name, 128) ?: return null
        if (value !in values) invalid("Invalid value for $name.")
        return value
    }
    private fun JSONObject.arrayRequired(name: String, minimum: Int, maximum: Int): JSONArray {
        val array = opt(name) as? JSONArray ?: invalid("Expected an array for $name.")
        if (array.length() !in minimum..maximum) invalid("Invalid item count for $name.")
        return array
    }
    private fun JSONObject.stringArrayOptional(name: String, maximum: Int, maxBytes: Int): List<String>? {
        if (!has(name)) return null
        val values = arrayRequired(name, 0, maximum)
        return List(values.length()) { index ->
            (values.opt(index) as? String)?.takeIf { it.isNotEmpty() && it.toByteArray(Charsets.UTF_8).size <= maxBytes && it.none { ch -> ch.code < 0x20 || ch.code == 0x7f } }
                ?: invalid("Invalid text in $name.")
        }
    }
    private fun JSONArray.objectAt(index: Int): JSONObject = opt(index) as? JSONObject ?: invalid("Expected an object in the credential options.")

    /** Deterministic, definite-length CBOR for our fixed WebAuthn output shapes. */
    private object Cbor {
        fun map(entries: List<Pair<Any, Any>>): ByteArray {
            val encoded = entries.map { encode(it.first) to encode(it.second) }.sortedWith { a, b ->
                if (a.first.size != b.first.size) a.first.size.compareTo(b.first.size)
                else a.first.indices.firstOrNull { a.first[it] != b.first[it] }?.let { (a.first[it].toInt() and 255).compareTo(b.first[it].toInt() and 255) } ?: 0
            }
            return ByteArrayOutputStream().apply {
                head(this, 5, encoded.size)
                encoded.forEach { (key, value) -> write(key); write(value) }
            }.toByteArray()
        }
        private fun encode(value: Any): ByteArray = ByteArrayOutputStream().apply {
            when (value) {
                is Int -> head(this, if (value >= 0) 0 else 1, if (value >= 0) value else -1 - value)
                is String -> { val bytes = value.toByteArray(Charsets.UTF_8); head(this, 3, bytes.size); write(bytes) }
                is ByteArray -> { head(this, 2, value.size); write(value) }
                is Map<*, *> -> { check(value.isEmpty()); head(this, 5, 0) }
                else -> error("Unsupported internal CBOR value")
            }
        }.toByteArray()
        private fun head(output: ByteArrayOutputStream, major: Int, size: Int) {
            when {
                size < 24 -> output.write((major shl 5) or size)
                size < 256 -> { output.write((major shl 5) or 24); output.write(size) }
                size < 65_536 -> { output.write((major shl 5) or 25); output.write(size ushr 8); output.write(size) }
                else -> error("Internal CBOR value is too large")
            }
        }
    }
}
