package com.pureswift.swiftandroid.passkeys

import java.math.BigInteger
import java.io.File
import java.security.AlgorithmParameters
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.ECParameterSpec
import java.security.spec.ECPoint
import java.security.spec.ECPublicKeySpec
import java.security.spec.X509EncodedKeySpec
import java.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

/** Software keys occur only in this independent verifier, never in the provider engine. */
class WebAuthnTests {
    private val authorization = WebAuthnUserAuthorization(userPresent = true, userVerified = true)
    private val challenge = encode(ByteArray(32) { (it + 1).toByte() })
    private val userHandle = encode(byteArrayOf(1, 2, 3, 4))
    private val credentialId = encode(ByteArray(32) { (it + 63).toByte() })
    private val browserHash = ByteArray(32) { (it * 3).toByte() }

    @Test fun registrationHasIndependentlyDecodableAttestationAndCosePublicKey() {
        val request = WebAuthn.parseCreate(createJson().put("extensions", JSONObject().put("credProps", true)).toString())
        val key = keyPair()
        val record = record(request)
        val response = JSONObject(WebAuthn.registrationResponse(request, record, x963(key), clientData(request), authorization))
        assertEquals("public-key", response.getString("type"))
        assertEquals(credentialId, response.getString("id"))
        assertEquals(credentialId, response.getString("rawId"))
        assertFalse(response.has("authenticatorAttachment"))
        assertTrue(response.getJSONObject("clientExtensionResults").getJSONObject("credProps").getBoolean("rk"))
        val data = response.getJSONObject("response")
        assertEquals("", data.getString("clientDataJSON"))
        assertEquals(listOf("internal", "hybrid"), data.getJSONArray("transports").strings())
        assertEquals(-7, data.getInt("publicKeyAlgorithm"))
        val attestation = Decoder(decode(data.getString("attestationObject"))).complete() as Map<*, *>
        assertEquals(setOf("fmt", "attStmt", "authData"), attestation.keys)
        assertEquals("none", attestation["fmt"])
        assertEquals(emptyMap<Any, Any>(), attestation["attStmt"])
        val authData = attestation["authData"] as ByteArray
        assertArrayEquals(decode(data.getString("authenticatorData")), authData)
        assertArrayEquals(sha256("example.com".toByteArray()), authData.copyOfRange(0, 32))
        assertEquals(0x45, authData[32].toInt()) // UP+UV+AT; BE, BS and ED are absent.
        assertArrayEquals(ByteArray(4), authData.copyOfRange(33, 37))
        assertArrayEquals(ByteArray(16), authData.copyOfRange(37, 53)) // Anonymous none attestation.
        assertEquals(32, ((authData[53].toInt() and 255) shl 8) or (authData[54].toInt() and 255))
        assertArrayEquals(decode(credentialId), authData.copyOfRange(55, 87))
        val cose = Decoder(authData.copyOfRange(87, authData.size)).complete() as Map<*, *>
        assertEquals(setOf(1L, 3L, -1L, -2L, -3L), cose.keys)
        assertEquals(2L, cose[1L]); assertEquals(-7L, cose[3L]); assertEquals(1L, cose[-1L])
        val x = cose[-2L] as ByteArray; val y = cose[-3L] as ByteArray
        assertEquals(32, x.size); assertEquals(32, y.size)
        val parameters = AlgorithmParameters.getInstance("EC").apply { init(ECGenParameterSpec("secp256r1")) }
            .getParameterSpec(ECParameterSpec::class.java)
        val reconstructed = KeyFactory.getInstance("EC").generatePublic(ECPublicKeySpec(ECPoint(BigInteger(1, x), BigInteger(1, y)), parameters))
        val spki = KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(decode(data.getString("publicKey"))))
        assertArrayEquals(key.public.encoded, reconstructed.encoded)
        assertArrayEquals(key.public.encoded, spki.encoded)
    }

    @Test fun assertionSignatureVerifiesWithRegisteredPublicKeyAndExactBrowserHash() {
        val request = WebAuthn.parseGet(getJson().toString())
        val record = record()
        val key = keyPair()
        val assertion = WebAuthn.prepareAssertion(request, record, clientData(request))
        val expectedAuthData = sha256("example.com".toByteArray()) + byteArrayOf(5) + ByteArray(4)
        assertArrayEquals(expectedAuthData + browserHash, assertion.signingPayload)
        val signed = sign(key, assertion.signingPayload)
        val response = JSONObject(assertion.response(signed, authorization))
        val data = response.getJSONObject("response")
        assertEquals(credentialId, response.getString("rawId"))
        assertEquals(userHandle, data.getString("userHandle"))
        assertEquals("", data.getString("clientDataJSON"))
        assertEquals(0, response.getJSONObject("clientExtensionResults").length())
        assertArrayEquals(expectedAuthData, decode(data.getString("authenticatorData")))
        val verifier = Signature.getInstance("SHA256withECDSA")
        verifier.initVerify(key.public)
        verifier.update(decode(data.getString("authenticatorData")) + browserHash)
        assertTrue(verifier.verify(decode(data.getString("signature"))))
        verifier.initVerify(key.public); verifier.update(expectedAuthData + sha256(browserHash))
        assertFalse("The browser hash must not be hashed a second time before concatenation", verifier.verify(signed))
    }

    @Test fun unsignedDraftDoesNotReleaseResponseWithoutRealPresenceAndVerification() {
        val create = WebAuthn.parseCreate(createJson().toString())
        val get = WebAuthn.parseGet(getJson().toString())
        val key = keyPair()
        val draft = WebAuthn.prepareAssertion(get, record(), clientData(get))
        val signature = sign(key, draft.signingPayload)
        for (denied in listOf(WebAuthnUserAuthorization(false, false), WebAuthnUserAuthorization(false, true), WebAuthnUserAuthorization(true, false))) {
            rejected("userVerificationRequired") { draft.response(signature, denied) }
            rejected("userVerificationRequired") { WebAuthn.registrationResponse(create, record(), x963(key), clientData(create), denied) }
        }
    }

    @Test fun nativeClientDataContainsExactAndroidOriginChallengeAndType() {
        val request = WebAuthn.parseGet(getJson().toString())
        val origin = "android:apk-key-hash:" + encode(ByteArray(32) { 9 })
        val client = WebAuthn.clientData(request, origin)
        val raw = decode(client.clientDataJSON)
        val data = JSONObject(String(raw, Charsets.UTF_8))
        assertEquals("webauthn.get", data.getString("type"))
        assertEquals(challenge, data.getString("challenge"))
        assertEquals(origin, data.getString("origin"))
        assertFalse(data.getBoolean("crossOrigin"))
        assertArrayEquals(sha256(raw), client.clientDataHash)
    }

    @Test fun browserClientDataIsOwnedByVerifiedOsAndSupportsRelatedOriginRequests() {
        val request = WebAuthn.parseGet(getJson().toString())
        // OS/browser authorizes Related Origin Requests. Engine must not impose a suffix check.
        val data = WebAuthn.clientData(request, "https://related.example.net", browserHash)
        assertEquals("", data.clientDataJSON)
        assertArrayEquals(browserHash, data.clientDataHash)
        rejected("invalidRequest") { WebAuthn.clientData(request, "https://example.com") }
        rejected("invalidRequest") { WebAuthn.clientData(request, "https://example.com", ByteArray(31)) }
        for (origin in listOf("https://example.com/path", "https://u@example.com", "https://example.com#x", "https://example.com?x", "file://example.com", "http://example.com", "https://example.com:0", "android:apk-key-hash:AA"))
            rejected("invalidRequest") { WebAuthn.clientData(request, origin, browserHash) }
    }

    @Test fun clientDataCannotBeReusedForAnotherRequestOrCeremony() {
        val create = WebAuthn.parseCreate(createJson().toString())
        val get = WebAuthn.parseGet(getJson().toString())
        val changedChallenge = WebAuthn.parseGet(getJson().put("challenge", encode(ByteArray(32) { 8 })).toString())
        val changedRp = WebAuthn.parseGet(getJson().put("rpId", "other.example").toString())
        rejected("bindingMismatch") { WebAuthn.prepareAssertion(get, record(), clientData(create)) }
        rejected("bindingMismatch") { WebAuthn.prepareAssertion(changedChallenge, record(), clientData(get)) }
        rejected("bindingMismatch") { WebAuthn.prepareAssertion(changedRp, record().copy(rpId = "other.example"), clientData(get)) }
    }

    @Test fun onlyExplicitLocalhostHttpMatchesTheTrustedBrowserDevelopmentPolicy() {
        val request = WebAuthn.parseGet(getJson().put("rpId", "localhost").toString())
        val local = WebAuthn.clientData(request, "http://localhost:8080", browserHash)
        assertEquals("", local.clientDataJSON)
        assertArrayEquals(browserHash, local.clientDataHash)
        for (origin in listOf("http://localhost.evil.test", "http://127.0.0.1:8080", "http://localhost:8080/path", "http://localhost@evil.test", "http://example.com"))
            rejected("invalidRequest") { WebAuthn.clientData(request, origin, browserHash) }
        rejected("invalidRequest") { WebAuthn.clientData(request, "http://localhost:8080") }
    }

    @Test fun capturedHashAndUnsignedPayloadCannotBeMutatedByCaller() {
        val request = WebAuthn.parseGet(getJson().toString())
        val supplied = browserHash.copyOf()
        val client = WebAuthn.clientData(request, "https://example.com", supplied)
        supplied.fill(0); client.clientDataHash.fill(0)
        val draft = WebAuthn.prepareAssertion(request, record(), client)
        val original = draft.signingPayload
        draft.signingPayload.fill(0); draft.authenticatorData.fill(0)
        assertArrayEquals(browserHash, client.clientDataHash)
        assertArrayEquals(original, draft.signingPayload)
        assertArrayEquals(original.copyOfRange(0, 37), draft.authenticatorData)
    }

    @Test fun exclusionAndAllowListsAreScopedToExactRelyingParty() {
        val otherId = encode(ByteArray(32) { 99 })
        val existing = record()
        val otherRpSameId = existing.copy(rpId = "other.example")
        val otherCredential = existing.copy(id = otherId, keyAlias = "second-key")
        val all = listOf(existing, otherRpSameId, otherCredential)
        val create = WebAuthn.parseCreate(createJson().put("excludeCredentials", JSONArray().put(descriptor(credentialId))).toString())
        assertEquals(listOf(existing), WebAuthn.excludedCredentials(create, all))
        val get = WebAuthn.parseGet(getJson().put("allowCredentials", JSONArray().put(descriptor(otherId))).toString())
        assertEquals(listOf(otherCredential), WebAuthn.matchingCredentials(get, all))
        rejected("noCredentials") { WebAuthn.prepareAssertion(get, existing, clientData(get)) }
        rejected("bindingMismatch") { WebAuthn.prepareAssertion(get, otherRpSameId, clientData(get)) }
        val discoverable = WebAuthn.parseGet(getJson().toString())
        assertEquals(listOf(existing, otherCredential), WebAuthn.matchingCredentials(discoverable, all))
        rejected("credentialExcluded") { WebAuthn.registrationResponse(create, existing, x963(keyPair()), clientData(create), authorization) }
    }

    @Test fun registrationIsBoundToAllReviewedMetadata() {
        val request = WebAuthn.parseCreate(createJson().toString())
        val key = x963(keyPair())
        for (bad in listOf(record().copy(rpId = "other.example"), record().copy(userHandle = "BQ"), record().copy(userName = "else"), record().copy(displayName = "Someone else"), record().copy(keyAlias = "")))
            rejected("bindingMismatch") { WebAuthn.registrationResponse(request, bad, key, clientData(request), authorization) }
    }

    @Test fun credentialIdsAreCanonicalRandom32BytesAndNeverEpochDerived() {
        val ids = (1..64).map { WebAuthn.newCredentialId() }
        assertEquals(64, ids.toSet().size)
        ids.forEach { assertEquals(32, decode(it).size); assertEquals(43, it.length); assertEquals(it, encode(decode(it))) }
        val request = WebAuthn.parseGet(getJson().toString())
        val old = record().copy(createdAt = 1)
        val same = old.copy(createdAt = 1L + 14_400_000 * 20)
        assertArrayEquals(WebAuthn.prepareAssertion(request, old, clientData(request)).signingPayload,
            WebAuthn.prepareAssertion(request, same, clientData(request)).signingPayload)
    }

    @Test fun canonicalBase64RejectsPaddingAlphabetWhitespaceAndNonzeroTailBits() {
        assertArrayEquals(byteArrayOf(0), WebAuthn.decodeBase64Url("AA", 1, 1))
        for (value in listOf("AA=", "AA==", "AB", "A", "A+", "A/", "AA\n", " AA", "ÄA"))
            rejected("invalidRequest") { WebAuthn.decodeBase64Url(value) }
        rejected("invalidRequest") { WebAuthn.decodeBase64Url("", 1, 64) }
        rejected("invalidRequest") { WebAuthn.decodeBase64Url(encode(ByteArray(65)), 1, 64) }
    }

    @Test fun challengeAndUserHandleBoundsAreValidatedBeforeAnyKeyCreation() {
        for (size in listOf(0, 15, 1025)) rejected("invalidRequest") { WebAuthn.parseGet(getJson().put("challenge", encode(ByteArray(size))).toString()) }
        for (size in listOf(16, 1024)) assertEquals(size, decode(WebAuthn.parseGet(getJson().put("challenge", encode(ByteArray(size))).toString()).challenge).size)
        for (size in listOf(0, 65)) {
            val json = createJson(); json.getJSONObject("user").put("id", encode(ByteArray(size)))
            rejected("invalidRequest") { WebAuthn.parseCreate(json.toString()) }
        }
        for (size in listOf(1, 64)) {
            val json = createJson(); json.getJSONObject("user").put("id", encode(ByteArray(size)))
            assertEquals(size, decode(WebAuthn.parseCreate(json.toString()).userHandle).size)
        }
    }

    @Test fun strictJsonRejectsLenientAndroidSyntaxDuplicateKeysAndBadUnicode() {
        val valid = getJson().toString()
        val variants = listOf("$valid true", "/*x*/$valid", valid.dropLast(1) + ",}", "{'rpId':'example.com'}", "{rpId:1}",
            "{\"x\":01}", "{\"x\":NaN}", "{\"x\":+1}", "{\"x\":1.}", "{\"x\":1e}", "{\"x\":1e999}",
            "{\"x\":1,\"x\":2}", "{\"rpId\":1,\"rp\\u0049d\":2}", "{\"x\":\"\\uD800\"}", "{\"x\":\"\\uDC00\"}",
            "{\"x\":\"\\q\"}", "{\"x\":\"\u0001\"}", "[]", "null", "")
        for (json in variants) rejected("invalidRequest") { WebAuthn.parseGet(json) }
        val unicode = createJson(); unicode.getJSONObject("user").put("displayName", "Zöe 😀")
        assertEquals("Zöe 😀", WebAuthn.parseCreate(unicode.toString()).displayName)
    }

    @Test fun boundedJsonRejectsOversizedDepthStringsArraysAndInput() {
        val deep = "{\"unknown\":" + "[".repeat(18) + "0" + "]".repeat(18) + "}"
        val arrays = "{\"unknown\":[" + List(129) { "0" }.joinToString(",") + "]}"
        val text = "{\"unknown\":\"" + "x".repeat(8193) + "\"}"
        val oversize = " ".repeat(65_537) + "{}"
        for (json in listOf(deep, arrays, text, oversize)) rejected("invalidRequest") { WebAuthn.parseGet(json) }
    }

    @Test fun invalidFieldTypesAndRpIdentifiersFailClosed() {
        for (rpId in listOf("Example.com", "example.com.", "https://example.com", ".example.com", "a..b", "-example.com", "example_.com", "éxample.com", "a".repeat(64) + ".com"))
            rejected("invalidRequest") { WebAuthn.parseGet(getJson().put("rpId", rpId).toString()) }
        for (value in listOf(JSONObject.NULL, 1, true, JSONArray())) rejected("invalidRequest") { WebAuthn.parseGet(getJson().put("rpId", value).toString()) }
        for (value in listOf(-1, 0x1_0000_0000L, 1.5, "1000", JSONObject.NULL)) rejected("invalidRequest") { WebAuthn.parseGet(getJson().put("timeout", value).toString()) }
        assertEquals(1000, WebAuthn.parseGet(getJson().put("timeout", 0).toString()).timeoutMillis)
        assertEquals(120_000, WebAuthn.parseGet(getJson().put("timeout", 0xffff_ffffL).toString()).timeoutMillis)
        assertEquals("localhost", WebAuthn.parseGet(getJson().put("rpId", "localhost").toString()).rpId)
    }

    @Test fun es256MustBeOfferedButOtherAlgorithmAlternativesDoNotPreventNegotiation() {
        val json = createJson().put("pubKeyCredParams", JSONArray().put(JSONObject().put("type", "public-key").put("alg", -257)))
        rejected("notSupported") { WebAuthn.parseCreate(json.toString()) }
        json.getJSONArray("pubKeyCredParams").put(JSONObject().put("type", "public-key").put("alg", -7))
        assertEquals("example.com", WebAuthn.parseCreate(json.toString()).rpId)
        json.put("pubKeyCredParams", JSONArray().put(JSONObject().put("type", "public-key").put("alg", "-7")))
        rejected("invalidRequest") { WebAuthn.parseCreate(json.toString()) }
    }

    @Test fun directAndIndirectAttestationReturnNoneAndEnterpriseFails() {
        val key = x963(keyPair())
        for (preference in listOf("none", "direct", "indirect")) {
            val request = WebAuthn.parseCreate(createJson().put("attestation", preference).toString())
            val response = JSONObject(WebAuthn.registrationResponse(request, record(), key, clientData(request), authorization))
            val attestation = Decoder(decode(response.getJSONObject("response").getString("attestationObject"))).complete() as Map<*, *>
            assertEquals("none", attestation["fmt"])
        }
        rejected("notSupported") { WebAuthn.parseCreate(createJson().put("attestation", "enterprise").toString()) }
    }

    @Test fun osHybridAttachmentIsNotRejectedAndDiscoverableRequirementIsSupported() {
        for (attachment in listOf("platform", "cross-platform")) {
            val json = createJson().put("authenticatorSelection", JSONObject().put("authenticatorAttachment", attachment)
                .put("residentKey", "required").put("userVerification", "required").put("requireResidentKey", true))
            val request = WebAuthn.parseCreate(json.toString())
            assertEquals(attachment, request.authenticatorAttachment)
            assertEquals("required", request.residentKey)
            assertEquals("required", request.userVerification)
        }
        val invalid = createJson().put("authenticatorSelection", JSONObject().put("residentKey", "required").put("requireResidentKey", "true"))
        rejected("invalidRequest") { WebAuthn.parseCreate(invalid.toString()) }
    }

    @Test fun optionalExtensionsAreIgnoredWithoutClaimingTheirCapabilities() {
        val extensions = JSONObject().put("credProps", true).put("unknownFuture", JSONObject().put("key", "value"))
            .put("prf", JSONObject().put("eval", JSONObject().put("first", encode(byteArrayOf(4)))))
            .put("credentialProtectionPolicy", "userVerificationRequired").put("enforceCredentialProtectionPolicy", false)
            .put("largeBlob", JSONObject().put("support", "preferred")).put("uvm", true)
        val request = WebAuthn.parseCreate(createJson().put("extensions", extensions).toString())
        val response = JSONObject(WebAuthn.registrationResponse(request, record(), x963(keyPair()), clientData(request), authorization))
        val result = response.getJSONObject("clientExtensionResults")
        assertEquals(setOf("credProps"), result.keys().asSequence().toSet())
        assertTrue(result.getJSONObject("credProps").getBoolean("rk"))
        val get = WebAuthn.parseGet(getJson().put("extensions", JSONObject().put("prf", JSONObject())).toString())
        val draft = WebAuthn.prepareAssertion(get, record(), clientData(get))
        assertEquals(0, JSONObject(draft.response(sign(keyPair(), draft.signingPayload), authorization)).getJSONObject("clientExtensionResults").length())
    }

    @Test fun mandatoryUnsupportedExtensionsAndMalformedKnownInputsFailHonestly() {
        for (extension in listOf(JSONObject().put("largeBlob", JSONObject().put("support", "required")),
            JSONObject().put("credentialProtectionPolicy", "userVerificationRequired").put("enforceCredentialProtectionPolicy", true),
            JSONObject().put("payment", JSONObject()), JSONObject().put("thirdPartyPayment", true)))
            rejected("notSupported") { WebAuthn.parseCreate(createJson().put("extensions", extension).toString()) }
        for (extension in listOf(JSONObject().put("credProps", "true"), JSONObject().put("enforceCredentialProtectionPolicy", true),
            JSONObject().put("largeBlob", JSONObject().put("read", true)), JSONObject().put("prf", JSONObject().put("eval", JSONObject()))))
            rejected("invalidRequest") { WebAuthn.parseCreate(createJson().put("extensions", extension).toString()) }
        rejected("invalidRequest") { WebAuthn.parseGet(getJson().put("extensions", JSONObject().put("largeBlob", JSONObject().put("support", "required"))).toString()) }
    }

    @Test fun malformedPublicKeysCannotBePublishedAsP256() {
        val request = WebAuthn.parseCreate(createJson().toString())
        val correct = x963(keyPair())
        val invalid = listOf(ByteArray(65), byteArrayOf(4) + ByteArray(64), correct.copyOf(64), correct.copyOf().also { it[0] = 2 }, byteArrayOf(4) + ByteArray(64) { 0xff.toByte() })
        for (key in invalid) rejected("invalidRequest") { WebAuthn.registrationResponse(request, record(), key, clientData(request), authorization) }
    }

    @Test fun malformedDerSignatureCannotEscapeIntoAResponse() {
        val request = WebAuthn.parseGet(getJson().toString())
        val draft = WebAuthn.prepareAssertion(request, record(), clientData(request))
        val invalid = listOf(ByteArray(64), byteArrayOf(0x30, 6, 2, 1, 0, 2, 1, 1), // zero r
            byteArrayOf(0x30, 6, 2, 1, -1, 2, 1, 1), // negative r
            byteArrayOf(0x30, 7, 2, 2, 0, 1, 2, 1, 1), // redundant padding
            byteArrayOf(0x30, 7, 2, 1, 1, 2, 1, 1, 0), // trailing byte
            byteArrayOf(0x30, -127, 6, 2, 1, 1, 2, 1, 1)) // non-short length
        for (signature in invalid) rejected("invalidSignature") { draft.response(signature, authorization) }
    }

    @Test fun publicInteropFixtureUsesEngineOutputsAndNeverExportsPrivateKeys() {
        val create = WebAuthn.parseCreate(createJson().toString())
        val get = WebAuthn.parseGet(getJson().put("challenge", encode(ByteArray(32) { (it + 100).toByte() })).toString())
        fun browserData(request: WebAuthnRequest, type: String): ByteArray = JSONObject().put("type", type)
            .put("challenge", request.challenge).put("origin", "https://example.com").put("crossOrigin", false)
            .toString().toByteArray(Charsets.UTF_8)
        val registrationData = browserData(create, "webauthn.create")
        val authenticationData = browserData(get, "webauthn.get")
        val key = keyPair()
        val registration = JSONObject(WebAuthn.registrationResponse(create, record(), x963(key),
            WebAuthn.clientData(create, "https://example.com", sha256(registrationData)), authorization))
        val draft = WebAuthn.prepareAssertion(get, record(), WebAuthn.clientData(get, "https://example.com", sha256(authenticationData)))
        val assertion = JSONObject(draft.response(sign(key, draft.signingPayload), authorization))
        assertEquals("", registration.getJSONObject("response").getString("clientDataJSON"))
        assertEquals("", assertion.getJSONObject("response").getString("clientDataJSON"))
        // Android sends an empty placeholder to the privileged browser; the browser
        // inserts its original bytes before submitting these objects to the RP.
        registration.getJSONObject("response").put("clientDataJSON", encode(registrationData))
        assertion.getJSONObject("response").put("clientDataJSON", encode(authenticationData))
        val fixture = JSONObject().put("source", "SwiftKey WebAuthn engine; ephemeral test-only software signer")
            .put("rpId", "example.com").put("origin", "https://example.com").put("userHandle", userHandle)
            .put("registrationChallenge", create.challenge).put("assertionChallenge", get.challenge)
            .put("registration", registration).put("assertion", assertion)
        assertFalse(fixture.toString().contains("PRIVATE KEY"))
        System.getenv("SWIFTKEY_WEBAUTHN_FIXTURE")?.let { destination ->
            require(destination.startsWith("/tmp/")) { "Interop fixture output must be an explicit temporary path." }
            File(destination).writeText(fixture.toString(2) + "\n", Charsets.UTF_8)
        }
    }

    private fun createJson() = JSONObject().put("rp", JSONObject().put("id", "example.com").put("name", "Example"))
        .put("user", JSONObject().put("id", userHandle).put("name", "alice@example.com").put("displayName", "Alice"))
        .put("challenge", challenge).put("pubKeyCredParams", JSONArray().put(JSONObject().put("type", "public-key").put("alg", -7)))
    private fun getJson() = JSONObject().put("rpId", "example.com").put("challenge", challenge)
    private fun descriptor(id: String) = JSONObject().put("type", "public-key").put("id", id)
    private fun record(request: WebAuthnCreateRequest = WebAuthn.parseCreate(createJson().toString())) =
        PasskeyRecord(credentialId, request.rpId, request.userHandle, request.userName, request.displayName, "test-only-key-alias", 1000)
    private fun clientData(request: WebAuthnRequest) = WebAuthn.clientData(request, "https://example.com", browserHash)
    private fun keyPair(): KeyPair = KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()
    private fun x963(key: KeyPair): ByteArray {
        val public = key.public as ECPublicKey
        fun coordinate(value: BigInteger): ByteArray = value.toByteArray().let { ByteArray(32 - it.takeLast(32).size) + it.takeLast(32).toByteArray() }
        return byteArrayOf(4) + coordinate(public.w.affineX) + coordinate(public.w.affineY)
    }
    private fun sign(key: KeyPair, payload: ByteArray): ByteArray = Signature.getInstance("SHA256withECDSA").run { initSign(key.private); update(payload); sign() }
    private fun sha256(value: ByteArray) = MessageDigest.getInstance("SHA-256").digest(value)
    private fun encode(value: ByteArray) = Base64.getUrlEncoder().withoutPadding().encodeToString(value)
    private fun decode(value: String) = Base64.getUrlDecoder().decode(value)
    private fun JSONArray.strings() = (0 until length()).map { getString(it) }
    private fun rejected(code: String, body: () -> Unit) {
        try { body(); fail("Expected WebAuthnException($code)") }
        catch (error: WebAuthnException) { assertEquals(code, error.code) }
    }

    /** Independent small CBOR decoder: verifies production bytes, never calls its encoder. */
    private class Decoder(private val bytes: ByteArray) {
        private var offset = 0
        fun complete(): Any { val result = value(); assertEquals("No trailing CBOR bytes", bytes.size, offset); return result }
        private fun value(): Any {
            val head = read(); val major = head ushr 5
            val size = when (val additional = head and 31) {
                in 0..23 -> additional
                24 -> read()
                25 -> (read() shl 8) or read()
                else -> throw AssertionError("Unexpected CBOR length")
            }
            return when (major) {
                0 -> size.toLong()
                1 -> -1L - size
                2 -> bytes.copyOfRange(offset, offset + size).also { offset += size }
                3 -> String(bytes.copyOfRange(offset, offset + size), Charsets.UTF_8).also { offset += size }
                5 -> linkedMapOf<Any, Any>().apply { repeat(size) { val key = value(); assertFalse(containsKey(key)); put(key, value()) } }
                else -> throw AssertionError("Unexpected CBOR major type")
            }
        }
        private fun read(): Int { assertTrue("Truncated CBOR", offset < bytes.size); return bytes[offset++].toInt() and 255 }
    }
}
