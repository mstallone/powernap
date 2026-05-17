import Foundation
import Darwin
import Logging
import PowerNAPCore

public final class PTYSession {
    public struct SpawnOptions {
        public var executable: String
        public var arguments: [String]
        public var environment: [String: String]
        public var cwd: String?

        public init(executable: String, arguments: [String] = [], environment: [String: String] = ProcessInfo.processInfo.environment, cwd: String? = nil) {
            self.executable = executable
            self.arguments = arguments
            self.environment = environment
            self.cwd = cwd
        }
    }

    public private(set) var pid: pid_t = -1
    public private(set) var masterFD: Int32 = -1
    public private(set) var isRunning: Bool = false
    public private(set) var exitStatus: Int32?

    private let logger: Logger
    private var originalTermios: termios?
    private let attrLock = NSLock()

    public init(logger: Logger? = nil) {
        self.logger = logger ?? Logger(label: "dev.powernap.process.pty")
    }

    public func spawn(_ options: SpawnOptions) throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        var winSize = winsize(ws_row: 40, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
        var term = termios()
        cfmakeraw(&term)
        term.c_cflag |= tcflag_t(CS8)
        #if canImport(Darwin)
        term.c_iflag |= tcflag_t(IUTF8)
        #endif

        let rc = withUnsafeMutablePointer(to: &winSize) { wsPtr -> Int32 in
            withUnsafeMutablePointer(to: &term) { termPtr in
                openpty(&master, &slave, nil, termPtr, wsPtr)
            }
        }
        if rc < 0 { throw SysError.fromErrno() }

        var fileActions = posix_spawn_file_actions_t(bitPattern: 0)
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        posix_spawn_file_actions_adddup2(&fileActions, slave, 0)
        posix_spawn_file_actions_adddup2(&fileActions, slave, 1)
        posix_spawn_file_actions_adddup2(&fileActions, slave, 2)
        posix_spawn_file_actions_addclose(&fileActions, master)
        posix_spawn_file_actions_addclose(&fileActions, slave)
        if let cwd = options.cwd {
            _ = cwd.withCString { cstr -> Int32 in
                posix_spawn_file_actions_addchdir_np(&fileActions, cstr)
            }
        }

        var attrs = posix_spawnattr_t(bitPattern: 0)
        posix_spawnattr_init(&attrs)
        defer { posix_spawnattr_destroy(&attrs) }
        var flags: Int16 = 0
        flags |= Int16(POSIX_SPAWN_SETSID)
        posix_spawnattr_setflags(&attrs, flags)

        let argvCStrings = ([options.executable] + options.arguments).map { strdup($0) }
        defer { for p in argvCStrings { free(p) } }
        var argv: [UnsafeMutablePointer<CChar>?] = argvCStrings.map { $0 }
        argv.append(nil)

        let envStrings: [String] = options.environment.map { "\($0.key)=\($0.value)" }
        let envCStrings: [UnsafeMutablePointer<CChar>?] = envStrings.map { strdup($0) }
        defer { for p in envCStrings { if let p { free(p) } } }
        var envp: [UnsafeMutablePointer<CChar>?] = envCStrings
        envp.append(nil)

        var newPID: pid_t = 0
        let spawnRC = options.executable.withCString { exePath -> Int32 in
            argv.withUnsafeMutableBufferPointer { argvBuf in
                envp.withUnsafeMutableBufferPointer { envpBuf in
                    posix_spawn(&newPID, exePath, &fileActions, &attrs, argvBuf.baseAddress, envpBuf.baseAddress)
                }
            }
        }
        if spawnRC != 0 {
            Darwin.close(master)
            Darwin.close(slave)
            throw SysError(code: spawnRC, message: String(cString: strerror(spawnRC)))
        }
        Darwin.close(slave)
        self.pid = newPID
        self.masterFD = master
        self.isRunning = true
        logger.debug("spawned agent", metadata: ["pid": "\(newPID)", "exe": "\(options.executable)"])
    }

    public func makeStdinRaw() throws {
        let fd: Int32 = 0
        guard isatty(fd) != 0 else { return }
        var orig = termios()
        if tcgetattr(fd, &orig) < 0 { throw SysError.fromErrno() }
        attrLock.lock()
        originalTermios = orig
        attrLock.unlock()
        var raw = orig
        cfmakeraw(&raw)
        withUnsafeMutablePointer(to: &raw.c_cc) { tuplePtr in
            tuplePtr.withMemoryRebound(to: cc_t.self, capacity: Int(NCCS)) { ccs in
                ccs[Int(VMIN)] = 1
                ccs[Int(VTIME)] = 0
            }
        }
        if tcsetattr(fd, TCSANOW, &raw) < 0 { throw SysError.fromErrno() }
    }

    public func restoreStdin() {
        attrLock.lock()
        let saved = originalTermios
        attrLock.unlock()
        guard var orig = saved else { return }
        let fd: Int32 = 0
        _ = tcsetattr(fd, TCSANOW, &orig)
    }

