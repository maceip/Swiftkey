package com.pureswift.swiftandroid.passkeys

import java.nio.file.Files
import java.nio.file.attribute.PosixFilePermissions
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import org.junit.After
import org.junit.Assert.*
import org.junit.Test

/** Software keys exist only in this injected test double, never as a production fallback. */
class PasskeyStoreTest {
    private val directory = Files.createTempDirectory("passkey-store-test").toFile()
    private val database = PasskeyDatabase(directory)
    private val keys = TestKeys()
    private val live = PasskeyProcessState()
    private var now = 1_000_000L
    private val store = PasskeyStore(database, keys, { now }, live)
    private val reservations = mutableListOf<PendingPasskey>()

    @After fun cleanup() {
        reservations.forEach { runCatching { store.abortRegistration(it) } }
        directory.deleteRecursively()
    }

    private fun id(number: Int) = encode(ByteArray(32).also { it[30] = (number shr 8).toByte(); it[31] = number.toByte() })
    private fun prepare(number: Int = 1) = store.prepareRegistration(id(number), "example.com", encode(byteArrayOf(7)), "person@example.com", "Person").also { reservations.add(it) }
    private fun approve(value: PendingPasskey, payload: ByteArray = byteArrayOf(1, 2, 3)): PasskeySignedResult {
        val operation = store.beginRegistrationSignature(value, payload)
        return store.finishSignature(operation, operation.signature)
    }
    private fun commit(number: Int = 1): PasskeyRecord { val value = prepare(number); return store.commitRegistration(value, approve(value)) }
    private fun reject(code: String? = null, block: () -> Unit) {
        try { block(); fail("Expected fail-closed rejection") }
        catch (error: PasskeyStoreException) { if (code != null) assertEquals(code, error.code) }
    }

    @Test fun pendingKeyIsNotSelectableAndOnlyVerifiedApprovalCommitsIt() {
        val value = prepare()
        assertTrue(store.list().isEmpty()); assertNull(store.find(value.record.id))
        assertEquals(65, value.publicKeyX963.size); assertEquals(4, value.publicKeyX963[0].toInt())
        val proof = approve(value)
        assertTrue(store.list().isEmpty())
        assertEquals(value.record, store.commitRegistration(value, proof))
        assertEquals(listOf(value.record), store.list("example.com"))
        assertTrue(store.list("other.example").isEmpty())
        assertEquals(value.record, store.find(value.record.id))
        assertEquals(1, keys.signatureInitializations)
    }

    @Test fun signingUsesOriginalCopiedBytesAndExactAuthenticatedCryptoObject() {
        val record = commit()
        val original = byteArrayOf(8, 9, 10)
        val supplied = original.copyOf()
        val operation = store.beginAssertionSignature(record.id, record.rpId, supplied)
        supplied.fill(0)
        reject("operationMismatch") { store.finishSignature(operation, Signature.getInstance("SHA256withECDSA")) }
        val result = store.finishSignature(operation, operation.signature)
        assertTrue(Signature.getInstance("SHA256withECDSA").run {
            initVerify(keys.inspect(record.keyAlias)); update(original); verify(result.signatureDer)
        })
        val exposed = result.signatureDer; exposed.fill(0)
        assertFalse(result.signatureDer.contentEquals(exposed))
        reject("operationMismatch") { store.finishSignature(operation, operation.signature) }
    }

    @Test fun registrationCannotUseAnotherPendingKeyApproval() {
        val first = prepare(1); val second = prepare(2)
        val proof = approve(first)
        reject("operationMismatch") { store.commitRegistration(second, proof) }
        assertTrue(store.list().isEmpty())
        store.commitRegistration(first, proof)
        assertEquals(listOf(first.record), store.list())
    }

    @Test fun separateCredentialsForSameUserAreAllowedWithoutOverwritingAnything() {
        val first = commit(1)
        val publicKey = keys.inspect(first.keyAlias).encoded.copyOf()
        val second = commit(2)
        assertEquals(first.userHandle, second.userHandle)
        assertEquals(2, store.list().size)
        reject("alreadyExists") { prepare(1) }
        assertArrayEquals(publicKey, keys.inspect(first.keyAlias).encoded)
        assertTrue(keys.deleted.isEmpty())
    }

