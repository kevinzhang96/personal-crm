// Everyone, searchable, with the groups as filter chips. "Reach out" is
// the working view: who to contact, most overdue first. Select turns the
// list into a checklist for moving, archiving or deleting many at once.

import Contacts
import SwiftData
import SwiftUI

struct PeopleView: View {
    enum Filter: Hashable {
        case all, attention, archived
        case group(UUID)
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \Friend.displayName) private var friends: [Friend]
    @Query(sort: \FriendGroup.order) private var groups: [FriendGroup]
    @State private var filter: Filter
    @State private var search = ""
    @State private var newFriend: Friend?
    @State private var draft: EntryDraft?
    @State private var pickingContacts = false
    @State private var picked: [CNContact] = []
    @State private var bulk: BulkAddView.Source?
    @State private var showGroups = false
    @State private var deleting: Friend?
    @State private var selecting = false
    @State private var selected = Set<UUID>()
    @State private var confirmBulkDelete = false
    @AppStorage(SwipeAction.leadingKey) private var swipeLeading = SwipeAction.defaultLeading
    @AppStorage(SwipeAction.trailingKey) private var swipeTrailing = SwipeAction.defaultTrailing
    private let now = Date()

    init(initialFilter: Filter = .all) {
        _filter = State(initialValue: initialFilter)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                VStack(spacing: 0) {
                    chips
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    List(selection: $selected) {
                        if shown.isEmpty {
                            empty.plainRow()
                        }
                        ForEach(shown) { friend in
                            row(friend)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .contentMargins(.bottom, 90, for: .scrollContent)
                    .environment(\.editMode, .constant(selecting ? .active : .inactive))
                }
            }
            .navigationTitle("People")
            .searchable(text: $search, prompt: "Names, tags, places…")
            .navigationDestination(for: Friend.self) { FriendDetailView(friend: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selecting ? "Done" : "Select") {
                        selecting.toggle()
                        if !selecting { selected = [] }
                    }
                    .disabled(friends.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if selecting { bulkBar }
            }
            .overlay(alignment: .bottomTrailing) {
                if !selecting { addMenu }
            }
            .sheet(item: $newFriend) { FriendEditorView(friend: $0, isNew: true) }
            .sheet(item: $draft) { EntryEditorView(draft: $0) }
            // The picker's own dismissal has to finish before the review
            // sheet can be presented, so the hand-off rides onDismiss.
            .sheet(isPresented: $pickingContacts, onDismiss: {
                if !picked.isEmpty { bulk = .contacts(picked) }
            }) {
                ContactsMultiPicker { contacts in
                    picked = contacts
                    pickingContacts = false
                }
                .ignoresSafeArea()
            }
            .sheet(item: $bulk) { source in
                BulkAddView(source: source).onDisappear { picked = [] }
            }
            .sheet(isPresented: $showGroups) { GroupsView() }
            .confirmationDialog(
                "Delete \(deleting?.displayName ?? "")? Their facts and reminders go too; entries stay in the log.",
                isPresented: .init(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let friend = deleting { delete([friend]) }
                    deleting = nil
                }
            }
            .confirmationDialog(
                "Delete \(selected.count) people? Their facts and reminders go too; entries stay in the log.",
                isPresented: $confirmBulkDelete, titleVisibility: .visible
            ) {
                Button("Delete \(selected.count)", role: .destructive) {
                    delete(chosen)
                    selected = []
                    selecting = false
                }
            }
        }
    }

    // MARK: rows

    private func row(_ friend: Friend) -> some View {
        FriendRow(friend: friend, now: now)
            // Selecting is what a tap does in select mode; the link is
            // only there when it is not.
            .background(selecting ? nil : NavigationLink(value: friend) { EmptyView() }.opacity(0))
            .id(friend.id)
            .tag(friend.id)
            .plainRow()
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if let action = SwipeAction.one(swipeLeading) { swipeButton(action, friend) }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if let action = SwipeAction.one(swipeTrailing) { swipeButton(action, friend) }
            }
            .contextMenu {
                Button { draft = EntryDraft(friends: [friend]) } label: { Label("Add note", systemImage: "square.and.pencil") }
                Menu {
                    ForEach(groups) { g in
                        Button { move([friend], to: g) } label: {
                            Label(g.name, systemImage: friend.group?.id == g.id ? "checkmark" : "folder")
                        }
                    }
                } label: { Label("Move to group", systemImage: "folder") }
                Button { snooze(friend, weeks: 2) } label: { Label("Snooze 2 weeks", systemImage: "zzz") }
                Button { archive([friend], !friend.archived) } label: {
                    Label(friend.archived ? "Unarchive" : "Archive", systemImage: "archivebox")
                }
                Button(role: .destructive) { deleting = friend } label: { Label("Delete", systemImage: "trash") }
            } preview: {
                FriendPreview(friend: friend)
            }
    }

