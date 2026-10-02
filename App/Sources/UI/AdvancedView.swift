import SwiftUI
import GameReadyCore

/// Advanced: a native sidebar and grouped rows, with the readiness ring and monospaced readouts.
struct AdvancedView: View {
    enum Page: String, CaseIterable, Identifiable {
        case overview, checklist, history, settings
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .overview: return "gauge.with.dots.needle.67percent"
            case .checklist: return "checklist"
            case .history: return "clock"
            case .settings: return "gearshape"
            }
        }
    }

    @Environment(AppModel.self) private var model
    @State private var page: Page

    init(page: Page = .overview) { _page = State(initialValue: page) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            Group {
                switch page {
                case .overview: OverviewPage()
                case .checklist: ChecklistView()
                case .history: HistoryView()
                case .settings: SettingsView(embedded: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.surface)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Page.allCases) { p in
                Button { page = p } label: {
                    Label(L("adv.page.\(p.rawValue)"), systemImage: p.icon)
                        .padding(.vertical, 6).padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(page == p ? Theme.ready.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 7))
                        .foregroundStyle(page == p ? Theme.ready : Theme.text)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(page == p ? .isSelected : [])
            }
            Spacer()
            LiveReadouts()
        }
        .padding(10)
        .frame(width: 190)
        .background(Theme.sidebar.opacity(0.6))
    }
}

/// The sidebar's live numbers: from the live watch while Game Mode is on, else the last check.
private struct LiveReadouts: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.live.running ? L("ui.live.title").uppercased() : L("adv.lastCheck").uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(Theme.textVariant)
                .padding(.leading, 12).padding(.bottom, 2)
            row(L("ui.live.router"), model.live.running ? model.live.lastRouterMs : nil, unit: "ms")
            row(L("ui.live.server"), model.live.running ? model.live.lastServerMs : model.metrics.pingMs, unit: "ms")
            row(L("adv.loss"), model.metrics.lossPercent, unit: "%", decimals: 1)
        }
        .padding(.bottom, 10)
        .accessibilityElement(children: .combine)
    }
    private func row(_ k: String, _ v: Double?, unit: String, decimals: Int = 0) -> some View {
        HStack {
            Text(k.uppercased()).foregroundStyle(Theme.textVariant)
            Spacer()
            Text(v.map { String(format: "%.\(decimals)f", $0) + (unit == "%" ? "%" : " " + unit) } ?? "–").foregroundStyle(Theme.ready)
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 12)
    }
}

/// Overview: ring + verdict + readouts, the three actions, then every result in groups.
struct OverviewPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.gameMode.leftOn { leftOnBanner }
                header
                actions
                if model.running {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: Double(model.stepsDone), total: Double(max(1, model.stepCount))).tint(Theme.ready)
                        if let step = model.step { Text(Copy.step(step)).font(.callout).foregroundStyle(Theme.textVariant) }
                    }
                }
                if let error = model.changesError {
                    Text(L("ui.gameMode.failed") + " " + error).font(.callout).foregroundStyle(Theme.bad)
                }
                if !model.results.isEmpty {
                    RowGroup(title: L("adv.group.network")) { rows([.connection, .wifi, .hop, .internet, .udp, .ipv6]) }
                    RowGroup(title: L("adv.group.lineAndMac")) { rows([.speed, .lineFree, .mac, .apps, .checklist]) }
                }
            }
            .padding(20)
        }
    }

    private var header: some View {
        HStack(spacing: 18) {
            ReadinessRing(score: model.score, grade: verdictGrade)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.verdict.map { Copy.title($0.level) } ?? L("verdict.none.title"))
                    .font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
                Text(reason).foregroundStyle(Theme.textVariant).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Readout(key: L("adv.ping"), value: model.metrics.pingMs.map { String(format: "%.0f ms", $0) })
                    Readout(key: L("adv.down"), value: model.metrics.downMbps.map { String(format: "%.0f Mbps", $0) })
                    Readout(key: L("adv.jitter"), value: model.metrics.jitterMs.map { String(format: "%.1f ms", $0) })
                    Readout(key: L("adv.loss"), value: model.metrics.lossPercent.map { String(format: "%.1f%%", $0) })
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button { Task { await model.runCheck() } } label: {
                Label(model.running ? L("basic.checking") : model.verdict == nil ? L("ui.checkNow") : L("ui.checkAgain"),
                      systemImage: "arrow.clockwise")
            }
            .controlSize(.large).disabled(model.running).keyboardShortcut("r", modifiers: .command)
            Spacer()
            Toggle(L("ui.gameMode"), isOn: Binding(get: { model.gameMode.isOn },
                                                   set: { _ in Task { await model.toggleGameMode() } }))
                .toggleStyle(TintedSwitchStyle(tint: Theme.ready))
                .disabled(model.switching || model.running)
                .keyboardShortcut("g", modifiers: .command)
            Button { model.play() } label: {
                Label(String(format: L("ui.playOn"), model.settings.platform.displayName), systemImage: "play.fill")
            }
            .buttonStyle(FilledButtonStyle(tint: Theme.ready, foreground: Theme.onReady))
            .keyboardShortcut("p", modifiers: .command)
        }
    }

    private var leftOnBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
            Text(L("ui.gameMode.leftOn")).foregroundStyle(Theme.text)
            Spacer()
            Button(L("ui.gameMode.turnOff")) { Task { await model.turnGameModeOff() } }
        }
        .padding(12)
        .background(Theme.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private var verdictGrade: Grade {
        switch model.verdict?.level {
        case .ready: .green
        case .warning: .amber
        case .notReady: .red
        default: .unknown
        }
    }

    private var reason: String {
        guard let v = model.verdict else { return L("verdict.none.subtitle") }
        return v.problems.first?.findings.first.map(Copy.sentence) ?? Copy.subtitle(v.level)
    }

    @ViewBuilder private func rows(_ ids: [CheckID]) -> some View {
        let items = model.results.filter { ids.contains($0.id) }
        ForEach(Array(items.enumerated()), id: \.element.id) { i, r in
            ResultLine(result: r, last: i == items.count - 1)
        }
    }
}

