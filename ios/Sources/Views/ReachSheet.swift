// Every way to reach one person, as a sheet: a number fans out into its
// channels, everything else is a row of its own, and a method with no
// link copies itself. Tapping one leaves the app and, on return, the
// "did you reach them?" question is waiting.

import SwiftUI
import UIKit

struct ReachSheet: View {
    let friend: Friend
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = Appearance.dark.rawValue
    @State private var copied = false

    private struct Way: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let url: URL?
        let kind: ContactKind
        let value: String
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                List {
                    HStack(spacing: 12) {
                        Avatar(friend: friend, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(friend.displayName).font(.headline)
                            if let last = friend.lastContact {
                                Text("last talked \(Dates.since(last, now: Date()))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .plainRow()
                    if ways.isEmpty {
                        EmptyPanel(icon: "phone.badge.plus", title: "No way to reach them yet",
                                   hint: "Add a number or a handle under Edit → Reach on their page, or link their contact.")
                            .plainRow()
                    }
                    ForEach(ways) { way in
                        Button {
                            if let url = way.url {
                                PendingContact.open(url, kind: way.kind, friendId: friend.id)
                                dismiss()
                            } else {
                                UIPasteboard.general.string = way.value
                                copied.toggle()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: way.icon)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(way.title).font(.subheadline.weight(.semibold))
                                    Text(way.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: way.url == nil ? "doc.on.doc" : "arrow.up.right")
                                    .font(.caption).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                            .panel()
                        }
                        .buttonStyle(.plain)
                        .plainRow()
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Reach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sensoryFeedback(.success, trigger: copied)
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
    }

    /// Phone numbers first, each as its channels, then the rest in the
    /// app's usual order.
    private var ways: [Way] {
        var out: [Way] = []
        for method in friend.sortedMethods {
            let label = method.label.isEmpty ? method.value : "\(method.label) · \(method.value)"
            if method.kind == .phone {
                for channel in [ContactKind.phone, .sms, .facetime, .facetimeAudio, .whatsapp] {
                    guard let url = ContactLinks.url(kind: channel, value: method.value) else { continue }
                    out.append(Way(id: "\(method.id)-\(channel.rawValue)", title: channel.label, subtitle: label,
                                   icon: channel.icon, url: url, kind: channel, value: method.value))
                }
            } else {
                out.append(Way(id: method.id.uuidString, title: method.kind.label, subtitle: method.url == nil ? "\(method.value) · copy" : label,
                               icon: method.kind.icon, url: method.url, kind: method.kind, value: method.value))
            }
        }
        return out
    }
}
