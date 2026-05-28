import XCTest
@testable import Awesome_Player

/// Tests for the crop geometry math in CropOverlayView. The interactive crop
/// tool maps a drag rect (in view-local points, origin bottom-left) into
/// libvlc's "WIDTHxHEIGHT+X+Y" source-pixel string (origin top-left). Easy to
/// get silently wrong: letterbox/pillarbox detection, Y-axis flip, off-by-one
/// at edges. These tests pin the math against representative inputs.
final class CropOverlayViewTests: XCTestCase {

    // MARK: - Helpers

    private func bounds(_ w: Double, _ h: Double) -> NSRect {
        NSRect(x: 0, y: 0, width: w, height: h)
    }
    private func sel(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> NSRect {
        NSRect(x: x, y: y, width: w, height: h)
    }
    private func size(_ w: Double, _ h: Double) -> NSSize {
        NSSize(width: w, height: h)
    }

    // MARK: - Degenerate inputs

    func testReturnsNilForZeroSourceSize() {
        let r = CropOverlayView.cropGeometry(
            selection: sel(0, 0, 100, 100), viewBounds: bounds(800, 600),
            videoSize: size(0, 0))
        XCTAssertNil(r)
    }

    func testReturnsNilForTinySelection() {
        // Selection < 4pt in either dimension is treated as a misclick.
        let r = CropOverlayView.cropGeometry(
            selection: sel(0, 0, 3, 3), viewBounds: bounds(800, 600),
            videoSize: size(1920, 1080))
        XCTAssertNil(r)
    }

    func testReturnsNilForSelectionOutsideDisplayedVideo() {
        // Source is 1:1 (square) inside a wide view → pillarbox with bars on
        // the sides. A selection entirely inside the left bar must return nil.
        let r = CropOverlayView.cropGeometry(
            selection: sel(0, 0, 50, 600), viewBounds: bounds(800, 600),
            videoSize: size(600, 600))
        // displayed video: x=100..700, y=0..600. Selection x=0..50 is bar-only.
        XCTAssertNil(r)
    }

    // MARK: - No-crop / full-frame selection

    func testFullFrameSelectionReturnsFullSourceRect() {
        // View matches source aspect exactly: no bars. Drag the entire view →
        // crop equals the full source frame.
        let r = CropOverlayView.cropGeometry(
            selection: sel(0, 0, 1920, 1080), viewBounds: bounds(1920, 1080),
            videoSize: size(1920, 1080))
        XCTAssertEqual(r, "1920x1080+0+0")
    }

    // MARK: - Pillarbox (view wider than source)

    func testPillarboxCenterSquareMapsCorrectly() {
        // 600x600 source displayed in 800x600 view → 100pt bars left and
        // right, video runs 100..700 in x. Select the middle 300pt square at
        // view coords (250, 150, 300x300):
        //   - clipped to displayed: x=250..550, y=150..450 (300×300 still)
        //   - relative to displayed origin: (150, 150) → (450, 450) px
        //   - source-px y flip: srcY = 600 - 150 - 300 = 150
        let r = CropOverlayView.cropGeometry(
            selection: sel(250, 150, 300, 300), viewBounds: bounds(800, 600),
            videoSize: size(600, 600))
        XCTAssertEqual(r, "300x300+150+150")
    }

    func testPillarboxSelectionClipsToDisplayedRegion() {
        // Same 600x600-in-800x600 setup. Drag from view x=50 (in the bar) to
        // view x=350 (inside the video). Effective selection clipped to
        // (100..350, 100..400) = 250×300 in view space, then mapped to source
        // pixels. Width scale = 600/600 = 1, so result is 250x300+0+200
        // (Y flipped: 600 - 100 - 300 = 200).
        let r = CropOverlayView.cropGeometry(
            selection: sel(50, 100, 300, 300), viewBounds: bounds(800, 600),
            videoSize: size(600, 600))
        XCTAssertEqual(r, "250x300+0+200")
    }

    // MARK: - Letterbox (view taller than source)

    func testLetterboxCenterRectMapsCorrectly() {
        // 1920×1080 source in a 1920×1500 view → view is taller than source
        // aspect (1.28 vs 1.78), so letterbox bars top/bottom. Displayed video
        // has height 1920/1.7778 ≈ 1080 → bars are (1500-1080)/2 = 210pt each.
        // Video runs y = 210..1290 in view space.
        // Select view (480, 480, 960×540):
        //   - within displayed area (clipped equals input)
        //   - relative origin: (480, 480-210) = (480, 270) in displayed pts
        //   - source scaleX = 1920/1920 = 1, scaleY = 1080/1080 = 1
        //   - srcY = 1080 - 270 - 540 = 270
        let r = CropOverlayView.cropGeometry(
            selection: sel(480, 480, 960, 540), viewBounds: bounds(1920, 1500),
            videoSize: size(1920, 1080))
        XCTAssertEqual(r, "960x540+480+270")
    }

    // MARK: - Source-pixel scaling (view < source size)

    func testScalingFromSmallViewToLargeSource() {
        // 3840x2160 4K source displayed in 1920x1080 view (exact same aspect,
        // so no bars). Select the top-right quadrant of the view (960, 540,
        // 960×540) → maps to 1920×1080 at source x=1920, y=0 (top-right).
        let r = CropOverlayView.cropGeometry(
            selection: sel(960, 540, 960, 540), viewBounds: bounds(1920, 1080),
            videoSize: size(3840, 2160))
        XCTAssertEqual(r, "1920x1080+1920+0")
    }

    // MARK: - Y-axis flip sanity

    func testSelectionAtBottomOfViewBecomesTopOfSource() {
        // View origin is bottom-left; libvlc/AVPlayer want top-left. Select
        // the bottom-left corner of the displayed video — that should become
        // the BOTTOM portion of the source (high Y), not the top.
        // 1920x1080 in 1920x1080: pick (0, 0, 100, 100) → source srcY = 980.
        let r = CropOverlayView.cropGeometry(
            selection: sel(0, 0, 100, 100), viewBounds: bounds(1920, 1080),
            videoSize: size(1920, 1080))
        XCTAssertEqual(r, "100x100+0+980")
    }

    func testSelectionAtTopOfViewBecomesTopOfSource() {
        // Inverse: pick the top-left corner of the displayed video → source
        // Y=0 (the very top of the source frame).
        let r = CropOverlayView.cropGeometry(
            selection: sel(0, 980, 100, 100), viewBounds: bounds(1920, 1080),
            videoSize: size(1920, 1080))
        XCTAssertEqual(r, "100x100+0+0")
    }
}
