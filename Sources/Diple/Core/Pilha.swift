import Foundation

/// Uma pilha de PRs empilhados: a base de um é o topo do anterior.
/// Quem usa git-spice, Graphite ou empilha na mão acaba com dezenas destes,
/// e listá-los soltos esconde que precisam ser lidos em ordem.
struct Pilha: Identifiable, Sendable {
    let prs: [PR]
    var id: String { prs.first?.chave ?? UUID().uuidString }
    var empilhada: Bool { prs.count > 1 }
    var base: PR? { prs.first }
}

extension Array where Element == PR {
    /// Encadeia por ramo: se o `ramoBase` de um PR é o `ramo` de outro do
    /// mesmo repositório, eles são a mesma pilha, e a ordem importa.
    func emPilhas() -> [Pilha] {
        // A chave inclui o repositório: nomes de ramo se repetem entre repos.
        var porRamo: [String: PR] = [:]
        for pr in self { porRamo["\(pr.repo)/\(pr.ramo)"] = pr }

        let temFilho = Set(compactMap { pr -> String? in
            let chave = "\(pr.repo)/\(pr.ramoBase)"
            return porRamo[chave] != nil ? chave : nil
        })

        var usados = Set<String>()
        var pilhas: [Pilha] = []

        // Começa por quem não é base de ninguém: o topo da pilha.
        for pr in self where !temFilho.contains("\(pr.repo)/\(pr.ramo)") {
            guard !usados.contains(pr.chave) else { continue }
            var cadeia: [PR] = []
            var atual: PR? = pr
            while let p = atual, !usados.contains(p.chave) {
                usados.insert(p.chave)
                cadeia.append(p)
                atual = porRamo["\(p.repo)/\(p.ramoBase)"]
            }
            // Montada do topo pra base; inverte pra ler de baixo pra cima.
            pilhas.append(Pilha(prs: cadeia.reversed()))
        }

        // Sobra o que ficou preso em ciclo ou já consumido no meio.
        for pr in self where !usados.contains(pr.chave) {
            usados.insert(pr.chave)
            pilhas.append(Pilha(prs: [pr]))
        }
        return pilhas
    }
}
