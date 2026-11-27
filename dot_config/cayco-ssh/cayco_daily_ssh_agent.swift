import Foundation
import Darwin
import LocalAuthentication

private let unlockDurationSeconds: Int64 = 86400

private func logMsg(_ msg: String) {
    let df = ISO8601DateFormatter()
    df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let line = "[\(df.string(from: Date()))] \(msg)\n"
    if let data = line.data(using: .utf8) {
        FileHandle.standardOutput.write(data)
    }
}

private func currentBootSec() -> Int64 {
    var tv = timeval(tv_sec: 0, tv_usec: 0)
    var size = MemoryLayout<timeval>.size
    var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
    if sysctl(&mib, 2, &tv, &size, nil, 0) == 0 {
        return Int64(tv.tv_sec)
    }
    return 0
}

private struct UnlockState: Codable {
    let boot_sec: Int64
    let unlocked_until: Int64
}

private final class DailyAuthGate {
    static let shared = DailyAuthGate()

    private let lock = NSLock()
    private let statePath: String
    private let autoPoint65: Data?

    private init() {
        let home = NSHomeDirectory()
        self.statePath = home + "/.ssh/cayco/.daily_unlock_state"
        let pubPath = home + "/.ssh/cayco/cayco-studio-auto.pub"
        if let content = try? String(contentsOfFile: pubPath, encoding: .utf8) {
            let parts = content.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            if parts.count >= 2,
               let blob = Data(base64Encoded: String(parts[1])),
               blob.count >= 65 {
                self.autoPoint65 = blob.suffix(65)
            } else {
                self.autoPoint65 = nil
            }
        } else {
            self.autoPoint65 = nil
        }
    }

    func matchesAutoKey(_ signPayload: Data) -> Bool {
        guard let point = autoPoint65, signPayload.count > 70 else { return false }
        var lenBE: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &lenBE) { dst in
            signPayload.copyBytes(to: dst, from: 1..<5)
        }
        let keyBlobLen = Int(UInt32(bigEndian: lenBE))
        guard keyBlobLen > 65, 5 + keyBlobLen <= signPayload.count else { return false }
        let keyBlob = signPayload.subdata(in: 5..<(5 + keyBlobLen))
        return keyBlob.range(of: point) != nil
    }

    private func isUnlockedLocked() -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: statePath)),
              let st = try? JSONDecoder().decode(UnlockState.self, from: data) else {
            return false
        }
        let now = Int64(Date().timeIntervalSince1970)
        return st.boot_sec == currentBootSec() && now < st.unlocked_until
    }

    private func writeUnlockedLocked() {
        let now = Int64(Date().timeIntervalSince1970)
        let st = UnlockState(boot_sec: currentBootSec(), unlocked_until: now + unlockDurationSeconds)
        guard let data = try? JSONEncoder().encode(st) else { return }
        let tmpPath = statePath + ".tmp.\(getpid())"
        let fd = Darwin.open(tmpPath, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard fd >= 0 else { return }
        _ = data.withUnsafeBytes { raw in
            Darwin.write(fd, raw.baseAddress!, raw.count)
        }
        Darwin.close(fd)
        Darwin.rename(tmpPath, statePath)
        notifySketchyBar()
    }

    private func notifySketchyBar() {
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/sketchybar")
            p.arguments = ["-m", "--trigger", "secretive_update"]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
        }
    }

    /// Serializes all signing operations and enforces 1 Apple Watch / password prompt per 24h for cayco-studio-auto.
    func authorizeAndForward(packet: Data, payload: Data, forward: () -> Data?) -> Data {
        lock.lock()
        defer { lock.unlock() }

        let failurePacket = Data([0, 0, 0, 1, 5]) // SSH_AGENT_FAILURE

        if matchesAutoKey(payload) && !isUnlockedLocked() {
            logMsg("24h window expired or cold; requesting DeviceOwnerAuthentication via LAContext")
            let ctx = LAContext()
            ctx.localizedCancelTitle = "Odrzuć"
            let sem = DispatchSemaphore(value: 0)
            var ok = false
            ctx.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Odblokuj klucze SSH (Cayco Home) na 24 godziny"
            ) { success, err in
                if let err = err {
                    logMsg("LAContext auth failed/cancelled: \(err.localizedDescription)")
                }
                ok = success
                sem.signal()
            }
            sem.wait()
            guard ok else {
                return failurePacket
            }
            writeUnlockedLocked()
            logMsg("24h SSH unlock granted (valid for \(unlockDurationSeconds)s)")
        }

        return forward() ?? failurePacket
    }
}

private func readExact(_ fd: Int32, _ count: Int) -> Data? {
    var buf = Data(count: count)
    var offset = 0
    while offset < count {
        let n = buf.withUnsafeMutableBytes { raw -> Int in
            let ptr = raw.baseAddress!.advanced(by: offset)
            return Darwin.read(fd, ptr, count - offset)
        }
        if n == 0 { return nil }
        if n < 0 {
            if errno == EINTR { continue }
            return nil
        }
        offset += n
    }
    return buf
}

