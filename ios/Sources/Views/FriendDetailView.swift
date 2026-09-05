// One friend: how to reach them, what to remember, what is coming up,
// and everything said so far — ordered as a prep card before a call.

import SwiftData
import SwiftUI
import UIKit

struct FriendDetailView: View {
    @Bindable var friend: Friend
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var draft: EntryDraft?
    @State private var recording = false
    @State private var newFact = false
    @State private var newReminder: Reminder?
    @State private var editingReminder: Reminder?
    @State private var confirmDelete = false
    @State private var refreshNote: String?
    @State private var player = Player()
    @State private var engine = SummaryEngine.shared
    private let now = Date()

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    hero
                    reach
                    if case .snoozed(let until) = friend.status(now: now) { snoozed(until) }
                    summary
                    about
                    followUps
                    dates
                    timeline
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { menu }
        }
        .overlay(alignment: .bottomTrailing) {
            CaptureButtons(onRecord: { recording = true },
                           onNote: { draft = EntryDraft(friends: [friend]) })
        }
        .sheet(isPresented: $editing) { FriendEditorView(friend: friend, isNew: false) }
        .sheet(item: $draft) { EntryEditorView(draft: $0) }
        .sheet(isPresented: $recording) {
            RecordSheet { file, duration in
                draft = EntryDraft(friends: [friend], audioFile: file, duration: duration)
            }
        }
        .sheet(isPresented: $newFact) { FactEditorView(friend: friend) }
        .sheet(item: $newReminder) { ReminderEditorView(reminder: $0, isNew: true) }
        .sheet(item: $editingReminder) { ReminderEditorView(reminder: $0) }
        .confirmationDialog("Delete \(friend.displayName)? Their notes and reminders go too.",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(friend)
                try? context.save()
                Task { await Notifier.reschedule(context: context) }
                dismiss()
            }
        }
        .alert("Contacts", isPresented: .init(get: { refreshNote != nil }, set: { if !$0 { refreshNote = nil } })) {
            Button("OK") {}
        } message: { Text(refreshNote ?? "") }
    }

    // MARK: sections

    private var hero: some View {
        ZStack {
            if let data = friend.photo, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 180)
                    .blur(radius: 40)
                    .opacity(0.5)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
            } else {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Theme.accent.opacity(0.18))
                    .frame(height: 180)
            }
            VStack(spacing: 8) {
                Avatar(friend: friend, size: 84)
                    .shadow(color: .black.opacity(0.4), radius: 14, y: 8)
                Text(friend.displayName)
                    .font(.title2.weight(.bold))
                HStack(spacing: 6) {
                    Text(heroMeta).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    StatusBadge(status: friend.status(now: now))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var heroMeta: String {
        var parts = [friend.groupName]
        if let cadence = friend.effectiveCadenceDays { parts.append("every \(cadence)d") }
        if let last = friend.lastContact { parts.append(Dates.since(last, now: now)) }
        if !friend.location.isEmpty { parts.append(friend.location) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var reach: some View {
        let methods = friend.sortedMethods
        if methods.isEmpty {
            Button { editing = true } label: {
                Label("Add a way to reach them", systemImage: "plus.circle")
                    .font(.footnote.weight(.semibold))
            }
        } else {
            ChipStrip(spacing: 10) {
                ForEach(methods) { method in
                    MethodButton(method: method, friendId: friend.id)
                }
            }
        }
    }

    private func snoozed(_ until: Date) -> some View {
        HStack {
            Label("Snoozed until \(until.formatted(.dateTime.month(.abbreviated).day()))", systemImage: "zzz")
                .font(.footnote)
            Spacer()
            Button("Wake") {
                friend.snoozedUntil = nil
                save()
            }
            .font(.footnote.weight(.semibold))
        }
        .panel()
    }

    /// What to remember right now — rebuilt after each log, or on demand.
    private var summary: some View {
        let updating = engine.inFlight.contains(friend.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Summary")
                Spacer()
                if updating {
                    ProgressView().controlSize(.small)
                } else {
                    Button { Task { await engine.refresh(friend, context: context) } } label: {
                        Image(systemName: "arrow.clockwise").font(.caption.weight(.bold))
                    }
                }
            }
            if !friend.summary.isEmpty {
                Text(friend.summary).font(.subheadline)
                if let at = friend.summaryUpdatedAt {
                    Text("Updated \(Dates.since(at, now: now)) · \(SuggestionEngine.usesLanguageModel ? "written on your device" : "from your notes")")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            } else if updating {
                Text("Writing…").font(.footnote).foregroundStyle(.tertiary)
            } else {
                Text("Builds itself after each log. Tap ↻ to write one now from what's here.")
                    .font(.footnote).foregroundStyle(.tertiary)
            }
        }
        .panel()
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("About")
                Spacer()
                Button { newFact = true } label: { Image(systemName: "plus").font(.caption.weight(.bold)) }
            }
            if !friend.about.isEmpty {
                Text(friend.about).font(.subheadline)
            }
            if !friend.howWeMet.isEmpty {
                (Text("Met ").foregroundStyle(.secondary) + Text(friend.howWeMet)).font(.subheadline)
            }
            let facts = friend.sortedFacts
            if facts.isEmpty && friend.about.isEmpty && friend.howWeMet.isEmpty {
                Text("Partner, kids, job, what they're into — the things you'd hate to have to ask twice.")
                    .font(.footnote).foregroundStyle(.tertiary)
            }
            ForEach(facts) { fact in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(fact.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(width: 84, alignment: .leading)
                    Text(fact.value).font(.subheadline)
                    Spacer(minLength: 0)
                }
                .contextMenu {
                    Button(role: .destructive) {
                        context.delete(fact)
                        save()
                    } label: { Label("Delete", systemImage: "trash") }
                }
            }
            if !friend.tags.isEmpty {
                Text(friend.tags.map { "#\($0)" }.joined(separator: " "))
                    .font(.caption).foregroundStyle(Theme.accent)
            }
        }
        .panel()
    }

    private var followUps: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Follow-ups")
                Spacer()
                Button {
                    let reminder = Reminder(title: "", due: Dates.at(hour: 9, on: Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now), kind: .custom)
                    reminder.friend = friend
                    context.insert(reminder)
                    newReminder = reminder
                } label: { Image(systemName: "plus").font(.caption.weight(.bold)) }
            }
            let open = friend.openReminders
            if open.isEmpty {
                Text("Nothing pending.").font(.footnote).foregroundStyle(.tertiary)
            }
            ForEach(open) { reminder in
                Button { editingReminder = reminder } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Button {
                            reminder.done = true
                            reminder.doneAt = now
                            save()
                        } label: { Image(systemName: "circle").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reminder.title).font(.subheadline.weight(.semibold))
                            Text(Dates.until(reminder.due, now: now) + " · " + reminder.due.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                                .font(.caption).foregroundStyle(reminder.due < now ? Theme.warn : .secondary).monospacedDigit()
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .panel()
    }

    @ViewBuilder private var dates: some View {
        let list = (friend.dates ?? []).compactMap { d -> (ImportantDate, Date)? in
            d.next(after: now).map { (d, $0) }
        }.sorted { $0.1 < $1.1 }
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Dates")
                ForEach(list, id: \.0.id) { date, next in
                    HStack {
                        Text(date.label).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(next.formatted(.dateTime.month(.abbreviated).day()) + " · " + Dates.until(next, now: now)
                             + (date.ageTurning(on: next).map { " · \($0)" } ?? ""))
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            .panel()
        }
    }

    @ViewBuilder private var timeline: some View {
        let entries = friend.sortedEntries
        SectionLabel(entries.isEmpty ? "Timeline" : "Timeline · \(entries.count)")
        if entries.isEmpty {
            EmptyPanel(icon: "text.bubble", title: "Nothing logged yet",
                       hint: "After you talk, tap the pencil or the mic. Notes that mention an upcoming event turn into follow-ups.")
        }
        ForEach(entries) { entry in
            Button { draft = EntryDraft(entry: entry) } label: {
                EntryRow(entry: entry, showFriends: false, now: now)
            }
            .buttonStyle(.plain)
        }
    }

    private var menu: some View {
        Menu {
            Button { editing = true } label: { Label("Edit", systemImage: "pencil") }
            Menu {
                Button("1 week") { snooze(weeks: 1) }
                Button("2 weeks") { snooze(weeks: 2) }
                Button("1 month") { snooze(weeks: 4) }
            } label: { Label("Snooze nudges", systemImage: "zzz") }
            if friend.contactIdentifier != nil {
                Button { refreshFromContacts() } label: { Label("Refresh from Contacts", systemImage: "person.crop.circle.badge.checkmark") }
            }
            Button { Task { await engine.refresh(friend, context: context) } } label: { Label("Rebuild summary", systemImage: "text.badge.checkmark") }
            Button { friend.archived.toggle(); save() } label: {
                Label(friend.archived ? "Unarchive" : "Archive", systemImage: "archivebox")
            }
            Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    // MARK: actions

    private func snooze(weeks: Int) {
        friend.snoozedUntil = Calendar.current.date(byAdding: .weekOfYear, value: weeks, to: now)
        save()
    }

    private func refreshFromContacts() {
        guard let id = friend.contactIdentifier else { return }
        Task {
            guard await ContactsService.requestAccess() else {
                refreshNote = "Contacts access is off. Enable it in Settings → Tend."
                return
            }
            do {
                let contact = try ContactsService.fetch(identifier: id)
                ContactsService.apply(contact, to: friend, context: context, overwrite: true)
                save()
                refreshNote = "Updated from Contacts."
            } catch {
                refreshNote = "That contact no longer exists. Link them again from Edit."
            }
        }
    }

    private func save() {
        friend.updatedAt = now
        try? context.save()
        Task { await Notifier.reschedule(context: context) }
    }
}

/// One way to reach someone. A phone number is five channels, so it
/// opens a menu; everything else opens directly. A method with no link
/// (a WeChat id) copies itself.
struct MethodButton: View {
    let method: ContactMethod
    let friendId: UUID
    @State private var copied = false

    var body: some View {
        Group {
            if method.kind == .phone {
                Menu {
                    ForEach([ContactKind.phone, .sms, .facetime, .facetimeAudio, .whatsapp], id: \.self) { channel in
                        if let url = ContactLinks.url(kind: channel, value: method.value) {
                            Button { PendingContact.open(url, kind: channel, friendId: friendId) } label: {
                                Label(channel.label, systemImage: channel.icon)
                            }
                        }
                    }
                    Button { copy() } label: { Label("Copy number", systemImage: "doc.on.doc") }
                } label: { face }
            } else if let url = method.url {
                Button { PendingContact.open(url, kind: method.kind, friendId: friendId) } label: { face }
            } else {
                Button { copy() } label: { face }
            }
        }
        .glassButton(prominent: method.preferred)
        .sensoryFeedback(.success, trigger: copied)
    }

    private var face: some View {
        HStack(spacing: 6) {
            Image(systemName: method.kind.icon).font(.subheadline.weight(.semibold))
            Text(method.label.isEmpty ? method.kind.label : "\(method.kind.label) · \(method.label)")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 3)
        .foregroundStyle(method.preferred ? Color.white : Color.primary)
    }

    private func copy() {
        UIPasteboard.general.string = method.value
        copied.toggle()
    }
}

struct FactEditorView: View {
    let friend: Friend
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var value = ""
    @AppStorage("appearance") private var appearance = Appearance.dark.rawValue

    var body: some View {
        NavigationStack {
            PanelScroll {
                SectionLabel("Label")
                ChipStrip(wraps: true) {
                    ForEach(Fact.commonLabels, id: \.self) { l in
                        GlassChip(active: label == l, action: { label = l }) {
                            Text(l).font(.subheadline.weight(.semibold))
                        }
                    }
                }
                TextField("Or your own label", text: $label).textFieldStyle(.roundedBorder)
                SectionLabel("Value")
                TextField("Maya · Stripe · pour-over kettle…", text: $value, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
            }
            .navigationTitle("Fact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let fact = Fact(label: label.trimmingCharacters(in: .whitespaces), value: value.trimmingCharacters(in: .whitespacesAndNewlines))
                        fact.friend = friend
                        context.insert(fact)
                        friend.updatedAt = Date()
                        try? context.save()
                        dismiss()
                    }
                    .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty || value.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
    }
}
