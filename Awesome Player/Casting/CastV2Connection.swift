/// Cast V2 transport layer: protobuf framing + TLS socket.
///
/// Extracted from ChromecastManager so the wire protocol can be reasoned
/// about (and one day tested) in isolation from the discovery + media
/// playback control facade. The facade in ChromecastManager.swift owns
/// the higher-level "connect to device → load media → send heartbeat"
/// state machine; this file owns the bytes-on-the-wire concerns.
///
/// Two types live here:
///   - `CastV2Message`  — hand-rolled protobuf serializer for CastMessage.
///     We don't pull in SwiftProtobuf as a dependency because the schema
///     is 6 fields (all varints or length-delimited strings).
///   - `NWConnectionWrapper` — TLS socket using raw BSD sockets + Apple's
///     Security framework. NWConnection and URLSessionStreamTask both
///     mis-handle Chromecast's self-signed certificate; VLC's approach
///     of bare CFStream + manual TLS settings is what actually works.
import Foundation

// MARK: - Cast V2 Protobuf Message (Minimal)

/// Minimal hand-rolled protobuf serializer for CastMessage. Avoids pulling in
/// SwiftProtobuf as a dependency — the CastMessage schema is simple enough to
/// encode manually (6 fields, all varints or length-delimited strings).
struct CastV2Message {
    let sourceId: String
    let destinationId: String
    let namespace: String
    let payloadUtf8: String

    func serialize() -> Data {
        // Field 1: protocol_version (varint) = 0 (CASTV2_1_0)
        // Field 2: source_id (string)
        // Field 3: destination_id (string)
        // Field 4: namespace (string)
        // Field 5: payload_type (varint) = 0 (STRING)
        // Field 6: payload_utf8 (string)
        var data = Data()

        func appendVarint(_ value: UInt64) {
            var v = value
            while v > 127 {
                data.append(UInt8(v & 0x7F | 0x80))
                v >>= 7
            }
            data.append(UInt8(v))
        }

        func appendString(fieldNumber: Int, value: String) {
            let tag = UInt64(fieldNumber << 3 | 2) // wire type 2 = length-delimited
            appendVarint(tag)
            let bytes = value.utf8
            appendVarint(UInt64(bytes.count))
            data.append(contentsOf: bytes)
        }

        func appendVarintField(fieldNumber: Int, value: UInt64) {
            let tag = UInt64(fieldNumber << 3 | 0) // wire type 0 = varint
            appendVarint(tag)
            appendVarint(value)
        }

        appendVarintField(fieldNumber: 1, value: 0) // CASTV2_1_0
        appendString(fieldNumber: 2, value: sourceId)
        appendString(fieldNumber: 3, value: destinationId)
        appendString(fieldNumber: 4, value: namespace)
        appendVarintField(fieldNumber: 5, value: 0) // STRING
        appendString(fieldNumber: 6, value: payloadUtf8)

        // Cast V2 framing: 4-byte big-endian length prefix before each protobuf message
        var length = UInt32(data.count).bigEndian
        var framed = Data(bytes: &length, count: 4)
        framed.append(data)
        return framed
    }
}

// MARK: - URLSession Stream Wrapper

/// TLS socket using raw BSD sockets + Apple Security framework, matching
/// VLC's approach. NWConnection and URLSessionStreamTask both have issues
/// with Chromecast's self-signed certificates.
class NWConnectionWrapper: NSObject, StreamDelegate {
    var onConnected: (() -> Void)?
    var onData: ((Data) -> Void)?

    let host: String
    let port: Int

    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private var isConnected = false
    private var outputBuffer = Data()
    private var canWrite = false

    init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    func connect() {
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?

        CFStreamCreatePairWithSocketToHost(nil, host as CFString, UInt32(port), &readStream, &writeStream)

        guard let input = readStream?.takeRetainedValue() as InputStream?,
              let output = writeStream?.takeRetainedValue() as OutputStream? else {
            castLog("[Chromecast] Failed to create streams")
            return
        }

        inputStream = input
        outputStream = output

        // Configure TLS — disable certificate validation for Chromecast's self-signed cert
        let sslSettings: [NSString: Any] = [
            kCFStreamSSLLevel: kCFStreamSocketSecurityLevelNegotiatedSSL as String,
            kCFStreamSSLValidatesCertificateChain: kCFBooleanFalse!,
            kCFStreamSSLPeerName: kCFNull!,
        ]
        input.setProperty(sslSettings, forKey: Stream.PropertyKey(rawValue: kCFStreamPropertySSLSettings as String))
        output.setProperty(sslSettings, forKey: Stream.PropertyKey(rawValue: kCFStreamPropertySSLSettings as String))

        // Also try setting the socket security level on the streams directly
        input.setProperty(StreamSocketSecurityLevel.negotiatedSSL, forKey: .socketSecurityLevelKey)
        output.setProperty(StreamSocketSecurityLevel.negotiatedSSL, forKey: .socketSecurityLevelKey)

        input.delegate = self
        output.delegate = self

        input.schedule(in: .main, forMode: .common)
        output.schedule(in: .main, forMode: .common)

        input.open()
        output.open()

        castLog("[Chromecast] BSD+SSL connecting to \(host):\(port)...")
    }

    func send(data: Data) {
        guard isConnected, let output = outputStream else {
            outputBuffer.append(data)
            return
        }
        if canWrite {
            let written = data.withUnsafeBytes { ptr -> Int in
                guard let base = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
                return output.write(base, maxLength: data.count)
            }
            if written < 0 {
                castLog("[Chromecast] Send error: \(output.streamError?.localizedDescription ?? "unknown")")
            } else if written < data.count {
                outputBuffer.append(data.subdata(in: written..<data.count))
            }
        } else {
            outputBuffer.append(data)
        }
    }

    func disconnect() {
        inputStream?.close()
        outputStream?.close()
        inputStream?.remove(from: .main, forMode: .common)
        outputStream?.remove(from: .main, forMode: .common)
        inputStream = nil
        outputStream = nil
        isConnected = false
    }

    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .openCompleted:
            if aStream == outputStream {
                castLog("[Chromecast] TLS connected!")
                isConnected = true
                onConnected?()
            }
        case .hasBytesAvailable:
            if aStream == inputStream {
                readAvailableData()
            }
        case .hasSpaceAvailable:
            if aStream == outputStream {
                canWrite = true
                flushOutputBuffer()
            }
        case .errorOccurred:
            castLog("[Chromecast] Stream error: \(aStream.streamError?.localizedDescription ?? "unknown")")
        case .endEncountered:
            castLog("[Chromecast] Stream ended")
            disconnect()
        default:
            break
        }
    }

    private func readAvailableData() {
        guard let input = inputStream else { return }
        var buffer = [UInt8](repeating: 0, count: 65536)
        var allData = Data()
        while input.hasBytesAvailable {
            let bytesRead = input.read(&buffer, maxLength: buffer.count)
            if bytesRead > 0 {
                allData.append(buffer, count: bytesRead)
            } else {
                break
            }
        }
        if !allData.isEmpty {
            onData?(allData)
        }
    }

    private func flushOutputBuffer() {
        guard !outputBuffer.isEmpty, let output = outputStream else { return }
        let written = outputBuffer.withUnsafeBytes { ptr -> Int in
            guard let base = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            return output.write(base, maxLength: outputBuffer.count)
        }
        if written > 0 {
            outputBuffer.removeFirst(written)
        }
    }
}
