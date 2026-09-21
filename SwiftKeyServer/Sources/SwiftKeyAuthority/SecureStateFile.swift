import Foundation
import Darwin

/// One process owns the authority directory; every successful mutation is fsynced
/// before being acknowledged. State is private to the invoking OS account.
final class SecureStateFile: @unchecked Sendable {
    let directory: URL
    private let lockFD: Int32
    init(directory: URL) throws {
        self.directory = directory.standardizedFileURL
        if mkdir(self.directory.path, 0o700) != 0 && errno != EEXIST { throw AuthorityError.rejected("Cannot create state directory") }
        var info = stat()
        try require(lstat(self.directory.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR && info.st_uid == geteuid() && (info.st_mode & 0o077) == 0, "State directory must be an owned, real directory with mode0700")
        let fd = open(self.directory.appendingPathComponent("authority.lock").path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw AuthorityError.rejected("Cannot open state lock") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); throw AuthorityError.rejected("Another authority process owns this state directory") }
        self.lockFD = fd
    }
    deinit { close(lockFD) }

    func read(_ name: String) throws -> Data? {
        let path = directory.appendingPathComponent(name).path
        let fd = open(path, O_RDONLY | O_NOFOLLOW)
        if fd < 0 && errno == ENOENT { return nil }
        guard fd >= 0 else { throw AuthorityError.rejected("Cannot read state file") }
        defer { close(fd) }
        var info = stat()
        try require(fstat(fd, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG && info.st_uid == geteuid() && (info.st_mode & 0o077) == 0, "State files must be owned regular files with mode0600")
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        return try handle.readToEnd() ?? Data()
    }

    func write(_ data: Data, name: String) throws {
        let temporary = directory.appendingPathComponent(".\(UUID().uuidString).tmp").path
        let fd = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw AuthorityError.rejected("Cannot create state transaction") }
        defer { close(fd); unlink(temporary) }
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let count = Darwin.write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw AuthorityError.rejected("Cannot write state transaction") }
                offset += count
            }
        }
        try require(fsync(fd) == 0, "Cannot flush state transaction")
        try require(rename(temporary, directory.appendingPathComponent(name).path) == 0, "Cannot commit state transaction")
        let directoryFD = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directoryFD >= 0 else { throw AuthorityError.rejected("Cannot open state directory for flush") }
        defer { close(directoryFD) }
        try require(fsync(directoryFD) == 0, "Cannot flush state directory")
    }
}
