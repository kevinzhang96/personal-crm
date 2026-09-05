// A chooser for one of many named things — groups, tags — as a sheet:
// full-width rows that never wrap, counts, a search field once there are
// enough to need one, and room to grow. A menu wrapped the names and
// stopped fitting; this is what the chips open instead.

import SwiftUI

struct PickSheet: View {
    struct Item: Identifiable {
        let id: String
        let name: String
        let count: Int
    }

    let title: String
    let icon: String
    let items: [Item]
    let selectedId: String?
    /// The word for "no particular one".
    var anyLabel = "Any"
    let onPick: (String?) -> Void
    var onManage: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = Appearance.dark.rawValue
    @State private var filter = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                List {
                    Button {
                        onPick(nil)
                        dismiss()
                    } label: {
                        row(name: anyLabel, count: nil, on: selectedId == nil, icon: "circle.dashed")
                    }
                    .buttonStyle(.plain)
                    .plainRow()
                    ForEach(shown) { item in
                        Button {
                            onPick(item.id)
                            dismiss()
                        } label: {
                            row(name: item.name, count: item.count, on: item.id == selectedId, icon: icon)
                        }
                        .buttonStyle(.plain)
                        .plainRow()
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onManage {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Manage") {
                            dismiss()
                            onManage()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .modifier(SearchWhenMany(count: items.count, text: $filter))
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
    }

    private var shown: [Item] {
        let q = filter.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? items : items.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private func row(name: String, count: Int?, on: Bool, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(on ? Theme.accent : Color.secondary)
                .frame(width: 22)
            Text(name)
                .font(.subheadline.weight(on ? .semibold : .regular))
                .lineLimit(1)
            Spacer()
            if let count {
                Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if on {
                Image(systemName: "checkmark").font(.subheadline.weight(.bold)).foregroundStyle(Theme.accent)
            }
        }
        .contentShape(Rectangle())
        .panel()
    }
}

/// A search field only once the list is long enough to need one.
private struct SearchWhenMany: ViewModifier {
    let count: Int
    @Binding var text: String

    func body(content: Content) -> some View {
        if count > 8 {
            content.searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always))
        } else {
            content
        }
    }
}
