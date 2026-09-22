import UIKit
import AuthenticationServices
import CryptoKit
import SwiftKeyPasskeys

/// A real public AuthenticationServices adapter, available only for simulator mock requests.
@MainActor public final class CredentialProviderViewController: ASCredentialProviderViewController {
    public enum MockCompletion {
        case registration(ASPasskeyRegistrationCredential)
        case assertion(ASPasskeyAssertionCredential)
        case failure(ASExtensionError.Code)
        case configuration
    }
    /// Allows the simulator test harness to exercise these exact adapter methods without an OS session.
    public var mockCompletionHandler: ((MockCompletion) -> Void)?
    public var mockStore: MockPasskeyStore = .init()
    private lazy var coordinator = MockPasskeyCoordinator(store: mockStore)
    private var finished = false
    private var verification = false
    private var approvalID: UUID?
    private let stack = UIStackView()

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        stack.axis = .vertical; stack.spacing = 18; stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48)
        ])
    }

    public override func provideCredentialWithoutUserInteraction(for credentialRequest: any ASCredentialRequest) {
        guard enabled else { return fail(.failed) }
        do { _ = try assertion(credentialRequest); fail(.userInteractionRequired) }
        catch { fail(.failed) }
    }

    public override func prepareInterfaceToProvideCredential(for credentialRequest: any ASCredentialRequest) {
        guard enabled else { return fail(.failed) }
        do { try coordinator.beginAssertion(assertion(credentialRequest)); showApproval() }
        catch { fail(.failed) }
    }

    public override func prepareInterface(forPasskeyRegistration registrationRequest: any ASCredentialRequest) {
        guard enabled else { return fail(.failed) }
        do {
            guard let request = registrationRequest as? ASPasskeyCredentialRequest,
                  let identity = request.credentialIdentity as? ASPasskeyCredentialIdentity else { throw MockCoordinatorError.invalidRequest }
            try validate(request)
            var excluded: [Data] = []
            if #available(iOS 18.0, *) {
                guard request.type == .passkeyRegistration else { throw MockCoordinatorError.invalidRequest }
                excluded = request.excludedCredentials?.map(\.credentialID) ?? []
            }
            let input = MockCreatePasskeyRequest(
                requestID: requestID(kind: "registration", rpID: identity.relyingPartyIdentifier,
                                     hash: request.clientDataHash, id: identity.userHandle),
                rpID: identity.relyingPartyIdentifier, userHandle: identity.userHandle,
                userName: identity.userName, displayName: identity.userName,
                clientDataHash: request.clientDataHash,
                algorithms: request.supportedAlgorithms.map { $0.rawValue }, excludedCredentialIDs: excluded)
            try coordinator.beginRegistration(input)
            showApproval()
        } catch { fail(.failed) }
    }

    public override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier],
                                               requestParameters: ASPasskeyCredentialRequestParameters) {
        guard enabled else { return fail(.failed) }
        do {
            let rpID = requestParameters.relyingPartyIdentifier
            let hash = requestParameters.clientDataHash
            let allowed = requestParameters.allowedCredentials
            guard hash.count == 32, allowed.count <= 128 else { throw MockCoordinatorError.invalidRequest }
            if #available(iOS 18.0, *), requestParameters.extensionInput != nil { throw MockCoordinatorError.invalidRequest }
            let records = try coordinator.matchingCredentials(rpID: rpID, allowedIDs: allowed)
            header("Choose a mock passkey", detail: "Mock mode · \(rpID)\nSoftware keys. No biometric authentication.")
            if records.isEmpty { label("No matching mock passkeys exist for this request.") }
            for record in records {
                button(record.userName) { [weak self] in
                    guard let self, !finished else { return }
                    do {
                        let input = MockSignPasskeyRequest(
                            requestID: requestID(kind: "assertion", rpID: rpID, hash: hash, id: record.id),
                            rpID: rpID, clientDataHash: hash, credentialID: record.id,
                            allowedCredentialIDs: allowed, userHandle: record.userHandle)
                        try coordinator.beginAssertion(input); showApproval()
                    } catch { fail(.failed) }
                }
            }
            button("Cancel mock request") { [weak self] in self?.cancelMockRequest() }
        } catch { fail(.failed) }
    }

    public override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) { fail(.failed) }

    public override func prepareInterfaceForExtensionConfiguration() {
        guard enabled else { return fail(.failed) }
        header("SwiftKey · Mock mode", detail: "Debug Simulator only. This provider supports swiftkey.mock and localhost with software test keys. Verification is explicitly simulated; this is not an iPhone hardware passkey implementation.")
        button("Finish mock configuration") { [weak self] in
            guard let self, !finished else { return }
            Task { @MainActor in
                do {
                    try await MockPasskeyIdentitySync.synchronize(store: mockStore)
                    guard !finished else { return }
                    finished = true
                    if let mockCompletionHandler { mockCompletionHandler(.configuration) }
                    else { extensionContext.completeExtensionConfigurationRequest() }
                } catch { fail(.failed) }
            }
        }
        button("Cancel mock configuration") { [weak self] in self?.cancelMockRequest() }
    }

    /// The test harness must explicitly request the same simulated-verification step as the UI.
    public func approveMockRequest(simulatedVerification: Bool) {
        guard enabled, !finished, let approvalID else { return fail(.failed) }
        guard let response = coordinator.approve(requestID: approvalID, simulatedVerification: simulatedVerification) else {
            return fail(.failed)
        }
        finished = true
        switch response {
        case .registration(let value):
            let credential = ASPasskeyRegistrationCredential(relyingParty: value.credential.rpID,
                clientDataHash: value.clientDataHash, credentialID: value.credential.id, attestationObject: value.attestationObject)
            if let mockCompletionHandler { mockCompletionHandler(.registration(credential)) }
            else { extensionContext.completeRegistrationRequest(using: credential, completionHandler: nil) }
        case .assertion(let value):
            let credential = ASPasskeyAssertionCredential(userHandle: value.userHandle, relyingParty: value.rpID,
                signature: value.signatureDER, clientDataHash: value.clientDataHash,
                authenticatorData: value.authenticatorData, credentialID: value.credentialID)
            if let mockCompletionHandler { mockCompletionHandler(.assertion(credential)) }
            else { extensionContext.completeAssertionRequest(using: credential, completionHandler: nil) }
        }
        if mockCompletionHandler == nil {
            Task { @MainActor in try? await MockPasskeyIdentitySync.synchronize(store: mockStore) }
        }
    }

    public func cancelMockRequest() {
        if let approvalID { coordinator.cancel(requestID: approvalID) }
        fail(.userCanceled)
    }

    private var enabled: Bool { MockPasskeyStore.isMockEnabled && !finished }
    private func assertion(_ request: any ASCredentialRequest) throws -> MockSignPasskeyRequest {
        guard request.type == .passkeyAssertion, let request = request as? ASPasskeyCredentialRequest,
              request.supportedAlgorithms.isEmpty,
              let identity = request.credentialIdentity as? ASPasskeyCredentialIdentity else { throw MockCoordinatorError.invalidRequest }
        try validate(request)
        guard let record = try coordinator.matchingCredentials(rpID: identity.relyingPartyIdentifier,
            allowedIDs: [identity.credentialID]).first,
              record.userHandle == identity.userHandle, record.userName == identity.userName,
              identity.recordIdentifier == nil || identity.recordIdentifier == record.id.mockBase64URL else { throw MockCoordinatorError.missingCredential }
        return .init(requestID: requestID(kind: "assertion", rpID: record.rpID, hash: request.clientDataHash, id: record.id),
            rpID: record.rpID, clientDataHash: request.clientDataHash, credentialID: record.id,
            allowedCredentialIDs: [record.id], userHandle: record.userHandle)
    }

    private func validate(_ request: ASPasskeyCredentialRequest) throws {
        guard request.clientDataHash.count == 32,
              let identity = request.credentialIdentity as? ASPasskeyCredentialIdentity,
              ["swiftkey.mock", "localhost"].contains(identity.relyingPartyIdentifier),
              ["required", "preferred", "discouraged"].contains(request.userVerificationPreference.rawValue) else {
            throw MockCoordinatorError.invalidRequest
        }
        if #available(iOS 18.0, *) {
            switch request.extensionInput {
            case .none: break
            default: throw MockCoordinatorError.invalidRequest
            }
        }
    }

    private func requestID(kind: String, rpID: String, hash: Data, id: Data) -> UUID {
        let bytes = Array(SHA256.hash(data: Data((kind + "\u{0}" + rpID + "\u{0}").utf8) + hash + id).prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
    private func showApproval() {
        guard let pending = coordinator.pending else { return fail(.failed) }
        approvalID = pending.id; verification = false
        header(pending.kind == .registration ? "Create mock passkey" : "Approve mock sign-in",
               detail: "Mock mode · \(pending.rpID)\nAccount: \(pending.userName)\nSoftware key. Verification will be simulated, never biometric.")
        let toggle = UISwitch(); toggle.accessibilityIdentifier = "mock.extension.simulatedVerification"
        toggle.addAction(UIAction { [weak self, weak toggle] _ in self?.verification = toggle?.isOn == true }, for: .valueChanged)
        label("Explicitly simulate user verification")
        stack.addArrangedSubview(toggle)
        button("Approve mock request") { [weak self] in
            guard let self else { return }; approveMockRequest(simulatedVerification: verification)
        }
        button("Cancel mock request") { [weak self] in self?.cancelMockRequest() }
    }
    private func header(_ title: String, detail: String) {
        loadViewIfNeeded()
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        label(title, title: true); label(detail)
    }
    private func label(_ text: String, title: Bool = false) {
        let label = UILabel(); label.text = text; label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: title ? .title2 : .body); label.adjustsFontForContentSizeCategory = true
        stack.addArrangedSubview(label)
    }
    private func button(_ title: String, action: @escaping @MainActor () -> Void) {
        let button = UIButton(type: .system); button.setTitle(title, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        stack.addArrangedSubview(button)
    }
    private func fail(_ code: ASExtensionError.Code) {
        guard !finished else { return }
        finished = true
        #if DEBUG && targetEnvironment(simulator)
        if let mockCompletionHandler { mockCompletionHandler(.failure(code)); return }
        #endif
        extensionContext.cancelRequest(withError: NSError(domain: ASExtensionErrorDomain, code: code.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Mock mode request unavailable, cancelled, or invalid. This provider does not supply production iPhone passkeys."]))
    }
}
