import SwiftUI
import GameReadyCore

/// Basic: one status, one sentence, one button. "Fix & Play" applies every fix Game Ready can
/// make (Game Mode, Better xCloud, noisy apps) and opens the game.
struct BasicView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Scrolls when large text or a long translation doesn't fit the window.
        ScrollView {
        VStack(spacing: 16) {
            Spacer(minLength: 16)
            StatusOrb(grade: orbGrade, symbol: orbSymbol, busy: model.running)
            VStack(spacing: 6) {
                Text(title).font(.system(size: 34, weight: .heavy)).tracking(-0.6).multilineTextAlignment(.center)
                    .foregroundStyle(Theme.text)
                Text(subtitle).font(.title3).foregroundStyle(Theme.textVariant).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            middle
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.basicState)

            // Hidden (space kept) while a check runs: the progress bar is the state, and a greyed
            // "Check now" or "Fix & Play" read as the next step.
            primaryButton
                .opacity(model.running ? 0 : 1)
                .disabled(model.running)
                .accessibilityHidden(model.running)
            if let error = model.changesError {
                Text(L("ui.gameMode.failed") + " " + error).font(.callout).foregroundStyle(Theme.bad)
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
            }
            Spacer(minLength: 6)
            footer.padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .containerRelativeFrame(.vertical, alignment: .center) { h, _ in h }
        }
        .background(Theme.surface)
        .task { if model.verdict == nil && !model.running && !model.isDemo { await model.runCheck() } }
    }

    // MARK: Status

    private var ready: Bool { model.gameMode.isOn && model.plan.fixes.isEmpty }

    private var orbGrade: Grade {
        if model.running || model.verdict == nil { return .unknown }
        switch model.basicState {
        case .ready, .readyWithAdvice: return .green
        case .canFix: return .amber
        case .problem, .problemButCanFix: return .red
        case .unchecked: return .unknown
        }
    }

    private var orbSymbol: String {
        if model.running { return "waveform.path.ecg" }
        switch orbGrade {
        case .green: return "checkmark"
        case .amber: return "exclamationmark"
        case .red: return "xmark"
        case .unknown: return "gamecontroller.fill"
        }
    }

    private var title: String {
        if model.running { return L("basic.checking") }
        switch model.basicState {
        case .unchecked: return L("basic.unchecked.title")
        case .canFix: return L("basic.canFix.title")
        case .ready, .readyWithAdvice: return L("basic.ready.title")
        case .problem, .problemButCanFix: return L("basic.problem.title")
        }
    }

    private var subtitle: String {
        if model.running, let step = model.step { return Copy.step(step) }
        switch model.basicState {
        case .unchecked: return L("verdict.none.subtitle")
        case .canFix:
            let n = model.plan.fixes.count
            return n == 1 ? L("basic.canFix.one") : String(format: L("basic.canFix.many"), n)
        case .ready, .readyWithAdvice:
            if model.gameMode.isOn, let ping = model.live.lastServerMs ?? model.metrics.pingMs {
                return String(format: L("basic.ready.live"), Int(ping.rounded()))
            }
            return L("basic.ready.subtitle")
        case .problem, .problemButCanFix:
            return model.verdict?.problems.first?.findings.first.map(Copy.sentence) ?? L("verdict.incomplete.subtitle")
        }
    }

    // MARK: Middle: what will be done, or what was done

    @ViewBuilder private var middle: some View {
        if model.running {
            ProgressView(value: Double(model.stepsDone), total: Double(max(1, model.stepCount)))
                .tint(Theme.ready).frame(width: 260)
        } else if model.basicState == .canFix || model.basicState == .problemButCanFix {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(model.plan.fixes.enumerated()), id: \.offset) { _, fix in
                    FixRow(title: fixTitle(fix), detail: fixDetail(fix))
                }
            }
            .padding(14)
            .frame(maxWidth: 420, alignment: .leading)
            .padding(.horizontal, 24)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else if ready {
            HStack(spacing: 8) {
                Chip(text: L("basic.done.gameMode"), icon: "bolt.fill")
                if model.changes.xcloud == .applied { Chip(text: L("basic.done.xcloud"), icon: "slider.horizontal.3") }
                if !model.closedApps.isEmpty {
                    let n = model.closedApps.count
                    Chip(text: n == 1 ? L("basic.done.apps.one") : String(format: L("basic.done.apps"), n), icon: "xmark.app")
                }
            }
        }
    }

    // MARK: Button

    @ViewBuilder private var primaryButton: some View {
        switch model.basicState {
        case .unchecked:
            Button { Task { await model.runCheck() } } label: {
                Label(L("ui.checkNow"), systemImage: "waveform.path.ecg").frame(minWidth: 220)
            }
            .buttonStyle(FilledButtonStyle(tint: .accentColor))
            .disabled(model.running)
            .keyboardShortcut(.defaultAction)
        case .canFix, .problemButCanFix:
            let anyway = model.basicState == .problemButCanFix
            Button { Task { await model.fixAndPlay() } } label: {
                Label(L(anyway ? "basic.fixAndPlayAnyway" : "basic.fixAndPlay"), systemImage: "wand.and.stars").frame(minWidth: 220)
            }
            .buttonStyle(FilledButtonStyle(tint: anyway ? Theme.warn : .accentColor))
            .disabled(model.running || model.switching)
            .keyboardShortcut(.defaultAction)
        case .ready, .readyWithAdvice, .problem:
            Button { model.play() } label: {
                Label(String(format: L(model.basicState == .problem ? "ui.playAnywayOn" : "ui.playOn"),
                             model.settings.platform.displayName), systemImage: "play.fill").frame(minWidth: 220)
            }
            .buttonStyle(FilledButtonStyle(tint: model.basicState == .problem ? Theme.warn : Theme.ready, foreground: Theme.onReady))
            .disabled(model.running)
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 4) {
            // Advice shows with Game Mode on too: a warning must never read as "all good".
            if !model.running, let advice = model.plan.advice.first {
                Text(L("advice.\(advice.rawValue)")).multilineTextAlignment(.center)
            }
            HStack(spacing: 6) {
                if model.gameMode.isOn {
                    Text(model.live.events.isEmpty ? L("basic.watching.calm")
                         : String(format: L("basic.watching.hiccups"), model.live.events.count))
                    Text("·")
                    Button(L("basic.turnOff")) { Task { await model.turnGameModeOff() } }.buttonStyle(.link)
                        .disabled(model.running || model.switching)
                } else if model.verdict != nil {
                    Button(L("ui.checkAgain")) { Task { await model.runCheck() } }.buttonStyle(.link)
                        .disabled(model.running || model.switching)
                }
            }
        }
        .padding(.horizontal, 24)
        .font(.callout)
        .foregroundStyle(Theme.textVariant)
        .tint(Theme.ready)
    }

    private func fixTitle(_ f: Fix) -> String {
        switch f {
        case .gameMode: return L("fix.gameMode")
        case .betterXcloud: return L("fix.betterXcloud")
        case .quitApps(let names): return String(format: L("fix.quitApps"), ListFormatter.localizedString(byJoining: names))
        }
    }

    private func fixDetail(_ f: Fix) -> String {
        switch f {
        case .gameMode: return L("fix.gameMode.detail")
        case .betterXcloud: return L("fix.betterXcloud.detail")
        case .quitApps: return L("fix.quitApps.detail")
        }
    }
}

/// The big round status.
struct StatusOrb: View {
    var grade: Grade
    var symbol: String
    var busy: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let c = color
        ZStack {
            Circle().fill(c.opacity(0.13)).frame(width: 144, height: 144)
            Circle().fill(c).frame(width: 96, height: 96).shadow(color: c.opacity(0.4), radius: 14)
            Image(systemName: symbol).font(.system(size: 40, weight: .black)).foregroundStyle(.white)
                .symbolEffect(.pulse, isActive: busy && !reduceMotion)
        }
        .accessibilityHidden(true)
    }

    private var color: Color {
        switch grade {
        case .green: return Theme.ready
        case .amber: return .orange
        case .red: return Theme.bad
        case .unknown: return .accentColor
        }
    }
}

private struct FixRow: View {
    var title: String
    var detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "circle.dashed").foregroundStyle(.orange).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).fontWeight(.medium).foregroundStyle(Theme.text)
                Text(detail).font(.caption).foregroundStyle(Theme.textVariant).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

struct Chip: View {
    var text: String
    var icon: String
    var body: some View {
        Label(text, systemImage: icon).font(.callout)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Theme.ready.opacity(0.14), in: Capsule())
            .foregroundStyle(Theme.ready)
    }
}
