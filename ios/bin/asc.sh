# Shared by provision.sh and dev-profile.sh: a bearer token for the App
# Store Connect API from the key in ~/.appstoreconnect, and `call`.
set -eu

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

# The certificate in the keychain under `name`, as the ASC certificate id.
asc_certificate_id() {
  SERIAL=$(security find-certificate -c "$1" -p | openssl x509 -noout -serial | cut -d= -f2)
  call "$API/certificates?filter[certificateType]=$2&limit=200" \
    | jq -r --arg s "$SERIAL" '.data[] | select((.attributes.serialNumber|ascii_upcase)==($s|ascii_upcase)) | .id' | head -1
}

# Download and install profile `$1` (an ASC id) under name `$2`.
asc_install_profile() {
  DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
  mkdir -p "$DIR"
  call "$API/profiles/$1" | jq -r '.data.attributes.profileContent' | openssl base64 -d -A > "$DIR/$2.mobileprovision"
  [ -s "$DIR/$2.mobileprovision" ] || { echo "downloaded profile is empty" >&2; exit 1; }
  echo "PROVISION-OK $DIR/$2.mobileprovision"
}
