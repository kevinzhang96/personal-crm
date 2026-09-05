# Tend — a personal CRM for friendships

> "I always forget to keep in touch with people, and I always forget the
> things we've talked about."

Tend is an iOS app that remembers two things for you: **when** you last
talked to each friend, and **what** you talked about — and then turns both
into nudges: catch-up reminders when someone has gone quiet, and follow-ups
on the specific things they told you.

This document is the whole design, end to end. Decisions made here are
binding for the code; `CLAUDE.md` points at it.

## 1. Product

### Who it is for

One person (Kevin) managing their own friendships. Not a team, not a sales
pipeline, not a social network. Everything is optimised for the one-handed
30-second capture after a phone call.

### Jobs to be done

| # | Job | Feature |
|---|-----|---------|
| 1 | Capture what we talked about, fast | Quick note; voice memo with on-device transcription; import an audio file |
| 2 | Know when I last talked to someone | Every interaction is a timeline entry; "last contact" is derived, never typed |
| 3 | Keep a living picture of each friend | Facts panel (partner, kids, job, likes, gift ideas…) + notes timeline |
| 4 | Never lose the data | Versioned JSON export with audio, CSV, import/restore; iOS device backup covers the store |
| 5 | Be nudged before a friendship goes quiet | Per-friend cadence via circles; daily digest notification of who is overdue |
| 6 | Organise people | Circles (inner / close / friends / acquaintances), free tags, search, archive |
| 7 | Reach them in one tap | Contact methods with deep links: phone, SMS, FaceTime, WhatsApp, Messenger, Instagram, Telegram, Signal, email, and more; linked to the iOS contact |
| 8 | Follow up on specific events | Follow-up reminders with a due date, tied to a friend and to the note that caused them |
| 9 | Be prompted to set those follow-ups | When a note is saved, an extractor proposes follow-ups ("Sarah's marathon is Sept 14 → check in Sept 15?") and facts; one tap accepts |

### Things a personal CRM also wants (and where they landed)

Considered beyond the original list. **MVP** ships in the first build;
**next** is designed for and cheap to add; **no** is a deliberate omission.

