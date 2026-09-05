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
- **People**: search, circle filters, long-press preview with facts and
  last notes. Each swipe edge carries one action you choose in Settings
  (log a call, snooze, archive, delete); delete always confirms first. Add one by hand, many from Contacts
  (multi-select picker), or many by pasting a list of names; both bulk
  paths go through a review sheet that sets the circle and tags for the
  batch and skips anyone already added.
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
