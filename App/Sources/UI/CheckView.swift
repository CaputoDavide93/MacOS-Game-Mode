import SwiftUI
import GameReadyCore

/// Home: verdict card, the main action, Game Mode, Play, then the results.
struct CheckView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.gameMode.leftOn { leftOnBanner }
                VerdictCard()
                Button {
                    Task { await model.runCheck() }
                } label: {
                    Label(model.running ? L("ui.checking") : (model.verdict == nil ? L("ui.checkNow") : L("ui.checkAgain")),
                          systemImage: "waveform.path.ecg")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.running)
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityHint(L("verdict.none.subtitle"))

                if model.running { progress }
                GameModeRow()
                Button { model.play() } label: {
                    Label(isGreen ? L("ui.play") : L("ui.playAnyway"), systemImage: "gamecontroller")
                }
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut("p", modifiers: .command)

                if !model.results.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(model.results) { ResultRow(result: $0) }
                    }
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.results.count)
                }
            }
            .padding(Theme.padding)
        }
        .background(Theme.surface)
    }

    private var isGreen: Bool { model.verdict?.level == .ready }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: Double(model.stepsDone), total: Double(model.stepCount))
                .tint(Theme.primary)
            if let step = model.step {
                Text(Copy.step(step)).font(.callout).foregroundStyle(Theme.textVariant)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var leftOnBanner: some View {
        Card {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
                Text(L("ui.gameMode.leftOn")).foregroundStyle(Theme.text)
                Spacer()
                Button(L("ui.gameMode.turnOff")) { Task { await model.toggleGameMode() } }
            }
        }
    }
}

struct VerdictCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title2.weight(.semibold)).foregroundStyle(Theme.text)
                    Text(reason).font(.body).foregroundStyle(Theme.textVariant)
                        .fixedSize(horizontal: false, vertical: true)
                    if let at = model.lastCheck {
                        Text("\(L("ui.lastCheck")) \(at.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(Theme.textVariant)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var grade: Grade? {
        switch model.verdict?.level {
        case .ready: return .green
        case .warning: return .amber
        case .notReady: return .red
        case .incomplete: return .unknown
        case nil: return nil
        }
    }
    private var symbol: String { grade.map(Theme.symbol) ?? "gamecontroller" }
    private var color: Color { grade.map(Theme.color) ?? Theme.primary }
    private var title: String { model.verdict.map { Copy.title($0.level) } ?? L("verdict.none.title") }

    /// The headline reason: the worst problem's first finding, else the level's subtitle.
    private var reason: String {
        guard let v = model.verdict else { return L("verdict.none.subtitle") }
        if let first = v.problems.first?.findings.first { return Copy.sentence(first) }
        return Copy.subtitle(v.level)
    }
}

struct GameModeRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(get: { model.gameMode.isOn },
                                     set: { _ in Task { await model.toggleGameMode() } })) {
                    Label(L("ui.gameMode"), systemImage: "bolt.shield")
                        .font(.headline).foregroundStyle(Theme.text)
                }
                .toggleStyle(.switch)
                .tint(Theme.primary)
                .disabled(busy)
                .keyboardShortcut("g", modifiers: .command)
                Text(statusText).font(.callout).foregroundStyle(statusColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var busy: Bool { model.gameMode.phase == .starting || model.gameMode.phase == .stopping }

    private var statusText: String {
        switch model.gameMode.phase {
        case .starting: return L("ui.gameMode.starting")
        case .stopping: return L("ui.gameMode.stopping")
        case .failed(let message): return L("ui.gameMode.failed") + " " + message
        default: return L("ui.gameMode.help")
        }
    }

    private var statusColor: Color {
        if case .failed = model.gameMode.phase { return Theme.bad }
        return Theme.textVariant
    }
}

struct ResultRow: View {
    let result: CheckResult
    @State private var expanded = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: Theme.symbol(result.grade))
                        .foregroundStyle(Theme.color(result.grade))
                        .font(.title3)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Copy.name(result.id)).font(.headline).foregroundStyle(Theme.text)
                        ForEach(result.findings, id: \.self) { f in
                            Text(Copy.sentence(f)).font(.callout).foregroundStyle(Theme.textVariant)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    if !result.details.isEmpty {
                        Button { expanded.toggle() } label: {
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.textVariant)
                        .accessibilityLabel(L("ui.details"))
                    }
                }
                if expanded {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(result.details.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            HStack {
                                Text(detailLabel(key)).foregroundStyle(Theme.textVariant)
                                Spacer()
                                Text(value).monospacedDigit().foregroundStyle(Theme.text)
                            }
                            .font(.callout)
                        }
                    }
                    .padding(.leading, 34)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Copy.accessibility(result))
    }

    /// Detail keys are either known labels or a target name ("Cloudflare", "IPv4").
    private func detailLabel(_ key: String) -> String {
        let localized = Copy.detail(key)
        return localized == "detail.\(key)" ? key : localized
    }
}
