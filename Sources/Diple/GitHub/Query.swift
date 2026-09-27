enum Query {
    static let fila = """
    fragment pr on PullRequest {
      id
      number
      title
      url
      updatedAt
      isDraft
      headRefName
      baseRefName
      repository { nameWithOwner }
      author { login __typename avatarUrl(size: 64) }
      reviewDecision
      comments(last: 20) {
        nodes { author { login __typename } createdAt bodyText }
      }
      reviewThreads(last: 20) {
        nodes {
          id
          isResolved
          path
          line
          comments(last: 10) {
            nodes { author { login __typename } createdAt bodyText diffHunk }
          }
        }
      }
      commits(last: 1) {
        nodes { commit { statusCheckRollup { state } } }
      }
    }
    query Fila {
      viewer { login }
      meus: search(query: "is:open is:pr author:@me sort:updated", type: ISSUE, first: 30) {
        nodes { ...pr }
      }
      revisar: search(query: "is:open is:pr review-requested:@me sort:updated", type: ISSUE, first: 30) {
        nodes { ...pr }
      }
      envolvido: search(query: "is:open is:pr involves:@me -author:@me sort:updated", type: ISSUE, first: 30) {
        nodes { ...pr }
      }
      rateLimit { remaining resetAt }
    }
    """
}