/// The readiness score ring (ReadinessScore, docs/decisions.md).
struct ReadinessRing: View {
    var score: Int?
    var grade: Grade
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = grade == .green || grade == .unknown ? Theme.ready : Theme.color(grade)
        ZStack {
            Circle().stroke(c.opacity(0.18), lineWidth: 9)
            Circle().trim(from: 0, to: CGFloat(score ?? 0) / 100)
                .stroke(c, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: c.opacity(scheme == .dark ? 0.6 : 0.15), radius: 6)
            VStack(spacing: -2) {
                Text(score.map(String.init) ?? "–").font(.system(size: 28, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Theme.text)
                Text(L("adv.score")).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(c)
            }
        }
        .frame(width: 96, height: 96)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: L("a11y.score"), score ?? 0))
    }
}

struct Readout: View {
    var key: String
    var value: String?
    var body: some View {
        HStack(spacing: 4) {
            Text(key.uppercased()).foregroundStyle(Theme.textVariant)
            Text(value ?? "–").foregroundStyle(Theme.ready)
        }
        .font(.system(size: 11, weight: .bold, design: .monospaced))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .overlay(Capsule().strokeBorder(Theme.ready.opacity(0.45)))
    }
}

/// One result: status bar, name, sentence, monospaced value; click for the raw numbers.
struct ResultLine: View {
    let result: CheckResult
    var last: Bool
    @State private var open = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { if !result.details.isEmpty { open.toggle() } } label: {
                HStack(spacing: 12) {
                    Capsule().fill(color).frame(width: 4, height: 26)
                        .shadow(color: color.opacity(scheme == .dark ? 0.7 : 0), radius: 4)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Copy.name(result.id)).fontWeight(.medium).foregroundStyle(Theme.text)
                        Text(result.findings.first.map(Copy.sentence) ?? "").font(.caption).foregroundStyle(Theme.textVariant)
                            .lineLimit(open ? nil : 1)
                    }
                    Spacer()
                    Text(value).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(color)
                    if !result.details.isEmpty {
                        Image(systemName: open ? "chevron.down" : "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(result.findings.dropFirst(), id: \.self) { f in
                        Text(Copy.sentence(f)).font(.caption).foregroundStyle(Theme.textVariant)
                    }
                    ForEach(result.details.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                        HStack {
                            Text(detailLabel(k)).foregroundStyle(Theme.textVariant)
                            Spacer()
                            Text(v).monospacedDigit().foregroundStyle(Theme.text)
                        }
                        .font(.caption)
                    }
                }
                .padding(.leading, 16)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .overlay(alignment: .bottom) { if !last { Divider().padding(.leading, 28) } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Copy.accessibility(result))
    }

    private var color: Color { Theme.color(result.grade) }

    /// The headline number for the row; falls back to the grade word.
    private var value: String {
        for key in ["avg", "rssi", "down", "now", "IPv4", "Cloudflare", "Game server", "cpu", "open"] {
            if let v = result.details[key] { return v.components(separatedBy: ",").first ?? v }
        }
        return Copy.grade(result.grade)
    }

    private func detailLabel(_ key: String) -> String {
        let localized = Copy.detail(key)
        return localized == "detail.\(key)" ? key : localized
    }
}
