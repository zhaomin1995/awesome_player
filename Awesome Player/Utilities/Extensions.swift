import Cocoa

/// Identifies file formats AVPlayer can handle natively (no remuxing needed).
extension URL {
    var isNativeAVPlayerFormat: Bool {
        let nativeExtensions = Set(["mp4", "m4v", "mov", "m4a", "aac", "mp3", "wav", "aiff"])
        return nativeExtensions.contains(pathExtension.lowercased())
    }
}