    public func updateWindowSize(cols: UInt16, rows: UInt16) {
        var ws = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFD, UInt(TIOCSWINSZ), &ws)
    }

    public func forwardCurrentWindowSize() {
        var ws = winsize()
        if ioctl(0, UInt(TIOCGWINSZ), &ws) == 0 {
            _ = ioctl(masterFD, UInt(TIOCSWINSZ), &ws)
        }
    }

    public func sendSignal(_ sig: Int32) {
        if pid > 0 { kill(pid, sig) }
    }

    public func close() {
        if masterFD >= 0 {
            Darwin.close(masterFD)
            masterFD = -1
        }
        restoreStdin()
    }

    public func wait() -> Int32 {
        var status: Int32 = 0
        while true {
            let rc = waitpid(pid, &status, 0)
            if rc == -1 {
                if errno == EINTR { continue }
                return -1
            }
            break
        }
        isRunning = false
        if (status & 0x7f) == 0 {
            exitStatus = (status >> 8) & 0xff
        } else {
            exitStatus = 128 + (status & 0x7f)
        }
        return exitStatus ?? -1
    }

    public func tryReap() -> Int32? {
        var status: Int32 = 0
        let rc = waitpid(pid, &status, WNOHANG)
        if rc == 0 { return nil }
        if rc < 0 { return nil }
        isRunning = false
        if (status & 0x7f) == 0 {
            exitStatus = (status >> 8) & 0xff
        } else {
            exitStatus = 128 + (status & 0x7f)
        }
        return exitStatus
    }
}

public final class PTYRelay {
    private let pty: PTYSession
    private let logger: Logger
    private var running: Bool = false
    private let stdinQueue = DispatchQueue(label: "dev.powernap.pty.stdin", qos: .userInteractive)
    private let stdoutQueue = DispatchQueue(label: "dev.powernap.pty.stdout", qos: .userInteractive)
    private let stdoutGroup = DispatchGroup()
    private let outputLock = NSLock()
    private var lastOutputByte: UInt8?
    private var signalSources: [DispatchSourceSignal] = []

    public init(pty: PTYSession, logger: Logger? = nil) {
        self.pty = pty
        self.logger = logger ?? Logger(label: "dev.powernap.pty.relay")
    }

    public func start() {
        running = true
        let master = pty.masterFD
        stdinQueue.async { [weak self] in
            guard let self else { return }
            PTYRelay.pump(from: 0, to: master, running: { self.running })
        }
        let stdoutGroup = self.stdoutGroup
        stdoutGroup.enter()
        stdoutQueue.async { [weak self] in
            defer { stdoutGroup.leave() }
            guard let self else { return }
            PTYRelay.pump(from: master, to: 1, running: { true }) { byte in
                self.recordLastOutputByte(byte)
            }
        }
        setupSignalHandlers()
    }

    public func stop() {
        running = false
        for s in signalSources { s.cancel() }
        signalSources.removeAll()
    }

    public func waitForOutputDrain(timeoutSeconds: TimeInterval) -> Bool {
        stdoutGroup.wait(timeout: .now() + timeoutSeconds) == .success
    }

    public var outputNeedsTrailingNewline: Bool {
        outputLock.lock()
        defer { outputLock.unlock() }
        guard let lastOutputByte else { return false }
        return lastOutputByte != UInt8(ascii: "\n") && lastOutputByte != UInt8(ascii: "\r")
    }

    private func recordLastOutputByte(_ byte: UInt8) {
        outputLock.lock()
        lastOutputByte = byte
        outputLock.unlock()
    }

    private static func pump(
        from src: Int32,
        to dst: Int32,
        running: @escaping () -> Bool,
        lastByteObserver: ((UInt8) -> Void)? = nil
    ) {
        let bufSize = 4096
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate() }
        while running() {
            let n = read(src, buf, bufSize)
            if n <= 0 {
                if n < 0 && errno == EINTR { continue }
                break
            }
            var offset = 0
            while offset < n {
                let written = write(dst, buf.advanced(by: offset), n - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    break
                }
                if written == 0 { break }
                let writtenCount = Int(written)
                lastByteObserver?(buf[offset + writtenCount - 1])
                offset += writtenCount
            }
        }
    }

    private func setupSignalHandlers() {
        let signals: [Int32] = [SIGWINCH, SIGINT, SIGTERM, SIGQUIT, SIGHUP]
        for sig in signals {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .global(qos: .userInteractive))
            src.setEventHandler { [weak self] in
                self?.handleSignal(sig)
            }
            src.resume()
            signalSources.append(src)
        }
    }

    private func handleSignal(_ sig: Int32) {
        if sig == SIGWINCH {
            pty.forwardCurrentWindowSize()
        } else {
            pty.sendSignal(sig)
        }
    }
}
