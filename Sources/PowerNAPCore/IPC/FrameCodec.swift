import Foundation

public enum FrameCodec {
    public enum Error: Swift.Error, LocalizedError {
        case frameTooLarge(UInt32)
        case shortRead
        case invalidLength
        case encodingFailed
        case decodingFailed(underlying: Swift.Error)

        public var errorDescription: String? {
            switch self {
            case .frameTooLarge(let n): return "IPC frame \(n) bytes exceeds max \(IPCProtocol.maxFrameBytes)"
            case .shortRead: return "IPC short read"
            case .invalidLength: return "IPC invalid frame length"
            case .encodingFailed: return "IPC encoding failed"
            case .decodingFailed(let err): return "IPC decoding failed: \(err)"
            }
        }
    }

    public static func encode<T: Encodable>(_ value: T, encoder: JSONEncoder = makeEncoder()) throws -> Data {
        let payload = try encoder.encode(value)
        guard UInt32(payload.count) <= IPCProtocol.maxFrameBytes else {
            throw Error.frameTooLarge(UInt32(payload.count))
        }
        var header = UInt32(payload.count).bigEndian
        var out = Data(capacity: 4 + payload.count)
        withUnsafeBytes(of: &header) { raw in
            out.append(contentsOf: raw)
        }
        out.append(payload)
        return out
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data, decoder: JSONDecoder = makeDecoder()) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw Error.decodingFailed(underlying: error)
        }
    }

    public static func makeEncoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return enc
    }

    public static func makeDecoder() -> JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let s = try? container.decode(String.self) {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let d = formatter.date(from: s) { return d }
                let formatter2 = ISO8601DateFormatter()
                formatter2.formatOptions = [.withInternetDateTime]
                if let d = formatter2.date(from: s) { return d }
                if let t = TimeInterval(s) { return Date(timeIntervalSince1970: t) }
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(s)")
            } else if let t = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: t)
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date encoding")
            }
        }
        return dec
    }

    public static func readLengthPrefixedFrame(fromFileDescriptor fd: Int32) throws -> Data {
        var header = [UInt8](repeating: 0, count: 4)
        try readFully(fd: fd, into: &header, count: 4)
        let length = (UInt32(header[0]) << 24) | (UInt32(header[1]) << 16) | (UInt32(header[2]) << 8) | UInt32(header[3])
        if length == 0 {
            return Data()
        }
        if length > IPCProtocol.maxFrameBytes {
            throw Error.frameTooLarge(length)
        }
        var buf = [UInt8](repeating: 0, count: Int(length))
        try readFully(fd: fd, into: &buf, count: Int(length))
        return Data(buf)
    }

    public static func writeLengthPrefixedFrame(toFileDescriptor fd: Int32, payload: Data) throws {
        guard UInt32(payload.count) <= IPCProtocol.maxFrameBytes else {
            throw Error.frameTooLarge(UInt32(payload.count))
        }
        var header = [UInt8](repeating: 0, count: 4)
        let length = UInt32(payload.count)
        header[0] = UInt8((length >> 24) & 0xff)
        header[1] = UInt8((length >> 16) & 0xff)
        header[2] = UInt8((length >> 8) & 0xff)
        header[3] = UInt8(length & 0xff)
        try writeFully(fd: fd, bytes: header)
        try payload.withUnsafeBytes { raw in
            let count = raw.count
            if count == 0 { return }
            let ptr = raw.bindMemory(to: UInt8.self).baseAddress!
            var offset = 0
            while offset < count {
                let n = write(fd, ptr.advanced(by: offset), count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw SysError.fromErrno()
                }
                if n == 0 { throw Error.shortRead }
                offset += n
            }
        }
    }

    private static func readFully(fd: Int32, into buf: inout [UInt8], count: Int) throws {
        var offset = 0
        while offset < count {
            let n = buf.withUnsafeMutableBufferPointer { ptr -> Int in
                let base = ptr.baseAddress!.advanced(by: offset)
                return read(fd, base, count - offset)
            }
            if n < 0 {
                if errno == EINTR { continue }
                throw SysError.fromErrno()
            }
            if n == 0 {
                throw Error.shortRead
            }
            offset += n
        }
    }

    private static func writeFully(fd: Int32, bytes: [UInt8]) throws {
        var offset = 0
        while offset < bytes.count {
            let n = bytes.withUnsafeBufferPointer { ptr -> Int in
                let base = ptr.baseAddress!.advanced(by: offset)
                return write(fd, base, bytes.count - offset)
            }
            if n < 0 {
                if errno == EINTR { continue }
                throw SysError.fromErrno()
            }
            if n == 0 { throw Error.shortRead }
            offset += n
        }
    }
}

public struct SysError: Swift.Error, LocalizedError {
    public var code: Int32
    public var message: String
    public var errorDescription: String? { "POSIX error \(code): \(message)" }
    public init(code: Int32, message: String) {
        self.code = code
        self.message = message
    }
    public static func fromErrno(_ code: Int32 = errno) -> SysError {
        let msg = String(cString: strerror(code))
        return SysError(code: code, message: msg)
    }
}
