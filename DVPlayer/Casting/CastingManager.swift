import Foundation

enum CastDeviceType {
    case airplay
    case chromecast
    case dlna
}

struct CastDevice {
    let id: String
    let name: String
    let type: CastDeviceType
    let host: String
    let port: Int
}

enum CastState {
    case disconnected
    case connecting
    case connected(CastDevice)
    case playing(CastDevice)
}

protocol CastingManagerDelegate: AnyObject {
    func castingManager(_ manager: CastingManager, didDiscoverDevice device: CastDevice)
    func castingManager(_ manager: CastingManager, didRemoveDevice deviceId: String)
    func castingManager(_ manager: CastingManager, didChangeState state: CastState)
    func castingManager(_ manager: CastingManager, didUpdatePosition position: Double, duration: Double)
}

class CastingManager {
    weak var delegate: CastingManagerDelegate?

    private let chromecastManager = ChromecastManager()
    private let dlnaManager = DLNAManager()
    private let httpServer = CastingHTTPServer()

    private(set) var state: CastState = .disconnected
    private(set) var discoveredDevices: [CastDevice] = []

    func startDiscovery() {
        chromecastManager.delegate = self
        dlnaManager.delegate = self
        chromecastManager.startDiscovery()
        dlnaManager.startDiscovery()
    }

    func stopDiscovery() {
        chromecastManager.stopDiscovery()
        dlnaManager.stopDiscovery()
    }

    func connect(to device: CastDevice) {
        state = .connecting
        delegate?.castingManager(self, didChangeState: state)

        switch device.type {
        case .chromecast:
            chromecastManager.connect(to: device)
        case .dlna:
            dlnaManager.connect(to: device)
        case .airplay:
            break // Handled by AVPlayer natively
        }
    }

    func cast(fileURL: URL, to device: CastDevice) {
        httpServer.start(servingFile: fileURL) { [weak self] serverURL in
            guard let self = self, let url = serverURL else { return }

            switch device.type {
            case .chromecast:
                self.chromecastManager.loadMedia(url: url, on: device)
            case .dlna:
                self.dlnaManager.loadMedia(url: url, on: device)
            case .airplay:
                break
            }

            self.state = .playing(device)
            self.delegate?.castingManager(self, didChangeState: self.state)
        }
    }

    func pause() {
        switch state {
        case .playing(let device):
            switch device.type {
            case .chromecast: chromecastManager.pause()
            case .dlna: dlnaManager.pause()
            case .airplay: break
            }
        default: break
        }
    }

    func resume() {
        switch state {
        case .playing(let device):
            switch device.type {
            case .chromecast: chromecastManager.play()
            case .dlna: dlnaManager.play()
            case .airplay: break
            }
        default: break
        }
    }

    func seek(to position: Double) {
        switch state {
        case .playing(let device):
            switch device.type {
            case .chromecast: chromecastManager.seek(to: position)
            case .dlna: dlnaManager.seek(to: position)
            case .airplay: break
            }
        default: break
        }
    }

    func stop() {
        switch state {
        case .playing(let device), .connected(let device):
            switch device.type {
            case .chromecast: chromecastManager.stop()
            case .dlna: dlnaManager.stop()
            case .airplay: break
            }
        default: break
        }
        httpServer.stop()
        state = .disconnected
        delegate?.castingManager(self, didChangeState: state)
    }

    func disconnect() {
        stop()
    }
}

extension CastingManager: ChromecastManagerDelegate {
    func chromecastDidDiscover(_ device: CastDevice) {
        discoveredDevices.append(device)
        delegate?.castingManager(self, didDiscoverDevice: device)
    }

    func chromecastDidRemove(_ deviceId: String) {
        discoveredDevices.removeAll { $0.id == deviceId }
        delegate?.castingManager(self, didRemoveDevice: deviceId)
    }

    func chromecastDidConnect(_ device: CastDevice) {
        state = .connected(device)
        delegate?.castingManager(self, didChangeState: state)
    }

    func chromecastDidUpdatePosition(_ position: Double, duration: Double) {
        delegate?.castingManager(self, didUpdatePosition: position, duration: duration)
    }
}

extension CastingManager: DLNAManagerDelegate {
    func dlnaDidDiscover(_ device: CastDevice) {
        discoveredDevices.append(device)
        delegate?.castingManager(self, didDiscoverDevice: device)
    }

    func dlnaDidRemove(_ deviceId: String) {
        discoveredDevices.removeAll { $0.id == deviceId }
        delegate?.castingManager(self, didRemoveDevice: deviceId)
    }

    func dlnaDidConnect(_ device: CastDevice) {
        state = .connected(device)
        delegate?.castingManager(self, didChangeState: state)
    }

    func dlnaDidUpdatePosition(_ position: Double, duration: Double) {
        delegate?.castingManager(self, didUpdatePosition: position, duration: duration)
    }
}
