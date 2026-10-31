import Foundation
import Network

/// 端口转发的底层实现。
/// 本地/动态转发均用 Network 框架在本地监听,每个连接通过 libssh2 的 direct-tcpip 通道
/// (经 SSHForwardChannel 桥接)连到远端目标。
///
/// 说明:NMSSH 未提供转发能力,SSHForwardChannel 直接调用 libssh2(由 NMSSH 链接)。
/// 需确保 libssh2 头文件对桥接头可见(通常随 NMSSH pod 附带)。此部分需在真机/模拟器联调验证。

/// 转发通道的数据回调:把远端数据写回本地连接。
private final class ForwardReader {
    let local: NWConnection
    let forward: SSHForwardChannel
    private var stopped = false

    init(local: NWConnection, forward: SSHForwardChannel) {
        self.local = local
        self.forward = forward
    }

    /// 在专用线程上阻塞读取远端数据并写回本地。
    func run() {
        let thread = Thread { [weak self] in
            guard let self else { return }
            var done = false
            while !done && !stopped {
                let data = forward.readData(&done, error: nil) ?? Data()
                if !data.isEmpty {
                    local.send(content: data, completion: .contentProcessed({ _ in }))
                } else if !done {
                    usleep(10_000) // EAGAIN:短暂让出,避免空转
                }
            }
            local.cancel()
        }
        thread.start()
    }

    func stop() { stopped = true }
}

// MARK: - 本地转发 (-L)

final class LocalPortForward: PortForward {
    let localPort: UInt16
    private let rawSession: OpaquePointer
    private let targetHost: String
    private let targetPort: Int
    private var listener: NWListener?
    private var reader: ForwardReader?

    init(rawSession: OpaquePointer, bindPort: UInt16, targetHost: String, targetPort: Int) {
        self.localPort = bindPort
        self.rawSession = rawSession
        self.targetHost = targetHost
        self.targetPort = targetPort
        startListener()
    }

    private func startListener() {
        guard let listener = try? NWListener(using: .tcp,
                                            on: NWEndpoint.Port(integerLiteral: localPort)) else { return }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in self?.accept(local: conn) }
        listener.start(queue: .global(qos: .userInitiated))
    }

    private func accept(local: NWConnection) {
        local.stateUpdateHandler = { [weak self] state in
            if case .ready = state { self?.bridge(local: local) }
        }
        local.start(queue: .global(qos: .userInitiated))
    }

    private func bridge(local: NWConnection) {
        guard let forward = SSHForwardChannel(rawSession: UnsafeRawPointer(rawSession),
                                            host: targetHost, port: UInt16(targetPort)) else {
            local.cancel(); return
        }
        // 本地 → 远端
        func pump() {
            local.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                if let data = data, !data.isEmpty {
                    _ = forward.writeData(data, error: nil)
                    pump()
                } else {
                    forward.close(); local.cancel()
                }
            }
        }
        pump()
        // 远端 → 本地
        let reader = ForwardReader(local: local, forward: forward)
        self.reader = reader
        reader.run()
    }

    func stop() {
        reader?.stop()
        listener?.cancel()
    }
}

// MARK: - 动态转发 / SOCKS5 (-D)

final class DynamicPortForward: PortForward {
    let localPort: UInt16
    private let rawSession: OpaquePointer
    private var listener: NWListener?
    private var reader: ForwardReader?

    init(rawSession: OpaquePointer, bindPort: UInt16) {
        self.localPort = bindPort
        self.rawSession = rawSession
        startListener()
    }

    private func startListener() {
        guard let listener = try? NWListener(using: .tcp,
                                            on: NWEndpoint.Port(integerLiteral: localPort)) else { return }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in self?.accept(local: conn) }
        listener.start(queue: .global(qos: .userInitiated))
    }

    private func accept(local: NWConnection) {
        local.stateUpdateHandler = { [weak self] state in
            if case .ready = state { Task { await self?.socksHandshake(local) } }
        }
        local.start(queue: .global(qos: .userInitiated))
    }

    /// 最小 SOCKS5:无认证,支持 IPv4 与域名目标。
    private func socksHandshake(_ local: NWConnection) async {
        guard let methods = await read(local, length: 2), methods[0] == 5 else { local.cancel(); return }
        _ = await read(local, length: Int(methods[1]))
        local.send(content: Data([0x05, 0x00]), completion: .contentProcessed({ _ in }))

        guard let req = await read(local, length: 4), req[0] == 5, req[1] == 1 else { local.cancel(); return }
        let atyp = req[3]
        var host = ""
        var port: UInt16 = 0
        if atyp == 1 {
            guard let b = await read(local, length: 4) else { local.cancel(); return }
            host = b.map { String($0) }.joined(separator: ".")
            guard let p = await read(local, length: 2) else { local.cancel(); return }
            port = (UInt16(p[0]) << 8) | UInt16(p[1])
        } else if atyp == 3 {
            guard let lenB = await read(local, length: 1), let d = await read(local, length: Int(lenB[0])) else {
                local.cancel(); return
            }
            host = String(decoding: d, as: UTF8.self)
            guard let p = await read(local, length: 2) else { local.cancel(); return }
            port = (UInt16(p[0]) << 8) | UInt16(p[1])
        } else { local.cancel(); return }

        guard let forward = SSHForwardChannel(rawSession: UnsafeRawPointer(rawSession), host: host, port: port) else {
            local.send(content: Data([0x05, 0x01, 0x00, 0x01, 0,0,0,0, 0,0]),
                      completion: .contentProcessed({ _ in local.cancel() }))
            return
        }
        local.send(content: Data([0x05, 0x00, 0x00, 0x01, 0,0,0,0, 0,0]),
                  completion: .contentProcessed({ _ in }))

        func pump() {
            local.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                if let data = data, !data.isEmpty { _ = forward.writeData(data, error: nil); pump() }
                else { forward.close(); local.cancel() }
            }
        }
        pump()
        let reader = ForwardReader(local: local, forward: forward)
        self.reader = reader
        reader.run()
    }

    private func read(_ conn: NWConnection, length: Int) async -> Data? {
        await withCheckedContinuation { cont in
            conn.receive(minimumIncompleteLength: length, maximumLength: length) { data, _, _, _ in
                cont.resume(returning: data)
            }
        }
    }

    func stop() {
        reader?.stop()
        listener?.cancel()
    }
}
