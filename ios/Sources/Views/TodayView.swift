// The screen that makes the app worth opening: who has gone quiet, what
// is due, whose birthday is coming, and what was said lately.

import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Friend> { !$0.archived }, sort: \Friend.displayName) private var friends: [Friend]
    @Query(filter: #Predicate<Reminder> { !$0.done }, sort: \Reminder.due) private var reminders: [Reminder]
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]

    @State private var draft: EntryDraft?
    @State private var recording = false
    @State private var editingReminder: Reminder?
    private let now = Date()

    var body: some View {
        NavigationStack {
            PanelScroll {
                attention
                followUps
                birthdays
                recent
            }
            .navigationTitle(now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Friend.self) { FriendDetailView(friend: $0) }
            .overlay(alignment: .bottomTrailing) {
                CaptureButtons(onRecord: { recording = true }, onNote: { draft = EntryDraft() })
            }
            .sheet(item: $draft) { EntryEditorView(draft: $0) }
            .sheet(isPresented: $recording) {
                RecordSheet { file, duration in
                    draft = EntryDraft(audioFile: file, duration: duration)
                }
            }
            .sheet(item: $editingReminder) { ReminderEditorView(reminder: $0) }
        }
    }

    private var needingAttention: [Friend] {
        friends.filter { $0.status(now: now).needsAttention }
            .sorted { $0.status(now: now).urgency > $1.status(now: now).urgency }
    }

    @ViewBuilder private var attention: some View {
        let people = needingAttention
        SectionLabel(people.isEmpty ? "Catch up" : "Catch up · \(people.count)")
        if friends.isEmpty {
            EmptyPanel(icon: "person.2", title: "No friends yet",
                       hint: "Add people from Contacts in the People tab. Each one gets a circle, and the circle sets how often you'd like to be in touch.")
        } else if people.isEmpty {
            EmptyPanel(icon: "checkmark.seal", title: "Everyone's in touch",
                       hint: "Nobody is past their usual cadence. Log a note when you talk to someone.")
        } else {
            ForEach(people.prefix(8)) { friend in
                NavigationLink(value: friend) { FriendRow(friend: friend, now: now) }
                    .buttonStyle(.plain)
            }
            if people.count > 8 {
                NavigationLink { PeopleView(initialFilter: .attention) } label: {
                    Text("All \(people.count)").font(.footnote.weight(.semibold))
                }
            }
        }
    }

    @ViewBuilder private var followUps: some View {
        let soon = reminders.filter { Dates.daysBetween(now, $0.due) <= 7 }
        HStack {
            SectionLabel("Follow-ups")
            Spacer()
            NavigationLink { RemindersView() } label: {
                Text("All \(reminders.count)").font(.caption.weight(.semibold))
            }
        }
        if soon.isEmpty {
            EmptyPanel(icon: "bell", title: "Nothing due this week",
                       hint: "Follow-ups come from notes — mention an interview next Thursday and Tend will offer to remind you Friday.")
        } else {
            ForEach(soon) { reminder in
                ReminderRow(reminder: reminder, now: now) { complete(reminder) }
                    .onTapGesture { editingReminder = reminder }
            }
        }
    }

    @ViewBuilder private var birthdays: some View {
        let upcoming: [(ImportantDate, Date)] = friends.flatMap { friend in
            (friend.dates ?? []).compactMap { date in
                guard let next = date.next(after: now), Dates.daysBetween(now, next) <= 14 else { return nil }
                return (date, next)
            }
        }.sorted { $0.1 < $1.1 }
        if !upcoming.isEmpty {
            SectionLabel("Dates")
            ForEach(upcoming, id: \.0.id) { date, next in
                if let friend = date.friend {
                    NavigationLink(value: friend) {
                        HStack(spacing: 12) {
                            Avatar(friend: friend, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(friend.displayName).font(.subheadline.weight(.semibold))
                                Text("\(date.label) · \(Dates.until(next, now: now))"
                                     + (date.ageTurning(on: next).map { " · turns \($0)" } ?? ""))
                                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                            Spacer()
                            Image(systemName: "gift").foregroundStyle(Theme.accent)
                        }
                        .panel()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private var recent: some View {
        if !entries.isEmpty {
            SectionLabel("Recent")
            ForEach(entries.prefix(5)) { entry in
                EntryRow(entry: entry, now: now)
                    .onTapGesture { draft = EntryDraft(entry: entry) }
            }
        }
    }

    private func complete(_ reminder: Reminder) {
        reminder.done.toggle()
        reminder.doneAt = reminder.done ? now : nil
        try? context.save()
        Task { await Notifier.reschedule(context: context) }
    }
}
