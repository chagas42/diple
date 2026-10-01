import Foundation

enum Demo {
    static var isOn: Bool { CommandLine.arguments.contains("--demo") }

    private static let viewer = "you"

    private static func avatar(_ login: String) -> URL? { nil }

    private static func ago(_ minutes: Double) -> Date {
        Date().addingTimeInterval(-minutes * 60)
    }

    private static func pr(
        _ repo: String, _ number: Int, _ title: String,
        author: String, mine: Bool,
        checks: CheckState = .passing, approved: Bool = false, draft: Bool = false,
        minutes: Double, head: String, base: String = "main",
        reply: (String, String, Int, String)? = nil,
        askedYou: Bool = false
    ) -> PR {
        var threads: [PR.ReviewThread] = []
        var last: PR.HumanComment?

        if let (who, path, line, text) = reply {
            let thread = PR.ReviewThread(
                id: "T\(repo)\(number)",
                path: path,
                line: line,
                diffHunk: """
                @@ -\(line - 2),6 +\(line - 2),8 @@
                   const account = await this.repository.findById(id)
                -  if (!account) return null
                +  if (!account) {
                +    throw new PhoneAccountNotFound(id)
                +  }
                """,
                outdated: false,
                comments: [
                    PR.ThreadComment(
                        id: "C\(number)a", author: who, at: ago(minutes),
                        text: text, isBot: false
                    )
                ]
            )
            threads = [thread]
            last = PR.HumanComment(
                author: who, at: ago(minutes), excerpt: text,
                location: thread.location, threadId: thread.id
            )
        }

        return PR(
            id: "\(repo)#\(number)",
            repo: repo,
            number: number,
            title: title,
            url: URL(string: "https://github.com/\(repo)/pull/\(number)")!,
            updatedAt: ago(minutes),
            createdAt: ago(minutes * 3 + 120),
            draft: draft,
            author: author,
            authorAvatar: avatar(author),
            isMine: mine,
            headRef: head,
            baseRef: base,
            checks: checks,
            approved: approved,
            threads: threads,
            lastComment: last,
            askedYou: askedYou
        )
    }

    static var queue: Queue {
        Queue(
            viewer: viewer,
            mine: [
                pr("acme/orders-api", 7842, "feat: charge trial accounts again once they convert",
                   author: viewer, mine: true, checks: .failing, minutes: 12,
                   head: "you/bill-demo-companies",
                   reply: ("rafa-mendes", "src/orders/refund-policy.ts", 27,
                           "This marks trial accounts as overdue too. Wouldn't it be better to handle it in the skip reason?")),
                pr("acme/orders-api", 7843, "feat: keep internal accounts out of dunning",
                   author: viewer, mine: true, approved: true, minutes: 48,
                   head: "you/skip-own-companies", base: "you/bill-demo-companies"),
                pr("acme/orders-api", 7841, "feat: never charge internal accounts for overage",
                   author: viewer, mine: true, minutes: 95,
                   head: "you/roaming-own-companies",
                   reply: ("nina-costa", "src/orders/orders-module.ts", 102,
                           "Doesn't storing the provider on the account leak a billing detail into the domain?")),
                pr("acme/mobile", 844, "feat: move the app routes under /app/v1",
                   author: viewer, mine: true, checks: .running, minutes: 180,
                   head: "you/app-v1-routes"),
                pr("acme/notifier", 312, "chore: move the welcome email to the new provider",
                   author: viewer, mine: true, draft: true, minutes: 300,
                   head: "you/welcome-resend"),
            ],
            toReview: [
                pr("acme/console", 4753, "feat: hide the balance column on group tabs",
                   author: "lu-ferraz", mine: false, minutes: 7,
                   head: "lu-ferraz/hide-balance-column"),
                pr("acme/console", 4751, "feat: show pooled accounts as unavailable",
                   author: "lu-ferraz", mine: false, checks: .failing, minutes: 34,
                   head: "lu-ferraz/pooled-unavailable"),
                pr("acme/orders-api", 7867, "feat: say what kind of actor authenticated",
                   author: "rafa-mendes", mine: false, minutes: 110,
                   head: "rafa-mendes/actor-kind"),
                pr("acme/warehouse", 541, "chore: sync warehouse models with orders-api #742",
                   author: "tiago-arantes", mine: false, approved: true, minutes: 240,
                   head: "tiago-arantes/sync-warehouse-models", askedYou: true),
                pr("acme/billing", 1290, "chore: bump the invoice renderer",
                   author: "caio-braga", mine: false, minutes: 55,
                   head: "caio-braga/invoice-renderer"),
            ],
            following: [
                pr("acme/orders-api", 7880, "fix: retry the reroute when the label is stale",
                   author: "bea-nunes", mine: false, minutes: 22,
                   head: "bea-nunes/reroute-retry",
                   reply: ("bea-nunes", "src/shipping/reroute-parcel.ts", 58,
                           "Good catch. Pushed the retry with backoff the way you suggested.")),
                pr("acme/console", 4749, "feat: block top-up and group changes for pooled accounts",
                   author: "lu-ferraz", mine: false, minutes: 260,
                   head: "lu-ferraz/pooled-batch-top-up"),
            ],
            rateLimitLeft: 4980
        )
    }

