import AppKit

/// Janela sem moldura que vive acima de tudo, inclusive de app em tela cheia,
/// e que nunca rouba o foco do que você está fazendo.
final class NotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        // fullScreenAuxiliary é o que faz o painel sobreviver a app em tela cheia.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        acceptsMouseMovedEvents = true
        // Sem isto, um painel que não ativa exige um clique só pra "acordar"
        // antes de o botão receber o segundo. É o clique que não pega.
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }   // aceita digitar a resposta
    override var canBecomeMain: Bool { false } // mas nunca vira a janela principal
}
