// Appearance, the digest time, permissions, and the way out: export
// everything as a zip, or bring a backup back in.

import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("appearance") private var appearance = Appearance.dark.rawValue
    @AppStorage(Notifier.digestHourKey) private var digestHour = Notifier.defaultHour
    @AppStorage(Notifier.digestMinuteKey) private var digestMinute = 0
    @AppStorage(SwipeAction.leadingKey) private var swipeLeading = SwipeAction.defaultLeading
    @AppStorage(SwipeAction.trailingKey) private var swipeTrailing = SwipeAction.defaultTrailing
    @Query private var friends: [Friend]
    @Query private var entries: [Entry]
    @State private var notifications: UNAuthorizationStatus = .notDetermined
    @State private var exportURL: URL?
    @State private var exporting = false
    @State private var importing = false
    @State private var note: String?

    var body: some View {
        NavigationStack {
            PanelScroll {
                appearancePanel
                swipePanel
                nudgesPanel
                suggestionsPanel
                dataPanel
                Text("Tend \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · everything stays on this phone")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
            .navigationTitle("Settings")
            .task { notifications = await Notifier.authorizationStatus() }
            .sheet(isPresented: .init(get: { exportURL != nil }, set: { if !$0 { exportURL = nil } })) {
                if let exportURL { ShareSheet(items: [exportURL]) }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .folder]) { result in
                switch result {
                case .success(let url):
                    do {
                        let summary = try Importer.importBackup(from: url, into: context)
                        note = "Imported " + summary.description
                        Task { await Notifier.reschedule(context: context) }
                    } catch {
                        note = error.localizedDescription
                    }
                case .failure(let error):
                    note = error.localizedDescription
                }
            }
            .alert("Data", isPresented: .init(get: { note != nil }, set: { if !$0 { note = nil } })) {
                Button("OK") {}
            } message: { Text(note ?? "") }
        }
    }

    private var appearancePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Appearance")
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(Appearance.allCases) { a in
                        GlassChip(active: appearance == a.rawValue, action: { appearance = a.rawValue }) {
                            Label(a.label, systemImage: a.icon).font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
        }
        .panel()
    }

    private var swipePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Swipe actions · People")
            swipeEdge("Swipe right", raw: $swipeLeading)
            swipeEdge("Swipe left", raw: $swipeTrailing)
            Text("Each edge carries one action. Tap the chosen one to clear it. Delete always asks first.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .panel()
    }

    private func swipeEdge(_ label: String, raw: Binding<String>) -> some View {
        let chosen = SwipeAction.one(raw.wrappedValue)
        return VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            ForEach(SwipeAction.allCases) { action in
                let on = chosen == action
                Button {
                    // One action per edge: choosing is replacing, and
                    // choosing the current one again leaves the edge bare.
                    raw.wrappedValue = SwipeAction.store(on ? nil : action)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: on ? "largecircle.fill.circle" : "circle")
                            .font(.subheadline)
                            .foregroundStyle(on ? Theme.accent : Color.secondary)
                        Image(systemName: action.icon)
                            .font(.caption)
                            .foregroundStyle(action.tint)
                        Text(action.label)
                            .font(.subheadline.weight(on ? .semibold : .regular))
                        Spacer()
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var nudgesPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Nudges")
            DatePicker("Daily digest at", selection: digestTime, displayedComponents: .hourAndMinute)
                .font(.subheadline)
                .onChange(of: digestHour) { _, _ in Task { await Notifier.reschedule(context: context) } }
                .onChange(of: digestMinute) { _, _ in Task { await Notifier.reschedule(context: context) } }
            HStack {
                Text("Notifications").font(.subheadline)
                Spacer()
                switch notifications {
                case .authorized, .provisional, .ephemeral:
                    Badge("on", tint: Theme.rise)
                case .denied:
                    Badge("off", tint: Theme.warn)
                default:
                    Button("Allow") {
                        Task {
                            _ = await Notifier.requestAuthorization()
                            notifications = await Notifier.authorizationStatus()
                            await Notifier.reschedule(context: context)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            if notifications == .denied {
                Text("Turn them on in Settings → Tend → Notifications.").font(.caption).foregroundStyle(.secondary)
            }
            Text("One digest a morning, only on days someone is overdue. Follow-ups and birthdays fire on their day.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .panel()
    }

    private var suggestionsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Suggestions")
            HStack {
                Text("On-device language model").font(.subheadline)
                Spacer()
                Badge(SuggestionEngine.usesLanguageModel ? "on" : "n/a", tint: SuggestionEngine.usesLanguageModel ? Theme.rise : .secondary)
            }
            Text(SuggestionEngine.usesLanguageModel
                 ? "Apple Intelligence reads new notes for events and facts. Nothing leaves the phone."
                 : "This device has no on-device model; notes are read by pattern matching instead.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .panel()
    }

    private var dataPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Data")
            Text("\(friends.count) friends · \(entries.count) entries · \(entries.filter { $0.audioFile != nil }.count) recordings")
                .font(.subheadline).monospacedDigit()
            HStack(spacing: 16) {
                Button {
                    exporting = true
                    Task {
                        defer { exporting = false }
                        do { exportURL = try Exporter.exportZip(context: context) } catch { note = error.localizedDescription }
                    }
                } label: { Label(exporting ? "Exporting…" : "Export", systemImage: "square.and.arrow.up") }
                .disabled(exporting)
                Button { importing = true } label: { Label("Import", systemImage: "square.and.arrow.down") }
            }
            .font(.subheadline.weight(.semibold))
            Text("Export is a zip: backup.json, friends.csv, entries.csv, and every recording. Import reads a backup.json — or the unzipped folder, to bring recordings back — and merges by id without deleting anything.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .panel()
    }

    private var digestTime: Binding<Date> {
        Binding(
            get: { Dates.at(hour: digestHour, minute: digestMinute, on: Date()) },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                digestHour = parts.hour ?? Notifier.defaultHour
                digestMinute = parts.minute ?? 0
            })
    }
}
