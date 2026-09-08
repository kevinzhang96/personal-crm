#!/bin/sh
# One-time per machine: a development profile for Debug builds, made the
# same account-free way as the App Store one — this Mac registered as a
# device and the Apple Development certificate already in the keychain,
# through the App Store Connect API. A development-signed build talks to
# CloudKit's Development environment, which is where the schema is first
# created; the App Store build cannot do that.
set -eu
cd "$(dirname "$0")"
. ./asc.sh

BUNDLE_ID=com.kevinzhang.tend
PROFILE=tend-dev
CERT_NAME="Apple Development: Kevin Zhang"

BID=$(call "$API/bundleIds?filter[identifier]=$BUNDLE_ID" | jq -r '.data[] | select(.attributes.identifier=="'"$BUNDLE_ID"'") | .id' | head -1)
[ -n "$BID" ] || { echo "bundle id $BUNDLE_ID is not registered — run provision.sh first" >&2; exit 1; }

CID=$(asc_certificate_id "$CERT_NAME" "DEVELOPMENT,IOS_DEVELOPMENT")
[ -n "$CID" ] || { echo "no ASC development certificate matches the keychain's \"$CERT_NAME\"" >&2; exit 1; }

# This Mac, registered as a device: an iOS app runs on Apple silicon
# under an iOS development profile that lists the Mac.
UDID=$(system_profiler SPHardwareDataType | awk -F': ' '/Provisioning UDID/{print $2}')
NAME=$(scutil --get ComputerName)
DID=$(call "$API/devices?limit=200" | jq -r --arg u "$UDID" '.data[] | select(.attributes.udid==$u) | .id' | head -1)
if [ -z "$DID" ]; then
  R=$(call -X POST "$API/devices" -d '{"data":{"type":"devices","attributes":{"name":"'"$NAME"'","platform":"MAC_OS","udid":"'"$UDID"'"}}}')
  DID=$(echo "$R" | jq -r '.data.id // empty')
  [ -n "$DID" ] || { echo "could not register this Mac: $(echo "$R" | jq -c '.errors[0].detail // .')" >&2; exit 1; }
  echo "registered $NAME ($UDID) as $DID"
else
  echo "this Mac is registered ($DID)"
fi

for OLD in $(call "$API/profiles?filter[name]=$PROFILE" | jq -r '.data[] | select(.attributes.profileState!="ACTIVE") | .id'); do
  call -X DELETE "$API/profiles/$OLD" >/dev/null && echo "removed invalid profile $OLD"
done
PID=$(call "$API/profiles?filter[name]=$PROFILE" | jq -r '.data[] | select(.attributes.profileState=="ACTIVE") | .id' | head -1)
if [ -z "$PID" ]; then
  R=$(call -X POST "$API/profiles" -d '{"data":{"type":"profiles","attributes":{"name":"'"$PROFILE"'","profileType":"IOS_APP_DEVELOPMENT"},"relationships":{"bundleId":{"data":{"type":"bundleIds","id":"'"$BID"'"}},"certificates":{"data":[{"type":"certificates","id":"'"$CID"'"}]},"devices":{"data":[{"type":"devices","id":"'"$DID"'"}]}}}}')
  PID=$(echo "$R" | jq -r '.data.id // empty')
  [ -n "$PID" ] || { echo "could not create profile $PROFILE: $(echo "$R" | jq -c '.errors[0].detail // .')" >&2; exit 1; }
  echo "created profile $PROFILE ($PID)"
else
  echo "profile $PROFILE exists ($PID)"
fi
asc_install_profile "$PID" "$PROFILE"
