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

/// A named set of key bindings. Switching presets overwrites the user's
/// active bindings — no per-action customization is preserved across a
/// preset switch (matches Movist Pro's "Shortcuts preset" behavior).
struct BindingPreset {
    let id: String              // stable English, used as UserDefaults value
    let displayKey: String      // L() key for the human-visible name
    let bindings: [KeyBinding]
}

class KeyBindingManager {
    static let shared = KeyBindingManager()

    private var bindings: [KeyBinding] = []

    private init() {
        loadBindings()
    }

    /// Force-reload from UserDefaults. Useful after applyPreset() has
    /// modified the saved bindings out from under whatever is using them.
    func loadBindings() {
        if let data = UserDefaults.standard.data(forKey: Defaults.customShortcuts),
           let saved = try? JSONDecoder().decode([KeyBinding].self, from: data) {
            bindings = saved
        } else {
            // Fresh install — apply default preset
            bindings = Self.allPresets[0].bindings
            saveBindings()
            UserDefaults.standard.set(Self.allPresets[0].id, forKey: Self.presetKey)
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

    // MARK: - Presets

    static let presetKey = "keyboard.bindingPresetId"

    /// All registered presets, in display order. First entry is the
    /// fresh-install default.
    static let allPresets: [BindingPreset] = [
        BindingPreset(id: "default", displayKey: "Default (Awesome Player)", bindings: makeDefaultBindings()),
        BindingPreset(id: "vlc",     displayKey: "VLC Style",                bindings: makeVLCBindings()),
    ]

    var currentPresetId: String {
        UserDefaults.standard.string(forKey: Self.presetKey) ?? Self.allPresets[0].id
    }

    var currentBindings: [KeyBinding] { bindings }

    func applyPreset(id: String) {
        guard let preset = Self.allPresets.first(where: { $0.id == id }) else { return }
        bindings = preset.bindings
        UserDefaults.standard.set(preset.id, forKey: Self.presetKey)
        saveBindings()
    }

    // MARK: - Preset definitions

    private static let none = NSEvent.ModifierFlags([]).rawValue
    private static let shift = NSEvent.ModifierFlags.shift.rawValue
    private static let cmd = NSEvent.ModifierFlags.command.rawValue
    private static let opt = NSEvent.ModifierFlags.option.rawValue
    private static let ctrl = NSEvent.ModifierFlags.control.rawValue

    private static let left = String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
    private static let right = String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
    private static let up = String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
    private static let down = String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))

    /// Our original mapping. Optimized for single-handed use: arrows for
    /// seek/volume, bare letters for common toggles. Easy to reach without
    /// taking a hand off the keyboard.
    private static func makeDefaultBindings() -> [KeyBinding] {
        [
            KeyBinding(key: " ",   modifiers: none,  action: PlayerAction.playPause.rawValue),
            KeyBinding(key: right, modifiers: none,  action: PlayerAction.seekForwardShort.rawValue),
            KeyBinding(key: left,  modifiers: none,  action: PlayerAction.seekBackwardShort.rawValue),
            KeyBinding(key: right, modifiers: shift, action: PlayerAction.seekForwardLong.rawValue),
            KeyBinding(key: left,  modifiers: shift, action: PlayerAction.seekBackwardLong.rawValue),
            KeyBinding(key: right, modifiers: cmd,   action: PlayerAction.seekForwardExtraLong.rawValue),
            KeyBinding(key: left,  modifiers: cmd,   action: PlayerAction.seekBackwardExtraLong.rawValue),
            KeyBinding(key: up,    modifiers: none,  action: PlayerAction.volumeUp.rawValue),
            KeyBinding(key: down,  modifiers: none,  action: PlayerAction.volumeDown.rawValue),
            KeyBinding(key: "m",   modifiers: none,  action: PlayerAction.mute.rawValue),
            KeyBinding(key: "f",   modifiers: none,  action: PlayerAction.fullscreen.rawValue),
            KeyBinding(key: "]",   modifiers: none,  action: PlayerAction.speedUp.rawValue),
            KeyBinding(key: "[",   modifiers: none,  action: PlayerAction.speedDown.rawValue),
            KeyBinding(key: "\\",  modifiers: none,  action: PlayerAction.speedReset.rawValue),
            KeyBinding(key: ".",   modifiers: none,  action: PlayerAction.frameForward.rawValue),
            KeyBinding(key: ",",   modifiers: none,  action: PlayerAction.frameBackward.rawValue),
            KeyBinding(key: "n",   modifiers: cmd,   action: PlayerAction.nextChapter.rawValue),
            KeyBinding(key: "p",   modifiers: cmd,   action: PlayerAction.previousChapter.rawValue),
        ]
    }

