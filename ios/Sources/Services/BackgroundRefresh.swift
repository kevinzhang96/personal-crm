// Keeps the digest window rolling when the app isn't opened for a week:
// the seven scheduled mornings run out, and this extends them.

import BackgroundTasks
import Foundation
import SwiftData

enum BackgroundRefresh {
    static let identifier = "com.kevinzhang.tend.refresh"

    static func register(container: ModelContainer) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            schedule()
            Task { @MainActor in
                await Notifier.reschedule(context: container.mainContext)
                task.setTaskCompleted(success: true)
            }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 24 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
