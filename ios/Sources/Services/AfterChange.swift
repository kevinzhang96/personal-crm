// What follows any change to the store, and every foreground: the
// notifications are rescheduled from it, and the calendar, when sync is
// on, is made to match it. One seam, so a screen that saves has one
// thing to call.

import Foundation
import SwiftData

enum AfterChange {
    @MainActor
    static func run(context: ModelContext) async {
        await Notifier.reschedule(context: context)
        await CalendarSync.shared.reconcile(context: context)
    }
}
