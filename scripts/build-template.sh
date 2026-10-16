#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${1:--}"; OUT="${2:--}"; VER="${3:-}"
[ "$SRC_DIR" = "-" ] && SRC_DIR="$HOME/Documents/Linux_Tamriel_Trade_Center/Database"
[ "$OUT" = "-" ] && OUT="$ROOT/../../#Documentations/Cross-platform-Tamriel-Trade-Center-HarvestMap-ESO-Hub-Auto-Updater/Auto-Updater Database Template"
[ -n "$VER" ] || VER="$(TZ=UTC-8 date +%Y.%m.%d.%H.%M)"
if ! [[ "$VER" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]{2}\.[0-9]{2}$ ]]; then
    echo "build-template: '$VER' is not YYYY.MM.DD.HH.mm" >&2; exit 1
fi
[ -s "$SRC_DIR/LTTC_Database.db" ] || { echo "build-template: no LTTC_Database.db in $SRC_DIR" >&2; exit 1; }
mkdir -p "$OUT"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

touch "$OUT/LTTC_Database.db"
LC_ALL=C awk -F'|' '
    /^#DATABASE VERSION:/ { next }
    {
        sub(/\r$/, ""); if ($0 == "") next
        if ($1 == "GUILD") key = "GUILD_"$2
        else if ($1 == "KIOSK") key = "KIOSK_"$2
        else if ($1 ~ /^[0-9]+$/) key = "ITEM_"$1
        else key = $0
        if (!seen[key]++) print
    }' "$SRC_DIR/LTTC_Database.db" "$OUT/LTTC_Database.db" | LC_ALL=C sort -t'|' -k1,1 -k7,7 -k6,6 > "$TMP/db"
{ echo "#DATABASE VERSION: $VER"; cat "$TMP/db"; } > "$OUT/LTTC_Database.db"

export DB_FILE="$OUT/LTTC_Database.db"
source "$ROOT/src/linux/features/database/merge.sh"
CUTOFF=$(( $(date +%s) - 2592000 ))
recent() { [ -f "$1" ] && LC_ALL=C awk -F'|' -v c="$CUTOFF" '$1 == "HISTORY" && $2 + 0 >= c { sub(/\r$/, ""); print }' "$1" || true; }
recent "$OUT/LTTC_History.db" > "$TMP/base"
{ echo "#HISTORY VERSION: $VER"; history_merge "$TMP/base" "$(recent "$SRC_DIR/LTTC_History.db")" max | grep '^HISTORY|'; } > "$TMP/hist"
mv -f "$TMP/hist" "$OUT/LTTC_History.db"

echo "build-template: $VER, $(grep -c '|' "$OUT/LTTC_Database.db") database lines, $(grep -c '^HISTORY|' "$OUT/LTTC_History.db") history entries -> $OUT"
