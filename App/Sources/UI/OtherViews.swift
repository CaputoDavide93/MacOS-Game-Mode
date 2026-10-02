import AppKit
import SwiftUI
import UniformTypeIdentifiers
import GameReadyCore

struct ContentView: View {
    enum Tab: String, CaseIterable { case check, checklist, history }
    @State private var tab: Tab

    init(tab: Tab = .check) { _tab = State(initialValue: tab) }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text(L("ui.tab.\($0.rawValue)")).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Theme.padding)
            .padding(.vertical, 12)
            switch tab {
            case .check: CheckView()
            case .checklist: ChecklistView()
            case .history: HistoryView()
            }
        }
        .background(Theme.surface)
        .tint(Theme.primary)
        .frame(minWidth: 380, idealWidth: 440, minHeight: 560, idealHeight: 680)
    }
}

struct ChecklistView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if model.settings.platform.usesBetterXcloud { XcloudCard() }
                ForEach(Checklist.Item.allCases) { item in
                    Card {
                        HStack(alignment: .top, spacing: 12) {
                            Toggle("", isOn: Binding(get: { model.checklist.done[item] ?? false },
                                                     set: { model.checklist.setDone(item, $0) }))
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                                .accessibilityLabel(Copy.item(item))
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(Copy.item(item)).font(.headline).foregroundStyle(Theme.text)
                                    if model.checklist.source[item] == .detected {
                                        Text(L("ui.detected")).font(.caption)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Theme.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                                            .foregroundStyle(Theme.primary)
                                    }
                                }
                                Text(Copy.help(item)).font(.callout).foregroundStyle(Theme.textVariant)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let url = item.settingsURL {
                                    Button(L("ui.openSettings")) { NSWorkspace.shared.open(url) }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(Theme.primary)
                                        .frame(minHeight: 28)
                                }
                            }
                        }
                    }
                }
            }
            .padding(Theme.padding)
        }
        .background(Theme.surface)
        .task {
            guard !model.isDemo else { return }
            await model.checklist.detect()
            if model.settings.platform.usesBetterXcloud {
                await model.changes.refreshXcloud(browser: model.settings.browser)
                model.checklist.applyBetterXcloud(model.changes.xcloudSettings)
            }
        }
    }
}

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            if model.entries.isEmpty {
                Spacer()
                Text(L("ui.history.empty")).foregroundStyle(Theme.textVariant).multilineTextAlignment(.center).padding(Theme.padding)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(model.entries.enumerated()), id: \.offset) { _, entry in row(entry) }
                    }
                    .padding(Theme.padding)
                }
            }
            HStack {
                Button(L("ui.history.export")) { export() }.disabled(model.entries.isEmpty)
                Spacer()
                Button(L("ui.history.delete"), role: .destructive) { confirmDelete = true }.disabled(model.entries.isEmpty)
            }
            .padding(Theme.padding)
        }
        .background(Theme.surface)
        .confirmationDialog(L("ui.history.deleteConfirm"), isPresented: $confirmDelete) {
            Button(L("ui.history.deleteButton"), role: .destructive) { model.deleteAllData() }
            Button(L("ui.cancel"), role: .cancel) {}
        }
    }

    @ViewBuilder private func row(_ entry: HistoryEntry) -> some View {
        switch entry {
        case .check(let c):
            Card {
                HStack {
                    Image(systemName: Theme.symbol(grade(c.verdict))).foregroundStyle(Theme.color(grade(c.verdict)))
                    VStack(alignment: .leading) {
                        Text(Copy.title(c.verdict)).font(.headline).foregroundStyle(Theme.text)
                        Text(c.at.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Theme.textVariant)
                    }
                    Spacer()
                }
            }
            .accessibilityElement(children: .combine)
        case .session(let s):
            Card {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "gamecontroller").foregroundStyle(Theme.primary)
                        Text(L("ui.session")).font(.headline).foregroundStyle(Theme.text)
                        Spacer()
                        Text(s.start.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Theme.textVariant)
                    }
                    Text(s.events.isEmpty ? L("ui.session.calm")
                         : s.events.count == 1 ? L("ui.session.hiccupOne")
                         : String(format: L("ui.session.hiccups"), s.events.count))
                        .font(.callout).foregroundStyle(Theme.textVariant)
                    ForEach(Array(s.events.prefix(8).enumerated()), id: \.offset) { _, e in EventLine(event: e) }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func grade(_ v: VerdictLevel) -> Grade {
        switch v { case .ready: .green; case .warning: .amber; case .notReady: .red; case .incomplete: .unknown }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "game-ready-checks.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? model.exportCSV().write(to: url, atomically: true, encoding: .utf8)
    }
}

