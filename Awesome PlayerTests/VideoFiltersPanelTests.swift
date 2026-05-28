import XCTest
@testable import Awesome_Player

/// Tests for VideoFiltersPanelController.buildFilterChainOption — the string
/// assembly that produces the libvlc `:video-filter=...` media option.
///
/// The actual filter modules ("sharpen", "grain", "posterize") are libvlc
/// module names — a typo here means the filter silently doesn't apply. These
/// tests pin the wire format so a future refactor can't quietly break it.
///
/// Uses an isolated `UserDefaults(suiteName:)` so test runs don't leak filter
/// state into the user's real preferences.
final class VideoFiltersPanelTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "VideoFiltersPanelTests.suite"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testEmptyChainReturnsNil() {
        // No filters enabled → no `:video-filter=` option at all, which is
        // semantically different from `:video-filter=` (empty chain).
        XCTAssertNil(VideoFiltersPanelController.buildFilterChainOption(defaults: defaults))
    }

    func testSingleUnparameterizedFilter() {
        defaults.set(true, forKey: Defaults.filterInvert)
        XCTAssertEqual(
            VideoFiltersPanelController.buildFilterChainOption(defaults: defaults),
            "invert")
    }

    func testSharpenIncludesSigmaWithTwoDecimals() {
        defaults.set(true, forKey: Defaults.filterSharpen)
        defaults.set(1.5, forKey: Defaults.filterSharpenSigma)
        XCTAssertEqual(
            VideoFiltersPanelController.buildFilterChainOption(defaults: defaults),
            "sharpen{sigma=1.50}")
    }

    func testSharpenDefaultsToHalfWhenSigmaUnset() {
        // Toggle on but never set sigma — must fall back to a sane default
        // instead of emitting `sigma=0.00` which produces no visible effect.
        defaults.set(true, forKey: Defaults.filterSharpen)
        // Sigma deliberately not set
        XCTAssertEqual(
            VideoFiltersPanelController.buildFilterChainOption(defaults: defaults),
            "sharpen{sigma=0.50}")
    }

    func testGrainDefaultsToOneWhenVarianceUnset() {
        defaults.set(true, forKey: Defaults.filterGrain)
        XCTAssertEqual(
            VideoFiltersPanelController.buildFilterChainOption(defaults: defaults),
            "grain{variance=1.00}")
    }

    func testMultipleFiltersJoinedWithColons() {
        defaults.set(true, forKey: Defaults.filterSharpen)
        defaults.set(0.8, forKey: Defaults.filterSharpenSigma)
        defaults.set(true, forKey: Defaults.filterPosterize)
        defaults.set(true, forKey: Defaults.filterMirror)
        // Order matches the source listing: sharpen, grain, posterize, invert,
        // mirror. Pinning this order matters — libvlc applies filters
        // sequentially, so order is semantic, not cosmetic.
        XCTAssertEqual(
            VideoFiltersPanelController.buildFilterChainOption(defaults: defaults),
            "sharpen{sigma=0.80}:posterize:mirror")
    }

    func testAllFiltersEnabled() {
        for key in [Defaults.filterSharpen, Defaults.filterGrain,
                    Defaults.filterPosterize, Defaults.filterInvert, Defaults.filterMirror] {
            defaults.set(true, forKey: key)
        }
        defaults.set(0.5, forKey: Defaults.filterSharpenSigma)
        defaults.set(2.0, forKey: Defaults.filterGrainVariance)
        XCTAssertEqual(
            VideoFiltersPanelController.buildFilterChainOption(defaults: defaults),
            "sharpen{sigma=0.50}:grain{variance=2.00}:posterize:invert:mirror")
    }
}
