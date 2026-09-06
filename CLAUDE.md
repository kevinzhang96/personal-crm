# Tend — working conventions for agents

Read this before changing anything. `docs/DESIGN.md` is the design and is
binding; this file is the short version of how to work in the repo.

## Product architecture

- **Local-first, no server.** All data lives in the on-device SwiftData
  store. There is no backend and nothing here should assume one; iCloud
  sync, when it comes, is CloudKit over the same models. Keep the models
  CloudKit-compatible: every relationship optional, every property with a
  default, no `@Attribute(.unique)`.
- **Functional core, imperative shell.** `ios/Sources/Logic/` is pure —
  no SwiftData, no UIKit, no clocks (every function takes `now`). It is the
  only layer with unit tests, and it is where cadence, digest, suggestion,
  grounding, judge-loop, link and backup rules live. `Services/` is the edge (Contacts, audio,
  speech, notifications, files); `Views/` render and call services.
- **Derived, never stored.** Last contact and overdue status are computed
  from entries; never add a column that caches them.
- **The backup JSON is the durable format.** `Logic/Backup.swift` decodes
  independently of the SwiftData models, and its `version` is bumped with
  a migration path when the shape changes. Models may change freely under
  it.
- **Suggestions are proposals.** Nothing the extractor produces is saved
  without the user accepting it. The pipeline is proposer → rules → judge
  (`Logic/Grounding.swift`, `Logic/JudgeLoop.swift`); each stage only
  proposes or trims, and the bias is toward leaving things out. A change
  to what gets suggested usually touches the heuristic and the rules,
  not just a prompt string.
- **Design language:** midnight glass (`~/.claude/skills/midnight-glass-ui/SKILL.md`).
  `Theme.swift` is copied from tcgdb; here blue = action, green = in touch /
  on track, orange = overdue / due. An accent must mean something.

## Build, test, ship

- `cd ios && xcodegen generate` — the `.xcodeproj` is generated from
  `project.yml`, never hand-edited or committed.
- Build: `xcodebuild build -project Tend.xcodeproj -scheme Tend -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
- Test: `xcodebuild test -project Tend.xcodeproj -scheme Tend -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
- Verify a build compiles before declaring UI work done; screenshot both
  colour schemes for UI changes.
- Release: `cd ios && ./bin/release.sh` — manual signing (team XF283F7SB6,
  profile `tend-appstore`), account-free `altool` upload with the App
  Store Connect key in `~/.appstoreconnect`. The one-time bundle-id and
  profile registration is `ios/bin/provision.sh`.
- No secrets in git. Signing material lives in the login keychain and
  `~/.appstoreconnect`, both belonging to the machine.

## Quality bar

- Every unit of code has a one-sentence purpose; core logic stays pure;
  edge cases live at the boundary that owns them
  (`~/.claude/skills/principled-review/`).
- Comments say *why*, never *what*, and never narrate a change. Match the
  surrounding density.
- Tests are Swift Testing (`import Testing`), over `Logic/` only; the shell
  is verified by building and running.
