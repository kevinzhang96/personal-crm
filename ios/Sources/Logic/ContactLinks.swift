// The deep link each contact method opens. Universal https links are
// preferred over custom schemes: they open the app when it is installed
// and its website when it is not, and need no scheme allow-list.

import Foundation

enum ContactLinks {
    static func url(kind: ContactKind, value: String) -> URL? {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        switch kind {
        case .phone: return URL(string: "tel:\(phone(raw))")
        case .sms: return URL(string: "sms:\(phone(raw))")
        case .facetime: return URL(string: "facetime://\(isEmail(raw) ? raw : phone(raw))")
        case .facetimeAudio: return URL(string: "facetime-audio://\(isEmail(raw) ? raw : phone(raw))")
        case .whatsapp: return URL(string: "https://wa.me/\(digits(raw))")
        case .messenger: return URL(string: "https://m.me/\(escaped(handle(raw)))")
        case .instagram: return URL(string: "https://instagram.com/\(escaped(handle(raw)))")
        case .telegram:
            let h = handle(raw)
            return URL(string: "https://t.me/\(looksLikePhone(h) ? phone(h) : escaped(h))")
        case .signal: return URL(string: "https://signal.me/#p/\(phone(raw))")
        case .email: return URL(string: "mailto:\(raw)")
        case .discord:
            // Only numeric user ids deep-link; a username is copy-only.
            return raw.allSatisfy(\.isNumber) ? URL(string: "https://discord.com/users/\(raw)") : nil
        case .linkedin: return URL(string: "https://linkedin.com/in/\(escaped(handle(raw)))")
        case .snapchat: return URL(string: "https://snapchat.com/add/\(escaped(handle(raw)))")
        case .wechat: return nil
        case .x: return URL(string: "https://x.com/\(escaped(handle(raw)))")
        case .url:
            let withScheme = raw.contains("://") ? raw : "https://\(raw)"
            return URL(string: withScheme)
        }
    }

    /// The conversation a tap on this method starts, for the "did you reach
    /// them?" prompt on return.
    static func entryKind(for kind: ContactKind) -> EntryKind {
        switch kind {
        case .phone, .facetimeAudio: .call
        case .facetime: .video
        case .sms, .whatsapp, .messenger, .telegram, .signal, .discord, .wechat: .message
        case .email: .email
        case .instagram, .linkedin, .snapchat, .x, .url: .social
        }
    }

    /// A handle however it was pasted: "@sam", "sam", or a profile URL.
    static func handle(_ value: String) -> String {
        var v = value
        if v.contains("/"), let url = URL(string: v.contains("://") ? v : "https://\(v)") {
            v = url.lastPathComponent
        }
        if v.hasPrefix("@") { v.removeFirst() }
        return v
    }

    /// Digits with a leading plus kept — what tel: and friends accept.
    static func phone(_ value: String) -> String {
        let d = digits(value)
        return value.trimmingCharacters(in: .whitespaces).hasPrefix("+") ? "+\(d)" : d
    }

    static func digits(_ value: String) -> String {
        value.filter(\.isNumber)
    }

    private static func looksLikePhone(_ value: String) -> Bool {
        let d = digits(value)
        return d.count >= 7 && value.filter(\.isLetter).isEmpty
    }

    private static func isEmail(_ value: String) -> Bool {
        value.contains("@") && value.contains(".")
    }

    private static func escaped(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}
