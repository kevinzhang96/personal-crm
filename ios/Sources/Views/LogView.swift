// Everything said, newest first, across everyone — and the search box
// that answers "who was it that mentioned the kettle?"

import SwiftData
import SwiftUI

struct LogView: View {
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
    @State private var search = ""
    @State private var draft: EntryDraft?
    @State private var recording = false
    private let now = Date()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                List {
                    if shown.isEmpty {
                        EmptyPanel(icon: "text.bubble", title: search.isEmpty ? "Nothing logged yet" : "No matches",
                                   hint: search.isEmpty ? "After a call or a coffee, tap the pencil or the mic." : "Try a name or a word from the note.")
                            .plainRow()
                    }
                    ForEach(shown) { entry in
                        Button { draft = EntryDraft(entry: entry) } label: { EntryRow(entry: entry, now: now) }
                            .buttonStyle(.plain)
                            .plainRow()
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, 90, for: .scrollContent)
            }
            .navigationTitle("Log")
            .searchable(text: $search, prompt: "Words, names…")
            .overlay(alignment: .bottomTrailing) {
                CaptureButtons(onRecord: { recording = true }, onNote: { draft = EntryDraft() })
            }
            .sheet(item: $draft) { EntryEditorView(draft: $0) }
            .sheet(isPresented: $recording) {
                RecordSheet { file, duration in draft = EntryDraft(audioFile: file, duration: duration) }
            }
        }
    }

    private var shown: [Entry] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return entries }
        return entries.filter {
            $0.text.lowercased().contains(q) || $0.transcript.lowercased().contains(q) || $0.friendNames.lowercased().contains(q)
        }
    }
}
