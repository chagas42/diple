import Foundation

struct RepoRef: Codable, Sendable, Hashable, Identifiable {
    let nameWithOwner: String
    let owner: String
    let isOrg: Bool
    let isPrivate: Bool

    var id: String { nameWithOwner }
    var name: String { String(nameWithOwner.split(separator: "/").last ?? "") }
}

private struct ReposResponse: Decodable, Sendable {
    let data: Payload?
    let errors: [GraphQLError]?

    struct Payload: Decodable, Sendable { let viewer: Viewer }
    struct Viewer: Decodable, Sendable { let repositories: Page }
    struct Page: Decodable, Sendable {
        let pageInfo: PageInfo
        let nodes: [Node?]
    }
    struct PageInfo: Decodable, Sendable {
        let hasNextPage: Bool
        let endCursor: String?
    }
    struct Node: Decodable, Sendable {
        let nameWithOwner: String
        let isPrivate: Bool
        let owner: Owner
    }
    struct Owner: Decodable, Sendable {
        let login: String
        let __typename: String
    }
}

private struct RepoPRsResponse: Decodable, Sendable {
    let data: Payload?
    let errors: [GraphQLError]?

    struct Payload: Decodable, Sendable {
        let viewer: RawResponse.RawViewer
        let repository: Repo?
    }
    struct Repo: Decodable, Sendable { let pullRequests: Page }
    struct Page: Decodable, Sendable { let nodes: [RawPR?] }
}

extension GitHubClient {
    func fetchRepos() async throws -> [RepoRef] {
        var out: [RepoRef] = []
        var cursor: String?

        for _ in 0..<6 {
            let after = cursor.map { "\"\($0)\"" } ?? "null"
            let query = """
            { viewer { repositories(
                first: 100, after: \(after),
                affiliations: [OWNER, COLLABORATOR, ORGANIZATION_MEMBER],
                ownerAffiliations: [OWNER, COLLABORATOR, ORGANIZATION_MEMBER],
                orderBy: {field: PUSHED_AT, direction: DESC}
              ) {
                pageInfo { hasNextPage endCursor }
                nodes { nameWithOwner isPrivate owner { login __typename } }
              } } }
            """
            let body: ReposResponse = try await send(query)
            if let e = body.errors, !e.isEmpty { throw ClientError.graphql(e.map(\.message)) }
            guard let page = body.data?.viewer.repositories else { break }

            for n in page.nodes.compactMap({ $0 }) {
                out.append(RepoRef(
                    nameWithOwner: n.nameWithOwner,
                    owner: n.owner.login,
                    isOrg: n.owner.__typename == "Organization",
                    isPrivate: n.isPrivate
                ))
            }
            guard page.pageInfo.hasNextPage, let next = page.pageInfo.endCursor else { break }
            cursor = next
        }
        return out
    }

    func fetchRepoPRs(_ nameWithOwner: String) async throws -> [PR] {
        let parts = nameWithOwner.split(separator: "/")
        guard parts.count == 2 else { return [] }

        let query = Query.prFragment + """
        query RepoPRs {
          viewer { login }
          repository(owner: "\(parts[0])", name: "\(parts[1])") {
            pullRequests(states: OPEN, first: 50, orderBy: {field: UPDATED_AT, direction: DESC}) {
              nodes { ...pr }
            }
          }
        }
        """
        let body: RepoPRsResponse = try await send(query)
        if let e = body.errors, !e.isEmpty { throw ClientError.graphql(e.map(\.message)) }
        guard let d = body.data else { throw ClientError.empty }
        let viewer = d.viewer.login
        return (d.repository?.pullRequests.nodes ?? []).compactMap { PR($0, viewerLogin: viewer) }
    }
}
