// What the note implied, as an editable checklist. Everything is on by
// default, every word and date can be changed, and nothing exists until
// Add; when the entry was with several people, the reader says which one
// the follow-ups and facts are about.

import SwiftData
import SwiftUI

/// A proposal the reader can rewrite before it becomes a reminder or a fact.
struct EditableSuggestion: Identifiable {
    let id: UUID
    let isFollowUp: Bool
    /// Follow-up: what to do. Fact: the label.
    var title: String
    /// Follow-up: the sentence it came from. Fact: the value.
    var detail: String
    var due: Date
    var selected = true

    init(_ s: Suggestion) {
        id = s.id
        isFollowUp = s.isFollowUp
        title = s.title
        detail = s.detail
        due = s.dueDate ?? Date()
    }

    /// Blank wording is nothing to add, however it was ticked.
    var complete: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && (isFollowUp || !detail.trimmingCharacters(in: .whitespaces).isEmpty)
    }
}

struct SuggestionsSheet: View {
    let outcome: JudgeOutcome
    let friends: [Friend]
    let entry: Entry?
    let onClose: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = Appearance.dark.rawValue
    @State private var items: [EditableSuggestion] = []
    @State private var target: Friend?

    var body: some View {
        NavigationStack {
            PanelScroll {
                if friends.count > 1 {
                    SectionLabel("About")
                    ChipStrip(wraps: true) {
                        ForEach(friends) { f in
                            GlassChip(active: target?.id == f.id, action: { target = f }) {
                                Text(f.displayName).font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                }
                if items.contains(where: \.isFollowUp) {
                    SectionLabel("Follow up")
                    ForEach($items) { $item in
                        if item.isFollowUp { followUpRow($item) }
                    }
                }
                if items.contains(where: { !$0.isFollowUp }) {
                    SectionLabel("Remember")
                    ForEach($items) { $item in
                        if !item.isFollowUp { factRow($item) }
                    }
                }
                Text(provenance + " Edit anything before adding.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .navigationTitle("Tend noticed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { close() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    let count = chosen.count
                    Button(count == 0 ? "Add" : "Add \(count)") { accept() }
                        .disabled(count == 0 || target == nil)
                }
            }
            .onAppear {
                items = outcome.suggestions.map(EditableSuggestion.init)
                target = friends.first
            }
        }
        .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
        .interactiveDismissDisabled()
    }

    private var chosen: [EditableSuggestion] {
        items.filter { $0.selected && $0.complete }
    }

    /// Where these came from, and how many were set aside on the way.
    private var provenance: String {
        var text = outcome.modelled ? "Found on your device by Apple's language model" : "Found by pattern matching, on your device"
        if outcome.rounds > 0 { text += ", then read again by a second pass" }
        if !outcome.rejected.isEmpty { text += "; \(outcome.rejected.count) set aside" }
        return text + "."
    }

    private func checkbox(_ item: Binding<EditableSuggestion>) -> some View {
        Button { item.wrappedValue.selected.toggle() } label: {
            Image(systemName: item.wrappedValue.selected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(item.wrappedValue.selected ? Theme.accent : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func followUpRow(_ item: Binding<EditableSuggestion>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            checkbox(item)
            VStack(alignment: .leading, spacing: 6) {
                TextField("What to do", text: item.title)
                    .font(.subheadline.weight(.semibold))
                    .textFieldStyle(.plain)
                DatePicker("When", selection: item.due, displayedComponents: [.date])
                    .font(.caption)
                    .tint(Theme.accent)
                Text("“\(item.wrappedValue.detail)”")
                    .font(.caption).foregroundStyle(.tertiary).italic().lineLimit(2)
            }
        }
        .panel()
        .opacity(item.wrappedValue.selected ? 1 : 0.6)
    }

    private func factRow(_ item: Binding<EditableSuggestion>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            checkbox(item)
            TextField("Label", text: item.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textFieldStyle(.plain)
                .frame(width: 86)
            TextField("Value", text: item.detail, axis: .vertical)
                .font(.subheadline)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
        }
        .panel()
        .opacity(item.wrappedValue.selected ? 1 : 0.6)
    }

    private func accept() {
        guard let target else { return }
        for item in chosen {
            let title = item.title.trimmingCharacters(in: .whitespaces)
            let detail = item.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            if item.isFollowUp {
                let reminder = Reminder(title: title, due: item.due, note: detail, kind: .followUp)
                reminder.friend = target
                reminder.source = entry
                context.insert(reminder)
            } else if let existing = (target.facts ?? []).first(where: { $0.label.caseInsensitiveCompare(title) == .orderedSame }) {
                existing.value = detail
                existing.updatedAt = Date()
                existing.source = entry
            } else {
                let fact = Fact(label: title, value: detail)
                fact.friend = target
                fact.source = entry
                context.insert(fact)
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
