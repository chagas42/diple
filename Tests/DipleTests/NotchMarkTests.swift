import Foundation
import Testing
@testable import Diple

@Suite struct NotchMarkTests {
    static func decode(_ json: String) throws -> Settings {
        try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
    }

    @Test func whoeverTurnedTheEyeOffGetsTheTray() throws {
        #expect(try Self.decode(#"{"showsEye": false}"#).notchMark == .tray)
        #expect(try Self.decode(#"{"showsEye": true}"#).notchMark == .eye)
        #expect(try Self.decode("{}").notchMark == .eye)
    }

    @Test func aPickedMarkWinsOverTheOldSwitch() throws {
        #expect(try Self.decode(#"{"showsEye": true, "notchMark": "tray"}"#).notchMark == .tray)
        #expect(try Self.decode(#"{"notchMark": "nonsense"}"#).notchMark == .eye)
    }

    @Test func theMarkSurvivesASaveAndTheOldSwitchIsGone() throws {
        var s = Settings()
        s.notchMark = .tray
        let data = try JSONEncoder().encode(s)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["notchMark"] as? String == "tray")
        #expect(json["showsEye"] == nil)
        #expect(try JSONDecoder().decode(Settings.self, from: data).notchMark == .tray)
    }

    @Test func noMarkAtAllSurvivesASaveAndStillTeachesTheTrayInOnboarding() throws {
        var s = Settings()
        s.notchMark = .blank
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(Settings.self, from: data).notchMark == .blank)
        #expect(!s.showsEye)
        #expect(NotchMark.blank.noun == "tray")
    }

    @Test func theEyeIsTheDefaultAndTurningItOffLeavesTheTray() {
        var s = Settings()
        #expect(s.notchMark == .eye)
        s.showsEye = false
        #expect(s.notchMark == .tray)
        s.showsEye = true
        #expect(s.notchMark == .eye)
    }

    @Test func theTrayFillsWithWorkAndBecomesTheMoonInFocus() {
        #expect(TrayMark.symbol(count: 3, focused: false) == "tray.full.fill")
        #expect(TrayMark.symbol(count: 0, focused: false) == "tray")
        #expect(TrayMark.symbol(count: 3, focused: true) == "moon.fill")
    }

    @Test func theOneTrickNamesTheMarkToClick() {
        #expect(NotchMark.tray.noun == "tray")
        #expect(NotchMark.eye.noun == "eye")
    }
}