private func writeAll(_ fd: Int32, _ data: Data) -> Bool {
    var offset = 0
    while offset < data.count {
        let n = data.withUnsafeBytes { raw -> Int in
            let ptr = raw.baseAddress!.advanced(by: offset)
            return Darwin.write(fd, ptr, data.count - offset)
        }
        if n <= 0 {
            if n < 0 && errno == EINTR { continue }
            return false
        }
        offset += n
    }
    return true
}

private func connectUnixSocket(_ path: String) -> Int32 {
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return -1 }
    var one: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = path.utf8CString
    guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
        Darwin.close(fd)
        return -1
    }
    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dst in
            for i in 0..<pathBytes.count { dst[i] = pathBytes[i] }
        }
    }
    let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
    let rc = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
            Darwin.connect(fd, sa, addrLen)
        }
    }
    if rc != 0 {
        Darwin.close(fd)
        return -1
    }
    return fd
}

private func forwardToSecretAgent(packet: Data, upstreamPath: String) -> Data? {
    var upFd = connectUnixSocket(upstreamPath)
    if upFd < 0 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-g", "-a", "Secretive"]
        try? p.run()
        p.waitUntilExit()
        Thread.sleep(forTimeInterval: 1.0)
        upFd = connectUnixSocket(upstreamPath)
        guard upFd >= 0 else {
            logMsg("ERROR: Unable to connect to SecretAgent socket at \(upstreamPath)")
            return nil
        }
    }
    defer { Darwin.close(upFd) }

    guard writeAll(upFd, packet),
          let hdr = readExact(upFd, 4) else {
        return nil
    }
    var lenBE: UInt32 = 0
    _ = withUnsafeMutableBytes(of: &lenBE) { hdr.copyBytes(to: $0) }
    let respLen = Int(UInt32(bigEndian: lenBE))
    guard respLen > 0, respLen <= 1_048_576,
          let body = readExact(upFd, respLen) else {
        return nil
    }
    return hdr + body
}

private func handleClient(clientFd: Int32, upstreamPath: String) {
    defer { Darwin.close(clientFd) }
    var one: Int32 = 1
    setsockopt(clientFd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))

    while let hdr = readExact(clientFd, 4) {
        var lenBE: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &lenBE) { hdr.copyBytes(to: $0) }
        let msgLen = Int(UInt32(bigEndian: lenBE))
        guard msgLen > 0, msgLen <= 1_048_576,
              let payload = readExact(clientFd, msgLen) else {
            break
        }
        let packet = hdr + payload
        let msgType = payload[0]
        let response: Data
        if msgType == 13 { // SSH_AGENTC_SIGN_REQUEST
            response = DailyAuthGate.shared.authorizeAndForward(packet: packet, payload: payload) {
                forwardToSecretAgent(packet: packet, upstreamPath: upstreamPath)
            }
        } else if msgType == 11 { // SSH_AGENTC_REQUEST_IDENTITIES
            response = forwardToSecretAgent(packet: packet, upstreamPath: upstreamPath) ?? Data([0, 0, 0, 1, 5])
        } else {
            // Do not allow external add/remove/lock mutations; return standard SSH_AGENT_FAILURE
            response = Data([0, 0, 0, 1, 5])
        }
        if !writeAll(clientFd, response) {
            break
        }
    }
}

signal(SIGPIPE, SIG_IGN)
setbuf(__stdoutp, nil)

let home = NSHomeDirectory()
let dirPath = home + "/.ssh/cayco"
let sockPath = dirPath + "/daily-agent.sock"
let upstreamPath = home + "/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh"

try? FileManager.default.createDirectory(
    atPath: dirPath,
    withIntermediateDirectories: true,
    attributes: [.posixPermissions: 0o700]
)
Darwin.unlink(sockPath)

let serverFd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
guard serverFd >= 0 else {
    logMsg("FATAL: socket() failed")
    exit(1)
}

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
let pathBytes = sockPath.utf8CString
withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
    ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dst in
        for i in 0..<pathBytes.count { dst[i] = pathBytes[i] }
    }
}

let oldMask = Darwin.umask(0o177)
let bindRc = withUnsafePointer(to: &addr) { ptr in
    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
        Darwin.bind(serverFd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
Darwin.umask(oldMask)
guard bindRc == 0 else {
    logMsg("FATAL: bind(\(sockPath)) failed errno=\(errno)")
    exit(1)
}
Darwin.chmod(sockPath, 0o600)
guard Darwin.listen(serverFd, 64) == 0 else {
    logMsg("FATAL: listen() failed errno=\(errno)")
    exit(1)
}

logMsg("cayco-daily-ssh-agent listening on \(sockPath) -> \(upstreamPath)")

while true {
    let clientFd = Darwin.accept(serverFd, nil, nil)
    if clientFd < 0 {
        if errno == EINTR { continue }
        Thread.sleep(forTimeInterval: 0.05)
        continue
    }
    DispatchQueue.global(qos: .userInitiated).async {
        handleClient(clientFd: clientFd, upstreamPath: upstreamPath)
    }
}
