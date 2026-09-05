// What the note implied, as a checklist. Everything is on by default and
// nothing exists until Add; when the entry was with several people, the
// reader says which one the follow-ups and facts are about.

import SwiftData
import SwiftUI

struct SuggestionsSheet: View {
    let suggestions: [Suggestion]
    let friends: [Friend]
    let entry: Entry?
    let onClose: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = Appearance.dark.rawValue
    @State private var selected: Set<UUID> = []
    @State private var target: Friend?

    var body: some View {
        NavigationStack {
            PanelScroll {
                if friends.count > 1 {
                    SectionLabel("About")
                    ChipStrip {
                        ForEach(friends) { f in
                            GlassChip(active: target?.id == f.id, action: { target = f }) {
                                Text(f.displayName).font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                }
                let followUps = suggestions.filter(\.isFollowUp)
                if !followUps.isEmpty {
                    SectionLabel("Follow up")
                    ForEach(followUps) { row($0) }
                }
                let facts = suggestions.filter { !$0.isFollowUp }
                if !facts.isEmpty {
                    SectionLabel("Remember")
                    ForEach(facts) { row($0) }
                }
                Text(SuggestionEngine.usesLanguageModel ? "Found on your device by Apple's language model." : "Found by pattern matching, on your device.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .navigationTitle("Tend noticed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { close() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.isEmpty ? "Add" : "Add \(selected.count)") { accept() }
                        .disabled(selected.isEmpty || target == nil)
                }
            }
            .onAppear {
                selected = Set(suggestions.map(\.id))
                target = friends.first
            }
        }
        .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
        .interactiveDismissDisabled()
    }

    private func row(_ s: Suggestion) -> some View {
        let on = selected.contains(s.id)
        return Button {
            if on { selected.remove(s.id) } else { selected.insert(s.id) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(on ? Theme.accent : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    if let due = s.dueDate {
                        Text(s.title).font(.subheadline.weight(.semibold))
                        Text(due.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                            .font(.caption).foregroundStyle(Theme.accent).monospacedDigit()
                        Text("“\(s.detail)”").font(.caption).foregroundStyle(.tertiary).italic().lineLimit(2)
                    } else {
                        (Text(s.title + "  ").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                         + Text(s.detail).font(.subheadline))
                    }
                }
                Spacer(minLength: 0)
            }
            .panel()
        }
        .buttonStyle(.plain)
    }

    private func accept() {
        guard let target else { return }
        for s in suggestions where selected.contains(s.id) {
            switch s.kind {
            case .followUp(let due):
                let reminder = Reminder(title: s.title, due: due, note: s.detail, kind: .followUp)
                reminder.friend = target
                reminder.source = entry
                context.insert(reminder)
            case .fact:
                if let existing = (target.facts ?? []).first(where: { $0.label.caseInsensitiveCompare(s.title) == .orderedSame }) {
                    existing.value = s.detail
                    existing.updatedAt = Date()
                    existing.source = entry
                } else {
                    let fact = Fact(label: s.title, value: s.detail)
                    fact.friend = target
                    fact.source = entry
                    context.insert(fact)
                }
            }
        }
        target.updatedAt = Date()
        try? context.save()
        Task { await Notifier.reschedule(context: context) }
        close()
    }

    private func close() {
        dismiss()
        onClose()
    }
}
