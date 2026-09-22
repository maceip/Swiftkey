import XCTest
import Foundation
import AuthenticationServices
import CryptoKit
import SwiftKeyPasskeys

final class MockProviderAdapterTests: XCTestCase {
    @MainActor private func isolated(_ body: (MockPasskeyStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MockProviderTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(MockPasskeyStore(directoryURL: directory))
    }

    @MainActor private func request(rpID: String = "swiftkey.mock", credentialID: Data = Data(),
                                    userHandle: Data = Data([1, 2, 3]), hash: Data = Data(repeating: 7, count: 32),
                                    registration: Bool = true) -> ASPasskeyCredentialRequest {
        let identity = ASPasskeyCredentialIdentity(relyingPartyIdentifier: rpID, userName: "mock-user",
            credentialID: credentialID, userHandle: userHandle,
            recordIdentifier: credentialID.isEmpty ? nil : credentialID.mockBase64URL)
        if #available(iOS 18.0, *), registration {
            // The original iOS17 initializer always constructs assertion type. The
            // registration-extension overload marks the actual registration ceremony.
            return ASPasskeyCredentialRequest(credentialIdentity: identity, clientDataHash: hash,
                userVerificationPreference: .required, supportedAlgorithms: [ASCOSEAlgorithmIdentifier(rawValue: -7)],
                extensionInput: nil as ASPasskeyRegistrationCredentialExtensionInput?)
        }
        return ASPasskeyCredentialRequest(credentialIdentity: identity, clientDataHash: hash,
            userVerificationPreference: .required,
            supportedAlgorithms: registration ? [ASCOSEAlgorithmIdentifier(rawValue: -7)] : [])
    }

    @MainActor private func seed(_ store: MockPasskeyStore) throws -> MockPasskeyCredential {
        try store.transaction { engine in
            let input = MockCreatePasskeyRequest(rpID: "swiftkey.mock", userHandle: Data([1, 2, 3]),
                userName: "mock-user", displayName: "mock-user", clientDataHash: Data(repeating: 9, count: 32))
            let approval = try engine.approve(.create(input))
            return try engine.create(input, approval: approval).credential
        }
    }

    @MainActor func testRegistrationAdapterReturnsExactOSHashAndPersistentCredentialOnlyAfterSimulation() async throws {
        try isolated { store in
            let controller = CredentialProviderViewController()
            controller.mockStore = store
            var completions: [CredentialProviderViewController.MockCompletion] = []
            controller.mockCompletionHandler = { completions.append($0) }
            let input = request()
            controller.prepareInterface(forPasskeyRegistration: input)
            XCTAssertTrue(completions.isEmpty)
            XCTAssertTrue(try store.credentials().isEmpty)
            controller.approveMockRequest(simulatedVerification: true)
            guard case .registration(let response)? = completions.first else {
                XCTFail("Adapter did not return a mock registration"); return
            }
            let record = try XCTUnwrap(store.credentials().first)
            XCTAssertEqual(response.relyingParty, "swiftkey.mock")
            XCTAssertEqual(response.clientDataHash, input.clientDataHash)
            XCTAssertEqual(response.credentialID, record.id)
            XCTAssertFalse(response.attestationObject.isEmpty)
            controller.approveMockRequest(simulatedVerification: true)
            XCTAssertEqual(completions.count, 1)
            XCTAssertEqual(try store.credentials().count, 1)

            // A new adapter process/session cannot replay the same original OS request.
            let replay = CredentialProviderViewController(); replay.mockStore = store
            var replayCode: ASExtensionError.Code?
            replay.mockCompletionHandler = { if case .failure(let code) = $0 { replayCode = code } }
            replay.prepareInterface(forPasskeyRegistration: input)
            replay.approveMockRequest(simulatedVerification: true)
            XCTAssertEqual(replayCode, .failed)
            XCTAssertEqual(try store.credentials().count, 1)
        }
    }

