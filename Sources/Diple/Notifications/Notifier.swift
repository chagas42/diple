import Foundation
@preconcurrency import UserNotifications
import AppKit

@MainActor
final class Notifier: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let client = GitHubClient()

    var onChange: (() async -> Void)?

    var settings = Settings()

    private enum Cat {
        static let thread = "THREAD"
        static let simples = "SIMPLES"
    }
    private enum Acao {
        static let reply = "RESPONDER"
        static let resolve  = "RESOLVER"
    }

    func install() {
        center.delegate = self

        let reply = UNTextInputNotificationAction(
            identifier: Acao.reply,
            title: "Responder",
            options: [],
            textInputButtonTitle: "Enviar",
            textInputPlaceholder: "Write your reply…"
        )
        let resolve = UNNotificationAction(
            identifier: Acao.resolve,
            title: "Resolver thread",
            options: []
        )

        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Cat.thread,
                actions: [reply, resolve],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: Cat.simples,
                actions: [],
                intentIdentifiers: [],
                options: []
            ),
        ])
    }

    @discardableResult
    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    nonisolated func isAuthorized() async -> Bool {
        await withCheckedContinuation { cont in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                cont.resume(returning: settings.authorizationStatus == .authorized)
            }
        }
    }

    func post(_ events: [Event], force: Bool = false) async {
        guard !Bench.isOn else { return }
        for e in events where force || settings.shouldInterrupt(e.kind) {
            let c = UNMutableNotificationContent()
            c.title = e.title
            c.body = e.body
            if let sound = force ? (settings.sounds[e.kind.rawValue] ?? e.kind.sound) ?? e.kind.sound
                                   : settings.sound(e.kind) {
                c.sound = UNNotificationSound(named: UNNotificationSoundName("\(sound).aiff"))
            }

            c.threadIdentifier = e.key
            c.categoryIdentifier = e.threadId == nil ? Cat.simples : Cat.thread
            c.userInfo = [
                "url": e.url.absoluteString,
                "threadId": e.threadId ?? "",
            ]
            try? await center.add(
                UNNotificationRequest(identifier: e.id, content: c, trigger: nil)
            )
        }
    }

    private func reportFailure(_ what: String, _ error: Error) async {
        let c = UNMutableNotificationContent()
        c.title = "\(what) was not sent"
        c.body = error.localizedDescription
        c.sound = UNNotificationSound(named: UNNotificationSoundName("Basso.aiff"))
        try? await center.add(
            UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil)
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        let thread = (info["threadId"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        switch response.actionIdentifier {
        case Acao.reply:
            guard let text = (response as? UNTextInputNotificationResponse)?.userText
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty, let thread else { return }
            do {
                try await client.reply(threadId: thread, body: text)
                await onChange?()
            } catch {
                await reportFailure("Your comment", error)
            }

        case Acao.resolve:
            guard let thread else { return }
            do {
                try await client.resolve(threadId: thread)
                await onChange?()
            } catch {
                await reportFailure("Resolving the thread", error)
            }

        default:
            if let s = info["url"] as? String, let url = URL(string: s) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
