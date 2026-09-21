import Foundation
import SwiftKeyCore
import Darwin

/// The development USB adapter. Parsing, expiry/pin checks and configuration
/// construction are Swift; adb only transfers bytes into the app's private UID.
@main struct SwiftKeyOperator {
    static func main() async {
        do { try await run() }
        catch {
            FileHandle.standardError.write(Data("SwiftKey: \(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
        init(_ message: String) { self.message = message }
    }

    static func run() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        func option(_ flag: String) throws -> String {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else {
                throw Failure("Missing \(flag).")
            }
            return arguments[i + 1]
        }
        guard arguments.first == "provision-android" else {
            print("swiftkey-operator provision-android --bundle-file /private/enrollment.json --pin-file .state/server-public-key.txt --serial DEVICE")
            return
        }
        let bundlePath = try option("--bundle-file")
        let pinPath = try option("--pin-file")
        let serial = try option("--serial")
        guard !serial.isEmpty, serial.utf8.count <= 128,
              serial.allSatisfy({ $0.isLetter || $0.isNumber || "-_.:".contains($0) }) else {
            throw Failure("Invalid device serial.")
        }
        let bundleBytes = try Data(contentsOf: URL(fileURLWithPath: bundlePath))
        guard bundleBytes.count <= 16_384 else { throw Failure("Enrollment bundle is too large.") }
        let bundle = try JSONDecoder().decode(EnrollmentBundle.self, from: bundleBytes)
        let now = UInt64(Date().timeIntervalSince1970)
        guard bundle.version == 1, now < bundle.expiresAt,
              UUID(uuidString: bundle.accountID) != nil else {
            throw Failure("Enrollment bundle is expired or unsupported. Issue a new invitation from the website.")
        }
        let configuration = bundle.configuration
        guard configuration.expectedAccountID == bundle.accountID else {
            throw Failure("Enrollment configuration is not bound to the account in this bundle.")
        }
        let expectedPin = try String(contentsOfFile: pinPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard Data(base64Encoded: expectedPin) == configuration.serverPublicKey else {
            throw Failure("Enrollment bundle does not match the separately supplied authority pin.")
        }
        try ProtocolCrypto.validatePublicKey(configuration.serverPublicKey)
        guard let url = URLComponents(string: configuration.serverURL), url.scheme == "http",
              url.host == "127.0.0.1", let port = url.port, (1024...65535).contains(port),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else {
            throw Failure("This USB provisioning adapter requires an explicit loopback HTTP port.")
        }
        guard configuration.bootstrapToken.utf8.count >= 32,
              configuration.bootstrapToken.utf8.count <= 4096,
              configuration.bootstrapToken.utf8.allSatisfy({ (0x21...0x7e).contains($0) }),
              !configuration.audience.isEmpty else { throw Failure("Invalid enrollment configuration.") }
        let prefix = ["-s", serial]
        guard try adb(prefix + ["get-state"]).trimmingCharacters(in: .whitespacesAndNewlines) == "device" else {
            throw Failure("The Android device is not authorized.")
        }
        let package = "com.pureswift.swiftandroidui"
        // Confirm the installed debug app's UID before creating its private
        // directory. A fresh installation need not have launched or filesDir yet.
        let uidText = try adb(prefix + ["shell", "run-as", package, "id", "-u"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uid = UInt(uidText), uid >= 10_000 else {
            throw Failure("Could not verify the installed Android app's private UID.")
        }
        _ = try adb(prefix + ["shell", "run-as", package, "mkdir", "-p", "files"])
        let existing = try adb(prefix + ["shell", "run-as", package, "ls", "files"])
        guard !existing.split(whereSeparator: \.isWhitespace).contains("swiftkey-protocol-state.json") else {
            throw Failure("This installation already has protocol state. Refusing to replace its enrollment or hardware identity.")
        }
        // A failed enrollment may already have created an attested key. Do not
        // overwrite its configuration with a challenge for a different identity.
        guard !existing.split(whereSeparator: \.isWhitespace).contains("swiftkey-client.json") else {
            throw Failure("This installation is already configured. Resume it using its existing invitation instead of replacing configuration.")
        }
        _ = try adb(prefix + ["reverse", "tcp:\(port)", "tcp:\(port)"])
        let data = try JSONEncoder().encode(configuration)
        _ = try adb(prefix + ["shell", "run-as", package, "sh", "-c",
            "'umask 077; mkdir -p files; cat > files/swiftkey-client.json.new && chmod 600 files/swiftkey-client.json.new && mv files/swiftkey-client.json.new files/swiftkey-client.json'"], input: data)
        print("Provisioned account \(bundle.accountID) on Android \(serial). The invitation and configuration were not printed.")
        _ = try adb(prefix + ["shell", "am", "force-stop", package])
        _ = try adb(prefix + ["shell", "am", "start", "-W", "-n", package + "/com.pureswift.swiftandroid.MainActivity"])
        print("Started hardware enrollment and credential issuance. Check the website after refreshing; process launch alone is not enrollment proof.")
    }

    static func adb(_ arguments: [String], input: Data? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["adb"] + arguments
        let output = Pipe(), errors = Pipe(), stdin = Pipe()
        process.standardOutput = output; process.standardError = errors; process.standardInput = stdin
        try process.run()
        if let input { try stdin.fileHandleForWriting.write(contentsOf: input) }
        try stdin.fileHandleForWriting.close()
        let result = output.fileHandleForReading.readDataToEndOfFile()
        let error = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            // adb diagnostics contain no bundle contents; never echo stdin.
            throw Failure("Android transfer failed: " + (String(data: error, encoding: .utf8) ?? "adb error"))
        }
        return String(data: result, encoding: .utf8) ?? ""
    }
}
