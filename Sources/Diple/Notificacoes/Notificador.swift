import Foundation
import UserNotifications
import AppKit

@MainActor
final class Notificador: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    private let centro = UNUserNotificationCenter.current()
    private let cliente = GitHubClient()

    /// Chamado depois de responder ou resolver, pra fila refletir o que você fez.
    var aoMudar: (() async -> Void)?
    /// A config viva, injetada pelo modelo a cada sincronização.
    var config = Config()

    private enum Cat {
        static let thread = "THREAD"   // dá pra responder
        static let simples = "SIMPLES" // só abre
    }
    private enum Acao {
        static let responder = "RESPONDER"
        static let resolver  = "RESOLVER"
    }

    func instalar() {
        centro.delegate = self

        // O campo de texto vive na categoria, não na notificação: o placeholder
        // é fixo, então tem que ser genérico.
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

    func postar(_ eventos: [Evento]) async {
        for e in eventos where config.deixaPassar(e.tipo) {
            let c = UNMutableNotificationContent()
            c.title = e.titulo
            c.body = e.corpo
            if let som = config.som(e.tipo) {
                c.sound = UNNotificationSound(named: UNNotificationSoundName("\(som).aiff"))
            }
            // Agrupa tudo do mesmo PR num aviso só em vez de empilhar três.
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

    /// Falha silenciosa aqui é pior que ruído: você acha que respondeu e não respondeu.
    private func avisarFalha(_ oQue: String, _ erro: Error) async {
        let c = UNMutableNotificationContent()
        c.title = "\(oQue) não foi enviado"
        c.body = erro.localizedDescription
        c.sound = UNNotificationSound(named: UNNotificationSoundName("Basso.aiff"))
        try? await centro.add(
            UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil)
        )
    }

    // MARK: - Delegate

    // Sem isto, um aviso postado com o app ativo é engolido em silêncio.
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