    @MainActor func testAssertionAdapterSignsExactOSHashWithSelectedMockKey() async throws {
        try isolated { store in
            let saved = try seed(store)
            let hash = Data(repeating: 21, count: 32)
            let controller = CredentialProviderViewController(); controller.mockStore = store
            var response: ASPasskeyAssertionCredential?
            controller.mockCompletionHandler = { if case .assertion(let value) = $0 { response = value } }
            controller.prepareInterfaceToProvideCredential(for: request(credentialID: saved.id, hash: hash, registration: false))
            XCTAssertNil(response)
            controller.approveMockRequest(simulatedVerification: true)
            let value = try XCTUnwrap(response)
            XCTAssertEqual(value.clientDataHash, hash)
            XCTAssertEqual(value.credentialID, saved.id)
            XCTAssertEqual(value.userHandle, saved.userHandle)
            XCTAssertEqual(value.relyingParty, saved.rpID)
            let key = try P256.Signing.PublicKey(x963Representation: saved.publicKeyX963)
            let signature = try P256.Signing.ECDSASignature(derRepresentation: value.signature)
            XCTAssertTrue(key.isValidSignature(signature, for: value.authenticatorData + hash))
            XCTAssertFalse(key.isValidSignature(signature, for: value.authenticatorData + Data(repeating: 22, count: 32)))
        }
    }

    @MainActor func testSilentAssertionRequiresInteractionAndDoesNotReturnCredential() async throws {
        try isolated { store in
            let saved = try seed(store)
            let controller = CredentialProviderViewController(); controller.mockStore = store
            var code: ASExtensionError.Code?
            var returnedCredential = false
            controller.mockCompletionHandler = {
                switch $0 {
                case .failure(let failure): code = failure
                default: returnedCredential = true
                }
            }
            controller.provideCredentialWithoutUserInteraction(for: request(credentialID: saved.id, registration: false))
            XCTAssertEqual(code, .userInteractionRequired)
            XCTAssertFalse(returnedCredential)
        }
    }

    @MainActor func testCancelAndFailedSimulationLeaveNoCredential() async throws {
        try isolated { store in
            for cancel in [true, false] {
                let controller = CredentialProviderViewController(); controller.mockStore = store
                var code: ASExtensionError.Code?
                controller.mockCompletionHandler = { if case .failure(let value) = $0 { code = value } }
                controller.prepareInterface(forPasskeyRegistration: request())
                if cancel { controller.cancelMockRequest() }
                else { controller.approveMockRequest(simulatedVerification: false) }
                XCTAssertEqual(code, cancel ? .userCanceled : .failed)
                controller.approveMockRequest(simulatedVerification: true)
                XCTAssertTrue(try store.credentials().isEmpty)
            }
        }
    }

    @MainActor func testRealRPAndWrongIdentityFailBeforeReturningAnyCredential() async throws {
        try isolated { store in
            let saved = try seed(store)
            let inputs = [
                request(rpID: "example.com"),
                request(credentialID: saved.id, userHandle: Data([99]), registration: false),
                request(credentialID: Data(repeating: 0, count: 32), registration: false),
                request(credentialID: saved.id, hash: Data(repeating: 0, count: 31), registration: false)
            ]
            for (index, input) in inputs.enumerated() {
                let controller = CredentialProviderViewController(); controller.mockStore = store
                var code: ASExtensionError.Code?
                var success = false
                controller.mockCompletionHandler = {
                    if case .failure(let value) = $0 { code = value } else { success = true }
                }
                if index == 0 { controller.prepareInterface(forPasskeyRegistration: input) }
                else { controller.prepareInterfaceToProvideCredential(for: input) }
                controller.approveMockRequest(simulatedVerification: true)
                XCTAssertEqual(code, .failed)
                XCTAssertFalse(success)
            }
            XCTAssertEqual(try store.credentials().map(\.id), [saved.id])
        }
    }
}
