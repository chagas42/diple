import Foundation
import Testing
@testable import Diple

@MainActor
@Suite struct ApprovalTests {
    func classic(_ permission: String, rule: String?) -> Data {
        let ref = rule.map { #"{"branchProtectionRule":\#($0)}"# } ?? #"{"branchProtectionRule":null}"#
        return Data(#"{"data":{"repository":{"viewerPermission":"\#(permission)","ref":\#(ref)}}}"#.utf8)
    }

    let rulesets = Data(#"[{"type":"deletion"},{"type":"pull_request","parameters":{"required_approving_review_count":1}},{"type":"pull_request","parameters":{"required_approving_review_count":2}}]"#.utf8)

    @Test func theStrictestRulesetWins() {
        #expect(RequiredApprovals.fromRulesets(rulesets) == 2)
        #expect(RequiredApprovals.fromRulesets(Data("[]".utf8)) == 0)
    }

    @Test func aClassicRuleSeenByAnAdminCounts() {
        let r = RequiredApprovals(rules: Data("[]".utf8), classic: classic("ADMIN", rule: #"{"requiredApprovingReviewCount":3}"#))
        #expect(r.count == 3)
    }

    @Test func anAdminWithNoRuleNeedsNone() {
        let r = RequiredApprovals(rules: Data("[]".utf8), classic: classic("ADMIN", rule: nil))
        #expect(r.count == 0)
    }

    @Test func aReaderSeesOnlyRulesets() {
        #expect(RequiredApprovals(rules: Data("[]".utf8), classic: classic("READ", rule: nil)).count == nil)
        #expect(RequiredApprovals(rules: rulesets, classic: classic("WRITE", rule: nil)).count == 2)
    }

    @Test func botsAndTheAuthorDoNotCount() {
        let raw = #"{"nodes":[{"state":"APPROVED","author":{"login":"ana","__typename":"User"}},{"state":"APPROVED","author":{"login":"coderabbitai","__typename":"Bot"}},{"state":"COMMENTED","author":{"login":"me","__typename":"User"}},{"state":"CHANGES_REQUESTED","author":{"login":"bia","__typename":"User"}},{"state":"PENDING","author":{"login":"caio","__typename":"User"}}]}"#
        let reviews = try! JSONDecoder().decode(RawPR.RawReviews.self, from: Data(raw.utf8))
        #expect(PR.counted(reviews, author: "me") == ["APPROVED", "CHANGES_REQUESTED"])
        let none = try! JSONDecoder().decode(RawPR.RawReviews.self, from: Data(#"{"nodes":[]}"#.utf8))
        #expect(PR.counted(none, author: "me") == [])
    }

    func pr(approvals: Int?, reviewed: Bool? = nil, draft: Bool = false) -> PR {
        PR(id: "x", repo: "o/r", number: 1, title: "t", url: URL(string: "https://github.com")!,
           updatedAt: Date(), createdAt: Date(), draft: draft, author: "a", authorAvatar: nil, isMine: false,
           headRef: "h", baseRef: "main", checks: .none, approved: false, threads: [], lastComment: nil,
           approvals: approvals, reviewedByOthers: reviewed)
    }

    @Test func theBadgeReadsAgainstTheRequirement() {
        #expect(ApprovalCount(pr: pr(approvals: 1), required: 2)?.text == "1/2")
        #expect(ApprovalCount(pr: pr(approvals: 1), required: 2)?.met == false)
        #expect(ApprovalCount(pr: pr(approvals: 2), required: 2)?.met == true)
        #expect(ApprovalCount(pr: pr(approvals: 0), required: 2)?.text == "0/2")
        #expect(ApprovalCount(pr: pr(approvals: 1), required: nil)?.text == "1")
        #expect(ApprovalCount(pr: pr(approvals: 1), required: 0)?.text == "1")
        #expect(ApprovalCount(pr: pr(approvals: 0), required: nil) == nil)
        #expect(ApprovalCount(pr: pr(approvals: 1, draft: true), required: 2) == nil)
        #expect(ApprovalCount(pr: pr(approvals: nil), required: 2) == nil)
    }

    @Test func onlyAPRNobodyReviewedHasNoReviews() {
        #expect(pr(approvals: 0, reviewed: false).hasNoReviews)
        #expect(!pr(approvals: 0, reviewed: true).hasNoReviews)
        #expect(!pr(approvals: nil, reviewed: nil).hasNoReviews)
    }
}
