import Foundation

struct Pilha: Identifiable, Sendable {
    let prs: [PR]
    var id: String { prs.first?.chave ?? UUID().uuidString }
    var empilhada: Bool { prs.count > 1 }
    var base: PR? { prs.first }
}

extension Array where Element == PR {
    func emPilhas() -> [Pilha] {
        var porRamo: [String: PR] = [:]
        for pr in self { porRamo["\(pr.repo)/\(pr.ramo)"] = pr }

        let temFilho = Set(compactMap { pr -> String? in
            let chave = "\(pr.repo)/\(pr.ramoBase)"
            return porRamo[chave] != nil ? chave : nil
        })

        var usados = Set<String>()
        var pilhas: [Pilha] = []

        for pr in self where !temFilho.contains("\(pr.repo)/\(pr.ramo)") {
            guard !usados.contains(pr.chave) else { continue }
            var cadeia: [PR] = []
            var atual: PR? = pr
            while let p = atual, !usados.contains(p.chave) {
                usados.insert(p.chave)
                cadeia.append(p)
                atual = porRamo["\(p.repo)/\(p.ramoBase)"]
            }

            pilhas.append(Pilha(prs: cadeia.reversed()))
        }

        for pr in self where !usados.contains(pr.chave) {
            usados.insert(pr.chave)
            pilhas.append(Pilha(prs: [pr]))
        }
        return pilhas
    }
}
