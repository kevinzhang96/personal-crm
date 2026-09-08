// Choosing people from Contacts, with the question of access asked
// first, once, and plainly: a word on why, the system prompt, then the
// app's own searchable list. The system picker used to open before
// access was asked, so on iOS 18 the "select contacts" sheet surfaced
// after a pick — and once an app is limited, asking again does nothing,
// because Apple leaves that upgrade to Settings. The list is the app's
// because the system picker has no search the app can reach; what iOS
// keeps for itself is the choice of full or limited access.

import Contacts
import ContactsUI
import SwiftUI
import UIKit

struct ContactsSheet: View {
    enum Mode {
        case one((CNContact) -> Void)
        case many(([CNContact]) -> Void)
    }

    let mode: Mode
    /// The way to add someone without Contacts at all.
    var onManual: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = Appearance.dark.rawValue
    @State private var status = ContactsService.status
    @State private var contacts: [CNContact] = []
    @State private var loaded = false
    @State private var selected: Set<String> = []
    @State private var search = ""
    @State private var addingMore = false
    @FocusState private var focused: Bool

    private var many: Bool {
        if case .many = mode { return true }
        return false
    }

    private var canRead: Bool { status == .authorized || status == .limited }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                switch status {
                case .notDetermined: priming
                case .authorized, .limited: list
                default: blocked
                }
            }
            .navigationTitle(many ? "From Contacts" : "Link a contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if many, canRead {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(selected.isEmpty ? "Add" : "Add \(selected.count)") { finish() }.disabled(selected.isEmpty)
                    }
                }
            }
            // iOS 18's own sheet for widening a limited grant; the list
            // reloads with whatever was added.
            .contactAccessPicker(isPresented: $addingMore) { _ in reload() }
            .task(id: status) { if canRead { reload() } }
        }
        .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
    }

    // MARK: not yet asked

    private var priming: some View {
        PanelScroll {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "person.crop.circle.badge.checkmark").font(.title).foregroundStyle(Theme.accent)
                Text("Tend reads your contacts to fill in names, photos and ways to reach people.")
                    .font(.subheadline.weight(.semibold))
                Text("Nothing is written back. Allow full access to search everyone; if you share only some contacts, only those will show here, and adding more later goes through Settings.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button { ask() } label: {
                    Text("Continue").font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .glassButton(prominent: true)
                if let onManual {
                    Button("Enter a name instead") {
                        dismiss()
                        onManual()
                    }
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
            }
            .panel()
        }
    }

    private func ask() {
        Task {
            _ = await ContactsService.requestAccess()
            status = ContactsService.status
        }
    }

    // MARK: the list

    private var list: some View {
        VStack(spacing: 8) {
            field
            if status == .limited { limitedBanner }
            List {
                if !loaded {
                    ProgressView().frame(maxWidth: .infinity).plainRow()
                } else if shown.isEmpty {
                    EmptyPanel(icon: "person.fill.questionmark",
                               title: search.isEmpty ? "No contacts to show" : "No one called “\(search)”",
                               hint: status == .limited ? "Only the contacts you've shared with Tend are here." : "Try another spelling.")
                        .plainRow()
                }
                ForEach(shown, id: \.identifier) { row($0) }
                if status == .limited, !search.trimmingCharacters(in: .whitespaces).isEmpty {
                    // The one thing the app cannot list: matches outside its
                    // grant. Apple's button shows them and, on a tap, shares them.
                    ContactAccessButton(queryString: search) { _ in reload() }
                        .contactAccessButtonCaption(.defaultText)
                        .plainRow()
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Name, company, number", text: $search)
                .focused($focused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.body)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .task {
            try? await Task.sleep(for: .milliseconds(150))
            focused = true
        }
    }

    private var limitedBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("You're sharing \(contacts.count) contact\(contacts.count == 1 ? "" : "s") with Tend.")
                .font(.subheadline.weight(.semibold))
            Text("Add more here, or allow full access in Settings — that switch is iOS's, not the app's.")
                .font(.caption2).foregroundStyle(.tertiary)
            HStack(spacing: 16) {
                Button { addingMore = true } label: { Label("Add more", systemImage: "person.badge.plus") }
                Button { openSettings() } label: { Label("Settings", systemImage: "gear") }
            }
            .font(.subheadline.weight(.semibold))
        }
        .panel()
        .padding(.horizontal, 16)
    }

    private func row(_ contact: CNContact) -> some View {
        let name = ContactsService.displayName(contact)
        let on = selected.contains(contact.identifier)
        return Button {
            switch mode {
            case .one(let pick):
                dismiss()
                pick(contact)
            case .many:
                if on { selected.remove(contact.identifier) } else { selected.insert(contact.identifier) }
            }
        } label: {
            HStack(spacing: 12) {
                PhotoCircle(photo: contact.isKeyAvailable(CNContactThumbnailImageDataKey) ? contact.thumbnailImageData : nil,
                            initials: Friend.initials(of: name), size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name.isEmpty ? "Unnamed" : name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    let detail = Self.detail(contact)
                    if !detail.isEmpty {
                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if many {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(on ? Theme.accent : .secondary)
                }
            }
            .panel()
        }
        .buttonStyle(.plain)
        .plainRow()
    }

    /// A second line that tells two people of one name apart.
    private static func detail(_ contact: CNContact) -> String {
        if contact.isKeyAvailable(CNContactOrganizationNameKey), !contact.organizationName.isEmpty { return contact.organizationName }
        if contact.isKeyAvailable(CNContactPhoneNumbersKey), let phone = contact.phoneNumbers.first { return phone.value.stringValue }
        if contact.isKeyAvailable(CNContactEmailAddressesKey), let email = contact.emailAddresses.first { return email.value as String }
        return ""
    }

    private var shown: [CNContact] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return contacts }
        return contacts.filter { c in
            ContactsService.displayName(c).lowercased().contains(q) || Self.detail(c).lowercased().contains(q)
                || (c.isKeyAvailable(CNContactNicknameKey) && c.nickname.lowercased().contains(q))
        }
    }

    private func reload() {
        Task.detached(priority: .userInitiated) {
            let all = (try? ContactsService.all()) ?? []
            await MainActor.run {
                contacts = all
                loaded = true
                status = ContactsService.status
            }
        }
    }

    private func finish() {
        guard case .many(let pick) = mode else { return }
        let chosen = contacts.filter { selected.contains($0.identifier) }
        dismiss()
        pick(chosen)
    }

    // MARK: no access

    private var blocked: some View {
        PanelScroll {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "person.crop.circle.badge.xmark").font(.title).foregroundStyle(Theme.warn)
                Text(status == .restricted ? "Contacts access is restricted on this phone." : "Contacts access is off for Tend.")
                    .font(.subheadline.weight(.semibold))
                Text(status == .restricted
                     ? "A restriction such as Screen Time is in the way; you can still add people by name."
                     : "Turn it on in Settings → Tend → Contacts, or add people by name.")
                    .font(.footnote).foregroundStyle(.secondary)
                if status != .restricted {
                    Button { openSettings() } label: {
                        Label("Open Settings", systemImage: "gear").font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .glassButton(prominent: true)
                }
                if let onManual {
                    Button("Enter a name instead") {
                        dismiss()
                        onManual()
                    }
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
            }
            .panel()
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}
