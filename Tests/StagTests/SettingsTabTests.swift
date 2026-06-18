import XCTest
@testable import Stag

/// Tab presentation metadata extracted from PreferencesView.
final class SettingsTabTests: XCTestCase {

    func testAllSixTabsPresentInOrder() {
        XCTAssertEqual(SettingsTab.allCases.map(\.rawValue),
                       ["general", "capture", "recording", "overlays", "shortcuts", "advanced"])
    }

    func testEveryTabHasNonEmptyMetadata() {
        for tab in SettingsTab.allCases {
            XCTAssertFalse(tab.icon.isEmpty, "\(tab) icon")
            XCTAssertFalse(tab.label.isEmpty, "\(tab) label")
            XCTAssertFalse(tab.subtitle.isEmpty, "\(tab) subtitle")
        }
    }

    func testLabelsAndIconsAreUnique() {
        let labels = SettingsTab.allCases.map(\.label)
        XCTAssertEqual(Set(labels).count, labels.count)
        let icons = SettingsTab.allCases.map(\.icon)
        XCTAssertEqual(Set(icons).count, icons.count)
    }

    func testSpotChecks() {
        XCTAssertEqual(SettingsTab.general.label, "General")
        XCTAssertEqual(SettingsTab.recording.icon, "video.fill")
        XCTAssertEqual(SettingsTab.shortcuts.subtitle, "Global hotkeys and editor tool keys.")
    }
}
