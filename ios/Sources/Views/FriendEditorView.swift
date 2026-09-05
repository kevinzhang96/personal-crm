// Everything about a friend that is typed rather than logged. The friend
// already exists in the context when this opens; a new one that is
// cancelled is deleted again, so the store never keeps a blank.

import Contacts
import SwiftData
import SwiftUI

struct FriendEditorView: View {
    @Bindable var friend: Friend
    let isNew: Bool
    @Query(sort: \FriendGroup.order) private var groups: [FriendGroup]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = Appearance.dark.rawValue
    @State private var pickingContact = false
    @State private var tagsText = ""
    @State private var customCadence = false
    @State private var cadence = 30
    @State private var birthdayKnown = false
    @State private var birthday = Date()
    @State private var yearKnown = false
    @State private var newDateLabel = ""
    @State private var newDate = Date()
    @State private var contactNote: String?

    var body: some View {
        NavigationStack {
            PanelScroll {
                identity
                circle
                details
                methods
                dates
            }
            .navigationTitle(isNew ? "New friend" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isNew { context.delete(friend) }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(friend.displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
            .sheet(isPresented: $pickingContact) {
                ContactPicker { contact in
                    pickingContact = false
                    link(contact)
                }
                .ignoresSafeArea()
            }
            .alert("Contacts", isPresented: .init(get: { contactNote != nil }, set: { if !$0 { contactNote = nil } })) {
                Button("OK") {}
            } message: { Text(contactNote ?? "") }
        }
        .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
        .interactiveDismissDisabled(isNew)
    }

    // MARK: sections

    private var identity: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Avatar(friend: friend, size: 64)
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Name", text: $friend.displayName)
                        .font(.headline)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                    TextField("Nickname", text: $friend.nickname)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.nickname)
                        .autocorrectionDisabled()
                }
            }
            Button { pickingContact = true } label: {
                Label(friend.contactIdentifier == nil ? "Link a contact" : "Re-link contact", systemImage: "person.crop.circle.badge.plus")
                    .font(.footnote.weight(.semibold))
            }
        }
        .panel()
    }

    private var circle: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Groups")
            ChipStrip(wraps: true) {
                ForEach(groups) { g in
                    GlassChip(active: friend.isIn(g), action: { toggle(g) }) {
                        VStack(spacing: 1) {
                            Text(g.name).font(.subheadline.weight(.semibold))
                            Text(g.cadenceLabel)
                                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }
            Toggle("Custom cadence", isOn: $customCadence.animation())
                .font(.subheadline)
            if customCadence {
                Stepper("Every \(cadence) days", value: $cadence, in: 1...730, step: cadence >= 60 ? 30 : cadence >= 14 ? 7 : 1)
                    .font(.subheadline)
                    .monospacedDigit()
            }
        }
        .panel()
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Details")
            TextField("Tags, comma separated", text: $tagsText).textFieldStyle(.roundedBorder)
            TextField("Where they live", text: $friend.location).textFieldStyle(.roundedBorder)
            TextField("How you met", text: $friend.howWeMet).textFieldStyle(.roundedBorder)
            TextField("About them", text: $friend.about, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...6)
            Toggle("Birthday", isOn: $birthdayKnown.animation()).font(.subheadline)
            if birthdayKnown {
                DatePicker("Date", selection: $birthday, displayedComponents: .date)
                    .font(.subheadline)
                Toggle("Year is right", isOn: $yearKnown).font(.subheadline)
            }
        }
        .panel()
    }

    private var methods: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Reach")
                Spacer()
                Menu {
                    ForEach(ContactKind.allCases) { kind in
                        Button { add(kind) } label: { Label(kind.label, systemImage: kind.icon) }
                    }
                } label: { Image(systemName: "plus").font(.caption.weight(.bold)) }
            }
            let list = friend.sortedMethods
            if list.isEmpty {
                Text("Numbers, handles, emails. Linking a contact fills these in.")
                    .font(.footnote).foregroundStyle(.tertiary)
            }
            ForEach(list) { method in
                MethodEditorRow(method: method) {
                    context.delete(method)
                }
            }
        }
        .panel()
    }

    private var dates: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Other dates")
            let others = (friend.dates ?? []).filter { $0.label.caseInsensitiveCompare(ImportantDate.birthdayLabel) != .orderedSame }
            ForEach(others) { date in
                HStack {
                    Text(date.label).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(String(format: "%02d/%02d", date.month, date.day)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    Button(role: .destructive) { context.delete(date) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain)
                }
            }
            HStack {
                TextField("Anniversary, name day…", text: $newDateLabel).textFieldStyle(.roundedBorder)
                DatePicker("", selection: $newDate, displayedComponents: .date).labelsHidden()
                Button {
                    let parts = Calendar.current.dateComponents([.month, .day], from: newDate)
                    let date = ImportantDate(label: newDateLabel.trimmingCharacters(in: .whitespaces), month: parts.month ?? 1, day: parts.day ?? 1)
                    date.friend = friend
                    context.insert(date)
                    newDateLabel = ""
                } label: { Image(systemName: "plus.circle.fill") }
                .disabled(newDateLabel.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .panel()
    }

    // MARK: state

    private func load() {
        if (friend.groups ?? []).isEmpty, let home = Groups.defaultGroup(groups) { friend.groups = [home] }
        tagsText = friend.tags.joined(separator: ", ")
        customCadence = friend.cadenceDays != nil
        cadence = friend.cadenceDays ?? friend.effectiveCadenceDays ?? 30
        if let b = friend.birthday {
            birthdayKnown = true
            yearKnown = b.year != nil
            var parts = DateComponents()
            parts.year = b.year ?? Calendar.current.component(.year, from: Date())
            parts.month = b.month
            parts.day = b.day
            birthday = Calendar.current.date(from: parts) ?? Date()
        }
    }

    private func toggle(_ group: FriendGroup) {
        if friend.isIn(group) {
            friend.groups?.removeAll { $0.id == group.id }
        } else {
            friend.groups = (friend.groups ?? []) + [group]
        }
    }

    private func add(_ kind: ContactKind) {
        let method = ContactMethod(kind: kind, value: "")
        method.friend = friend
        context.insert(method)
    }

    private func link(_ contact: CNContact) {
        Task {
            var full = contact
            if await ContactsService.requestAccess(), let fetched = try? ContactsService.fetch(identifier: contact.identifier) {
                full = fetched
            }
            ContactsService.apply(full, to: friend, context: context)
            load()
        }
    }

    private func save() {
        friend.displayName = friend.displayName.trimmingCharacters(in: .whitespaces)
        // Nobody is in no group; a friend cleared of every chip lands in the default.
        if (friend.groups ?? []).isEmpty, let home = Groups.defaultGroup(groups) { friend.groups = [home] }
        friend.tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        friend.cadenceDays = customCadence ? cadence : nil
        // Blank methods are mis-taps on +, not data.
        for method in friend.methods ?? [] where method.value.trimmingCharacters(in: .whitespaces).isEmpty {
            context.delete(method)
        }
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: birthday)
        if birthdayKnown, let month = parts.month, let day = parts.day {
            if let existing = friend.birthday {
                existing.month = month
                existing.day = day
                existing.year = yearKnown ? parts.year : nil
            } else {
                let date = ImportantDate(label: ImportantDate.birthdayLabel, month: month, day: day, year: yearKnown ? parts.year : nil)
                date.friend = friend
                context.insert(date)
            }
        } else if let existing = friend.birthday {
            context.delete(existing)
        }
        friend.updatedAt = Date()
        try? context.save()
        Task { await Notifier.reschedule(context: context) }
        dismiss()
    }
}

struct MethodEditorRow: View {
    @Bindable var method: ContactMethod
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(ContactKind.allCases) { kind in
                    Button { method.kind = kind } label: { Label(kind.label, systemImage: kind.icon) }
                }
            } label: {
                Image(systemName: method.kind.icon)
                    .frame(width: 28)
            }
            TextField(method.kind.placeholder, text: $method.value)
                .textFieldStyle(.roundedBorder)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button { method.preferred.toggle() } label: {
                Image(systemName: method.preferred ? "star.fill" : "star")
                    .foregroundStyle(method.preferred ? Theme.accent : .secondary)
            }
            .buttonStyle(.plain)
            Button(role: .destructive, action: onDelete) { Image(systemName: "minus.circle") }
                .buttonStyle(.plain)
        }
    }

    private var keyboard: UIKeyboardType {
        switch method.kind {
        case .phone, .sms, .facetime, .facetimeAudio, .whatsapp, .signal: .phonePad
        case .email: .emailAddress
        case .url: .URL
        default: .default
        }
    }
}
