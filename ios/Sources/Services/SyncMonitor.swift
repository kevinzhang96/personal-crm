// What CloudKit last did, so Settings can say "synced 3m ago" or show
// the error — a store that looks synced while every export fails is the
// one failure worth surfacing. SwiftData rides NSPersistentCloudKitContainer,
// whose event notifications still fire.

import CoreData
import Foundation
import Observation

@MainActor
@Observable
final class SyncMonitor {
    static let shared = SyncMonitor()

    private(set) var lastSuccess: Date?
    private(set) var lastError: String?
    private var token: NSObjectProtocol?

    func start() {
        guard token == nil else { return }
        token = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                  let ended = event.endDate
            else { return }
            let error = event.error?.localizedDescription
            Task { @MainActor in
                if let error {
                    self.lastError = error
                } else {
                    self.lastSuccess = ended
                    self.lastError = nil
                }
            }
        }
    }
}
