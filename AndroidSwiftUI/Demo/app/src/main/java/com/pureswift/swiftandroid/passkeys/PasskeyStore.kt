package com.pureswift.swiftandroid.passkeys

import android.app.KeyguardManager
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.biometrics.BiometricManager
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import java.io.File
import java.io.ByteArrayOutputStream
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.math.BigInteger
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.nio.file.attribute.PosixFilePermissions
import java.security.AlgorithmParameters
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.ECParameterSpec
import java.security.spec.X509EncodedKeySpec
import java.util.Base64
import java.util.UUID

internal const val PASSKEY_ALIAS_PREFIX = "swiftkey.passkey.v1."
private const val MAX_RECORDS = 256
private const val MAX_PENDING = 8
private const val MAX_METADATA = 1024 * 1024
private const val OPERATION_LIFETIME = 5 * 60 * 1000L
private val passkeyMonitor = Any()
private val processState = PasskeyProcessState()

internal class PasskeyProcessState {
    val liveAliases = mutableSetOf<String>()
}

/**
 * Separate passkey namespace and private no-backup journal. All entry points are
 * serialized across instances and processes. A corrupt journal never triggers
 * cleanup. An unauthenticated/new key is never returned from list/find.
 */
class PasskeyStore internal constructor(
    private val database: PasskeyDatabase,
    private val keys: PasskeyKeyBackend,
    private val clock: () -> Long = System::currentTimeMillis,
    private val live: PasskeyProcessState = processState,
) {
    constructor(context: Context) : this(
        PasskeyDatabase(File(context.applicationContext.noBackupFilesDir, "swiftkey-passkeys")),
        AndroidPasskeyKeys(context.applicationContext),
    )

    private val pending = mutableMapOf<String, PendingPasskey>()
    private val operations = mutableMapOf<String, PasskeySigningOperation>()
    private val proofs = mutableMapOf<String, PasskeySignedResult>()
    private val leases = mutableMapOf<String, AutoCloseable>()

    fun capability(): PasskeyAvailability = keys.capability()

    fun list(rpId: String? = null): List<PasskeyRecord> = locked { state ->
        if (rpId != null) validateRpId(rpId)
        state.credentials.filter { rpId == null || it.record.rpId == rpId }.mapNotNull {
            try { validatedKey(it); it.record } catch (_: PasskeyStoreException) { null }
        }.sortedByDescending { it.createdAt }
    }

    fun find(id: String): PasskeyRecord? = locked { state ->
        validateId(id)
        val stored = state.credentials.firstOrNull { it.record.id == id } ?: return@locked null
        try { validatedKey(stored); stored.record } catch (_: PasskeyStoreException) { null }
    }

    fun prepareRegistration(id: String, rpId: String, userHandle: String, userName: String,
                            displayName: String): PendingPasskey = locked { state ->
        val record = PasskeyRecord(id, rpId, userHandle, userName, displayName, aliasFor(id), clock())
        validateRecord(record)
        failUnless(keys.capability().canCreate, "hardwareUnavailable", keys.capability().message)
        failUnless(state.credentials.size < MAX_RECORDS && state.pending.size < MAX_PENDING,
            "capacity", "Passkey storage is full. Remove an unused passkey before trying again.")
        failUnless(state.credentials.none { it.record.id == id } && state.pending.none { it.id == id }
            && record.keyAlias !in keys.aliases(), "alreadyExists", "This credential already exists.")
        // Persist the reservation before key generation. A process crash leaves
        // a recoverable reservation, never a silently selectable credential.
        val lease = database.pendingLease(record.keyAlias)
            ?: throw PasskeyStoreException("busy", "This passkey is already being created.")
        try { state.pending.add(record); database.write(state) }
        catch (error: Exception) { lease.close(); throw error }
        leases[record.keyAlias] = lease
        live.liveAliases.add(record.keyAlias)
        try {
            keys.create(record.keyAlias)
            val publicKey = keys.inspect(record.keyAlias)
            PendingPasskey(record, UUID.randomUUID().toString(), publicKey).also { pending[it.token] = it }
        } catch (error: Exception) {
            live.liveAliases.remove(record.keyAlias)
            // Cleanup is journaled; a cleanup failure leaves the reservation for
            // a later safe retry. Never touch an existing credential/root alias.
            try { removePending(state, record) } catch (_: Exception) { }
            leases.remove(record.keyAlias)?.close()
            if (error is PasskeyStoreException) throw error
            throw PasskeyStoreException("hardwareUnavailable", "StrongBox could not create this passkey. No fallback key was created.", error)
        }
    }

    fun beginRegistrationSignature(value: PendingPasskey, dataToSign: ByteArray): PasskeySigningOperation = locked { state ->
        validatePending(state, value)
        begin(value.record, value.publicKey, value.token, dataToSign)
    }

    fun beginAssertionSignature(id: String, rpId: String, dataToSign: ByteArray): PasskeySigningOperation = locked { state ->
        validateId(id); validateRpId(rpId)
        val stored = state.credentials.firstOrNull { it.record.id == id && it.record.rpId == rpId }
            ?: throw PasskeyStoreException("notFound", "This passkey is unavailable for this site.")
        begin(stored.record, validatedKey(stored), null, dataToSign)
    }

    private fun begin(record: PasskeyRecord, publicKey: ECPublicKey, pendingToken: String?, data: ByteArray): PasskeySigningOperation {
        failUnless(data.isNotEmpty() && data.size <= 65536, "invalidRequest", "Invalid passkey signing request.")
        failUnless(operations.values.none { it.record.id == record.id }, "busy", "This passkey is already awaiting authentication.")
        return PasskeySigningOperation(record, keys.signature(record.keyAlias), UUID.randomUUID().toString(),
            pendingToken, data.copyOf(), publicKey, clock()).also { operations[it.token] = it }
    }

    fun finishSignature(operation: PasskeySigningOperation, authenticatedSignature: Signature): PasskeySignedResult = locked { state ->
        failUnless(operations[operation.token] === operation && operation.signature === authenticatedSignature,
            "operationMismatch", "Authentication did not match this passkey request.")
        // Consume before signing, including failure. Never retry a consumed
        // authentication token or reinterpret it for a different request.
        operations.remove(operation.token)
        checkFresh(operation.createdAt)
        if (operation.pendingToken != null) {
            val value = pending[operation.pendingToken]
                ?: throw PasskeyStoreException("cancelled", "Passkey creation was cancelled.")
            validatePending(state, value)
        } else {
            val stored = state.credentials.firstOrNull { it.record == operation.record }
                ?: throw PasskeyStoreException("notFound", "This passkey was removed.")
            validatedKey(stored)
        }
        requireSamePublicKey(keys.inspect(operation.record.keyAlias), operation.publicKey)
        val bytes = try {
            authenticatedSignature.update(operation.payload)
            authenticatedSignature.sign()
        } catch (error: Exception) {
            throw PasskeyStoreException("authenticationFailed", "Unlock approval did not authorize this signature. Try again.", error)
        }
        val verified = try {
            Signature.getInstance("SHA256withECDSA").run {
                initVerify(operation.publicKey); update(operation.payload); verify(bytes)
            }
        } catch (_: Exception) { false }
        failUnless(verified, "invalidSignature", "The hardware passkey signature could not be verified.")
        PasskeySignedResult(operation, bytes).also { result ->
            operation.pendingToken?.let { proofs[it] = result }
        }
    }

    fun commitRegistration(value: PendingPasskey, result: PasskeySignedResult): PasskeyRecord = locked { state ->
        validatePending(state, value)
        failUnless(proofs[value.token] === result && result.operation.pendingToken == value.token
            && result.operation.record == value.record, "operationMismatch", "Passkey creation needs its matching unlock approval.")
        checkFresh(result.operation.createdAt)
        failUnless(state.credentials.none { it.record.id == value.record.id }, "alreadyExists", "This credential already exists.")
        requireSamePublicKey(keys.inspect(value.record.keyAlias), value.publicKey)
        state.credentials.add(StoredPasskey(value.record, encode(value.publicKey.encoded)))
        state.pending.removeAll { it == value.record }
        database.write(state)
        forget(value)
        value.record
    }

    fun abortRegistration(value: PendingPasskey) = locked { state ->
        if (pending[value.token] !== value) return@locked
        // A completed atomic write must never be undone by a late Cancel or by
        // a caller retrying after it missed the commit result.
        if (state.credentials.none { it.record.id == value.record.id }) removePending(state, value.record)
        forget(value)
    }

    fun cancelSignature(operation: PasskeySigningOperation) = synchronized(passkeyMonitor) {
        if (operations[operation.token] === operation) operations.remove(operation.token)
        Unit
    }

    fun delete(id: String) = locked { state ->
        validateId(id)
        val stored = state.credentials.firstOrNull { it.record.id == id } ?: return@locked
        state.credentials.remove(stored)
        state.deletions.add(stored.record.keyAlias)
        database.write(state)
        cleanupDeletions(state)
        operations.values.filter { it.record.id == id }.map { it.token }.forEach { operations.remove(it) }
    }

    private fun forget(value: PendingPasskey) {
        live.liveAliases.remove(value.record.keyAlias)
        leases.remove(value.record.keyAlias)?.close()
        pending.remove(value.token); proofs.remove(value.token)
        operations.values.filter { it.pendingToken == value.token }.map { it.token }.forEach { operations.remove(it) }
    }

    private fun checkFresh(created: Long) {
        val now = clock()
        failUnless(now >= created && now - created < OPERATION_LIFETIME, "expired", "This passkey request expired. Start again.")
    }

    private fun validatePending(state: PasskeyState, value: PendingPasskey) {
        failUnless(pending[value.token] === value && value.record in state.pending, "cancelled", "Passkey creation is no longer pending.")
        checkFresh(value.record.createdAt)
        requireSamePublicKey(keys.inspect(value.record.keyAlias), value.publicKey)
    }

    private fun validatedKey(stored: StoredPasskey): ECPublicKey {
        val key = keys.inspect(stored.record.keyAlias)
        failUnless(encode(key.encoded) == stored.publicKey, "keyChanged", "The hardware key no longer matches this passkey.")
        return key
    }

    private fun removePending(state: PasskeyState, record: PasskeyRecord) {
        if (record !in state.pending) return
        state.pending.remove(record); state.deletions.add(record.keyAlias)
        database.write(state)
        cleanupDeletions(state)
    }

    private fun cleanupDeletions(state: PasskeyState) {
        val removed = state.deletions.filter { alias ->
            failUnless(ownedAlias(alias), "invalidMetadata", "Passkey metadata is invalid.")
            keys.delete(alias); true
        }
        if (removed.isNotEmpty()) { state.deletions.removeAll(removed.toSet()); database.write(state) }
    }

    private fun recover(state: PasskeyState) {
        cleanupDeletions(state)
        for (record in state.pending.toList()) {
            if (record.keyAlias in live.liveAliases) continue
            // Cross-process lease spans the biometric prompt. OS file locks
            // release on process death, so another process can safely recover
            // only a genuinely abandoned reservation.
            database.pendingLease(record.keyAlias)?.use { removePending(state, record) }
        }
        val referenced = state.credentials.map { it.record.keyAlias }.toSet() + state.pending.map { it.keyAlias }
        val orphaned = keys.aliases().filter { ownedAlias(it) && it !in referenced && it !in live.liveAliases }
        if (orphaned.isNotEmpty()) {
            state.deletions.addAll(orphaned); database.write(state); cleanupDeletions(state)
        }
    }

    private fun <T> locked(block: (PasskeyState) -> T): T = synchronized(passkeyMonitor) {
        database.lock {
            failUnless(database.hasJournal || keys.aliases().none(::ownedAlias), "invalidMetadata",
                "Passkey metadata is missing. Existing hardware keys were preserved.")
            val state = database.read() // Parse/validate fully before any key deletion.
            recover(state)
            block(state)
        }
    }
}

