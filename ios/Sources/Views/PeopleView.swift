// Everyone, searchable, with the circles as filter chips. The "attention"
// chip is the working view: who to reach out to, most overdue first.

import SwiftData
import SwiftUI

struct PeopleView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all, attention, inner, close, friends, acquaintances, archived

        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: "All"
            case .attention: "Reach out"
            case .archived: "Archived"
            default: FriendCircle(rawValue: rawValue)?.label ?? rawValue
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \Friend.displayName) private var friends: [Friend]
    @State private var filter: Filter
    @State private var search = ""
    @State private var newFriend: Friend?
    @State private var draft: EntryDraft?
    private let now = Date()

    init(initialFilter: Filter = .all) {
        _filter = State(initialValue: initialFilter)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                List {
                    chips
                        .plainRow(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                    if shown.isEmpty {
                        empty.plainRow()
                    }
                    ForEach(shown) { friend in
                        FriendRow(friend: friend, now: now)
                            .background(NavigationLink(value: friend) { EmptyView() }.opacity(0))
                        .id(friend.id)
                        .plainRow()
                        .swipeActions(edge: .leading) {
                            Button { draft = EntryDraft(friends: [friend], kind: .call) } label: {
                                Label("Log", systemImage: "square.and.pencil")
                            }
                            .tint(Theme.accent)
                        }
                        .swipeActions(edge: .trailing) {
                            Button { snooze(friend, weeks: 2) } label: {
                                Label("Snooze 2w", systemImage: "zzz")
                            }
                            .tint(.indigo)
                        }
                        .contextMenu {
                            Button { draft = EntryDraft(friends: [friend]) } label: { Label("Add note", systemImage: "square.and.pencil") }
                            Button { snooze(friend, weeks: 2) } label: { Label("Snooze 2 weeks", systemImage: "zzz") }
                            Button { friend.archived.toggle(); try? context.save() } label: {
                                Label(friend.archived ? "Unarchive" : "Archive", systemImage: "archivebox")
                            }
                        } preview: {
                            FriendPreview(friend: friend)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, 90, for: .scrollContent)
            }
            .navigationTitle("People")
            .searchable(text: $search, prompt: "Names, tags, places…")
            .navigationDestination(for: Friend.self) { FriendDetailView(friend: $0) }
            .overlay(alignment: .bottomTrailing) {
                GlassCircle(icon: "person.badge.plus", tint: Theme.accent) {
                    let friend = Friend()
                    context.insert(friend)
                    newFriend = friend
                }
                .padding(.trailing, 18)
                .padding(.bottom, 18)
            }
            .sheet(item: $newFriend) { FriendEditorView(friend: $0, isNew: true) }
            .sheet(item: $draft) { EntryEditorView(draft: $0) }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(Filter.allCases) { f in
                        let count = self.count(f)
                        if f != .archived || count > 0 {
                            GlassChip(active: filter == f, action: { filter = f }) {
                                HStack(spacing: 5) {
                                    Text(f.label).font(.subheadline.weight(.semibold))
                                    if count > 0 {
                                        Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 2)
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
        default: !friend.archived && friend.circle.rawValue == f.rawValue
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
                       hint: "Tap + and pick someone from Contacts. Their photo, numbers and birthday come along.")
        default:
            EmptyPanel(icon: "person.2", title: "Nobody here", hint: "Change a friend's circle from their page.")
        }
    }

    private func snooze(_ friend: Friend, weeks: Int) {
        friend.snoozedUntil = Calendar.current.date(byAdding: .weekOfYear, value: weeks, to: now)
        try? context.save()
        Task { await Notifier.reschedule(context: context) }
    }
}

extension Friend {
    var searchText: String {
        ([displayName, nickname, location, howWeMet] + tags).joined(separator: " ").lowercased()
    }
}
