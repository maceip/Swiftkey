import SwiftUI

struct MockHomeView: View {
    @ObservedObject var model: MockAppModel
    @State private var selection: MockCredentialItem?
    @FocusState private var nameFocused: Bool

    private enum Sheet: Identifiable {
        case credential(MockCredentialItem), approval(MockPendingRequest)
        var id: String {
            switch self {
            case .credential(let value): "credential-" + value.id
            case .approval(let value): "request-" + value.id.uuidString
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Passkeys, on your terms.")
                            .font(MockDesign.font(31, weight: .bold))
                            .accessibilityAddTraits(.isHeader)
                        Text("Try the complete flow with a local test account.")
                            .font(MockDesign.font(16)).foregroundStyle(MockDesign.muted)
                    }
                    MockCard {
                        Label("Software keys for testing", systemImage: "info.circle")
                            .font(MockDesign.font(15, weight: .semibold))
                        Text("This build simulates user verification. It does not use Secure Enclave keys or sign you in to a real service.")
                            .font(MockDesign.font(14)).foregroundStyle(MockDesign.muted)
                        if let status = model.identityIndexStatus {
                            Divider().overlay(MockDesign.line)
                            Text(status).font(MockDesign.font(12)).foregroundStyle(MockDesign.muted)
                                .accessibilityIdentifier("mock.identityIndexStatus")
                        }
                    }
                    if let error = model.startupFailure {
                        MockCard {
                            Text("Mock store unavailable").font(MockDesign.font(18, weight: .semibold))
                            Text(error).font(MockDesign.font(14)).foregroundStyle(MockDesign.danger)
                        }.accessibilityIdentifier("mock.startupError")
                    }
                    if let outcome = model.outcome {
                        MockOutcomeCard(outcome: outcome).id("mock.result")
                    }
                    MockCard {
                        Text("Create a test passkey").font(MockDesign.font(20, weight: .semibold))
                        Text("swiftkey.mock").font(MockDesign.mono()).foregroundStyle(MockDesign.muted)
                        Text("Test name").font(MockDesign.font(14, weight: .medium))
                        TextField("Your test name", text: $model.testName)
                            .font(MockDesign.font(17))
                            .textContentType(.nickname)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($nameFocused)
                            .onSubmit { nameFocused = false }
                            .padding(13)
                            .background(MockDesign.canvas, in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(MockDesign.line))
                            .accessibilityIdentifier("mock.testName")
                        Button("Create passkey") { nameFocused = false; model.requestRegistration() }
                            .buttonStyle(MockActionStyle())
                            .disabled(!model.canRegister)
                            .accessibilityIdentifier("mock.register")
                    }
                    VStack(alignment: .leading, spacing: 13) {
                        HStack {
                            Text("Saved test passkeys").font(MockDesign.font(20, weight: .semibold))
                            Spacer()
                            Text("\(model.credentials.count)").font(MockDesign.mono())
                                .accessibilityIdentifier("mock.credentialCount")
                        }
                        if model.credentials.isEmpty {
                            MockCard {
                                Image(systemName: "key.horizontal").font(.system(size: 25)).foregroundStyle(MockDesign.accent)
                                Text("No test passkeys yet").font(MockDesign.font(17, weight: .semibold))
                                Text("Create one above, then use it to verify a fresh sign-in request.")
                                    .font(MockDesign.font(14)).foregroundStyle(MockDesign.muted)
                            }.accessibilityIdentifier("mock.credentials.empty")
                        } else {
                            ForEach(model.credentials) { credential in
                                Button { selection = credential } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "key.fill").foregroundStyle(MockDesign.accent)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(credential.userName).font(MockDesign.font(17, weight: .semibold))
                                                .foregroundStyle(MockDesign.ink)
                                            Text(credential.relyingPartyID).font(MockDesign.mono())
                                                .foregroundStyle(MockDesign.muted)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(MockDesign.muted)
                                    }
                                    .padding(17)
                                    .background(MockDesign.surface, in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(MockDesign.line))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Test passkey for \(credential.userName)")
                                .accessibilityIdentifier("mock.credential.row.\(credential.id)")
                            }
                        }
                    }
                    Text("Mock responses are checked locally. Your existing SwiftKey accounts and paired phones are separate.")
                        .font(MockDesign.font(12)).foregroundStyle(MockDesign.muted)
                        .padding(.bottom, 12)
                }.padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.outcome?.title) { _, title in
                if title != nil { withAnimation { proxy.scrollTo("mock.result", anchor: .top) } }
            }
            }
            .background(MockDesign.canvas)
            .foregroundStyle(MockDesign.ink)
            .safeAreaInset(edge: .top, spacing: 0) { persistentMockBanner }
            .navigationTitle("SwiftKey")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: Binding<Sheet?>(get: {
                if let pending = model.pending { return .approval(pending) }
                return selection.map(Sheet.credential)
            }, set: { value in
                if value == nil { selection = nil; model.cancelPending() }
            })) { sheet in
                switch sheet {
                case .credential(let credential):
                    MockCredentialDetail(credential: credential, model: model, close: { selection = nil })
                case .approval(let request):
                    MockApprovalView(request: request, model: model)
                        .interactiveDismissDisabled(model.isWorking)
                }
            }
        }
    }

    private var persistentMockBanner: some View {
        MockModeBanner().padding(.horizontal, 20).padding(.vertical, 10)
            .background(MockDesign.canvas)
    }
}

