// Capturing a conversation: what kind, when, with whom, and the words —
// typed, or recorded and transcribed. Saving runs the extractor and
// offers what it found; nothing is created without a tap.

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
    @State private var savedEntry: Entry?
    @State private var confirmDelete = false
    @FocusState private var textFocused: Bool

    var body: some View {
        NavigationStack {
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
                SuggestionsSheet(suggestions: batch.items, friends: friends, entry: savedEntry) { dismiss() }
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
                        Text(SuggestionEngine.usesLanguageModel ? "Reading your note…" : "Saving…")
                            .font(.footnote.weight(.semibold))
                    }
                    .padding(22)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
                }
            }
        }
        .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
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
            if let file = audioFile {
                HStack(spacing: 12) {
                    Button { player.toggle(file) } label: {
                        Image(systemName: player.isPlaying && player.playingFile == file ? "stop.circle.fill" : "play.circle.fill")
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
            audioFile = entry.audioFile
            duration = entry.durationSeconds
        } else {
            kind = draft.kind
            friends = draft.friends
            if let file = draft.audioFile {
                audioFile = file
                duration = draft.duration
                Task { await transcribe(file) }
            } else {
                textFocused = true
            }
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
            let heard = try await Transcriber.transcribe(AudioStore.url(for: file))
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
        entry.durationSeconds = duration
        entry.friends = friends
        for friend in friends { friend.updatedAt = Date() }
        try? context.save()
        await Notifier.reschedule(context: context)
        savedEntry = entry

        // Only a first save proposes; re-opening an entry to fix a typo
        // shouldn't re-ask about the same interview.
        guard draft.entry == nil, !friends.isEmpty else {
            dismiss()
            return
        }
        let found = await SuggestionEngine.suggestions(for: entry.body)
        if found.isEmpty {
            dismiss()
        } else {
            suggestions = SuggestionBatch(items: found)
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
    let items: [Suggestion]
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