    @Test fun abortOnlyDeletesFreshPendingKeyAndLateAbortCannotDeleteCommittedKey() {
        keys.pairs["swiftkey_attested_root_v2"] = TestKeys.generate()
        val committed = prepare(1); store.commitRegistration(committed, approve(committed))
        val cancelled = prepare(2)
        store.abortRegistration(cancelled); store.abortRegistration(cancelled)
        store.abortRegistration(committed)
        assertEquals(setOf(cancelled.record.keyAlias), keys.deleted.toSet())
        assertNotNull(keys.pairs["swiftkey_attested_root_v2"])
        assertEquals(committed.record, store.find(committed.record.id))
    }

    @Test fun multipleStoreInstancesDoNotRecoverAnActivePendingKey() {
        val value = prepare()
        val other = PasskeyStore(PasskeyDatabase(directory), keys, { now }, live)
        assertTrue(other.list().isEmpty())
        assertTrue(keys.deleted.isEmpty())
        store.commitRegistration(value, approve(value))
        assertEquals(value.record, other.find(value.record.id))
    }

    @Test fun processLeaseProtectsPendingKeyUntilTheOwningProcessDies() {
        val record = PasskeyRecord(id(3), "example.com", encode(byteArrayOf(1)), "user", "User", aliasFor(id(3)), now)
        keys.create(record.keyAlias)
        database.lock { database.write(PasskeyState(pending = mutableListOf(record))) }
        val lease = database.pendingLease(record.keyAlias)!!
        val otherProcess = PasskeyStore(database, keys, { now }, PasskeyProcessState())
        assertTrue(otherProcess.list().isEmpty()); assertTrue(keys.deleted.isEmpty())
        lease.close() // OS releases this lock when the owning process exits.
        assertTrue(otherProcess.list().isEmpty())
        assertEquals(listOf(record.keyAlias), keys.deleted)
        assertTrue(database.read().pending.isEmpty())
    }

    @Test fun orphanCleanupIsRestrictedToValidOwnedAliasesAndPreservesCommittedKeys() {
        val committed = commit()
        val orphan = aliasFor(id(4))
        val root = "swiftkey_attested_root_v2"
        val malformed = PASSKEY_ALIAS_PREFIX + "not-a-credential-id"
        keys.create(orphan); keys.create(root); keys.create(malformed)
        val recreated = PasskeyStore(database, keys, { now }, PasskeyProcessState())
        assertEquals(listOf(committed), recreated.list())
        assertEquals(listOf(orphan), keys.deleted)
        assertTrue(keys.pairs.containsKey(root)); assertTrue(keys.pairs.containsKey(malformed))
    }

    @Test fun wrongSiteOrKeySubstitutionNeverBecomesSelectable() {
        val record = commit()
        reject("notFound") { store.beginAssertionSignature(record.id, "attacker.example", byteArrayOf(1)) }
        keys.pairs[record.keyAlias] = TestKeys.generate()
        assertNull(store.find(record.id)); assertTrue(store.list().isEmpty())
        reject("keyChanged") { store.beginAssertionSignature(record.id, record.rpId, byteArrayOf(1)) }
        assertTrue(keys.deleted.isEmpty())
    }

    @Test fun cancellationAndDeletionInvalidateOutstandingOperations() {
        val record = commit()
        val cancelled = store.beginAssertionSignature(record.id, record.rpId, byteArrayOf(1))
        store.cancelSignature(cancelled)
        reject("operationMismatch") { store.finishSignature(cancelled, cancelled.signature) }
        val removed = store.beginAssertionSignature(record.id, record.rpId, byteArrayOf(2))
        store.delete(record.id)
        assertNull(store.find(record.id))
        reject("operationMismatch") { store.finishSignature(removed, removed.signature) }
        assertEquals(listOf(record.keyAlias), keys.deleted)
    }

    @Test fun expiredOrClockRollbackRequestsCannotCommitOrSign() {
        val value = prepare()
        val operation = store.beginRegistrationSignature(value, byteArrayOf(1))
        now += 300_000L
        reject("expired") { store.finishSignature(operation, operation.signature) }
        store.abortRegistration(value)
        val next = prepare(2)
        val proof = approve(next)
        now -= 1
        reject("expired") { store.commitRegistration(next, proof) }
        assertTrue(store.list().isEmpty())
    }

