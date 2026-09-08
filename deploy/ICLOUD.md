# iCloud sync: the one step the API cannot do

Tend syncs its store to the private CloudKit database of the container
**`iCloud.com.kevinzhang.tend`**. The app is built with that entitlement,
so a signed build needs the App ID to carry the iCloud and Push
capabilities *and* that container. `ios/bin/provision.sh` turns on the two
capabilities through the App Store Connect API and regenerates the
profile; the API has no way to create or assign an iCloud container, so
that is a two-minute visit to the developer portal, once:

1. Open <https://developer.apple.com/account/resources/identifiers/list/cloudContainer>
   and click **+**. Description: `Tend`. Identifier: `iCloud.com.kevinzhang.tend`.
   Continue → Register.
2. Open <https://developer.apple.com/account/resources/identifiers/list>,
   pick **Tend (com.kevinzhang.tend)**, find **iCloud** in the list (it is
   already ticked, by provision.sh), click **Edit** beside it, tick the
   `iCloud.com.kevinzhang.tend` container, Continue → Save.
3. Back on this machine:

   ```sh
   cd ~/code/personal-crm/ios && ./bin/provision.sh
   ```

   which deletes the profile the capability change invalidated and
   installs a fresh `tend-appstore` that includes the container.

Until step 3 is done, the deploy pipeline's iOS job fails at code
signing with "Provisioning profile doesn't include the
com.apple.developer.icloud-container-identifiers entitlement". The tests
job is unaffected, and the simulator build carries the entitlement
regardless.

## What syncs, and what the app does without it

Everything in the store: people, groups, methods, entries and their
recordings (external binary data in the store), facts, reminders, dates,
summaries. The store is opened CloudKit-backed when the entitlement is
present; a build without it, or a device that refuses, falls back to the
local store and Settings → iCloud says why. A pre-sync store is imported
into the synced one once, on first launch of a syncing build, through the
same codec as backup export (`Store.migrateLegacy`), and left in place
with a `.migrated` marker.

CloudKit sync needs the device signed in to iCloud; without an account
the app runs local-only and syncs once one appears. The CloudKit schema
is created on first use from the Development environment; before the
App Store build, deploy the schema to Production in
<https://icloud.developer.apple.com/dashboard> (TestFlight builds use the
Production environment, so this matters for the first TestFlight build
after sync ships).

## Creating the schema in Development

Only a development-signed build talks to the Development environment,
and only a save creates record types. The Debug configuration signs for
development with `tend-dev`, a profile `ios/bin/dev-profile.sh` makes
the same account-free way as the App Store one (this Mac registered as a
device, the Apple Development certificate already in the keychain), and
carries `Tend-Debug.entitlements` (development push, Development
container environment). Release is untouched.

To create every record type at once, on this Mac signed in to iCloud:

```sh
cd ~/code/personal-crm/ios && ./bin/dev-profile.sh   # once per machine
TEST_RUNNER_TEND_SCHEMA_PROBE=1 xcodebuild test -project Tend.xcodeproj -scheme Tend \
  -configuration Debug -destination 'id=<this Mac's provisioning UDID>' \
  -only-testing:TendTests/SchemaProbeTests
```

xcodebuild launches the Debug app on the Mac as the test host; the app
writes one row of every model (`Services/SchemaProbe.swift`, Debug
only), waits for CloudKit's export, deletes the rows, and the test
prints `SCHEMA PROBE OK` with the probe's log. The Mac's provisioning
UDID is in `system_profiler SPHardwareDataType`. The same probe runs
from a Debug build launched with `-schemaProbe 1`. If the app reports
`CKAccountStatus` 3 (no account), the Mac is not signed in to iCloud as
far as iOS apps on it are concerned; sign in and run it again.

Then in the dashboard: Schema → Deploy Schema Changes → to Production.
`xcrun cktool` can do the same with a management token from the
dashboard (Tokens → Management Token → `xcrun cktool save-token`).
