// What every launch puts right before the screens read the store: the
// groups invariant, the pre-sync store carried into the synced one, and
// recordings that were files becoming data the store carries.

import Foundation
import SwiftData

enum Maintenance {
    @MainActor
    static func run(container: ModelContainer) {
        let context = container.mainContext
        Store.migrateLegacy(into: container)
        Groups.ensureSeeded(context: context)
        adoptAudioFiles(context: context)
        #if DEBUG
        SchemaProbe.runIfAsked(context: context)
        #endif
    }

    /// Recordings from before they lived in the store: read into it, the
    /// file left as cache.
    @MainActor
    private static func adoptAudioFiles(context: ModelContext) {
        let entries = (try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.audioFile != nil && $0.audio == nil }))) ?? []
        var changed = false
        for entry in entries {
            guard let file = entry.audioFile, let data = AudioStore.data(for: file) else { continue }
            entry.audio = data
            changed = true
        }
        if changed { try? context.save() }
    }
}
