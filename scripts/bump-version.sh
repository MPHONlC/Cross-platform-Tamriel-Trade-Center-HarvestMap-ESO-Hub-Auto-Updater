#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEW="${1:-$(TZ=UTC-8 date +%Y.%m.%d.%H.%M)}"
if ! [[ "$NEW" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]{2}\.[0-9]{2}$ ]]; then
    echo "bump-version: '$NEW' is not YYYY.MM.DD.HH.mm" >&2
    exit 1
fi
OLD="$(tr -d ' \r\n' < "$ROOT/VERSION" 2>/dev/null || true)"

printf '%s\n' "$NEW" > "$ROOT/VERSION"
perl -pi -e 's/APP_VERSION="[^"]*"/APP_VERSION="'"$NEW"'"/' "$ROOT/src/linux/lib/paths.sh" "$ROOT/src/macos/lib/paths.sh"
perl -pi -e 's/^\$APP_VERSION = "[^"]*"/\$APP_VERSION = "'"$NEW"'"/' "$ROOT/src/windows/lib/constants.ps1"
perl -pi -e 's/(Tamriel Trade Center Auto-Updater v)\S+/${1}'"$NEW"'/' "$ROOT/src/linux/main.sh" "$ROOT/src/macos/main.sh" "$ROOT/src/windows/launcher.bat"
if [ -n "$OLD" ] && [ -f "$ROOT/CHANGELOG.md" ]; then
    SHORT="$(echo "$NEW" | awk -F. '{ printf "%s%s%s%s", substr($1, 3), $2, $3, $4 }')"
    perl -0pi -e 's/^Version: \Q'"$OLD"'\E(?: \(\S+\))?[ \t]*$/Version: '"$NEW"' ('"$SHORT"')/m' "$ROOT/CHANGELOG.md"
fi
echo "bump-version: ${OLD:-none} -> $NEW"
