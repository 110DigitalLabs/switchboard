import Darwin
import Foundation

/// Listens on a Unix socket for hook helper messages. Each connection carries
/// one message and ends at EOF. Connections are accepted and read one at a
/// time on a private serial queue, so messages are delivered in the order the
/// helper sent them, and the main thread never blocks the helper.
final class HookSocketServer: @unchecked Sendable {
    private static let maxMessageSize = 8 << 20

    let path: String
    private let queue = DispatchQueue(label: "Switchboard.HookSocketServer")
    private let onMessage: @Sendable (Data) -> Void
    // Touched only on `queue` after start().
    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?

    init(path: String, onMessage: @escaping @Sendable (Data) -> Void) {
        self.path = path
        self.onMessage = onMessage
    }

    deinit {
        source?.cancel()
    }

    func start() throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError.current }
        unlink(path) // a stale socket from a previous run
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else {
            close(fd)
            throw POSIXError(.ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: path.utf8)
            buffer[path.utf8.count] = 0
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 64) == 0 else {
            let error = POSIXError.current
            close(fd)
            throw error
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending() }
        source.setCancelHandler { close(fd) }
        queue.sync {
            listenFD = fd
            self.source = source
        }
        source.resume()
    }

    private func acceptPending() {
        while true {
            let client = accept(listenFD, nil, nil)
            guard client >= 0 else { return }
            if let data = readAll(client) { onMessage(data) }
            close(client)
        }
    }

    private func readAll(_ fd: Int32) -> Data? {
        // The accepted socket inherits O_NONBLOCK; reads should wait briefly.
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while data.count < Self.maxMessageSize {
            let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if count > 0 {
                data.append(contentsOf: buffer[0..<count])
            } else if count == 0 {
                return data
            } else if errno == EINTR {
                continue
            } else {
                return nil
            }
        }
        return nil
    }
}

private extension POSIXError {
    static var current: POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
}
