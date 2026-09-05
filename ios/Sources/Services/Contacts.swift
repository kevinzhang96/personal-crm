// The bridge to the phone's address book: pick a contact, and copy what
// it knows into a friend. One-way — nothing is ever written to Contacts.

import Contacts
import ContactsUI
import SwiftData
import SwiftUI

struct ContactPicker: UIViewControllerRepresentable {
    let onPick: (CNContact) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (CNContact) -> Void
        init(onPick: @escaping (CNContact) -> Void) { self.onPick = onPick }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onPick(contact)
        }
    }
}

/// The same picker, in the mode where the delegate takes a list: that is
/// what makes CNContactPickerViewController offer multi-select. A
/// separate type rather than a flag, because the mode is decided by
/// which delegate method exists, not by what it does.
struct ContactsMultiPicker: UIViewControllerRepresentable {
    let onPick: ([CNContact]) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: ([CNContact]) -> Void
        init(onPick: @escaping ([CNContact]) -> Void) { self.onPick = onPick }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            onPick(contacts)
        }
    }
}

enum ContactsService {
    /// What to call someone the picker handed over: their name, failing
    /// that their company, failing that how to reach them.
    static func displayName(_ contact: CNContact) -> String {
        if contact.isKeyAvailable(CNContactGivenNameKey), contact.isKeyAvailable(CNContactFamilyNameKey),
           let full = CNContactFormatter.string(from: contact, style: .fullName), !full.isEmpty {
            return full
        }
        if contact.isKeyAvailable(CNContactOrganizationNameKey), !contact.organizationName.isEmpty {
            return contact.organizationName
        }
        if contact.isKeyAvailable(CNContactPhoneNumbersKey), let phone = contact.phoneNumbers.first {
            return phone.value.stringValue
        }
        if contact.isKeyAvailable(CNContactEmailAddressesKey), let email = contact.emailAddresses.first {
            return email.value as String
        }
        return ""
    }

    static let keys: [CNKeyDescriptor] = [
        CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactNicknameKey as CNKeyDescriptor,
        CNContactThumbnailImageDataKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactBirthdayKey as CNKeyDescriptor,
        CNContactSocialProfilesKey as CNKeyDescriptor,
        CNContactInstantMessageAddressesKey as CNKeyDescriptor,
        CNContactPostalAddressesKey as CNKeyDescriptor,
    ]

    static var authorized: Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        return status == .authorized || status == .limited
    }

    static func requestAccess() async -> Bool {
        if authorized { return true }
        return (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
    }

    /// The full record behind a picker result or a stored link. The picker
    /// hands back whatever it chooses to; this asks for every key the app
    /// reads, so the guards in `apply` are for the picker path only.
    static func fetch(identifier: String) throws -> CNContact {
        try CNContactStore().unifiedContact(withIdentifier: identifier, keysToFetch: keys)
    }

    /// Copies the contact into the friend. Blank fields are filled and
    /// the link is set; existing methods are kept, and new ones are added
    /// only when the same kind and value are not already there.
    @MainActor
    static func apply(_ contact: CNContact, to friend: Friend, context: ModelContext, overwrite: Bool = false) {
        func has(_ key: String) -> Bool { contact.isKeyAvailable(key) }

        friend.contactIdentifier = contact.identifier
        if has(CNContactGivenNameKey) { friend.givenName = contact.givenName }
        if has(CNContactFamilyNameKey) { friend.familyName = contact.familyName }
        if has(CNContactNicknameKey), overwrite || friend.nickname.isEmpty { friend.nickname = contact.nickname }
        let full = (has(CNContactGivenNameKey) && has(CNContactFamilyNameKey))
            ? (CNContactFormatter.string(from: contact, style: .fullName) ?? "")
            : ""
        if overwrite || friend.displayName.isEmpty {
            friend.displayName = full.isEmpty ? [friend.givenName, friend.familyName].filter { !$0.isEmpty }.joined(separator: " ") : full
        }
        if has(CNContactThumbnailImageDataKey), let data = contact.thumbnailImageData, overwrite || friend.photo == nil {
            friend.photo = data
        }

        var existing = Set((friend.methods ?? []).map { "\($0.kindRaw)|\($0.value)" })
        func add(_ kind: ContactKind, _ value: String, label: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, existing.insert("\(kind.rawValue)|\(trimmed)").inserted else { return }
            let method = ContactMethod(kind: kind, value: trimmed, label: label)
            method.friend = friend
            context.insert(method)
        }
        func label(_ raw: String?) -> String {
            raw.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) } ?? ""
        }
        if has(CNContactPhoneNumbersKey) {
            for phone in contact.phoneNumbers { add(.phone, phone.value.stringValue, label: label(phone.label)) }
        }
        if has(CNContactEmailAddressesKey) {
            for email in contact.emailAddresses { add(.email, email.value as String, label: label(email.label)) }
        }
        if has(CNContactSocialProfilesKey) {
            for profile in contact.socialProfiles {
                let p = profile.value
                guard let kind = kind(forService: p.service) else { continue }
                add(kind, p.username.isEmpty ? p.urlString : p.username, label: "")
            }
        }
        if has(CNContactInstantMessageAddressesKey) {
            for im in contact.instantMessageAddresses {
                guard let kind = kind(forService: im.value.service) else { continue }
                add(kind, im.value.username, label: "")
            }
        }
        if has(CNContactBirthdayKey), let b = contact.birthday, let month = b.month, let day = b.day, friend.birthday == nil {
            let date = ImportantDate(label: ImportantDate.birthdayLabel, month: month, day: day, year: b.year)
            date.friend = friend
            context.insert(date)
        }
        if has(CNContactPostalAddressesKey), friend.location.isEmpty, let address = contact.postalAddresses.first?.value {
            friend.location = [address.city, address.state].filter { !$0.isEmpty }.joined(separator: ", ")
        }
        friend.updatedAt = Date()
    }

    /// Contacts stores whatever service name the messaging app registered;
    /// the match is by substring, case-insensitively, for that reason.
    private static func kind(forService service: String) -> ContactKind? {
        let s = service.lowercased()
        if s.contains("whatsapp") { return .whatsapp }
        if s.contains("telegram") { return .telegram }
        if s.contains("signal") { return .signal }
        if s.contains("instagram") { return .instagram }
        if s.contains("messenger") || s.contains("facebook") { return .messenger }
        if s.contains("twitter") || s == "x" { return .x }
        if s.contains("linkedin") { return .linkedin }
        if s.contains("snapchat") { return .snapchat }
        if s.contains("wechat") || s.contains("weixin") { return .wechat }
        if s.contains("discord") { return .discord }
        return nil
    }
}
