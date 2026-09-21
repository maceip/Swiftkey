package com.pureswift.swiftandroid

import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.MultiFormatReader
import com.google.zxing.MultiFormatWriter
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.common.HybridBinarizer
import org.junit.Assert.*
import org.junit.Test

class PhoneHostPolicyTest {
    @Test fun productionAuthorityRequiresHTTPSAndNoAmbientURLCredentials() {
        assertEquals("https://authority.example", PhoneHostPolicy.canonicalOrigin("https://authority.example/", false))
        for (url in listOf("http://authority.example", "http://127.0.0.1:8080", "https://user@authority.example", "https://authority.example?q=pin", "https://authority.example#key", "https://authority.example/pair")) {
            assertRejected { PhoneHostPolicy.canonicalOrigin(url, false) }
        }
    }
    @Test fun debugLoopbackExceptionRequiresExactIPv4AndExplicitPort() {
        assertEquals("http://127.0.0.1:8080", PhoneHostPolicy.canonicalOrigin("http://127.0.0.1:8080", true))
        for (url in listOf("http://localhost:8080", "http://127.0.0.1", "http://127.0.0.1:0", "http://192.168.1.2:8080")) {
            assertRejected { PhoneHostPolicy.canonicalOrigin(url, true) }
        }
    }
    @Test fun endpointsCannotChangePinnedOriginOrUseV1Governance() {
        val origin = "https://authority.example"
        for (path in listOf("/v2/pairings", "/v2/accounts/roster", "/v1/challenges", "/v1/epochs")) {
            PhoneHostPolicy.validateEndpoint(origin + path, origin, false)
        }
        for (url in listOf("https://attacker.example/v2/pairings", "https://authority.example.attacker.example/v2/pairings",
            "$origin/v1/admin/accounts", "$origin/v1/pairing/approve", "$origin/v2/../v1/admin/accounts",
            "$origin/v2/%2e%2e/v1/admin/accounts", "$origin/v2/pairings#secret", "$origin/v2/pairings?secret=value")) {
            assertRejected { PhoneHostPolicy.validateEndpoint(url, origin, false) }
        }
    }
    @Test fun onlyParsedHTTPAuthorityCodesAreDefinitiveErrorsAndSecretsAreNeverEchoed() {
        assertEquals("invalidProof", PhoneHostPolicy.authorityErrorCode(403, "invalidProof", true, "request", "bearer-secret"))
        assertNull(PhoneHostPolicy.authorityErrorCode(0, "requestTimedOut", true, "request", ""))
        assertNull(PhoneHostPolicy.authorityErrorCode(503, null, true, "request", ""))
        assertNull(PhoneHostPolicy.authorityErrorCode(302, "invalidProof", true, "request", ""))
        assertNull(PhoneHostPolicy.authorityErrorCode(403, "bearer-secret", true, "request", "bearer-secret"))
        assertNull(PhoneHostPolicy.authorityErrorCode(403, "private-capability", true, "{capability:private-capability}", ""))
        assertNull(PhoneHostPolicy.authorityErrorCode(500, "database error with private data", true, "request", ""))
    }
    @Test fun secretPresentationChecksCompleteBindingAndDeadlineAtUse() {
        val context = "pair1|3|immutable-digest|500"
        assertTrue(PhoneHostPolicy.mayPresent(context, context, 500, 499))
        assertFalse(PhoneHostPolicy.mayPresent(context, context, 500, 500))
        assertFalse(PhoneHostPolicy.mayPresent("", context, 500, 100))
        assertFalse(PhoneHostPolicy.mayPresent(context, "pair1|2|old-digest|500", 500, 100))
    }
    @Test fun malformedOrOversizedImportNeverReachesProtocol() {
        PhoneHostPolicy.validateLinkSize("https://authority.example/pair#transient-test-capability")
        for (link in listOf("", " ", "x".repeat(8193), "https://authority.example/\nsecret")) {
            assertRejected { PhoneHostPolicy.validateLinkSize(link) }
        }
    }
    @Test fun qrCodeRoundTripPreservesInvitationFragmentExactly() {
        val invitation = "https://authority.example/pair#pairing-id.TestOnly_Secret-Capability123"
        val matrix = MultiFormatWriter().encode(invitation, BarcodeFormat.QR_CODE, 640, 640)
        val pixels = IntArray(matrix.width * matrix.height) { index -> if (matrix[index % matrix.width, index / matrix.width]) -0x1000000 else -0x1 }
        val bitmap = BinaryBitmap(HybridBinarizer(RGBLuminanceSource(matrix.width, matrix.height, pixels)))
        assertEquals(invitation, MultiFormatReader().decode(bitmap).text)
    }
    private fun assertRejected(operation: () -> Unit) {
        try { operation(); fail("Expected input rejection") } catch (_: IllegalArgumentException) { }
    }
}
