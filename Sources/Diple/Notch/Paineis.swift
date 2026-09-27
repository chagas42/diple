import SwiftUI

// MARK: - Time

struct PainelTime: View {
    @ObservedObject var modelo: Modelo

    private let colunas = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Quem você acompanha de perto")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))

            if modelo.equipe.isEmpty {
                carregando
            } else {
                LazyVGrid(columns: colunas, spacing: 11) {
                    ForEach(modelo.equipe.prefix(18)) { p in
                        Button { modelo.seguir(p.login) } label: {
                            VStack(spacing: 5) {
                                Avatar(pessoa: p, lado: 34)
                                    .overlay(
                                        Circle().stroke(
                                            modelo.seguindo.contains(p.login) ? Color.orange : .clear,
                                            lineWidth: 2
                                        )
                                    )
                                    .opacity(modelo.seguindo.contains(p.login) ? 1 : 0.55)
                                Text(p.login)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.white.opacity(
                                        modelo.seguindo.contains(p.login) ? 0.85 : 0.4))
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var carregando: some View {
        HStack { Spacer(); ProgressView().controlSize(.small).tint(.white); Spacer() }
            .frame(maxHeight: .infinity)
    }
}

struct Avatar: View {
    let pessoa: Pessoa
    var lado: CGFloat = 32

    var body: some View {
        AsyncImage(url: pessoa.avatar) { fase in
            switch fase {
            case .success(let img): img.resizable().scaledToFill()
            default:
                ZStack {
                    Color.white.opacity(0.1)
                    Text(pessoa.iniciais)
                        .font(.system(size: lado * 0.34, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(width: lado, height: lado)
        .clipShape(Circle())
    }
}

// MARK: - Rank

struct PainelRank: View {
    @ObservedObject var modelo: Modelo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reviews nos últimos 3 meses")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))

            if modelo.rank.isEmpty {
                HStack { Spacer(); ProgressView().controlSize(.small).tint(.white); Spacer() }
                    .frame(maxHeight: .infinity)
            } else {
                let maximo = max(1, modelo.rank.first?.reviews ?? 1)
                VStack(spacing: 6) {
                    ForEach(Array(modelo.rank.prefix(5).enumerated()), id: \.element.id) { i, l in
                        HStack(spacing: 9) {
                            Text("\(i + 1)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.35))
                                .frame(width: 12, alignment: .trailing)
                            Avatar(pessoa: l.pessoa, lado: 22)
                            Text(l.pessoa.login)
                                .font(.system(size: 11.5, weight: eu(l) ? .semibold : .regular))
                                .foregroundStyle(.white.opacity(eu(l) ? 1 : 0.75))
                                .frame(width: 104, alignment: .leading)
                                .lineLimit(1)
                            GeometryReader { g in
                                Capsule()
                                    .fill(eu(l) ? Color.orange : .white.opacity(0.22))
                                    .frame(width: max(3, g.size.width * CGFloat(l.reviews) / CGFloat(maximo)))
                                    .frame(maxHeight: .infinity, alignment: .center)
                            }
                            .frame(height: 7)
                            Text("\(l.reviews)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(width: 38, alignment: .trailing)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func eu(_ l: LinhaRank) -> Bool { l.pessoa.login == modelo.fila.eu }
}

// MARK: - Ritmo

struct PainelRitmo: View {
    @ObservedObject var modelo: Modelo

    /// Verde-menta em vez de laranja: laranja é o sinal de "precisa de você",
    /// e reaproveitá-lo aqui faria o grid parecer alarme.
    private static let escala: [Color] = [
        Color(red: 0.10, green: 0.31, blue: 0.27),
        Color(red: 0.13, green: 0.52, blue: 0.43),
        Color(red: 0.19, green: 0.73, blue: 0.59),
        Color(red: 0.38, green: 0.93, blue: 0.73),
    ]
    private static let vazio = Color.white.opacity(0.06)
    private static let realce = Color(red: 0.38, green: 0.93, blue: 0.73)

    private let vao: CGFloat = 3
    private let linhas = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            cabecalho

            if modelo.ritmo.isEmpty {
                HStack { Spacer(); ProgressView().controlSize(.small).tint(.white); Spacer() }
                    .frame(maxHeight: .infinity)
            } else {
                GeometryReader { g in
                    // O quadrado é calculado a partir da largura disponível,
                    // então o grid preenche o painel em qualquer tamanho.
                    let n = max(1, semanas.count)
                    let lado = max(6, (g.size.width - vao * CGFloat(n - 1)) / CGFloat(n))
                    VStack(alignment: .leading, spacing: 5) {
                        meses(lado: lado)
                        HStack(alignment: .top, spacing: vao) {
                            ForEach(Array(semanas.enumerated()), id: \.offset) { _, semana in
                                VStack(spacing: vao) {
                                    ForEach(semana) { d in
                                        RoundedRectangle(cornerRadius: lado * 0.22, style: .continuous)
                                            .fill(cor(d.reviews))
                                            .frame(width: lado, height: lado)
                                            .help(dica(d))
                                    }
                                }
                            }
                        }
                    }
                }
                rodape
            }
        }
    }

    private var cabecalho: some View {
        HStack(spacing: 8) {
            Text("Dias em que você revisou")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
            Spacer()
            if sequencia > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill").font(.system(size: 9.5))
                    Text("\(sequencia) dia\(sequencia == 1 ? "" : "s") seguido\(sequencia == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Self.realce)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Self.realce.opacity(0.14), in: Capsule())
            }
        }
    }

    private func meses(lado: CGFloat) -> some View {
        HStack(spacing: vao) {
            ForEach(Array(semanas.enumerated()), id: \.offset) { i, semana in
                Group {
                    if let nome = inicioDeMes(i, semana) {
                        Text(nome)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                    } else {
                        Color.clear
                    }
                }
                .frame(width: lado, alignment: .leading)
            }
        }
        .frame(height: 11)
    }

    private var rodape: some View {
        HStack(spacing: 10) {
            Text("\(total) reviews · \(diasAtivos) dias ativos · melhor dia \(melhor)")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
            Spacer()
            HStack(spacing: 3) {
                Text("menos").font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.3))
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Self.vazio).frame(width: 9, height: 9)
                ForEach(Array(Self.escala.enumerated()), id: \.offset) { _, c in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(c).frame(width: 9, height: 9)
                }
                Text("mais").font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.3))
            }
        }
    }

    // MARK: - Contas

    /// Colunas de 7, do dia mais antigo pro mais novo.
    private var semanas: [[DiaRitmo]] {
        stride(from: 0, to: modelo.ritmo.count, by: linhas).map {
            Array(modelo.ritmo[$0..<min($0 + linhas, modelo.ritmo.count)])
        }
    }

    private var total: Int { modelo.ritmo.reduce(0) { $0 + $1.reviews } }
    private var diasAtivos: Int { modelo.ritmo.filter { $0.reviews > 0 }.count }
    private var melhor: Int { modelo.ritmo.map(\.reviews).max() ?? 0 }

    /// Conta de trás pra frente. Hoje ainda zerado não quebra a sequência —
    /// o dia não acabou.
    private var sequencia: Int {
        var n = 0
        for (i, d) in modelo.ritmo.enumerated().reversed() {
            if d.reviews > 0 { n += 1 }
            else if i == modelo.ritmo.count - 1 { continue }
            else { break }
        }
        return n
    }

    private func inicioDeMes(_ i: Int, _ semana: [DiaRitmo]) -> String? {
        guard let primeiro = semana.first else { return nil }
        let cal = Calendar.current
        let mes = cal.component(.month, from: primeiro.data)
        if i > 0, let anterior = semanas[i - 1].first,
           cal.component(.month, from: anterior.data) == mes { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "MMM"
        return f.string(from: primeiro.data).lowercased()
    }

    private func dica(_ d: DiaRitmo) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "d 'de' MMMM"
        let dia = f.string(from: d.data)
        return d.reviews == 0 ? "\(dia): nenhuma review"
                              : "\(dia): \(d.reviews) review\(d.reviews == 1 ? "" : "s")"
    }

    private func cor(_ n: Int) -> Color {
        switch n {
        case 0:      Self.vazio
        case 1...2:  Self.escala[0]
        case 3...5:  Self.escala[1]
        case 6...11: Self.escala[2]
        default:     Self.escala[3]
        }
    }
}