internal data class StoredPasskey(val record: PasskeyRecord, val publicKey: String)
internal data class PasskeyState(val credentials: MutableList<StoredPasskey> = mutableListOf(),
                                 val pending: MutableList<PasskeyRecord> = mutableListOf(),
                                 val deletions: MutableSet<String> = mutableSetOf())

internal interface PasskeyKeyBackend {
    fun capability(): PasskeyAvailability
    fun aliases(): Set<String>
    fun create(alias: String)
    fun inspect(alias: String): ECPublicKey
    fun signature(alias: String): Signature
    fun delete(alias: String)
}

internal class AndroidPasskeyKeys(private val context: Context) : PasskeyKeyBackend {
    override fun capability(): PasskeyAvailability {
        if (Build.VERSION.SDK_INT < 34) return PasskeyAvailability(false, "Android 14 or later is required for website passkeys.")
        if (!context.packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE))
            return PasskeyAvailability(false, "This device does not provide StrongBox passkey storage.")
        if (context.getSystemService(KeyguardManager::class.java)?.isDeviceSecure != true)
            return PasskeyAvailability(false, "Set a secure device screen lock before creating a passkey.")
        val auth = BiometricManager.Authenticators.BIOMETRIC_STRONG or BiometricManager.Authenticators.DEVICE_CREDENTIAL
        if (context.getSystemService(BiometricManager::class.java)?.canAuthenticate(auth) != BiometricManager.BIOMETRIC_SUCCESS)
            return PasskeyAvailability(false, "Strong biometric or device-credential authentication is unavailable.")
        return PasskeyAvailability(true, "StrongBox passkeys require approval for every use.")
    }

    private fun store(): KeyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    override fun aliases(): Set<String> = hardware { store().aliases().toList().filter { ownedAlias(it) }.toSet() }
    override fun create(alias: String) = hardware {
        failUnless(ownedAlias(alias) && !store().containsAlias(alias), "alreadyExists", "This credential already exists.")
        failUnless(capability().canCreate, "hardwareUnavailable", capability().message)
        val spec = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setIsStrongBoxBacked(true)
            .setUserAuthenticationRequired(true)
            .setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG or KeyProperties.AUTH_DEVICE_CREDENTIAL)
            .build()
        KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore").apply { initialize(spec) }.generateKeyPair()
        Unit
    }

    private fun entry(alias: String): KeyStore.PrivateKeyEntry = hardware {
        failUnless(Build.VERSION.SDK_INT >= 31 && ownedAlias(alias), "hardwareUnavailable", "StrongBox passkey verification is unavailable.")
        val entry = store().getEntry(alias, null) as? KeyStore.PrivateKeyEntry
            ?: throw PasskeyStoreException("keyUnavailable", "This passkey's hardware key is unavailable.")
        val info = KeyFactory.getInstance("EC", "AndroidKeyStore").getKeySpec(entry.privateKey, KeyInfo::class.java)
        failUnless(info.securityLevel == KeyProperties.SECURITY_LEVEL_STRONGBOX && info.origin == KeyProperties.ORIGIN_GENERATED
            && entry.privateKey.encoded == null && info.keySize == 256 && info.purposes == KeyProperties.PURPOSE_SIGN
            && info.digests.toSet() == setOf(KeyProperties.DIGEST_SHA256) && info.isUserAuthenticationRequired
            && info.isUserAuthenticationRequirementEnforcedBySecureHardware
            && info.userAuthenticationValidityDurationSeconds in setOf(-1, 0)
            && info.userAuthenticationType == (KeyProperties.AUTH_BIOMETRIC_STRONG or KeyProperties.AUTH_DEVICE_CREDENTIAL),
            "keyUnavailable", "This key does not meet the StrongBox per-use authentication policy.")
        validatePublicKey(entry.certificate.publicKey as? ECPublicKey
            ?: throw PasskeyStoreException("keyUnavailable", "This passkey is not a P-256 key."))
        entry
    }

    override fun inspect(alias: String): ECPublicKey = entry(alias).certificate.publicKey as ECPublicKey
    override fun signature(alias: String): Signature = hardware {
        Signature.getInstance("SHA256withECDSA").apply { initSign(entry(alias).privateKey) }
    }
    override fun delete(alias: String) = hardware {
        failUnless(ownedAlias(alias), "invalidMetadata", "Invalid passkey alias.")
        store().deleteEntry(alias)
    }

    private fun <T> hardware(block: () -> T): T = try { block() }
    catch (error: PasskeyStoreException) { throw error }
    catch (error: StrongBoxUnavailableException) {
        throw PasskeyStoreException("hardwareUnavailable", "StrongBox is unavailable or full. No fallback key was created.", error)
    } catch (error: Exception) {
        throw PasskeyStoreException("keyUnavailable", "The hardware passkey is unavailable. Unlock the device or choose another passkey.", error)
    }
}

