import XCTest
import Foundation
import CryptoKit
import SwiftKeyPasskeys

final class MockPasskeyCoordinatorTests: XCTestCase {
    @MainActor private func isolated(_ body: (MockPasskeyStore, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SwiftKeyMockTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(MockPasskeyStore(directoryURL: directory), directory)
    }

    @MainActor func testRegistrationPersistenceAndRealSignatureAcrossCoordinatorRestart() async throws {
        try isolated { store, directory in
            XCTAssertTrue(MockPasskeyCoordinator.isMockEnabled)
            let first = MockPasskeyCoordinator(store: store)
            first.beginMockRegistration(userName: "test@swiftkey.mock")
            let pending = try XCTUnwrap(first.pending)
            XCTAssertTrue(try store.credentials().isEmpty)
            guard case .registration? = first.approve(requestID: pending.id, simulatedVerification: true) else {
                XCTFail("Registration did not complete: \(first.error ?? "unknown")"); return
            }
            XCTAssertEqual(try store.credentials().count, 1)
            let second = MockPasskeyCoordinator(store: MockPasskeyStore(directoryURL: directory))
            XCTAssertEqual(second.credentials.count, 1)
            let saved = try XCTUnwrap(second.credentials.first)
            second.beginMockAssertion(credentialID: saved.id)
            let sign = try XCTUnwrap(second.pending)
            guard case .assertion(let response)? = second.approve(requestID: sign.id, simulatedVerification: true) else {
                XCTFail("Assertion did not complete: \(second.error ?? "unknown")"); return
            }
            try response.verify(publicKeyX963: XCTUnwrap(store.credentials().first).publicKeyX963)
            XCTAssertNil(second.approve(requestID: sign.id, simulatedVerification: true))
            second.removeCredential(id: saved.id)
            XCTAssertTrue(try store.credentials().isEmpty)
        }
    }

    @MainActor func testCancelAndFailedVerificationCannotMintCredentials() async throws {
        try isolated { store, _ in
            let coordinator = MockPasskeyCoordinator(store: store)
            coordinator.beginMockRegistration(userName: "cancel@swiftkey.mock")
            let request = try XCTUnwrap(coordinator.pending)
            XCTAssertNil(coordinator.approve(requestID: request.id, simulatedVerification: false))
            XCTAssertTrue(try store.credentials().isEmpty)
            coordinator.cancel(requestID: request.id)
            XCTAssertNil(coordinator.approve(requestID: request.id, simulatedVerification: true))
            XCTAssertTrue(try store.credentials().isEmpty)
        }
    }

    @MainActor func testExpiredRequestAndRealWebsiteCannotMintCredentials() async throws {
        try isolated { store, _ in
            var instant = Date()
            let coordinator = MockPasskeyCoordinator(store: store, now: { instant })
            coordinator.beginMockRegistration(userName: "expires@swiftkey.mock")
            let pending = try XCTUnwrap(coordinator.pending)
            instant.addTimeInterval(61)
            XCTAssertNil(coordinator.approve(requestID: pending.id, simulatedVerification: true))
            XCTAssertTrue(try store.credentials().isEmpty)
            coordinator.beginMockRegistration(userName: "real", rpID: "example.com")
            XCTAssertNil(coordinator.pending)
            XCTAssertNotNil(coordinator.error)
            XCTAssertTrue(try store.credentials().isEmpty)
        }
    }

    @MainActor func testCorruptMockStoreDoesNotBecomeSuccessfulEmptyState() async throws {
        try isolated { store, directory in
            let coordinator = MockPasskeyCoordinator(store: store)
            coordinator.beginMockRegistration(userName: "test@swiftkey.mock")
            let pending = try XCTUnwrap(coordinator.pending)
            XCTAssertNotNil(coordinator.approve(requestID: pending.id, simulatedVerification: true))
            let path = directory.appendingPathComponent("software-mock-credentials-v1.json")
            try Data("broken".utf8).write(to: path)
            XCTAssertThrowsError(try store.credentials())
            let reopened = MockPasskeyCoordinator(store: store)
            XCTAssertNotNil(reopened.error)
            XCTAssertEqual(try Data(contentsOf: path), Data("broken".utf8))
        }
    }
}
