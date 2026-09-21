import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum PrivateTokenFileError: Error, Equatable {
    case unreadable
    case insecurePermissions
    case invalidToken
}

/// Opens the verified descriptor itself, refusing symbolic links and bounding
/// the read. Error values never contain a path, token, or file contents.
public enum PrivateTokenFile {
    public static func read(_ path: String) throws -> String {
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { throw PrivateTokenFileError.unreadable }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? file.close() }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else { throw PrivateTokenFileError.unreadable }
        guard metadata.st_mode & S_IFMT == S_IFREG, metadata.st_uid == geteuid(),
              metadata.st_mode & 0o7777 == 0o600 else { throw PrivateTokenFileError.insecurePermissions }
        guard metadata.st_size >= 32, metadata.st_size <= 4096,
              let data = try file.read(upToCount: 4097), data.count <= 4096,
              let contents = String(data: data, encoding: .utf8) else { throw PrivateTokenFileError.invalidToken }
        let token = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.utf8.count >= 32, token.utf8.allSatisfy({ 0x21...0x7e ~= $0 }) else {
            throw PrivateTokenFileError.invalidToken
        }
        return token
    }
}
