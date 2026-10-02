#!/bin/bash
set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/${LTTC_PLATFORM:-linux}" && pwd)"
DB_FILE="$1"; shift
cmd="$1"; shift

write_ttc_log() { :; }
start_spinner() { :; }
stop_spinner() { :; }
source "$SRC/data/item_quality.sh"
source "$SRC/data/kiosk_locations.sh"
source "$SRC/features/ttc/extract.sh"
source "$SRC/features/ttc/upload.sh"
source "$SRC/features/esohub/extract.sh"
source "$SRC/features/database/merge.sh"
source "$SRC/features/database/prune.sh"
source "$SRC/features/database/browser.sh"
source "$SRC/lib/esoui.sh"
source "$SRC/features/addons/updater.sh"
source "$SRC/features/self/update.sh"

canon_extract() {
    local out; out="$(cat)"
    printf '%s\n' "$out" | grep -vE '^(MAX_TIME:|DB_UPDATE\||DB_GUILD\||DB_KIOSK\||HISTORY\|)' | grep -v '^$' | sed 's/^/L /'
    printf '%s\n' "$out" | grep '^HISTORY|' | sed 's/^/H /'
    printf '%s\n' "$out" | grep '^MAX_TIME:' | sed 's/^MAX_TIME:/M /'
    printf '%s\n' "$out" | grep -E '^DB_(UPDATE|GUILD|KIOSK)\|' | LC_ALL=C sort | sed 's/^/D /'
}

case "$cmd" in
    ttc) ttc_extract "$1" "$2" "$3" | canon_extract ;;
    ttcupload) ttc_upload_parse "$1" "$2" "$3" "$4" | LC_ALL=C sort ;;
    esohub) esohub_extract "$1" "$2" "$3" | canon_extract ;;
    merge) history_merge "$1" "$(cat "$2")" ;;
    tplhist)
        work="$(mktemp -d)"; [ "$1" != "-" ] && cp "$1" "$work/LTTC_History.db"
        template_history_apply "$work/LTTC_History.db" "$2" "$3"
        cat "$work/LTTC_History.db"; rm -rf "$work" ;;
    prune)
        work="$(mktemp -d)"; mkdir -p "$work/db" "$work/tmp"
        cp "$1" "$work/db/LTTC_History.db"
        DB_DIR="$work/db" TEMP_DIR_ROOT="$work/tmp" CURRENT_TIME="$2" LOG_MODE=simple LOG_FILE=/dev/null prune_history
        cat "$work/db/LTTC_History.db"; rm -rf "$work" ;;
    dbapply) merge_db_updates "$(cat "$1")"; cat "$DB_FILE" ;;
    listing)
        cutoff_time="$6"; src_lc="$4"; user_lc="$5"
        browser_history_rows "$1" "$3" "$2" ;;
    scan) browser_scan_rows "$1" "$3" "$2" ;;
    top) cutoff_time="$5"; src_lc="$3"; user_lc="$4"; browser_top_lines "$2" "$1" ;;
    price) cutoff_time="$5"; src_lc="$3"; user_lc="$4"; browser_price_lines "$2" "$1" ;;
    vnewer) if version_newer "$1" "$2"; then echo yes; else echo no; fi ;;
    localist) addon_local_list "$1" | LC_ALL=C sort ;;
    plan) addon_local_list "$1" > "$DB_FILE.local"; addon_update_plan "$DB_FILE.local" "$2" "${3:-}"; rm -f "$DB_FILE.local" ;;
    install)
        ADDON_DIR="$1"; TARGET_DIR="$2"; TEMP_DIR_ROOT="$(mktemp -d)"
        if install_addon_zip "$3"; then echo "installed:$ADDON_INSTALLED"; else echo "installed: none"; fi
        rm -rf "$TEMP_DIR_ROOT" ;;
    backupprune) TARGET_DIR="$1"; prune_addon_backups; ls "$1/Backups/AddOns" | LC_ALL=C sort ;;
    selfinstall)
        TARGET_DIR="$1"; SCRIPT_NAME="$2"; LTTC_SELF="$3"; APP_VERSION="$4"; TEMP_DIR_ROOT="$(mktemp -d)"
        self_update_install; rc=$?
        echo "rc=$rc new=${SELF_NEW_VERSION:-}"
        for f in "$TARGET_DIR/$SCRIPT_NAME" "$LTTC_SELF"; do
            [ -f "$f" ] && echo "$(basename "$(dirname "$f")")/$(basename "$f"): $(grep -m1 -o 'APP_VERSION="[^"]*"' "$f")"
        done
        rm -rf "$TEMP_DIR_ROOT" ;;
    *) echo "linux.sh: unknown command $cmd" >&2; exit 2 ;;
esac
