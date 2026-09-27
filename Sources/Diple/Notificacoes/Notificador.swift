import Foundation
import UserNotifications
import AppKit

@MainActor
final class Notificador: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    private let centro = UNUserNotificationCenter.current()
    private let cliente = GitHubClient()

    var aoMudar: (() async -> Void)?

    var config = Config()

    private enum Cat {
        static let thread = "THREAD"
        static let simples = "SIMPLES"
    }
    private enum Acao {
        static let responder = "RESPONDER"
        static let resolver  = "RESOLVER"
    }

    func instalar() {
        centro.delegate = self

        let responder = UNTextInputNotificationAction(
            identifier: Acao.responder,
            title: "Responder",
            options: [],
            textInputButtonTitle: "Enviar",
            textInputPlaceholder: "Escreva sua resposta…"
        )
        let resolver = UNNotificationAction(
            identifier: Acao.resolver,
            title: "Resolver thread",
            options: []
        )

        centro.setNotificationCategories([
            UNNotificationCategory(
                identifier: Cat.thread,
                actions: [responder, resolver],
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
    func pedirPermissao() async -> Bool {
        (try? await centro.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func autorizado() async -> Bool {
        await centro.notificationSettings().authorizationStatus == .authorized
    }

    func postar(_ eventos: [Evento], forcando: Bool = false) async {
        for e in eventos where forcando || config.deixaPassar(e.tipo) {
            let c = UNMutableNotificationContent()
            c.title = e.titulo
            c.body = e.corpo
            if let som = forcando ? (config.sons[e.tipo.rawValue] ?? e.tipo.som) ?? e.tipo.som
                                   : config.som(e.tipo) {
                c.sound = UNNotificationSound(named: UNNotificationSoundName("\(som).aiff"))
            }

            c.threadIdentifier = e.chave
            c.categoryIdentifier = e.threadId == nil ? Cat.simples : Cat.thread
            c.userInfo = [
                "url": e.url.absoluteString,
                "threadId": e.threadId ?? "",
            ]
            try? await centro.add(
                UNNotificationRequest(identifier: e.id, content: c, trigger: nil)
            )
        }
    }

    private func avisarFalha(_ oQue: String, _ erro: Error) async {
        let c = UNMutableNotificationContent()
        c.title = "\(oQue) não foi enviado"
        c.body = erro.localizedDescription
        c.sound = UNNotificationSound(named: UNNotificationSoundName("Basso.aiff"))
        try? await centro.add(
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
        case Acao.responder:
            guard let texto = (response as? UNTextInputNotificationResponse)?.userText
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !texto.isEmpty, let thread else { return }
            do {
                try await cliente.responder(threadId: thread, corpo: texto)
                await aoMudar?()
            } catch {
                await avisarFalha("Seu comentário", error)
            }

        case Acao.resolver:
            guard let thread else { return }
            do {
                try await cliente.resolver(threadId: thread)
                await aoMudar?()
            } catch {
                await avisarFalha("O resolve da thread", error)
            }

        default:
            if let s = info["url"] as? String, let url = URL(string: s) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
