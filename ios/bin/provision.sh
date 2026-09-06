#!/bin/sh
# One-time: register the bundle id and create the App Store provisioning
# profile through the App Store Connect API, then install the profile.
#
# Uses the same key as release.sh and the Apple Distribution certificate
# already in the keychain (created for tcgdb; certificates are per team,
# not per app). Idempotent: an existing bundle id or profile is reused.
# What it cannot do is create the app record itself — the ASC API has no
# such call — so that stays a two-minute form at
# https://appstoreconnect.apple.com/apps (+ → New App, bundle id below).
set -eu

BUNDLE_ID=com.kevinzhang.tend
NAME=Tend
PROFILE=tend-appstore
CERT_NAME="iPhone Distribution: Kevin Zhang (XF283F7SB6)"
cd "$(dirname "$0")"
. ./asc.sh

# 1. Bundle id (registered under the team in the developer portal).
BID=$(call "$API/bundleIds?filter[identifier]=$BUNDLE_ID" | jq -r '.data[] | select(.attributes.identifier=="'"$BUNDLE_ID"'") | .id' | head -1)
if [ -z "$BID" ]; then
  BID=$(call -X POST "$API/bundleIds" -d '{"data":{"type":"bundleIds","attributes":{"identifier":"'"$BUNDLE_ID"'","name":"'"$NAME"'","platform":"IOS"}}}' | jq -r '.data.id')
  [ -n "$BID" ] && [ "$BID" != null ] || { echo "could not register $BUNDLE_ID" >&2; exit 1; }
  echo "registered bundle id $BUNDLE_ID ($BID)"
else
  echo "bundle id $BUNDLE_ID exists ($BID)"
fi

# 2. The distribution certificate, matched by serial against the keychain
#    copy so the profile is built on the identity xcodebuild will sign with.
SERIAL=$(security find-certificate -c "$CERT_NAME" -p | openssl x509 -noout -serial | cut -d= -f2)
CID=$(call "$API/certificates?filter[certificateType]=DISTRIBUTION,IOS_DISTRIBUTION&limit=200" \
  | jq -r --arg s "$SERIAL" '.data[] | select((.attributes.serialNumber|ascii_upcase)==($s|ascii_upcase)) | .id' | head -1)
[ -n "$CID" ] || { echo "no ASC certificate matches keychain serial $SERIAL" >&2; exit 1; }

# 2b. Capabilities the app declares in its entitlements. iCloud (CloudKit)
#     and Push, which CloudKit uses for its silent change notifications.
#     The iCloud *container* is not something this API can create or
#     assign — see deploy/ICLOUD.md for that one portal step.
HAVE=$(call "$API/bundleIds/$BID/bundleIdCapabilities" | jq -r '.data[].attributes.capabilityType')
enable() {
  if echo "$HAVE" | grep -qx "$1"; then echo "capability $1 already on"; return; fi
  R=$(call -X POST "$API/bundleIdCapabilities" -d '{"data":{"type":"bundleIdCapabilities","attributes":{"capabilityType":"'"$1"'"'"$2"'},"relationships":{"bundleId":{"data":{"type":"bundleIds","id":"'"$BID"'"}}}}}')
  echo "$R" | jq -e '.data.id' >/dev/null || { echo "could not enable $1: $(echo "$R" | jq -c '.errors[0].detail // .')" >&2; exit 1; }
  echo "enabled capability $1"
}
enable ICLOUD ',"settings":[{"key":"ICLOUD_VERSION","options":[{"key":"XCODE_6"}]}]'
enable PUSH_NOTIFICATIONS ''

# 3. The profile: reuse if present and valid, else create and install. A
#    capability change invalidates the old profile; an invalid one under
#    this name is deleted so the name can be reused.
for OLD in $(call "$API/profiles?filter[name]=$PROFILE" | jq -r '.data[] | select(.attributes.profileState!="ACTIVE") | .id'); do
  call -X DELETE "$API/profiles/$OLD" >/dev/null && echo "removed invalid profile $OLD"
done
PID=$(call "$API/profiles?filter[name]=$PROFILE" | jq -r '.data[] | select(.attributes.profileState=="ACTIVE") | .id' | head -1)
if [ -z "$PID" ]; then
  PID=$(call -X POST "$API/profiles" -d '{"data":{"type":"profiles","attributes":{"name":"'"$PROFILE"'","profileType":"IOS_APP_STORE"},"relationships":{"bundleId":{"data":{"type":"bundleIds","id":"'"$BID"'"}},"certificates":{"data":[{"type":"certificates","id":"'"$CID"'"}]}}}}' | jq -r '.data.id')
  [ -n "$PID" ] && [ "$PID" != null ] || { echo "could not create profile $PROFILE" >&2; exit 1; }
  echo "created profile $PROFILE ($PID)"
fi
asc_install_profile "$PID" "$PROFILE"
echo "If this is a first setup: create the app in App Store Connect (bundle id $BUNDLE_ID)."
echo "If iCloud is not yet assigned to the App ID: see deploy/ICLOUD.md. Then ./bin/release.sh"