internal fun encode(bytes: ByteArray): String = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
internal fun decode(value: String, minimum: Int, maximum: Int): ByteArray {
    failUnless(value.length <= (maximum * 4 + 2) / 3 && value.matches(Regex("[A-Za-z0-9_-]+")), "invalidMetadata", "Invalid passkey identifier.")
    val decoded = try { Base64.getUrlDecoder().decode(value) } catch (error: Exception) {
        throw PasskeyStoreException("invalidMetadata", "Invalid passkey identifier.", error)
    }
    failUnless(decoded.size in minimum..maximum && encode(decoded) == value, "invalidMetadata", "Invalid passkey identifier.")
    return decoded
}
internal fun aliasFor(id: String): String { validateId(id); return PASSKEY_ALIAS_PREFIX + id }
private fun validateId(id: String) { decode(id, 32, 32) }
private fun ownedAlias(alias: String): Boolean = alias.startsWith(PASSKEY_ALIAS_PREFIX) &&
    runCatching { validateId(alias.removePrefix(PASSKEY_ALIAS_PREFIX)) }.isSuccess
private fun validateRpId(value: String) {
    failUnless(value.length in 1..253 && value == value.lowercase(java.util.Locale.ROOT)
        && value.split('.').all { it.length in 1..63 && it.matches(Regex("[a-z0-9](?:[a-z0-9-]*[a-z0-9])?")) },
        "invalidMetadata", "Invalid passkey site identifier.")
}
private fun validateRecord(value: PasskeyRecord) {
    validateId(value.id); validateRpId(value.rpId); decode(value.userHandle, 1, 64)
    failUnless(value.keyAlias == aliasFor(value.id) && value.createdAt > 0, "invalidMetadata", "Invalid passkey key binding.")
    for (name in listOf(value.userName, value.displayName)) {
        val bytes = try { Charsets.UTF_8.newEncoder().onMalformedInput(CodingErrorAction.REPORT).encode(java.nio.CharBuffer.wrap(name)) }
        catch (error: Exception) { throw PasskeyStoreException("invalidMetadata", "Invalid passkey account name.", error) }
        failUnless(name.isNotEmpty() && bytes.remaining() <= 256 && name.none { it.isISOControl() }, "invalidMetadata", "Invalid passkey account name.")
    }
}
private fun failUnless(condition: Boolean, code: String, message: String) {
    if (!condition) throw PasskeyStoreException(code, message)
}
private fun requireSamePublicKey(actual: ECPublicKey, expected: ECPublicKey) {
    failUnless(actual.encoded.contentEquals(expected.encoded), "keyChanged", "The hardware key no longer matches this passkey.")
}
private fun validatePublicKey(key: ECPublicKey) {
    val expected = AlgorithmParameters.getInstance("EC").apply { init(ECGenParameterSpec("secp256r1")) }.getParameterSpec(ECParameterSpec::class.java)
    val actual = key.params
    failUnless(actual.curve == expected.curve && actual.generator == expected.generator
        && actual.order == expected.order && actual.cofactor == expected.cofactor,
        "keyUnavailable", "This passkey is not a P-256 key.")
}
internal fun passkeyPublicBytes(key: ECPublicKey): ByteArray {
    fun coordinate(value: BigInteger): ByteArray {
        val bytes = value.toByteArray().let { if (it.size == 33 && it[0] == 0.toByte()) it.copyOfRange(1, 33) else it }
        failUnless(bytes.size <= 32, "keyUnavailable", "Invalid passkey public key.")
        return ByteArray(32 - bytes.size) + bytes
    }
    return byteArrayOf(4) + coordinate(key.w.affineX) + coordinate(key.w.affineY)
}

