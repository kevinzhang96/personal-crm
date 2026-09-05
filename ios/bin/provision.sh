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
API=https://api.appstoreconnect.apple.com/v1

set -- "$HOME/.appstoreconnect/private_keys"/AuthKey_*.p8
KEY=$1
[ -f "$KEY" ] || { echo "No AuthKey_*.p8 in ~/.appstoreconnect/private_keys/" >&2; exit 1; }
KEY_ID=$(basename "$KEY" .p8); KEY_ID=${KEY_ID#AuthKey_}
ISSUER=$(cat "$HOME/.appstoreconnect/issuer_id")
command -v jq >/dev/null || { echo "jq is required (brew install jq)" >&2; exit 1; }

b64() { openssl base64 -e -A | tr '+/' '-_' | tr -d '='; }
NOW=$(date +%s)
HEADER=$(printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "$KEY_ID" | b64)
CLAIMS=$(printf '{"iss":"%s","iat":%s,"exp":%s,"aud":"appstoreconnect-v1"}' "$ISSUER" "$NOW" $((NOW + 1200)) | b64)
# ES256 wants the raw r||s signature, and openssl emits DER; convert.
SIG=$(printf '%s.%s' "$HEADER" "$CLAIMS" \
  | openssl dgst -sha256 -sign "$KEY" \
  | openssl asn1parse -inform DER \
  | awk -F: '/INTEGER/{print $4}' | tr -d '\n' \
  | xxd -r -p | b64)
JWT="$HEADER.$CLAIMS.$SIG"
call() { curl -sSg -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" "$@"; }

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

# 3. The profile: reuse if present and valid, else create and install.
PID=$(call "$API/profiles?filter[name]=$PROFILE" | jq -r '.data[] | select(.attributes.profileState=="ACTIVE") | .id' | head -1)
if [ -z "$PID" ]; then
  PID=$(call -X POST "$API/profiles" -d '{"data":{"type":"profiles","attributes":{"name":"'"$PROFILE"'","profileType":"IOS_APP_STORE"},"relationships":{"bundleId":{"data":{"type":"bundleIds","id":"'"$BID"'"}},"certificates":{"data":[{"type":"certificates","id":"'"$CID"'"}]}}}}' | jq -r '.data.id')
  [ -n "$PID" ] && [ "$PID" != null ] || { echo "could not create profile $PROFILE" >&2; exit 1; }
  echo "created profile $PROFILE ($PID)"
fi
DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
mkdir -p "$DIR"
call "$API/profiles/$PID" | jq -r '.data.attributes.profileContent' | openssl base64 -d -A > "$DIR/$PROFILE.mobileprovision"
[ -s "$DIR/$PROFILE.mobileprovision" ] || { echo "downloaded profile is empty" >&2; exit 1; }
echo "PROVISION-OK $DIR/$PROFILE.mobileprovision"
echo "Next: create the app in App Store Connect (bundle id $BUNDLE_ID), then ./bin/release.sh"
