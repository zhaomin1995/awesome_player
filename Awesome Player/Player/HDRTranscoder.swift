/// Transcodes Dolby Vision Profile 5 content to plain HDR10 by spawning the
/// bundled ffmpeg (built with libplacebo) as a subprocess. The DV→HDR10
/// conversion is required for AirPlay/Cast to receivers that don't decode DV
/// (Samsung TVs, older Apple TV models, most Chromecast devices).
///
/// Why a subprocess instead of libvlc/libplacebo bindings: ffmpeg's libplacebo
/// filter is what actually applies the RPU's IPT→BT.2020 reshape per frame.
/// Wrapping libplacebo's C API directly from Swift would be much more code
/// and would have to be re-validated; ffmpeg is the well-tested integration.
///
/// The bundled ffmpeg lives at Contents/Resources/ffmpeg-cli/bin/ffmpeg and
/// finds its dylibs via @rpath = ../lib (resolves to ffmpeg-cli/lib).
/// VK_ICD_FILENAMES env var points to the bundled MoltenVK ICD JSON so
/// libplacebo's Vulkan backend can find Metal-backed Vulkan on Apple silicon.
import Foundation

class HDRTranscoder {
    enum TranscodeError: Error {
        case ffmpegNotBundled
        case launchFailed(Error)
        case exitedNonZero(Int32, String)
        case cancelled
    }

    private var process: Process?
    private var stderrBuffer = ""
    private var totalDurationSeconds: Double = 0

    /// Called on the main thread with progress in [0, 1].
    var onProgress: ((Double) -> Void)?

    /// Called on the main thread when transcoding completes (success or failure).
    var onCompletion: ((Result<URL, TranscodeError>) -> Void)?

    /// True once `start` succeeds and the subprocess is running.
    private(set) var isRunning = false

    /// Locate the bundled ffmpeg CLI binary.
    static var bundledFFmpegURL: URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("ffmpeg-cli/bin/ffmpeg")
    }

    /// Locate the bundled Vulkan ICD JSON (tells the Vulkan loader to use MoltenVK).
    static var bundledICDPath: String? {
        Bundle.main.resourceURL?
            .appendingPathComponent("ffmpeg-cli/etc/vulkan/icd.d/MoltenVK_icd.json")
            .path
    }

    /// Kick off the transcode. Returns the destination URL the file will be
    /// written to; callers can use this to monitor file growth for live-stream
    /// scenarios. Subprocess runs on a background queue; callbacks fire on main.
    @discardableResult
    func start(input: URL) -> Result<URL, TranscodeError> {
        guard let ffmpeg = Self.bundledFFmpegURL,
              FileManager.default.fileExists(atPath: ffmpeg.path) else {
            return .failure(.ffmpegNotBundled)
        }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("airplay_hdr10_" + UUID().uuidString)
            .appendingPathExtension("mp4")

        let proc = Process()
        proc.executableURL = ffmpeg
        proc.arguments = [
            "-y", "-hide_banner", "-loglevel", "info",
            "-i", input.path,
            // libplacebo applies the DV RPU's IPT→BT.2020 reshape automatically
            // (apply_dolbyvision defaults to true). Output limited-range PQ.
            "-vf", "libplacebo=colorspace=bt2020nc:color_primaries=bt2020:color_trc=smpte2084:range=tv:format=yuv420p10le",
            // Tag the output stream with HDR10 signaling so the muxer writes
            // the colr (nclx) atom that AirPlay/Cast receivers key on.
            "-color_primaries", "bt2020",
            "-color_trc", "smpte2084",
            "-colorspace", "bt2020nc",
            "-color_range", "tv",
            // VideoToolbox HW HEVC encode — ~2× realtime on M4.
            "-c:v", "hevc_videotoolbox",
            "-profile:v", "main10",
            "-tag:v", "hvc1",
            "-b:v", "25M",
            // Source EAC3 audio isn't supported by all AirPlay receivers;
            // transcode to AAC stereo for broad compatibility.
            "-c:a", "aac",
            "-b:a", "256k",
            "-movflags", "+faststart",
            // ffmpeg writes key=value progress lines here once per second
            "-progress", "pipe:2",
            output.path,
        ]

        var env = ProcessInfo.processInfo.environment
        if let icd = Self.bundledICDPath {
            env["VK_ICD_FILENAMES"] = icd
        }
        proc.environment = env

        let stderrPipe = Pipe()
        proc.standardError = stderrPipe

        // Read on a background queue; coalesce text chunks for line parsing.
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.handleStderr(text)
        }

        proc.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                guard let self = self else { return }
                self.isRunning = false
                let status = p.terminationStatus
                let reason = p.terminationReason
                if reason == .uncaughtSignal {
                    self.onCompletion?(.failure(.cancelled))
                } else if status == 0 {
                    self.onCompletion?(.success(output))
                } else {
                    let tail = self.stderrBuffer.split(separator: "\n").suffix(5).joined(separator: "\n")
                    self.onCompletion?(.failure(.exitedNonZero(status, tail)))
                }
            }
        }

        do {
            try proc.run()
        } catch {
            return .failure(.launchFailed(error))
        }
        self.process = proc
        self.isRunning = true
        return .success(output)
    }

    /// Terminates the subprocess. Completion callback fires with .cancelled.
    func cancel() {
        process?.terminate()
    }

    // MARK: - Stderr parsing

    /// ffmpeg writes two relevant things to stderr:
    /// - On startup, one line like `Duration: 00:46:53.72, start: 0.000000, ...`
    /// - With -progress pipe:2, key=value lines once per second including
    ///   `out_time_us=NNNNN` (we use it as numerator for progress).
    private func handleStderr(_ text: String) {
        stderrBuffer += text
        // Cap retained buffer to avoid unbounded growth on long encodes
        if stderrBuffer.count > 16_384 {
            stderrBuffer.removeFirst(stderrBuffer.count - 16_384)
        }

        if totalDurationSeconds == 0,
           let duration = Self.parseDuration(in: text) {
            totalDurationSeconds = duration
        }

        if totalDurationSeconds > 0,
           let outTimeUs = Self.parseOutTimeUs(in: text) {
            let progress = min(1.0, max(0, outTimeUs / 1_000_000 / totalDurationSeconds))
            DispatchQueue.main.async { [weak self] in
                self?.onProgress?(progress)
            }
        }
    }

    /// Parse `Duration: HH:MM:SS.mm` from an ffmpeg startup line.
    static func parseDuration(in text: String) -> Double? {
        guard let range = text.range(of: "Duration: ") else { return nil }
        let after = text[range.upperBound...]
        guard let end = after.firstIndex(of: ",") else { return nil }
        return parseHMS(String(after[..<end]))
    }

    /// Parse the last `out_time_us=NNNN` value in a text block.
    static func parseOutTimeUs(in text: String) -> Double? {
        var last: Double?
        for line in text.split(separator: "\n") {
            if line.hasPrefix("out_time_us=") {
                if let v = Double(line.dropFirst("out_time_us=".count)) { last = v }
            }
        }
        return last
    }

    private static func parseHMS(_ s: String) -> Double? {
        let parts = s.split(separator: ":")
        guard parts.count == 3,
              let h = Double(parts[0]),
              let m = Double(parts[1]),
              let sec = Double(parts[2]) else { return nil }
        return h * 3600 + m * 60 + sec
    }
}
