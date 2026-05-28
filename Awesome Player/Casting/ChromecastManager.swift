/// Chromecast integration using the Cast V2 protocol (no Google Cast SDK dependency).
/// Discovers devices via mDNS (_googlecast._tcp), connects over TLS, and communicates
/// using length-prefixed protobuf messages (CastV2Message). The protocol requires
/// establishing a virtual connection before launching the media receiver app.
import Foundation

/// Debug-only cast log routed through the unified logging façade.
/// In Release this is a no-op (see Utilities/Logging.swift). Earlier
/// versions wrote to /tmp/chromecast_debug.log which leaked stream URLs
/// and receiver names to a world-readable file and wasn't picked up by
/// Console.app. To capture cast traffic during debugging now:
///
///   log stream --predicate 'subsystem == "com.awesomeplayer.AwesomePlayer" && category == "Cast"'
@inline(__always)
func castLog(_ message: String) {
    dlog(.cast, message)
}

protocol ChromecastManagerDelegate: AnyObject {
    func chromecastDidDiscover(_ device: CastDevice)
    func chromecastDidRemove(_ deviceId: String)
    func chromecastDidConnect(_ device: CastDevice)
    func chromecastDidUpdatePosition(_ position: Double, duration: Double)
}

class ChromecastManager: NSObject {
    weak var delegate: ChromecastManagerDelegate?

    private var browser: NetServiceBrowser?
    private var services: [NetService] = []
    private var connectedDevice: CastDevice?
    private var connection: NWConnectionWrapper?

    private var transportId: String?
    private var heartbeatTimer: Timer?
    private var pendingMediaURL: URL?
    private var mediaSessionId: Int?
    private var requestId: Int = 0

    func startDiscovery() {
        browser = NetServiceBrowser()
        browser?.delegate = self
        browser?.searchForServices(ofType: "_googlecast._tcp.", inDomain: "local.")
    }

    func stopDiscovery() {
        browser?.stop()
        browser = nil
        services.removeAll()
    }

    func connect(to device: CastDevice) {
        connectedDevice = device
        // Strip trailing dot from mDNS hostnames (e.g. "xxx.local." → "xxx.local")
        let cleanHost = device.host.hasSuffix(".") ? String(device.host.dropLast()) : device.host
        castLog("[Chromecast] Connecting to \(cleanHost):\(device.port) (\(device.name))")
        connection = NWConnectionWrapper(host: cleanHost, port: device.port)
        connection?.onConnected = { [weak self] in
            self?.onTLSConnected(device)
        }
        connection?.onData = { [weak self] data in
            self?.handleIncomingData(data)
        }
        connection?.connect()
    }

    func loadMedia(url: URL, on device: CastDevice) {
        if transportId != nil {
            sendLoadCommand(url: url)
        } else {
            pendingMediaURL = url
        }
    }

    func play() {
        guard let sessionId = mediaSessionId else { return }
        sendMediaCommand(["type": "PLAY", "requestId": nextRequestId(), "mediaSessionId": sessionId])
    }

    func pause() {
        guard let sessionId = mediaSessionId else { return }
        sendMediaCommand(["type": "PAUSE", "requestId": nextRequestId(), "mediaSessionId": sessionId])
    }

    func seek(to position: Double) {
        guard let sessionId = mediaSessionId else { return }
        sendMediaCommand(["type": "SEEK", "requestId": nextRequestId(), "mediaSessionId": sessionId, "currentTime": position])
    }