private struct MockOutcomeCard: View {
    let outcome: MockOutcome
    var body: some View {
        MockCard {
            HStack {
                Image(systemName: outcome.isError ? "exclamationmark.circle" : (outcome.isCancelled ? "xmark.circle" : "checkmark.circle"))
                    .accessibilityHidden(true)
                Text(outcome.title).accessibilityIdentifier("mock.result.title")
            }.font(MockDesign.font(18, weight: .semibold))
                .foregroundStyle(outcome.isError ? MockDesign.danger : MockDesign.accent)
            Text(outcome.message).font(MockDesign.font(14)).foregroundStyle(MockDesign.muted)
                .accessibilityIdentifier("mock.result.message")
        }
    }
}

private struct MockCredentialDetail: View {
    let credential: MockCredentialItem
    @ObservedObject var model: MockAppModel
    let close: () -> Void
    @State private var confirmDeletion = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: "key.fill").font(.system(size: 38)).foregroundStyle(MockDesign.accent)
                    Text(credential.userName).font(MockDesign.font(28, weight: .bold))
                        .accessibilityIdentifier("mock.detail.name")
                    MockCard {
                        detail("Relying party", credential.relyingPartyID)
                        detail("Key storage", "Mock software key")
                        detail("Algorithm", "ES256 · P-256")
                        detail("Credential ID", credential.id)
                    }
                    Button("Sign in with this passkey") {
                        close()
                        model.requestSignIn(credential)
                    }.buttonStyle(MockActionStyle()).disabled(model.isWorking)
                        .accessibilityIdentifier("mock.detail.signIn")
                    Button("Delete test passkey", role: .destructive) { confirmDeletion = true }
                        .font(MockDesign.font(15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(MockDesign.danger)
                        .accessibilityIdentifier("mock.detail.delete")
                }.padding(20)
            }.background(MockDesign.canvas).foregroundStyle(MockDesign.ink)
                .safeAreaInset(edge: .top, spacing: 0) {
                    MockModeBanner().padding(.horizontal, 20).padding(.vertical, 10)
                        .background(MockDesign.canvas)
                }
                .navigationTitle("Test passkey").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: close).accessibilityIdentifier("mock.detail.done")
                } }
                .alert("Delete this test passkey?", isPresented: $confirmDeletion) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) { model.delete(credential); close() }
                        .accessibilityIdentifier("mock.delete.confirm")
                } message: { Text("This deletes only the local mock credential. It cannot be used for another test sign-in.") }
        }
    }
    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(MockDesign.font(12)).foregroundStyle(MockDesign.muted)
            Text(value).font(label == "Credential ID" ? MockDesign.mono() : MockDesign.font(16))
                .textSelection(.enabled)
        }
    }
}

private struct MockApprovalView: View {
    let request: MockPendingRequest
    @ObservedObject var model: MockAppModel
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: model.showVerification ? "person.crop.circle.badge.checkmark" : "hand.raised.fill")
                        .font(.system(size: 38)).foregroundStyle(MockDesign.accent)
                    Text(model.showVerification ? "Simulate user verification" : "Review this request")
                        .font(MockDesign.font(28, weight: .bold))
                        .accessibilityIdentifier("mock.approval.title")
                    Text(model.showVerification ? "No biometric check runs in mock mode. Choose the simulated result below." : "Approve only if the service and test name match what you intended.")
                        .font(MockDesign.font(16)).foregroundStyle(MockDesign.muted)
                    MockCard {
                        Text(request.kind == .registration ? "Create a test passkey" : "Sign in with a test passkey")
                            .font(MockDesign.font(19, weight: .semibold))
                        Text(request.userName).font(MockDesign.font(17))
                        Text(request.relyingPartyID).font(MockDesign.mono()).foregroundStyle(MockDesign.muted)
                        Text("Mock software key · ES256").font(MockDesign.font(12)).foregroundStyle(MockDesign.muted)
                    }
                    if model.isWorking {
                        ProgressView("Checking the mock response…")
                            .font(MockDesign.font(15)).frame(maxWidth: .infinity)
                            .accessibilityIdentifier("mock.verification.progress")
                    } else if model.showVerification {
                        Button(request.kind == .registration ? "Verify and create" : "Verify and sign in") {
                            model.completeVerification(success: true)
                        }.buttonStyle(MockActionStyle())
                            .accessibilityIdentifier("mock.verification.succeed")
                        Button("Simulate verification failure") { model.completeVerification(success: false) }
                            .buttonStyle(MockActionStyle(secondary: true))
                            .accessibilityIdentifier("mock.verification.fail")
                    } else {
                        Button("Approve request") { model.approveReview() }
                            .buttonStyle(MockActionStyle())
                            .accessibilityIdentifier("mock.approval.approve")
                    }
                    Button("Cancel request") { model.cancelPending() }
                        .font(MockDesign.font(16, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .disabled(model.isWorking)
                        .accessibilityIdentifier("mock.approval.cancel")
                }.padding(20)
            }.background(MockDesign.canvas).foregroundStyle(MockDesign.ink)
                .safeAreaInset(edge: .top, spacing: 0) {
                    MockModeBanner().padding(.horizontal, 20).padding(.vertical, 10)
                        .background(MockDesign.canvas)
                }
                .navigationTitle(request.kind == .registration ? "Create passkey" : "Test sign-in")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}
