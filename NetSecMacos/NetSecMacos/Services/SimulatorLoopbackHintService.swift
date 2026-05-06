import Foundation
import Network
import os

/// Local-only HTTP listener so the Web Attack Simulator can POST a host hint without `camguard://`
/// (no Safari “open app?” prompt). Binds to loopback peers only.
final class SimulatorLoopbackHintService {
    private let logger = Logger(subsystem: "CamGuardMac", category: "SimulatorLoopback")
    private let queue = DispatchQueue(label: "com.camguard.simulator-loopback", qos: .userInitiated)
    private var listener: NWListener?
    private var onHostHint: ((String) -> Void)?
    /// True when the listener is in `.ready` (port bound). Avoids `stop()`+immediate rebind → POSIX 48.
    private var isReady = false
    /// Invalidates in-flight scheduled binds when `stop()` runs.
    private var bindSessionID = 0
    /// After `stop()`, wait briefly before binding so the kernel can release the port (POSIX 48).
    private var lastStopAt: Date?
    private var didRetryBindAfterFailure = false

    static let port: UInt16 = 39_452
    static let hintPath = "/camguard/v1/hint"
    private static let maxHeaderBytes = 24_576
    private static let maxBodyBytes = 8_192

    func start(handler: @escaping (String) -> Void) {
        onHostHint = handler
        queue.async { [weak self] in
            self?.startListenerIfNeeded()
        }
    }