/** Same-directory atomic replacement, bounded strict JSON and private permissions. */
internal class PasskeyDatabase(private val directory: File) {
    internal val file = File(directory, "records-v1.json")
    val hasJournal: Boolean get() = Files.exists(file.toPath(), java.nio.file.LinkOption.NOFOLLOW_LINKS)
    fun pendingLease(alias: String): AutoCloseable? {
        failUnless(ownedAlias(alias), "invalidMetadata", "Invalid passkey alias.")
        val handle = RandomAccessFile(File(directory, ".pending-${alias.removePrefix(PASSKEY_ALIAS_PREFIX)}.lock"), "rw")
        try {
            val lock = try { handle.channel.tryLock() } catch (_: java.nio.channels.OverlappingFileLockException) { null }
            if (lock == null) { handle.close(); return null }
            return AutoCloseable { try { lock.release() } finally { handle.close() } }
        } catch (error: Exception) { handle.close(); throw error }
    }
    fun <T> lock(block: () -> T): T {
        try {
            Files.createDirectories(directory.toPath())
            Files.setPosixFilePermissions(directory.toPath(), PosixFilePermissions.fromString("rwx------"))
            RandomAccessFile(File(directory, ".lock"), "rw").use { handle ->
                Files.setPosixFilePermissions(File(directory, ".lock").toPath(), PosixFilePermissions.fromString("rw-------"))
                handle.channel.lock().use { return block() }
            }
        } catch (error: PasskeyStoreException) { throw error }
        catch (error: Exception) { throw PasskeyStoreException("storageUnavailable", "Private passkey storage is unavailable.", error) }
    }

