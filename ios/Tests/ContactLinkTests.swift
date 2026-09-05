// Every kind of handle, pasted however people paste them, to the link
// that opens the right app.

import Foundation
import Testing
@testable import Tend

struct ContactLinkTests {
    func url(_ kind: ContactKind, _ value: String) -> String? {
        ContactLinks.url(kind: kind, value: value)?.absoluteString
    }

    @Test("phone-shaped kinds keep the plus and drop the punctuation")
    func phones() {
        #expect(url(.phone, "+1 (555) 010-2030") == "tel:+15550102030")
        #expect(url(.sms, "555 010 2030") == "sms:5550102030")
        #expect(url(.facetime, "+1 555 010 2030") == "facetime://+15550102030")
        #expect(url(.facetimeAudio, "sam@example.com") == "facetime-audio://sam@example.com")
        #expect(url(.whatsapp, "+1 555-010-2030") == "https://wa.me/15550102030", "wa.me wants digits only")
        #expect(url(.signal, "+15550102030") == "https://signal.me/#p/+15550102030")
    }

    @Test("handles are accepted bare, with an @, or as a profile URL")
    func handles() {
        #expect(url(.instagram, "@sam.k") == "https://instagram.com/sam.k")
        #expect(url(.instagram, "https://www.instagram.com/sam.k/") == "https://instagram.com/sam.k")
        #expect(url(.x, "sam") == "https://x.com/sam")
        #expect(url(.messenger, "sam.k") == "https://m.me/sam.k")
        #expect(url(.telegram, "@sam") == "https://t.me/sam")
        #expect(url(.telegram, "+1 555 010 2030") == "https://t.me/+15550102030")
        #expect(url(.linkedin, "linkedin.com/in/sam-k-123") == "https://linkedin.com/in/sam-k-123")
        #expect(url(.snapchat, "sam") == "https://snapchat.com/add/sam")
    }

    @Test("what cannot be deep-linked yields nothing, so the button copies instead")
    func copyOnly() {
        #expect(url(.wechat, "sam_wx") == nil)
        #expect(url(.discord, "sam#1234") == nil)
        #expect(url(.discord, "123456789012345678") == "https://discord.com/users/123456789012345678")
        #expect(url(.phone, "   ") == nil)
    }

    @Test("a bare domain becomes https, an explicit scheme is kept")
    func links() {
        #expect(url(.url, "example.com/sam") == "https://example.com/sam")
        #expect(url(.url, "http://example.com") == "http://example.com")
        #expect(url(.email, "sam@example.com") == "mailto:sam@example.com")
    }

    @Test("a tap implies the interaction it starts")
    func impliedKind() {
        #expect(ContactLinks.entryKind(for: .phone) == .call)
        #expect(ContactLinks.entryKind(for: .facetime) == .video)
        #expect(ContactLinks.entryKind(for: .whatsapp) == .message)
        #expect(ContactLinks.entryKind(for: .email) == .email)
        #expect(ContactLinks.entryKind(for: .instagram) == .social)
    }
}
