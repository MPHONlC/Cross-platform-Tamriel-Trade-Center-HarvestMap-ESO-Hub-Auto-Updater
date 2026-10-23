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
source "$SRC/lib/secrets.sh"
source "$SRC/features/esohub/api.sh"
source "$SRC/features/esohub/cookie.sh"
source "$SRC/lib/format.sh"
esohub_open() { bash "$(dirname "${BASH_SOURCE[0]}")/fake_browser.sh" "$1" < /dev/null > /dev/null 2>&1 & }
esohub_code_wait() { [ "${EH_CODE_ENTER:-}" = 1 ] && return 0; sleep "$1"; return 1; }
ESOHUB_UA_WAIT="${EH_UA_WAIT:-2}"; ESOHUB_CODE_SECONDS="${EH_CODE_SECONDS:-6}"; ESOHUB_CODE_POLL="${EH_CODE_POLL:-1}"
case "${EH_LISTEN:-}" in "") ;; none) ESOHUB_LISTEN_TOOLS="" ;; *) ESOHUB_LISTEN_TOOLS="$EH_LISTEN" ;; esac
esohub_cf_can_ask() { [ "${EH_CF_ANSWER:-cannot}" != cannot ]; }
esohub_cf_read() {
    [ "${EH_CF_ANSWER:-}" = timeout ] && return 1
    if [ "${1:-}" = secret ]; then printf '%s' "${EH_CF_ANSWER%%|*}"; else echo >&2; printf '%s' "${EH_CF_ANSWER#*|}"; fi
}
ESOHUB_CF_CLEARANCE="${EH_CF_COOKIE:-}"; ESOHUB_CF_UA="${EH_CF_UA:-}"
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
        ui_echo() { printf '%b\n' "$1"; }
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
    dbsync)
        TARGET_DIR="$1"; DB_DIR="$1/Database"; DB_FILE="$DB_DIR/LTTC_Database.db"; TEMP_DIR_ROOT="$1/Temp"
        mkdir -p "$DB_DIR" "$TEMP_DIR_ROOT"; ENABLE_LOCAL_MODE=false
        ui_echo() { :; }; is_addon_active() { echo false; }
        source "$SRC/features/database/sync.sh"
        echo "database $(head -n 1 "$DB_FILE" | tr -d '\r') items=$(grep -vc '^#' "$DB_FILE")"
        echo "history $(head -n 1 "$DB_DIR/LTTC_History.db" 2>/dev/null | tr -d '\r') lines=$(grep -c '^HISTORY|' "$DB_DIR/LTTC_History.db" 2>/dev/null)"
        echo "temp_left=$(find "$TEMP_DIR_ROOT" -mindepth 1 | wc -l | tr -d ' ')" ;;
    backupprune) TARGET_DIR="$1"; prune_addon_backups; ls "$1/Backups/AddOns" | LC_ALL=C sort ;;
    selfinstall)
        TARGET_DIR="$1"; SCRIPT_NAME="$2"; LTTC_SELF="$3"; APP_VERSION="$4"; TEMP_DIR_ROOT="$(mktemp -d)"
        self_update_install "${5:-}" "${6:-}"; rc=$?
        echo "rc=$rc new=${SELF_NEW_VERSION:-}"
        for f in "$TARGET_DIR/$SCRIPT_NAME" "$LTTC_SELF"; do
            [ -f "$f" ] && echo "$(basename "$(dirname "$f")")/$(basename "$f"): $(grep -m1 -o 'APP_VERSION="[^"]*"' "$f")"
        done
        rm -rf "$TEMP_DIR_ROOT" ;;
    ghself)
        github_self_details; rc=$?
        echo "rc=$rc ver=$GH_SELF_VERSION url=$GH_SELF_URL" ;;
    ehparse2) esohub_v2_parse "$1" ;;
    ehparse1) esohub_v1_parse "$1" ;;
    ehlocal) echo "v=$(esohub_local_version "$1" "$2")" ;;
    ehnewer) if esohub_is_newer "$1" "$2"; then echo yes; else echo no; fi ;;
    ehfetch)
        TEMP_DIR_ROOT="$1"; EH_USER_TOKEN="${2:-}"; SYS_ID=test
        if esohub_fetch_addons; then echo "rc=0"; else echo "rc=1"; fi
        echo "api=$ESOHUB_API_USED blocked=$ESOHUB_BLOCKED fail=$ESOHUB_FAIL"
        printf '%s\n' "$ESOHUB_RECORDS" | grep -v '^$'
        echo "temp_left=$(find "$TEMP_DIR_ROOT" -mindepth 1 | wc -l | tr -d ' ')" ;;
    ehdownload)
        EH_USER_TOKEN=""; RAND_UA=""
        esohub_download "$1" "$2" "${3:-}"; rc=$?
        echo "rc=$rc file=$([ -f "$2" ] && echo yes || echo no)" ;;
    ehupload)
        SAVED_VAR_DIR="$5"; TEMP_DIR_ROOT="$6"; EH_USER_TOKEN="${7:-}"
        if esohub_upload "$1" "$2" "$3" "$4"; then echo "rc=0"; else echo "rc=1"; fi
        echo "temp_left=$(find "$TEMP_DIR_ROOT" -mindepth 1 | wc -l | tr -d ' ')" ;;
    ehtoken) SYS_ID=test; esohub_request_token "$1" "$2"; echo "token=$ESOHUB_TOKEN" ;;
    ehlogin) SYS_ID=test; esohub_request_token "$1" "$2"; echo "token=$ESOHUB_TOKEN blocked=$ESOHUB_LOGIN_BLOCKED fail=$ESOHUB_LOGIN_FAIL" ;;
    secret)
        for v in "$@"; do
            e=$(secret_encrypt "$v"); d=$(secret_decrypt "$e")
            case "$e" in ENC1:*) enc=ENC1 ;; *) enc=plain ;; esac
            if [ "$d" = "$v" ]; then echo "roundtrip ok enc=$enc [$v]"; else echo "roundtrip FAIL [$v] -> [$d]"; fi
        done ;;
    mergereport)
        work="$(mktemp -d)"; TEMP_DIR_ROOT="$work"
        ui_echo() { printf '%b\n' "$1"; }
        cp "$1" "$work/hist"
        history_merge_report "$work/hist" "$(cat "$2")"
        rm -rf "$work" ;;
    ehreload)
        ESOHUB_CF_CLEARANCE="$1"; ESOHUB_CF_UA="$2"; CONFIG_FILE="$3"
        esohub_reload_cf
        echo "cookie=$ESOHUB_CF_CLEARANCE ua=$ESOHUB_CF_UA" ;;
    ehuaprobe)
        esohub_browser_open "${1:-https://eso-hub.com/en}"
        echo "seen=[$ESOHUB_UA_SEEN] left=[$ESOHUB_UA_PIDS$ESOHUB_UA_DIR$ESOHUB_UA_URL]" ;;
    ehcodelogin)
        SYS_ID=test; CONFIG_CHANGED=false
        esohub_code_login
        echo "token=$ESOHUB_TOKEN user=$ESOHUB_LOGIN_USER fail=$ESOHUB_LOGIN_FAIL"
        echo "cf_saved=$([ -n "$ESOHUB_CF_CLEARANCE" ] && echo yes || echo no) ua=$ESOHUB_CF_UA changed=$CONFIG_CHANGED" ;;
    vdiff) for a in "$@"; do version_diff "${a%,*}" "${a#*,}" | sed 's/'$'\033''/<ESC>/g'; echo; done ;;
    cookie)
        OS_TYPE="$(uname -s)"; TEMP_DIR="${TMPDIR:-/tmp}"
        sub="$1"; shift
        case "$sub" in
            decrypt) esohub_cookie_decrypt "$1" "$2" && echo || echo "FAIL" ;;
            firefox) esohub_cookie_from_firefox "$1" && echo || echo "FAIL" ;;
            chromium) EH_TEST_PW="$2"; esohub_cookie_key() { printf '%s' "$EH_TEST_PW"; }; esohub_cookie_from_db "$1" "$3" && echo || echo "FAIL" ;;
            uaguess) ESOHUB_CF_UA=""; esohub_cookie_ua_guess "$1" && echo || echo "FAIL" ;;
        esac ;;
    ehcfclean)
        for a in "$@"; do
            if v=$(esohub_cf_clean_cookie "$a"); then echo "cookie [$a] -> [$v]"; else echo "cookie [$a] -> invalid"; fi
            if v=$(esohub_cf_clean_ua "$a"); then echo "ua [$a] -> [$v]"; else echo "ua [$a] -> invalid"; fi
        done ;;
    ehcycle)
        W="$1"; ADDON_DIR="$W/AddOns"; SAVED_VAR_DIR="$W/SavedVariables"; SNAP_DIR="$W/Snapshots"
        TEMP_DIR_ROOT="$W/Temp"; DB_DIR="$W/Database"; mkdir -p "$SNAP_DIR" "$TEMP_DIR_ROOT" "$DB_DIR"
        TEMP_SCAN_FILE="$TEMP_DIR_ROOT/scan.log"; LOG_FILE="$W/test.log"; : > "$TEMP_SCAN_FILE"
        CURRENT_TIME=1759300000; EH_LAST_DOWNLOAD="${3:-0}"; EH_LAST_SALE=0; EH_LAST_CHECK=0
        EH_LOC_5=0; EH_LOC_7=0; EH_LOC_9=0; EH_USER_TOKEN="${2:-}"
        ENABLE_LOCAL_MODE=false; ENABLE_DISPLAY=false; SILENT=false; SYS_ID=test; RAND_UA=""
        NOTIF_EH="Up-to-date"; FOUND_NEW_DATA=false; TEMP_DIR_USED=false; CONFIG_CHANGED=false
        ui_echo() { printf '%b\n' "$1"; }
        start_spinner() { printf 'spin: %s\n' "$1"; }
        stop_spinner() { printf 'done %s: %s\n' "$1" "$2"; }
        is_addon_active() { if [ -d "$ADDON_DIR/$1" ]; then echo true; else echo false; fi; }
        source "$SRC/features/esohub/update.sh"
        echo "notif=$NOTIF_EH"
        echo "cf_saved=$([ -n "$ESOHUB_CF_CLEARANCE" ] && echo yes || echo no) asked=$ESOHUB_CF_ASKED"
        echo "loc=$EH_LOC_5 $EH_LOC_7 $EH_LOC_9 last_download=$EH_LAST_DOWNLOAD"
        for a in EsoTradingHub LibEsoHubPrices EsoHubScanner; do echo "$a=$(esohub_local_version "$ADDON_DIR/$a" "$a")"; done
        echo "snapshots: $(ls "$SNAP_DIR" | LC_ALL=C sort | tr '\n' ' ')" ;;
    ttcver) echo "v=$(ttc_price_table_version "$1")" ;;
    ttccycle)
        W="$1"; ADDON_DIR="$W/AddOns"; SAVED_VAR_DIR="$W/SavedVariables"; SNAP_DIR="$W/Snapshots"
        TEMP_DIR_ROOT="$W/Temp"; DB_DIR="$W/Database"; mkdir -p "$SNAP_DIR" "$TEMP_DIR_ROOT" "$DB_DIR" "$SAVED_VAR_DIR"
        TEMP_SCAN_FILE="$TEMP_DIR_ROOT/scan.log"; LOG_FILE="$W/test.log"; : > "$TEMP_SCAN_FILE"
        CURRENT_TIME=1759300000; TTC_LAST_CHECK="$2"; AUTO_SRV="$3"; ENABLE_LOCAL_MODE="${4:-false}"
        HAS_TTC=true; TTC_LAST_DOWNLOAD=0; TTC_LAST_SALE=0
        ENABLE_DISPLAY=false; SILENT=false; TTC_USER_AGENT=test; TTC_DOMAIN=us.tamrieltradecentre.com
        NOTIF_TTC="Up-to-date"; FOUND_NEW_DATA=false; TEMP_DIR_USED=false; CONFIG_CHANGED=false
        ui_echo() { printf '%b\n' "$1"; }
        source "$SRC/features/ttc/update.sh"
        echo "notif=$NOTIF_TTC last_check=$TTC_LAST_CHECK changed=$CONFIG_CHANGED" ;;
    aomslots)
        eval "$(sed -n '/^_d()/,/^}/p' "$SRC/lib/system.sh")"; source "$SRC/features/aom/sync.sh"
        for t in "$@"; do slots="$(aom_slots "$t")"; echo "$t -> $slots wait=$(aom_wait_text $(( ${slots#* } - t )))"; done ;;
    aommerge)
        eval "$(sed -n '/^_d()/,/^}/p' "$SRC/lib/system.sh")"; source "$SRC/features/aom/sync.sh"
        work="$(mktemp -d)"; aom_merge_table "$1" "$2" "$work/out" "$work/stats"; cat "$work/out"; cat "$work/stats"; rm -rf "$work" ;;
    aomask)
        eval "$(sed -n '/^_d()/,/^}/p' "$SRC/lib/system.sh")"; source "$SRC/features/aom/sync.sh"
        ADDON_DIR="$1"
        if aom_installed; then echo "installed=yes"; else echo "installed=no"; fi
        aom_question
        for a in "" 1 2 x; do aom_set_answer "$a"; echo "answer '$a' -> $AOM_DATA_UPDATES"; done ;;
    aomcycle)
        eval "$(sed -n '/^_d()/,/^}/p' "$SRC/lib/system.sh")"; source "$SRC/features/aom/sync.sh"
        W="$1"; ADDON_DIR="$W/AddOns"; TEMP_DIR_ROOT="$W/Temp"; mkdir -p "$TEMP_DIR_ROOT"
        CURRENT_TIME="$2"; AOM_LAST_SYNC="$3"; CONFIG_CHANGED=false; NOTIF_AOM=""; SILENT=false
        AOM_DATA_UPDATES="${4:-true}"; [ "$AOM_DATA_UPDATES" = unset ] && AOM_DATA_UPDATES=""
        AOM_TEST_ANSWER="${5:-cannot}"; AOM_TEST_CYCLES="${6:-1}"
        ui_echo() { printf '%b\n' "$1"; }
        start_spinner() { printf 'spin: %s\n' "$1"; }
        stop_spinner() { printf 'done %s: %s\n' "$1" "$2"; }
        aom_can_ask() { [ "$AOM_TEST_ANSWER" != cannot ]; }
        aom_read_answer() { case "$AOM_TEST_ANSWER" in timeout) return 1 ;; enter) printf '' ;; *) printf '%s' "$AOM_TEST_ANSWER" ;; esac; }
        cycle=0
        while [ "$cycle" -lt "$AOM_TEST_CYCLES" ]; do run_aom_data_sync; cycle=$((cycle + 1)); done
        echo "aom_data_updates=$AOM_DATA_UPDATES asked=$AOM_ASKED"
        echo "notif=$NOTIF_AOM last_sync=$AOM_LAST_SYNC changed=$CONFIG_CHANGED temp_left=$(ls -A "$TEMP_DIR_ROOT" | wc -l | tr -d ' ')"
        for f in $AOM_TABLES; do
            [ -f "$ADDON_DIR/APH-OnManager/DATA/$f" ] || continue
            echo "== $f"; cat "$ADDON_DIR/APH-OnManager/DATA/$f"
        done ;;
    *) echo "linux.sh: unknown command $cmd" >&2; exit 2 ;;
esac
wait