    fun read(): PasskeyState {
        failUnless(!Files.isSymbolicLink(file.toPath()), "invalidMetadata", "Passkey metadata is invalid.")
        if (!file.exists()) return PasskeyState()
        failUnless(file.length() in 1..MAX_METADATA.toLong(), "invalidMetadata", "Passkey metadata is invalid.")
        val bytes = file.inputStream().use { stream ->
            val buffer = ByteArray(8192)
            val output = ByteArrayOutputStream()
            while (output.size() <= MAX_METADATA) {
                val count = stream.read(buffer, 0, minOf(buffer.size, MAX_METADATA + 1 - output.size()))
                if (count < 0) break
                output.write(buffer, 0, count)
            }
            output.toByteArray()
        }
        failUnless(bytes.size <= MAX_METADATA, "invalidMetadata", "Passkey metadata is too large.")
        val text = try { Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString() }
        catch (error: Exception) { throw PasskeyStoreException("invalidMetadata", "Passkey metadata is invalid.", error) }
        return PasskeyJson.read(text)
    }

    fun write(state: PasskeyState) {
        val bytes = PasskeyJson.write(state).toByteArray(Charsets.UTF_8)
        failUnless(bytes.size <= MAX_METADATA, "capacity", "Passkey storage is full.")
        val temporary = Files.createTempFile(directory.toPath(), ".records-", ".tmp", PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rw-------")))
        try {
            FileOutputStream(temporary.toFile()).use { it.write(bytes); it.fd.sync() }
            Files.move(temporary, file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        } finally { Files.deleteIfExists(temporary) }
    }
}

/** Narrow JSON grammar: duplicate/unknown keys, wrong types and trailing data fail closed. */
private object PasskeyJson {
    private val recordKeys = setOf("id", "rpId", "userHandle", "userName", "displayName", "keyAlias", "createdAt")
    fun read(text: String): PasskeyState {
        val value = Parser(text).parse() as? Map<*, *> ?: invalid()
        if (value.keys != setOf("version", "credentials", "pending", "deletions") || value["version"] != 1L) invalid()
        fun rows(name: String, maximum: Int): List<*> = (value[name] as? List<*>)?.also { if (it.size > maximum) invalid() } ?: invalid()
        fun record(map: Map<*, *>): PasskeyRecord = PasskeyRecord(
            map["id"] as? String ?: invalid(), map["rpId"] as? String ?: invalid(), map["userHandle"] as? String ?: invalid(),
            map["userName"] as? String ?: invalid(), map["displayName"] as? String ?: invalid(),
            map["keyAlias"] as? String ?: invalid(), map["createdAt"] as? Long ?: invalid(),
        ).also(::validateRecord)
        val credentials = rows("credentials", MAX_RECORDS).map { raw ->
            val map = raw as? Map<*, *> ?: invalid()
            if (map.keys != recordKeys + "publicKey") invalid()
            val publicKey = map["publicKey"] as? String ?: invalid()
            try { validatePublicKey(KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(decode(publicKey, 64, 512))) as ECPublicKey) }
            catch (_: Exception) { invalid() }
            StoredPasskey(record(map), publicKey)
        }.toMutableList()
        val pending = rows("pending", MAX_PENDING).map { raw ->
            val map = raw as? Map<*, *> ?: invalid()
            if (map.keys != recordKeys) invalid()
            record(map)
        }.toMutableList()
        val deletions = rows("deletions", MAX_RECORDS + MAX_PENDING).map { it as? String ?: invalid() }
        val ids = credentials.map { it.record.id } + pending.map { it.id }
        val aliases = credentials.map { it.record.keyAlias } + pending.map { it.keyAlias }
        if (ids.size != ids.toSet().size || deletions.size != deletions.toSet().size ||
            deletions.any { !ownedAlias(it) || it in aliases }) invalid()
        return PasskeyState(credentials, pending, deletions.toMutableSet())
    }

    fun write(state: PasskeyState): String {
        fun quote(s: String): String = buildString {
            append('"'); for (c in s) when(c) { '"' -> append("\\\""); '\\' -> append("\\\\"); else -> if (c.code < 32) append("\\u%04x".format(c.code)) else append(c) }; append('"')
        }
        fun fields(r: PasskeyRecord) = listOf("id" to r.id, "rpId" to r.rpId, "userHandle" to r.userHandle,
            "userName" to r.userName, "displayName" to r.displayName, "keyAlias" to r.keyAlias).joinToString(",") { quote(it.first)+":"+quote(it.second) } + ",\"createdAt\":" + r.createdAt
        val result = "{\"version\":1,\"credentials\":[" + state.credentials.joinToString(",") { "{"+fields(it.record)+",\"publicKey\":"+quote(it.publicKey)+"}" } +
            "],\"pending\":[" + state.pending.joinToString(",") { "{"+fields(it)+"}" } +
            "],\"deletions\":[" + state.deletions.joinToString(",") { quote(it) } + "]}"
        read(result) // Validate before replacing any usable journal.
        return result
    }

    private fun invalid(): Nothing = throw PasskeyStoreException("invalidMetadata", "Passkey metadata is invalid. Existing keys were preserved.")
    private class Parser(val text: String) {
        var position = 0
        fun parse(): Any { val value = value(0); whitespace(); if (position != text.length) invalid(); return value }
        fun whitespace() { while (position < text.length && text[position] in " \r\n\t") position++ }
        fun take(c: Char): Boolean { whitespace(); return if (position < text.length && text[position] == c) { position++; true } else false }
        fun value(depth: Int): Any {
            if (depth > 8) invalid(); whitespace(); if (position >= text.length) invalid()
            return when(text[position]) {
                '{' -> { position++; val result=linkedMapOf<String,Any>(); if (!take('}')) { do {
                    whitespace(); if (position>=text.length || text[position]!='"') invalid(); val key=string()
                    if (key in result || !take(':')) invalid(); result[key]=value(depth+1)
                } while(take(',')); if (!take('}')) invalid() }; result }
                '[' -> { position++; val result=mutableListOf<Any>(); if (!take(']')) { do {
                    if(result.size>MAX_RECORDS+MAX_PENDING) invalid(); result.add(value(depth+1))
                } while(take(',')); if (!take(']')) invalid() }; result }
                '"' -> string()
                in '0'..'9' -> { val start=position; while(position<text.length && text[position] in '0'..'9') position++
                    val number=text.substring(start,position); if(number.length>1 && number[0]=='0') invalid(); number.toLongOrNull() ?: invalid() }
                else -> invalid()
            }
        }
        fun string(): String {
            position++; val result=StringBuilder()
            while(position<text.length) {
                val c=text[position++]
                if(c=='"') return result.toString()
                if(c.code<32) invalid()
                if(c!='\\') result.append(c) else {
                    if(position>=text.length) invalid()
                    when(val escaped=text[position++]) {
                        '"','\\','/' -> result.append(escaped)
                        'b' -> result.append('\b'); 'f' -> result.append('\u000c'); 'n' -> result.append('\n'); 'r' -> result.append('\r'); 't' -> result.append('\t')
                        'u' -> { if(position+4>text.length) invalid(); val hex=text.substring(position,position+4); if(!hex.matches(Regex("[0-9a-fA-F]{4}"))) invalid(); result.append(hex.toInt(16).toChar()); position+=4 }
                        else -> invalid()
                    }
                }
            }; invalid()
        }
    }
}