    @Test fun strictMetadataFailuresPreserveEveryKeyWithoutCleanup() {
        val record = commit()
        val original = database.file.readText()
        val cases = listOf(
            original.replace("\"version\":1", "\"version\":2"),
            original.replace("\"version\":1", "\"version\":1,\"version\":1"),
            original.replace("\"version\":1", "\"version\":true"),
            original.replace("\"version\":1", "\"version\":1,\"unexpected\":[]"),
            original.replace(record.keyAlias, "swiftkey_attested_root_v2"),
            original + "[]",
        )
        keys.create(aliasFor(id(10)))
        for (bad in cases) {
            database.file.writeText(bad)
            reject { store.list() }
            assertTrue(keys.deleted.isEmpty())
            assertTrue(keys.pairs.containsKey(record.keyAlias))
        }
        database.file.writeText(original)
    }

    @Test fun boundedMetadataAndSymlinkReadsFailClosed() {
        commit()
        database.file.writeBytes(ByteArray(1024 * 1024 + 1) { 32 })
        reject("invalidMetadata") { store.list() }
        database.file.delete()
        val external = Files.createTempFile("passkey-external", ".json")
        try {
            Files.write(external, "{}".toByteArray())
            Files.createSymbolicLink(database.file.toPath(), external)
            reject("invalidMetadata") { store.list() }
            assertTrue(keys.deleted.isEmpty())
        } finally { Files.deleteIfExists(database.file.toPath()); Files.deleteIfExists(external) }
    }

    @Test fun missingMetadataDoesNotTreatCommittedKeysAsDisposableOrphans() {
        val record = commit()
        database.file.delete()
        reject("invalidMetadata") { store.list() }
        assertTrue(keys.pairs.containsKey(record.keyAlias))
        assertTrue(keys.deleted.isEmpty())
    }

    @Test fun invalidReplacementLeavesAtomicMetadataAndPrivatePermissionsIntact() {
        commit()
        val original = database.file.readBytes()
        val state = database.read()
        state.credentials.add(state.credentials.first())
        reject("invalidMetadata") { database.lock { database.write(state) } }
        assertArrayEquals(original, database.file.readBytes())
        assertEquals(PosixFilePermissions.fromString("rw-------"), Files.getPosixFilePermissions(database.file.toPath()))
        assertEquals(PosixFilePermissions.fromString("rwx------"), Files.getPosixFilePermissions(directory.toPath()))
        assertFalse(directory.listFiles()!!.any { it.name.endsWith(".tmp") })
    }

    @Test fun concurrentInstancesSerializeCreationWithoutLostRecords() {
        val executor = Executors.newFixedThreadPool(4)
        try {
            val tasks = (1..12).map { number -> Callable {
                val separate = PasskeyStore(database, keys, { now }, live)
                val value = separate.prepareRegistration(id(number), "example.com", encode(byteArrayOf(1)), "user", "User")
                val operation = separate.beginRegistrationSignature(value, byteArrayOf(number.toByte()))
                separate.commitRegistration(value, separate.finishSignature(operation, operation.signature))
            } }
            val result = executor.invokeAll(tasks).map { it.get() }
            assertEquals(result.map { it.id }.toSet(), store.list().map { it.id }.toSet())
            assertEquals(12, database.read().credentials.size)
            assertTrue(keys.deleted.isEmpty())
        } finally { executor.shutdownNow() }
    }

    @Test fun unavailableHardwareDoesNotGenerateFallbackKeys() {
        keys.available = false
        assertFalse(store.capability().canCreate)
        reject("hardwareUnavailable") { prepare() }
        assertTrue(keys.pairs.isEmpty())
        assertEquals(0, keys.signatureInitializations)
    }

    private class TestKeys : PasskeyKeyBackend {
        val pairs = mutableMapOf<String, KeyPair>()
        val deleted = mutableListOf<String>()
        var available = true
        var signatureInitializations = 0
        override fun capability() = PasskeyAvailability(available, "Test hardware capability")
        override fun aliases() = pairs.keys.toSet()
        override fun create(alias: String) { check(alias !in pairs); pairs[alias] = generate() }
        override fun inspect(alias: String) = pairs[alias]?.public as? ECPublicKey
            ?: throw PasskeyStoreException("keyUnavailable", "Test key unavailable")
        override fun signature(alias: String): Signature {
            signatureInitializations++
            return Signature.getInstance("SHA256withECDSA").apply { initSign(pairs.getValue(alias).private) }
        }
        override fun delete(alias: String) { pairs.remove(alias); deleted.add(alias) }
        companion object {
            fun generate(): KeyPair = KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()
        }
    }
}