    static var unread: Set<String> {
        ["acme/orders-api#7842", "acme/orders-api#7841", "acme/orders-api#7880"]
    }

    static var repos: [RepoRef] {
        team.isEmpty ? [] : [
            RepoRef(nameWithOwner: "acme/orders-api", owner: "acme", isOrg: true, isPrivate: true),
            RepoRef(nameWithOwner: "acme/console", owner: "acme", isOrg: true, isPrivate: true),
            RepoRef(nameWithOwner: "acme/notifier", owner: "acme", isOrg: true, isPrivate: true),
            RepoRef(nameWithOwner: "acme/mobile", owner: "acme", isOrg: true, isPrivate: true),
            RepoRef(nameWithOwner: "acme/warehouse", owner: "acme", isOrg: true, isPrivate: true),
            RepoRef(nameWithOwner: "chagas42/diple", owner: "you", isOrg: false, isPrivate: true),
            RepoRef(nameWithOwner: "chagas42/jsonl-inspect", owner: "you", isOrg: false, isPrivate: false),
        ]
    }

    static let team: [Person] = [
        Person(login: "rafa-mendes", name: "Rafa Mendes", avatar: URL(string: "about:blank")!),
        Person(login: "bea-nunes", name: "Bea Nunes", avatar: URL(string: "about:blank")!),
        Person(login: "you", name: "You", avatar: URL(string: "about:blank")!),
        Person(login: "tiago-arantes", name: "Tiago Arantes", avatar: URL(string: "about:blank")!),
        Person(login: "lu-ferraz", name: "Lu Ferraz", avatar: URL(string: "about:blank")!),
        Person(login: "nina-costa", name: "Nina Costa", avatar: URL(string: "about:blank")!),
        Person(login: "caio-braga", name: "Caio Braga", avatar: URL(string: "about:blank")!),
        Person(login: "ester-pinho", name: "Ester Pinho", avatar: URL(string: "about:blank")!),
    ]

    static func ranking(_ period: RankPeriod) -> [RankRow] {
        let base: [(String, Int)] = switch period {
        case .week:    [("rafa-mendes", 85), ("bea-nunes", 46), ("you", 36), ("tiago-arantes", 9), ("lu-ferraz", 4)]
        case .month:   [("rafa-mendes", 265), ("bea-nunes", 97), ("you", 85), ("tiago-arantes", 30), ("lu-ferraz", 8)]
        case .quarter: [("rafa-mendes", 937), ("you", 271), ("bea-nunes", 224), ("tiago-arantes", 186), ("lu-ferraz", 27)]
        }
        return base.compactMap { login, n in
            team.first { $0.login == login }.map { RankRow(person: $0, reviews: n) }
        }
    }

    static var activity: [ActivityDay] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let shape = [0, 2, 5, 0, 9, 14, 3, 0, 0, 7, 11, 6, 2, 0, 4, 18, 22, 9, 5, 0, 0, 12, 15, 8,
                     3, 0, 6, 20, 40, 20, 4, 0, 2, 9, 13, 7, 0, 0, 5, 16, 25, 11, 6, 0, 3, 14, 19, 8]
        return (0..<120).compactMap { back in
            guard let d = cal.date(byAdding: .day, value: -back, to: today) else { return nil }
            let n = shape[(119 - back) % shape.count]
            return ActivityDay(date: d, reviews: n)
        }.reversed()
    }
}
