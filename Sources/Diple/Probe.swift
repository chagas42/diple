import Foundation
import AppKit

/// `Diple --probe` imprime a fila no terminal. Serve pra depurar a camada
/// de dados sem subir a UI.
enum Probe {
    static func rodar() async {
        do {
            let fila = try await GitHubClient().buscarFila()
            imprimir("MEUS PRS", fila.meus)
            imprimir("PRA REVISAR", fila.revisar)
            imprimir("ENVOLVIDO", fila.envolvido)
            print("\ncota restante: \(fila.cotaRestante)")
        } catch {
            FileHandle.standardError.write(Data("erro: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func imprimir(_ titulo: String, _ prs: [PR]) {
        print("\n## \(titulo) (\(prs.count))")
        for p in prs.prefix(6) {
            let ci: String = switch p.ci {
            case .passou: "verde" case .falhou: "VERMELHO"
            case .rodando: "rodando" case .nenhum: "-"
            }
            var linha = "  \(p.chave.padding(toLength: min(34, max(p.chave.count, 34)), withPad: " ", startingAt: 0))"
            linha += " ci=\(ci.padding(toLength: 9, withPad: " ", startingAt: 0))"
            linha += p.aprovado ? " APROVADO" : "         "
            linha += " \(p.titulo.prefix(46))"
            print(linha)
            if let c = p.ultimoComentario {
                print("      ↳ \(c.autor)\(c.onde.map { " em \($0)" } ?? ""): \(c.trecho.prefix(64))")
            }
        }
    }
}

/// `Diple --notch` mede a tela: serve pra saber se o recorte existe e onde ele está.
@MainActor
enum ProbeNotch {
    static func rodar() {
        for (i, t) in NSScreen.screens.enumerated() {
            let g = Geometria(tela: t)
            print("tela \(i): \(Int(t.frame.width))x\(Int(t.frame.height)) scale \(t.backingScaleFactor)")
            print("  safeAreaInsets.top: \(t.safeAreaInsets.top)")
            print("  tem notch: \(g.temNotch)")
            print("  altura do topo: \(g.alturaTopo)")
            print("  largura do recorte: \(g.larguraNotch)")
            if let e = t.auxiliaryTopLeftArea, let d = t.auxiliaryTopRightArea {
                print("  área à esquerda: \(Int(e.width))  à direita: \(Int(d.width))")
            } else {
                print("  áreas auxiliares: nenhuma (tela sem recorte)")
            }
            print("  fechado:   \(g.fechado)  -> \(g.retangulo(g.fechado))")
            print("  atividade: \(g.atividade)  -> \(g.retangulo(g.atividade))")
            print("  aberto:    \(g.aberto)  -> \(g.retangulo(g.aberto))")
            print("  janela fixa: \(g.janela())")
        }
    }
}
