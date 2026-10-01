import Foundation

struct RequiredApprovals: Codable, Sendable, Equatable {
    let count: Int?

    init(count: Int?) { self.count = count }

    init(rules: Data?, classic: Data) {
        let ruleset = rules.map(Self.fromRulesets) ?? 0
        let known = Self.fromClassic(classic)
        if let known {
            count = max(known, ruleset)
        } else {
            count = ruleset > 0 ? ruleset : nil
        }
    }

    static func fromRulesets(_ data: Data) -> Int {
        struct Rule: Decodable {
            let type: String
            let parameters: Parameters?
            struct Parameters: Decodable { let required_approving_review_count: Int? }
        }
        let rules = (try? JSONDecoder().decode([Rule].self, from: data)) ?? []
        return rules.filter { $0.type == "pull_request" }
            .compactMap { $0.parameters?.required_approving_review_count }
            .max() ?? 0
    }

    static let seesBranchProtection: Set<String> = ["ADMIN", "MAINTAIN"]

    static func fromClassic(_ data: Data) -> Int? {
        struct Response: Decodable {
            let data: Payload?
            struct Payload: Decodable { let repository: Repo? }
            struct Repo: Decodable {
                let viewerPermission: String?
                let ref: Ref?
            }
            struct Ref: Decodable { let branchProtectionRule: Rule? }
            struct Rule: Decodable { let requiredApprovingReviewCount: Int? }
        }
        guard let repo = (try? JSONDecoder().decode(Response.self, from: data))?.data?.repository else { return nil }
        if let rule = repo.ref?.branchProtectionRule { return rule.requiredApprovingReviewCount ?? 0 }
        return seesBranchProtection.contains(repo.viewerPermission ?? "") ? 0 : nil
    }
}
