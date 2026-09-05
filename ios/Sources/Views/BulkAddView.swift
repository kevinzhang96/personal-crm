// Many friends at once — a selection from Contacts, or a pasted list of
// names — reviewed before anything is created: one circle and one set of
// tags for the batch, and anyone already in Tend shown as such.

import Contacts
import SwiftData
import SwiftUI

struct BulkAddView: View {
    enum Source: Identifiable {
        case contacts([CNContact])
        case names

        var id: String {
            switch self {
            case .contacts(let list): "contacts-" + list.map(\.identifier).joined(separator: ",")
            case .names: "names"
            }
        }
    }

    struct Row: Identifiable {
        let id: String
        let name: String
        let photo: Data?
        let contact: CNContact?
        /// The friend this would duplicate, when there is one.
        let existing: Friend?
    }

    let source: Source
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = Appearance.dark.rawValue
    @Query(sort: \Friend.displayName) private var friends: [Friend]
    @State private var text = ""
    @State private var circle: FriendCircle = .friends
    @State private var tagsText = ""
    @State private var excluded: Set<String> = []
    @State private var adding = false
    @FocusState private var textFocused: Bool

    var body: some View {
        NavigationStack {
            PanelScroll {
                if case .names = source { namesPanel }
                batchPanel
                let rows = self.rows
                SectionLabel(rows.isEmpty ? "People" : "Adding \(selected.count) of \(rows.count)")
                if rows.isEmpty {
                    if case .names = source {
                        Text("Names appear here as you type.").font(.footnote).foregroundStyle(.tertiary)
                    }
                }
                ForEach(rows) { rowView($0) }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await add() } } label: {
                        if adding { ProgressView() } else { Text(selected.isEmpty ? "Add" : "Add \(selected.count)") }
                    }
                    .disabled(adding || selected.isEmpty)
                }
            }
            .onAppear { if case .names = source { textFocused = true } }
        }
        .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
        .interactiveDismissDisabled(!text.isEmpty)
    }

    private var title: String {
        switch source {
        case .contacts: "From Contacts"
        case .names: "Paste names"
        }
    }

    // MARK: rows

    private var rows: [Row] {
        switch source {
        case .contacts(let contacts):
            return contacts.map { contact in
                let name = ContactsService.displayName(contact)
                return Row(
                    id: contact.identifier,
                    name: name.isEmpty ? "Unnamed" : name,
                    photo: contact.isKeyAvailable(CNContactThumbnailImageDataKey) ? contact.thumbnailImageData : nil,
                    contact: contact,
                    existing: friends.first { $0.contactIdentifier == contact.identifier })
            }
        case .names:
            return BulkNames.parse(text).map { name in
                Row(id: name.lowercased(), name: name, photo: nil, contact: nil,
                    existing: friends.first { !$0.archived && $0.displayName.caseInsensitiveCompare(name) == .orderedSame })
            }
        }
    }

    private var selected: [Row] {
        rows.filter { $0.existing == nil && !excluded.contains($0.id) }
    }

    private func rowView(_ row: Row) -> some View {
        let on = row.existing == nil && !excluded.contains(row.id)
        return Button {
            if excluded.contains(row.id) { excluded.remove(row.id) } else { excluded.insert(row.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(on ? Theme.accent : .secondary)
                PhotoCircle(photo: row.photo, initials: Friend.initials(of: row.name), size: 34)
                Text(row.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
                if row.existing != nil { Badge("added", tint: Theme.rise) }
            }
            .panel()
        }
        .buttonStyle(.plain)
        .disabled(row.existing != nil)
        .opacity(row.existing != nil ? 0.6 : 1)
    }

    // MARK: panels

    private var namesPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Names")
            TextEditor(text: $text)
                .focused($textFocused)
                .scrollContentBackground(.hidden)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .frame(minHeight: 120)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("One per line\nAna Lu\nBen Ko\n…")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
        }
        .panel()
    }

    private var batchPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Everyone gets")
            ChipStrip(wraps: true) {
                ForEach(FriendCircle.allCases) { c in
                    GlassChip(active: circle == c, action: { circle = c }) {
                        VStack(spacing: 1) {
                            Text(c.label).font(.subheadline.weight(.semibold))
                            Text(c.defaultCadenceDays.map { "\($0)d" } ?? "—")
                                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }
            TextField("Tags, comma separated", text: $tagsText)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
        }
        .panel()
    }

    // MARK: create

    private func add() async {
        adding = true
        let tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        // One permission ask for the batch; without it the picker's copy of
        // each contact is what gets applied, which is still a name and a
        // number.
        var authorized = false
        if case .contacts = source { authorized = await ContactsService.requestAccess() }
        for row in selected {
            let friend = Friend(displayName: row.name, circle: circle)
            friend.tags = tags
            context.insert(friend)
            if let contact = row.contact {
                let full = authorized ? ((try? ContactsService.fetch(identifier: contact.identifier)) ?? contact) : contact
                ContactsService.apply(full, to: friend, context: context)
                if friend.displayName.isEmpty { friend.displayName = row.name }
            }
        }
        try? context.save()
        await Notifier.reschedule(context: context)
        adding = false
        dismiss()
    }
}
