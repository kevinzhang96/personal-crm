// The groups themselves: make one, rename or re-pace one, reorder them,
// delete one — and, since every friend is in a group, say where a deleted
// group's people go.

import SwiftData
import SwiftUI

struct GroupsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = Appearance.dark.rawValue
    @Query(sort: \FriendGroup.order) private var groups: [FriendGroup]
    @State private var editing: FriendGroup?
    @State private var creating: FriendGroup?
    @State private var deleting: FriendGroup?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                List {
                    ForEach(groups) { group in
                        Button { editing = group } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "folder")
                                    .foregroundStyle(Theme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.name.isEmpty ? "Unnamed" : group.name).font(.subheadline.weight(.semibold))
                                    Text("\(group.cadenceSentence) · \(group.memberCount) people")
                                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .panel()
                        }
                        .buttonStyle(.plain)
                        .plainRow()
                        // Not a destructive role: that animates the row away
                        // before the question is asked. The row goes when the
                        // reader has said where its people go.
                        .swipeActions(edge: .trailing) {
                            Button { deleting = group } label: { Label("Delete", systemImage: "trash") }
                                .tint(.red)
                        }
                    }
                    .onMove(perform: move)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    // Reorder only: edit mode's own delete would drop rows
                    // before the confirmation.
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let group = FriendGroup(name: "", cadenceDays: 30, order: (groups.map(\.order).max() ?? -1) + 1)
                        context.insert(group)
                        creating = group
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $editing) { GroupEditorView(group: $0) }
            .sheet(item: $creating) { GroupEditorView(group: $0, isNew: true) }
            .confirmationDialog(deleteTitle, isPresented: .init(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                if let group = deleting {
                    let members = group.friends ?? []
                    if members.isEmpty {
                        Button("Delete \(group.name)", role: .destructive) { delete(group, moving: nil) }
                    } else {
                        ForEach(groups.filter { $0.id != group.id }) { other in
                            Button("Move \(members.count) to \(other.name), then delete") { delete(group, moving: other) }
                        }
                    }
                }
            }
        }
        .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
    }

    private var deleteTitle: String {
        guard let group = deleting else { return "" }
        let n = (group.friends ?? []).count
        if n == 0 { return "Delete \(group.name)? It has nobody in it." }
        if groups.count == 1 { return "\(group.name) is the only group; its \(n) people need somewhere to go. Make another group first." }
        return "Delete \(group.name)? Its \(n) people need a group."
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = groups
        ordered.move(fromOffsets: source, toOffset: destination)
        for (i, group) in ordered.enumerated() { group.order = i }
        try? context.save()
    }

    private func delete(_ group: FriendGroup, moving destination: FriendGroup?) {
        for friend in group.friends ?? [] { friend.group = destination }
        context.delete(group)
        try? context.save()
        Task { await Notifier.reschedule(context: context) }
        deleting = nil
    }
}

struct GroupEditorView: View {
    @Bindable var group: FriendGroup
    var isNew = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = Appearance.dark.rawValue
    @State private var nudges = true
    @State private var days = 30

    var body: some View {
        NavigationStack {
            PanelScroll {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Name", text: $group.name)
                        .font(.headline)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                    Toggle("Nudge me to keep in touch", isOn: $nudges.animation()).font(.subheadline)
                    if nudges {
                        Stepper("Every \(days) days", value: $days, in: 1...730, step: days >= 60 ? 30 : days >= 14 ? 7 : 1)
                            .font(.subheadline)
                            .monospacedDigit()
                        HStack(spacing: 8) {
                            ForEach([("Weekly", 7), ("Monthly", 30), ("Quarterly", 90), ("Yearly", 365)], id: \.1) { label, n in
                                Button(label) { days = n }
                                    .font(.caption.weight(.semibold))
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                    Text("A friend's own cadence, set on their page, overrides the group's.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .panel()
                if !isNew {
                    Text("\(group.memberCount) people").font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(isNew ? "New group" : "Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isNew { context.delete(group) }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(group.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                nudges = group.cadenceDays != nil
                days = group.cadenceDays ?? 30
            }
        }
        .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
        .interactiveDismissDisabled(isNew)
    }

    private func save() {
        group.name = group.name.trimmingCharacters(in: .whitespaces)
        group.cadenceDays = nudges ? days : nil
        try? context.save()
        Task { await Notifier.reschedule(context: context) }
        dismiss()
    }
}
