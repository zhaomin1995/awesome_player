import Cocoa

enum PlayerAction: String, CaseIterable {
    case playPause = "playPause"
    case seekForwardShort = "seekForwardShort"
    case seekBackwardShort = "seekBackwardShort"
    case seekForwardLong = "seekForwardLong"
    case seekBackwardLong = "seekBackwardLong"
    case seekForwardExtraLong = "seekForwardExtraLong"
    case seekBackwardExtraLong = "seekBackwardExtraLong"
    case volumeUp = "volumeUp"
    case volumeDown = "volumeDown"
    case mute = "mute"
    case fullscreen = "fullscreen"
    case speedUp = "speedUp"
    case speedDown = "speedDown"
    case speedReset = "speedReset"
    case frameForward = "frameForward"
    case frameBackward = "frameBackward"
    case nextChapter = "nextChapter"
    case previousChapter = "previousChapter"

    var displayName: String {
        switch self {
        case .playPause: return "Play / Pause"
        case .seekForwardShort: return "Seek Forward (Short)"
        case .seekBackwardShort: return "Seek Backward (Short)"
        case .seekForwardLong: return "Seek Forward (Long)"
        case .seekBackwardLong: return "Seek Backward (Long)"
        case .seekForwardExtraLong: return "Seek Forward (Extra Long)"
        case .seekBackwardExtraLong: return "Seek Backward (Extra Long)"
        case .volumeUp: return "Volume Up"
        case .volumeDown: return "Volume Down"
        case .mute: return "Mute"
        case .fullscreen: return "Toggle Fullscreen"
        case .speedUp: return "Speed Up"
        case .speedDown: return "Speed Down"
        case .speedReset: return "Speed Reset"
        case .frameForward: return "Frame Forward"
        case .frameBackward: return "Frame Backward"
        case .nextChapter: return "Next Chapter"
        case .previousChapter: return "Previous Chapter"
        }
    }
}

struct KeyBinding: Codable {
    let key: String
    let modifiers: UInt
    let action: String

    func matches(characters: String, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        let cleaned = modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function])
        return key == characters && modifiers == cleaned.rawValue
    }
}

class KeyBindingManager {
    static let shared = KeyBindingManager()

    private var bindings: [KeyBinding] = []

    private init() {
        loadBindings()
    }

    func loadBindings() {
        if let data = UserDefaults.standard.data(forKey: Defaults.customShortcuts),
           let saved = try? JSONDecoder().decode([KeyBinding].self, from: data) {
            bindings = saved
        } else {
            bindings = Self.defaultBindings
            saveBindings()
        }
    }

    func saveBindings() {
        if let data = try? JSONEncoder().encode(bindings) {
            UserDefaults.standard.set(data, forKey: Defaults.customShortcuts)
        }
    }

    func action(for event: NSEvent) -> PlayerAction? {
        guard let chars = event.charactersIgnoringModifiers else { return nil }
        for binding in bindings {
            if binding.matches(characters: chars, modifierFlags: event.modifierFlags),
               let action = PlayerAction(rawValue: binding.action) {
                return action
            }
        }
        return nil
    }

    func setBinding(action: PlayerAction, key: String, modifiers: NSEvent.ModifierFlags) {
        bindings.removeAll { $0.action == action.rawValue }
        let cleaned = modifiers.intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function])
        bindings.append(KeyBinding(key: key, modifiers: cleaned.rawValue, action: action.rawValue))
        saveBindings()
    }

    func resetToDefaults() {
        bindings = Self.defaultBindings
        saveBindings()
    }

    func binding(for action: PlayerAction) -> KeyBinding? {
        bindings.first { $0.action == action.rawValue }
    }

    private static let defaultBindings: [KeyBinding] = {
        let none = NSEvent.ModifierFlags([]).rawValue
        let shift = NSEvent.ModifierFlags.shift.rawValue
        let cmd = NSEvent.ModifierFlags.command.rawValue

        let left = String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
        let right = String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
        let up = String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
        let down = String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))

        return [
            KeyBinding(key: " ", modifiers: none, action: PlayerAction.playPause.rawValue),
            KeyBinding(key: right, modifiers: none, action: PlayerAction.seekForwardShort.rawValue),
            KeyBinding(key: left, modifiers: none, action: PlayerAction.seekBackwardShort.rawValue),
            KeyBinding(key: right, modifiers: shift, action: PlayerAction.seekForwardLong.rawValue),
            KeyBinding(key: left, modifiers: shift, action: PlayerAction.seekBackwardLong.rawValue),
            KeyBinding(key: right, modifiers: cmd, action: PlayerAction.seekForwardExtraLong.rawValue),
            KeyBinding(key: left, modifiers: cmd, action: PlayerAction.seekBackwardExtraLong.rawValue),
            KeyBinding(key: up, modifiers: none, action: PlayerAction.volumeUp.rawValue),
            KeyBinding(key: down, modifiers: none, action: PlayerAction.volumeDown.rawValue),
            KeyBinding(key: "m", modifiers: none, action: PlayerAction.mute.rawValue),
            KeyBinding(key: "f", modifiers: none, action: PlayerAction.fullscreen.rawValue),
            KeyBinding(key: "]", modifiers: none, action: PlayerAction.speedUp.rawValue),
            KeyBinding(key: "[", modifiers: none, action: PlayerAction.speedDown.rawValue),
            KeyBinding(key: "\\", modifiers: none, action: PlayerAction.speedReset.rawValue),
            KeyBinding(key: ".", modifiers: none, action: PlayerAction.frameForward.rawValue),
            KeyBinding(key: ",", modifiers: none, action: PlayerAction.frameBackward.rawValue),
            KeyBinding(key: "n", modifiers: cmd, action: PlayerAction.nextChapter.rawValue),
            KeyBinding(key: "p", modifiers: cmd, action: PlayerAction.previousChapter.rawValue),
        ]
    }()
}
