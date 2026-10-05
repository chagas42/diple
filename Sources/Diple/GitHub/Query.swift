enum Query {
    static let prFragment = """
    fragment pr on PullRequest {
      id
      number
      title
      url
      updatedAt
      isDraft
      headRefName
      headRefOid
      baseRefName
      repository { nameWithOwner viewerPermission }
      headRepository { nameWithOwner viewerPermission }
      maintainerCanModify
      mergeable
      author { login __typename avatarUrl(size: 64) }
      reviewDecision
      reviewRequests(first: 20) {
        nodes { requestedReviewer { __typename ... on User { login } } }
      }
      latestReviews(first: 20) {
        nodes { state author { login __typename } }
      }
      comments(last: 20) {
        nodes { author { login __typename } createdAt bodyText }
      }
      reviewThreads(last: 20) {
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          startLine
          comments(last: 10) {
            nodes { author { login __typename } createdAt bodyText diffHunk }
          }
        }
      }
      commits(last: 1) {
        nodes { commit { statusCheckRollup { state } } }
      }
    }
    """

    static func searches(watching: Set<String> = []) -> [Queue.Section: String] {
        var out: [Queue.Section: String] = [
            .mine: "is:open is:pr author:@me sort:updated",
            .toReview: "is:open is:pr review-requested:@me sort:updated",
            .following: "is:open is:pr involves:@me -author:@me sort:updated",
        ]
        let scope = watching.sorted().map { "repo:\($0)" }.joined(separator: " ")
        if !scope.isEmpty { out[.watched] = "is:open is:pr -author:@me \(scope) sort:created-desc" }
        return out
    }

    static func queueSection(_ section: Queue.Section, search: String) -> String {
        prFragment + """
        query QueueSection {
          viewer { login }
          \(section.rawValue): search(query: "\(search)", type: ISSUE, first: 30) {
            nodes { ...pr }
          }
          rateLimit { remaining resetAt }
        }
        """
    }

    static let beatFragment = """
    fragment beat on PullRequest {
      id
      updatedAt
      isDraft
      reviewDecision
      mergeable
      commits(last: 1) {
        nodes { commit { statusCheckRollup { state } } }
      }
    }
    """

    static let heartbeatSearches = [Queue.Section.mine, .toReview, .following].compactMap { searches()[$0] }

    static func heartbeat(_ search: String) -> String {
        beatFragment + """
        query Beat {
          viewer { login }
          section: search(query: "\(search)", type: ISSUE, first: 30) {
            nodes { ...beat }
          }
          rateLimit { remaining resetAt }
        }
        """
    }

    static func details(_ ids: [String]) -> String {
        let list = ids.map { "\"\($0)\"" }.joined(separator: ", ")
        return prFragment + """
        query Detail {
          viewer { login }
          nodes(ids: [\(list)]) { ...pr }
        }
        """
    }
}
