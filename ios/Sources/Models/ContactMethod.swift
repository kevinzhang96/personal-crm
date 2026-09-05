// A way to reach someone. The kinds are the app's vocabulary; the deep
// link each one opens lives in Logic/ContactLinks.swift.

import Foundation
import SwiftData

enum ContactKind: String, Codable, CaseIterable, Identifiable {
    case phone, sms, facetime, facetimeAudio, whatsapp, messenger, instagram,
         telegram, signal, email, discord, linkedin, snapchat, wechat, x, url

    var id: String { rawValue }

    var label: String {
        switch self {
        case .phone: "Call"
        case .sms: "Text"
        case .facetime: "FaceTime"
        case .facetimeAudio: "FaceTime Audio"
        case .whatsapp: "WhatsApp"
        case .messenger: "Messenger"
        case .instagram: "Instagram"
        case .telegram: "Telegram"
        case .signal: "Signal"
        case .email: "Email"
        case .discord: "Discord"
        case .linkedin: "LinkedIn"
        case .snapchat: "Snapchat"
        case .wechat: "WeChat"
        case .x: "X"
        case .url: "Link"
        }
    }

    var icon: String {
        switch self {
        case .phone: "phone.fill"
        case .sms: "message.fill"
        case .facetime: "video.fill"
        case .facetimeAudio: "phone.badge.waveform.fill"
        case .whatsapp: "bubble.left.and.bubble.right.fill"
        case .messenger: "bolt.horizontal.circle.fill"
        case .instagram: "camera.fill"
        case .telegram: "paperplane.fill"
        case .signal: "lock.shield.fill"
        case .email: "envelope.fill"
        case .discord: "gamecontroller.fill"
        case .linkedin: "briefcase.fill"
        case .snapchat: "bolt.fill"
        case .wechat: "text.bubble.fill"
        case .x: "number"
        case .url: "link"
        }
    }

    /// What the value is: a number, an address, a handle, or an address the
    /// reader typed in full.
    var placeholder: String {
        switch self {
        case .phone, .sms, .facetime, .facetimeAudio, .whatsapp, .signal: "+1 555 010 2030"
        case .email: "name@example.com"
        case .url: "https://…"
        case .messenger, .instagram, .telegram, .discord, .linkedin, .snapchat, .wechat, .x: "handle"
        }
    }

    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

@Model
final class ContactMethod {
    var id: UUID = UUID()
    var kindRaw: String = ContactKind.phone.rawValue
    var value: String = ""
    var label: String = ""
    var preferred: Bool = false
    var friend: Friend?

    init(kind: ContactKind, value: String, label: String = "", preferred: Bool = false) {
        self.kindRaw = kind.rawValue
        self.value = value
        self.label = label
        self.preferred = preferred
    }
}

extension ContactMethod {
    var kind: ContactKind {
        get { ContactKind(rawValue: kindRaw) ?? .url }
        set { kindRaw = newValue.rawValue }
    }

    var url: URL? { ContactLinks.url(kind: kind, value: value) }
}
