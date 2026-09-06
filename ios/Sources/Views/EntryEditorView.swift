// Capturing a conversation: who it was with first — the keyboard is up
// before the sheet has settled, a name or two and Return is enough —
// then what kind, when, and the words, typed or recorded and
// transcribed. Saving runs the extractor and offers what it found;
// nothing is created without a tap.

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// What an editor opens with. An existing entry, or the parts of a new
/// one that the caller already knows.
struct EntryDraft: Identifiable {
    let id = UUID()
    var entry: Entry?
    var friends: [Friend] = []
    var kind: EntryKind = .note
    var audioFile: String?
    var duration: Double?
}

struct EntryEditorView: View {
    let draft: EntryDraft
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = Appearance.dark.rawValue

    /// A new entry with nobody named yet asks who first.
    @State private var choosing: Bool
    @State private var kind: EntryKind = .note
    @State private var date = Date()
    @State private var friends: [Friend] = []
    @State private var text = ""
    @State private var transcript = ""
    @State private var audioFile: String?
    @State private var duration: Double?
    @State private var pickingFriends = false
    @State private var recording = false
    @State private var importing = false
    @State private var transcribing = false
    @State private var transcribeNote: String?
    @State private var player = Player()
    @State private var saving = false
    @State private var suggestions: SuggestionBatch?
    @State private var stage: JudgeLoop.Stage?
    @State private var savedEntry: Entry?
    @State private var removedAudio = false
    @State private var confirmDelete = false
    @FocusState private var textFocused: Bool