    func stop() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        if let tid = transportId {
            sendCastMessage(sourceId: "sender-vlc", destinationId: tid,
                          namespace: "urn:x-cast:com.google.cast.tp.connection",
                          payload: ["type": "CLOSE"])
        }
        sendCastMessage(sourceId: "sender-vlc", destinationId: "receiver-0",
                       namespace: "urn:x-cast:com.google.cast.receiver",
                       payload: ["type": "STOP", "requestId": nextRequestId()])
        connection?.disconnect()
        connection = nil
        connectedDevice = nil
        transportId = nil
        mediaSessionId = nil
        pendingMediaURL = nil
    }

    // MARK: - Connection Flow

    private func onTLSConnected(_ device: CastDevice) {
        castLog("[Chromecast] TLS connected to \(device.host):\(device.port)")
        // Step 1: Open virtual connection to the receiver
        sendCastMessage(sourceId: "sender-vlc", destinationId: "receiver-0",
                       namespace: "urn:x-cast:com.google.cast.tp.connection",
                       payload: ["type": "CONNECT", "origin": [:] as [String: Any],
                                 "userAgent": "Awesome Player", "senderInfo": ["sdkType": 2]])

        // Step 2: Launch the Default Media Receiver
        sendCastMessage(sourceId: "sender-vlc", destinationId: "receiver-0",
                       namespace: "urn:x-cast:com.google.cast.receiver",
                       payload: ["type": "LAUNCH", "requestId": nextRequestId(), "appId": "CC1AD845"])

        // Step 3: Start heartbeat to keep connection alive
        DispatchQueue.main.async { [weak self] in
            self?.heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.sendHeartbeat()
            }
        }

        delegate?.chromecastDidConnect(device)
    }

    private func sendHeartbeat() {
        sendCastMessage(sourceId: "sender-vlc", destinationId: "receiver-0",
                       namespace: "urn:x-cast:com.google.cast.tp.heartbeat",
                       payload: ["type": "PING"])
    }

    private func sendLoadCommand(url: URL) {
        guard let tid = transportId else {
            castLog("[Chromecast] Cannot send LOAD — no transport ID yet")
            return
        }
        castLog("[Chromecast] Sending LOAD to \(tid): \(url.absoluteString)")

        let ext = url.pathExtension.lowercased()
        let contentType: String
        switch ext {
        case "mp4", "m4v": contentType = "video/mp4"
        case "mkv": contentType = "video/x-matroska"
        case "webm": contentType = "video/webm"
        case "avi": contentType = "video/x-msvideo"
        case "mov": contentType = "video/quicktime"
        default: contentType = "video/mp4"
        }

        let loadPayload: [String: Any] = [
            "type": "LOAD",
            "requestId": nextRequestId(),
            "media": [
                "contentId": url.absoluteString,
                "contentType": contentType,
                "streamType": "BUFFERED",
            ],
            "autoplay": true,
        ]
        sendCastMessage(sourceId: "sender-vlc", destinationId: tid,
                       namespace: "urn:x-cast:com.google.cast.media",
                       payload: loadPayload)
    }

    private func sendMediaCommand(_ payload: [String: Any]) {
        guard let tid = transportId else { return }
        sendCastMessage(sourceId: "sender-vlc", destinationId: tid,
                       namespace: "urn:x-cast:com.google.cast.media",
                       payload: payload)
    }

    // MARK: - Response Parsing

    private var receiveBuffer = Data()

    private func handleIncomingData(_ data: Data) {
        receiveBuffer.append(data)

        // Cast V2: 4-byte big-endian length prefix, then protobuf message
        while receiveBuffer.count >= 4 {
            let length = Int(receiveBuffer[0]) << 24 | Int(receiveBuffer[1]) << 16 |
                         Int(receiveBuffer[2]) << 8 | Int(receiveBuffer[3])
            guard receiveBuffer.count >= 4 + length else { break }

            let messageData = receiveBuffer.subdata(in: 4..<(4 + length))
            receiveBuffer = receiveBuffer.subdata(in: (4 + length)..<receiveBuffer.count)

            parseProtobufMessage(messageData)
        }
    }

    private func parseProtobufMessage(_ data: Data) {
        // Minimal protobuf parser — extract namespace (field 4) and payload_utf8 (field 6)
        var namespace: String?
        var payloadUtf8: String?
        var offset = 0

        while offset < data.count {
            guard offset < data.count else { break }
            let byte = data[offset]
            let fieldNumber = Int(byte >> 3)
            let wireType = Int(byte & 0x07)
            offset += 1

            switch wireType {
            case 0: // varint
                while offset < data.count && data[offset] & 0x80 != 0 { offset += 1 }
                if offset < data.count { offset += 1 }
            case 2: // length-delimited
                var strLen: Int = 0
                var shift = 0
                while offset < data.count {
                    let b = data[offset]
                    strLen |= Int(b & 0x7F) << shift
                    offset += 1
                    shift += 7
                    if b & 0x80 == 0 { break }
                }
                guard offset + strLen <= data.count else { return }
                let strData = data.subdata(in: offset..<(offset + strLen))
                if fieldNumber == 4 { namespace = String(data: strData, encoding: .utf8) }
                if fieldNumber == 6 { payloadUtf8 = String(data: strData, encoding: .utf8) }
                offset += strLen
            default:
                return
            }
        }

        guard let ns = namespace, let payload = payloadUtf8,
              let jsonData = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            castLog("[Chromecast] Failed to parse message: ns=\(namespace ?? "nil")")
            return
        }

        let type = json["type"] as? String ?? "?"
        castLog("[Chromecast] Received: \(ns.split(separator: ".").last ?? "") → \(type)")
        handleCastMessage(namespace: ns, json: json)
    }

    private func handleCastMessage(namespace: String, json: [String: Any]) {
        let type = json["type"] as? String ?? ""

        switch namespace {
        case "urn:x-cast:com.google.cast.tp.heartbeat":
            if type == "PING" {
                sendCastMessage(sourceId: "sender-vlc", destinationId: "receiver-0",
                               namespace: "urn:x-cast:com.google.cast.tp.heartbeat",
                               payload: ["type": "PONG"])
            }

        case "urn:x-cast:com.google.cast.receiver":
            if type == "RECEIVER_STATUS" {
                if let status = json["status"] as? [String: Any],
                   let apps = status["applications"] as? [[String: Any]],
                   let app = apps.first,
                   let tid = app["transportId"] as? String {
                    if transportId == nil {
                        transportId = tid
                        castLog("[Chromecast] App launched, transportId: \(tid)")

                        // Connect to the app's transport
                        sendCastMessage(sourceId: "sender-vlc", destinationId: tid,
                                       namespace: "urn:x-cast:com.google.cast.tp.connection",
                                       payload: ["type": "CONNECT", "origin": [:] as [String: Any]])

                        // Send pending media load
                        if let url = pendingMediaURL {
                            pendingMediaURL = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                                self?.sendLoadCommand(url: url)
                            }
                        }
                    }
                }
            }

        case "urn:x-cast:com.google.cast.media":
            if type == "MEDIA_STATUS" {
                if let statuses = json["status"] as? [[String: Any]],
                   let status = statuses.first {
                    mediaSessionId = status["mediaSessionId"] as? Int
                    let currentTime = status["currentTime"] as? Double ?? 0
                    let duration = (status["media"] as? [String: Any])?["duration"] as? Double ?? 0
                    delegate?.chromecastDidUpdatePosition(currentTime, duration: duration)
                }
            }

        default:
            break
        }
    }

    // MARK: - Message Sending

    private func nextRequestId() -> Int {
        requestId += 1
        return requestId
    }

    private func sendCastMessage(sourceId: String, destinationId: String, namespace: String, payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        guard let jsonString = String(data: data, encoding: .utf8) else { return }

        let message = CastV2Message(
            sourceId: sourceId,
            destinationId: destinationId,
            namespace: namespace,
            payloadUtf8: jsonString
        )

        connection?.send(data: message.serialize())
    }
}

extension ChromecastManager: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5.0)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.removeAll { $0 == service }
        delegate?.chromecastDidRemove(service.name)
    }
}

extension ChromecastManager: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let hostName = sender.hostName else { return }
        var friendlyName = sender.name
        if let txtData = sender.txtRecordData() {
            let dict = NetService.dictionary(fromTXTRecord: txtData)
            if let fnData = dict["fn"], let fn = String(data: fnData, encoding: .utf8), !fn.isEmpty {
                friendlyName = fn
            }
        }
        let device = CastDevice(
            id: sender.name,
            name: friendlyName,
            type: .chromecast,
            host: hostName,
            port: sender.port
        )
        delegate?.chromecastDidDiscover(device)
    }
}

// CastV2Message + NWConnectionWrapper moved to Casting/CastV2Connection.swift
