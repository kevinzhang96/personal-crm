#!/bin/sh
# Archive, sign, and upload a TestFlight build.
#
# Lifted from tcgdb (minus its Kotlin core step) and fully account-free:
#   - SIGNING is manual: the Apple Distribution certificate already in the
#     login keychain, plus the tend-appstore App Store profile that
#     bin/provision.sh creates through the ASC API.
#   - UPLOAD rides the same ASC API key via altool. Key at
#     ~/.appstoreconnect/private_keys/AuthKey_<ID>.p8, issuer id in
#     ~/.appstoreconnect/issuer_id.
set -eu
cd "$(dirname "$0")/.."

BUILD=${1:-$(date +%y%m%d.%H%M)}

# Preflight, before the archive: every credential the upload needs must
# exist now, or the failure surfaces at altool ten minutes from here.
set -- "$HOME/.appstoreconnect/private_keys"/AuthKey_*.p8
KEY=$1
[ -f "$KEY" ] || { echo "No AuthKey_*.p8 in ~/.appstoreconnect/private_keys/" >&2; exit 1; }
[ -f "$HOME/.appstoreconnect/issuer_id" ] || {
  echo "No ~/.appstoreconnect/issuer_id" >&2; exit 1; }
KEY_ID=$(basename "$KEY" .p8); KEY_ID=${KEY_ID#AuthKey_}
ISSUER=$(cat "$HOME/.appstoreconnect/issuer_id")
ls "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"/*.mobileprovision \
   "$HOME/Library/MobileDevice/Provisioning Profiles"/*.mobileprovision 2>/dev/null \
  | xargs -I{} sh -c 'security cms -D -i "{}" 2>/dev/null' | grep -q '<string>tend-appstore</string>' \
  || { echo "No installed profile named tend-appstore — run bin/provision.sh first" >&2; exit 1; }

xcodegen generate
xcodebuild archive -project Tend.xcodeproj -scheme Tend \
  -destination 'generic/platform=iOS' -archivePath build/Tend.xcarchive \
  CURRENT_PROJECT_VERSION="$BUILD"
xcodebuild -exportArchive -archivePath build/Tend.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/export
[ -s build/export/Tend.ipa ] || { echo "export produced no Tend.ipa" >&2; exit 1; }
xcrun altool --upload-app -f build/export/Tend.ipa -t ios \
  --apiKey "$KEY_ID" --apiIssuer "$ISSUER"
echo "RELEASE-OK build=$BUILD uploaded — appears in TestFlight once Apple finishes processing (~5-15 min)."
