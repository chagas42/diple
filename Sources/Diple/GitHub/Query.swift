enum Query {
    /// Uma chamada cobre as três filas. Custa 1 ponto de 5000/hora,
    /// então 60s de intervalo gasta 60 pontos/hora.
    /// Pega 5 comentários porque o último costuma ser bot — o filtro é no cliente.
    static let fila = """
    fragment pr on PullRequest {
      id
      number
      title
      url
      updatedAt
      isDraft
      repository { nameWithOwner }
      author { login __typename }
      reviewDecision
      comments(last: 20) {
        nodes { author { login __typename } createdAt bodyText }
      }
      reviewThreads(last: 20) {
        nodes {
          path
          line
          comments(last: 10) {
            nodes { author { login __typename } createdAt bodyText }
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
