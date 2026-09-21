import Foundation
import Testing
@testable import SwiftKeyHTTP

@Test func privateTokenFileRejectsPublicPermissionsAndSymbolicLinks() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("admin-token")
    let token = String(repeating: "test-only-token-", count: 4)
    try Data((token + "\n").utf8).write(to: path)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    #expect(try PrivateTokenFile.read(path.path) == token)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path.path)
    #expect(throws: PrivateTokenFileError.insecurePermissions) { try PrivateTokenFile.read(path.path) }
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    let link = directory.appendingPathComponent("token-link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: path)
    #expect(throws: PrivateTokenFileError.unreadable) { try PrivateTokenFile.read(link.path) }
}

@Test(arguments: ["too-short", String(repeating: "x", count: 4097), String(repeating: "x", count: 32) + "\nembedded-line"])
func privateTokenFileRejectsInvalidContents(_ contents: String) throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-invalid-token-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: path) }
    try Data(contents.utf8).write(to: path)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    #expect(throws: PrivateTokenFileError.invalidToken) { try PrivateTokenFile.read(path.path) }
}