    /// Starts the TCP listener once; repeated `startMonitoring()` calls only refresh the callback.
    private func startListenerIfNeeded() {
        if isReady {
            return
        }
        if listener != nil {
            return
        }

        let delay: TimeInterval
        if let t = lastStopAt, Date().timeIntervalSince(t) < 2.0 {
            delay = 0.35
        } else {
            delay = 0
        }

        bindSessionID &+= 1
        let session = bindSessionID
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            guard session == self.bindSessionID else { return }
            guard !self.isReady, self.listener == nil else { return }
            self.openListener()
        }
    }

    private func openListener() {
        guard let nwPort = NWEndpoint.Port(rawValue: Self.port) else {
            logger.error("Invalid simulator port")
            return
        }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        do {
            let newListener = try NWListener(using: params, on: nwPort)
            listener = newListener

            newListener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isReady = true
                    self.lastStopAt = nil
                    self.didRetryBindAfterFailure = false
                    self.logger.info(
                        "Simulator loopback listening on 127.0.0.1:\(Self.port) \(Self.hintPath, privacy: .public)"
                    )
                case let .failed(error):
                    self.isReady = false
                    self.listener = nil
                    self.logger.error(
                        "Simulator loopback failed: \(String(describing: error), privacy: .public)"
                    )
                    self.scheduleOneBindRetryIfNeeded()
                case .cancelled:
                    self.isReady = false
                    self.listener = nil
                default:
                    break
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }

            newListener.start(queue: queue)
        } catch {
            logger.error("Could not create simulator listener: \(error.localizedDescription, privacy: .public)")
            isReady = false
            listener = nil
            scheduleOneBindRetryIfNeeded()
        }
    }

    /// Single delayed retry after a bind failure (e.g. POSIX 48) so we do not loop forever.
    private func scheduleOneBindRetryIfNeeded() {
        guard !isReady, listener == nil, onHostHint != nil, !didRetryBindAfterFailure else { return }
        didRetryBindAfterFailure = true
        bindSessionID &+= 1
        let session = bindSessionID
        queue.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            guard let self else { return }
            guard session == self.bindSessionID else { return }
            guard !self.isReady, self.listener == nil, self.onHostHint != nil else { return }
            self.openListener()
        }
    }

    func stop() {
        bindSessionID &+= 1
        isReady = false
        didRetryBindAfterFailure = false
        lastStopAt = Date()
        listener?.cancel()
        listener = nil
        onHostHint = nil
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .setup:
                break
            case .waiting:
                break
            case .preparing:
                break
            case .ready:
                if let path = connection.currentPath,
                   let remote = path.remoteEndpoint,
                   !Self.isLoopback(remote) {
                    self.logger.warning("Rejected simulator connection: not loopback")
                    connection.cancel()
                    return
                }
                self.receiveHTTP(connection: connection, buffer: Data(), generation: 0)
            case .failed, .cancelled:
                break
            @unknown default:
                connection.cancel()
            }
        }
        connection.start(queue: queue)
    }

    private static func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case let .hostPort(host, _) = endpoint else {
            return false
        }
        switch host {
        case let .ipv4(address):
            return address.rawValue[0] == 127
        case let .ipv6(address):
            let o = address.rawValue
            let allZero = (0 ..< 15).allSatisfy { o[$0] == 0 }
            return allZero && o[15] == 1
        case let .name(name, _):
            let lower = name.lowercased()
            return lower == "localhost" || lower == "127.0.0.1" || lower == "::1"
        @unknown default:
            return false
        }
    }

    private func receiveHTTP(connection: NWConnection, buffer: Data, generation: Int) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if error != nil {
                connection.cancel()
                return
            }
            var buf = buffer
            if let data, !data.isEmpty {
                buf.append(data)
            }
            if buf.count > Self.maxHeaderBytes + Self.maxBodyBytes {
                self.reply(connection: connection, raw: Self.jsonHTTPResponse(status: 413, json: ["ok": false, "error": "payload too large"]))
                return
            }
            guard let headerEnd = buf.range(of: Data("\r\n\r\n".utf8)) else {
                if isComplete {
                    self.reply(connection: connection, raw: Self.jsonHTTPResponse(status: 400, json: ["ok": false, "error": "incomplete headers"]))
                    return
                }
                self.receiveHTTP(connection: connection, buffer: buf, generation: generation + 1)
                return
            }

            let headerData = buf[..<headerEnd.lowerBound]
            let afterHeaders = buf.suffix(from: headerEnd.upperBound)
            guard let headerText = String(data: Data(headerData), encoding: .utf8) else {
                self.reply(connection: connection, raw: Self.jsonHTTPResponse(status: 400, json: ["ok": false, "error": "bad header encoding"]))
                return
            }

            let lines = headerText.split(whereSeparator: \.isNewline).map(String.init)
            guard let first = lines.first else {
                self.reply(connection: connection, raw: Self.jsonHTTPResponse(status: 400, json: ["ok": false, "error": "bad request"]))
                return
            }
            let tokens = first.split(separator: " ").map(String.init)
            guard tokens.count >= 2 else {
                self.reply(connection: connection, raw: Self.jsonHTTPResponse(status: 400, json: ["ok": false, "error": "bad request line"]))
                return
            }
            let method = tokens[0].uppercased()
            let targetPath = tokens[1].split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first
                .map(String.init) ?? tokens[1]

            var headerMap: [String: String] = [:]
            for line in lines.dropFirst() {
                if let colon = line.firstIndex(of: ":") {
                    let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
                    let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    headerMap[key] = value
                }
            }

            let length = Int(headerMap["content-length"] ?? "") ?? 0
            if length > Self.maxBodyBytes {
                self.reply(connection: connection, raw: Self.jsonHTTPResponse(status: 413, json: ["ok": false, "error": "body too large"]))
                return
            }

            let bodySoFar = Data(afterHeaders)
            if method == "OPTIONS" {
                self.reply(connection: connection, raw: Self.preflightResponse())
                return
            }

            if length == 0 && method == "POST" {
                self.reply(connection: connection, raw: Self.jsonHTTPResponse(status: 400, json: ["ok": false, "error": "Content-Length required"], cors: true))
                return
            }

            // GET /health or GET hint path: no body
            if method == "GET", targetPath == "/health" || targetPath == Self.hintPath {
                self.dispatch(method: method, targetPath: targetPath, body: Data(), connection: connection)
                return
            }

            if bodySoFar.count < length {
                self.receiveBody(
                    connection: connection,
                    expected: length,
                    collected: bodySoFar,
                    method: method,
                    targetPath: targetPath,
                    headerMap: headerMap,
                    generation: 0
                )
                return
            }

            let body = bodySoFar.prefix(length)
            self.dispatch(method: method, targetPath: targetPath, body: Data(body), connection: connection)
        }
    }

    private func receiveBody(
        connection: NWConnection,
        expected: Int,
        collected: Data,
        method: String,
        targetPath: String,
        headerMap: [String: String],
        generation: Int
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if error != nil {
                connection.cancel()
                return
            }
            var next = collected
            if let data, !data.isEmpty {
                next.append(data)
            }
            if next.count > expected {
                self.reply(connection: connection, raw: Self.jsonHTTPResponse(status: 400, json: ["ok": false, "error": "body overflow"]))
                return
            }
            if next.count < expected {
                if isComplete {
                    self.reply(connection: connection, raw: Self.jsonHTTPResponse(status: 400, json: ["ok": false, "error": "truncated body"]))
                    return
                }
                self.receiveBody(
                    connection: connection,
                    expected: expected,
                    collected: next,
                    method: method,
                    targetPath: targetPath,
                    headerMap: headerMap,
                    generation: generation + 1
                )
                return
            }
            self.dispatch(method: method, targetPath: targetPath, body: next, connection: connection)
        }
    }

    private func dispatch(method: String, targetPath: String, body: Data, connection: NWConnection) {
        if method == "GET", targetPath == "/health" || targetPath == Self.hintPath {
            let payload: [String: Any] = [
                "ok": true,
                "service": "camguard-simulator-hint",
                "port": Int(Self.port),
                "path": Self.hintPath
            ]
            self.reply(connection: connection, raw: Self.jsonHTTPResponse(status: 200, json: payload, cors: true))
            return
        }

        guard method == "POST", targetPath == Self.hintPath else {
            reply(connection: connection, raw: Self.jsonHTTPResponse(status: 404, json: ["ok": false, "error": "not found"], cors: true))
            return
        }

        struct HintPayload: Decodable {
            let host: String
        }

        do {
            let decoded = try JSONDecoder().decode(HintPayload.self, from: body)
            let trimmed = decoded.host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                reply(connection: connection, raw: Self.jsonHTTPResponse(status: 400, json: ["ok": false, "error": "host required"], cors: true))
                return
            }
            onHostHint?(trimmed)
            logger.info("Simulator loopback hint accepted for host (length \(trimmed.count, privacy: .public)).")
            reply(connection: connection, raw: Self.jsonHTTPResponse(status: 200, json: ["ok": true, "channel": "loopback"], cors: true))
        } catch {
            reply(connection: connection, raw: Self.jsonHTTPResponse(status: 400, json: ["ok": false, "error": "invalid JSON"], cors: true))
        }
    }

    private func reply(connection: NWConnection, raw: Data) {
        connection.send(content: raw, completion: .contentProcessed { error in
            if error != nil {
                connection.cancel()
                return
            }
            connection.cancel()
        })
    }

    private static func preflightResponse() -> Data {
        let headers = """
        HTTP/1.1 204 No Content\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type\r
        Access-Control-Max-Age: 86400\r
        Connection: close\r
        \r

        """
        return Data(headers.utf8)
    }

    private static func jsonHTTPResponse(status: Int, json: [String: Any], cors: Bool = false) -> Data {
        let data = try? JSONSerialization.data(withJSONObject: json)
        return httpResponse(status: status, body: data, cors: cors)
    }

    private static func httpResponse(status: Int, body: Data?, cors: Bool) -> Data {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 204: reason = "No Content"
        case 400: reason = "Bad Request"
        case 404: reason = "Not Found"
        case 413: reason = "Payload Too Large"
        default: reason = "Error"
        }
        var text = "HTTP/1.1 \(status) \(reason)\r\n"
        text += "Connection: close\r\n"
        if cors {
            text += "Access-Control-Allow-Origin: *\r\n"
            text += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
            text += "Access-Control-Allow-Headers: Content-Type\r\n"
        }
        if let body {
            text += "Content-Type: application/json; charset=utf-8\r\n"
            text += "Content-Length: \(body.count)\r\n"
        } else {
            text += "Content-Length: 0\r\n"
        }
        text += "\r\n"
        var out = Data(text.utf8)
        if let body {
            out.append(body)
        }
        return out
    }
}
