import Cocoa
import Foundation

/// Identifies file formats AVPlayer can handle natively (no remuxing needed).
extension URL {
    var isNativeAVPlayerFormat: Bool {
        let nativeExtensions = Set(["mp4", "m4v", "mov", "m4a", "aac", "mp3", "wav", "aiff"])
        if nativeExtensions.contains(pathExtension.lowercased()) { return true }
        if !isFileURL && (scheme == "http" || scheme == "https") && pathExtension.isEmpty { return true }
        return false
    }
}

/// Short alias for `NSLocalizedString` that uses the English string itself as
/// the lookup key. Pairs with the Xcode 15+ Localizable.xcstrings catalog —
/// when the catalog has no translation for the current locale, the source
/// English string is returned as the fallback.
///
/// Routes through `LanguageManager.shared.bundle` so the in-app language
/// picker can swap locales at runtime without a relaunch.
///
/// Usage: `L("Play / Pause")`, `L("Volume: %d%%")`.
func L(_ key: String, comment: String = "") -> String {
    LanguageManager.shared.bundle.localizedString(forKey: key, value: key, table: nil)
}

extension Notification.Name {
    /// Posted after LanguageManager.shared.setLanguage(...) finishes swapping
    /// the active bundle. Views that hold L()-derived static text in
    /// stringValue should observe this and re-apply L() to refresh in place.
    static let languageDidChange = Notification.Name("AwesomePlayer.LanguageDidChange")
}

/// Owns the active resource bundle that L() reads strings from. By default
/// this is Bundle.main (using whichever language macOS picked from
/// AppleLanguages at launch). When the user picks a specific language in
/// Preferences, we swap to that .lproj's bundle so new L() calls return the
/// chosen translations immediately — no relaunch.
///
/// We also write the choice to AppleLanguages so that:
/// 1. System dialogs (NSOpenPanel buttons, etc.) match next launch
/// 2. The setting persists across launches
final class LanguageManager {
    static let shared = LanguageManager()

    private var customBundle: Bundle?

    /// The active bundle L() reads from. Falls back to Bundle.main when no
    /// explicit override is set (System Default).
    var bundle: Bundle { customBundle ?? .main }

    /// The currently-active language code, or nil for System Default.
    var currentLanguage: String? {
        (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String])?.first
    }

    init() {
        loadBundleFromDefaults()
    }

    private func loadBundleFromDefaults() {
        guard let lang = currentLanguage,
              let path = Bundle.main.path(forResource: lang, ofType: "lproj"),
              let b = Bundle(path: path)
        else {
            customBundle = nil
            return
        }
        customBundle = b
    }

    /// `code` is the .lproj name (e.g. "zh-Hans", "yue"), or nil to clear
    /// the override and follow the system locale.
    func setLanguage(_ code: String?) {
        if let code = code, !code.isEmpty,
           let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let b = Bundle(path: path) {
            customBundle = b
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        } else {
            customBundle = nil
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
    }
}
