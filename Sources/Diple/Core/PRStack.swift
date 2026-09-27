import Foundation

struct PRStack: Identifiable, Sendable {
    let prs: [PR]
    var id: String { prs.first?.key ?? UUID().uuidString }
    var isStack: Bool { prs.count > 1 }
    var base: PR? { prs.first }
}

extension Array where Element == PR {
    func groupedIntoStacks() -> [PRStack] {
        var byRef: [String: PR] = [:]
        for pr in self { byRef["\(pr.repo)/\(pr.headRef)"] = pr }

        let hasChild = Set(compactMap { pr -> String? in
            let key = "\(pr.repo)/\(pr.baseRef)"
            return byRef[key] != nil ? key : nil
        })

        var used = Set<String>()
        var stacks: [PRStack] = []

        for pr in self where !hasChild.contains("\(pr.repo)/\(pr.headRef)") {
            guard !used.contains(pr.key) else { continue }
            var chain: [PR] = []
            var current: PR? = pr
            while let p = current, !used.contains(p.key) {
                used.insert(p.key)
                chain.append(p)
                current = byRef["\(p.repo)/\(p.baseRef)"]
            }

            stacks.append(PRStack(prs: chain.reversed()))
        }

        for pr in self where !used.contains(pr.key) {
            used.insert(pr.key)
            stacks.append(PRStack(prs: [pr]))
        }
        return stacks
    }
}