| Idea | Verdict | Why |
|------|---------|-----|
| Today dashboard (overdue, due follow-ups, birthdays this week) | MVP | It is the screen that makes the app worth opening |
| Birthdays and important dates with yearly reminders | MVP | The most common "I forgot" of all |
| Log an interaction after tapping Call / Message | MVP | The app already knows you tried; asking "did you reach them?" on return costs one tap |
| Group interactions (one dinner, four friends) | MVP | An entry links to many friends; each gets the timestamp |
| Snooze a nudge ("not now, ask in 2 weeks") | MVP | A nudge you can't defer gets ignored, then the app gets ignored |
| Prep card before a call (last 3 notes + open facts) | MVP | It's the friend detail screen, ordered right |
| Relationship links (partner of, sibling of, met through) | Next | A `Fact` with a friend reference covers 80% today |
| Home-screen widget "reach out to…" | Next | WidgetKit reads the same store; needs an app group |
| Siri / App Intents ("log that I called Sam") | Next | App Intents over the same entry editor |
| Share-sheet capture (send a screenshot or a text into a friend's timeline) | Next | Share extension; needs an app group |
| iCloud sync across devices (CloudKit) | Next | Models are written CloudKit-compatible from day one (see §3) so this is a capability toggle, not a migration |
| Face ID lock | Next | LocalAuthentication gate at the root; 40 lines |
| Stats / streaks ("12 people this month") | Next | Cheap once entries exist; not the point of v1 |
| Location / time zone → good time to call | Next | One field on Friend |
| Read call history or iMessage automatically | No | iOS exposes neither to third-party apps |
| Record phone calls in-app | No | iOS gives apps no access to call audio. Apple's own Phone-app recording (iOS 18.1+) saves to Notes; export that file and import it here |
| Message templates / auto-drafted texts | No | Friends can tell |
| Sentiment or "relationship score" | No | Gamifying friendship is how you lose the plot |
| Multi-user / sharing | No | Personal |

## 2. Architecture

### Local-first, no server

All data lives on the phone in a SwiftData store. There is no backend.

- **Privacy is the product.** Notes about friends' health, jobs, and
  relationships are the most sensitive data most people hold. The strongest
  story is "it never leaves your phone unless you export it".
- **Nothing to run.** No service to host, monitor, or keep releasable.
- **Offline is the normal case.** Capture happens right after a call, often
  with no signal.
- **Backup is already solved** for the store by iOS device backup; the app
  adds explicit, portable export (§5).

This deliberately inverts tcgdb's "backend does the work" rule: tcgdb has
three clients sharing one catalog; Tend has one client and one owner.
CloudKit sync is the designed-for path to a second device (§3), still
without a server of ours.

### Stack

- **SwiftUI + SwiftData**, iOS 26 deployment target (same as tcgdb).
- **Speech** for on-device transcription (`SFSpeechRecognizer` with
  on-device recognition when the device supports it).
- **FoundationModels** (Apple's on-device LLM) for follow-up and fact
  extraction where available; a pure heuristic extractor everywhere else.
- **Contacts** for linking and importing people.
- **UserNotifications** for every reminder — local, scheduled by the app.
- **BackgroundTasks** app-refresh to keep the digest scheduled when the
  app is not opened for a week.
- Design language: midnight glass (`~/.claude/skills/midnight-glass-ui`),
  `Theme.swift` copied from tcgdb with the green accent repurposed:
  **blue = action, green = "in touch / on track", orange = overdue / due.**

### Layout

```
ios/
  project.yml            xcodegen spec; bundle id com.kevinzhang.tend
  Sources/
    TendApp.swift        root: model container, tabs, notification delegate
    Theme.swift          midnight-glass tokens and panel components
    Models/              SwiftData models (the store's schema)
    Logic/               pure functions: cadence, digest, suggestions, links, backup codec
    Services/            edge: contacts, recorder, transcriber, notifier, exporter, extractor
    Views/               screens and sheets
  Tests/                 Swift Testing over Logic/ only
  bin/release.sh         archive → sign → TestFlight (from tcgdb, minus the Kotlin core)
  bin/provision.sh       one-time: register the bundle id and App Store profile via the ASC API
```

`Logic/` is the functional core: no SwiftData, no UIKit, no clocks —
every function takes `now` as an argument. `Services/` is the imperative
shell. Views call services; services call logic.

## 3. Data model

SwiftData models, written to be CloudKit-compatible from the start so sync
can be switched on without a migration: every relationship is optional,
every property has a default, no `@Attribute(.unique)`. Identity is a
`UUID` field the app sets.

```
Friend
  id, displayName, givenName, familyName, nickname
  photo: Data?                         thumbnail, from Contacts or camera roll
  contactIdentifier: String?           CNContact link; refreshable
  circle: inner | close | friends | acquaintances | none
  cadenceDays: Int?                    override of the circle's default
  snoozedUntil: Date?                  "not now"
  tags: [String]
  location, timeZoneIdentifier, howWeMet, about
  birthday: (month, day, year?)
  archived, createdAt, updatedAt
  methods  → [ContactMethod]
  entries  ↔ [Entry]                   many-to-many
  facts    → [Fact]
  reminders→ [Reminder]
  dates    → [ImportantDate]

ContactMethod   kind, value, label, preferred            kind ∈ phone, sms, facetime, facetimeAudio,
                                                         whatsapp, messenger, instagram, telegram,
                                                         signal, email, discord, linkedin, snapchat,
                                                         wechat, x, url
Entry           id, date, kind, text, transcript,        kind ∈ call, video, inPerson, message,
                audioFile, durationSeconds, createdAt     email, social, voiceMemo, note
                friends ↔ [Friend]                       note does NOT count as contact; the rest do
Fact            id, label, value, updatedAt, source → Entry?
Reminder        id, title, due, note, done, doneAt,      kind ∈ followUp, custom, birthday
                kind, source → Entry?, notificationId
ImportantDate   id, label, month, day, year?, remind
```

Derived, never stored: `lastContact` = max date of entries whose kind
counts as contact; `status` = f(lastContact, cadence, snooze, now).

## 4. Behaviour

### Search

The People search box is a small language (`Logic/PeopleQuery.swift`,
tested): a bare word matches anything about a person — name, nickname,
tags, location, how you met, about, group names, facts, and the text of
their entries; `key:value` narrows to one property; `#tag` is a tag;
terms AND together; double quotes hold a phrase. Keys are a fixed few
(`tag`, `group`/`in`, `lives`/`location`/`city`, `met`, `name`, `note`/
`said`/`mentioned`, `star`) and otherwise a fact label, so `works:figma`,
`partner:` (has one) and `gift:kettle` need no configuration. Tags are
free strings on the friend, added in the editor (existing tags offered
as toggles), in bulk from Select mode, and filtered by a dropdown chip.

### Groups

Every friend is in at least one group, and a group carries a cadence;
a friend in several inherits the tightest of them (being in Inner means
weekly, whatever else they are in; only no-nudge groups means never), and
`cadenceDays` on the friend overrides all of it. Groups are the reader's
own (`FriendGroup`: name, cadence, order). A friend can also be starred —
a flag with no semantics beyond sorting first and its own filter, which
is what makes it useful for whatever the reader means by it. The five circles
of the first design — inner 7d · close 30d · friends 90d · acquaintances
365d · no nudges — are seeded as the starting groups on first launch and
are ordinary groups from then on. The invariant that everyone has a
group is kept by `Services/Groups.swift`: it seeds, migrates the single
group of the first groups build into a membership, and re-homes any
friend without one (a pre-groups install, by the circle it kept; a
deleted group's sole members, by the destination chosen at deletion).
The People list filters by one group at a time through a dropdown chip
(a strip of chips stopped fitting past a handful of groups) that names
the group shown, lists them all with counts, and opens the manager.
Bulk membership changes happen from the People list's Select mode — one
menu entry per group, ticked when everyone chosen is in it, tapping adds
the rest or removes them all; the group manager lives in Settings and
behind the People "+" menu.

### Cadence and nudges

Status is pure:

```
overdue(days)  if now − lastContact > cadence   (never contacted ⇒ overdue since createdAt)
dueSoon        if within 20% of cadence of the deadline
onTrack        otherwise
snoozed        if snoozedUntil > now (hidden from digest until then)
```

The **daily digest** is one local notification at the user's chosen time
listing up to three overdue names and a count. Because status is a pure
function of stored dates, the next seven days' digests are computed and
scheduled in advance every time the app is foregrounded or data changes;
a background app-refresh task re-extends the window. Nothing is sent from
anywhere.

### Follow-ups

A `Reminder` schedules exactly one notification at `due` (9:00 local when
no time is given). Completing, deleting, or editing it reschedules. iOS caps
pending local notifications at 64, so the notifier keeps the 7 digests, the
nearest follow-ups, and the nearest birthdays, in that priority.

### Suggestions (auto follow-ups)

Saving an entry with text runs the extractor and shows a sheet of
proposals; accepting creates the `Reminder`/`Fact` with `source` pointing
at the entry. Nothing is created silently.

Two implementations behind one protocol, tried in order:

1. **FoundationModels** (on-device LLM, iOS 26 on Apple-Intelligence
   devices; verified working in the simulator on the Mac Studio):
   guided generation into a `@Generable` struct — events with an ISO
   date and evidence sentence, plus facts. Three guards, all learned from
   the first run: the prompt carries a dated calendar because a small
   model cannot do date arithmetic; the evidence sentence is re-resolved
   by the heuristic's date parser and wins over the model's date; and
   placeholder values ("none", "unknown") are dropped, because the model
   fills every slot it was told about.
2. **Heuristic**: `NSDataDetector` finds dates; a lexicon of event words
   (interview, surgery, wedding, trip, exam, moving, baby, presentation…)
   near a date proposes "check in the day after"; "partner/wife/husband/
   kids/works at" patterns propose facts. Deterministic, tested.

Proposals are editable in the sheet — wording and date of a follow-up,
label and value of a fact — because the model's phrasing is a draft, not
a verdict. Two guards on the model path, both learned from use: the
schema descriptions carry no example text, since a small model copies an
example into every answer ("Ask how the interview went" appeared on notes
about anything); and an event is kept only if its evidence sentence is
actually in the note and it carries a date or an event word.

### Summary

Each friend carries a short summary of what to remember right now,
rebuilt after each log is filed (after the suggestions sheet, so what was
accepted is in it) and on demand from the friend page. The on-device
model writes two to four sentences from a dated brief of facts, the
newest notes and open follow-ups (`Logic/Summary.swift` builds the brief,
bounded to twelve notes of 400 characters); without a model the same
brief is composed by hand into standing · facts · lately · up next.

### Interaction capture

- **Quick note**: text + kind + friends + date; kind defaults to `note`.
- **Voice memo**: AVAudioRecorder → `.m4a` in `Documents/audio/`; then the
  transcriber fills `transcript`, which the user can edit into `text`.
- **Import audio**: file importer (e.g., an Apple call recording exported
  from Notes) → same path as a voice memo.
- **After a tap on a contact method**: the app records a pending attempt;
  on return to the foreground it asks "Did you reach Sam?" and, if yes,
  opens the entry editor with kind and friend filled in.

### Contacts

Linking uses the system contact picker, stores the identifier, and copies
name, photo, phones, emails, birthday, social profiles and IM addresses
into Friend and ContactMethods. "Refresh from Contacts" re-pulls those
fields; nothing is written back to Contacts.

### Bulk add

The People "+" is a menu: one friend by hand, many from Contacts, or many
from a pasted list. The contact picker runs in multi-select mode (which
`CNContactPickerViewController` turns on when the delegate implements
the list-taking method, so it is a separate representable). Pasted text
is one name per line — or one line split on commas or semicolons — with
list numbering and bullets stripped (`Logic/BulkNames.swift`, tested).
Both paths land in one review sheet: a circle and tags for the whole
batch, one row per person, and anyone already present (same contact
identifier, or same name for pasted lists) shown as "added" and left out.
Contacts access is requested once per batch so full records can be
fetched; without it the picker's copies are applied, which still carry a
name and numbers.

## 5. Backup and export

Export writes a folder and zips it (via `NSFileCoordinator`'s
`forUploading` option, which needs no zip library):

```
Tend-2026-09-05/
  backup.json      version 1 — every table, UUID-keyed, ISO-8601 dates
  friends.csv      one row per friend: name, circle, last contact, status, tags
  entries.csv      one row per entry: date, kind, friends, text
  audio/*.m4a      every recording, named by entry id
```

Import reads a `backup.json` (or the whole folder, restoring audio) and
merges by UUID: existing rows are updated, missing ones created, nothing
is deleted. The JSON schema is versioned and decoded independently of the
SwiftData models, so it is the durable format; models can change under it.

## 6. Shipping

Everything tcgdb built for TestFlight is account-level and reusable: the
Apple Distribution certificate, the App Store Connect API key
(`~/.appstoreconnect`), the `altool` upload, xcodegen, the manual-signing
`ExportOptions.plist` pattern. What is app-specific and needed once:

1. Register the bundle id `com.kevinzhang.tend` and create an App Store
   provisioning profile against the existing certificate —
   `ios/bin/provision.sh` does both through the ASC API.
2. Create the app record in App Store Connect (the API cannot; it is a
   two-minute form on the website).
3. `cd ios && ./bin/release.sh` — archive, sign, upload.

## 7. Milestones

- **v0.1 (this build)**: everything marked MVP above, building and running
  in the simulator, tests over `Logic/`.
- **v0.2**: TestFlight; CloudKit sync; Face ID lock; widget.
- **v0.3**: App Intents; share-sheet capture; relationship links.
