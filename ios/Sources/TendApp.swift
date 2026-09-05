import SwiftData
import SwiftUI
import UserNotifications

@main
struct TendApp: App {
    private let container: ModelContainer
    private let notificationDelegate = Notifier.Delegate()
    @AppStorage("appearance") private var appearance = Appearance.dark.rawValue

    init() {
        do {
            container = try Store.container()
        } catch {
            // A store that cannot open is not a state the app can be
            // useful in; better to say so than to run on nothing.
            fatalError("Could not open the store: \(error)")
        }
        UNUserNotificationCenter.current().delegate = notificationDelegate
        // The refresh identifier has to be claimed before launch finishes,
        // so it is claimed here rather than in a view.
        BackgroundRefresh.register(container: container)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(container)
                .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme ?? .dark)
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var attempt: PendingContact.Attempt?
    @State private var draft: EntryDraft?

    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.horizon.fill") { TodayView() }
            Tab("People", systemImage: "person.2.fill") { PeopleView() }
            Tab("Log", systemImage: "text.bubble.fill") { LogView() }
            Tab("Settings", systemImage: "gearshape.fill") { SettingsView() }
        }
        .task { Groups.ensureSeeded(context: context) }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                attempt = PendingContact.take()
                Task { await Notifier.reschedule(context: context) }
            case .background:
                BackgroundRefresh.schedule()
            default:
                break
            }
        }
        .alert("Did you reach \(attemptName)?", isPresented: .init(get: { attempt != nil }, set: { if !$0 { attempt = nil } })) {
            Button("Log it") {
                if let attempt, let friend = friend(attempt.friendId) {
                    draft = EntryDraft(friends: [friend], kind: attempt.kind)
                }
                attempt = nil
            }
            Button("Not now", role: .cancel) { attempt = nil }
        }
        .sheet(item: $draft) { EntryEditorView(draft: $0) }
    }

    private var attemptName: String {
        attempt.flatMap { friend($0.friendId)?.displayName } ?? "them"
    }

    private func friend(_ id: UUID) -> Friend? {
        try? context.fetch(FetchDescriptor<Friend>(predicate: #Predicate { $0.id == id })).first
    }
}
