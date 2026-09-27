import Foundation

enum Demo {
    static var isOn: Bool { CommandLine.arguments.contains("--demo") }

    private static let viewer = "chagas42"

    private static func avatar(_ login: String) -> URL? {
        URL(string: "https://github.com/\(login).png?size=64")
    }

    private static func ago(_ minutes: Double) -> Date {
        Date().addingTimeInterval(-minutes * 60)
    }

    private static func pr(
        _ repo: String, _ number: Int, _ title: String,
        author: String, mine: Bool,
        checks: CheckState = .passing, approved: Bool = false, draft: Bool = false,
        minutes: Double, head: String, base: String = "main",
        reply: (String, String, Int, String)? = nil
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
            draft: draft,
            author: author,
            authorAvatar: avatar(author),
            isMine: mine,
            headRef: head,
            baseRef: base,
            checks: checks,
            approved: approved,
            threads: threads,
            lastComment: last
        )
    }

    static var queue: Queue {
        Queue(
            viewer: viewer,
            mine: [
                pr("SalvyLTD/salvy-api", 7842, "feat: bill Salvy's demo and test companies again",
                   author: viewer, mine: true, checks: .failing, minutes: 12,
                   head: "chagas42/bill-demo-companies",
                   reply: ("danilofuchs", "src/billing/invoice-skip-reason.ts", 27,
                           "Isso aqui vai marcar as empresas de teste como inadimplentes também. Não era melhor tratar no skip reason?")),
                pr("SalvyLTD/salvy-api", 7843, "feat: keep Salvy's own companies out of delinquency",
                   author: viewer, mine: true, approved: true, minutes: 48,
                   head: "chagas42/skip-own-companies", base: "chagas42/bill-demo-companies"),
                pr("SalvyLTD/salvy-api", 7841, "feat: never charge Salvy's own companies for roaming",
                   author: viewer, mine: true, minutes: 95,
                   head: "chagas42/roaming-own-companies",
                   reply: ("yurikasper", "src/billing/billing-container-module.ts", 102,
                           "Salvar o provider em companies não vaza detalhe de billing pro domínio?")),
                pr("SalvyLTD/salvy-flutter-app", 844, "feat: call the app routes under /app/v1 [ENG-7757]",
                   author: viewer, mine: true, checks: .running, minutes: 180,
                   head: "chagas42/app-v1-routes"),
                pr("SalvyLTD/salvy-emails", 312, "chore: move the welcome email to Resend",
                   author: viewer, mine: true, draft: true, minutes: 300,
                   head: "chagas42/welcome-resend"),
            ],
            toReview: [
                pr("SalvyLTD/salvy-dashboard", 4753, "feat: hide the data balance column on pool group tabs",
                   author: "girardiricardo", mine: false, minutes: 7,
                   head: "girardiricardo/hide-balance-column"),
                pr("SalvyLTD/salvy-dashboard", 4751, "feat: show pool phone accounts as unavailable in balance",
                   author: "girardiricardo", mine: false, checks: .failing, minutes: 34,
                   head: "girardiricardo/pool-unavailable"),
                pr("SalvyLTD/salvy-api", 7867, "feat: say what kind of actor authenticated",
                   author: "danilofuchs", mine: false, minutes: 110,
                   head: "danilofuchs/actor-kind"),
                pr("SalvyLTD/salvy-meltano", 541, "chore: sync DW models with salvy-api #7842",
                   author: "hudovisk", mine: false, approved: true, minutes: 240,
                   head: "hudovisk/sync-dw-models"),
            ],
            following: [
                pr("SalvyLTD/salvy-api", 7880, "fix: retry the Telecall swap when the msisdn is stale",
                   author: "eduardo-otte", mine: false, minutes: 22,
                   head: "eduardo-otte/telecall-retry",
                   reply: ("eduardo-otte", "src/telecall/swap-msisdn.ts", 58,
                           "Boa, era isso mesmo. Subi o retry com backoff como você sugeriu.")),
                pr("SalvyLTD/salvy-dashboard", 4749, "feat: block top-up and group changes for pool accounts",
                   author: "girardiricardo", mine: false, minutes: 260,
                   head: "girardiricardo/data-pool-batch-top-up"),
            ],
            rateLimitLeft: 4980
        )
    }

    static var unread: Set<String> {
        ["SalvyLTD/salvy-api#7842", "SalvyLTD/salvy-api#7841", "SalvyLTD/salvy-api#7880"]
    }

    static let team: [Person] = [
        Person(login: "danilofuchs", name: "Danilo Fuchs", avatar: avatar("danilofuchs")!),
        Person(login: "eduardo-otte", name: "Eduardo Otte", avatar: avatar("eduardo-otte")!),
        Person(login: "chagas42", name: "Celso Chagas", avatar: avatar("chagas42")!),
        Person(login: "hudovisk", name: "Hudo Assenco", avatar: avatar("hudovisk")!),
        Person(login: "girardiricardo", name: "Ricardo Girardi", avatar: avatar("girardiricardo")!),
        Person(login: "yurikasper", name: "Yuri Kasper", avatar: avatar("yurikasper")!),
        Person(login: "alysonvilela", name: "Alyson Vilela", avatar: avatar("alysonvilela")!),
        Person(login: "mizaelsantos", name: "Mizael Santos", avatar: avatar("mizaelsantos")!),
    ]

    static func ranking(_ period: RankPeriod) -> [RankRow] {
        let base: [(String, Int)] = switch period {
        case .week:    [("danilofuchs", 85), ("eduardo-otte", 46), ("chagas42", 36), ("hudovisk", 9), ("girardiricardo", 4)]
        case .month:   [("danilofuchs", 265), ("eduardo-otte", 97), ("chagas42", 85), ("hudovisk", 30), ("girardiricardo", 8)]
        case .quarter: [("danilofuchs", 937), ("chagas42", 271), ("eduardo-otte", 224), ("hudovisk", 186), ("girardiricardo", 27)]
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
