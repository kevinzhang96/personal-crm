// The swipe preference's stored form.

import Testing
@testable import Tend

struct SwipeActionTests {
    @Test("an edge stores one action and reads it back; bare is bare")
    func roundTrip() {
        for action in SwipeAction.allCases {
            #expect(SwipeAction.one(SwipeAction.store(action)) == action)
        }
        #expect(SwipeAction.store(nil) == "")
        #expect(SwipeAction.one("") == nil)
    }

    @Test("a value from a build that knew other actions is a bare edge, not a crash")
    func unknown() {
        #expect(SwipeAction.one("teleport") == nil)
    }

    @Test("out of the box, right selects and left snoozes, and only delete is destructive")
    func defaults() {
        #expect(SwipeAction.one(SwipeAction.defaultLeading) == .select)
        #expect(SwipeAction.one(SwipeAction.defaultTrailing) == .snooze)
        #expect(SwipeAction.allCases.filter(\.isDestructive) == [.delete])
        #expect(SwipeAction.allCases.contains(.star))
    }
}
