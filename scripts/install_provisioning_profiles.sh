#!/usr/bin/env bash
# Put the App Store provisioning profiles on this machine, ready for an archive.
#
# Release signing is manual precisely so that nothing can be minted mid-build.
# The archive names this certificate and these two profiles; if any of them is
# missing the build stops, rather than quietly asking Apple for a new signing
# certificate and filling the account's limit — which is how CI broke in August
# after a dozen unattended builds each left one behind.
#
# A second distribution certificate on the account must not stop builds either.
# In October 2026 B5JF4R83AN appeared next to CI's TKP9T7D2W7 and every build
# failed rather than guess between them — so the script identifies CI's
# certificate by fingerprint instead of requiring exactly one. The other
# certificate is left alone; it may belong to a teammate's local signing.
#
# Safe to run on every build: an existing profile is reused, and only a profile
# Apple has marked unusable is replaced.
set -euo pipefail

APP_BUNDLE_ID="${APP_BUNDLE_ID:-com.parthjadhav.ironlog}"
WIDGET_BUNDLE_ID="${WIDGET_BUNDLE_ID:-com.parthjadhav.ironlog.IronLogWidget}"
# These names are also in the Xcode project and ExportOptions.plist; changing one
# means changing all three.
APP_PROFILE_NAME="${APP_PROFILE_NAME:-Setzo App Store}"
WIDGET_PROFILE_NAME="${WIDGET_PROFILE_NAME:-Setzo Widget App Store}"

for required in ASC_API_KEY_ID ASC_API_ISSUER_ID ASC_API_PRIVATE_KEY_PATH; do
  if [[ -z "${!required:-}" ]]; then
    echo "$required must be set"
    exit 1
  fi
done

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

asc auth login \
  --name setzo \
  --key-id "$ASC_API_KEY_ID" \
  --issuer-id "$ASC_API_ISSUER_ID" \
  --private-key "$ASC_API_PRIVATE_KEY_PATH" > /dev/null

# Pull ids by searching the response rather than indexing a fixed path, so a
# change in how the CLI wraps its output does not quietly break this.
certs_json="$(asc certificates list --certificate-type DISTRIBUTION --paginate --output json)"
certificate_ids="$(printf '%s' "$certs_json" | jq -r '[.. | objects | select(.type? == "certificates") | .id] | unique | .[]')"
certificate_count="$(printf '%s\n' "$certificate_ids" | grep -c . || true)"

if [[ "$certificate_count" -eq 0 ]]; then
  echo "No distribution certificate on the account."
  echo "Create one with scripts/new_signing_certificate.sh."
  exit 1
fi

# Never guess between certificates: use the one whose public half matches the
# signing identity this job imported. The P12 step runs before this script in
# the same job, so CI's certificate is in the keychain; `find-identity` prints
# each identity's SHA-1 fingerprint, which is the SHA-1 of the DER content.
local_fingerprints="$(security find-identity -v -p codesigning 2> /dev/null \
  | grep -oE '[0-9A-F]{40}' | tr 'A-Z' 'a-z' || true)"
if [[ -z "$local_fingerprints" ]]; then
  echo "No codesigning identity in the keychain."
  echo "The P12 import step must run before this script."
  exit 1
fi

certificate_id=""
match_count=0
for candidate in $certificate_ids; do
  content="$(printf '%s' "$certs_json" \
    | jq -r --arg id "$candidate" \
      '[.. | objects | select(.type? == "certificates" and .id == $id) | .certificateContent] | first // empty')"
  if [[ -z "$content" ]]; then
    echo "Apple returned no certificate content for $candidate; cannot verify it."
    exit 1
  fi
  fingerprint="$(printf '%s' "$content" | base64 --decode 2> /dev/null \
    | openssl sha1 -r 2> /dev/null | awk '{print $1}' | tr 'A-Z' 'a-z')"
  if [[ -z "$fingerprint" ]]; then
    echo "Could not fingerprint certificate $candidate."
    exit 1
  fi
  if printf '%s\n' "$local_fingerprints" | grep -qxF "$fingerprint"; then
    certificate_id="$candidate"
    match_count=$((match_count + 1))
  fi
done

if [[ "$match_count" -eq 0 ]]; then
  echo "None of the $certificate_count distribution certificate(s) on the account"
  echo "matches this job's signing identity:"
  printf '  %s\n' $certificate_ids
  echo "Local keychain fingerprints:"
  printf '  %s\n' "$local_fingerprints"
  echo "If CI's certificate was replaced, update SIGNING_CERTIFICATE_P12(+_PASSWORD)."
  exit 1
fi
if [[ "$match_count" -gt 1 ]]; then
  echo "More than one account certificate matches this job's signing identity;"
  echo "refusing to choose. Clean up the duplicates in Certificates, Identifiers & Profiles."
  exit 1
fi
echo "Using distribution certificate $certificate_id (matches this job's signing identity)."

bundle_resource_id() {
  asc bundle-ids list --paginate --output json \
    | jq -r --arg identifier "$1" \
      '[.. | objects | select(.attributes?.identifier == $identifier) | .id] | first // empty'
}

find_profile() {
  asc profiles list --profile-type IOS_APP_STORE --paginate --output json \
    | jq -r --arg name "$1" --arg state "$2" \
      '[.. | objects | select(.attributes?.name == $name and .attributes?.profileState == $state) | .id] | first // empty'
}

install_profile() {
  local name="$1" bundle_id="$2"
  local bundle_resource profile_id stale

  bundle_resource="$(bundle_resource_id "$bundle_id")"
  if [[ -z "$bundle_resource" ]]; then
    echo "No bundle ID registered for $bundle_id"
    exit 1
  fi

  profile_id="$(find_profile "$name" ACTIVE)"
  if [[ -z "$profile_id" ]]; then
    # A profile Apple has invalidated keeps its name, and the name has to be
    # free before a replacement can take it.
    stale="$(find_profile "$name" INVALID)"
    if [[ -n "$stale" ]]; then
      echo "Replacing invalidated profile $name ($stale)"
      asc profiles delete --id "$stale" --confirm > /dev/null
    fi

    echo "Creating profile $name for $bundle_id"
    profile_id="$(asc profiles create \
      --name "$name" \
      --profile-type IOS_APP_STORE \
      --bundle "$bundle_resource" \
      --certificate "$certificate_id" \
      --output json \
      | jq -r '[.. | objects | select(.type? == "profiles") | .id] | first // empty')"
    if [[ -z "$profile_id" ]]; then
      echo "Apple accepted the request but returned no profile id."
      exit 1
    fi
  else
    echo "Reusing profile $name ($profile_id)"
  fi

  # Named per profile: the download refuses to write over an existing file, so a
  # shared filename fails the moment there is more than one profile to fetch.
  local downloaded="$work_dir/$profile_id.mobileprovision"
  rm -f "$downloaded"
  asc profiles download --id "$profile_id" --output "$downloaded" > /dev/null
  asc profiles local install --path "$downloaded"
}

install_profile "$APP_PROFILE_NAME" "$APP_BUNDLE_ID"
install_profile "$WIDGET_PROFILE_NAME" "$WIDGET_BUNDLE_ID"
