#!/bin/bash
# Installs (or updates) Voyager Bar from the latest GitHub release.
#
#   curl -fsSL https://raw.githubusercontent.com/FeN1x1/voyager-bar/main/install.sh | bash
#
# Options (environment):  VERSION=v1.0.0   INSTALL_DIR=~/Applications
set -euo pipefail

REPO="FeN1x1/voyager-bar"
APP="Voyager Bar.app"
DEST="${INSTALL_DIR:-/Applications}"

say() { printf '\033[1;33m›\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "Voyager Bar runs on macOS only."
major="$(sw_vers -productVersion | cut -d. -f1)"
(( major >= 13 )) || die "Voyager Bar needs macOS 13 Ventura or newer (found $(sw_vers -productVersion))."

if [[ -n "${VERSION:-}" ]]; then
    api="https://api.github.com/repos/$REPO/releases/tags/$VERSION"
else
    api="https://api.github.com/repos/$REPO/releases/latest"
fi
say "Looking up the ${VERSION:-latest} release…"
json="$(curl -fsSL "$api")" || die "Could not reach GitHub."
zip_url="$(printf '%s' "$json" | grep -o '"browser_download_url": *"[^"]*\.zip"' | head -1 | sed -E 's/.*"(https[^"]+)"/\1/')"
sums_url="$(printf '%s' "$json" | grep -o '"browser_download_url": *"[^"]*SHA256SUMS[^"]*"' | head -1 | sed -E 's/.*"(https[^"]+)"/\1/')"
tag="$(printf '%s' "$json" | grep -o '"tag_name": *"[^"]*"' | head -1 | sed -E 's/.*"([^"]+)"$/\1/')"
[[ -n "$zip_url" ]] || die "No downloadable build found in that release."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
say "Downloading Voyager Bar $tag…"
curl -fL --progress-bar "$zip_url" -o "$tmp/VoyagerBar.zip"

if [[ -n "$sums_url" ]]; then
    curl -fsSL "$sums_url" -o "$tmp/SHA256SUMS.txt"
    expected="$(grep '\.zip' "$tmp/SHA256SUMS.txt" | awk '{print $1}' | head -1)"
    actual="$(shasum -a 256 "$tmp/VoyagerBar.zip" | awk '{print $1}')"
    [[ -z "$expected" || "$expected" == "$actual" ]] || die "Checksum mismatch — download corrupted, try again."
    say "Checksum verified."
fi

ditto -x -k "$tmp/VoyagerBar.zip" "$tmp/unpacked"
[[ -d "$tmp/unpacked/$APP" ]] || die "The archive does not contain $APP."

pkill -x VoyagerBar 2>/dev/null || true
sudo_cmd=""
if [[ ! -w "$DEST" ]]; then
    say "Administrator rights are needed to write to $DEST."
    sudo_cmd="sudo"
fi
$sudo_cmd mkdir -p "$DEST"
$sudo_cmd rm -rf "$DEST/$APP"
$sudo_cmd ditto "$tmp/unpacked/$APP" "$DEST/$APP"
# Not notarized: clear the download quarantine so Gatekeeper lets it start.
$sudo_cmd xattr -dr com.apple.quarantine "$DEST/$APP" 2>/dev/null || true

say "Installed to $DEST/$APP"
open "$DEST/$APP"
printf '\033[1;32m✓\033[0m Voyager Bar is running — look for the little Voyager in your menu bar.\n'
