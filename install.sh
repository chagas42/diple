#!/bin/bash
# Installs the latest Diple release into /Applications.
#
#   curl -fsSL https://raw.githubusercontent.com/chagas42/diple/main/install.sh | bash
#
# Why a script instead of the .zip: the build is signed ad-hoc, not notarised
# (that needs a paid Apple Developer account). A browser marks every download
# with com.apple.quarantine, and Gatekeeper then calls the app malware. curl
# does not set that flag, so nothing downloaded here is ever quarantined.

set -euo pipefail

REPO="chagas42/diple"
APP="Diple"
DEST="/Applications/$APP.app"

say()  { printf '  %s\n' "$*"; }
fail() { printf '  error: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || fail "Diple is a macOS app."

major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 14 ] || fail "Diple needs macOS 14 or newer (this is $(sw_vers -productVersion))."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# The asset name carries the version, so ask the API which one is latest.
release=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest") \
  || fail "could not reach GitHub to find the latest release."
zip_url=$(printf '%s' "$release" | grep -o '"browser_download_url": *"[^"]*\.zip"' | head -1 | cut -d'"' -f4)
[ -n "$zip_url" ] || fail "the latest release has no .zip attached."
zip_name=${zip_url##*/}

say "downloading $zip_name"
curl -fsSL "$zip_url" -o "$tmp/$zip_name"
curl -fsSL "$zip_url.sha256" -o "$tmp/$zip_name.sha256"

(cd "$tmp" && shasum -a 256 -c "$zip_name.sha256" >/dev/null) \
  || fail "checksum does not match — not installing."

ditto -x -k "$tmp/$zip_name" "$tmp/unpacked"
[ -d "$tmp/unpacked/$APP.app" ] || fail "the zip does not contain $APP.app."

pkill -x "$APP" 2>/dev/null && sleep 1 || true

# /Applications is writable for admin accounts; ask for sudo only if it is not.
sudo=""
[ -w /Applications ] || sudo="sudo"
$sudo rm -rf "$DEST"
$sudo ditto "$tmp/unpacked/$APP.app" "$DEST"

# Belt and braces: nothing above sets the flag, but an older copy might have.
$sudo xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$DEST" 2>/dev/null || true

say "installed $DEST"

if ! command -v gh >/dev/null 2>&1; then
  say "Diple borrows the token of the GitHub CLI — install it and run: gh auth login"
elif ! gh auth status >/dev/null 2>&1; then
  say "Diple borrows the token of the GitHub CLI — run: gh auth login"
fi

open "$DEST"
