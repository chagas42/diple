import Foundation
import UserNotifications
import AppKit

@MainActor
final class Notificador: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    private let centro = UNUserNotificationCenter.current()

    func instalar() {
        centro.delegate = self
    }

    @discardableResult
    func pedirPermissao() async -> Bool {
        (try? await centro.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func autorizado() async -> Bool {
        await centro.notificationSettings().authorizationStatus == .authorized
    }

    func postar(_ eventos: [Evento]) async {
        for e in eventos where e.tipo.interrompe {
            let c = UNMutableNotificationContent()
            c.title = e.titulo
            c.body = e.corpo
            if let som = e.tipo.som {
                c.sound = UNNotificationSound(named: UNNotificationSoundName("\(som).aiff"))
            }
            // Agrupa tudo do mesmo PR num aviso só, em vez de empilhar três.
            c.threadIdentifier = e.chave
            c.userInfo = ["url": e.url.absoluteString]

            let req = UNNotificationRequest(identifier: e.id, content: c, trigger: nil)
            try? await centro.add(req)
        }
    }

    // Sem isto, um aviso postado com o app ativo é engolido em silêncio.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    // Clicar no banner abre o PR.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let s = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: s) else { return }
        NSWorkspace.shared.open(url)
    }
}
