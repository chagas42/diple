import Foundation
import Intents

@MainActor
final class Focus: ObservableObject {
    @Published var byHand = false
    @Published private(set) var system = false

    var isOn: Bool { byHand || system }

    var follows = true {
        didSet { if follows != oldValue { follows ? start() : stop() } }
    }

    var read: @MainActor () -> Bool? = {
        let center = INFocusStatusCenter.default
        guard center.authorizationStatus == .authorized else { return nil }
        return center.focusStatus.isFocused
    }

    var every: Duration = .seconds(5)
    private var watch: Task<Void, Never>?

    func toggle() {
        byHand.toggle()
    }

    func start() {
        guard follows, watch == nil else { return }
        if INFocusStatusCenter.default.authorizationStatus == .notDetermined {
            INFocusStatusCenter.default.requestAuthorization { _ in
                Task { @MainActor [weak self] in self?.check() }
            }
        }
        watch = Task { [weak self] in
            while !Task.isCancelled {
                self?.check()
                guard let every = self?.every else { return }
                try? await Task.sleep(for: every)
            }
        }
    }

    func stop() {
        watch?.cancel()
        watch = nil
        system = false
    }

    func check() {
        let now = follows && read() == true
        if now != system { system = now }
    }
}