    /// Mirrors VLC's macOS defaults — comfortable for users coming from VLC.
    /// Heavy ⌘/⌥/⇧ modifiers on the seek/volume keys; bare letters mostly
    /// reserved for toggles. The space-for-play is universal.
    private static func makeVLCBindings() -> [KeyBinding] {
        [
            KeyBinding(key: " ",   modifiers: none,        action: PlayerAction.playPause.rawValue),
            // Seek: ⌥← / ⌥→ short, ⇧← / ⇧→ long, ⇧⌘← / ⇧⌘→ extra-long
            KeyBinding(key: right, modifiers: opt,         action: PlayerAction.seekForwardShort.rawValue),
            KeyBinding(key: left,  modifiers: opt,         action: PlayerAction.seekBackwardShort.rawValue),
            KeyBinding(key: right, modifiers: shift,       action: PlayerAction.seekForwardLong.rawValue),
            KeyBinding(key: left,  modifiers: shift,       action: PlayerAction.seekBackwardLong.rawValue),
            KeyBinding(key: right, modifiers: shift | cmd, action: PlayerAction.seekForwardExtraLong.rawValue),
            KeyBinding(key: left,  modifiers: shift | cmd, action: PlayerAction.seekBackwardExtraLong.rawValue),
            // Volume: ⌘↑ / ⌘↓ (matches VLC's volume bindings)
            KeyBinding(key: up,    modifiers: cmd,         action: PlayerAction.volumeUp.rawValue),
            KeyBinding(key: down,  modifiers: cmd,         action: PlayerAction.volumeDown.rawValue),
            // ⌘M mute, ⌘F fullscreen (VLC uses these; same as macOS conventions)
            KeyBinding(key: "m",   modifiers: cmd,         action: PlayerAction.mute.rawValue),
            KeyBinding(key: "f",   modifiers: cmd,         action: PlayerAction.fullscreen.rawValue),
            // Speed: ⌘= speed up, ⌘- slow down, ⌘\ reset (close to VLC's ⌘+/⌘-)
            KeyBinding(key: "=",   modifiers: cmd,         action: PlayerAction.speedUp.rawValue),
            KeyBinding(key: "-",   modifiers: cmd,         action: PlayerAction.speedDown.rawValue),
            KeyBinding(key: "\\",  modifiers: cmd,         action: PlayerAction.speedReset.rawValue),
            // Frame stepping: ⌘. / ⌘, (VLC uses 'e' for next frame; we keep ⌘./⌘,)
            KeyBinding(key: ".",   modifiers: cmd,         action: PlayerAction.frameForward.rawValue),
            KeyBinding(key: ",",   modifiers: cmd,         action: PlayerAction.frameBackward.rawValue),
            // Chapter: ⌃⌘N / ⌃⌘P (less likely to conflict with macOS)
            KeyBinding(key: "n",   modifiers: ctrl | cmd,  action: PlayerAction.nextChapter.rawValue),
            KeyBinding(key: "p",   modifiers: ctrl | cmd,  action: PlayerAction.previousChapter.rawValue),
        ]
    }
}
