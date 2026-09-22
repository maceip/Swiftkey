package com.pureswift.swiftandroid.passkeys

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.view.WindowManager
import androidx.activity.compose.setContent
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
import androidx.biometric.BiometricPrompt
import androidx.compose.runtime.*
import androidx.core.content.ContextCompat
import androidx.credentials.*
import androidx.credentials.exceptions.*
import androidx.credentials.exceptions.domerrors.*
import androidx.credentials.exceptions.publickeycredential.CreatePublicKeyCredentialDomException
import androidx.credentials.exceptions.publickeycredential.GetPublicKeyCredentialDomException
import androidx.credentials.provider.PendingIntentHandler
import androidx.fragment.app.FragmentActivity
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

/** Private entry point for an OS-selected request, or explicit in-app passkey management. */
class PasskeyActivity : FragmentActivity() {
    companion object {
        const val MANAGE = "com.pureswift.swiftandroid.passkeys.MANAGE"
        const val CREATE = "com.pureswift.swiftandroid.passkeys.CREATE"
        const val GET = "com.pureswift.swiftandroid.passkeys.GET"
    }
    private val worker = Executors.newSingleThreadExecutor()
    private lateinit var store: PasskeyStore
    private var records by mutableStateOf<List<PasskeyRecord>>(emptyList())
    private var message by mutableStateOf<String?>(null)
    private var busy by mutableStateOf(false)
    private var availability by mutableStateOf(PasskeyAvailability(false, "Checking this phone…"))
    private var request: WebAuthnRequest? = null
    private var clientData: WebAuthnClientData? = null
    private var selected: PasskeyRecord? = null
    private var pending: PendingPasskey? = null
    private var operation: PasskeySigningOperation? = null
    private var assertion: WebAuthnAssertion? = null
    private var prompt: BiometricPrompt? = null
    private var deadline = 0L
    private var selectionToken: String? = null
    private var pendingSelection: PasskeyRequestRegistry.Selection? = null
    private val ceremonyLock = Any()
    @Volatile private var completed = false
    @Volatile private var signedResponseReady = false
    private val managing get() = intent.action == MANAGE

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        setResult(Activity.RESULT_CANCELED)
        store = PasskeyStore(this)
        if (!managing) {
            try {
                require(Build.VERSION.SDK_INT >= 34 && savedInstanceState == null) {
                    "Restart the request from your browser."
                }
                readRequest()
            } catch (error: Exception) { fail(error); return }
        }
        setContent {
            PasskeyScreen(managing, request, selected, records, availability, busy, message,
                onBack = { if (managing) finish() else cancel() },
                onEnable = { enableProvider() }, onApprove = { approve() },
                onDelete = { delete(it) })
        }
        refresh()
    }

    private fun readRequest() {
        require(intent.action == CREATE || intent.action == GET)
        val uri = requireNotNull(intent.data)
        require(uri.scheme == "swiftkey-passkey" && uri.host == "selection" && uri.pathSegments.size == 1)
        val selection = requireNotNull(PasskeyPendingRequests.peek(uri.lastPathSegment)) {
            "This request expired. Start again from your browser."
        }
        selectionToken = uri.lastPathSegment
        pendingSelection = selection
        val json: String
        val hash: ByteArray?
        val caller: TrustedPasskeyCaller.Identity
        if (intent.action == CREATE) {
            val provider = requireNotNull(PendingIntentHandler.retrieveProviderCreateCredentialRequest(intent))
            val create = provider.callingRequest as? CreatePublicKeyCredentialRequest
                ?: throw IllegalArgumentException("A website passkey request is required.")
            require(!create.isConditional) { "Choose SwiftKey explicitly to create a passkey." }
            json = create.requestJson; hash = create.clientDataHash
            caller = TrustedPasskeyCaller.verify(this, provider.callingAppInfo, hash)
            require(selection.matches(true, caller, json, hash)) { "The browser request changed." }
            request = WebAuthn.parseCreate(json)
        } else {
            val provider = requireNotNull(PendingIntentHandler.retrieveProviderGetCredentialRequest(intent))
            val get = provider.credentialOptions.singleOrNull() as? GetPublicKeyCredentialOption
                ?: throw IllegalArgumentException("Select a single website passkey.")
            json = get.requestJson; hash = get.clientDataHash
            caller = TrustedPasskeyCaller.verify(this, provider.callingAppInfo, hash)
            require(selection.matches(false, caller, json, hash)) { "The browser request changed." }
            val parsed = WebAuthn.parseGet(json)
            val record = requireNotNull(selection.credentialId?.let(store::find)) { "This passkey is unavailable." }
            require(WebAuthn.matchingCredentials(parsed, listOf(record)).size == 1) { "This passkey belongs to another website." }
            selected = record; request = parsed
        }
        clientData = WebAuthn.clientData(requireNotNull(request), caller.origin, hash)
        deadline = minOf(selection.expires, SystemClock.elapsedRealtime() + requireNotNull(request).timeoutMillis)
    }

    private fun refresh() {
        background({ store.capability() to store.list() }) { (capability, values) ->
            availability = capability; records = values
        }
    }

    private fun enableProvider() {
        if (Build.VERSION.SDK_INT < 34) { message = "Website passkeys require Android 14 or later."; return }
        try { CredentialManager.create(this).createSettingsPendingIntent().send() }
        catch (_: Exception) { message = "Open Android Settings → Passwords, passkeys and accounts, and enable SwiftKey." }
    }

    private fun approve() {
        if (busy || completed) return
        busy = true; message = null
        background({
            checkDeadline()
            require(requireNotNull(PasskeyPendingRequests.take(selectionToken)) === pendingSelection) {
                "This request is already being approved or has expired."
            }
            val data = requireNotNull(clientData)
            when (val parsed = requireNotNull(request)) {
                is WebAuthnCreateRequest -> {
                    // The button click supplies user presence before reporting an excluded ID.
                    if (WebAuthn.excludedCredentials(parsed, store.list(parsed.rpId)).isNotEmpty())
                        throw WebAuthnException("credentialExcluded", "This website already has a matching passkey on this phone.")
                    val fresh = store.prepareRegistration(WebAuthn.newCredentialId(), parsed.rpId,
                        parsed.userHandle, parsed.userName, parsed.displayName)
                    pending = fresh
                    operation = store.beginRegistrationSignature(fresh,
                        "SwiftKey WebAuthn registration proof v1\u0000".toByteArray(Charsets.UTF_8) +
                            data.clientDataHash + fresh.publicKeyX963)
                }
                is WebAuthnGetRequest -> {
                    val draft = WebAuthn.prepareAssertion(parsed, requireNotNull(selected), data)
                    assertion = draft
                    operation = store.beginAssertionSignature(requireNotNull(selected).id, parsed.rpId, draft.signingPayload)
                }
            }
        }) { authenticate() }
    }

    private fun authenticate() {
        try {
            checkDeadline()
            val signing = requireNotNull(operation)
            prompt = BiometricPrompt(this, ContextCompat.getMainExecutor(this),
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                        if (completed || isDestroyed || isFinishing) return
                        val signature = result.cryptoObject?.signature
                        if (signature == null) { fail(IllegalStateException("Device verification did not authorize the key.")); return }
                        background({
                            checkDeadline()
                            val signed = store.finishSignature(signing, signature)
                            checkDeadline()
                            val authorized = WebAuthnUserAuthorization(userPresent = true, userVerified = true)
                            synchronized(ceremonyLock) {
                                checkDeadline()
                                val response = when (val parsed = requireNotNull(request)) {
                                    is WebAuthnCreateRequest -> {
                                        val fresh = requireNotNull(pending)
                                        val response = WebAuthn.registrationResponse(parsed, fresh.record,
                                            fresh.publicKeyX963, requireNotNull(clientData), authorized)
                                        checkDeadline()
                                        store.commitRegistration(fresh, signed)
                                        pending = null
                                        response
                                    }
                                    is WebAuthnGetRequest -> requireNotNull(assertion).response(signed.signatureDer, authorized)
                                }
                                val resultIntent = Intent()
                                if (intent.action == CREATE) PendingIntentHandler.setCreateCredentialResponse(
                                    resultIntent, CreatePublicKeyCredentialResponse(response))
                                else PendingIntentHandler.setGetCredentialResponse(resultIntent,
                                    GetCredentialResponse(PublicKeyCredential(response)))
                                signedResponseReady = true
                                resultIntent
                            }
                        }) { resultIntent ->
                            completed = true
                            setResult(Activity.RESULT_OK, resultIntent)
                            finish()
                        }
                    }
                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence) { cancel() }
                    override fun onAuthenticationFailed() { message = "Verification failed. Try again in the system prompt." }
                })
            val info = BiometricPrompt.PromptInfo.Builder()
                .setTitle(if (intent.action == CREATE) "Create website passkey" else "Sign in with SwiftKey")
                .setSubtitle(requireNotNull(request).rpId)
                .setAllowedAuthenticators(BIOMETRIC_STRONG or DEVICE_CREDENTIAL)
                .setConfirmationRequired(true).build()
            prompt!!.authenticate(info, BiometricPrompt.CryptoObject(signing.signature))
        } catch (error: Exception) { fail(error) }
    }

    private fun checkDeadline() {
        require(!completed && !isDestroyed && !isFinishing && SystemClock.elapsedRealtime() < deadline) {
            "This request expired. Start again from your browser."
        }
    }

    private fun delete(record: PasskeyRecord) {
        if (busy) return
        busy = true
        background({ store.delete(record.id); store.list() }) {
            records = it; busy = false; message = "Passkey removed from this phone."
        }
    }

    private fun <T> background(work: () -> T, success: (T) -> Unit) {
        if (completed || isDestroyed || isFinishing) return
        try {
            worker.execute {
                try {
                    val value = work()
                    runOnUiThread {
                        if (completed || isDestroyed || isFinishing) cleanup()
                        else try { success(value) } catch (error: Exception) { fail(error) }
                    }
                } catch (error: Exception) {
                    runOnUiThread { if (isDestroyed || isFinishing) cleanup() else fail(error) }
                }
            }
        } catch (_: RejectedExecutionException) { /* Activity has already closed. */ }
    }

    private fun fail(error: Exception) {
        if (managing) { busy = false; message = error.message ?: "This phone's passkeys are unavailable."; return }
        synchronized(ceremonyLock) {
            if (completed || signedResponseReady) return
            completed = true
        }
        val result = Intent()
        val text = when (error) {
            is WebAuthnException -> error.message
            is PasskeyStoreException -> error.message
            else -> "SwiftKey could not complete this request. Restart it from your browser."
        }
        if (intent.action == CREATE) {
            val dom = when ((error as? WebAuthnException)?.code) {
                "credentialExcluded" -> InvalidStateError()
                "notSupported" -> NotSupportedError()
                "invalidRequest" -> DataError()
                "bindingMismatch" -> SecurityError()
                else -> NotAllowedError()
            }
            PendingIntentHandler.setCreateCredentialException(result, CreatePublicKeyCredentialDomException(dom, text))
        } else PendingIntentHandler.setGetCredentialException(result, GetPublicKeyCredentialDomException(NotAllowedError(), text))
        setResult(Activity.RESULT_OK, result)
        finish()
    }

    private fun cancel() {
        synchronized(ceremonyLock) {
            if (completed || signedResponseReady) return
            completed = true
        }
        val result = Intent()
        if (intent.action == CREATE) PendingIntentHandler.setCreateCredentialException(result, CreateCredentialCancellationException("Cancelled by the user."))
        else PendingIntentHandler.setGetCredentialException(result, GetCredentialCancellationException("Cancelled by the user."))
        setResult(Activity.RESULT_OK, result)
        finish()
    }

    private fun cleanup() {
        operation?.let { runCatching { store.cancelSignature(it) } }; operation = null
        pending?.let { runCatching { store.abortRegistration(it) } }; pending = null
    }
    override fun onDestroy() {
        synchronized(ceremonyLock) { if (!signedResponseReady) completed = true }
        prompt?.cancelAuthentication()
        // Queue after in-flight key operations so cancellation cannot strand a newly created key.
        worker.execute { cleanup() }
        worker.shutdown()
        super.onDestroy()
    }
}
