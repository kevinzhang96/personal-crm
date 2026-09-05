// The rows, avatars and small pieces every screen shares.

import SwiftUI
import UIKit

struct Avatar: View {
    let friend: Friend
    var size: CGFloat = 44

    var body: some View {
        PhotoCircle(photo: friend.photo, initials: friend.initials, size: size)
    }
}

/// A photo when there is one, initials on the accent otherwise — for a
/// friend, or for someone about to become one.
struct PhotoCircle: View {
    let photo: Data?
    let initials: String
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let photo, let image = UIImage(data: photo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(
                        Text(initials.isEmpty ? "?" : initials)
                            .font(.system(size: size * 0.38, weight: .bold))
                            .foregroundStyle(.white)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct StatusBadge: View {
    let status: ContactStatus

    var body: some View {
        if !status.short.isEmpty {
            Badge(status.short, tint: Theme.tint(for: status))
        }
    }
}

/// A friend in a list: who, how close, how long since, and whether that
/// is a problem.
struct FriendRow: View {
    let friend: Friend
    var now = Date()

    var body: some View {
        HStack(spacing: 12) {
            Avatar(friend: friend)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(friend.displayName.isEmpty ? "Unnamed" : friend.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if friend.starred {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                    }
                }
                Text(meta)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            StatusBadge(status: friend.status(now: now))
        }
        .panel()
    }

    private var meta: String {
        var parts = [friend.groupNames]
        if let last = friend.lastContact {
            parts.append(Dates.since(last, now: now))
        } else {
            parts.append("never")
        }
        if !friend.tags.isEmpty { parts.append(friend.tags.prefix(2).joined(separator: " · ")) }
        return parts.joined(separator: " · ")
    }
}

/// A timeline entry: when, how, with whom, and the first lines.
struct EntryRow: View {
    let entry: Entry
    /// Hidden on a friend's own page, where every row is about them.
    var showFriends = true
    var now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: entry.kind.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Text(entry.kind.label)
                    .font(.caption.weight(.semibold))
                Text("·").foregroundStyle(.tertiary)
                Text(entry.date, format: .dateTime.month(.abbreviated).day().year(.twoDigits))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if entry.hasAudio {
                    Image(systemName: "waveform")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(Dates.ago(entry.date, now: now))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            if showFriends, !entry.friendNames.isEmpty {
                Text(entry.friendNames)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            if !entry.body.isEmpty {
                Text(entry.body)
                    .font(.subheadline)
                    .foregroundStyle(showFriends ? .secondary : .primary)
                    .lineLimit(3)
            } else if entry.hasAudio {
                Text("Recording, not yet transcribed")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }
        .panel()
    }
}

struct ReminderRow: View {
    let reminder: Reminder
    var showFriend = true
    var now = Date()
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: reminder.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(reminder.done ? Theme.rise : .secondary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                Text(reminder.title)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(reminder.done)
                HStack(spacing: 4) {
                    if showFriend, let name = reminder.friend?.displayName {
                        Text(name)
                        Text("·").foregroundStyle(.tertiary)
                    }
                    Text(Dates.until(reminder.due, now: now))
                        .foregroundStyle(overdue ? Theme.warn : .secondary)
                }
                .font(.caption)
                .monospacedDigit()
                if !reminder.note.isEmpty {
                    Text(reminder.note)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .panel()
    }

    private var overdue: Bool { !reminder.done && reminder.due < now }
}

/// The long-press preview of a friend: what you'd want to know before
/// deciding to call — status, the last things said, the facts.
struct FriendPreview: View {
    let friend: Friend
    private let now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Avatar(friend: friend, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(friend.displayName).font(.headline)
                    HStack(spacing: 6) {
                        Text(friend.groupNames).font(.caption).foregroundStyle(.secondary)
                        StatusBadge(status: friend.status(now: now))
                    }
                }
            }
            if !friend.summary.isEmpty {
                Text(friend.summary).font(.caption).lineLimit(5)
            }
            let facts = friend.sortedFacts.prefix(3)
            if !facts.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(facts) { fact in
                        (Text(fact.label + " ").foregroundStyle(.secondary) + Text(fact.value))
                            .font(.caption)
                    }
                }
            }
            let recent = friend.sortedEntries.prefix(2)
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(recent) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(entry.kind.label) · \(Dates.ago(entry.date, now: now))")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if !entry.body.isEmpty {
                                Text(entry.body).font(.caption).lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
        .background(Theme.bgBottom)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// The floating capture pair every timeline screen carries: a voice
/// note and a written one.
struct CaptureButtons: View {
    let onRecord: () -> Void
    let onNote: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
                GlassCircle(icon: "mic.fill", action: onRecord)
                GlassCircle(icon: "square.and.pencil", tint: Theme.accent, action: onNote)
            }
        }
        .padding(.trailing, 18)
        .padding(.bottom, 18)
    }
}
