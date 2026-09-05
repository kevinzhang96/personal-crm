// Every open follow-up, grouped by when; and the editor for one.

import SwiftData
import SwiftUI

struct RemindersView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Reminder.due) private var reminders: [Reminder]
    @State private var showDone = false
    @State private var editing: Reminder?
    private let now = Date()

    var body: some View {
        PanelScroll {
            let open = reminders.filter { !$0.done }
            if open.isEmpty {
                EmptyPanel(icon: "bell", title: "Nothing pending",
                           hint: "Follow-ups come from notes, or from + on a friend's page.")
            }
            group("Overdue", open.filter { $0.due < now && Dates.daysBetween($0.due, now) > 0 })
            group("This week", open.filter { Dates.daysBetween($0.due, now) <= 0 && Dates.daysBetween(now, $0.due) <= 7 })
            group("Later", open.filter { Dates.daysBetween(now, $0.due) > 7 })
            let done = reminders.filter(\.done)
            if !done.isEmpty {
                Button(showDone ? "Hide done" : "Done · \(done.count)") { showDone.toggle() }
                    .font(.caption.weight(.semibold))
                if showDone {
                    ForEach(done.suffix(20).reversed()) { r in
                        ReminderRow(reminder: r, now: now) { toggle(r) }
                            .onTapGesture { editing = r }
                    }
                }
            }
        }
        .navigationTitle("Follow-ups")
        .sheet(item: $editing) { ReminderEditorView(reminder: $0) }
    }

    @ViewBuilder private func group(_ title: String, _ list: [Reminder]) -> some View {
        if !list.isEmpty {
            SectionLabel("\(title) · \(list.count)")
            ForEach(list) { r in
                ReminderRow(reminder: r, now: now) { toggle(r) }
                    .onTapGesture { editing = r }
            }
        }
    }

    private func toggle(_ r: Reminder) {
        r.done.toggle()
        r.doneAt = r.done ? now : nil
        try? context.save()
        Task { await Notifier.reschedule(context: context) }
    }
}

struct ReminderEditorView: View {
    @Bindable var reminder: Reminder
    var isNew = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = Appearance.dark.rawValue

    var body: some View {
        NavigationStack {
            PanelScroll {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Ask how the interview went", text: $reminder.title)
                        .font(.headline)
                        .textFieldStyle(.roundedBorder)
                    DatePicker("When", selection: $reminder.due)
                        .font(.subheadline)
                    HStack(spacing: 8) {
                        ForEach([("Tomorrow", 1), ("3 days", 3), ("1 week", 7), ("2 weeks", 14)], id: \.1) { label, days in
                            Button(label) {
                                let day = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
                                reminder.due = Dates.at(hour: 9, on: day)
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                        }
                    }
                    TextField("Note", text: $reminder.note, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                }
                .panel()
                if let friend = reminder.friend {
                    HStack(spacing: 10) {
                        Avatar(friend: friend, size: 30)
                        Text(friend.displayName).font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                    .panel()
                }
                if !isNew {
                    Button(reminder.done ? "Mark not done" : "Mark done") {
                        reminder.done.toggle()
                        reminder.doneAt = reminder.done ? Date() : nil
                        save()
                    }
                    .font(.subheadline.weight(.semibold))
                    Button("Delete", role: .destructive) {
                        context.delete(reminder)
                        save()
                    }
                    .font(.footnote)
                }
            }
            .navigationTitle(isNew ? "Follow-up" : "Edit follow-up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isNew { context.delete(reminder) }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(reminder.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
        .interactiveDismissDisabled(isNew)
    }

    private func save() {
        try? context.save()
        Task { await Notifier.reschedule(context: context) }
        dismiss()
    }
}
