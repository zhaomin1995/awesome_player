import XCTest
@testable import Awesome_Player

/// Tests for AppDelegate.classifyIncomingURL — the pure URL classifier used by
/// the awesomeplayer:// URL scheme handler, Services menu, bookmarklet, and
/// CLI to decide whether an inbound string is a local file, an HTTP stream,
/// or unrecognizable. The actual dispatch (openFile / openStream) is left to
/// the caller — these tests only pin classification.
final class URLRoutingTests: XCTestCase {

    private func classify(
        _ s: String, fileExists: @escaping (String) -> Bool = { _ in false }
    ) -> AppDelegate.IncomingURLAction {
        return AppDelegate.classifyIncomingURL(s, fileExists: fileExists)
    }

    // MARK: - file:// URLs

    func testFileURLOpensAsFile() {
        let r = classify("file:///Users/me/Movies/foo.mkv")
        guard case .openFile(let url) = r else { return XCTFail("expected .openFile, got \(r)") }
        XCTAssertEqual(url.path, "/Users/me/Movies/foo.mkv")
    }

    // MARK: - HTTP/HTTPS URLs

    func testHTTPSURLOpensAsStream() {
        let r = classify("https://example.com/video.mp4")
        guard case .openStream(let url) = r else { return XCTFail("expected .openStream, got \(r)") }
        XCTAssertEqual(url.absoluteString, "https://example.com/video.mp4")
    }

    func testHTTPURLOpensAsStream() {
        let r = classify("http://192.168.1.50:8080/stream.m3u8")
        guard case .openStream(let url) = r else { return XCTFail("expected .openStream, got \(r)") }
        XCTAssertEqual(url.host, "192.168.1.50")
    }

    func testYouTubeURLOpensAsStream() {
        // No file-extension shortcut here — the openStream branch hands the
        // URL to URLOpenCoordinator which dispatches to yt-dlp for resolution.
        let r = classify("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        guard case .openStream = r else { return XCTFail("expected .openStream, got \(r)") }
    }

    // MARK: - Bare paths (with fileExists injection)

    func testBarePathThatExistsOpensAsFile() {
        let path = "/tmp/test-video.mkv"
        let r = classify(path, fileExists: { $0 == path })
        guard case .openFile(let url) = r else { return XCTFail("expected .openFile, got \(r)") }
        XCTAssertEqual(url.path, path)
        XCTAssertTrue(url.isFileURL)
    }

    func testBarePathThatDoesNotExistIsUnknown() {
        let r = classify("/tmp/not-here.mkv", fileExists: { _ in false })
        XCTAssertEqual(r, .unknown)
    }

    // MARK: - Garbage inputs

    func testEmptyStringIsUnknown() {
        XCTAssertEqual(classify(""), .unknown)
    }

    func testUnrecognizedSchemeIsUnknown() {
        // Unknown scheme + not a real file path → don't try to interpret.
        XCTAssertEqual(classify("ftp://example.com/video.mp4"), .unknown)
        XCTAssertEqual(classify("javascript:alert(1)"), .unknown)
    }

    func testFileExistsCheckIsNotCalledForURLForms() {
        // Sanity: the file-exists callback should not run for inputs that the
        // URL branches consume first. Otherwise a slow disk lookup happens on
        // every web URL we route.
        var calls = 0
        _ = classify("https://example.com/x.mp4", fileExists: { _ in calls += 1; return false })
        _ = classify("file:///a", fileExists: { _ in calls += 1; return false })
        XCTAssertEqual(calls, 0)
    }
}