    init(draft: EntryDraft) {
        self.draft = draft
        _choosing = State(initialValue: draft.entry == nil && draft.friends.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Group {
                if choosing {
                    WhoStage(onPick: { begin(with: [$0]) }, onSkip: { begin(with: []) }, onCancel: cancel)
                } else {
                    editor
                }
            }
            .onAppear(perform: load)
            .sheet(isPresented: $pickingFriends) { FriendMultiPicker(selected: $friends) }
            .sheet(isPresented: $recording) {
                RecordSheet { file, length in attach(file, duration: length) }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .mpeg4Audio, .mp3, .wav]) { result in
                guard case .success(let url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let file = try? AudioStore.adopt(url) { attach(file, duration: nil) }
            }
            .sheet(item: $suggestions) { batch in
                SuggestionsSheet(outcome: batch.outcome, friends: friends, entry: savedEntry) {
                    SummaryEngine.shared.refresh(all: friends, context: context)
                    dismiss()
                }
            }
            .confirmationDialog("Delete this entry?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let entry = draft.entry {
                        if let file = entry.audioFile { AudioStore.delete(file) }
                        context.delete(entry)
                        try? context.save()
                        Task { await Notifier.reschedule(context: context) }
                    }
                    dismiss()
                }
            }
            .interactiveDismissDisabled(!text.isEmpty || audioFile != nil)
            .overlay {
                if saving {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(stageLabel)
                            .font(.footnote.weight(.semibold))
                            .contentTransition(.numericText())
                    }
                    .padding(22)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
                }
            }
        }
        .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
    }

    private var editor: some View {
        PanelScroll {
            kinds
            who
            words
            audio
            if draft.entry != nil {
                Button("Delete entry", role: .destructive) { confirmDelete = true }
                    .font(.footnote)
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(draft.entry == nil ? "Log" : "Entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { cancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button { Task { await save() } } label: {
                    if saving { ProgressView() } else { Text("Save") }
                }
                .disabled(saving || (text.isEmpty && transcript.isEmpty && audioFile == nil))
            }
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    // MARK: sections

    private var kinds: some View {
        VStack(alignment: .leading, spacing: 10) {
            ChipStrip(wraps: true) {
                ForEach(EntryKind.allCases) { k in
                    GlassChip(active: kind == k, action: { kind = k }) {
                        Label(k.label, systemImage: k.icon).font(.subheadline.weight(.semibold))
                    }
                }
            }
            HStack {
                DatePicker("When", selection: $date, in: ...Date.now.addingTimeInterval(86_400), displayedComponents: [.date])
                    .font(.subheadline)
                if kind == .note {
                    Text("doesn't count as contact").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .panel()
    }

    private var who: some View {
        Button { pickingFriends = true } label: {
            HStack(spacing: 10) {
                if friends.isEmpty {
                    Image(systemName: "person.badge.plus").foregroundStyle(Theme.accent)
                    Text("Who was it with?").font(.subheadline.weight(.semibold))
                } else {
                    HStack(spacing: -8) {
                        ForEach(friends.prefix(4)) { Avatar(friend: $0, size: 30) }
                    }
                    Text(friends.map(\.displayName).joined(separator: ", "))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .panel()
        }
        .buttonStyle(.plain)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("What was said")
            TextEditor(text: $text)
                .focused($textFocused)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 140)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Her interview at Figma is next Thursday… kids start school Monday… wants a pour-over kettle…")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
            if !transcript.isEmpty, transcript != text {
                Divider()
                HStack {
                    SectionLabel("Transcript")
                    Spacer()
                    Button("Use as note") { text = transcript }.font(.caption.weight(.semibold))
                }
                Text(transcript).font(.footnote).foregroundStyle(.secondary).lineLimit(6)
            }
        }
        .panel()
    }

    private var audio: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Recording")
            if let file = audioFile, let playURL = AudioStore.playbackURL(file: file, data: draft.entry?.audio) {
                HStack(spacing: 12) {
                    Button { player.toggle(playURL) } label: {
                        Image(systemName: player.isPlaying && player.playingURL == playURL ? "stop.circle.fill" : "play.circle.fill")
                            .font(.title)
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(duration.map { Self.clock($0) } ?? "Audio file").font(.subheadline.weight(.semibold)).monospacedDigit()
                        if transcribing {
                            Text("Transcribing…").font(.caption).foregroundStyle(.secondary)
                        } else if let transcribeNote {
                            Text(transcribeNote).font(.caption).foregroundStyle(Theme.warn)
                        } else if transcript.isEmpty {
                            Button("Transcribe") { Task { await transcribe(file) } }.font(.caption.weight(.semibold))
                        } else {
                            Text("Transcribed").font(.caption).foregroundStyle(Theme.rise)
                        }
                    }
                    Spacer()
                    Button(role: .destructive) {
                        player.stop()
                        if draft.entry?.audioFile != file { AudioStore.delete(file) }
                        audioFile = nil
                        duration = nil
                        transcript = ""
                        removedAudio = true
                    } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 12) {
                    Button { recording = true } label: { Label("Record", systemImage: "mic.fill") }
                    Button { importing = true } label: { Label("Import audio", systemImage: "square.and.arrow.down") }
                }
                .font(.subheadline.weight(.semibold))
                Text("Phone calls can't be recorded by apps. Apple's own call recording saves to Notes — export that file and import it here.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .panel()
    }

    // MARK: state

    private func load() {
        if let entry = draft.entry {
            kind = entry.kind
            date = entry.date
            friends = entry.friends ?? []
            text = entry.text
            transcript = entry.transcript
            audioFile = entry.audioFile ?? (entry.audio != nil ? "\(entry.id.uuidString).m4a" : nil)
            duration = entry.durationSeconds
        } else {
            kind = draft.kind
            friends = draft.friends
            if let file = draft.audioFile {
                audioFile = file
                duration = draft.duration
                Task { await transcribe(file) }
            } else if !choosing {
                textFocused = true
            }
        }
    }

    /// The person is settled; the words are next, so the cursor goes
    /// straight to them once the editor is on screen.
    private func begin(with chosen: [Friend]) {
        friends = chosen
        withAnimation(.snappy) { choosing = false }
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            textFocused = true
        }
    }

    private func attach(_ file: String, duration: Double?) {
        audioFile = file
        self.duration = duration
        transcript = ""
        transcribeNote = nil
        Task { await transcribe(file) }
    }

    private func transcribe(_ file: String) async {
        transcribing = true
        defer { transcribing = false }
        do {
            guard let url = AudioStore.playbackURL(file: file, data: draft.entry?.audio) else { throw Transcriber.Failure.empty }
            let heard = try await Transcriber.transcribe(url)
            transcript = heard
            if text.isEmpty { text = heard }
            transcribeNote = nil
        } catch {
            transcribeNote = error.localizedDescription
        }
    }

    private func cancel() {
        player.stop()
        // A recording made for an entry that was never saved is orphaned.
        if draft.entry == nil, let file = audioFile { AudioStore.delete(file) }
        dismiss()
    }

    private func save() async {
        saving = true
        player.stop()
        let entry = draft.entry ?? Entry()
        if draft.entry == nil { context.insert(entry) }
        entry.kind = kind
        entry.date = date
        entry.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.transcript = transcript
        if let old = draft.entry?.audioFile, old != audioFile { AudioStore.delete(old) }
        entry.audioFile = audioFile
        // The bytes go into the store, which is what syncs and survives;
        // the file stays as the playback cache.
        if removedAudio, audioFile == nil { entry.audio = nil }
        if let file = audioFile, entry.audio == nil || draft.entry?.audioFile != file {
            entry.audio = AudioStore.data(for: file) ?? entry.audio
        }
        entry.durationSeconds = duration
        entry.friends = friends
        for friend in friends { friend.updatedAt = Date() }
        try? context.save()
        await Notifier.reschedule(context: context)
        savedEntry = entry

        // Only a first save proposes; re-opening an entry to fix a typo
        // shouldn't re-ask about the same interview. The summary rebuilds
        // once the flow is over — after the suggestions, when there are any,
        // so what was accepted is in it.
        guard draft.entry == nil, !friends.isEmpty else {
            SummaryEngine.shared.refresh(all: friends, context: context)
            dismiss()
            return
        }
        let outcome = await SuggestionEngine.suggestions(for: entry.body) { step in
            Task { @MainActor in stage = step }
        }
        if outcome.suggestions.isEmpty {
            SummaryEngine.shared.refresh(all: friends, context: context)
            dismiss()
        } else {
            suggestions = SuggestionBatch(outcome: outcome)
        }
    }

    /// What the wait is for: reading, a second opinion, a second draft.
    private var stageLabel: String {
        guard SuggestionEngine.usesLanguageModel else { return "Saving…" }
        switch stage {
        case .judging(let round): return round == 1 ? "Getting a second opinion…" : "Checking again…"
        case .revising: return "Revising…"
        default: return "Reading your note…"
        }
    }

    static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// One extractor run, as a sheet item.
struct SuggestionBatch: Identifiable {
    let id = UUID()
    let outcome: JudgeOutcome
}

/// The first screen of a new log: who was it with. The field is focused
/// as the sheet arrives, the list narrows as the reader types, and a tap
/// or Return on the first match moves on. The people logged most
/// recently sit at the top, since they are the likely answer.
struct WhoStage: View {
    let onPick: (Friend) -> Void
    let onSkip: () -> Void
    let onCancel: () -> Void
    @Query(filter: #Predicate<Friend> { !$0.archived }, sort: \Friend.displayName) private var friends: [Friend]
    @State private var search = ""
    @FocusState private var focused: Bool
    private let now = Date()

    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 8) {
                field
                List {
                    if friends.isEmpty {
                        EmptyPanel(icon: "person.badge.plus", title: "No friends yet", hint: "Add people in the People tab first, or log a note on its own.")
                            .plainRow()
                    } else if shown.isEmpty {
                        EmptyPanel(icon: "person.fill.questionmark", title: "No one called “\(search)”", hint: "Try another spelling, or log a note on its own.")
                            .plainRow()
                    }
                    if search.isEmpty, !recent.isEmpty {
                        SectionLabel("Recent").plainRow(EdgeInsets(top: 8, leading: 20, bottom: 2, trailing: 16))
                        ForEach(recent) { row($0) }
                        SectionLabel("Everyone").plainRow(EdgeInsets(top: 12, leading: 20, bottom: 2, trailing: 16))
                    }
                    ForEach(shown) { row($0) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.immediately)
            }
        }
        .navigationTitle("Who was it with?")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
            ToolbarItem(placement: .confirmationAction) { Button("Just a note", action: onSkip) }
        }
        .task {
            // The sheet is still sliding in when this runs; the keyboard
            // follows it up rather than fighting it.
            try? await Task.sleep(for: .milliseconds(150))
            focused = true
        }
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Name", text: $search)
                .focused($focused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit { if let first = shown.first { onPick(first) } }
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
    }

    private func row(_ friend: Friend) -> some View {
        Button { onPick(friend) } label: {
            HStack(spacing: 12) {
                Avatar(friend: friend, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.displayName.isEmpty ? "Unnamed" : friend.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(friend.lastContact.map { "last talked " + Dates.since($0, now: now) } ?? friend.groupNames)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                StatusBadge(status: friend.status(now: now))
            }
            .panel()
        }
        .buttonStyle(.plain)
        .plainRow()
    }

    /// The few people logged with most recently, in that order.
    private var recent: [Friend] {
        friends.compactMap { f -> (Friend, Date)? in
            f.sortedEntries.first.map { (f, $0.date) }
        }
        .sorted { $0.1 > $1.1 }
        .prefix(4)
        .map(\.0)
    }

    /// Names that start with what was typed come first, then anything
    /// else about the person that contains it.
    private var shown: [Friend] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return friends }
        func rank(_ f: Friend) -> Int {
            if f.displayName.lowercased().hasPrefix(q) || f.givenName.lowercased().hasPrefix(q) || f.nickname.lowercased().hasPrefix(q) { return 0 }
            if f.displayName.lowercased().split(separator: " ").contains(where: { $0.hasPrefix(q) }) { return 1 }
            return 2
        }
        return friends.filter { $0.searchText.contains(q) }.sorted { (rank($0), $0.displayName) < (rank($1), $1.displayName) }
    }
}

/// Pick the people an entry was with.
struct FriendMultiPicker: View {
    @Binding var selected: [Friend]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Friend> { !$0.archived }, sort: \Friend.displayName) private var friends: [Friend]
    @State private var search = ""
    @AppStorage("appearance") private var appearance = Appearance.dark.rawValue

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                List {
                    if friends.isEmpty {
                        EmptyPanel(icon: "person.badge.plus", title: "No friends yet", hint: "Add people in the People tab first.")
                            .plainRow()
                    }
                    ForEach(shown) { friend in
                        let on = selected.contains { $0.id == friend.id }
                        Button {
                            if on { selected.removeAll { $0.id == friend.id } } else { selected.append(friend) }
                        } label: {
                            HStack(spacing: 12) {
                                Avatar(friend: friend, size: 36)
                                Text(friend.displayName).font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(on ? Theme.accent : .secondary)
                            }
                            .panel()
                        }
                        .buttonStyle(.plain)
                        .plainRow()
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("With")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
    }

    private var shown: [Friend] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? friends : friends.filter { $0.searchText.contains(q) }
    }
}
