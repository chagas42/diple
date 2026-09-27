import SwiftUI

struct TeamTab: View {
    @ObservedObject var model: AppModel
    @State private var search = ""

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)
    }

    private var people: [Person] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let matching = q.isEmpty ? model.team : model.team.filter {
            $0.login.lowercased().contains(q) || $0.name.lowercased().contains(q)
        }
        return matching.sorted { a, b in
            let fa = model.following.contains(a.login), fb = model.following.contains(b.login)
            return fa == fb ? a.login < b.login : fa
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pick your teammates")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Your squad, or whoever you want to prioritise reviewing for.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
                if model.team.count > 18 {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                        TextField("Search", text: $search)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white)
                            .frame(width: 96)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Color.white.opacity(0.08), in: Capsule())
                }
                Text("\(model.following.count) picked")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(model.following.isEmpty ? .white.opacity(0.4) : .orange)
            }

            if model.team.isEmpty {
                Placeholder(text: "Loading your organisation…")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 11) {
                        ForEach(people.prefix(60)) { p in
                            let picked = model.following.contains(p.login)
                            Button { model.toggleFollow(p.login) } label: {
                                VStack(spacing: 5) {
                                    AvatarView(person: p, side: 34)
                                        .overlay(
                                            Circle().stroke(picked ? Color.orange : .clear, lineWidth: 2)
                                        )
                                        .opacity(picked ? 1 : 0.5)
                                    Text(p.login)
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(.white.opacity(picked ? 0.85 : 0.4))
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            .help(p.name)
                        }
                    }
                    .padding(.top, 2)
                }
                .scrollIndicators(.visible)
            }
        }
    }
}

struct Placeholder: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Spacer()
            ProgressView().controlSize(.small).tint(.white)
            Text(text).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.45))
            Spacer()
        }
        .frame(maxHeight: .infinity)
    }
}

struct AvatarView: View {
    let person: Person
    var side: CGFloat = 32

