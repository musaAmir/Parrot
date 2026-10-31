import XCTest
@testable import ParrotCore

final class PanelPlacementTests: XCTestCase {
    @MainActor func testPanelShapePersistsAndUnknownValuesUseExistingStyle() {
        let name = "ParrotPanelTests-\(UUID())", defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let manager = AudioManager(defaults: defaults)
        XCTAssertEqual(manager.panelShape, .squared)
        manager.panelShape = .rounded
        manager.saveSettings()
        XCTAssertEqual(AudioManager(defaults: defaults).panelShape, .rounded)
        defaults.set("unknown-future-shape", forKey: "panelShape")
        XCTAssertEqual(AudioManager(defaults: defaults).panelShape, .squared)
    }

    func testCentersOnOffsetDisplayRatherThanAssumingMainDisplayOrigin() {
        let screen = CGRect(x: 1440, y: -200, width: 1920, height: 1080)
        for anchor in [PanelPlacement.Anchor.top, .bottom] {
            let frame = PanelPlacement.frame(size: CGSize(width: 352, height: 68), screen: screen, anchor: anchor)
            XCTAssertEqual(frame.midX, screen.midX)
            XCTAssertTrue(screen.contains(frame))
        }
    }
    func testControlWidthChangePreservesVisibleCenter() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let initial = CGRect(x: 600, y: 700, width: 240, height: 68)
        let expanded = PanelPlacement.resized(initial, to: CGSize(width: 352, height: 68), screen: screen)
        XCTAssertEqual(expanded.midX, initial.midX)
        XCTAssertEqual(expanded.midY, initial.midY)
    }
    func testSavedPositionIsClampedToVisibleScreen() {
        let screen = CGRect(x: -1920, y: 25, width: 1920, height: 1055)
        let frame = PanelPlacement.frame(size: CGSize(width: 352, height: 68), screen: screen, anchor: .top,
                                         savedCenter: CGPoint(x: -10, y: 1070))
        XCTAssertTrue(screen.contains(frame))
        XCTAssertEqual(frame.maxX, screen.maxX)
        XCTAssertEqual(frame.maxY, screen.maxY)
    }
    func testInvalidSavedPositionUsesDefaultPlacement() {
        let screen = CGRect(x: 100, y: 100, width: 1440, height: 900)
        let frame = PanelPlacement.frame(size: CGSize(width: 352, height: 68), screen: screen, anchor: .top,
                                         savedCenter: CGPoint(x: CGFloat.nan, y: CGFloat.infinity))
        XCTAssertTrue(screen.contains(frame))
        XCTAssertEqual(frame.midX, screen.midX)
    }
}
