# Tend

A personal CRM for friendships, as an iOS app. It remembers when you last
talked to each friend and what you talked about, then nudges you: a daily
digest of who has gone quiet, and follow-ups on the specific things people
told you ("her interview is next Thursday" → "ask Priya how the interview
went", the morning after).

Everything stays on the phone. Export is a zip of JSON + CSV + audio.

- Design, end to end: [docs/DESIGN.md](docs/DESIGN.md)
- Working conventions: [CLAUDE.md](CLAUDE.md)

## What's built (v0.1)

- **Today**: who is overdue (by circle cadence), follow-ups due this week,
  birthdays in the next fortnight, recent entries.
- **People**: search that understands people — words match names, tags,
  places, groups, facts and notes; `#tag`, `lives:LIC`, `works:Figma`,
  `partner:`, `met:college`, `note:skiing` narrow, and terms combine.
  Chips for All, ★ starred and Reach out, and pickers for group and tag
  that open as sheets. List or tile view (five faces across), remembered.
  Long-press for a preview and the quick actions; swipe left for every
  way to contact them, swipe right to start selecting — both edges are
  yours to reassign in Settings. Each swipe edge carries
  one action you choose in Settings (select, log a call, star, snooze,
  archive, delete); out of the box a right swipe starts a selection with
  that person ticked and a left swipe snoozes; delete always confirms
  first. Select turns the list into a checklist: add the ticked people to
  groups or take them out, star them, archive them, or delete them.
  Starred people sort first.
- **Groups**: your own, with a cadence each (the five built-in circles are
  the starting set). A friend can be in several; the tightest cadence
  among them applies. Make, rename, re-pace, reorder and delete groups
  from Settings; deleting a group asks where anyone left with no group
  should go. Add one by hand, many from Contacts
  (multi-select picker), or many by pasting a list of names; both bulk
  paths go through a review sheet that sets the groups and tags for the
  batch and skips anyone already added. Whichever group the list is
  filtered to when you tap + is the batch's starting group.
- **Friend page**: a summary of what to remember right now, rebuilt after
  every log (written by the on-device model where there is one, composed
  from facts and recent notes otherwise); one-tap reach (call / text /
  FaceTime / WhatsApp menu on a number; Messenger, Instagram, Telegram,
  Signal, email… as links); facts, follow-ups, dates, timeline. Tapping a
  reach button asks "did you reach them?" when you come back.
- **Capture**: typed note or voice memo (on-device transcription), or an
  imported audio file. Saving runs the extractor and proposes follow-ups
  and facts — every proposal's wording, date, label and value editable
  before it is added; Apple's on-device language model when the device
  has one, a deterministic pattern matcher otherwise.
- **Nudges**: local notifications only — a morning digest on days someone
  is overdue (next 7 mornings pre-scheduled, background refresh extends),
  follow-ups on their day, birthdays on their day.
- **Backup**: export a zip (backup.json v1, friends.csv, entries.csv,
  audio/); import merges by id.

## Build

```sh
cd ios && xcodegen generate && open Tend.xcodeproj
```

Tests (Swift Testing, over `Sources/Logic` only):

```sh
cd ios && xcodebuild test -project Tend.xcodeproj -scheme Tend -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Ship (TestFlight)

Signing and upload reuse tcgdb's account-level setup (distribution
certificate in the keychain, App Store Connect API key in
`~/.appstoreconnect`). Three one-time steps for this app:

1. `cd ios && ./bin/provision.sh` — registers the bundle id and creates the
   `tend-appstore` profile through the ASC API.
2. Create the app record at appstoreconnect.apple.com (bundle id
   `com.kevinzhang.tend`); the API has no call for this.
3. `cd ios && ./bin/release.sh` — archive, sign, upload.