    var body: some View {
        AsyncImage(url: person.avatar) { fase in
            switch fase {
            case .success(let img): img.resizable().scaledToFill()
            default:
                ZStack {
                    Color.white.opacity(0.1)
                    Text(person.initials)
                        .font(.system(size: side * 0.34, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
    }
}

struct RankTab: View {
    @ObservedObject var model: AppModel
    @State private var progress: CGFloat = 0
    @State private var celebrating = false

    private var scope: String {
        model.following.count >= 2 ? "you and who you follow" : "your organisation"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Reviews in the last 3 months")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                Text("· \(scope)")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.28))
                Spacer()
                if model.refreshingTab == .ranking && !model.ranking.isEmpty {
                    Text("updating")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }

            if model.ranking.isEmpty {
                Placeholder(text: "Counting reviews…")
            } else {
                let top = max(1, model.ranking.first?.reviews ?? 1)
                VStack(spacing: 6) {
                    ForEach(Array(model.ranking.prefix(5).enumerated()), id: \.element.id) { i, row in
                        let isMe = row.person.login == model.queue.viewer
                        HStack(spacing: 9) {
                            Text("\(i + 1)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.35))
                                .frame(width: 12, alignment: .trailing)
                            AvatarView(person: row.person, side: 22)
                            Text(row.person.login)
                                .font(.system(size: 11.5, weight: isMe ? .semibold : .regular))
                                .foregroundStyle(.white.opacity(isMe ? 1 : 0.75))
                                .frame(width: 104, alignment: .leading)
                                .lineLimit(1)
                            GeometryReader { g in
                                let full = g.size.width * CGFloat(row.reviews) / CGFloat(top)
                                let width = isMe ? full * progress : full
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(isMe ? Color.orange : .white.opacity(0.22))
                                        .frame(width: max(3, width))
                                    if isMe && celebrating {
                                        Image(systemName: "flame.fill")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.orange)
                                            .shadow(color: .orange.opacity(0.8), radius: 5)
                                            .offset(x: max(0, width - 5))
                                    }
                                }
                                .frame(maxHeight: .infinity, alignment: .center)
                            }
                            .frame(height: 9)
                            Text("\(row.reviews)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(width: 38, alignment: .trailing)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .onAppear(perform: runOnce)
    }

    private func runOnce() {
        guard !model.ranking.isEmpty else { return }
        guard model.shouldAnimateScore else { progress = 1; return }
        model.markScoreShown()
        progress = 0
        celebrating = true
        withAnimation(.easeOut(duration: 1.5)) { progress = 1 }
        Task {
            try? await Task.sleep(for: .milliseconds(1700))
            withAnimation(.easeOut(duration: 0.35)) { celebrating = false }
        }
    }
}

struct ActivityTab: View {
    @ObservedObject var model: AppModel

    private static let scale: [Color] = [
        Color(red: 0.10, green: 0.31, blue: 0.27),
        Color(red: 0.13, green: 0.52, blue: 0.43),
        Color(red: 0.19, green: 0.73, blue: 0.59),
        Color(red: 0.38, green: 0.93, blue: 0.73),
    ]
    private static let empty = Color.white.opacity(0.06)
    private static let accent = Color(red: 0.38, green: 0.93, blue: 0.73)

    private let gap: CGFloat = 3
    private let linhas = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if model.activity.isEmpty {
                Placeholder(text: "Reading your review history…")
            } else {
                GeometryReader { g in

                    let n = max(1, weeks.count)
                    let side = max(6, (g.size.width - gap * CGFloat(n - 1)) / CGFloat(n))
                    VStack(alignment: .leading, spacing: 5) {
                        monthLabels(side: side)
                        HStack(alignment: .top, spacing: gap) {
                            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                                VStack(spacing: gap) {
                                    ForEach(week) { d in
                                        RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                                            .fill(color(d.reviews))
                                            .frame(width: side, height: side)
                                            .help(tooltip(d))
                                    }
                                }
                            }
                        }
                    }
                }
                footer
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Days you reviewed")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
            Spacer()
            if streak > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill").font(.system(size: 9.5))
                    Text("\(streak) day\(streak == 1 ? "" : "s") seguido\(streak == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Self.accent)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Self.accent.opacity(0.14), in: Capsule())
            }
        }
    }

    private func monthLabels(side: CGFloat) -> some View {
        HStack(spacing: gap) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { i, week in
                Group {
                    if let name = monthStart(i, week) {
                        Text(name)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                    } else {
                        Color.clear
                    }
                }
                .frame(width: side, alignment: .leading)
            }
        }
        .frame(height: 11)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("\(total) reviews · \(activeDays) days ativos · best day \(best)")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
            Spacer()
            HStack(spacing: 3) {
                Text("deletions").font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.3))
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Self.empty).frame(width: 9, height: 9)
                ForEach(Array(Self.scale.enumerated()), id: \.offset) { _, c in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(c).frame(width: 9, height: 9)
                }
                Text("additions").font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.3))
            }
        }
    }

    private var weeks: [[ActivityDay]] {
        stride(from: 0, to: model.activity.count, by: linhas).map {
            Array(model.activity[$0..<min($0 + linhas, model.activity.count)])
        }
    }

    private var total: Int { model.activity.reduce(0) { $0 + $1.reviews } }
    private var activeDays: Int { model.activity.filter { $0.reviews > 0 }.count }
    private var best: Int { model.activity.map(\.reviews).max() ?? 0 }

    private var streak: Int {
        var n = 0
        for (i, d) in model.activity.enumerated().reversed() {
            if d.reviews > 0 { n += 1 }
            else if i == model.activity.count - 1 { continue }
            else { break }
        }
        return n
    }

    private func monthStart(_ i: Int, _ week: [ActivityDay]) -> String? {
        guard let first = week.first else { return nil }
        let cal = Calendar.current
        let mes = cal.component(.month, from: first.date)
        if i > 0, let anterior = weeks[i - 1].first,
           cal.component(.month, from: anterior.date) == mes { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "MMM"
        return f.string(from: first.date).lowercased()
    }

    private func tooltip(_ d: ActivityDay) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "d 'de' MMMM"
        let day = f.string(from: d.date)
        return d.reviews == 0 ? "\(day): nenhuma review"
                              : "\(day): \(d.reviews) review\(d.reviews == 1 ? "" : "s")"
    }

    private func color(_ n: Int) -> Color {
        switch n {
        case 0:      Self.empty
        case 1...2:  Self.scale[0]
        case 3...5:  Self.scale[1]
        case 6...11: Self.scale[2]
        default:     Self.scale[3]
        }
    }
}
