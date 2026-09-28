import Combine
import Foundation
import Testing
@testable import Diple

@MainActor
@Suite struct EyeTests {
    @Test func movingTheEyeDoesNotInvalidateTheNotch() {
        let notch = NotchController()
        var notchChanges = 0
        var eyeChanges = 0
        let a = notch.objectWillChange.sink { notchChanges += 1 }
        let b = notch.eye.objectWillChange.sink { eyeChanges += 1 }
        for i in 1...30 { notch.eye.look(at: CGPoint(x: Double(i) / 30, y: 0)) }
        notch.eye.blinking = true
        #expect(notchChanges == 0)
        #expect(eyeChanges == 31)
        _ = (a, b)
    }

    @Test func tinyMovementsAreIgnored() {
        let eye = EyeState()
        var changes = 0
        let c = eye.objectWillChange.sink { changes += 1 }
        eye.look(at: CGPoint(x: 0.005, y: 0.005))
        eye.look(at: CGPoint(x: 0.5, y: 0))
        eye.look(at: CGPoint(x: 0.505, y: 0))
        #expect(changes == 1)
        #expect(eye.gaze == CGPoint(x: 0.5, y: 0))
        _ = c
    }
}
