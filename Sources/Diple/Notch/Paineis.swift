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

    private let lado: CGFloat = 11
    private let vao: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("Dias em que você revisou")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                if sequencia > 0 {
                    Text("\(sequencia) dia\(sequencia == 1 ? "" : "s") seguido\(sequencia == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }

            if modelo.ritmo.isEmpty {
                HStack { Spacer(); ProgressView().controlSize(.small).tint(.white); Spacer() }
                    .frame(maxHeight: .infinity)
            } else {
                // Semanas em colunas, dias em linhas: igual ao gráfico do GitHub.
                HStack(alignment: .top, spacing: vao) {
                    ForEach(Array(semanas.enumerated()), id: \.offset) { _, semana in
                        VStack(spacing: vao) {
                            ForEach(semana) { d in
                                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                    .fill(cor(d.reviews))
                                    .frame(width: lado, height: lado)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    Text("\(total) reviews em \(diasAtivos) dias")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                    Spacer()
                    HStack(spacing: 4) {
                        Text("menos").font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.3))
                        ForEach([0, 1, 3, 6, 12], id: \.self) { n in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(cor(n)).frame(width: 8, height: 8)
                        }
                        Text("mais").font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.3))
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Agrupa em colunas de 7, do dia mais antigo pro mais novo.
    private var semanas: [[DiaRitmo]] {
        stride(from: 0, to: modelo.ritmo.count, by: 7).map {
            Array(modelo.ritmo[$0..<min($0 + 7, modelo.ritmo.count)])
        }
    }

    private var total: Int { modelo.ritmo.reduce(0) { $0 + $1.reviews } }
    private var diasAtivos: Int { modelo.ritmo.filter { $0.reviews > 0 }.count }

    /// Conta de trás pra frente, ignorando o dia de hoje se ainda estiver zerado.
    private var sequencia: Int {
        var n = 0
        for d in modelo.ritmo.reversed() {
            if d.reviews > 0 { n += 1 }
            else if n > 0 || modelo.ritmo.last?.id != d.id { break }
        }
        return n
    }

    private func cor(_ n: Int) -> Color {
        switch n {
        case 0:      .white.opacity(0.07)
        case 1...2:  .orange.opacity(0.32)
        case 3...5:  .orange.opacity(0.55)
        case 6...11: .orange.opacity(0.78)
        default:     .orange
        }
    }
}
