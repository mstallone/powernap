import Foundation

public enum UnixSocketClient {
    public enum ClientError: Swift.Error, LocalizedError {
        case socketCreationFailed(Int32)
        case connectFailed(String, Int32)
        case pathTooLong(String)
        case timedOut
        case daemonNotRunning(String)

        public var errorDescription: String? {
            switch self {
            case .socketCreationFailed(let c):
                return "Failed to create Unix socket (errno \(c))."
            case .connectFailed(let p, let c):
                return "Failed to connect to \(p): \(String(cString: strerror(c))) (errno \(c))."
            case .pathTooLong(let p):
                return "Socket path too long: \(p)"
            case .timedOut:
                return "IPC timed out."
            case .daemonNotRunning(let p):
                return "PowerNAP daemon not running at \(p). Try: powernap install"
            }
        }
    }

    public static func sendRequest(
        _ request: IPCRequest,
        socketPath: String = ConfigPaths.socketPath,
        timeoutSeconds: Double = 2.0
    ) throws -> IPCResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 { throw ClientError.socketCreationFailed(errno) }
        defer { close(fd) }

        try setTimeout(fd: fd, seconds: timeoutSeconds)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        if pathBytes.count >= maxLen { throw ClientError.pathTooLong(socketPath) }

        withUnsafeMutablePointer(to: &addr.sun_path) { tuplePtr in
            tuplePtr.withMemoryRebound(to: CChar.self, capacity: maxLen) { cptr in
                for i in 0..<pathBytes.count {
                    cptr[i] = CChar(bitPattern: pathBytes[i])
                }
                cptr[pathBytes.count] = 0
            }
        }

        let addrSize = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connectResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                connect(fd, saPtr, addrSize)
            }
        }
        if connectResult < 0 {
            let savedErrno = errno
            if savedErrno == ENOENT || savedErrno == ECONNREFUSED {
                throw ClientError.daemonNotRunning(socketPath)
            }
            throw ClientError.connectFailed(socketPath, savedErrno)
        }

        let reqData = try FrameCodec.encode(request)
        try FrameCodec.writeLengthPrefixedFrame(toFileDescriptor: fd, payload: reqData.subdata(in: 4..<reqData.count))

        let respData = try FrameCodec.readLengthPrefixedFrame(fromFileDescriptor: fd)
        return try FrameCodec.decode(IPCResponse.self, from: respData)
    }

    private static func setTimeout(fd: Int32, seconds: Double) throws {
        var tv = timeval(tv_sec: Int(seconds), tv_usec: Int32((seconds - Double(Int(seconds))) * 1_000_000))
        let sz = socklen_t(MemoryLayout<timeval>.size)
        if setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sz) < 0 {
            throw ClientError.socketCreationFailed(errno)
        }
        if setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sz) < 0 {
            throw ClientError.socketCreationFailed(errno)
        }
    }
}
