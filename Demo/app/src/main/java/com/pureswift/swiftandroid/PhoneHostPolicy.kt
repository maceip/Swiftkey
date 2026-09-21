package com.pureswift.swiftandroid

import java.net.URI

/** Pure checks shared by transport, secure presentation and host tests. */
internal object PhoneHostPolicy {
    const val MAXIMUM_LINK_LENGTH = 8192
    private val ERROR_CODE = Regex("[A-Za-z][A-Za-z0-9_.:-]{0,127}")
    fun authorityErrorCode(status: Int, code: String?, hasErrorMessage: Boolean, requestBody: String, bearer: String): String? =
        code?.takeIf { status in 400..599 && hasErrorMessage && ERROR_CODE.matches(it)
            && !requestBody.contains(it) && (bearer.isEmpty() || !it.contains(bearer)) }
    fun canonicalOrigin(value: String, debug: Boolean): String {
        val uri = URI(value)
        require(uri.isAbsolute && uri.host != null && uri.rawUserInfo == null && uri.rawFragment == null && uri.rawQuery == null)
        require(uri.rawPath.isNullOrEmpty() || uri.rawPath == "/")
        val https = uri.scheme == "https" && (uri.port == -1 || uri.port in 1..65535)
        val loopback = debug && uri.scheme == "http" && uri.host == "127.0.0.1" && uri.port in 1..65535
        require(https || loopback)
        return "${uri.scheme}://${uri.rawAuthority}"
    }
    fun validateEndpoint(value: String, configuredOrigin: String, debug: Boolean) {
        val uri = URI(value)
        require(uri.rawUserInfo == null && uri.rawFragment == null && uri.rawQuery == null)
        require((uri.rawPath.startsWith("/v2/") || uri.rawPath in setOf("/v1/challenges", "/v1/epochs")) && !uri.rawPath.contains("..") && !uri.rawPath.contains("%"))
        val origin = canonicalOrigin("${uri.scheme}://${uri.rawAuthority}", debug)
        require(origin == canonicalOrigin(configuredOrigin, debug))
    }
    fun validateLinkSize(link: String) {
        require(link.isNotBlank() && link.length <= MAXIMUM_LINK_LENGTH && link.none { it.code < 0x20 })
    }
    fun mayPresent(expected: String, supplied: String, expiresAt: Long, now: Long): Boolean =
        expected.isNotEmpty() && supplied == expected && expiresAt > now
}