struct EventLine: View {
    let event: LiveEvent
    var body: some View {
        HStack(spacing: 6) {
            Text(event.at.formatted(date: .omitted, time: .standard)).monospacedDigit()
            Text("·")
            Text(Copy.layer(event.layer)).fontWeight(.semibold)
            Text(Copy.event(event.kind))
            if let v = event.value { Text(v).monospacedDigit() }
        }
        .font(.caption)
        .foregroundStyle(Theme.textVariant)
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Picker(L("ui.settings.platform"), selection: $settings.platform) {
                ForEach(GamingPlatform.allCases) { Text($0.displayName).tag($0) }
            }
            Picker(L("ui.settings.browser"), selection: $settings.browser) {
                Text("Chrome").tag(Browser.chrome)
                Text("Safari").tag(Browser.safari)
                Text("Edge").tag(Browser.edge)
            }
            Toggle(isOn: $settings.runSpeedTest) {
                VStack(alignment: .leading) {
                    Text(L("ui.settings.speed"))
                    Text(L("ui.settings.speed.help")).font(.caption).foregroundStyle(.secondary)
                }
            }
            if settings.platform.usesBetterXcloud {
                Section("Better xCloud") {
                    Toggle(isOn: $settings.tuneBetterXcloud) {
                        VStack(alignment: .leading) {
                            Text(L("ui.xcloud.tune"))
                            Text(L("ui.xcloud.tune.help")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section(L("ui.settings.quitApps")) {
                ForEach(AppsProbe.knownNoisy, id: \.id) { app in
                    Toggle(app.name, isOn: Binding(
                        get: { settings.quitApps.contains(app.id) },
                        set: { on in if on { settings.quitApps.insert(app.id) } else { settings.quitApps.remove(app.id) } }))
                }
            }
            Section(L("ui.settings.about")) {
                Text(L("ui.settings.why")).fixedSize(horizontal: false, vertical: true)
                Text(L("ui.settings.privacy")).fixedSize(horizontal: false, vertical: true).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
    }
}

/// The menu-bar popover: live readings, the Game Mode switch, recent events.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("ui.live.title")).font(.headline)
                Spacer()
                Toggle(L("ui.gameMode"), isOn: Binding(get: { model.gameMode.isOn },
                                                        set: { _ in Task { await model.toggleGameMode() } }))
                    .toggleStyle(.switch).controlSize(.small)
                    .disabled(model.switching)
            }
            if model.live.running {
                HStack(spacing: 16) {
                    reading(L("ui.live.router"), model.live.lastRouterMs)
                    reading(L("ui.live.server"), model.live.lastServerMs)
                }
                if model.live.events.isEmpty {
                    Text(L("ui.live.noEvents")).font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(model.live.events.suffix(5).reversed().enumerated()), id: \.offset) { _, e in EventLine(event: e) }
                }
            } else {
                Text(L("ui.live.off")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Button(L("ui.openApp")) {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button(L("ui.quit")) { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private func reading(_ label: String, _ ms: Double?) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(ms.map { String(format: "%.0f ms", $0) } ?? "–").font(.title3.weight(.semibold)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

/// What Game Ready can see of Better xCloud, and what to do when it can't.
struct XcloudCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon).foregroundStyle(color)
                    Text("Better xCloud").font(.headline).foregroundStyle(Theme.text)
                    Spacer()
                    Button(L("ui.xcloud.refresh")) {
                        Task {
                            await model.changes.refreshXcloud(browser: model.settings.browser)
                            model.checklist.applyBetterXcloud(model.changes.xcloudSettings)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.primary)
                }
                Text(L("ui.xcloud.\(key)")).font(.callout).foregroundStyle(Theme.textVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var key: String {
        switch model.changes.xcloud {
        case .unknown: return "unknown"
        case .notInstalled: return "notInstalled"
        case .noTab: return "noTab"
        case .jsDisabled: return "jsDisabled"
        case .notAllowed: return "notAllowed"
        case .browserClosed: return "browserClosed"
        case .failed: return "failed"
        case .matches: return "matches"
        case .differs: return "differs"
        case .applied: return "applied"
        case .restorePending: return "restorePending"
        }
    }

    private var icon: String {
        switch model.changes.xcloud {
        case .matches, .applied: return Theme.symbol(.green)
        case .differs, .restorePending: return Theme.symbol(.amber)
        case .jsDisabled, .notAllowed, .failed: return Theme.symbol(.red)
        default: return Theme.symbol(.unknown)
        }
    }

    private var color: Color {
        switch model.changes.xcloud {
        case .matches, .applied: return Theme.good
        case .differs, .restorePending: return Theme.warn
        case .jsDisabled, .notAllowed, .failed: return Theme.bad
        default: return Theme.textVariant
        }
    }
}
