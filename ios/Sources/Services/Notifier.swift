// Every notification the app sends, scheduled from the store. Called
// after any change and on every foreground; the digest for each of the
// next seven mornings is computed now, because status is a pure function
// of dates the app already knows.

import Foundation
import SwiftData
import UserNotifications

enum Notifier {
    static let digestHourKey = "digestHour"
    static let digestMinuteKey = "digestMinute"
    static let defaultHour = 9
    /// iOS keeps at most 64 pending local notifications per app.
    static let pendingLimit = 64

    static var digestTime: (hour: Int, minute: Int) {
        let defaults = UserDefaults.standard
        let hour = defaults.object(forKey: digestHourKey) as? Int ?? defaultHour
        let minute = defaults.object(forKey: digestMinuteKey) as? Int ?? 0
        return (hour, minute)
    }

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @MainActor
    static func reschedule(context: ModelContext, now: Date = Date(), calendar: Calendar = .current) async {
        let friends = (try? context.fetch(FetchDescriptor<Friend>(predicate: #Predicate { !$0.archived }))) ?? []
        let reminders = (try? context.fetch(FetchDescriptor<Reminder>(predicate: #Predicate { !$0.done }))) ?? []
        var requests: [UNNotificationRequest] = []

        // 1. The digests, one per morning for a week.
        let candidates = friends.map {
            DigestCandidate(name: $0.displayName, lastContact: $0.lastContact, cadenceDays: $0.effectiveCadenceDays,
                            snoozedUntil: $0.snoozedUntil, createdAt: $0.createdAt)
        }
        let time = digestTime
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let fire = Dates.at(hour: time.hour, minute: time.minute, on: day, calendar: calendar)
            guard fire > now, let content = Digest.content(for: Digest.overdue(candidates, on: fire, calendar: calendar)) else { continue }
            requests.append(request(
                id: "digest-" + fire.formatted(.iso8601.year().month().day()),
                title: content.title, body: content.body, at: fire, calendar: calendar))
        }

        // 2. Follow-ups, soonest first.
        for reminder in reminders.sorted(by: { $0.due < $1.due }) where reminder.due > now {
            let who = reminder.friend?.displayName ?? ""
            let body = [who, reminder.note].filter { !$0.isEmpty }.joined(separator: " · ")
            requests.append(request(id: reminder.notificationId, title: reminder.title,
                                    body: body.isEmpty ? "Follow up" : body, at: reminder.due, calendar: calendar))
        }

        // 3. Birthdays and other yearly dates, at digest time on the day.
        var dated: [(Date, UNNotificationRequest)] = []
        for friend in friends {
            for date in friend.dates ?? [] where date.remind {
                guard let day = date.next(after: now, calendar: calendar) else { continue }
                let fire = Dates.at(hour: time.hour, minute: time.minute, on: day, calendar: calendar)
                guard fire > now else { continue }
                let age = date.ageTurning(on: day, calendar: calendar).map { " · turns \($0)" } ?? ""
                let title = date.label.caseInsensitiveCompare(ImportantDate.birthdayLabel) == .orderedSame
                    ? "\(friend.displayName)'s birthday" : "\(friend.displayName) · \(date.label)"
                dated.append((fire, request(id: "date-\(date.id.uuidString)", title: title, body: "Today\(age)", at: fire, calendar: calendar)))
            }
        }
        requests += dated.sorted { $0.0 < $1.0 }.map(\.1)

        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        for request in requests.prefix(pendingLimit) {
            try? await center.add(request)
        }
    }

    private static func request(id: String, title: String, body: String, at date: Date, calendar: Calendar) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    /// Shows notifications while the app is in front too; a nudge that
    /// only fires when the app is closed is a nudge the reader never sees
    /// on the day they happen to have it open.
    final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(
            _ center: UNUserNotificationCenter, willPresent notification: UNNotification
        ) async -> UNNotificationPresentationOptions {
            [.banner, .list, .sound]
        }
    }
}