    /// One assigned action as its swipe button, named for this row.
    private func swipeButton(_ action: SwipeAction, _ friend: Friend) -> some View {
        Button(role: action.isDestructive ? .destructive : nil) {
            switch action {
            case .log: draft = EntryDraft(friends: [friend], kind: .call)
            case .snooze: snooze(friend, weeks: 2)
            case .archive: archive([friend], !friend.archived)
            case .delete: deleting = friend
            }
        } label: {
            Label(action == .archive && friend.archived ? "Unarchive" : action.label, systemImage: action.icon)
        }
        .tint(action.tint)
    }

    // MARK: chips and filters

    private var chips: some View {
        ChipStrip {
            chip(.all, "All")
            chip(.attention, "Reach out")
            ForEach(groups) { g in chip(.group(g.id), g.name) }
            if count(.archived) > 0 { chip(.archived, "Archived") }
        }
    }

    private func chip(_ f: Filter, _ label: String) -> some View {
        let n = count(f)
        return GlassChip(active: filter == f, action: { filter = f }) {
            HStack(spacing: 5) {
                Text(label).font(.subheadline.weight(.semibold))
                if n > 0 {
                    Text("\(n)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func count(_ f: Filter) -> Int {
        friends.filter { matches($0, f) }.count
    }

    private func matches(_ friend: Friend, _ f: Filter) -> Bool {
        switch f {
        case .all: !friend.archived
        case .attention: !friend.archived && friend.status(now: now).needsAttention
        case .archived: friend.archived
        case .group(let id): !friend.archived && friend.group?.id == id
        }
    }

    private var shown: [Friend] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let list = friends.filter { friend in
            matches(friend, filter) && (query.isEmpty || friend.searchText.contains(query))
        }
        return filter == .attention
            ? list.sorted { $0.status(now: now).urgency > $1.status(now: now).urgency }
            : list
    }

    private var empty: some View {
        switch filter {
        case .attention:
            EmptyPanel(icon: "checkmark.seal", title: "Nobody to chase", hint: "Everyone is within their cadence.")
        case .all:
            EmptyPanel(icon: "person.badge.plus", title: "Add your first friend",
                       hint: "Tap + and pick people from Contacts. Their photos, numbers and birthdays come along.")
        default:
            EmptyPanel(icon: "person.2", title: "Nobody here", hint: "Select people and move them here, or change a friend's group from their page.")
        }
    }

    // MARK: add menu and bulk bar

    private var addMenu: some View {
        Menu {
            Button {
                let friend = Friend()
                context.insert(friend)
                newFriend = friend
            } label: { Label("New friend", systemImage: "person.badge.plus") }
            Button { pickingContacts = true } label: { Label("From Contacts", systemImage: "person.crop.circle.badge.plus") }
            Button { bulk = .names } label: { Label("Paste names", systemImage: "text.badge.plus") }
            Divider()
            Button { showGroups = true } label: { Label("Groups…", systemImage: "folder") }
        } label: {
            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
        }
        .glassButton(prominent: true, shape: .circle)
        .padding(.trailing, 18)
        .padding(.bottom, 18)
    }

    /// The people ticked, in the order shown.
    private var chosen: [Friend] {
        friends.filter { selected.contains($0.id) }
    }

    private var bulkBar: some View {
        let n = selected.count
        return GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(groups) { g in
                        Button { move(chosen, to: g); selected = []; selecting = false } label: { Label(g.name, systemImage: "folder") }
                    }
                } label: {
                    Label(n == 0 ? "Move" : "Move \(n)", systemImage: "folder")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 3)
                }
                .glassButton(prominent: true)
                .disabled(n == 0)
                Button {
                    let all = chosen
                    archive(all, !(all.allSatisfy(\.archived)))
                    selected = []
                    selecting = false
                } label: {
                    // A Label under the glass style keeps the tint; a stack takes the colour it is given.
                    HStack(spacing: 6) {
                        Image(systemName: "archivebox")
                        Text(filter == .archived ? "Unarchive" : "Archive")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                }
                .glassButton()
                .disabled(n == 0)
                Button(role: .destructive) { confirmBulkDelete = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                        Text("Delete")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.red)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                }
                .glassButton()
                .disabled(n == 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: actions

    private func move(_ people: [Friend], to group: FriendGroup) {
        for friend in people {
            friend.group = group
            friend.updatedAt = now
        }
        save()
    }

    private func archive(_ people: [Friend], _ archived: Bool) {
        for friend in people {
            friend.archived = archived
            friend.updatedAt = now
        }
        save()
    }

    private func delete(_ people: [Friend]) {
        for friend in people { context.delete(friend) }
        save()
    }

    private func snooze(_ friend: Friend, weeks: Int) {
        friend.snoozedUntil = Calendar.current.date(byAdding: .weekOfYear, value: weeks, to: now)
        save()
    }

    private func save() {
        try? context.save()
        Task { await Notifier.reschedule(context: context) }
    }
}

extension Friend {
    var searchText: String {
        ([displayName, nickname, location, howWeMet, groupName] + tags).joined(separator: " ").lowercased()
    }
}
