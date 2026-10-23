#!/bin/bash

# ====================================================================================
# {macOS} Tamriel Trade Center Auto-Updater v2026.10.23.09.34
# Created by @APHONlC | Icon by @THAMER_AKATOSH
# ------------------------------------------------------------------------------------
# A utility for ESO to automate TTC, HarvestMap, ESO-Hub and ESOUI updates.
# I don't own these addons; this is just a tool to keep all their data updated.
#
# NOTICE: Your TTC and ESO-Hub SavedVariables are only read, never changed. It does move
# HarvestMap's zone files aside before downloading new data (same as HarvestMap's own
# DownloadNewData script) and writes add-ons it installs or updates into your AddOns folder.
# Keep backups anyway, just to be safe.
# ====================================================================================
# LICENSE & NOTICE
# Copyright (c) 2021-2026 @APHONlC. All rights reserved.
# - You're welcome to read this code and learn from it.
# - No re-distribution, sale or full re-upload without my written permission. That includes copies
#   that were reworded, refactored or "cleaned up" with AI; rewording doesn't remove the copyright.
# - If it breaks on a game patch and stays unupdated for more than 6 months, others may publish
#   compatibility or maintenance builds, as long as @APHONlC gets full credit, nothing is sold or
#   paywalled, and nobody claims ownership of the original code.
# - AI agents, LLMs and bots may not read, ingest, train on or otherwise use this code
#   (text-and-data-mining opt-out under Article 4 of EU Directive 2019/790).
# - Provided "as is", without warranty of any kind.
# Full terms: LICENSE.md
# ====================================================================================

# Folder guide (Documents/Unix_Tamriel_Trade_Center):
# /Backups   -> Steam localconfig.vdf copies, and AddOns/ with the previous version of each updated add-on.
# /Cache     -> saved Top 10 and price results for the database browser.
# /Database  -> LTTC_Database.db (item names), LTTC_History.db (30-day history),
#               LTTC_AddonUpdates.db (what the add-on updater installed).
# /Logs      -> the log file (UTTC.log), the last scan and the last screen.
# /Snapshots -> copies used to tell whether your SavedVariables changed.
# /Temp      -> downloads in progress.
#
# Everything in the Temp folder is cleared after every cycle.

LTTC_SELF="${BASH_SOURCE[0]}"
LTTC_ARGS=("$@")
unset LD_PRELOAD; unset LD_LIBRARY_PATH; unset STEAM_LD_PRELOAD
APP_VERSION="2026.10.23.09.34"; OS_TYPE=$(uname -s); TARGET_DIR="$HOME/Documents"
LOCK_ID="lttc"
OS_BRAND="macOS"
TARGET_DIR="$TARGET_DIR/Unix_Tamriel_Trade_Center"
SYS_ID="mac"

DB_DIR="$TARGET_DIR/Database"; LOG_DIR="$TARGET_DIR/Logs"
SNAP_DIR="$TARGET_DIR/Snapshots"; TEMP_DIR_ROOT="$TARGET_DIR/Temp"
mkdir -p "$DB_DIR" "$LOG_DIR" "$SNAP_DIR" "$TEMP_DIR_ROOT"

[ -f "$TARGET_DIR/LTTC_Database.db" ] && mv "$TARGET_DIR/LTTC_Database.db" "$DB_DIR/" 2>/dev/null
[ -f "$TARGET_DIR/LTTC_History.db" ] && mv "$TARGET_DIR/LTTC_History.db" "$DB_DIR/" 2>/dev/null
[ -f "$TARGET_DIR/UTTC.log" ] && mv "$TARGET_DIR/UTTC.log" "$LOG_DIR/" 2>/dev/null
[ -f "$TARGET_DIR/LTTC_LastScan.log" ] && mv "$TARGET_DIR/LTTC_LastScan.log" "$LOG_DIR/" 2>/dev/null
[ -f "$TARGET_DIR/LTTC_Display_State.log" ] && mv "$TARGET_DIR/LTTC_Display_State.log" "$LOG_DIR/" 2>/dev/null

for snap in "$TARGET_DIR"/*_snapshot.lua; do
    [ -f "$snap" ] && mv "$snap" "$SNAP_DIR/" 2>/dev/null
done
rm -f "$TARGET_DIR"/*.tmp "$TARGET_DIR"/*.out 2>/dev/null

CONFIG_FILE="$TARGET_DIR/lttc_updater.conf"; DB_FILE="$DB_DIR/LTTC_Database.db"
LOG_FILE="$LOG_DIR/UTTC.log"
LAST_SCAN_FILE="$LOG_DIR/LTTC_LastScan.log"; UI_STATE_FILE="$LOG_DIR/LTTC_Display_State.log"
APP_TITLE="$OS_BRAND Tamriel Trade Center v$APP_VERSION"
SCRIPT_NAME="${OS_BRAND}_Tamriel_Trade_Center.sh"
ESOUI_API="${LTTC_ESOUI_API:-https://api.mmoui.com}"
ESOUI_UA="Mozilla/5.0"
ESOUI_SELF_ID="3249"
ESOUI_DB_ID="4428"

md5_of() {
    md5 -q "$1" 2>/dev/null
}

version_newer() {
    awk -v a="$1" -v b="$2" 'BEGIN {
        sub(/^[vV]/, "", a); sub(/^[vV]/, "", b)
        na = split(a, x, /[^0-9]+/); nb = split(b, y, /[^0-9]+/)
        n = (na > nb) ? na : nb
        for (i = 1; i <= n; i++) {
            p = x[i] + 0; q = y[i] + 0
            if (p > q) exit 0
            if (p < q) exit 1
        }
        exit 1
    }'
}

json_value() {
    printf '%s' "$1" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -n 1 | cut -d'"' -f4 | sed 's/\\\//\//g'
}

esoui_details() {
    ESOUI_VERSION=""; ESOUI_DOWNLOAD=""; ESOUI_MD5=""
    local resp
    resp=$(curl -s -f -m 30 -A "$ESOUI_UA" "$ESOUI_API/v3/game/ESO/filedetails/$1.json" 2>/dev/null) || return 1
    ESOUI_VERSION=$(json_value "$resp" "UIVersion")
    ESOUI_DOWNLOAD=$(json_value "$resp" "UIDownload")
    ESOUI_MD5=$(json_value "$resp" "UIMD5" | tr 'A-F' 'a-f')
    [ -n "$ESOUI_VERSION" ] && [ -n "$ESOUI_DOWNLOAD" ]
}

esoui_download() {
    local id="$1" dest="$2"
    esoui_details "$id" || return 1
    rm -f "$dest"
    curl -s -f -L -m 180 -A "$ESOUI_UA" -o "$dest" "$ESOUI_DOWNLOAD" </dev/null || { rm -f "$dest"; return 1; }
    if [ -n "$ESOUI_MD5" ] && [ "$(md5_of "$dest")" != "$ESOUI_MD5" ]; then
        write_ttc_log "WARN" "ESOUI file $id failed its checksum, discarded."
        rm -f "$dest"; return 2
    fi
    if ! unzip -t "$dest" >/dev/null 2>&1; then
        rm -f "$dest"; return 2
    fi
    return 0
}

kill_zombie_updater() {
    trap - EXIT SIGHUP SIGINT SIGTERM
    if [ "$SETUP_COMPLETE" != "true" ] && [ "$HAS_ARGS" = false ]; then
        write_ttc_log "WARN" "User aborted or closed script before completing setup."
    fi
    write_ttc_log "INFO" "Script execution terminated/closed by user or system."
    release_instance_lock 2>/dev/null
    pkill -P $$ 2>/dev/null
    exit 0
}
trap kill_zombie_updater EXIT SIGHUP SIGINT SIGTERM
CURRENT_DIR="$(cd "$(dirname "$LTTC_SELF")" &> /dev/null && pwd)"

IS_BACKGROUND=false
for arg in "$@"; do
    if [ "$arg" = "--silent" ] || [ "$arg" = "--task" ] || [ "$arg" = "--steam" ]; then
        IS_BACKGROUND=true
    fi
done

manage_old_pid() {
    local old_pid=$1
    if [ "$IS_BACKGROUND" = true ]; then exit 0; fi
    echo -e "\e[0;33m[!] Another updater instance (PID: ${old_pid:-Unknown}) is running.\e[0m"
    read -t 10 -p "Do you want to terminate the existing process and continue? (y/n): " k_choice
    kill_choice="${k_choice:-y}"
    echo ""
    if [[ "$kill_choice" =~ ^[Yy]$ ]]; then
        echo -e "\e[0;31mTerminating old process...\e[0m"
        if [ -n "$old_pid" ] && [ "$old_pid" != "Unknown" ]; then
            kill -9 "$old_pid" 2>/dev/null || true
        fi
        for p in $(pgrep -f "$SCRIPT_NAME"); do
            if [ "$p" != "$$" ] && [ "$p" != "$PPID" ]; then
                kill -9 "$p" 2>/dev/null || true
            fi
        done
        sleep 1; return 0
    else
        echo -e "\e[0;32mKeeping the existing process safe. Exiting new instance.\e[0m"
        exit 1
    fi
}

LOG_MODE="simple"
write_ttc_log() {
    local level="$1"; local message="$2"
    if [ "$level" == "ITEM" ] && [ "$LOG_MODE" != "detailed" ]; then return; fi
    clean_msg=$(printf '%s\n' "$message" | sed "s/$(printf '\033')\[[0-9;]*m//g")
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $clean_msg" >> "$LOG_FILE"
}

missing_tools=""
for tool in curl unzip awk sed grep find; do
    command -v "$tool" >/dev/null 2>&1 || missing_tools="$missing_tools $tool"
done
if [ -n "$missing_tools" ]; then
    echo -e "\e[0;31m[!] This updater needs these tools, which are not installed:$missing_tools\e[0m"
    echo -e "\e[0;33m    Install them with your system's package manager, then run the updater again.\e[0m"
    write_ttc_log "ERROR" "Missing required tools:$missing_tools"
    exit 1
fi
SPINNER_PID=0
SPIN_START=0
SPIN_MSG_FILE="$TEMP_DIR_ROOT/lttc_spin.msg"

start_spinner() {
    local msg="$1"
    echo "$msg" > "$SPIN_MSG_FILE"
    SPIN_START=$(date +%s)
    if [ "$SILENT" = true ]; then return; fi
    tput civis 2>/dev/null
    (
        local W=8 pos=0 frame=0 i bar pac cur_msg
        while :; do
            read -r cur_msg < "$SPIN_MSG_FILE" 2>/dev/null
            [ $((frame % 2)) -eq 0 ] && pac="C" || pac="c"
            bar=""; i=0
            while [ "$i" -lt "$W" ]; do
                if [ "$i" -lt "$pos" ]; then bar="$bar--"
                elif [ "$i" -eq "$pos" ]; then bar="$bar \e[33m$pac\e[0m"
                else bar="$bar \e[90mo\e[0m"; fi
                i=$((i + 1))
            done
            printf "\r\033[K \e[33m[\e[0m%b\e[33m]\e[0m %s" "$bar" "${cur_msg:-$msg}"
            sleep 0.12
            frame=$((frame + 1)); pos=$((pos + 1))
            [ "$pos" -ge "$W" ] && pos=0
        done
    ) &
    SPINNER_PID=$!
}

update_spinner() {
    echo "$1" > "$SPIN_MSG_FILE"
}

stop_spinner() {
    local ok="$1"; local msg="$2"
    local el=$(( $(date +%s) - SPIN_START ))
    if [ "$SILENT" = false ] && [ "$SPINNER_PID" != "0" ]; then
        kill "$SPINNER_PID" 2>/dev/null; wait "$SPINNER_PID" 2>/dev/null
        tput cnorm 2>/dev/null
        local out_str=""
        if [ "$ok" = "0" ]; then out_str=" \e[92m[\0342\0234\0223]\e[0m $msg (${el}s)"
        else out_str=" \e[31m[\0342\0234\0227]\e[0m $msg (${el}s)"; fi
        printf "\r\033[K%b\n" "$out_str"
        echo -e "$out_str" >> "$UI_STATE_FILE"
        SPINNER_PID=0
    fi
    write_ttc_log "INFO" "Task '$msg' finished in ${el}s (Status: $ok)."
}

LOCK_DIR="$TEMP_DIR_ROOT/ttc_updater_dir_$LOCK_ID"
release_instance_lock() {
    if [ "$(cat "$LOCK_DIR/pid" 2>/dev/null)" = "$$" ]; then rm -rf "$LOCK_DIR"; fi
}
if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo $$ > "$LOCK_DIR/pid"
else
    OLD_PID=$(cat "$LOCK_DIR/pid" 2>/dev/null)
    if [ "$OLD_PID" != "$$" ]; then manage_old_pid "$OLD_PID"; fi
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR" 2>/dev/null
    echo $$ > "$LOCK_DIR/pid"
fi
mkdir -p "$TARGET_DIR"; CONFIG_FILE="$TARGET_DIR/lttc_updater.conf"
touch "$DB_FILE" 2>/dev/null; touch "$LOG_FILE" 2>/dev/null
touch "$LAST_SCAN_FILE" 2>/dev/null; touch "$UI_STATE_FILE" 2>/dev/null

merge_db_updates() {
    local updates="$1"
    if [ -n "$updates" ]; then
        local header=$(grep "^#DATABASE VERSION" "$DB_FILE" 2>/dev/null)
        echo "$updates" | awk -F'|' -v db="$DB_FILE" '
        BEGIN {
            while ((getline < db) > 0) {
                if ($1 == "GUILD") { lines["GUILD_"$2] = $0 }
                else if ($1 == "KIOSK") { lines["KIOSK_"$2] = $0 }
                else if ($1 ~ /^[0-9]+$/) { lines["ITEM_"$1] = $0 }
            }
            close(db)
        }
        {
            if ($1 == "DB_UPDATE") {
                id = $2; val = $2
                for(i=3; i<=NF; i++) val = val "|" $i
                lines["ITEM_"id] = val
            } else if ($1 == "DB_GUILD") {
                gname = $2; gid = $3; lines["GUILD_"gname] = "GUILD|" gname "|" gid
            } else if ($1 == "DB_KIOSK") {
                lines["KIOSK_"$2] = "KIOSK|" $2 "|" $3 "|" $4 "|" $5
            }
        }
        END { for (k in lines) { print lines[k] } }' > "$DB_FILE.tmp"
        LC_ALL=C sort -t'|' -k1,1 -k7,7 -k6,6 "$DB_FILE.tmp" -o "$DB_FILE.tmp" 2>/dev/null
        if [ -n "$header" ]; then
            echo "$header" > "$DB_FILE"
            cat "$DB_FILE.tmp" >> "$DB_FILE"
        else
            mv "$DB_FILE.tmp" "$DB_FILE"
        fi
        rm -f "$DB_FILE.tmp" 2>/dev/null
    fi
}

history_merge() {
    awk -F'|' -v OFS='|' -v db="$DB_FILE" -v scan_mode="${3:-add}" '
    BEGIN {
        uid_count = 0
        while ((getline line < db) > 0) {
            split(line, p, "|")
            if (p[1] ~ /^[0-9]+$/) {
                q_num = p[2] + 0
                c = "\033[0m"
                if(q_num==0) c="\033[90m"
                else if(q_num==1) c="\033[97m"
                else if(q_num==2) c="\033[32m"
                else if(q_num==3) c="\033[36m"
                else if(q_num==4) c="\033[35m"
                else if(q_num==5) c="\033[33m"
                else if(q_num==6) c="\033[38;5;214m"
                db_colors[p[1]] = c
            }
        }
        close(db)
    }
    {
        sub(/\r$/, "")
        if ($1 != "HISTORY") {
            if ($0 != "") print $0
            next
        }

        if ($NF ~ /^[0-9]+$/) {
            scans = $NF + 0
            src = $(NF-1)
        } else {
            scans = 1
            src = $NF
        }
        if (src ~ /^(Unknown|\[Unknown\])$/ || src == "") src = "TTC"

        kiosk = $11
        if (index(kiosk, "|") > 0) {
            split(kiosk, kp, "|")
            kiosk = kp[1]
        }

        uid = $6"|"$3"|"$4"|"$5"|"src
        ts = $2 + 0
        buyer = $8; seller = $9; guild = $10

        color = db_colors[$6]
        if (color == "") {
            color = $12
            if (color !~ /^\033\[/) color = "\033[0m"
        }

        if (!(uid in seen)) {
            seen[uid] = 1
            uids[++uid_count] = uid
            db_ts[uid] = ts
            db_name[uid] = $7
            db_buyer[uid] = buyer
            db_seller[uid] = seller
            db_guild[uid] = guild
            db_kiosk[uid] = kiosk
            db_color[uid] = color
            db_scans[uid] = scans
        } else {
            if (ts > db_ts[uid]) db_ts[uid] = ts

            if (buyer != "" && index(db_buyer[uid], buyer) == 0) {
                db_buyer[uid] = (db_buyer[uid]=="") ? buyer : db_buyer[uid]", "buyer
            }
            if (seller != "" && index(db_seller[uid], seller) == 0) {
                db_seller[uid] = (db_seller[uid]=="") ? seller : db_seller[uid]", "seller
            }
            if (guild != "" && index(db_guild[uid], guild) == 0) {
                db_guild[uid] = (db_guild[uid]=="") ? guild : db_guild[uid]", "guild
            }
            if (kiosk != "" && index(db_kiosk[uid], kiosk) == 0) {
                db_kiosk[uid] = (db_kiosk[uid]=="") ? kiosk : db_kiosk[uid]", "kiosk
            }
            if (scan_mode == "max") { if (scans > db_scans[uid]) db_scans[uid] = scans }
            else db_scans[uid] += scans
        }
    }
    END {
        for (i = 1; i <= uid_count; i++) {
            u = uids[i]
            split(u, p, "|")
            print "HISTORY", db_ts[u], p[2], p[3], p[4], p[1], db_name[u], \
                  db_buyer[u], db_seller[u], db_guild[u], db_kiosk[u], \
                  db_color[u], p[5], db_scans[u]
        }
    }
    ' "$1" <(printf '%s\n' "$2")
}

history_merge_report() {
    local hf="$1" incoming="$2" before inc after added updated szb sza
    local tmp="$TEMP_DIR_ROOT/LTTC_History_Merged.tmp" intmp="$TEMP_DIR_ROOT/hm_incoming.tmp"
    touch "$hf" 2>/dev/null
    before=$(count_history_uids "$hf")
    szb=$(wc -c < "$hf" 2>/dev/null | tr -d ' '); szb=${szb:-0}
    printf '%s\n' "$incoming" > "$intmp"
    inc=$(count_history_uids "$intmp"); rm -f "$intmp"
    history_merge "$hf" "$incoming" > "$tmp" 2>/dev/null
    [ -s "$tmp" ] && mv "$tmp" "$hf"
    after=$(count_history_uids "$hf")
    sza=$(wc -c < "$hf" 2>/dev/null | tr -d ' '); sza=${sza:-0}
    added=$((after - before)); [ "$added" -lt 0 ] && added=0
    updated=$((inc - added)); [ "$updated" -lt 0 ] && updated=0
    if [ "$inc" -gt 0 ]; then
        ui_echo "\t\e[90mTrade history: \e[92m$added new\e[90m, $updated updated ($(size_human "$szb") -> $(size_human "$sza")).\e[0m"
    fi
}

template_history_apply() {
    local hist="$1" tpl="$2" ver="$3" tmp="$1.template.tmp"
    [ -f "$hist" ] || : > "$hist"
    {
        echo "#HISTORY VERSION: $ver"
        history_merge <(grep -v '^#HISTORY VERSION:' "$hist" | tr -d '\r') "$(grep '^HISTORY|' "$tpl" | tr -d '\r')" max
    } > "$tmp" && mv -f "$tmp" "$hist"
}
find_eso_paths() {
    declare -a game_paths=()
    game_paths=(
        "$HOME/Library/Application Support/Steam/steamapps/common/Zenimax Online/The Elder Scrolls Online/game/client"
        "$HOME/Library/Application Support/Steam/steamapps/common/Zenimax Online/The Elder Scrolls Online"
        "/Applications/Zenimax Online/The Elder Scrolls Online/game/client"
    )
    for p in "${game_paths[@]}"; do
        if [ -f "$p/eso.app/Contents/MacOS/eso" ] || [ -d "$p/eso.app" ]; then
            echo "$p"; return 0
        fi
    done
    echo ""
}

is_eso_running() {
    if pgrep -i -f 'eso\.app|steam_app_306130|Bethesda\.net_Launcher' > /dev/null 2>&1; then
        return 0
    fi
    return 1
}

secret_key() {
    local id=""
    [ -r /etc/machine-id ] && id=$(cat /etc/machine-id 2>/dev/null)
    [ -z "$id" ] && command -v ioreg > /dev/null 2>&1 && id=$(ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null | awk -F'"' '/IOPlatformUUID/{print $4; exit}')
    [ -z "$id" ] && id=$(hostname 2>/dev/null)
    printf 'LTTC-secret-v1-%s' "${id:-fallback}"
}

secret_encrypt() {
    local v="$1" out
    [ -z "$v" ] && return 0
    case "$v" in ENC1:*) printf '%s' "$v"; return 0 ;; esac
    command -v openssl > /dev/null 2>&1 || { printf '%s' "$v"; return 0; }
    out=$(printf '%s' "$v" | openssl enc -aes-256-cbc -base64 -A -salt -pass "pass:$(secret_key)" 2>/dev/null)
    if [ -n "$out" ]; then printf 'ENC1:%s' "$out"; else printf '%s' "$v"; fi
}

secret_decrypt() {
    local v="$1"
    case "$v" in
        ENC1:*) printf '%s' "${v#ENC1:}" | openssl enc -aes-256-cbc -d -base64 -A -pass "pass:$(secret_key)" 2>/dev/null ;;
        *) printf '%s' "$v" ;;
    esac
}
SILENT=false; AUTO_PATH=false; AUTO_SRV=""; AUTO_MODE=""; ADDON_DIR=""
SETUP_COMPLETE=false; ENABLE_NOTIFS=false; HAS_ARGS=false; IS_TASK=false
IS_STEAM_LAUNCH=false; ENABLE_DISPLAY="true"; ENABLE_LOCAL_MODE=false

if [ -f "$CONFIG_FILE" ]; then source "$CONFIG_FILE"; fi

TTC_LAST_SALE="${TTC_LAST_SALE:-0}"
TTC_LAST_DOWNLOAD="${TTC_LAST_DOWNLOAD:-0}"
TTC_LAST_CHECK="${TTC_LAST_CHECK:-0}"
EH_LAST_SALE="${EH_LAST_SALE:-0}"
EH_LAST_DOWNLOAD="${EH_LAST_DOWNLOAD:-0}"
EH_LAST_CHECK="${EH_LAST_CHECK:-0}"
EH_LOC_5="${EH_LOC_5:-0}"; EH_LOC_7="${EH_LOC_7:-0}"; EH_LOC_9="${EH_LOC_9:-0}"
HM_LAST_DOWNLOAD="${HM_LAST_DOWNLOAD:-0}"
HM_LAST_CHECK="${HM_LAST_CHECK:-0}"
LOG_MODE="${LOG_MODE:-simple}"
EH_USER_TOKEN="${EH_USER_TOKEN:-}"
TTC_CLIENT_ID="${TTC_CLIENT_ID:-}"
TARGET_RUN_TIME="${TARGET_RUN_TIME:-0}"
TARGET_USERNAME="${TARGET_USERNAME:-}"
SKIP_DL_TTC="${SKIP_DL_TTC:-false}"
SKIP_DL_HM="${SKIP_DL_HM:-false}"
SKIP_DL_EH="${SKIP_DL_EH:-false}"
ENABLE_ADDON_UPDATES="${ENABLE_ADDON_UPDATES:-false}"
ADDON_LAST_CHECK="${ADDON_LAST_CHECK:-0}"
ADDON_UPDATE_SKIP="${ADDON_UPDATE_SKIP:-}"
AUTO_SELF_UPDATE="${AUTO_SELF_UPDATE:-true}"
SELF_LAST_CHECK="${SELF_LAST_CHECK:-0}"
AOM_LAST_SYNC="${AOM_LAST_SYNC:-0}"
AOM_DATA_UPDATES="${AOM_DATA_UPDATES:-}"
ESOHUB_CF_CLEARANCE="${ESOHUB_CF_CLEARANCE:-}"
ESOHUB_CF_UA="${ESOHUB_CF_UA:-}"
ESOHUB_COOKIE_IMPORT="${ESOHUB_COOKIE_IMPORT:-false}"
EH_USER_TOKEN=$(secret_decrypt "$EH_USER_TOKEN")
TTC_CLIENT_ID=$(secret_decrypt "$TTC_CLIENT_ID")
TARGET_USERNAME=$(secret_decrypt "$TARGET_USERNAME")
ESOHUB_CF_CLEARANCE=$(secret_decrypt "$ESOHUB_CF_CLEARANCE")
ESOHUB_CF_UA=$(secret_decrypt "$ESOHUB_CF_UA")

write_lttc_config() {
    touch "$CONFIG_FILE" && chmod 600 "$CONFIG_FILE" 2>/dev/null
    local enc_token enc_client enc_user enc_cf enc_ua
    enc_token=$(secret_encrypt "$EH_USER_TOKEN"); enc_client=$(secret_encrypt "$TTC_CLIENT_ID")
    enc_user=$(secret_encrypt "$TARGET_USERNAME"); enc_cf=$(secret_encrypt "$ESOHUB_CF_CLEARANCE"); enc_ua=$(secret_encrypt "$ESOHUB_CF_UA")
    cat <<EOF > "$CONFIG_FILE"
AUTO_SRV="$AUTO_SRV"
SILENT=$SILENT
AUTO_MODE="$AUTO_MODE"
ADDON_DIR="$ADDON_DIR"
SETUP_COMPLETE=$SETUP_COMPLETE
ENABLE_NOTIFS=$ENABLE_NOTIFS
ENABLE_DISPLAY="$ENABLE_DISPLAY"
ENABLE_LOCAL_MODE=$ENABLE_LOCAL_MODE
LOG_MODE="$LOG_MODE"
TTC_LAST_SALE="$TTC_LAST_SALE"
TTC_LAST_DOWNLOAD="$TTC_LAST_DOWNLOAD"
TTC_LAST_CHECK="$TTC_LAST_CHECK"
EH_LAST_SALE="$EH_LAST_SALE"
EH_LAST_DOWNLOAD="$EH_LAST_DOWNLOAD"
EH_LAST_CHECK="$EH_LAST_CHECK"
EH_LOC_5="$EH_LOC_5"
EH_LOC_7="$EH_LOC_7"
EH_LOC_9="$EH_LOC_9"
HM_LAST_DOWNLOAD="$HM_LAST_DOWNLOAD"
HM_LAST_CHECK="$HM_LAST_CHECK"
EH_USER_TOKEN="$enc_token"
TTC_CLIENT_ID="$enc_client"
TARGET_RUN_TIME="$TARGET_RUN_TIME"
TARGET_USERNAME="$enc_user"
SKIP_DL_TTC=$SKIP_DL_TTC
SKIP_DL_HM=$SKIP_DL_HM
SKIP_DL_EH=$SKIP_DL_EH
ENABLE_ADDON_UPDATES=$ENABLE_ADDON_UPDATES
ADDON_LAST_CHECK="$ADDON_LAST_CHECK"
ADDON_UPDATE_SKIP="$ADDON_UPDATE_SKIP"
AUTO_SELF_UPDATE=$AUTO_SELF_UPDATE
SELF_LAST_CHECK="$SELF_LAST_CHECK"
AOM_LAST_SYNC="$AOM_LAST_SYNC"
AOM_DATA_UPDATES="$AOM_DATA_UPDATES"
ESOHUB_CF_CLEARANCE="$enc_cf"
ESOHUB_CF_UA="$enc_ua"
ESOHUB_COOKIE_IMPORT=$ESOHUB_COOKIE_IMPORT
EOF
}

ESOHUB_API="${LTTC_ESOHUB_API:-https://data.eso-hub.com}"
ESOHUB_V2_UA="ESO-Hub Client v2"
ESOHUB_V2_VERSION="0.2.23"
ESOHUB_V1_UA="ESOHubClient/1.0.9"
ESOHUB_LANGS="en"
esohub_lang() {
    local l="${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}"
    l=$(printf '%s' "$l" | cut -c1-2 | tr 'A-Z' 'a-z')
    case " $ESOHUB_LANGS " in *" $l "*) printf '%s' "$l" ;; *) printf 'en' ;; esac
}
ESOHUB_LANG="$(esohub_lang)"
ESOHUB_CF_PAGE="https://eso-hub.com/$ESOHUB_LANG/user/profile"
ESOHUB_LOGIN_PAGE="https://eso-hub.com/$ESOHUB_LANG/client-token-login?code="
ESOHUB_CF_ASK_SECONDS=300
ESOHUB_CODE_SECONDS=300
ESOHUB_CODE_POLL=2
ESOHUB_UA_WAIT=30
ESOHUB_LISTEN_TOOLS="python3 perl nc"
ESOHUB_CF_ASKED=false
ESOHUB_CF_HINT=""
ESOHUB_UA_SEEN=""
ESOHUB_UA_URL=""
ESOHUB_UA_DIR=""
ESOHUB_UA_PIDS=""
ESOHUB_UA_MISSING=""

ESOHUB_UA_PY='import os, socket, sys, time
target, path, out, limit = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(("127.0.0.1", 0))
s.listen(8)
with open(out + ".port.tmp", "w") as f:
    f.write(str(s.getsockname()[1]))
os.replace(out + ".port.tmp", out + ".port")
end = time.time() + limit
while time.time() < end:
    s.settimeout(max(0.2, end - time.time()))
    try:
        c, _ = s.accept()
    except OSError:
        break
    c.settimeout(5)
    data = b""
    try:
        while b"\r\n\r\n" not in data and len(data) < 32768:
            part = c.recv(4096)
            if not part:
                break
            data += part
    except OSError:
        pass
    lines = data.split(b"\r\n\r\n")[0].decode("latin-1").split("\r\n")
    hit = lines[0].startswith("GET " + path + " ")
    ua = ""
    for line in lines[1:]:
        key, _, value = line.partition(":")
        if key.strip().lower() == "user-agent":
            ua = value.strip()
    if hit:
        reply = "HTTP/1.1 302 Found\r\nLocation: " + target + "\r\nCache-Control: no-store\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    else:
        reply = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    try:
        c.sendall(reply.encode("latin-1"))
    except OSError:
        pass
    c.close()
    if hit:
        with open(out + ".tmp", "w", encoding="latin-1") as f:
            f.write(ua)
        os.replace(out + ".tmp", out)
        break
s.close()'

ESOHUB_UA_PL='use strict; use IO::Socket::INET;
my ($target, $path, $out, $limit) = @ARGV;
my $s = IO::Socket::INET->new(LocalAddr => "127.0.0.1", LocalPort => 0, Listen => 8, Proto => "tcp") or exit 1;
open(my $pf, ">", "$out.port.tmp") or exit 1;
print $pf $s->sockport;
close($pf);
rename("$out.port.tmp", "$out.port") or exit 1;
my $end = time + $limit;
while (time < $end) {
    my $rin = "";
    vec($rin, fileno($s), 1) = 1;
    next unless select(my $rout = $rin, undef, undef, 0.5);
    my $c = $s->accept or next;
    my ($data, $stop) = ("", time + 5);
    while (index($data, "\r\n\r\n") < 0 && length($data) < 32768 && time < $stop) {
        my $cin = "";
        vec($cin, fileno($c), 1) = 1;
        last unless select(my $cout = $cin, undef, undef, 1);
        my $n = sysread($c, my $buf, 4096);
        last unless $n;
        $data .= $buf;
    }
    my @lines = split(/\r\n/, (split(/\r\n\r\n/, $data))[0] // "");
    my $hit = @lines && index($lines[0], "GET $path ") == 0;
    my $ua = "";
    for my $line (@lines[1 .. $#lines]) { $ua = $1 if $line =~ /^user-agent:\s*(.*?)\s*$/i; }
    print $c ($hit ? "HTTP/1.1 302 Found\r\nLocation: $target\r\nCache-Control: no-store\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        : "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
    close($c);
    if ($hit) {
        open(my $f, ">", "$out.tmp") or exit 1;
        print $f $ua;
        close($f);
        rename("$out.tmp", $out);
        last;
    }
}'

esohub_cf_ready() {
    [ -n "${ESOHUB_CF_CLEARANCE:-}" ] && [ -n "${ESOHUB_CF_UA:-}" ]
}

esohub_reload_cf() {
    [ -n "${CONFIG_FILE:-}" ] && [ -f "$CONFIG_FILE" ] || return 0
    local line val
    line=$(grep -m1 '^ESOHUB_CF_CLEARANCE=' "$CONFIG_FILE" 2>/dev/null); val="${line#ESOHUB_CF_CLEARANCE=}"; val="${val%\"}"; val="${val#\"}"; val=$(secret_decrypt "$val")
    [ -n "$val" ] && ESOHUB_CF_CLEARANCE="$val"
    line=$(grep -m1 '^ESOHUB_CF_UA=' "$CONFIG_FILE" 2>/dev/null); val="${line#ESOHUB_CF_UA=}"; val="${val%\"}"; val="${val#\"}"; val=$(secret_decrypt "$val")
    [ -n "$val" ] && ESOHUB_CF_UA="$val"
}

esohub_ua() {
    if esohub_cf_ready; then printf '%s' "$ESOHUB_CF_UA"; else printf '%s' "$1"; fi
}

esohub_cf_host_ok() {
    local host
    case "$1" in "$ESOHUB_API"/*) return 0 ;; https://*) ;; *) return 1 ;; esac
    host="${1#https://}"; host="${host%%[/?#]*}"
    case "$host" in *@*|*:*) return 1 ;; eso-hub.com|*.eso-hub.com) return 0 ;; esac
    return 1
}

esohub_cf_config() {
    if esohub_cf_ready && esohub_cf_host_ok "$1"; then
        printf 'header = "Cookie: cf_clearance=%s"\n' "$ESOHUB_CF_CLEARANCE"
    fi
    return 0
}

esohub_cf_clean_cookie() {
    local v
    v=$(printf '%s' "$1" | tr -d ' \t\r\n')
    v="${v#Cookie:}"; v="${v#cf_clearance=}"; v="${v%%;*}"
    case "$v" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac
    [ "${#v}" -ge 20 ] || return 1
    printf '%s' "$v"
}

esohub_cf_clean_ua() {
    local v
    v=$(printf '%s' "$1" | tr -d '\r\n' | sed "s/^[[:space:]]*//; s/[[:space:]]*\$//; s/^['\"]//; s/['\"]\$//")
    case "$v" in Mozilla/*) ;; *) return 1 ;; esac
    case "$v" in *[\"\$\`\\]*) return 1 ;; esac
    printf '%s' "$v"
}

esohub_cf_can_ask() {
    [ "$SILENT" != true ] && { : < /dev/tty; } 2>/dev/null
}

esohub_cf_read() {
    local ans=""
    if [ "${1:-}" = secret ]; then
        read -r -s -t "$ESOHUB_CF_ASK_SECONDS" ans < /dev/tty 2>/dev/null || return 1
    else
        read -r -t "$ESOHUB_CF_ASK_SECONDS" ans < /dev/tty 2>/dev/null || return 1
    fi
    printf '%s' "$ans"
}

esohub_open() {
    open_url "$1"
}

esohub_have() {
    command -v "$1" > /dev/null 2>&1 || return 1
    if [ "$1" = python3 ] && [ "$(command -v python3)" = /usr/bin/python3 ] && command -v xcode-select > /dev/null 2>&1; then
        xcode-select -p > /dev/null 2>&1 || return 1
    fi
    return 0
}

esohub_login_code() {
    local h
    h=$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
    case "$h" in ''|*[!0-9a-f]*) return 1 ;; esac
    [ "${#h}" -eq 32 ] || return 1
    printf '%s-%s-4%s-%x%s-%s' "${h:0:8}" "${h:8:4}" "${h:13:3}" $(( (16#${h:16:1} & 3) | 8 )) "${h:17:3}" "${h:20:12}"
}

esohub_ua_kill() {
    local pid
    for pid in $ESOHUB_UA_PIDS; do
        { pkill -P "$pid"; kill "$pid"; wait "$pid"; } > /dev/null 2>&1
    done
    ESOHUB_UA_PIDS=""
}

esohub_ua_stop() {
    esohub_ua_kill
    [ -n "$ESOHUB_UA_DIR" ] && rm -rf "$ESOHUB_UA_DIR"
    ESOHUB_UA_DIR=""; ESOHUB_UA_URL=""
}

esohub_ua_nc() {
    local target="$1" path="$2" out="$3" end=$((SECONDS + ESOHUB_UA_WAIT)) rc
    shift 3
    while [ "$SECONDS" -lt "$end" ]; do
        printf 'HTTP/1.1 302 Found\r\nLocation: %s\r\nCache-Control: no-store\r\nContent-Length: 0\r\nConnection: close\r\n\r\n' "$target" \
            | nc "$@" > "$out.req" 2> /dev/null
        rc=$?
        if head -n 1 "$out.req" 2> /dev/null | grep -q "^GET $path "; then
            sed -n 's/^[Uu][Ss][Ee][Rr]-[Aa][Gg][Ee][Nn][Tt]:[[:space:]]*//p' "$out.req" | tr -d '\r' | head -n 1 > "$out.tmp"
            mv -f "$out.tmp" "$out"
            break
        fi
        if [ "$rc" -ne 0 ] && [ ! -s "$out.req" ]; then
            : > "$out.fail"
            sleep 0.2
        fi
    done
    rm -f "$out.req"
}

esohub_ua_nc_start() {
    local target="$1" path="$2" out="$3" form first second port pid dog
    case "$(nc -h 2>&1 < /dev/null | head -n 40)" in
        *"GNU netcat"*|*"[v1.10"*|*BusyBox*|*"-q secs"*) first="-l -s 127.0.0.1 -p"; second="-l 127.0.0.1" ;;
        *) first="-l 127.0.0.1"; second="-l -s 127.0.0.1 -p" ;;
    esac
    for form in "$first" "$second"; do
        port=$((49152 + RANDOM % 16000))
        ( exec 3<> "/dev/tcp/127.0.0.1/$port" ) > /dev/null 2>&1 && continue
        rm -f "$out.fail"
        esohub_ua_nc "$target" "$path" "$out" $form "$port" < /dev/null > /dev/null 2>&1 &
        pid=$!
        ( sleep $((ESOHUB_UA_WAIT + 5)); pkill -P "$pid"; kill "$pid" ) < /dev/null > /dev/null 2>&1 &
        dog=$!
        ESOHUB_UA_PIDS="$pid $dog"
        sleep 0.4
        if [ ! -f "$out.fail" ]; then
            printf '%s' "$port" > "$out.port"
            return 0
        fi
        esohub_ua_kill
    done
    rm -f "$out.fail"
    return 1
}

esohub_ua_listen() {
    local target="$1" tool path port i tried=""
    esohub_ua_stop
    ESOHUB_UA_MISSING=""
    ESOHUB_UA_DIR=$(mktemp -d 2>/dev/null) || ESOHUB_UA_DIR=""
    if [ -z "$ESOHUB_UA_DIR" ] || ! path="/$(esohub_login_code)"; then
        ESOHUB_UA_MISSING="it couldn't make a temporary folder or a random page name"
        esohub_ua_stop
        return 1
    fi
    for tool in $ESOHUB_LISTEN_TOOLS; do
        esohub_have "$tool" || continue
        tried="${tried:+$tried, }$tool"
        case "$tool" in
            python3)
                python3 -I -c "$ESOHUB_UA_PY" "$target" "$path" "$ESOHUB_UA_DIR/ua" "$ESOHUB_UA_WAIT" < /dev/null > /dev/null 2>&1 &
                ESOHUB_UA_PIDS=$! ;;
            perl)
                perl -e "$ESOHUB_UA_PL" "$target" "$path" "$ESOHUB_UA_DIR/ua" "$ESOHUB_UA_WAIT" < /dev/null > /dev/null 2>&1 &
                ESOHUB_UA_PIDS=$! ;;
            nc) esohub_ua_nc_start "$target" "$path" "$ESOHUB_UA_DIR/ua" || continue ;;
            *) continue ;;
        esac
        i=0
        while [ ! -s "$ESOHUB_UA_DIR/ua.port" ] && [ "$i" -lt 30 ]; do sleep 0.1; i=$((i + 1)); done
        port=$(cat "$ESOHUB_UA_DIR/ua.port" 2>/dev/null)
        case "$port" in
            ''|*[!0-9]*) esohub_ua_kill; rm -f "$ESOHUB_UA_DIR/ua.port" ;;
            *) ESOHUB_UA_URL="http://127.0.0.1:$port$path"; return 0 ;;
        esac
    done
    if [ -n "$tried" ]; then
        ESOHUB_UA_MISSING="$tried couldn't open a local port on 127.0.0.1"
    else
        ESOHUB_UA_MISSING="that needs python3, perl or nc (netcat), and none of them is installed"
    fi
    esohub_ua_stop
    return 1
}

esohub_ua_wait() {
    local i=0 limit=$((ESOHUB_UA_WAIT * 10))
    while [ "$i" -lt "$limit" ]; do
        if [ -f "$ESOHUB_UA_DIR/ua" ]; then
            cat "$ESOHUB_UA_DIR/ua"
            return 0
        fi
        sleep 0.1
        i=$((i + 1))
    done
    return 1
}

esohub_browser_open() {
    local page="$1" ua
    ESOHUB_UA_SEEN=""
    if ! esohub_ua_listen "$page"; then
        echo -e " \e[33m[-] The updater can't read your browser's User-Agent by itself: $ESOHUB_UA_MISSING. Step 4 asks you to paste it.\e[0m"
        esohub_open "$page"
        return 1
    fi
    esohub_open "$ESOHUB_UA_URL"
    if ua=$(esohub_ua_wait); then
        esohub_ua_stop
        if ua=$(esohub_cf_clean_ua "$ua"); then
            ESOHUB_UA_SEEN="$ua"
            echo -e " \e[0;32m[+] Login and Verify.\e[0m"
            return 0
        fi
        echo -e " \e[33m[-] Your browser sent a User-Agent the updater can't use. Step 4 asks you to paste it.\e[0m"
        return 1
    fi
    esohub_ua_stop
    echo -e " \e[33m[-] Your browser didn't reach the updater's page within $ESOHUB_UA_WAIT seconds, so ESO-Hub opens directly. Step 4 asks you to paste the User-Agent.\e[0m"
    esohub_open "$page"
    return 1
}

esohub_cf_prompt() {
    local page="${1:-$ESOHUB_CF_PAGE}" step="${2:-}" ck ua
    [ -n "$step" ] || step="Opening \e[0;35m$page\e[0m in your browser \e[90m(opening it now)\e[0m wait until ESO-Hub's page shows."
    echo -e " \e[0;33m[-] ESO-Hub Human Verification Required:\e[0m"
    echo -e "  \e[0;32m1)\e[0m $step"
    esohub_browser_open "$page"
    echo -e "  \e[0;32m2)\e[0m Press F12, then open \e[0;36mApplication\e[0m \e[90m(Chrome, Edge, Brave)\e[0m or \e[0;36mStorage\e[0m \e[90m(Firefox)\e[0m > \e[0;36mCookies\e[0m > https://eso-hub.com."
    echo -e "  \e[0;32m3)\e[0m Copy the value of \e[0;36mcf_clearance\e[0m and paste it here."
    echo -e "     \e[90mcf_clearance is ESO-Hub's proof that a human, not a bot, passed this check. The updater\e[0m"
    echo -e "     \e[90msends it with each request so ESO-Hub answers with data instead of the check again. It\e[0m"
    echo -e "     \e[90mstays on this PC and is sent only to eso-hub.com.\e[0m"
    echo -ne " \e[0;34mcf_clearance \e[90m(hidden while you paste, Enter skips)\e[0;34m: \e[0m"
    if ! ck=$(esohub_cf_read secret); then
        echo
        echo -e " \e[90mNo answer, so ESO-Hub is skipped this time.\e[0m"
        write_ttc_log "WARN" "ESO-Hub browser check skipped: no cf_clearance entered within $((ESOHUB_CF_ASK_SECONDS / 60)) minutes; the updater continues."
        return 1
    fi
    echo
    if [ -z "$ck" ]; then
        echo -e " \e[90mSkipped.\e[0m"
        return 1
    fi
    if ! ck=$(esohub_cf_clean_cookie "$ck"); then
        echo -e " \e[31m[-] That isn't a cf_clearance value. Copy the Value column of the cf_clearance row.\e[0m"
        return 1
    fi
    if [ -n "$ESOHUB_UA_SEEN" ]; then
        ua="$ESOHUB_UA_SEEN"
    else
        echo -e "  \e[0;32m4)\e[0m In the same DevTools window open \e[0;36mConsole\e[0m, type \e[0;36mnavigator.userAgent\e[0m, press Enter and copy the text it shows."
        echo -ne " \e[0;34mUser-Agent: \e[0m"
        if ! ua=$(esohub_cf_read); then
            echo
            echo -e " \e[90mNo answer, so ESO-Hub is skipped this time.\e[0m"
            write_ttc_log "WARN" "ESO-Hub browser check skipped: no cf_clearance entered within $((ESOHUB_CF_ASK_SECONDS / 60)) minutes; the updater continues."
            return 1
        fi
        if ! ua=$(esohub_cf_clean_ua "$ua"); then
            echo -e " \e[31m[-] That isn't a browser User-Agent. It starts with Mozilla/5.0.\e[0m"
            return 1
        fi
    fi
    ESOHUB_CF_CLEARANCE="$ck"; ESOHUB_CF_UA="$ua"; CONFIG_CHANGED=true
    echo -e " \e[0;32m[+] Saved (${#ck} characters). The updater only sends it to eso-hub.com.\e[0m"
    write_ttc_log "INFO" "ESO-Hub browser check saved (cf_clearance and User-Agent)."
    return 0
}

esohub_cf_ask_now() {
    if [ "${ESOHUB_COOKIE_IMPORT:-false}" = true ] && esohub_cookie_fetch; then
        ESOHUB_CF_HINT=""
        return 0
    fi
    if [ "$ESOHUB_CF_ASKED" = true ]; then
        ESOHUB_CF_HINT="The updater asks for ESO-Hub's browser check again the next time it starts."
        return 1
    fi
    ESOHUB_CF_ASKED=true
    if ! esohub_cf_can_ask; then
        ESOHUB_CF_HINT="Start the updater in a terminal or run --setup to refresh ESO-Hub's cf_clearance; a running copy picks it up next cycle."
        return 1
    fi
    ESOHUB_CF_HINT=""
    esohub_cf_prompt
}

esohub_v2_parse() {
    awk '
    { s = s $0 "\n" }
    function path(   k, p) {
        p = ""
        for (k = 1; k <= d; k++) p = p (k > 1 ? "." : "") (typ[k] == "o" ? key[k] : idx[k])
        return p
    }
    function keep(p, v,   n, rest, field) {
        if (substr(p, 1, 7) != "addons.") return
        rest = substr(p, 8)
        n = rest; sub(/\..*$/, "", n)
        if (n !~ /^[0-9]+$/) return
        field = substr(rest, length(n) + 2)
        if (v == "null") v = ""
        gsub(/[|\t\r\n]/, " ", v)
        n = n + 0
        if (n > last) last = n
        seen[n] = 1
        if (field == "id") aid[n] = v
        else if (field == "folder_name") folder[n] = v
        else if (field == "file") file[n] = v
        else if (field == "checksum") sum[n] = v
        else if (field == "version.integer") vint[n] = v
        else if (field == "version.string") vstr[n] = v
        else if (field == "transfer.endpoint") ep[n] = v
        else if (field ~ /^transfer\.sv_file_names\.[0-9]+$/ && v != "") sv[n] = (sv[n] == "" ? v : sv[n] ";" v)
    }
    END {
        n = length(s); d = 0; i = 1; last = -1
        while (i <= n) {
            c = substr(s, i, 1)
            if (c == "{") { d++; typ[d] = "o"; key[d] = ""; want[d] = 1; i++; continue }
            if (c == "[") { d++; typ[d] = "a"; idx[d] = 0; i++; continue }
            if (c == "}" || c == "]") { d--; i++; continue }
            if (c == ",") { if (typ[d] == "a") idx[d]++; else want[d] = 1; i++; continue }
            if (c == ":") { want[d] = 0; i++; continue }
            if (c == " " || c == "\t" || c == "\r" || c == "\n") { i++; continue }
            if (c == "\"") {
                str = ""; i++
                while (i <= n) {
                    c = substr(s, i, 1)
                    if (c == "\\") {
                        e = substr(s, i + 1, 1)
                        if (e == "n" || e == "t" || e == "r") str = str " "
                        else if (e == "u") { str = str "\\u" substr(s, i + 2, 4); i += 4 }
                        else str = str e
                        i += 2; continue
                    }
                    if (c == "\"") { i++; break }
                    str = str c; i++
                }
                if (d > 0 && typ[d] == "o" && want[d]) { key[d] = str; continue }
                keep(path(), str); continue
            }
            j = i
            while (j <= n) {
                c = substr(s, j, 1)
                if (c == "," || c == "}" || c == "]" || c == " " || c == "\t" || c == "\r" || c == "\n") break
                j++
            }
            keep(path(), substr(s, i, j - i)); i = j
        }
        for (k = 0; k <= last; k++) {
            if (!seen[k] || folder[k] == "") continue
            id = aid[k]
            if (match(file[k], /[0-9]+$/)) id = substr(file[k], RSTART)
            if (id == "") id = "0"
            ver = (vint[k] != "" ? vint[k] : vstr[k])
            printf "%s|%s|%s|%s|%s|%s|%s\n", id, folder[k], ver, file[k], sum[k], ep[k], sv[k]
        }
    }' "$1"
}

esohub_v1_parse() {
    local line fname sv ep file ver id
    awk '{ gsub(/\{"folder_name"/, "\n{\"folder_name\""); print }' "$1" | grep '"folder_name"' | while read -r line; do
        fname=$(echo "$line" | grep -oE '"folder_name":"[^"]+"' | cut -d'"' -f4)
        [ -z "$fname" ] && continue
        sv=$(echo "$line" | grep -oE '"sv_file_name":"[^"]+"' | cut -d'"' -f4)
        ep=$(echo "$line" | grep -oE '"endpoint":"[^"]+"' | cut -d'"' -f4 | sed 's/\\//g')
        file=$(echo "$line" | grep -oE '"file":"[^"]+"' | cut -d'"' -f4 | sed 's/\\//g')
        ver=$(echo "$line" | grep -oE '"version":\{[^}]*\}' | grep -oE '"string":"[^"]+"' | cut -d'"' -f4)
        id=$(echo "$file" | grep -oE '[0-9]+$')
        [ -z "$id" ] && id="0"
        printf '%s|%s|%s|%s||%s|%s\n' "$id" "$fname" "$ver" "$file" "$ep" "$sv"
    done
}

esohub_http() {
    local body="$1" head="$2" url="$3"; shift 3
    rm -f "$body" "$head"
    esohub_cf_config "$url" | curl -s -m 30 -K - -D "$head" -o "$body" -w '%{http_code}' "$@" "$url" 2>/dev/null
}

esohub_reason() {
    local code="$1" head="$2"
    if [ -z "$code" ] || [ "$code" = "000" ]; then echo "no connection"; return; fi
    if grep -qi '^cf-mitigated: *challenge' "$head" 2>/dev/null; then echo "HTTP $code (Cloudflare challenge)"; return; fi
    echo "HTTP $code"
}

esohub_fetch_addons() {
    local body="$TEMP_DIR_ROOT/lttc_eh_list.json" head="$TEMP_DIR_ROOT/lttc_eh_list.head" code why_v2 why_v1
    ESOHUB_RECORDS=""; ESOHUB_API_USED=""; ESOHUB_FAIL=""; ESOHUB_BLOCKED=false
    mkdir -p "$TEMP_DIR_ROOT" 2>/dev/null

    code=$(esohub_http "$body" "$head" "$ESOHUB_API/v2/api/get-addon-versions" -H "User-Agent: $(esohub_ua "$ESOHUB_V2_UA")" \
        -H "X-ESO-Hub-Client-Version: $ESOHUB_V2_VERSION" -H "Accept: application/json" ${EH_USER_TOKEN:+-H "Authorization: Bearer $EH_USER_TOKEN"})
    if [ -n "${EH_USER_TOKEN:-}" ] && [ "$code" = "401" ] && ! grep -qi '^cf-mitigated' "$head" 2>/dev/null; then
        write_ttc_log "WARN" "ESO-Hub did not accept the saved token (HTTP 401); asking again without it."
        code=$(esohub_http "$body" "$head" "$ESOHUB_API/v2/api/get-addon-versions" -H "User-Agent: $(esohub_ua "$ESOHUB_V2_UA")" \
            -H "X-ESO-Hub-Client-Version: $ESOHUB_V2_VERSION" -H "Accept: application/json")
    fi
    [ "$code" = "200" ] && ESOHUB_RECORDS=$(esohub_v2_parse "$body")
    if [ -n "$ESOHUB_RECORDS" ]; then
        ESOHUB_API_USED="v2"; rm -f "$body" "$head"; return 0
    fi
    why_v2=$(esohub_reason "$code" "$head")
    [ "$code" = "200" ] && why_v2="HTTP 200 without an add-on list"

    code=$(esohub_http "$body" "$head" "$ESOHUB_API/v1/api/get-addon-versions" -X POST -H "User-Agent: $(esohub_ua "$ESOHUB_V1_UA")" \
        -d "user_token=&client_system=${SYS_ID:-linux}&client_version=1.0.9&lang=en")
    [ "$code" = "200" ] && ESOHUB_RECORDS=$(esohub_v1_parse "$body")
    if [ -n "$ESOHUB_RECORDS" ]; then
        ESOHUB_API_USED="v1"; rm -f "$body" "$head"
        write_ttc_log "WARN" "ESO-Hub v2 add-on list failed ($why_v2); the v1 list answered."
        return 0
    fi
    why_v1=$(esohub_reason "$code" "$head")
    [ "$code" = "200" ] && why_v1="HTTP 200 without an add-on list"
    rm -f "$body" "$head"

    ESOHUB_FAIL="v2: $why_v2, v1: $why_v1"
    case "$ESOHUB_FAIL" in *Cloudflare*) ESOHUB_BLOCKED=true ;; esac
    return 1
}

esohub_local_version() {
    local f
    for f in "$1/$2.txt" "$1/$2.addon"; do
        [ -f "$f" ] || continue
        awk '/IntVersion:/ { sub(/^.*IntVersion:[ \t]*/, ""); sub(/\r$/, ""); sub(/[ \t].*$/, ""); print; exit }' "$f"
        return
    done
}

esohub_is_newer() {
    [ -n "$1" ] || return 1
    case "$1$2" in *[!0-9]*) [ "$1" != "$2" ]; return ;; esac
    [ -n "$2" ] || return 0
    [ "$1" -gt "$2" ]
}

esohub_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
    elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 "$1" | awk '{ print $NF }'
    fi
}

esohub_download() {
    local url="$1" out="$2" want="$3" got
    rm -f "$out"
    esohub_cf_config "$url" | curl -s -f -L -m 60 -K - -H "User-Agent: $(esohub_ua "$ESOHUB_V2_UA")" -H "X-ESO-Hub-Client-Version: $ESOHUB_V2_VERSION" \
        ${EH_USER_TOKEN:+-H "Authorization: Bearer $EH_USER_TOKEN"} -o "$out" --url "$url" \
        || esohub_cf_config "$url" | curl -s -f -L -m 30 -K - -A "$(esohub_ua "$ESOHUB_V1_UA")" -o "$out" --url "$url" \
        || curl -s -f -L -m 30 -A "${RAND_UA:-Mozilla/5.0}" -o "$out" --url "$url" </dev/null \
        || { rm -f "$out"; return 1; }
    if [ -n "$want" ]; then
        got=$(esohub_sha256 "$out")
        if [ -n "$got" ] && [ "$(printf '%s' "$got" | tr 'A-F' 'a-f')" != "$(printf '%s' "$want" | tr 'A-F' 'a-f')" ]; then
            write_ttc_log "ERROR" "ESO-Hub download $url failed its checksum (expected $want, got $got)."
            rm -f "$out"; return 2
        fi
    fi
    unzip -t "$out" > /dev/null 2>&1 || { rm -f "$out"; return 1; }
    return 0
}

esohub_zip() {
    local out="$1" dir="$2"; shift 2
    rm -f "$out"
    if command -v zip >/dev/null 2>&1 && (cd "$dir" && zip -q -X "$out" "$@") >/dev/null 2>&1 && [ -s "$out" ]; then return 0; fi
    rm -f "$out"
    if command -v bsdtar >/dev/null 2>&1 && bsdtar --format zip -cf "$out" -C "$dir" "$@" >/dev/null 2>&1 && [ -s "$out" ]; then return 0; fi
    rm -f "$out"
    if tar --version 2>/dev/null | grep -qi bsdtar && tar --format zip -cf "$out" -C "$dir" "$@" >/dev/null 2>&1 && [ -s "$out" ]; then return 0; fi
    rm -f "$out"
    if command -v python3 >/dev/null 2>&1 && python3 -I -c 'import os, sys, zipfile
z = zipfile.ZipFile(sys.argv[1], "w", zipfile.ZIP_DEFLATED)
for n in sys.argv[3:]: z.write(os.path.join(sys.argv[2], n), n)
z.close()' "$out" "$dir" "$@" >/dev/null 2>&1 && [ -s "$out" ]; then return 0; fi
    rm -f "$out"
    return 1
}

esohub_upload_name() {
    printf '%04x%04x-%04x-4%03x-%04x-%04x%04x%04x' $RANDOM $RANDOM $RANDOM $((RANDOM % 4096)) $((RANDOM % 16384 + 32768)) $RANDOM $RANDOM $RANDOM
}

esohub_upload_v2() {
    local url="$1" zipf="$TEMP_DIR_ROOT/lttc_eh_upload.zip" rc f
    local -a found
    shift
    found=()
    for f in "$@"; do [ -f "$SAVED_VAR_DIR/$f" ] && found+=("$f"); done
    [ "${#found[@]}" -gt 0 ] || return 1
    if ! esohub_zip "$zipf" "$SAVED_VAR_DIR" "${found[@]}"; then
        write_ttc_log "WARN" "ESO-Hub v2 upload needs zip, bsdtar or python3 to pack ${found[*]}; none worked."
        return 1
    fi
    esohub_cf_config "$url" | curl -s -f -m 60 -K - -H "User-Agent: $(esohub_ua "$ESOHUB_V2_UA")" -H "X-ESO-Hub-Client-Version: $ESOHUB_V2_VERSION" \
        -H "Accept: application/json" ${EH_USER_TOKEN:+-H "Authorization: Bearer $EH_USER_TOKEN"} \
        -F "archive=@\"$zipf\";filename=$(esohub_upload_name).zip;type=application/zip" -F "server=live" \
        "$url" > /dev/null 2>&1
    rc=$?
    rm -f "$zipf"
    return $rc
}

esohub_upload_v1() {
    local url="$1" f
    shift
    for f in "$@"; do
        esohub_cf_config "$url" | curl -s -f -m 60 -K - -A "$(esohub_ua "$ESOHUB_V1_UA")" -F "file=@\"$SAVED_VAR_DIR/$f\"" \
            "$url?user_token=${EH_USER_TOKEN:-}" > /dev/null 2>&1 || return 1
    done
    return 0
}

esohub_upload() {
    local api="$1" endpoint="$2" send="$3" all="$4" url
    local -a send_files all_files
    case "$endpoint" in http://*|https://*) url="$endpoint" ;; *) url="$ESOHUB_API$endpoint" ;; esac
    send_files=(); all_files=()
    while IFS= read -r f; do [ -n "$f" ] && send_files+=("$f"); done <<< "$(printf '%s' "$send" | tr ';' '\n')"
    while IFS= read -r f; do [ -n "$f" ] && all_files+=("$f"); done <<< "$(printf '%s' "$all" | tr ';' '\n')"
    [ "${#send_files[@]}" -gt 0 ] || return 1
    [ "${#all_files[@]}" -gt 0 ] || all_files=("${send_files[@]}")
    if [ "$api" = "v1" ]; then
        esohub_upload_v1 "$url" "${send_files[@]}" && return 0
        esohub_upload_v2 "$url" "${all_files[@]}" && return 0
    else
        esohub_upload_v2 "$url" "${all_files[@]}" && return 0
        esohub_upload_v1 "$url" "${send_files[@]}" && return 0
    fi
    return 1
}

esohub_curl_quote() {
    printf '%s' "$1" | sed 's/[\\"]/\\&/g'
}

esohub_login_reason() {
    local code="$1" head="$2" msg
    if [ -z "$code" ] || [ "$code" = "000" ]; then echo "no connection to ESO-Hub"; return; fi
    if grep -qi '^cf-mitigated: *challenge' "$head" 2>/dev/null; then echo "ESO-Hub's server answered with a Cloudflare check"; return; fi
    msg=$(grep -o '"message" *: *"[^"]*"' "$3" 2>/dev/null | head -n 1 | cut -d'"' -f4 | tr -cd '[:print:]' | tr -d '\\' | cut -c1-120)
    case "$code" in 200|401|403|422) echo "ESO-Hub did not accept that username and password${msg:+ ($msg)}"; return ;; esac
    echo "ESO-Hub answered HTTP $code${msg:+ ($msg)}"
}

esohub_request_token() {
    local user pass work code why_v2
    ESOHUB_TOKEN=""; ESOHUB_LOGIN_FAIL=""; ESOHUB_LOGIN_BLOCKED=false
    user=$(esohub_curl_quote "$1"); pass=$(esohub_curl_quote "$2")
    work=$(mktemp -d 2>/dev/null) || return 1
    code=$({ printf 'user = "%s:%s"\n' "$user" "$pass"; esohub_cf_config "$ESOHUB_API/v2/api/request-token"; } | curl -s -m 30 -K - -X POST \
        -D "$work/h" -o "$work/b" -w '%{http_code}' \
        -H "User-Agent: $(esohub_ua "$ESOHUB_V2_UA")" -H "X-ESO-Hub-Client-Version: $ESOHUB_V2_VERSION" -H "Accept: application/json" \
        "$ESOHUB_API/v2/api/request-token" 2>/dev/null)
    ESOHUB_TOKEN=$(grep -o '"token" *: *"[^"]*"' "$work/b" 2>/dev/null | head -n 1 | cut -d'"' -f4)
    why_v2=$(esohub_login_reason "$code" "$work/h" "$work/b")
    if [ -z "$ESOHUB_TOKEN" ]; then
        rm -f "$work/h" "$work/b"
        code=$({ printf 'data-urlencode = "username=%s"\ndata-urlencode = "password=%s"\n' "$user" "$pass"; esohub_cf_config "$ESOHUB_API/v1/api/login"; } \
            | curl -s -m 30 -K - -X POST -D "$work/h" -o "$work/b" -w '%{http_code}' \
            -H "User-Agent: $(esohub_ua "$ESOHUB_V1_UA")" \
            --data-urlencode "client_system=${SYS_ID:-linux}" \
            --data-urlencode "client_version=1.0.9" \
            --data-urlencode "client_version_int=1009" \
            --data-urlencode "lang=en" \
            "$ESOHUB_API/v1/api/login" 2>/dev/null)
        ESOHUB_TOKEN=$(grep -o '"token" *: *"[^"]*"' "$work/b" 2>/dev/null | head -n 1 | cut -d'"' -f4)
        if [ -z "$ESOHUB_TOKEN" ]; then
            case "$why_v2" in
                *Cloudflare*)
                    ESOHUB_LOGIN_FAIL=$(esohub_login_reason "$code" "$work/h" "$work/b")
                    case "$ESOHUB_LOGIN_FAIL" in *Cloudflare*) ESOHUB_LOGIN_BLOCKED=true ;; esac ;;
                *) ESOHUB_LOGIN_FAIL="$why_v2" ;;
            esac
        fi
    fi
    rm -rf "$work"
    [ -n "$ESOHUB_TOKEN" ]
}

esohub_code_poll() {
    esohub_http "$2/b" "$2/h" "$ESOHUB_API/v2/api/request-token-with-code" -X POST \
        -H "User-Agent: $(esohub_ua "$ESOHUB_V2_UA")" -H "X-ESO-Hub-Client-Version: $ESOHUB_V2_VERSION" \
        -H "Accept: application/json" -H "Content-Type: application/json" --data "{\"code\":\"$1\"}"
}

esohub_code_wait() {
    local start=$SECONDS ans
    if read -r -t "$1" ans < /dev/tty 2>/dev/null; then return 0; fi
    [ $((SECONDS - start)) -ge 1 ] || sleep "$1"
    return 1
}

esohub_wait_text() {
    if [ "$1" -ge 120 ]; then echo "$(($1 / 60)) minutes"; else echo "$1 seconds"; fi
}

esohub_code_answer() {
    local msg
    if [ -z "$1" ] || [ "$1" = "000" ]; then echo "no connection"; return; fi
    msg=$(grep -o '"message" *: *"[^"]*"' "$2" 2>/dev/null | head -n 1 | cut -d'"' -f4 | tr -cd '[:print:]' | tr -d '\\' | cut -c1-120)
    echo "HTTP $1${msg:+, $msg}"
}

esohub_code_login() {
    local code url work deadline http
    ESOHUB_TOKEN=""; ESOHUB_LOGIN_USER=""; ESOHUB_LOGIN_FAIL=""
    if ! code=$(esohub_login_code); then
        ESOHUB_LOGIN_FAIL="this system couldn't make a login code from /dev/urandom"
        return 1
    fi
    if ! work=$(mktemp -d 2>/dev/null); then
        ESOHUB_LOGIN_FAIL="the updater couldn't make a temporary folder"
        return 1
    fi
    url="$ESOHUB_LOGIN_PAGE$code"
    http=$(esohub_code_poll "$code" "$work")
    if [ -z "$http" ] || [ "$http" = "000" ]; then
        ESOHUB_LOGIN_FAIL="no connection to ESO-Hub"
        rm -rf "$work"
        return 1
    fi
    if grep -qi '^cf-mitigated: *challenge' "$work/h" 2>/dev/null; then
        if ! esohub_cf_prompt "$url" "Opening ESO-Hub's login page in your browser \e[90m(opening it now)\e[0m, log in and link this device, then stay on that tab for the next steps."; then
            ESOHUB_LOGIN_FAIL="the updater can't pick up the Login Token without cf_clearance, because ESO-Hub's data server answers with a Cloudflare check"
            rm -rf "$work"
            return 1
        fi
    else
        echo -e " \e[0;33mLog in to ESO-Hub in your browser \e[90m(opening it now)\e[0;33m and link this device when ESO-Hub asks.\e[0m"
        esohub_open "$url"
    fi
    deadline=$((SECONDS + ESOHUB_CODE_SECONDS))
    echo -e " \e[36mWaiting for ESO-Hub to confirm the login \e[90m(up to $(esohub_wait_text "$ESOHUB_CODE_SECONDS"), Enter stops waiting)\e[36m...\e[0m"
    while :; do
        http=$(esohub_code_poll "$code" "$work")
        ESOHUB_TOKEN=$(grep -o '"token" *: *"[^"]*"' "$work/b" 2>/dev/null | head -n 1 | cut -d'"' -f4)
        if [ -n "$ESOHUB_TOKEN" ]; then
            ESOHUB_LOGIN_USER=$(grep -o '"username" *: *"[^"]*"' "$work/b" 2>/dev/null | head -n 1 | cut -d'"' -f4 | tr -cd '[:print:]' | tr -d '\\' | cut -c1-60)
            break
        fi
        if grep -qi '^cf-mitigated: *challenge' "$work/h" 2>/dev/null; then
            ESOHUB_LOGIN_FAIL="ESO-Hub's server still answers with a Cloudflare check; copy cf_clearance from the browser that opened, on this PC and network"
            break
        fi
        if [ "$SECONDS" -ge "$deadline" ]; then
            ESOHUB_LOGIN_FAIL="ESO-Hub didn't confirm the login within $(esohub_wait_text "$ESOHUB_CODE_SECONDS") (last answer: $(esohub_code_answer "$http" "$work/b"))"
            break
        fi
        if esohub_code_wait "$ESOHUB_CODE_POLL"; then
            ESOHUB_LOGIN_FAIL="you stopped waiting"
            break
        fi
    done
    rm -rf "$work"
    [ -n "$ESOHUB_TOKEN" ]
}
esohub_cookie_roots() {
    if [ "$OS_TYPE" = Darwin ]; then
        printf '%s\n' \
            "brave|$HOME/Library/Application Support/BraveSoftware/Brave-Browser" \
            "chrome|$HOME/Library/Application Support/Google/Chrome" \
            "chromium|$HOME/Library/Application Support/Chromium" \
            "Microsoft Edge|$HOME/Library/Application Support/Microsoft Edge" \
            "Vivaldi|$HOME/Library/Application Support/Vivaldi"
    else
        printf '%s\n' \
            "brave|$HOME/.config/BraveSoftware/Brave-Browser" \
            "brave|$HOME/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser" \
            "chrome|$HOME/.config/google-chrome" \
            "chrome|$HOME/.var/app/com.google.Chrome/config/google-chrome" \
            "chromium|$HOME/.config/chromium" \
            "chromium|$HOME/.var/app/org.chromium.Chromium/config/chromium" \
            "Microsoft Edge|$HOME/.config/microsoft-edge" \
            "Vivaldi|$HOME/.config/vivaldi"
    fi
}

esohub_cookie_firefox_roots() {
    if [ "$OS_TYPE" = Darwin ]; then
        printf '%s\n' "$HOME/Library/Application Support/Firefox/Profiles"
    else
        printf '%s\n' "$HOME/.mozilla/firefox" "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox"
    fi
}

esohub_cookie_key() {
    local label="$1" pw=""
    if [ "$OS_TYPE" = Darwin ]; then
        pw=$(security find-generic-password -ws "$label Safe Storage" 2>/dev/null)
    else
        local app
        case "$label" in
            brave) app=brave ;;
            chrome) app=chrome ;;
            chromium) app=chromium ;;
            "Microsoft Edge") app=chrome ;;
            Vivaldi) app=vivaldi ;;
            *) app=chrome ;;
        esac
        command -v secret-tool > /dev/null 2>&1 && pw=$(secret-tool lookup application "$app" 2>/dev/null)
    fi
    [ -n "$pw" ] && { printf '%s' "$pw"; return 0; }
    printf 'peanuts'
}

esohub_cookie_decrypt() {
    local hexblob="$1" pw="$2" iters prefix cthex keyhex plainhex n core cand
    command -v python3 > /dev/null 2>&1 || return 1
    command -v openssl > /dev/null 2>&1 || return 1
    if [ "$OS_TYPE" = Darwin ]; then iters=1003; else iters=1; fi
    prefix="${hexblob:0:6}"
    case "$prefix" in 763130|763131) cthex="${hexblob:6}" ;; *) return 1 ;; esac
    keyhex=$(PW="$pw" IT="$iters" python3 -I -c 'import os,hashlib;print(hashlib.pbkdf2_hmac("sha1",os.environ["PW"].encode(),b"saltysalt",int(os.environ["IT"]),16).hex())' 2>/dev/null)
    case "$keyhex" in ''|*[!0-9a-f]*) return 1 ;; esac
    plainhex=$(printf '%s' "$cthex" | xxd -r -p 2>/dev/null | openssl enc -d -aes-128-cbc -K "$keyhex" -iv 20202020202020202020202020202020 -nopad 2>/dev/null | xxd -p 2>/dev/null | tr -d '\n')
    case "$plainhex" in ''|*[!0-9a-f]*) return 1 ;; esac
    [ "${#plainhex}" -ge 4 ] || return 1
    n=$(( 16#${plainhex:$((${#plainhex}-2))} ))
    [ "$n" -ge 1 ] && [ "$n" -le 16 ] && [ $(( n*2 )) -le "${#plainhex}" ] && core="${plainhex:0:$((${#plainhex}-n*2))}" || core="$plainhex"
    cand=$(printf '%s' "${core:64}" | xxd -r -p 2>/dev/null)
    esohub_cf_clean_cookie "$cand" 2>/dev/null && return 0
    cand=$(printf '%s' "$core" | xxd -r -p 2>/dev/null)
    esohub_cf_clean_cookie "$cand" 2>/dev/null && return 0
    return 1
}

esohub_cookie_ua_guess() {
    local root="$1" ver major
    [ -n "$ESOHUB_CF_UA" ] && { printf '%s' "$ESOHUB_CF_UA"; return 0; }
    ver=$(head -c 40 "$root/Last Version" 2>/dev/null | tr -d '\r\n')
    major="${ver%%.*}"
    case "$major" in ''|*[!0-9]*) return 1 ;; esac
    if [ "$OS_TYPE" = Darwin ]; then
        printf 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/%s.0.0.0 Safari/537.36' "$major"
    else
        printf 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/%s.0.0.0 Safari/537.36' "$major"
    fi
}

esohub_cookie_from_db() {
    local db="$1" label="$2" tmp hexblob pw ck
    [ -f "$db" ] || return 1
    tmp="${TEMP_DIR:-/tmp}/lttc_ck.$$"
    cp "$db" "$tmp" 2>/dev/null || return 1
    hexblob=$(sqlite3 "file:$tmp?immutable=1" "SELECT hex(encrypted_value) FROM cookies WHERE name='cf_clearance' AND host_key LIKE '%eso-hub.com' ORDER BY length(encrypted_value) DESC LIMIT 1;" 2>/dev/null)
    rm -f "$tmp" 2>/dev/null
    case "$hexblob" in ''|*[!0-9A-Fa-f]*) return 1 ;; esac
    pw=$(esohub_cookie_key "$label")
    ck=$(esohub_cookie_decrypt "$hexblob" "$pw") || return 1
    printf '%s' "$ck"
}

esohub_cookie_from_firefox() {
    local db="$1" tmp val
    [ -f "$db" ] || return 1
    tmp="${TEMP_DIR:-/tmp}/lttc_ffck.$$"
    cp "$db" "$tmp" 2>/dev/null || return 1
    val=$(sqlite3 "file:$tmp?immutable=1" "SELECT value FROM moz_cookies WHERE name='cf_clearance' AND host LIKE '%eso-hub.com' ORDER BY expiry DESC LIMIT 1;" 2>/dev/null)
    rm -f "$tmp" 2>/dev/null
    esohub_cf_clean_cookie "$val" 2>/dev/null
}

esohub_cookie_fetch() {
    command -v sqlite3 > /dev/null 2>&1 || return 1
    local line label root db ck ua
    while IFS='|' read -r label root; do
        [ -d "$root" ] || continue
        for db in "$root"/*/Network/Cookies "$root"/*/Cookies; do
            [ -f "$db" ] || continue
            if ck=$(esohub_cookie_from_db "$db" "$label"); then
                ua=$(esohub_cookie_ua_guess "$root") || continue
                ua=$(esohub_cf_clean_ua "$ua") || continue
                ESOHUB_CF_CLEARANCE="$ck"; ESOHUB_CF_UA="$ua"; CONFIG_CHANGED=true
                write_ttc_log "INFO" "ESO-Hub cf_clearance read from the local browser cookie store ($label)."
                return 0
            fi
        done
    done <<EOF
$(esohub_cookie_roots)
EOF
    if [ -n "$ESOHUB_CF_UA" ]; then
        for root in $(esohub_cookie_firefox_roots); do
            [ -d "$root" ] || continue
            for db in "$root"/*/cookies.sqlite; do
                [ -f "$db" ] || continue
                if ck=$(esohub_cookie_from_firefox "$db"); then
                    ESOHUB_CF_CLEARANCE="$ck"; ESOHUB_CF_UA="$ESOHUB_CF_UA"; CONFIG_CHANGED=true
                    write_ttc_log "INFO" "ESO-Hub cf_clearance read from the local browser cookie store (firefox)."
                    return 0
                fi
            done
        done
    fi
    return 1
}
download_if_missing() {
    local a_name="$1"; local a_id="$2"; local skip_var="$3"
    if [ "${!skip_var}" = true ]; then return 1; fi
    
    if [ ! -d "$ADDON_DIR/$a_name" ]; then
        local ans="y"
        if [ ! -f "/etc/os-release" ] || ! grep -qi "steamos" "/etc/os-release"; then
            echo -ne "\n \e[33m[?] $a_name is missing. Download it? (y/N):\e[0m "
            read -r ans < /dev/tty
        fi
        
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            start_spinner "Downloading $a_name from ESOUI..."
            
            if esoui_download "$a_id" "$TEMP_DIR_ROOT/${a_name}.zip"; then
                unzip -q -o "$TEMP_DIR_ROOT/${a_name}.zip" -d "$ADDON_DIR/" > /dev/null 2>&1
                rm -f "$TEMP_DIR_ROOT/${a_name}.zip"
                
                if [ "$a_name" = "TamrielTradeCentre" ]; then
                    TTC_LAST_CHECK=0
                    CONFIG_CHANGED=true
                fi
                
                if [ "$a_name" = "LibEsoHubPrices" ]; then
                    local loc_ver
                    loc_ver=$(esohub_local_version "$ADDON_DIR/LibEsoHubPrices" "LibEsoHubPrices")
                    if [ -n "$loc_ver" ]; then
                        EH_LOC_7="$loc_ver"
                        CONFIG_CHANGED=true
                    fi
                fi
                
                stop_spinner 0 "$a_name installed"
                
                local settings_file="$ADDON_DIR/../AddOnSettings.txt"
                if [ -f "$settings_file" ]; then
                    if [ "$a_name" = "EsoTradingHub" ]; then
                        sed -i.bak -e "s/^EsoTradingHub 0/EsoTradingHub 1/g" \
                               -e "s/^EsoHubScanner 0/EsoHubScanner 1/g" \
                               -e "s/^LibEsoHubPrices 0/LibEsoHubPrices 1/g" \
                               "$settings_file" 2>/dev/null
                        grep -q "^EsoTradingHub " "$settings_file" || echo "EsoTradingHub 1" >> "$settings_file"
                        grep -q "^EsoHubScanner " "$settings_file" || echo "EsoHubScanner 1" >> "$settings_file"
                        grep -q "^LibEsoHubPrices " "$settings_file" || echo "LibEsoHubPrices 1" >> "$settings_file"
                    elif [ "$a_name" = "HarvestMap" ] || [ "$a_name" = "HarvestMapData" ]; then
                        sed -i.bak -e "s/^HarvestMap 0/HarvestMap 1/g" \
                               -e "s/^HarvestMapData 0/HarvestMapData 1/g" \
                               "$settings_file" 2>/dev/null
                        grep -q "^HarvestMap " "$settings_file" || echo "HarvestMap 1" >> "$settings_file"
                        grep -q "^HarvestMapData " "$settings_file" || echo "HarvestMapData 1" >> "$settings_file"
                    else
                        sed -i.bak -e "s/^$a_name 0/$a_name 1/g" "$settings_file" 2>/dev/null
                        grep -q "^$a_name " "$settings_file" || echo "$a_name 1" >> "$settings_file"
                    fi
                    rm -f "$settings_file.bak" 2>/dev/null
                fi
                return 0
            else
                stop_spinner 1 "$a_name download failed"
                return 1
            fi
        else
            ui_echo " \e[90mUser Declined download of $a_name. Will not ask again.\e[0m"
            printf -v "$skip_var" "true"
            write_lttc_config
            return 1
        fi
    fi
    return 0
}

ADDON_UPDATE_EXCLUDE="HarvestMapData EsoTradingHub EsoHubScanner LibEsoHubPrices"
ADDON_UPDATE_INTERVAL=21600
ADDON_BOM="$(printf '\357\273\277')"

addon_local_list() {
    local dir="$1" top d rel name mf av ver
    for top in "$dir"/*/; do
        top="${top%/}"
        [ -L "$top" ] && continue
        while IFS= read -r d; do
            rel="${d#"$dir"/}"; name="${d##*/}"
            mf="$d/$name.addon"; [ -f "$mf" ] || mf="$d/$name.txt"; [ -f "$mf" ] || continue
            av=$(LC_ALL=C sed "1s/^$ADDON_BOM//" "$mf" | LC_ALL=C grep -a -m1 -i '^##[[:space:]]*AddOnVersion:' | tr -d '\r' \
                | tr -d '|' | sed 's/^[^:]*:[[:space:]]*//' | awk '{ print $1 }')
            ver=$(LC_ALL=C sed "1s/^$ADDON_BOM//" "$mf" | LC_ALL=C grep -a -m1 -i '^##[[:space:]]*Version:' | tr -d '\r|' \
                | sed 's/^[^:]*:[[:space:]]*//; s/[[:space:]]*$//')
            printf '%s|%s|%s\n' "$rel" "$av" "$ver"
        done <<< "$(find "$top" -maxdepth 3 -type d 2>/dev/null)"
    done
}

addon_update_plan() {
    LC_ALL=C awk -F'|' -v skip="$ADDON_UPDATE_EXCLUDE ${ADDON_UPDATE_SKIP:-}" -v records="${3:-}" '
    function jstr(s, key,   p, i, c, out) {
        p = index(s, "\"" key "\":\"")
        if (p == 0) return ""
        i = p + length(key) + 4; out = ""
        while (i <= length(s)) {
            c = substr(s, i, 1)
            if (c == "\\") {
                c = substr(s, i + 1, 1)
                if (c == "u") { if (tolower(substr(s, i + 2, 4)) != "feff") out = out "?"; i += 6; continue }
                out = out c; i += 2; continue
            }
            if (c == "\"") break
            out = out c; i++
        }
        return out
    }
    function dotted(v) { return v ~ /^[vV]?[0-9]+(\.[0-9]+)*$/ }
    function parts(v,   x) { sub(/^[vV]/, "", v); return split(v, x, ".") }
    function newer(a, b,   x, y, na, nb, n, i, p, q) {
        sub(/^[vV]/, "", a); sub(/^[vV]/, "", b)
        na = split(a, x, /[^0-9]+/); nb = split(b, y, /[^0-9]+/)
        n = (na > nb) ? na : nb
        for (i = 1; i <= n; i++) { p = x[i] + 0; q = y[i] + 0; if (p > q) return 1; if (p < q) return 0 }
        return 0
    }
    function vnorm(v) { sub(/^[vV]/, "", v); return v }
    function listing(s,   id, title, lver, lu, a, rest, p, nxt, obj, path, av, npaths, nt, k, f, score, mine, all) {
        if (!match(s, /"id":[0-9]+/)) return
        if (s ~ /"categoryId":157[,}]/) return
        id = substr(s, RSTART + 5, RLENGTH - 5)
        lu = match(s, /"lastUpdate":[0-9]+/) ? substr(s, RSTART + 13, RLENGTH - 13) : ""
        title = tolower(jstr(s, "title"))
        lver = jstr(s, "version")
        a = index(s, "\"addons\":[")
        if (a == 0) return
        rest = substr(s, a); npaths = 0; nt = 0; all = ""
        while ((p = index(rest, "\"path\":\"")) > 0) {
            rest = substr(rest, p)
            path = jstr(rest, "path")
            nxt = index(substr(rest, 9), "\"path\":\"")
            obj = (nxt > 0) ? substr(rest, 1, nxt + 7) : rest
            av = jstr(obj, "addOnVersion")
            npaths++
            all = all path "=" av "\n"
            if (index(path, "/") == 0) { nt++; tp[nt] = path; tav[nt] = av }
            rest = substr(rest, 9)
        }
        paths_of[id] = all
        for (k = 1; k <= nt; k++) {
            f = tp[k]
            if (!(f in local_av) || (f in skipped)) continue
            score = (npaths == 1 ? 2 : 0) + (title == tolower(f) ? 1 : 0)
            mine = ((tav[k] != "" && tav[k] == local_av[f]) || (lver != "" && vnorm(lver) == vnorm(local_ver[f]))) ? 1 : 0
            if (!(f in best_id) || score > best_score[f] || (score == best_score[f] && (mine > best_mine[f] || (mine == best_mine[f] && lu + 0 > best_lu[f] + 0)))) {
                best_id[f] = id; best_score[f] = score; best_mine[f] = mine; best_ver[f] = lver; best_tav[f] = tav[k]; best_lu[f] = lu
            }
        }
    }
    BEGIN {
        n = split(skip, sk, " "); for (i = 1; i <= n; i++) skipped[sk[i]] = 1
        if (records != "") {
            while ((getline line < records) > 0) { split(line, r, "|"); rec_id[r[1]] = r[2]; rec_lu[r[1]] = r[3] }
            close(records)
        }
    }
    FNR == NR { local_av[$1] = $2; local_ver[$1] = $3; next }
    {
        gsub(/\},\{"id":/, "}\n{\"id\":")
        nl = split($0, L, "\n")
        for (li = 1; li <= nl; li++) listing(L[li])
    }
    END {
        for (f in best_id) {
            id = best_id[f]; state = ""; lshow = local_av[f]; rshow = best_tav[f]
            np = split(paths_of[id], pl, "\n")
            for (i = 1; i <= np; i++) {
                if (pl[i] == "") continue
                eq = index(pl[i], "="); path = substr(pl[i], 1, eq - 1); ra = substr(pl[i], eq + 1)
                if (path != f && index(path, f "/") != 1) continue
                if (!(path in local_av)) continue
                la = local_av[path]
                if (la ~ /^[0-9]+$/ && ra ~ /^[0-9]+$/) {
                    if (ra + 0 > la + 0) { state = "UPDATE"; lshow = la; rshow = ra; break }
                    if (state == "") { state = "CURRENT"; if (path == f) { lshow = la; rshow = ra } }
                } else if (dotted(la) && dotted(ra) && parts(la) == parts(ra)) {
                    if (newer(ra, la)) { state = "UPDATE"; lshow = la; rshow = ra; break }
                    if (state == "") { state = "CURRENT"; if (path == f) { lshow = la; rshow = ra } }
                }
            }
            lv = local_ver[f]; rv = best_ver[f]
            if (state == "" && (f in rec_id) && rec_id[f] == id && best_lu[f] != "") {
                state = (best_lu[f] + 0 > rec_lu[f] + 0) ? "UPDATE" : "CURRENT"; lshow = lv; rshow = rv
            }
            if (state == "" && rv != "" && (vnorm(lv) == vnorm(rv) || vnorm(local_av[f]) == vnorm(rv))) { state = "CURRENT"; lshow = rv; rshow = rv }
            if (state == "") {
                if (dotted(lv) && dotted(rv) && parts(lv) == parts(rv)) { state = newer(rv, lv) ? "UPDATE" : "CURRENT"; lshow = lv; rshow = rv }
                else { state = "UNKNOWN"; lshow = (local_av[f] != "" ? local_av[f] : lv); rshow = (best_tav[f] != "" ? best_tav[f] : rv) }
            }
            print state "|" id "|" f "|" lshow "|" rshow "|" best_lu[f]
        }
    }' "$1" "$2" | LC_ALL=C sort -t'|' -k3,3
}

install_addon_zip() {
    local zip="$1" work="$TEMP_DIR_ROOT/addon_update" d name ex installed=""
    rm -rf "$work"; mkdir -p "$work"
    unzip -q -o "$zip" -d "$work" >/dev/null 2>&1 || { rm -rf "$work"; return 1; }
    mkdir -p "$TARGET_DIR/Backups/AddOns"
    for d in "$work"/*/; do
        d="${d%/}"; name="${d##*/}"
        [ -d "$d" ] || continue
        for ex in $ADDON_UPDATE_EXCLUDE ${ADDON_UPDATE_SKIP:-}; do [ "$name" = "$ex" ] && continue 2; done
        [ -L "$ADDON_DIR/$name" ] && continue
        rm -rf "$TARGET_DIR/Backups/AddOns/$name"
        [ -d "$ADDON_DIR/$name" ] && mv "$ADDON_DIR/$name" "$TARGET_DIR/Backups/AddOns/$name" && touch "$TARGET_DIR/Backups/AddOns/$name"
        if mv "$d" "$ADDON_DIR/$name"; then
            installed="$installed $name"
            write_ttc_log "INFO" "Add-on updated: $name"
        elif [ -d "$TARGET_DIR/Backups/AddOns/$name" ]; then
            mv "$TARGET_DIR/Backups/AddOns/$name" "$ADDON_DIR/$name"
        fi
    done
    rm -rf "$work"
    ADDON_INSTALLED="$installed"
    [ -n "$installed" ]
}

ADDON_RECORDS="${DB_DIR:-.}/LTTC_AddonUpdates.db"

record_addon_install() {
    local id="$1" lu="$2" name
    [ -n "$lu" ] || return 0
    touch "$ADDON_RECORDS"
    for name in $ADDON_INSTALLED; do
        awk -F'|' -v n="$name" '$1 != n' "$ADDON_RECORDS" > "$ADDON_RECORDS.tmp" && mv -f "$ADDON_RECORDS.tmp" "$ADDON_RECORDS"
        printf '%s|%s|%s\n' "$name" "$id" "$lu" >> "$ADDON_RECORDS"
    done
}

ADDON_BACKUP_DAYS=30

prune_addon_backups() {
    local dir="$TARGET_DIR/Backups/AddOns" old
    [ -d "$dir" ] || return 0
    find "$dir" -mindepth 1 -maxdepth 1 -type d -mmin +$(( ADDON_BACKUP_DAYS * 1440 )) 2>/dev/null | while IFS= read -r old; do
        rm -rf "$old"
        write_ttc_log "INFO" "Add-on backup older than ${ADDON_BACKUP_DAYS} days removed: ${old##*/}"
    done
}

run_addon_updates() {
    prune_addon_backups
    [ "$ENABLE_ADDON_UPDATES" = true ] || return 0
    [ -d "$ADDON_DIR" ] || return 0
    ui_echo "\e[1m\e[97m [+] Updating Your Add-Ons & Libraries \e[0m"
    local now since
    now=$(date +%s); since=$((now - ${ADDON_LAST_CHECK:-0}))
    if [ "$since" -lt "$ADDON_UPDATE_INTERVAL" ] && [ "$since" -ge 0 ]; then
        ui_echo " \e[90mChecked $(( since / 60 )) minutes ago. Next check in $(( (ADDON_UPDATE_INTERVAL - since) / 60 )) minutes.\e[0m\n"
        return 0
    fi

    local catalog="$TEMP_DIR_ROOT/esoui_filelist.json" locals="$TEMP_DIR_ROOT/addon_local.lst" plan
    start_spinner "Reading the ESOUI add-on list..."
    if ! curl -s -f -m 120 -A "$ESOUI_UA" -o "$catalog" "$ESOUI_API/v4/game/ESO/filelist.json" </dev/null; then
        stop_spinner 1 "Could not reach ESOUI"
        NOTIF_ADDONS="Check Failed"
        rm -f "$catalog"; echo ""; return 0
    fi
    addon_local_list "$ADDON_DIR" > "$locals"
    plan=$(addon_update_plan "$locals" "$catalog" "$ADDON_RECORDS")
    rm -f "$catalog" "$locals"
    stop_spinner 0 "Compared $(printf '%s\n' "$plan" | grep -c '|') add-ons with ESOUI"
    ADDON_LAST_CHECK="$now"; CONFIG_CHANGED=true

    local updates ids id line folder lv rv count=0 failed=0
    updates=$(printf '%s\n' "$plan" | grep '^UPDATE|')
    if [ -z "$updates" ]; then
        ui_echo " \e[90mNo changes detected. \e[92mAll add-ons are up-to-date.\e[0m\n"
        NOTIF_ADDONS="Up-to-date"
        return 0
    fi

    while IFS='|' read -r _ id folder lv rv _; do
        ui_echo " \e[33m$folder\e[0m $(version_diff "$lv" "$rv")"
    done <<< "$updates"
    printf '%s\n' "$plan" | grep '^UNKNOWN|' | while IFS='|' read -r _ id folder lv rv _; do
        write_ttc_log "INFO" "Add-on update skipped for $folder: its version ($lv) can't be compared with ESOUI's ($rv)."
    done

    ids=$(printf '%s\n' "$updates" | cut -d'|' -f2 | awk '!seen[$0]++')
    for id in $ids; do
        folder=$(printf '%s\n' "$updates" | awk -F'|' -v i="$id" '$2 == i { print $3; exit }')
        start_spinner "Downloading $folder from ESOUI..."
        TEMP_DIR_USED=true
        if esoui_download "$id" "$TEMP_DIR_ROOT/addon_$id.zip" && install_addon_zip "$TEMP_DIR_ROOT/addon_$id.zip"; then
            stop_spinner 0 "Installed:$ADDON_INSTALLED"
            count=$((count + 1))
            record_addon_install "$id" "$(printf '%s\n' "$updates" | awk -F'|' -v i="$id" '$2 == i { print $6; exit }')"
            case " $ADDON_INSTALLED " in
                *" TamrielTradeCentre "*) TTC_LAST_CHECK=0 ;;
            esac
        else
            stop_spinner 1 "Update failed for $folder"
            write_ttc_log "WARN" "Add-on update failed for $folder: ESOUI file $id could not be downloaded or installed."
            failed=$((failed + 1))
        fi
        rm -f "$TEMP_DIR_ROOT/addon_$id.zip"
    done
    NOTIF_ADDONS="Updated ($count)"
    [ "$failed" -gt 0 ] && NOTIF_ADDONS="$NOTIF_ADDONS, Failed ($failed)"
    ui_echo ""
}
SELF_UPDATE_INTERVAL=21600
GH_SELF_API="${LTTC_SELF_GH_API:-https://api.github.com}"
GH_SELF_REPO="MPHONlC/Cross-platform-Tamriel-Trade-Center-HarvestMap-ESO-Hub-Auto-Updater"
GH_SELF_ASSET="Tamriel_Trade_Center_Auto-Updater.zip"

github_self_details() {
    GH_SELF_VERSION=""; GH_SELF_URL=""
    local resp tag
    resp=$(curl -fsS -m 20 -H "Accept: application/vnd.github+json" "$GH_SELF_API/repos/$GH_SELF_REPO/releases/latest" < /dev/null 2>/dev/null) || return 1
    tag=$(printf '%s' "$resp" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/')
    GH_SELF_VERSION="${tag#Version-}"
    GH_SELF_URL=$(printf '%s' "$resp" | grep -o '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\(http[^"]*\)"$/\1/' | grep "$GH_SELF_ASSET" | head -n 1)
    [ -n "$GH_SELF_VERSION" ] && [ -n "$GH_SELF_URL" ]
}

self_update_install() {
    local src="${1:-esoui}" gh_url="$2"
    local zip="$TEMP_DIR_ROOT/self_update.zip" work="$TEMP_DIR_ROOT/self_update" new new_ver dest tmp
    SELF_NEW_VERSION=""
    rm -rf "$work"; mkdir -p "$work"
    local rc
    if [ "$src" = github ]; then
        rm -f "$zip"
        curl -fsSL -m 120 -A "${RAND_UA:-TTC-Updater}" -o "$zip" "$gh_url" < /dev/null 2>/dev/null; rc=$?
        [ "$rc" -eq 0 ] && [ -s "$zip" ] || rc=1
    else
        esoui_download "$ESOUI_SELF_ID" "$zip"; rc=$?
    fi
    if [ "$rc" -ne 0 ]; then rm -rf "$work"; return "$rc"; fi
    unzip -q -o "$zip" -d "$work" >/dev/null 2>&1
    rm -f "$zip"
    new=$(find "$work" -type f -name "$SCRIPT_NAME" | head -n 1)
    if [ -z "$new" ] || ! bash -n "$new" 2>/dev/null; then rm -rf "$work"; return 2; fi
    new_ver=$(grep -m1 -o 'APP_VERSION="[^"]*"' "$new" | cut -d'"' -f2)
    if [ -z "$new_ver" ] || ! version_newer "$new_ver" "$APP_VERSION"; then rm -rf "$work"; return 3; fi

    for dest in "$TARGET_DIR/$SCRIPT_NAME" "$LTTC_SELF"; do
        [ -n "$dest" ] || continue
        tmp="$dest.new.$$"
        if cp "$new" "$tmp" 2>/dev/null && chmod +x "$tmp" && mv -f "$tmp" "$dest"; then
            write_ttc_log "INFO" "Self-update: installed v$new_ver at $dest"
        else
            rm -f "$tmp"
        fi
    done
    rm -rf "$work"
    SELF_NEW_VERSION="$new_ver"
    return 0
}

self_update_check() {
    [ "$AUTO_SELF_UPDATE" = false ] && return 0
    [ "$ENABLE_LOCAL_MODE" = true ] && return 0
    [ -n "$LTTC_DEV" ] && return 0
    local now since
    now=$(date +%s); since=$((now - ${SELF_LAST_CHECK:-0}))
    if [ "$since" -lt "$SELF_UPDATE_INTERVAL" ] && [ "$since" -ge 0 ]; then return 0; fi
    SELF_LAST_CHECK="$now"; write_lttc_config

    ESOUI_VERSION=""
    esoui_details "$ESOUI_SELF_ID" || write_ttc_log "WARN" "Self-update: could not reach ESOUI."
    github_self_details || write_ttc_log "WARN" "Self-update: could not reach GitHub."

    local best_ver="$APP_VERSION" best_src="" best_url=""
    if [ -n "$ESOUI_VERSION" ] && version_newer "$ESOUI_VERSION" "$best_ver"; then best_ver="$ESOUI_VERSION"; best_src="esoui"; best_url=""; fi
    if [ -n "$GH_SELF_VERSION" ] && version_newer "$GH_SELF_VERSION" "$best_ver"; then best_ver="$GH_SELF_VERSION"; best_src="github"; best_url="$GH_SELF_URL"; fi
    [ -z "$best_src" ] && return 0

    start_spinner "Updating the updater to $best_ver (from $best_src)..."
    if self_update_install "$best_src" "$best_url"; then
        stop_spinner 0 "Updated to v$SELF_NEW_VERSION, restarting"
        release_instance_lock
        trap - EXIT SIGHUP SIGINT SIGTERM
        exec bash "$LTTC_SELF" "${LTTC_ARGS[@]}"
    else
        stop_spinner 1 "Update to $best_ver failed, keeping v$APP_VERSION"
    fi
}
IS_DESKTOP=false; FORCE_SETUP=false
if [ "$#" -gt 0 ]; then HAS_ARGS=true; fi
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --silent) SILENT=true; IS_TASK=true ;;
        --auto) AUTO_PATH=true ;;
        --na) AUTO_SRV="1" ;;
        --eu) AUTO_SRV="2" ;;
        --both) AUTO_SRV="3" ;;
        --loop) AUTO_MODE="2" ;;
        --once) AUTO_MODE="1" ;;
        --task) IS_TASK=true; SILENT=true ;;
        --steam) IS_STEAM_LAUNCH=true ;;
        --addon-dir) shift; ADDON_DIR="$1" ;;
        --setup) rm -f "$CONFIG_FILE"; SETUP_COMPLETE=false; FORCE_SETUP=true ;;
        --desktop) IS_DESKTOP=true ;;
    esac
    shift
done

if [ "$IS_STEAM_LAUNCH" = false ] && [ "$IS_TASK" = false ]; then SILENT=false; fi
if [ "$IS_STEAM_LAUNCH" = true ] && [ "$SILENT" = true ]; then ENABLE_NOTIFS=true; fi

_d() {
    local h="$1" s="$2" o="" i b
    for (( i = 0; i < ${#h}; i += 2 )); do
        s=$(( (s * 73 + 41) % 256 ))
        b=$(( 16#${h:i:2} ^ s ))
        o="${o}$(printf "\\$(printf '%03o' "$b")")"
    done
    printf '%s' "$o"
}

push_sys_notif() {
    local msg="$1"
    if [ "$ENABLE_NOTIFS" = "false" ]; then return; fi
    local safe_msg="${msg//\"/\\\"}" safe_title="${APP_TITLE//\"/\\\"}"
    osascript -e "display notification \"$safe_msg\" with title \"$safe_title\"" 2>/dev/null \
        || write_ttc_log "WARN" "macOS notification failed; allow notifications for Script Editor in System Settings"
}

open_url() {
    open "$1" > /dev/null 2>&1 &
    return 0
}

get_active_terminal() {
    echo "Terminal"
}

find_addon_folder() {
    local p
    p="$HOME/Documents/Elder Scrolls Online/live/AddOns"
    if [ -d "$p" ]; then echo "$p"; return 0; fi
    echo ""
}

wizard_first_run() {
    clear
    echo -e "\n\e[0;33m--- Initial Setup & Configuration ---\e[0m"
    
    if [ "$CURRENT_DIR" != "$TARGET_DIR" ]; then
        cp "$LTTC_SELF" "$TARGET_DIR/$SCRIPT_NAME" 2>/dev/null
        chmod +x "$TARGET_DIR/$SCRIPT_NAME"
        echo -e "\e[0;32m[+] Script copied to Documents: \e[0;35m$TARGET_DIR\e[0m"
    else
        echo -e "\e[0;36m-> Script is already running from the Documents folder.\e[0m\n"
    fi

    echo -e "\n\e[0;33m1. Which server do you play on? \e[0;32m(For TTC Updates)\e[0m"
    echo "1) North America (NA)"
    echo "2) Europe (EU)"
    echo "3) Both (NA & EU)"
    read -p $'\e[0;34mChoice [1-3]: \e[0m' AUTO_SRV

    echo -e "\n\e[0;33m2. Do you want the terminal to be visible on Steam launch?\e[0m"
    echo -e "1) Show Terminal \e[38;5;212m(Default: Verbose output)\e[0m"
    echo -e "2) Hide Terminal \e[0;90m(Invisible background hidden)\e[0m"
    read -p $'\e[0;34mChoice [1-2]: \e[0m' term_choice
    [ "$term_choice" == "2" ] && SILENT=true || SILENT=false

    echo -e "\n\e[0;33m3. How should the script run during gameplay?\e[0m"
    echo "1) Run once and close immediately"
    echo -e "2) Loop continuously \e[0;32m(Default: Checks every 60 minutes)\e[0m"
    read -p $'\e[0;34mChoice [1-2]: \e[0m' AUTO_MODE
    [ -z "$AUTO_MODE" ] && AUTO_MODE="2"

    echo -e "\n\e[0;33m4. Extract & Display Data \e[0;35m(Requires Database)\e[0m"
    echo -e "\e[0;32mExtract and display item sales on the terminal?\e[0m"
    echo -e "1) Yes \e[38;5;212m(Default: Build Database)\e[0m"
    echo -e "2) No \e[0;90m(Just upload the files instantly)\e[0m"
    read -p $'\e[0;34mChoice [1-2]: \e[0m' display_choice
    [ "$display_choice" == "2" ] && ENABLE_DISPLAY=false || ENABLE_DISPLAY=true

    echo -e "\n\e[0;33m5. Addon Folder Location\e[0m"
    if [ -n "$ADDON_DIR" ] && [ -d "$ADDON_DIR" ]; then
        echo -e "\e[0;32m[+] Found Saved Addons Directory: \e[0;35m$ADDON_DIR\e[0m"
        FOUND_ADDONS="$ADDON_DIR"
    else
        echo -e "\e[0;34mScanning default locations for Addons folder...\e[0m"
        FOUND_ADDONS=$(find_addon_folder)
        if [ -n "$FOUND_ADDONS" ]; then
            echo -e "\e[0;32m[+] Found Addons folder at: \e[0;35m$FOUND_ADDONS\e[0m"
            read -p "Is this the correct location? (y/N): " use_found
            if [[ ! "$use_found" =~ ^[Yy]$ ]]; then
                read -p $'\e[0;34mEnter full custom path to AddOns folder: \e[0m' FOUND_ADDONS
            fi
        else
            echo -e "\e[0;31m[-] Could not find AddOns automatically.\e[0m"
            read -p $'\e[0;34mEnter full custom path to AddOns folder: \e[0m' FOUND_ADDONS
        fi
    fi
    ADDON_DIR="$FOUND_ADDONS"

    echo -e "\n\e[0;33m6. Enable Native System Notifications?\e[0m"
    echo -e "1) Yes \e[38;5;212m(Summarizes updates, respects Do Not Disturb)\e[0m"
    echo -e "2) No \e[0;32m(Default)\e[0m"
    read -p $'\e[0;34mChoice [1-2]: \e[0m' notif_choice
    [ "$notif_choice" == "1" ] && ENABLE_NOTIFS=true || ENABLE_NOTIFS=false

    echo -e "\n\e[0;33m7. Logging Level\e[0m"
    echo -e "Creates a log file at \e[0;35m$LOG_FILE\e[0m"
    echo -e "1) Simple Logging \e[0;32m(Default: records script events)\e[0m"
    echo -e "2) Detailed Logging \e[0;31m(WARNING: records item extractions, pruned history, file deletions)\e[0m"
    read -p $'\e[0;34mChoice [1-2]: \e[0m' log_choice
    [ "$log_choice" == "2" ] && LOG_MODE="detailed" || LOG_MODE="simple"
    touch "$LOG_FILE" 2>/dev/null

    echo -e "\n\e[0;33m8. ESO-Hub Integration \e[0;32m(Optional)\e[0m"
    echo -e "\n\e[0;31m(DO NOT SHARE YOUR TOKENS TO ANYONE)\e[0m"
    echo -e "1) Log in through your browser \e[0;32m(Fetches Login Token securely, no password typed here)\e[0m"
    echo -e "2) Log in with Username and Password \e[0;32m(Fetches Login Token securely)\e[0m"
    echo -e "3) Skip / \e[0;90mUpload Anonymously No Login\e[0m \e[0;32m(Default)\e[0m"
    read -p $'\e[0;34mChoice [1-3]: \e[0m' eh_choice
    
    EH_USER_TOKEN=""
    if [ "$eh_choice" == "1" ]; then
        echo -e "\n\e[36mLogging in to ESO-Hub through your browser...\e[0m"
        esohub_code_login
        EH_USER_TOKEN="$ESOHUB_TOKEN"; ESOHUB_TOKEN=""
        if [ -n "$EH_USER_TOKEN" ]; then
            echo -e "\e[0;32m[+] Logged in${ESOHUB_LOGIN_USER:+ as $ESOHUB_LOGIN_USER}! Login Token saved securely.\e[0m"
        else
            echo -e "\e[0;31m[-] Login failed: $ESOHUB_LOGIN_FAIL. Falling back to anonymous mode.\e[0m"
        fi
    elif [ "$eh_choice" == "2" ]; then
        read -p "ESO-Hub Username: " EH_USER
        echo -n "ESO-Hub Password: "
        EH_PASS=""
        while IFS= read -r -s -n1 char; do
            if [[ -z $char ]]; then echo; break; fi
            if [[ $char == $'\177' || $char == $'\b' ]]; then
                if [[ -n $EH_PASS ]]; then
                    EH_PASS="${EH_PASS%?}"
                    echo -en "\b \b"
                fi
            else
                EH_PASS+="$char"
                echo -n "*"
            fi
        done
        
        echo -e "\n\e[36mAuthenticating with ESO-Hub API...\e[0m"
        if ! esohub_request_token "$EH_USER" "$EH_PASS" && [ "$ESOHUB_LOGIN_BLOCKED" = true ]; then
            echo -e "\e[0;33m[-] ESO-Hub's server answered the login with a Cloudflare check.\e[0m"
            if esohub_cf_prompt; then
                echo -e "\e[36mAuthenticating with ESO-Hub API...\e[0m"
                esohub_request_token "$EH_USER" "$EH_PASS"
            fi
        fi
        EH_USER=""; EH_PASS=""
        EH_USER_TOKEN="$ESOHUB_TOKEN"; ESOHUB_TOKEN=""
        
        if [ -n "$EH_USER_TOKEN" ]; then
            echo -e "\e[0;32m[+] Successfully logged in! Login Token saved securely.\e[0m"
        else
            echo -e "\e[0;31m[-] Login failed: $ESOHUB_LOGIN_FAIL. Falling back to anonymous mode.\e[0m"
        fi
    fi

    echo -e "\n\e[0;32mWhen ESO-Hub needs its Cloudflare check again, read cf_clearance from your browser automatically?\e[0m"
    echo -e "\e[0;90m(Reads only ESO-Hub's own cookie from Brave, Chrome, Edge, Vivaldi, Chromium or Firefox, keeps it on this PC, and falls back to copy-paste if it can't.)\e[0m"
    echo -e "1) Yes"
    echo -e "2) No \e[0;32m(Default)\e[0m"
    read -p $'\e[0;34mChoice [1-2]: \e[0m' eh_cookie_choice
    [ "$eh_cookie_choice" == "1" ] && ESOHUB_COOKIE_IMPORT=true || ESOHUB_COOKIE_IMPORT=false

    echo -e "\n\e[0;33m9. Keep Your Other Add-Ons Up To Date \e[0;32m(Optional)\e[0m"
    echo -e "\e[0;32mAlso check ESOUI for newer versions of the add-ons and libraries in your AddOns folder and install them?\e[0m"
    echo -e "\e[0;90m(Checks every 6 hours, keeps the previous version in $TARGET_DIR/Backups/AddOns, skips linked folders)\e[0m"
    echo -e "1) Yes"
    echo -e "2) No \e[0;32m(Default)\e[0m"
    read -p $'\e[0;34mChoice [1-2]: \e[0m' addon_update_choice
    [ "$addon_update_choice" == "1" ] && ENABLE_ADDON_UPDATES=true || ENABLE_ADDON_UPDATES=false

    local q=10
    if aom_installed; then
        echo -e "\n\e[0;33m$q. APH-OnManager Data \e[0;32m(Optional)\e[0m"
        aom_question
        read -p $'\e[0;34mChoice [1-2]: \e[0m' aom_choice
        aom_set_answer "$aom_choice"
        q=$((q + 1))
    fi

    SETUP_COMPLETE=true; write_lttc_config

    echo -e "\n\e[0;33m$q. Desktop Shortcut\e[0m"
    echo -e "Creates a shortcut at \e[0;35m$HOME/Desktop\e[0m"
    read -p "Create a desktop shortcut? (Y/n): " make_shortcut
    [ -z "$make_shortcut" ] && make_shortcut="y"
    
    SHORTCUT_SRV_FLAG="--na"
    [ "$AUTO_SRV" == "2" ] && SHORTCUT_SRV_FLAG="--eu"
    [ "$AUTO_SRV" == "3" ] && SHORTCUT_SRV_FLAG="--both"
    LOOP_FLAG="--once"
    [ "$AUTO_MODE" == "2" ] && LOOP_FLAG="--loop"

    rm -f "$HOME/Desktop/"*Tamriel_Trade_Center*.command 2>/dev/null
    if [[ "$make_shortcut" =~ ^[Yy]$ ]]; then
        mkdir -p "$HOME/Desktop"
        DESKTOP_FILE="$HOME/Desktop/${OS_BRAND}_Tamriel_Trade_Center.command"
        cat <<EOF > "$DESKTOP_FILE"
#!/bin/bash
exec "$TARGET_DIR/$SCRIPT_NAME" $SHORTCUT_SRV_FLAG $LOOP_FLAG --desktop
EOF
        chmod +x "$DESKTOP_FILE"
        echo -e "\e[0;32m[+] macOS desktop shortcut installed (double-click it to open in Terminal).\e[0m"
    fi

    TERM_CMD=$(get_active_terminal)
    echo -e "\n\e[0;92m================ SETUP COMPLETE ================\e[0m"
    echo -e "Copy this string into your \e[1mSteam Launch Options\e[0m:\n"
    
    DETACHED_CMD="nohup bash -c '$TARGET_DIR/$SCRIPT_NAME $SHORTCUT_SRV_FLAG $LOOP_FLAG --silent --steam' >/dev/null 2>&1 & %command%"

    if [ "$SILENT" = true ]; then
        echo -e "\e[0;104m $DETACHED_CMD \e[0m\n"
    else
        LAUNCH_CMD="osascript -e 'tell application \"Terminal\" to do script \"\\\"$TARGET_DIR/$SCRIPT_NAME\\\" $SHORTCUT_SRV_FLAG $LOOP_FLAG --steam\"' & %command%"
        echo -e "\e[0;104m $LAUNCH_CMD \e[0m\n"
    fi
    
    echo -e "\e[0;33m$((q + 1)). Steam Launch Options\e[0m"
    echo -e "\e[0;32mAutomatically inject the Launch Command into Steam?\e[0m"
    echo -e "\e[31m(WARNING: Steam MUST be closed to do this.)\e[0m"
    read -p "Apply automatically? (Y/n): " auto_steam
    [ -z "$auto_steam" ] && auto_steam="y"
    
    if [[ "$auto_steam" =~ ^[Yy]$ ]] && ! command -v perl >/dev/null 2>&1; then
        echo -e "\e[0;33m[!] perl is not installed, so the launch options can't be added for you. Paste the line above into Steam > ESO > Properties > Launch Options.\e[0m"
        auto_steam="n"
    fi
    if [[ "$auto_steam" =~ ^[Yy]$ ]]; then
        STEAM_PIDS=$(pgrep -x "steam_osx|Steam")
        if [ -n "$STEAM_PIDS" ]; then
            ui_echo "\e[0;33m[!] Steam is running. Closing Steam to inject options...\e[0m"
            osascript -e 'quit app "Steam"' > /dev/null 2>&1
            sleep 5
            pkill -x "steam_osx|Steam" > /dev/null 2>&1
        fi
        
        export LAUNCH_STR="$LAUNCH_CMD"
        [ "$SILENT" = true ] && export LAUNCH_STR="$DETACHED_CMD"

        BACKUP_DIR="$TARGET_DIR/Backups"; mkdir -p "$BACKUP_DIR"
        
        for conf in "$HOME/Library/Application Support/Steam/userdata"/*/config/localconfig.vdf; do
            if [ -f "$conf" ]; then
                TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
                STEAM_ID=$(basename "$(dirname "$(dirname "$conf")")")
                BACKUP_FILE="$BACKUP_DIR/localconfig_${STEAM_ID}_${TIMESTAMP}.vdf"
                cp "$conf" "$BACKUP_FILE" 2>/dev/null
                ui_echo "\e[0;36m-> Backed up Steam config to: $BACKUP_FILE\e[0m"
                ui_echo "\e[0;36m-> Injecting Launch Options into ESO config (AppID: 306130)...\e[0m"
                
                if perl -pi.bak -e '
                    BEGIN{undef $/;} 
                    sub lttc_merge { my ($cur, $ls) = @_; (my $pfx = $ls) =~ s{\s*%command%\s*$}{}i; my @keep; for my $s (split m{\s+&(?=\s|$)}, $cur) { $s =~ s{\s*(?:osascript\s+-e|nohup\s+bash\s+-c)\b.*Tamriel_Trade_Center.*$}{}s; $s =~ s{^\s+|\s+$}{}g; push @keep, $s if length $s; } my $n = grep { m{%command%}i } @keep; @keep = grep { !(m{^%command%$}i && $n-- > 1) } @keep; my $rest = join " & ", @keep; return $rest eq "" ? "$pfx %command%" : ($rest =~ m{%command%}i ? "$pfx $rest" : "$pfx %command% $rest"); }
                    my $ls=$ENV{LAUNCH_STR}; $ls=~s/\\/\\\\/g; $ls=~s/"/\\"/g; 
                    if (/"306130"\s*\{/) { 
                        if (s/("306130"\s*\{[^}]*"LaunchOptions"\s*)"((?:\\"|[^"])*)"/$1 . "\"" . lttc_merge($2, $ls) . "\""/se) {} 
                        else { s/("306130"\s*\{)/$1\n\t\t\t\t"LaunchOptions"\t\t"$ls"/s; } 
                    } else { 
                        s/("apps"\s*\{)/$1\n\t\t\t"306130"\n\t\t\t{\n\t\t\t\t"LaunchOptions"\t\t"$ls"\n\t\t\t}/s; 
                    }' "$conf" 2>/dev/null; then
                    ui_echo "\e[0;32m[+] Successfully injected Launch Options into Steam!\e[0m"
                else
                    ui_echo "\e[0;31m[-] Perl injection failed for $conf\e[0m"
                fi
                rm -f "$conf.bak" 2>/dev/null
            fi
        done
        
        ui_echo "\e[0;33m[!] Restarting Steam...\e[0m"
        
        open -a Steam "steam://open/main" 2>/dev/null || open "steam://open/main" 2>/dev/null
        
        ui_echo "\e[0;36m-> Verifying Steam launch...\e[0m"
        steam_started=false
        for i in {1..10}; do
            if pgrep -x "steam_osx|Steam" > /dev/null 2>&1; then
                steam_started=true; break
            fi
            sleep 1
        done
        
        if [ "$steam_started" = true ]; then
            ui_echo "\e[0;32m[+] Steam launched successfully.\e[0m"
        else
            ui_echo "\e[0;31m[-] Could not verify Steam is running.\e[0m"
        fi
    fi
    
    write_ttc_log "INFO" "User successfully completed the setup wizard."
    if ! read -p $'\e[38;5;212mPress Enter to start the updater now...\e[0m'; then
        echo -e "\nUser Closed The Terminal. Exiting safely."; exit 0
    fi
    SILENT=false
}

awk_time_formatter='
{
    while (match($0, /\[TS:([0-9]+)\]/)) {
        ts = substr($0, RSTART+4, RLENGTH-5) + 0; diff = now - ts
        if (diff < 0) diff = 0
        if (diff < 60) { rel = diff (diff == 1 ? " second ago" : " seconds ago") }
        else if (diff < 3600) { v = int(diff/60); rel = v (v==1 ? " minute ago" : " minutes ago") }
        else if (diff < 86400) { v = int(diff/3600); rel = v (v==1 ? " hour ago" : " hours ago") }
        else { v = int(diff/86400); rel = v (v==1 ? " day ago" : " days ago") }
        pre = substr($0, 1, RSTART-1); post = substr($0, RSTART+RLENGTH)
        $0 = pre "[\033[90m" rel "\033[0m]" post
    }
    print $0
}'

print_dynamic_log() {
    local file="$1"
    if [ -s "$file" ]; then awk -v now="$(date +%s)" "$awk_time_formatter" "$file"; fi
}

ui_echo() {
    if [ "$SILENT" = false ]; then
        echo -e "$1" | awk -v now="$(date +%s)" "$awk_time_formatter"
        echo -e "$1" >> "$UI_STATE_FILE"
    fi
}

is_addon_active() {
    local addon="$1"
    local os_log_id="(macOS)"

    if [ ! -d "$ADDON_DIR/$addon" ]; then 
        write_ttc_log "INFO" "is_addon_active: $addon not present in addon folder $os_log_id"
        echo "false"
        return
    fi

    if [ -f "$ADDON_SETTINGS_FILE" ]; then
        if grep -qw "$addon" "$ADDON_SETTINGS_FILE"; then 
            write_ttc_log "INFO" "is_addon_active: $addon enabled in AddOnSettings.txt $os_log_id"
            echo "true"
        else 
            write_ttc_log "INFO" "is_addon_active: $addon not listed in AddOnSettings.txt $os_log_id"
            echo "false"
        fi
    else
        if [ -d "$ADDON_DIR/$addon" ]; then 
            write_ttc_log "INFO" "is_addon_active: $addon present (no AddOnSettings.txt) $os_log_id"
            echo "true"
        else 
            write_ttc_log "INFO" "is_addon_active: $addon missing (no AddOnSettings.txt) $os_log_id"
            echo "false"
        fi
    fi
}

get_relative_time() {
    local ts=$1; local now=$(date +%s); local diff=$((now - ts))
    if (( diff < 60 )); then (( diff == 1 )) && echo "1 second ago" || echo "$diff seconds ago"
    elif (( diff < 3600 )); then local m=$((diff / 60)); (( m == 1 )) && echo "1 minute ago" || echo "$m minutes ago"
    elif (( diff < 86400 )); then local h=$((diff / 3600)); (( h == 1 )) && echo "1 hour ago" || echo "$h hours ago"
    else local d=$((diff / 86400)); (( d == 1 )) && echo "1 day ago" || echo "$d days ago"; fi
}

format_date() {
    local ts="$1"
    date -r "$ts" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "Unknown Date"
}

version_diff() {
    local old="$1" new="$2" no nn min pre=0 suf=0
    no=${#old}; nn=${#new}; min=$no; [ "$nn" -lt "$min" ] && min=$nn
    while [ "$pre" -lt "$min" ] && [ "${old:pre:1}" = "${new:pre:1}" ]; do pre=$((pre + 1)); done
    while [ "$suf" -lt $((min - pre)) ] && [ "${old:$((no - 1 - suf)):1}" = "${new:$((nn - 1 - suf)):1}" ]; do suf=$((suf + 1)); done
    local opre="${old:0:pre}" omid="${old:pre:$((no - pre - suf))}" osuf="${old:$((no - suf))}" nmid="${new:pre:$((nn - pre - suf))}"
    printf '\e[0m%s\e[31m%s\e[0m%s \e[90m->\e[0m \e[0m%s\e[92m%s\e[0m%s' "$opre" "$omid" "$osuf" "$opre" "$nmid" "$osuf"
}

age_short() {
    local s="$1"
    [ "$s" -lt 0 ] 2>/dev/null && s=0
    if [ "$s" -ge 86400 ]; then echo "$((s / 86400))d $(((s % 86400) / 3600))h"
    elif [ "$s" -ge 3600 ]; then echo "$((s / 3600))h $(((s % 3600) / 60))m"
    elif [ "$s" -ge 60 ]; then echo "$((s / 60))m"
    else echo "${s}s"; fi
}

size_human() {
    local b="$1"
    if [ "$b" -ge 1048576 ]; then printf '%d.%d MB' "$((b / 1048576))" "$(((b % 1048576) * 10 / 1048576))"
    elif [ "$b" -ge 1024 ]; then printf '%d.%d KB' "$((b / 1024))" "$(((b % 1024) * 10 / 1024))"
    else printf '%d B' "$b"; fi
}

count_history_uids() {
    awk -F'|' '
    $1 == "HISTORY" {
        if ($NF ~ /^[0-9]+$/) src = $(NF - 1); else src = $NF
        if (src ~ /^(Unknown|\[Unknown\])$/ || src == "") src = "TTC"
        u = $6 "|" $3 "|" $4 "|" $5 "|" src
        if (!(u in seen)) { seen[u] = 1; c++ }
    }
    END { print c + 0 }
    ' "$1" 2>/dev/null
}
master_kiosk_logic='
k_dict["0"] = "Belkarth|309.702%3B339.015"
k_dict["1"] = "Belkarth Outlaws Refuge|397.782%3B384.003"
k_dict["2"] = "The Hollow City|335.049%3B502.183"
k_dict["3"] = "Haj Uxith|664.037%3B1686.503"
k_dict["4"] = "Court of Contempt|1194.908%3B1257.149"
k_dict["5"] = "Rawl\047kha|479.207%3B636.837"
k_dict["6"] = "Rawl\047kha Outlaws Refuge|501.386%3B452.438"
k_dict["7"] = "Vinedusk|397.082%3B865.97"
k_dict["8"] = "Dune|398.415%3B310.5"
k_dict["9"] = "Baandari Trading Post|834.059%3B700.203"
k_dict["10"] = "Dra\047bul|588.829%3B888.956"
k_dict["11"] = "Valeguard|1173.63%3B785.94"
k_dict["12"] = "Velyn Harbor Outlaws Refuge|494.732%3B274.696"
k_dict["13"] = "Marbruk|772.277%3B700.203"
k_dict["14"] = "Marbruk Outlaws Refuge|424.395%3B351.686"
k_dict["15"] = "Verrant Morass|995.35%3B581.739"
k_dict["16"] = "Greenheart|1110.89%3B1729.019"
k_dict["17"] = "Elden Root|620.197%3B682.777"
k_dict["18"] = "Elden Root Outlaws Refuge|177.267%3B314.617"
k_dict["19"] = "Cormount|1107.491%3B528.163"
k_dict["20"] = "Southpoint|884.46%3B1541.567"
k_dict["21"] = "Skywatch|141.782%3B486.342"
k_dict["22"] = "Firsthold|758.349%3B436.227"
k_dict["23"] = "Vulkhel Guard|692.355%3B701.774"
k_dict["24"] = "Vulkhel Guard Outlaws Refuge|360.712%3B403.013"
k_dict["25"] = "Mistral|499.801%3B563.965"
k_dict["26"] = "Evermore|753.425%3B448.638"
k_dict["27"] = "Evermore Outlaws Refuge|483.326%3B521.825"
k_dict["28"] = "Bangkorai Pass|931.328%3B1085.287"
k_dict["29"] = "Hallin\047s Stand|948.118%3B736.639"
k_dict["30"] = "Sentinel|474.455%3B887.134"
k_dict["31"] = "Sentinel Outlaws Refuge|272.316%3B447.686"
k_dict["32"] = "Morwha\047s Bounty|592.539%3B1337.948"
k_dict["33"] = "Bergama|1141.733%3B1237.474"
k_dict["34"] = "Shornhelm|555.722%3B825.034"
k_dict["35"] = "Shornhelm Outlaws Refuge|340.752%3B381.151"
k_dict["36"] = "Hoarfrost Downs|441.188%3B755.649"
k_dict["37"] = "Oldgate|947.927%3B1525.045"
k_dict["38"] = "Wayrest|412.673%3B609.906"
k_dict["39"] = "Wayrest Outlaws Refuge|420.594%3B446.735"
k_dict["40"] = "Firebrand Keep|605.813%3B736.682"
k_dict["41"] = "Koeglin Village|693.069%3B470.5"
k_dict["42"] = "Daggerfall|480.792%3B389.708"
k_dict["43"] = "Daggerfall Outlaws Refuge|435.801%3B402.062"
k_dict["44"] = "Lion Guard Redoubt|1275.731%3B538.132"
k_dict["45"] = "Wyrd Tree|832.354%3B1161.648"
k_dict["46"] = "Stonetooth|490.296%3B845.946"
k_dict["47"] = "Port Hunding|181.386%3B872.876"
k_dict["48"] = "Riften|417.584%3B947.964"
k_dict["49"] = "Riften Outlaws Refuge|295.128%3B405.864"
k_dict["50"] = "Nimalten|666.138%3B594.064"
k_dict["51"] = "Fallowstone Hall|640.792%3B556.045"
k_dict["52"] = "Windhelm|700.99%3B492.678"
k_dict["53"] = "Windhelm Outlaws Refuge|166.811%3B380.201"
k_dict["54"] = "Voljar Meadery|867.256%3B695.033"
k_dict["55"] = "Fort Amol|265.346%3B96.639"
k_dict["56"] = "Stormhold|628.118%3B535.451"
k_dict["57"] = "Stormhold Outlaws Refuge|317.94%3B351.686"
k_dict["58"] = "Venomous Fens|459.7%3B777.556"
k_dict["59"] = "Hissmir|650.118%3B1092.45"
k_dict["60"] = "Mournhold|845.148%3B860.203"
k_dict["61"] = "Mournhold Outlaws Refuge|305.584%3B515.171"
k_dict["62"] = "Tal\047Deic Grounds|1711.712%3B946.019"
k_dict["63"] = "Muth Gnaar Hills|502.25%3B1153.052"
k_dict["64"] = "Ebonheart|497.425%3B647.608"
k_dict["65"] = "Kragenmoor|596.435%3B643.173"
k_dict["66"] = "Davon\047s Watch|886.336%3B834.856"
k_dict["67"] = "Davon\047s Watch Outlaws Refuge|520.395%3B345.983"
k_dict["68"] = "Dhalmora|514.059%3B814.262"
k_dict["69"] = "Bleakrock|699.5%3B622.905"
k_dict["70"] = "Orsinium|659.801%3B510.104"
k_dict["71"] = "Orsinium Outlaws Refuge|402.534%3B339.33"
k_dict["72"] = "Morkul Stronghold|472.871%3B359.609"
k_dict["73"] = "Thieves Den|381.623%3B287.052"
k_dict["74"] = "Abah\047s Landing|575.841%3B795.253"
k_dict["75"] = "Anvil|525.148%3B590.896"
k_dict["76"] = "Kvatch|631.287%3B551.292"
k_dict["77"] = "Anvil Outlaws Refuge|489.029%3B453.389"
k_dict["78"] = "Vivec City|290.692%3B475.253"
k_dict["79"] = "Vivec City Outlaws Refuge|311.287%3B630.181"
k_dict["80"] = "Sadrith Mora|401.584%3B806.342"
k_dict["81"] = "Balmora|659.801%3B953.668"
k_dict["82"] = "Brass Fortress|622.747%3B787.782"
k_dict["83"] = "Brass Fortress Outlaws Refuge|677.227%3B486.656"
k_dict["84"] = "Lillandril|605.94%3B787.332"
k_dict["85"] = "Shimmerene|368.921%3B881.274"
k_dict["86"] = "Alinor|735.841%3B682.777"
k_dict["87"] = "Alinor Outlaws Refuge|398.732%3B280.399"
k_dict["88"] = "Lilmoth|580.593%3B646.342"
k_dict["89"] = "Lilmoth Outlaws Refuge|256.158%3B478.102"
k_dict["90"] = "Rimmen|282.772%3B620.995"
k_dict["91"] = "Rimmen Outlaws Refuge|448.158%3B273.745"
k_dict["92"] = "Senchal|518.811%3B518.025"
k_dict["93"] = "Senchal Outlaws Refuge|338.851%3B420.122"
k_dict["94"] = "Solitude|441.197%3B426.611"
k_dict["95"] = "Solitude Outlaws Refuge|286.574%3B319.369"
k_dict["96"] = "Markarth|745.346%3B782.579"
k_dict["97"] = "Markarth Outlaws Refuge|298.93%3B496.161"
k_dict["98"] = "Leyawiin|539.405%3B864.955"
k_dict["99"] = "Leyawiin Outlaws Refuge|389.227%3B463.844"
k_dict["100"] = "Fargrave|881.584%3B312.084"
k_dict["101"] = "Fargrave Outlaws Refuge|244.752%3B440.082"
k_dict["102"] = "Gonfalon Bay|430.098%3B486.342"
k_dict["103"] = "Gonfalon Bay Outlaws Refuge|599.287%3B235.726"
k_dict["104"] = "Vastyr|905.346%3B723.965"
k_dict["105"] = "Vastyr Outlaws Refuge|477.623%3B533.231"
k_dict["106"] = "Necrom|700.99%3B667.543"
k_dict["107"] = "Necrom Outlaws Refuge|520.395%3B410.617"
k_dict["108"] = "Skingrad|419.009%3B733.47"
k_dict["109"] = "Skingrad Outlaws Refuge|372.118%3B457.191"
k_dict["110"] = "Sunport|640.792%3B796.837"
k_dict["111"] = "Sunport Outlaws Refuge|551.762%3B402.062"

k_dict["Lejesha"] = "Bergama Wayshrine - Alik\047r Desert|30"
k_dict["Manidah"] = "Morwha\047s Bounty Wayshrine - Alik\047r Desert|30"
k_dict["Laknar"] = "Sentinel - Alik\047r Desert|83"
k_dict["Saymimah"] = "Sentinel - Alik\047r Desert|83"
k_dict["Uurwaerion"] = "Sentinel - Alik\047r Desert|83"
k_dict["Vinder Hlaran"] = "Sentinel - Alik\047r Desert|83"
k_dict["Yat"] = "Sentinel - Alik\047r Desert|83"
k_dict["Panersewen"] = "Firsthold Wayshrine - Auridon|143"
k_dict["Cerweriell"] = "Skywatch - Auridon|545"
k_dict["Ferzhela"] = "Skywatch - Auridon|545"
k_dict["Guzg"] = "Skywatch - Auridon|545"
k_dict["Lanirsare"] = "Skywatch - Auridon|545"
k_dict["Renzaiq"] = "Skywatch - Auridon|545"
k_dict["Carillda"] = "Vulkhel Guard - Auridon|243"
k_dict["Galam Seleth"] = "Dhalmora - Bal Foyen|56"
k_dict["Malirzzaka"] = "Bangkorai Pass Wayshrine - Bangkorai|20"
k_dict["Arver Falos"] = "Evermore - Bangkorai|84"
k_dict["Tilinarie"] = "Evermore - Bangkorai|84"
k_dict["Values-Many-Things"] = "Evermore - Bangkorai|84"
k_dict["Kaale"] = "Evermore - Bangkorai|84"
k_dict["Zunlog"] = "Evermore - Bangkorai|84"
k_dict["Glorgzorgo"] = "Hallin\047s Stand - Bangkorai|360"
k_dict["Ghatrugh"] = "Stonetooth Fortress - Betnikh|649"
k_dict["Amirudda"] = "Leyawiin - Blackwood|1940"
k_dict["Dandras Omayn"] = "Leyawiin - Blackwood|1940"
k_dict["Lhotahir"] = "Leyawiin - Blackwood|1940"
k_dict["Sihrimaya"] = "Leyawiin - Blackwood|1940"
k_dict["Shuruthikh"] = "Leyawiin - Blackwood|1940"
k_dict["Praxedes Vestalis"] = "Leyawiin - Blackwood|1940"
k_dict["Inishez"] = "Bleakrock Wayshrine - Bleakrock Isle|74"
k_dict["Commerce Delegate"] = "Brass Fortress - Clockwork City|1348"
k_dict["Ravam Sedas"] = "Brass Fortress - Clockwork City|1348"
k_dict["Orstag"] = "Brass Fortress - Clockwork City|1348"
k_dict["Noveni Adrano"] = "Brass Fortress - Clockwork City|1348"
k_dict["Valowende"] = "Brass Fortress - Clockwork City|1348"
k_dict["Shogarz"] = "Brass Fortress - Clockwork City|1348"
k_dict["Harzdak"] = "Court of Contempt Wayshrine - Coldharbour|255"
k_dict["Shuliish"] = "Haj Uxith Wayshrine - Coldharbour|255"
k_dict["Nistyniel"] = "The Hollow City - Coldharbour|422"
k_dict["Ramzasa"] = "The Hollow City - Coldharbour|422"
k_dict["Balver Sarvani"] = "The Hollow City - Coldharbour|422"
k_dict["Virwillaure"] = "The Hollow City - Coldharbour|422"
k_dict["Donnaelain"] = "Belkarth - Craglorn|1131"
k_dict["Glegokh"] = "Belkarth - Craglorn|1131"
k_dict["Shelzaka"] = "Belkarth - Craglorn|1131"
k_dict["Keen-Eyes"] = "Belkarth - Craglorn|1131"
k_dict["Shuhasa"] = "Belkarth - Craglorn|1131"
k_dict["Nelvon Galen"] = "Belkarth - Craglorn|1131"
k_dict["Mengilwaen"] = "Belkarth - Craglorn|1131"
k_dict["Endoriell"] = "Mournhold - Deshaan|205"
k_dict["Through-Gilded-Eyes"] = "Mournhold - Deshaan|205"
k_dict["Zarum"] = "Mournhold - Deshaan|205"
k_dict["Gals Fendyn"] = "Mournhold - Deshaan|205"
k_dict["Razgugul"] = "Mournhold - Deshaan|205"
k_dict["Hayaia"] = "Mournhold - Deshaan|205"
k_dict["Erwurlde"] = "Mournhold - Deshaan|205"
k_dict["Feran Relenim"] = "Muth Gnaar Hills Wayshrine - Deshaan|13"
k_dict["Telvon Arobar"] = "Tal\047Deic Grounds Wayshrine - Deshaan|13"
k_dict["Muslabliz"] = "Fort Amol - Eastmarch|578"
k_dict["Alareth"] = "Voljar Meadery Wayshrine - Eastmarch|61"
k_dict["Alisewen"] = "Windhelm - Eastmarch|160"
k_dict["Celorien"] = "Windhelm - Eastmarch|160"
k_dict["Dosa"] = "Windhelm - Eastmarch|160"
k_dict["Deras Golathyn"] = "Windhelm - Eastmarch|160"
k_dict["Ghogurz"] = "Windhelm - Eastmarch|160"
k_dict["Bodsa Manas"] = "The Bazaar - Fargrave|2136"
k_dict["Furnvekh"] = "The Bazaar - Fargrave|2136"
k_dict["Livia Tappo"] = "The Bazaar - Fargrave|2136"
k_dict["Ven"] = "The Bazaar - Fargrave|2136"
k_dict["Vesakta"] = "The Bazaar - Fargrave|2136"
k_dict["Zenelaz"] = "The Bazaar - Fargrave|2136"
k_dict["Arzalaya"] = "Vastyr - Galen|2227"
k_dict["Sharflekh"] = "Vastyr - Galen|2227"
k_dict["Gei"] = "Vastyr - Galen|2227"
k_dict["Stephenn Surilie"] = "Vastyr - Galen|2227"
k_dict["Tildinfanya"] = "Vastyr - Galen|2227"
k_dict["Var the Vague"] = "Vastyr - Galen|2227"
k_dict["Sintilfalion"] = "Daggerfall - Glenumbra|63"
k_dict["Murgoz"] = "Daggerfall - Glenumbra|63"
k_dict["Khalatah"] = "Daggerfall - Glenumbra|63"
k_dict["Faedre"] = "Daggerfall - Glenumbra|63"
k_dict["Brara Hlaalo"] = "Daggerfall - Glenumbra|63"
k_dict["Nameel"] = "Lion Guard Redoubt Wayshrine - Glenumbra|63"
k_dict["Mogazgur"] = "Wyrd Tree Wayshrine - Glenumbra|63"
k_dict["Daynas Sadrano"] = "Anvil - Gold Coast|1074"
k_dict["Majhasur"] = "Anvil - Gold Coast|1074"
k_dict["Onurai-Maht"] = "Anvil - Gold Coast|1074"
k_dict["Erluramar"] = "Kvatch - Gold Coast|1064"
k_dict["Farul"] = "Kvatch - Gold Coast|1064"
k_dict["Zagh gro-Stugh"] = "Kvatch - Gold Coast|1064"
k_dict["Nirywy"] = "Cormount Wayshrine - Grahtwood|9"
k_dict["Fintilorwe"] = "Elden Root - Grahtwood|445"
k_dict["Walks-In-Leaves"] = "Elden Root - Grahtwood|445"
k_dict["Mizul"] = "Elden Root - Grahtwood|445"
k_dict["Iannianith"] = "Elden Root - Grahtwood|445"
k_dict["Bols Thirandus"] = "Elden Root - Grahtwood|445"
k_dict["Goh"] = "Elden Root - Grahtwood|445"
k_dict["Naifineh"] = "Elden Root - Grahtwood|445"
k_dict["Glothozug"] = "Southpoint Wayshrine - Grahtwood|9"
k_dict["Halash"] = "Greenheart Wayshrine - Greenshade|300"
k_dict["Camyaale"] = "Marbruk - Greenshade|387"
k_dict["Fendros Faryon"] = "Marbruk - Greenshade|387"
k_dict["Ghobargh"] = "Marbruk - Greenshade|387"
k_dict["Goudadul"] = "Marbruk - Greenshade|387"
k_dict["Hasiwen"] = "Marbruk - Greenshade|387"
k_dict["Seeks-Better-Deals"] = "Verrant Morass Wayshrine - Greenshade|300"
k_dict["Farvyn Rethan"] = "Abah\047s Landing - Hew\047s Bane|993"
k_dict["Gathewen"] = "Abah\047s Landing - Hew\047s Bane|993"
k_dict["Qanliz"] = "Abah\047s Landing - Hew\047s Bane|993"
k_dict["Shiny-Trades"] = "Abah\047s Landing - Hew\047s Bane|993"
k_dict["Snegbug"] = "Abah\047s Landing - Hew\047s Bane|993"
k_dict["Dahnadreel"] = "Thieves Den - Hew\047s Bane|1013"
k_dict["Innryk"] = "Gonfalon Bay - High Isle|2163"
k_dict["Kemshelar"] = "Gonfalon Bay - High Isle|2163"
k_dict["Marcelle Fanis"] = "Gonfalon Bay - High Isle|2163"
k_dict["Pugereau Laffoon"] = "Gonfalon Bay - High Isle|2163"
k_dict["Shakhrath"] = "Gonfalon Bay - High Isle|2163"
k_dict["Zoe Frernile"] = "Gonfalon Bay - High Isle|2163"
k_dict["Janne Jonnicent"] = "Gonfalon Bay Outlaws Refuge - High Isle|2169"
k_dict["Dulia"] = "Mistral - Khenarthi\047s Roost|567"
k_dict["Shamuniz"] = "Mistral - Khenarthi\047s Roost|567"
k_dict["Mani"] = "Baandari Trading Post - Malabal Tor|282"
k_dict["Murgrud"] = "Baandari Trading Post - Malabal Tor|282"
k_dict["Jalaima"] = "Baandari Trading Post - Malabal Tor|282"
k_dict["Nindenel"] = "Baandari Trading Post - Malabal Tor|282"
k_dict["Teromawen"] = "Baandari Trading Post - Malabal Tor|282"
k_dict["Ulyn Marys"] = "Dra\047bul Wayshrine - Malabal Tor|22"
k_dict["Kharg"] = "Valeguard Wayshrine - Malabal Tor|22"
k_dict["Aki-Osheeja"] = "Lilmoth - Murkmire|1560"
k_dict["Faelemar"] = "Lilmoth - Murkmire|1560"
k_dict["Ordasha"] = "Lilmoth - Murkmire|1560"
k_dict["Xokomar"] = "Lilmoth - Murkmire|1560"
k_dict["Mahadal at-Bergama"] = "Lilmoth - Murkmire|1560"
k_dict["Thaloril"] = "Lilmoth - Murkmire|1560"
k_dict["Maelanrith"] = "Rimmen - Northern Elsweyr|1576"
k_dict["Artura Pamarc"] = "Rimmen - Northern Elsweyr|1576"
k_dict["Razzamin"] = "Rimmen - Northern Elsweyr|1576"
k_dict["Nirshala"] = "Rimmen - Northern Elsweyr|1576"
k_dict["Adiblargo"] = "Rimmen - Northern Elsweyr|1576"
k_dict["Fortis Asina"] = "Rimmen - Northern Elsweyr|1576"
k_dict["Uzarrur"] = "Dune - Reaper\047s March|533"
k_dict["Muheh"] = "Rawl\047kha - Reaper\047s March|312"
k_dict["Shiniraer"] = "Rawl\047kha - Reaper\047s March|312"
k_dict["Heat-On-Scales"] = "Rawl\047kha - Reaper\047s March|312"
k_dict["Canda"] = "Rawl\047kha - Reaper\047s March|312"
k_dict["Ronuril"] = "Rawl\047kha - Reaper\047s March|312"
k_dict["Ambarys Teran"] = "Vinedusk Wayshrine - Reaper\047s March|256"
k_dict["Aldam Urvyn"] = "Hoarfrost Downs - Rivenspire|528"
k_dict["Fanwyearie"] = "Oldgate Wayshrine - Rivenspire|10"
k_dict["Frenidela"] = "Shornhelm - Rivenspire|85"
k_dict["Roudi"] = "Shornhelm - Rivenspire|85"
k_dict["Shakh"] = "Shornhelm - Rivenspire|85"
k_dict["Tendir Vlaren"] = "Shornhelm - Rivenspire|85"
k_dict["Vorh"] = "Shornhelm - Rivenspire|85"
k_dict["Talen-Dum"] = "Hissmir Wayshrine - Shadowfen|26"
k_dict["Emuin"] = "Stormhold - Shadowfen|217"
k_dict["Gasheg"] = "Stormhold - Shadowfen|217"
k_dict["Tar-Shehs"] = "Stormhold - Shadowfen|217"
k_dict["Vals Salvani"] = "Stormhold - Shadowfen|217"
k_dict["Zino"] = "Stormhold - Shadowfen|217"
k_dict["Junal-Nakal"] = "Venomous Fens Wayshrine - Shadowfen|26"
k_dict["Florentina Verus"] = "Solitude - Western Skyrim|1773"
k_dict["Gilur Vules"] = "Solitude - Western Skyrim|1773"
k_dict["Grobert Agnan"] = "Solitude - Western Skyrim|1773"
k_dict["Mandyl"] = "Solitude - Western Skyrim|1773"
k_dict["Ohanath"] = "Solitude - Western Skyrim|1773"
k_dict["Tuhdri"] = "Solitude - Western Skyrim|1773"
k_dict["Fanyehna"] = "Solitude Outlaws Refuge - Western Skyrim|1778"
k_dict["Glaetaldo"] = "Senchal - Southern Elsweyr|1675"
k_dict["Golgakul"] = "Senchal - Southern Elsweyr|1675"
k_dict["Jafinna"] = "Senchal - Southern Elsweyr|1675"
k_dict["Maguzak"] = "Senchal - Southern Elsweyr|1675"
k_dict["Saden Sarvani"] = "Senchal - Southern Elsweyr|1675"
k_dict["Wusava"] = "Senchal - Southern Elsweyr|1675"
k_dict["Tanur Llervu"] = "Davon\047s Watch - Stonefalls|24"
k_dict["Silver-Scales"] = "Ebonheart - Stonefalls|511"
k_dict["Gananith"] = "Ebonheart - Stonefalls|511"
k_dict["Luz"] = "Ebonheart - Stonefalls|511"
k_dict["J\047zaraer"] = "Ebonheart - Stonefalls|511"
k_dict["Urvel Hlaren"] = "Ebonheart - Stonefalls|511"
k_dict["Ma\047jidid"] = "Kragenmoor - Stonefalls|510"
k_dict["Dromash"] = "Firebrand Keep Wayshrine - Stormhaven|12"
k_dict["Aniama"] = "Koeglin Village - Stormhaven|532"
k_dict["Azarati"] = "Wayrest - Stormhaven|33"
k_dict["Morg"] = "Wayrest - Stormhaven|33"
k_dict["Atin"] = "Wayrest - Stormhaven|33"
k_dict["Tredyn Daram"] = "Wayrest - Stormhaven|33"
k_dict["Estilldo"] = "Wayrest - Stormhaven|33"
k_dict["Aerchith"] = "Wayrest - Stormhaven|33"
k_dict["Ah-Zish"] = "Wayrest - Stormhaven|33"
k_dict["Makmargo"] = "Port Hunding - Stros M\047Kai|530"
k_dict["Talwullaure"] = "Alinor - Summerset|1430"
k_dict["Irna Dren"] = "Alinor - Summerset|1430"
k_dict["Rubyn Denile"] = "Alinor - Summerset|1430"
k_dict["Yggurz Strongbow"] = "Alinor - Summerset|1430"
k_dict["Huzzin"] = "Alinor - Summerset|1430"
k_dict["Rialilrin"] = "Alinor - Summerset|1430"
k_dict["Ambalor"] = "Lillandril - Summerset|1455"
k_dict["Nowajan"] = "Lillandril - Summerset|1455"
k_dict["Quelilmor"] = "Shimmerene - Summerset|1455"
k_dict["Shargalash"] = "Shimmerene - Summerset|1455"
k_dict["Varandia"] = "Shimmerene - Summerset|1455"
k_dict["Rinedel"] = "Lillandril - Summerset|1455"
k_dict["Grudogg"] = "Necrom - Telvanni Peninsula|2343"
k_dict["Tuls Madryon"] = "Necrom - Telvanni Peninsula|2343"
k_dict["Alvura Thenim"] = "Necrom - Telvanni Peninsula|2343"
k_dict["Falani"] = "Necrom - Telvanni Peninsula|2343"
k_dict["Runethyne Brenur"] = "Necrom - Telvanni Peninsula|2343"
k_dict["Wyn Serpe"] = "Necrom - Telvanni Peninsula|2343"
k_dict["Thredis"] = "Necrom Outlaws Refuge - Telvanni Peninsula|2402"
k_dict["Dion Hassildor"] = "Leyawiin Outlaws Refuge - Blackwood|1999"
k_dict["Nardhil Barys"] = "Slag Town Outlaws Refuge - Clockwork City|1354"
k_dict["Tuxutl"] = "Fargrave Outlaws Refuge - Fargrave|2099"
k_dict["Virwen"] = "Abah\047s Landing - Hew\047s Bane|993"
k_dict["Begok"] = "Rimmen Outlaws Refuge - Northern Elsweyr|1575"
k_dict["Laytiva Sendris"] = "Senchal Outlaws Refuge - Southern Elsweyr|1679"
k_dict["Bodfira"] = "Markarth - The Reach|1858"
k_dict["Marilia Verethi"] = "Markarth - The Reach|1858"
k_dict["Atazha"] = "Vivec City - Vvardenfell|1287"
k_dict["Jena Calvus"] = "Vivec City - Vvardenfell|1287"
k_dict["Lorthodaer"] = "Vivec City - Vvardenfell|1287"
k_dict["Mauhoth"] = "Vivec City - Vvardenfell|1287"
k_dict["Rinami"] = "Vivec City - Vvardenfell|1287"
k_dict["Sebastian Brutya"] = "Vivec City - Vvardenfell|1287"
k_dict["Relieves-Burdens"] = "Vivec City Outlaws Refuge - Vvardenfell|1287"
k_dict["Narril"] = "Balmora - Vvardenfell|1290"
k_dict["Ginette Malarelie"] = "Balmora - Vvardenfell|1287"
k_dict["Mahrahdr"] = "Balmora - Vvardenfell|1290"
k_dict["Ruxultav"] = "Sadrith Mora - Vvardenfell|1288"
k_dict["Felayn Uvaram"] = "Sadrith Mora - Vvardenfell|1288"
k_dict["Runik"] = "Sadrith Mora - Vvardenfell|1288"
k_dict["Eralian"] = "Riften - The Rift|198"
k_dict["Arnyeana"] = "Riften - The Rift|198"
k_dict["Jeelus-Lei"] = "Riften - The Rift|198"
k_dict["Llether Nilem"] = "Riften - The Rift|198"
k_dict["Atheval"] = "Nimalten - The Rift|543"
k_dict["Borgrara"] = "Morkul Stronghold - Wrothgar|954"
k_dict["Henriette Panoit"] = "Morkul Stronghold - Wrothgar|954"
k_dict["Nagrul gro-Stugbaz"] = "Morkul Stronghold - Wrothgar|954"
k_dict["Oorgurn"] = "Morkul Stronghold - Wrothgar|954"
k_dict["Jee-Ma"] = "Orsinium - Wrothgar|895"
k_dict["Terorne"] = "Orsinium - Wrothgar|895"
k_dict["Narkhukulg"] = "Orsinium Outlaws Refuge - Wrothgar|927"
k_dict["Adzi-Dool"] = "Skingrad - West Weald|2514"
k_dict["Catro Catius"] = "Skingrad - West Weald|2514"
k_dict["Curinwe"] = "Skingrad - West Weald|2514"
k_dict["Ildare Berel"] = "Skingrad - West Weald|2514"
k_dict["Lucius Lento"] = "Skingrad - West Weald|2514"
k_dict["Otho Tatius"] = "Skingrad - West Weald|2514"
k_dict["Uraacil"] = "Vulkhel Guard Outlaws Refuge - Auridon|243"
k_dict["Naerorien"] = "Elden Root Outlaws Refuge - Grahtwood|445"
k_dict["Dugugikh"] = "Marbruk Outlaws Refuge - Greenshade|387"
k_dict["Galis Andalen"] = "Velyn Harbor Outlaws Refuge - Malabal Tor|282"
k_dict["Sharaddargo"] = "Rawl\047kha Outlaws Refuge - Reaper\047s March|312"
k_dict["Marbilah"] = "Sentinel Outlaws Refuge - Alik\047r Desert|83"
k_dict["Ornyenque"] = "Evermore Outlaws Refuge - Bangkorai|84"
k_dict["Zulgozu"] = "Daggerfall Outlaws Refuge - Glenumbra|63"
k_dict["Bixitleesh"] = "Shornhelm Outlaws Refuge - Rivenspire|85"
k_dict["Essilion"] = "Wayrest Outlaws Refuge - Stormhaven|33"
k_dict["Nakmargo"] = "Mournhold Outlaws Refuge - Deshaan|205"
k_dict["Meden Berendus"] = "Windhelm Outlaws Refuge - Eastmarch|160"
k_dict["Majdawa"] = "Riften Outlaws Refuge - The Rift|198"
k_dict["Geeh-Sakka"] = "Stormhold Outlaws Refuge - Shadowfen|217"
k_dict["Adagwen"] = "Davon\047s Watch Outlaws Refuge - Stonefalls|24"
k_dict["Makkhzahr"] = "Belkarth Outlaws Refuge - Craglorn|1131"
k_dict["Ushataga"] = "Skingrad Outlaws Refuge - West Weald|2514"

for (k in k_dict) {
    if (k ~ /^[0-9]+$/) {
        split(k_dict[k], parts, "|")
        loc_name = parts[1]; coord_str = parts[2]
        k_dict[k] = loc_name "||" coord_str
        best = ""
        for (t in k_dict) {
            if (t !~ /^[0-9]+$/) {
                split(k_dict[t], tparts, "|")
                t_loc = tparts[1]; t_map = tparts[2]
                if (index(t_loc, loc_name " - ") == 1 || index(t_loc, loc_name " Wayshrine") == 1 || t_loc == loc_name) {
                    k_dict[t] = t_loc "|" t_map "|" coord_str
                    if (best == "" || t < best) { best = t; best_val = t_loc "|" t_map "|" coord_str }
                }
            }
        }
        if (best != "") k_dict[k] = best_val
    }
}
'

master_color_logic='
function get_hq(q) {
    if(q==6)return "Mythic (Orange) 6"
    if(q==5)return "Legendary (Gold) 5"
    if(q==4)return "Epic (Purple) 4"
    if(q==3)return "Superior (Blue) 3"
    if(q==2)return "Fine (Green) 2"
    if(q==1)return "Normal (White) 1"
    return "Trash (Grey) 0"
}
function get_cat(n,i,s,v) {
    ln = tolower(n)
    if(ln~/motif/)return "Crafting Motif"
    if(ln~/blueprint|praxis|design|pattern|formula|diagram|sketch/)return "Furniture Plan"
    if(ln~/style page|runebox/)return "Style/Collectible"
    if(ln~/tea blends of tamriel|tin of high isle taffy|assorted stolen shiny trinkets/)return "Companion Gift"
    if(ln~/lightly used fiddle|stuffed bear|grisly trophy|companion gift/)return "Companion Gift"
    if(v>1||s>=20)return "Equipment (Armor/Weapon)"
    return "Materials/Misc"
}
function calc_quality(id, name, s, v) {
    ln = tolower(name)
    if(id~/^(165899|187648|171437|165910|175510|181971|181961|175402|184206|191067)$/) return 6
    if(ln~/citation|truly superb glyph|tempering alloy|dreugh wax|rosin|kuta|perfect roe/) return 5
    if(ln~/aetherial dust|chromium plating|style page:|runebox:|research scroll|psijic ambrosia/) return 5
    if(ln~/indoril inks:/) return 5
    if(ln~/master .* writ/) return 4
    if(ln~/unknown .* writ|welkynar binding|rekuta|grain solvent|mastic|elegant lining/) return 4
    if(ln~/zircon plating|potent nirncrux|fortified nirncrux|culanda lacquer|harvested soul fragment/) return 4
    if(ln~/tea blends of tamriel|twenty-year ruby port|assorted stolen shiny trinkets/) return 3
    if(ln~/lightly used fiddle|stuffed bear|grisly trophy|companion gift|tin of high isle taffy/) return 3
    if(ln~/angler\047s knife set|dried fish biscuits|beginner\047s bowfishing kit/) return 3
    if(ln~/survey report|dwarven oil|turpen|embroidery|iridium plating|treasure map|bervez juice|frost mirriam/) return 3
    if(ln~/hemming|honing stone|pitch|terne plating|soul gem/) return 2
    if(ln~/^(recipe|design|blueprint|pattern|praxis|formula|diagram|sketch):/) { 
        if(s==6) return 5; if(s==5) return 4; if(s==4) return 3; if(s==3) return 2; return 1 
    }
    if(s >= 2 && s <= 6) return s - 1
    if(s >= 20 && s <= 24) return s - 19
    if(s >= 25 && s <= 29) return s - 24
    if(s >= 30 && s <= 34) return s - 29
    if(s >= 236 && s <= 240) return s - 235
    if(s >= 241 && s <= 245) return s - 240
    if(s >= 254 && s <= 258) return s - 253
    if(s >= 259 && s <= 263) return s - 258
    if(s >= 272 && s <= 276) return s - 271
    if(s >= 277 && s <= 281) return s - 276
    if(s >= 290 && s <= 294) return s - 289
    if(s >= 295 && s <= 299) return s - 294
    if(s >= 305 && s <= 309) return s - 304
    if(s >= 308 && s <= 312) return s - 307
    if(s >= 313 && s <= 317) return s - 312
    if(s >= 361 && s <= 365) return s - 360
    if(s >= 51 && s <= 60) return 2
    if(s >= 61 && s <= 70) return 3
    if(s >= 71 && s <= 80) return 4
    if(s >= 81 && s <= 90) return 3
    if(s >= 91 && s <= 100) return 4
    if(s >= 101 && s <= 110) return 5
    if(s >= 111 && s <= 120) return 1
    if(s >= 125 && s <= 134) return 1
    if(s >= 135 && s <= 144) return 2
    if(s >= 145 && s <= 154) return 3
    if(s >= 155 && s <= 164) return 4
    if(s >= 165 && s <= 174) return 5
    if(s >= 39 && s <= 49) return 2
    if(s >= 229 && s <= 231) return s - 227
    if(s >= 232 && s <= 234) return s - 229
    if(s >= 250 && s <= 252) return s - 247
    if(s == 7) return 3; if(s == 8) return 4; if(s == 9) return 2
    if(s == 235 || s == 253) return 1
    if(s == 366) return 6
    if(s == 358) return 2
    if(s == 360) return 3
    return 1
}
'

clean_legacy_tags() {
    write_ttc_log "INFO" "clean_legacy_tags: sanitizing legacy DB files"
    local found_dirt=false
    for db in "$DB_FILE" "$DB_DIR/LTTC_History.db"; do
        if [ -f "$db" ] && grep -q "<title>" "$db"; then
            sed -i.bak -e 's/<title>UESP:ESO Item -- //g' \
                       -e 's/<title>ESO Item -- //g' \
                       -e 's/<\/title>//g' "$db" 2>/dev/null
            rm -f "${db}.bak" 2>/dev/null
            found_dirt=true
        fi
    done
    if [ "$found_dirt" = true ]; then
        write_ttc_log "INFO" "Sanitized legacy tags."
        echo -e " \e[92m[+] Cleaned legacy tags.\e[0m"
    fi
}
clean_legacy_tags

repair_missing_names() {
    write_ttc_log "INFO" "repair_missing_names: repairing DB entries with local SavedVariables"
    if [ ! -f "$DB_FILE" ]; then return; fi
    
    local tmp_db="$DB_FILE.repair"
    local missing_ids="$TEMP_DIR_ROOT/lttc_db_missing.tmp"
    local offline_dict="$TEMP_DIR_ROOT/offline_name_dict.tmp"
    
    awk -F'|' '$1 ~ /^[0-9]+$/ && (length($0) >= 6 ? $6 : $3) ~ /^Unknown Item \(/ { print $1 }' \
        "$DB_FILE" | tr -d '\r' > "$missing_ids"
        
    local missing_count=$(wc -l < "$missing_ids" 2>/dev/null)
    [ -z "$missing_count" ] && missing_count=0
    
    if (( missing_count > 0 )); then
        if [ "$SILENT" = false ]; then
            echo -e " \e[33m[!] Auto-Repair: Scanning local data for $missing_count unknown items...\e[0m"
        fi
        write_ttc_log "INFO" "Auto-Repair: Found $missing_count unknown items."
        
        grep -oE '\|H[^:]*:item:[0-9]+[^|]*\|h[^|]+\|h' "$SAVED_VAR_DIR/TamrielTradeCentre.lua" 2>/dev/null | \
        awk -F'\\|h' '{ 
            split($1, parts, ":")
            id = parts[3]; name = $2
            sub(/\^.*$/, "", name)
            if (id ~ /^[0-9]+$/ && name != "") print id "|" name 
        }' | sort -u > "$offline_dict"
        
        awk -F'|' -v OFS='|' -v lookup="$offline_dict" '
        '"$master_color_logic"'
        BEGIN {
            while ((getline line < lookup) > 0) {
                split(line, p, "|")
                names[p[1]] = p[2]
            }
            close(lookup)
        }
        {
            if ($1 ~ /^[0-9]+$/ && NF >= 6) {
                if ($6 ~ /^Unknown Item \(/ || $6 == "") {
                    if (names[$1] != "") {
                        $6 = names[$1]
                        real_qual = calc_quality($1, $6, $3+0, $4+0)
                        $2 = real_qual
                        $5 = get_hq(real_qual)
                        $7 = get_cat($6, $1, $3+0, $4+0)
                    }
                }
            }
            print $0
        }' "$DB_FILE" > "$tmp_db" 2>/dev/null
        
        if [ -s "$tmp_db" ]; then
            mv "$tmp_db" "$DB_FILE"
            if [ "$SILENT" = false ]; then
                echo -e " \e[92m[\0342\0234\0223]\e[0m Offline Database repair complete!"
            fi
            write_ttc_log "INFO" "Auto-Repair done."
        fi
    fi
    rm -f "$missing_ids" "$offline_dict" 2>/dev/null
}

awk_sort_logic='
function sort_num(a, n,    i, t) {
    for (i = int(n / 2) - 1; i >= 0; i--) sift_down(a, i, n)
    for (i = n - 1; i > 0; i--) { t = a[0]; a[0] = a[i]; a[i] = t; sift_down(a, 0, i) }
}
function sift_down(a, r, n,    c, t) {
    while ((c = 2 * r + 1) < n) {
        if (c + 1 < n && a[c + 1] > a[c]) c++
        if (a[r] >= a[c]) return
        t = a[r]; a[r] = a[c]; a[c] = t; r = c
    }
}
'

awk_browser_logic='
function name_enc(s) { gsub(/ /, "+", s); gsub(/'\''/, "%27", s); return s }
function ttc_url(name) { return "https://us.tamrieltradecentre.com/pc/Trade/SearchResult?SearchType=Sell&ItemNamePattern=" name_enc(name) }
function item_links(name, id,    u, out) {
    out = "\033[90m[\033]8;;" ttc_url(name) "\033\\TTC\033]8;;\033\\]\033[0m " \
          "\033[90m[\033]8;;https://eso-hub.com/en/trading/" id "\033\\ESO-Hub\033]8;;\033\\]\033[0m"
    if (name ~ /^(Blueprint|Praxis|Design|Pattern|Formula|Diagram|Sketch): /) {
        u = name; sub(/^[^:]+: /, "", u)
        gsub(/ /, "_", u); gsub(/'\''/, "%27", u)
        out = out " \033[90m[\033]8;;https://en.uesp.net/wiki/File:ON-furnishing-" u ".jpg\033\\UESP\033]8;;\033\\]\033[0m"
    } else if (name ~ /Crafting Motif/ || name ~ /Style Page:/) {
        u = name
        sub(/^.*Crafting Motif [^:]+: /, "", u)
        sub(/^.*Style Page: /, "", u)
        sub(/ (Axes|Belts|Boots|Bows|Chests|Daggers|Gloves|Helmets)$/, "", u)
        sub(/ (Legs|Maces|Shields|Shoulders|Staves|Swords|Cuirass)$/, "", u)
        sub(/ (Greaves|Helm|Pauldrons|Sabatons|Gauntlets|Bracers)$/, "", u)
        sub(/ (Epaulets|Jack|Guards|Belt|Shoes|Jerkin|Breeches|Hat)$/, "", u)
        sub(/ (Robes|Sash|Girdle|Corselet|Arm Cops)$/, "", u)
        sub(/ Style$/, "", u)
        gsub(/ /, "_", u); gsub(/'\''/, "%27", u)
        out = out " \033[90m[\033]8;;https://en.uesp.net/wiki/Online:" u "_Style\033\\UESP\033]8;;\033\\]\033[0m"
    }
    return out
}
function band_price(a, n,    trim, valid_n, ms, me, i, sum, c) {
    sort_num(a, n)
    trim = int(n * 0.10); if (trim == 0) trim = 1
    valid_n = n - (2 * trim); if (valid_n < 1) valid_n = 1
    ms = trim + int(valid_n * 0.45); me = trim + int(valid_n * 0.55)
    if (me < ms) me = ms
    sum = 0; c = 0
    for (i = ms; i <= me; i++) { sum += a[i]; c++ }
    return sum / c
}
function row_passes() {
    if (cutoff > 0 && $2 < cutoff) return 0
    if (src_filter != "" && index(tolower($13), src_filter) == 0) return 0
    if (t_user != "" && index(tolower($8), t_user) == 0 && index(tolower($9), t_user) == 0) return 0
    if (index($7, "Unknown Item (") == 1) return 0
    return 1
}
function rel_time(ts,    d) {
    if (ts == 0) return "Active"
    d = now - ts; if (d < 0) d = 0
    if (d < 60) return d "s ago"
    if (d < 3600) return int(d / 60) "m ago"
    if (d < 86400) return int(d / 3600) "h ago"
    return int(d / 86400) "d ago"
}
function sort_key(ts, price, name, idx,    k) {
    if (sort_opt == "2") k = sprintf("%010d", ts)
    else if (sort_opt == "3") k = sprintf("%018.3f", 100000000000000 - price)
    else if (sort_opt == "4") k = sprintf("%018.3f", price)
    else if (sort_opt == "5") k = tolower(name)
    else k = sprintf("%010d", 9999999999 - ts)
    return k "|" sprintf("%09d", idx)
}
'
awk_browser_logic="$awk_sort_logic$awk_browser_logic"

browser_prompt_filters() {
    echo -ne "\033[33mSearch by Source [TTC or ESO-Hub] (leave empty for ALL):\033[0m "; read -r source_filter
    echo -ne "\033[33mFilter to your @Username only? (y/N):\033[0m "; read -r personal_opt

    echo -e "\n\033[33mTime Filter:\033[0m"
    echo -e " 1) Past 1 Week\n 2) Past 2 Weeks\n 3) Past 3 Weeks\n 4) All Data"
    echo -ne "\033[33mChoice [1-4] (default 4):\033[0m "; read -r time_opt

    cutoff_time=0; now_ts=$(date +%s)
    case "$time_opt" in
        1) cutoff_time=$((now_ts - 604800)) ;;
        2) cutoff_time=$((now_ts - 1209600)) ;;
        3) cutoff_time=$((now_ts - 1814400)) ;;
    esac

    t_user=""
    if [[ "$personal_opt" == [Yy] ]]; then
        if [ -z "$TARGET_USERNAME" ]; then echo -e "\033[31m[!] @Username not set!\033[0m"
        else t_user="$TARGET_USERNAME"; fi
    fi
    src_lc="$(printf '%s' "$source_filter" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
    user_lc="$(printf '%s' "$t_user" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
}

browser_cache_file() {
    local hash
    hash=$(echo "$1" | md5 -q)
    echo "$CACHE_DIR/cache_${hash}.txt"
}

browser_page() {
    local file="$1" total page=1 pages start key
    total=$(wc -l < "$file" | tr -d ' ')
    pages=$(( (total + 49) / 50 ))
    while true; do
        clear
        echo -e "\033[36m--- Results Page $page of $pages ---\033[0m\n"
        start=$(( (page - 1) * 50 + 1 ))
        sed -n "${start},$((start + 49))p" "$file"
        echo -e "\n\033[33mPress [SPACE] for next page, or 'q' to quit...\033[0m"
        read -rsn1 key
        [[ "$key" == "q" || "$key" == "Q" ]] && break
        [ $((page * 50)) -ge "$total" ] && break
        page=$((page + 1))
    done
}

browser_listing() {
    local mode="$1" s_term sort_opt out
    echo -ne "\033[33mEnter search term (leave empty for ALL data):\033[0m "; read -r s_term
    browser_prompt_filters
    echo -e "\n\033[33mSort By:\033[0m"
    echo -e " 1) Date (Newest First)\n 2) Date (Oldest First)\n 3) Price (Highest First)\n 4) Price (Lowest First)\n 5) Alphabetical (A-Z)"
    echo -ne "\033[33mChoice [1-5]:\033[0m "; read -r sort_opt

    if [ "$mode" = "scan" ]; then echo -e "\n\033[36m--- View Previous Extraction History ---\033[0m"
    else echo -e "\n\033[36mProcessing data...\033[0m"; fi

    out="$TEMP_DIR_ROOT/lttc_browse.out"
    start_spinner "Filtering and sorting..."
    if [ "$mode" = "scan" ]; then
        browser_scan_rows "$LAST_SCAN_FILE" "$s_term" "$sort_opt" > "$out"
    else
        browser_history_rows "$DB_DIR/LTTC_History.db" "$s_term" "$sort_opt" > "$out"
    fi
    stop_spinner 0 "$(wc -l < "$out" | tr -d ' ') results"

    if [ ! -s "$out" ]; then
        echo -e " \033[31m[-] No results found.\033[0m"
        echo -ne "\n\033[33mPress Enter to return...\033[0m "; read -r _
    else
        browser_page "$out"
    fi
    rm -f "$out"
}

browser_history_rows() {
    LC_ALL=C awk -F'|' -v term="$(printf '%s' "$2" | LC_ALL=C tr '[:upper:]' '[:lower:]')" -v sort_opt="$3" \
        -v cutoff="$cutoff_time" -v src_filter="$src_lc" -v t_user="$user_lc" \
        -v now="$(date +%s)" -v db_file="$DB_FILE" '
    '"$awk_browser_logic"'
    BEGIN {
        while ((getline line < db_file) > 0) {
            split(line, p, "|")
            if (p[1] == "GUILD") guild_id[p[2]] = p[3]
        }
        close(db_file)
        '"$master_kiosk_logic"'
    }
    { sub(/\r$/, "") }
    $1 == "HISTORY" {
        if (!row_passes()) next
        if ($10 == "Unknown Guild" || $10 == "Guilds") next
        kname = $11
        if (kname != "" && kname != "0" && (kname in k_dict)) { split(k_dict[kname], kp, "|"); kname = kp[1] }
        if (term != "" && index(tolower($0 "|" kname), term) == 0) next

        act_col = "\033[36m"
        if ($3 == "Sold") act_col = "\033[38;5;214m"
        if ($3 == "Purchased") act_col = "\033[92m"
        if ($3 == "Cancelled") act_col = "\033[31m"

        k_str = ""
        if ($11 != "" && $11 != "0") {
            if ($11 in k_dict) {
                split(k_dict[$11], kp, "|")
                if (kp[2] != "" && kp[3] != "") k_str = " \033[90m(\033]8;;https://eso-hub.com/en/interactive-map?map=" kp[2] "&ping=" kp[3] "\033\\" kp[1] "\033]8;;\033\\)\033[0m"
                else if (kp[2] != "") k_str = " \033[90m(\033]8;;https://eso-hub.com/en/interactive-map?map=" kp[2] "\033\\" kp[1] "\033]8;;\033\\)\033[0m"
                else k_str = " \033[90m(" kp[1] ")\033[0m"
            } else k_str = " \033[90m(Kiosk ID: " $11 ")\033[0m"
        }

        g_str = ""
        if ($10 != "") {
            if ($10 in guild_id) g_str = " in \033[35m\033]8;;|H1:guild:" guild_id[$10] "|h" $10 "|h\033\\" $10 "\033]8;;\033\\\033[0m"
            else g_str = " in \033[35m" $10 "\033[0m"
        }

        link = ($13 == "TTC") ? ttc_url($7) : "https://eso-hub.com/en/trading/" $6
        scans = $14 + 0
        scan_str = (scans > 1) ? " \033[96m[" scans "x Scans]\033[0m" : ""

        trade = ""
        if ($9 != "" && $8 != "") trade = " by \033[36m" $9 "\033[0m to \033[36m" $8 "\033[0m"
        else if ($9 != "") trade = " by \033[36m" $9 "\033[0m"
        else if ($8 != "") trade = " to \033[36m" $8 "\033[0m"

        ts = $2 + 0
        row = " [\033[90m" rel_time(ts) "\033[0m] " act_col $3 "\033[0m for \033[32m" $4 "\033[33mgold\033[0m - \033[32m" $5 "x\033[0m \033]8;;" link "\033\\" $12 $7 "\033[0m\033]8;;\033\\" trade g_str k_str " [\033[90m" $13 "\033[0m]" scan_str
        print sort_key(ts, $4 + 0, $7, NR) "\t" row
    }' "$1" | LC_ALL=C sort -t$'\t' -k1,1 | cut -f2-
}

browser_scan_rows() {
    LC_ALL=C awk -v term="$(printf '%s' "$2" | LC_ALL=C tr '[:upper:]' '[:lower:]')" -v sort_opt="$3" -v now="$(date +%s)" '
    '"$awk_browser_logic"'
    { sub(/\r$/, "") }
    /\[TS:[0-9]+\]|\[\033\[90mListing\033\[0m\]/ {
        plain = $0
        gsub(/\033\]8;;[^\033]*\033\\/, "", plain)
        gsub(/\033\[[0-9;]*m/, "", plain)
        if (term != "" && index(tolower(plain), term) == 0) next
        ts = 0
        if (match($0, /\[TS:[0-9]+\]/)) ts = substr($0, RSTART + 4, RLENGTH - 5) + 0
        price = 0
        if (match(plain, / for [0-9]+gold/)) price = substr(plain, RSTART + 5, RLENGTH - 9) + 0
        name = plain; sub(/^[^-]* - [0-9]+x /, "", name)
        row = $0
        if (ts > 0) sub(/\[TS:[0-9]+\]/, "[\033[90m" rel_time(ts) "\033[0m]", row)
        print sort_key(ts, price, name, NR) "\t" row
    }' "$1" | LC_ALL=C sort -t$'\t' -k1,1 | cut -f2-
}

browser_top_lines() {
    LC_ALL=C awk -F'|' -v kind="$1" -v cutoff="$cutoff_time" -v src_filter="$src_lc" -v t_user="$user_lc" '
    '"$awk_browser_logic"'
    { sub(/\r$/, "") }
    $1 == "HISTORY" && ($3 == "Sold" || $3 == "Purchased" || $3 == "Listed") && $5 > 0 {
        if (!row_passes()) next
        qty = $5 + 0; unit_p = $4 / qty; name = $7
        scans = ($14 != "" && $14 > 0) ? $14 + 0 : 1
        colors[name] = ($12 != "") ? $12 : "\033[0m"
        ids[name] = $6
        for (s = 0; s < scans; s++) {
            prices[name, count[name]++] = unit_p
            if ($3 == "Sold" || $3 == "Purchased") total[name] += (kind == "vol") ? qty : $4
        }
    }
    END {
        for (name in total) {
            n = count[name]; sugg = 0
            if (n >= 5) {
                delete p_arr
                for (i = 0; i < n; i++) p_arr[i] = prices[name, i]
                sugg = band_price(p_arr, n)
            }
            p_str = (sugg == 0) ? "Not enough data" : sprintf("%.2f", sugg) "g"
            if (kind == "vol") lead = " \033[36m" sprintf("%.0f", total[name]) "x\033[0m sold - "
            else lead = " \033[33m" sprintf("%.0f", total[name]) "g\033[0m grossed - "
            printf "%020.3f\t%s\t%s\n", total[name], name, lead colors[name] name "\033[0m (Avg: \033[33m" p_str "\033[0m) " item_links(name, ids[name])
        }
    }' "$2" \
        | LC_ALL=C sort -t$'\t' -k1,1r -k2,2 | head -n 10 | cut -f3-
}

browser_price_lines() {
    LC_ALL=C awk -F'|' -v term="$(printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]')" \
        -v cutoff="$cutoff_time" -v src_filter="$src_lc" -v t_user="$user_lc" '
    '"$awk_browser_logic"'
    { sub(/\r$/, "") }
    $1 == "HISTORY" && index(tolower($7), term) > 0 && ($3 == "Listed" || $3 == "Sold" || $3 == "Purchased") && \
    $4 ~ /^[0-9]+(\.[0-9]+)?$/ && $5 > 0 {
        if (!row_passes()) next
        qty = $5 + 0; unit_p = $4 / qty; name = $7
        scans = ($14 != "" && $14 > 0) ? $14 + 0 : 1
        colors[name] = ($12 != "") ? $12 : "\033[0m"
        ids[name] = $6
        for (s = 0; s < scans; s++) prices[name, count[name]++] = unit_p
    }
    END {
        for (name in count) {
            n = count[name]
            if (n < 5) continue
            delete p_arr
            for (i = 0; i < n; i++) p_arr[i] = prices[name, i]
            sugg = band_price(p_arr, n)
            printf "%s\t%s\n", name, colors[name] name "\033[0m - Suggested Price: \033[33m" sprintf("%.2f", sugg) "g\033[0m (Based on " n " data points) " item_links(name, ids[name])
        }
    }' "$2" \
        | LC_ALL=C sort -t$'\t' -k1,1 | cut -f2-
}

browser_top() {
    local kind="$1" tag title cache_file
    if [ "$kind" = "vol" ]; then
        write_ttc_log "INFO" "DB Browser: Generating Top 10 Selling Items list."; tag="O1v4"
    else
        write_ttc_log "INFO" "DB Browser: Generating Top 10 Highest Grossing Items list."; tag="O2v4"
    fi
    browser_prompt_filters

    if [ "$kind" = "vol" ]; then title="Top 10 Selling Items (By Volume)"; else title="Top 10 Highest Grossing Items"; fi
    if [ -n "$t_user" ]; then echo -e "\n\033[36m--- $title [$t_user] ---\033[0m"
    else echo -e "\n\033[36m--- $title [Global] ---\033[0m"; fi

    cache_file="$(browser_cache_file "$tag|$source_filter|$personal_opt|$time_opt")"
    if [ -f "$cache_file" ] && [ "$cache_file" -nt "$DB_DIR/LTTC_History.db" ]; then
        echo -e " \033[32m[+] Loading instantly from persistent cache...\033[0m\n"
        cat "$cache_file"
    else
        echo ""
        if [ "$kind" = "vol" ]; then start_spinner "Calculating Top 10 by Volume (Building Cache)..."
        else start_spinner "Calculating Top 10 by Grossing (Building Cache)..."; fi
        browser_top_lines "$kind" "$DB_DIR/LTTC_History.db" > "$cache_file"
        stop_spinner 0 "Calculation complete"
        echo ""
        cat "$cache_file"
    fi
    echo ""
}

browser_price_check() {
    local p_term cache_file
    echo -ne "\033[33mEnter exact or partial item name for price check:\033[0m "; read -r p_term
    browser_prompt_filters
    write_ttc_log "INFO" "DB Browser: Executed Suggested Price Check for '$p_term'"

    echo -e "\n\033[36m--- Suggested Price Check ---\033[0m"
    cache_file="$(browser_cache_file "O3v4|$p_term|$source_filter|$personal_opt|$time_opt")"
    if [ -f "$cache_file" ] && [ "$cache_file" -nt "$DB_DIR/LTTC_History.db" ]; then
        echo -e " \033[32m[+] Loading instantly from persistent cache...\033[0m\n"
        cat "$cache_file"
    else
        echo ""
        start_spinner "Calculating Outlier Eliminations (Building Cache)..."
        browser_price_lines "$p_term" "$DB_DIR/LTTC_History.db" > "$cache_file"

        if [ -s "$cache_file" ]; then
            stop_spinner 0 "Calculation complete"
            echo ""
            cat "$cache_file"
        else
            stop_spinner 1 "Not enough data to display anything"
            rm -f "$cache_file" 2>/dev/null
        fi
    fi
    echo ""
}

browser_set_user() {
    local input_user
    echo -e "\n\033[36m--- Settings: Edit My Target Username ---\033[0m"
    echo -ne "\033[33mEnter your exact @Username (leave blank to clear): \033[0m"
    read -r input_user

    if [ -n "$input_user" ]; then input_user="@${input_user#@}"; fi
    if grep -q "^TARGET_USERNAME=" "$CONFIG_FILE" 2>/dev/null; then
        awk -v u="$input_user" '/^TARGET_USERNAME=/ { print "TARGET_USERNAME=\"" u "\""; next } { print }' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" \
            && mv -f "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    else
        echo "TARGET_USERNAME=\"$input_user\"" >> "$CONFIG_FILE"
    fi
    TARGET_USERNAME="$input_user"

    if [ -z "$input_user" ]; then
        echo -e " \033[90m[-] Username cleared.\033[0m\n"
        write_ttc_log "INFO" "DB Browser: Target Username cleared."
    else
        echo -e " \033[92m[+] Username saved as $TARGET_USERNAME\033[0m\n"
        write_ttc_log "INFO" "DB Browser: Target Username updated to '$TARGET_USERNAME'"
    fi
    echo -ne "\033[33mPress Enter to return...\033[0m "; read -r _
}

browse_database() {
    write_ttc_log "INFO" "browse_database: entering DB browser"
    clear
    echo -e "\n\033[92m===========================================================================\033[0m"
    echo -e "\033[1m\033[94m                         TTC & ESO-Hub Database Browser\033[0m"
    echo -e "\033[97m                 (Data automatically retained for the last 30 days)\033[0m"
    echo -e "\033[92m===========================================================================\033[0m\n"

    if [ ! -s "$DB_DIR/LTTC_History.db" ]; then
        echo -e "\033[31m[!] No history database found. Wait for extraction first.\033[0m\n"
        echo -e "\033[31m[!] (or go visit a guild store in-game and press scan then /reloadui)\033[0m\n"
        echo -ne "\033[33mPress Enter to return...\033[0m "; read -r _; return
    fi

    if [ -f "$CONFIG_FILE" ] && grep -q '^TARGET_USERNAME=' "$CONFIG_FILE"; then
        TARGET_USERNAME="$(sed -n 's/^TARGET_USERNAME="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$CONFIG_FILE" | tail -n 1)"
    fi

    CACHE_DIR="$TARGET_DIR/Cache"
    mkdir -p "$CACHE_DIR"

    while true; do
        echo -e "\n\033[33mSelect a Database Function:\033[0m"
        echo -e " 1) View / Search Database (Paginated & Sorted)"
        echo -e " 2) Top 10 Most Selling Items (By Volume)"
        echo -e " 3) Top 10 Highest Grossing Items (By Total Gold)"
        echo -e " 4) Suggested Price Calculator (Outlier Elimination)"
        echo -e " 5) View Previous Extraction History (Paginated & Sorted)"
        echo -e " 6) Settings: Edit My Target Username \033[90m(Current: ${TARGET_USERNAME:-None})\033[0m"
        echo -e " 7) Exit Browser & Resume Updater"
        echo -ne "\033[33mChoice [1-7]:\033[0m "; read -r b_opt

        case $b_opt in
            1) browser_listing db ;;
            2) browser_top vol ;;
            3) browser_top gold ;;
            4) browser_price_check ;;
            5) browser_listing scan ;;
            6) browser_set_user ;;
            7) write_ttc_log "INFO" "browse_database: exiting DB browser"; break ;;
            *) echo -e "\033[31mInvalid option.\033[0m" ;;
        esac
    done
    clear
    if [ "$SILENT" = false ]; then
        echo -ne "\033]0;$APP_TITLE - Created by @APHONIC\007"
        if [ -s "$UI_STATE_FILE" ]; then print_dynamic_log "$UI_STATE_FILE"; fi
    fi
}
prune_history() {
    write_ttc_log "INFO" "prune_history: Initiating 30 days data prune and metadata sync."
    if [ -f "$DB_DIR/LTTC_History.db" ]; then
        start_spinner "Pruning history data (30 days)..."
        local cutoff=$((CURRENT_TIME - 2592000))
        
        local orig_lines=$(wc -l < "$DB_DIR/LTTC_History.db" 2>/dev/null)
        [ -z "$orig_lines" ] && orig_lines=0
        
        local del_log="$TEMP_DIR_ROOT/LTTC_History_Pruned.tmp"
        > "$del_log"
        
        awk -F'|' -v OFS='|' -v cutoff="$cutoff" -v db="$DB_FILE" -v del_log="$del_log" '
        BEGIN {
            if (db != "") {
                while ((getline line < db) > 0) {
                    split(line, p, "|")
                    if (p[1] ~ /^[0-9]+$/) {
                        db_name[p[1]] = (length(p) >= 6) ? p[6] : p[3]
                        db_qual[p[1]] = p[2] + 0
                    }
                }
                close(db)
            }
        }
        $1!="HISTORY" { if ($0 != "") print $0; next }
        $1=="HISTORY" {
            if ($2 < cutoff) {
                print $0 >> del_log
                next
            }
            if ($NF ~ /^[0-9]+$/) {
                scans = $NF + 0
                src = $(NF-1)
            } else {
                scans = 1
                src = $NF
            }
            if (src ~ /^(Unknown|\[Unknown\])$/ || src == "") src = "TTC"
            if ($6 in db_name && db_name[$6] != "" && db_name[$6] !~ /^Unknown Item/) {
                $7 = db_name[$6]
            }
            if ($6 in db_qual) {
                q_num = db_qual[$6]
                c = "\033[0m"
                if(q_num==0) c="\033[90m"
                else if(q_num==1) c="\033[97m"
                else if(q_num==2) c="\033[32m"
                else if(q_num==3) c="\033[36m"
                else if(q_num==4) c="\033[35m"
                else if(q_num==5) c="\033[33m"
                else if(q_num==6) c="\033[38;5;214m"
                $12 = c
            } else if ($12 !~ /^\033\[/) {
                $12 = "\033[0m"
            }
            $13 = src
            $14 = scans
            print $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14
        }' "$DB_DIR/LTTC_History.db" > "$TEMP_DIR_ROOT/LTTC_History.tmp" 2>/dev/null
        local awk_ok=$?
        
        local pruned_count=0
        if [ "$awk_ok" -eq 0 ] && [ -f "$TEMP_DIR_ROOT/LTTC_History.tmp" ]; then
            local new_lines=$(wc -l < "$TEMP_DIR_ROOT/LTTC_History.tmp" 2>/dev/null)
            pruned_count=$((orig_lines - new_lines))
            [ "$pruned_count" -lt 0 ] && pruned_count=0
            
            mv "$TEMP_DIR_ROOT/LTTC_History.tmp" "$DB_DIR/LTTC_History.db" 2>/dev/null
        fi
        
        if [ "$LOG_MODE" = "detailed" ] && [ -s "$del_log" ]; then
            local d_time=$(date '+%Y-%m-%d %H:%M:%S')
            awk -v dt="$d_time" '{
                gsub(/\033\[[0-9;]*m/, "", $0)
                print "["dt"] [ITEM] Pruned History Item: " $0
            }' "$del_log" >> "$LOG_FILE"
        fi
        rm -f "$del_log" 2>/dev/null
        
        stop_spinner 0 "History pruned ($pruned_count items removed)"

        local p_stats p_count p_min p_max p_near p_size
        p_stats=$(awk -F'|' -v now="$CURRENT_TIME" -v edge="$((CURRENT_TIME - 2332800))" '
            $1=="HISTORY" { c++; if (min=="" || $2 < min) min=$2; if ($2 > max) max=$2; if ($2 < edge) near++ }
            END { printf "%d %d %d %d", c+0, (min==""?now:min), (max==""?now:max), near+0 }
        ' "$DB_DIR/LTTC_History.db" 2>/dev/null)
        read -r p_count p_min p_max p_near <<< "$p_stats"
        p_size=$(wc -c < "$DB_DIR/LTTC_History.db" 2>/dev/null | tr -d ' '); p_size=${p_size:-0}
        ui_echo "\t\e[90m$p_count entries, $(size_human "$p_size"). Oldest $(age_short $((CURRENT_TIME - p_min))), newest $(age_short $((CURRENT_TIME - p_max))). $p_near near the 30-day cutoff.\e[0m"
    fi
}

ttc_extract() {
    awk -v last_time="$2" -v now_time="$3" -v db_file="$DB_FILE" '
    '"$master_color_logic"'
    BEGIN {
        max_time = last_time
        count = 0
        while ((getline line < db_file) > 0) {
            split(line, p, "|")
            if (p[1] == "GUILD") {
                db_guild_id[p[2]] = p[3]
            } else if (p[1] ~ /^[0-9]+$/) {
                db_cols[p[1]] = length(p)
                db_qual[p[1]] = p[2]
                db_name[p[1]] = (length(p) >= 6) ? p[6] : p[3]
            }
        }
        close(db_file)
        '"$master_kiosk_logic"'
    }
    { sub(/\r$/, "") }
    /^[ \t]*\["?([^"]+)"?\][ \t]*=/ {
        match($0, /^[ \t]*/)
        lvl = RLENGTH + 0
        match($0, /^[ \t]*\["?([^"]+)"?\]/)
        key = substr($0, RSTART, RLENGTH)
        sub(/^[ \t]*\["?/, "", key)
        sub(/"?\]$/, "", key)

        for (i in path) {
            if ((i + 0) >= lvl) {
                delete path[i]
            }
        }
        path[lvl] = key

        if (key == "KioskLocationID") {
            n = 0
            for (i in path) { keys[n++] = i + 0 }
            for (i = 0; i < n; i++) {
                for (j = i + 1; j < n; j++) {
                    if (keys[i] > keys[j]) {
                        temp = keys[i]
                        keys[i] = keys[j]
                        keys[j] = temp
                    }
                }
            }
            gname = ""
            for (i = 0; i < n; i++) {
                if (path[keys[i]] == "Guilds" && i + 1 < n) {
                    gname = path[keys[i+1]]
                }
            }
            if (gname != "") {
                match($0, /[0-9]+/)
                guild_kiosks[gname] = substr($0, RSTART, RLENGTH)
            }
        }

        if (key ~ /^[0-9]+$/ && !in_item) {
            in_item = 1
            item_lvl = lvl
            n = 0
            for (i in path) { keys[n++] = i + 0 }
            for (i = 0; i < n; i++) {
                for (j = i + 1; j < n; j++) {
                    if (keys[i] > keys[j]) {
                        temp = keys[i]
                        keys[i] = keys[j]
                        keys[j] = temp
                    }
                }
            }

            action = "Listed"
            guild = ""
            player = ""
            seller = ""
            buyer = ""
            ttc_id = ""
            amt = ""; stime = ""; price = ""; itemid = ""
            subtype = ""; internal_level = ""; real_name = ""; game_qual = ""

            for (i = 0; i < n; i++) {
                k = path[keys[i]]
                if (k == "SaleHistoryEntries") action = "Sold"
                if (k == "AutoRecordEntries" || k == "Entries") action = "Listed"
                if (k == "Guilds" && i + 1 < n) guild = path[keys[i+1]]
                if (k == "PlayerListings" && i + 1 < n) player = path[keys[i+1]]
            }
        }
    }
    in_item && /\["Amount"\][ \t]*=/ {
        match($0, /[0-9]+/)
        amt=substr($0, RSTART, RLENGTH)
    }
    in_item && /\["SaleTime"\][ \t]*=/ {
        match($0, /[0-9]+/)
        stime=substr($0, RSTART, RLENGTH)
    }
    in_item && /\["Timestamp"\][ \t]*=/ {
        match($0, /[0-9]+/)
        if(stime=="") stime=substr($0, RSTART, RLENGTH)
    }
    in_item && /\["TimeStamp"\][ \t]*=/ {
        match($0, /[0-9]+/)
        if(stime=="") stime=substr($0, RSTART, RLENGTH)
    }
    in_item && /\["QualityID"\][ \t]*=/ {
        match($0, /[0-9]+/)
        game_qual = substr($0, RSTART, RLENGTH)
    }
    in_item && /\["TotalPrice"\][ \t]*=/ {
        match($0, /[0-9]+/)
        price=substr($0, RSTART, RLENGTH)
    }
    in_item && /\["Price"\][ \t]*=/ {
        if ($0 !~ /TotalPrice/) {
            match($0, /[0-9]+/)
            if(price=="") price=substr($0, RSTART, RLENGTH)
        }
    }
    in_item && /\["Buyer"\][ \t]*=/ {
        match($0, /\["Buyer"\][ \t]*=[ \t]*"([^"]+)"/)
        if(RLENGTH>0) {
            buyer=substr($0,RSTART,RLENGTH)
            sub(/.*\["Buyer"\][ \t]*=[ \t]*"/,"",buyer)
            sub(/"$/,"",buyer)
        }
    }
    in_item && /\["Seller"\][ \t]*=/ {
        match($0, /\["Seller"\][ \t]*=[ \t]*"([^"]+)"/)
        if(RLENGTH>0) {
            seller=substr($0,RSTART,RLENGTH)
            sub(/.*\["Seller"\][ \t]*=[ \t]*"/,"",seller)
            sub(/"$/,"",seller)
        }
    }
    in_item && /\["ItemLink"\][ \t]*=/ {
        if (match($0, /\|H[0-9a-fA-F]*:item:[0-9]+/)) {
            split(substr($0, RSTART, RLENGTH), ip, ":")
            itemid = ip[3]
        }
        if (match($0, /"(\|H[^"]+)"/)) {
            split(substr($0, RSTART+1, RLENGTH-2), lp, ":")
            subtype = lp[4]
            internal_level = lp[5]
        }
    }
    in_item && /\["Name"\][ \t]*=/ {
        val = $0
        sub(/.*Name"\][ \t]*=[ \t]*"/, "", val)
        sub(/",[ \t]*$/, "", val)
        gsub(/\\"/, "\"", val)
        real_name = val
    }
    in_item && /^[ \t]*\},?[ \t]*$/ {
        match($0, /^[ \t]*/)
        if (RLENGTH <= item_lvl) {
            in_item = 0
            stime_num = (stime == "") ? 0 : stime + 0
            if (stime_num > max_time) max_time = stime_num

            if (stime_num > last_time || last_time == 0 || action == "Listed") {
                if (amt == "") amt = "1"
                if (real_name == "" || real_name ~ /^\|[0-9]+\|$/) {
                    if (itemid in db_name && db_name[itemid] !~ /^Unknown Item/) {
                        real_name = db_name[itemid]
                    } else {
                        real_name = "Unknown Item (" itemid ")"
                    }
                }

                if (price != "") {
                    s = subtype + 0
                    v = internal_level + 0
                    needs_update = 0

                    if (itemid in db_name) {
                        if (real_name != db_name[itemid] && real_name !~ /^Unknown Item/) {
                            needs_update = 1
                        }
                        if (db_cols[itemid] < 7) needs_update = 1
                    } else {
                        needs_update = 1
                    }

                    if (game_qual != "") {
                        real_qual = game_qual + 1
                        if (!(itemid in db_qual) || db_qual[itemid] + 0 != real_qual) needs_update = 1
                    } else if (itemid in db_qual) {
                        real_qual = db_qual[itemid] + 0
                    } else {
                        real_qual = calc_quality(itemid, real_name, s, v)
                    }

                    if (index(real_name, "Unknown Item (") == 1) needs_update = 0

                    if (needs_update) {
                        hq = get_hq(real_qual)
                        cat = get_cat(real_name, itemid, s, v)

                        update_str = itemid "|" real_qual "|" s "|" v "|" hq "|" real_name "|" cat
                        db_updated[itemid] = update_str
                        db_name[itemid] = real_name
                        db_qual[itemid] = real_qual
                        db_cols[itemid] = 7
                    }

                    q_num = real_qual + 0
                    c = "\033[0m"
                    if(q_num==0) c="\033[90m"
                    else if(q_num==1) c="\033[97m"
                    else if(q_num==2) c="\033[32m"
                    else if(q_num==3) c="\033[36m"
                    else if(q_num==4) c="\033[35m"
                    else if(q_num==5) c="\033[33m"
                    else if(q_num==6) c="\033[38;5;214m"

                    guild_str = ""
                    kiosk = ""
                    if (guild != "" && guild != "Unknown Guild" && guild != "Guilds") {
                        if (guild in db_guild_id) {
                            gid = db_guild_id[guild]
                            g_display = "\033[35m\033]8;;|H1:guild:" gid "|h" guild \
                                        "|h\033\\" guild "\033]8;;\033\\\033[0m"
                        } else {
                            g_display = "\033[35m" guild "\033[0m"
                        }

                        kiosk = guild_kiosks[guild]
                        if (kiosk != "" && kiosk != "0") {
                            if (kiosk in k_dict) {
                                split(k_dict[kiosk], kp, "|")
                                k_loc = kp[1]
                                k_map = kp[2]
                                k_coords = kp[3]

                                if (k_map != "" && k_coords != "") {
                                    k_str = " \033[90m(\033]8;;https://eso-hub.com/en/" \
                                            "interactive-map?map=" k_map "&ping=" k_coords \
                                            "\033\\" k_loc "\033]8;;\033\\)\033[0m"
                                } else if (k_map != "") {
                                    k_str = " \033[90m(\033]8;;https://eso-hub.com/en/" \
                                            "interactive-map?map=" k_map "\033\\" k_loc \
                                            "\033]8;;\033\\)\033[0m"
                                } else {
                                    k_str = " \033[90m(" k_loc ")\033[0m"
                                }
                            } else {
                                k_str = " \033[90m(Kiosk ID: " kiosk ")\033[0m"
                            }
                        } else {
                            k_str = " \033[90m(Local Trader)\033[0m"
                        }
                        guild_str = " in " g_display k_str
                    }

                    player_str_clean = player
                    if (player_str_clean != "" && player_str_clean !~ /^@/) {
                        player_str_clean = "@" player_str_clean
                    }

                    if (buyer != "" && buyer !~ /^@/) buyer = "@" buyer
                    if (seller != "" && seller !~ /^@/) seller = "@" seller

                    if (seller == "" && player_str_clean != "") seller = player_str_clean

                    trade_str = ""
                    if (seller != "" && buyer != "") {
                        trade_str = " by \033[36m" seller "\033[0m to \033[36m" buyer "\033[0m"
                    } else if (seller != "") {
                        trade_str = " by \033[36m" seller "\033[0m"
                    } else if (buyer != "") {
                        trade_str = " to \033[36m" buyer "\033[0m"
                    } else if (player_str_clean != "" && player_str_clean != guild) {
                        trade_str = " by \033[36m" player_str_clean "\033[0m"
                    }

                    name_enc = real_name
                    gsub(/ /, "+", name_enc)
                    gsub(/'\''/, "%27", name_enc)

                    link_start = "\033]8;;https://us.tamrieltradecentre.com/pc/Trade/" \
                                 "SearchResult?SearchType=Sell&ItemNamePattern=" name_enc "\033\\"

                    age = now_time - stime_num
                    status_tag = ""

                    if (action == "Sold") {
                        status_tag = " \033[38;5;214m[SOLD]\033[0m"
                    } else if (action == "Listed") {
                        if (stime_num > 0 && age > 2592000) {
                            status_tag = " \033[90m[EXPIRED]\033[0m"
                        } else {
                            status_tag = " \033[34m[AVAILABLE]\033[0m"
                        }
                    }

                    ts_str = (stime_num > 0) ? stime_num "|" : "0|"

                    lines[count] = ts_str " \033[36m" action "\033[0m for \033[32m" price \
                                   "\033[33mgold\033[0m - \033[32m" amt "x\033[0m " link_start \
                                   c real_name "\033[0m\033]8;;\033\\" trade_str \
                                   guild_str status_tag

                    if (guild != "Guilds" && guild != "Unknown Guild" && guild != "") {
                        hist_lines[count] = "HISTORY|" ts_str action "|" price "|" amt "|" \
                                            itemid "|" real_name "|" buyer "|" seller "|" \
                                            guild "|" kiosk "|" c "|TTC"
                    } else if (action == "Listed" && seller != "") {
                        hist_lines[count] = "HISTORY|" ts_str action "|" price "|" amt "|" \
                                            itemid "|" real_name "|" buyer "|" seller "||" \
                                            kiosk "|" c "|TTC"
                    } else {
                        hist_lines[count] = ""
                    }
                    count++
                }
            }
        }
    }
    END {
        for (i = 0; i < count; i++) {
            print lines[i]
            if (hist_lines[i] != "") print hist_lines[i]
        }
        print "MAX_TIME:" max_time
        for (i in db_updated) {
            print "DB_UPDATE|" db_updated[i]
        }
        for (k in k_dict) {
            print "DB_KIOSK|" k "|" k_dict[k]
        }
    }
    ' "$1"
}
TTC_WEB_CLIENT_VERSION="3.1.0.0"
TTC_BATCH_SIZE=100
TTC_CHECK_EVERY=2700

ttc_price_table_version() {
    local v=""
    [ -f "$1" ] && v=$(head -n 2 "$1" 2>/dev/null | tr -d '\r' | grep -iE '^--Version[ \t]*=[ \t]*[0-9]+' \
        | grep -oE '[0-9]+' | head -n 1)
    printf '%s' "${v:-0}"
}

ttc_client_id() {
    if [ -z "${TTC_CLIENT_ID:-}" ]; then
        if command -v uuidgen > /dev/null 2>&1; then
            TTC_CLIENT_ID="$(uuidgen | tr 'A-Z' 'a-z')"
        elif [ -r /proc/sys/kernel/random/uuid ]; then
            TTC_CLIENT_ID="$(cat /proc/sys/kernel/random/uuid)"
        else
            TTC_CLIENT_ID="$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n' \
                | sed -E 's/^(.{8})(.{4})(.{4})(.{4})(.{12}).*/\1-\2-4\3-a\4-\5/' | cut -c1-36)"
        fi
        CONFIG_CHANGED=true
    fi
}

ttc_upload_parse() {
    awk -v region="$2" -v now="$3" -v cache="$4" '
    function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r,]+$/, "", s); return s }
    function unkey(s) { s = trim(s); sub(/^\[/, "", s); sub(/\]$/, "", s); if (s ~ /^".*"$/) s = substr(s, 2, length(s) - 2); return s }
    function jstr(s) { return "\"" s "\"" }
    function field(d, k) { return ((d, k) in val) ? val[d, k] : "" }
    function add(json, name, v) { if (v == "" || v == "nil") return json; return json (json == "" ? "" : ",") "\"" name "\":" v }
    function sorted_list(d,    n, i, j, t, a, out) {
        n = 0
        for (i = 0; i < 64; i++) if ((d, "#" i) in val) a[++n] = val[d, "#" i] + 0
        for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (a[j] < a[i]) { t = a[i]; a[i] = a[j]; a[j] = t }
        out = ""
        for (i = 1; i <= n; i++) out = out (i > 1 ? "," : "") a[i]
        return "[" out "]"
    }
    function put(d, k, v) { if (!((d, k) in val)) klist[d] = klist[d] (klist[d] == "" ? "" : SUBSEP) k; val[d, k] = v }
    function clear(d,    n, i, p) { n = split(klist[d], p, SUBSEP); for (i = 1; i <= n; i++) delete val[d, p[i]]; klist[d] = "" }
    function item_json(d,    j) {
        j = ""
        j = add(j, "ID", field(d, "ID"))
        j = add(j, "UID", field(d, "UID"))
        j = add(j, "QualityID", field(d, "QualityID"))
        j = add(j, "Category2IDOverWrite", field(d, "Category2IDOverWrite"))
        j = add(j, "TraitID", field(d, "TraitID"))
        j = add(j, "LevelTotal", field(d, "Level"))
        j = add(j, "PotionEffectIDs", field(d, "PotionEffects"))
        j = add(j, "MasterWritInfo", field(d, "MasterWritInfo") == "" ? "null" : field(d, "MasterWritInfo"))
        return "{" j "}"
    }
    function close_table(d,    sub_d, j, key) {
        key = stack[d]
        if (d >= 2 && stack[d - 1] != "" && (key == "PotionEffects" || key == "RequiredPotionEffectIDs")) {
            put(d - 1, key, sorted_list(d))
        } else if (key == "MasterWritInfo") {
            j = ""
            j = add(j, "RequiredItemID", field(d, "RequiredItemID"))
            j = add(j, "RequiredQualityID", field(d, "RequiredQualityID"))
            j = add(j, "RequiredTraitID", field(d, "RequiredTraitID"))
            j = add(j, "RequiredSetID", field(d, "RequiredSetID"))
            j = add(j, "RequiredStyleID", field(d, "RequiredStyleID"))
            j = add(j, "RequiredPotionEffectIDs", field(d, "RequiredPotionEffectIDs"))
            j = add(j, "NumVoucher", field(d, "NumVoucher"))
            put(d - 1, "MasterWritInfo", "{" j "}")
        } else if (d == 9 && stack[5] == region "Data" && stack[6] == "Guilds" && stack[8] == "Entries") {
            n_self++
            self_acct[n_self] = stack[3]; self_guild[n_self] = stack[7]
            self_asset[n_self] = add(add("", "Amount", field(d, "Amount")), "TotalPrice", field(d, "TotalPrice"))
            self_item[n_self] = item_json(d); self_uid[n_self] = field(d, "UID"); self_link[n_self] = field(d, "ItemLink")
        } else if (d == 7 && stack[5] == region "Data" && stack[6] == "Guilds") {
            guild_scan[stack[3], stack[7]] = field(d, "LastFullScan")
            guild_kiosk[stack[3], stack[7]] = field(d, "KioskLocationID")
        } else if (d == 11 && stack[5] == region "Data" && stack[6] == "AutoRecordEntries" && stack[9] == "PlayerListings") {
            n_auto++
            auto_acct[n_auto] = stack[3]; auto_guild[n_auto] = stack[8]; auto_player[n_auto] = stack[10]
            auto_asset[n_auto] = add(add("", "Amount", field(d, "Amount")), "TotalPrice", field(d, "TotalPrice"))
            auto_item[n_auto] = item_json(d); auto_uid[n_auto] = field(d, "UID"); auto_link[n_auto] = field(d, "ItemLink")
            auto_discover[n_auto] = field(d, "DiscoverTime"); auto_expire[n_auto] = field(d, "ExpireTime")
        } else if (d == 8 && stack[5] == region "Data" && stack[6] == "AutoRecordEntries" && stack[7] == "Guilds") {
            auto_kiosk[stack[3], stack[8]] = field(d, "KioskLocationID")
            auto_update[stack[3], stack[8]] = field(d, "LastUpdate")
        } else if (d == 5 && stack[5] == "Settings") {
            set_auto[stack[3]] = field(d, "EnableAutoRecordStoreEntries")
            set_self[stack[3]] = field(d, "EnableSelfEntriesUpload")
        } else if (d == 4 && stack[4] == "$AccountWide") {
            acct_version[stack[3]] = field(d, "ActualVersion")
            acct_culture[stack[3]] = field(d, "ClientCulture")
            accounts[stack[3]] = 1
        }
        clear(d)
    }
    function keep(acct, guild, player, asset, item, uid, link, discover, expire, kiosk,    u, j) {
        if (discover == "" || expire == "") return
        discover += 0; expire += 0
        if (discover <= now && discover > newest) newest = discover
        u = uid; gsub(/"/, "", u)
        if (u == "" || u == "0") return
        if (((u "|" discover) in sent) || now > expire || discover > now || now - discover > 21600) return
        if (item !~ /"ID":/) { gsub(/"/, "", link); if (link != "") nolink[++n_nolink] = link; return }
        j = "{\"TradeAsset\":{" asset ",\"Item\":" item "},\"PlayerID\":" jstr(player) ",\"GuildID\":@@"
        if (kiosk != "") j = j ",\"GuildKioskLocationID\":" kiosk
        j = j ",\"DiscoverUnixTime\":" discover ",\"ExpireUnixTime\":" expire "}"
        if ((u in best) && best[u] >= discover) return
        best[u] = discover; pick_guild[u] = guild; pick_json[u] = j
        need_guild[guild] = 1
    }
    BEGIN {
        depth = 0; pending = ""; newest = 0
        if (cache != "") while ((getline l < cache) > 0) { split(l, p, "\t"); sent[p[1] "|" p[2]] = 1 }
    }
    {
        line = $0; sub(/\r$/, "", line); t = trim(line)
        if (t == "{") { depth++; stack[depth] = pending; pending = ""; next }
        if (t == "}" || t == "},") { close_table(depth); depth--; next }
        eq = index(t, "=")
        if (eq == 0) next
        k = unkey(substr(t, 1, eq - 1)); v = trim(substr(t, eq + 1))
        if (v == "") { pending = k; next }
        if (k ~ /^[0-9]+$/) k = "#" k
        put(depth, k, v)
    }
    END {
        for (a in accounts) {
            if (acct_version[a] + 0 < 7) continue
            if (culture == "") culture = acct_culture[a]
            if (set_auto[a] == "true") for (i = 1; i <= n_auto; i++) if (auto_acct[i] == a && auto_kiosk[a, auto_guild[i]] != "") {
                keep(a, auto_guild[i], auto_player[i], auto_asset[i], auto_item[i], auto_uid[i], auto_link[i],
                    auto_discover[i], auto_expire[i], auto_kiosk[a, auto_guild[i]])
                kiosks[auto_guild[i]] = auto_kiosk[a, auto_guild[i]] "\t" auto_update[a, auto_guild[i]]
            }
            if (set_self[a] == "true") for (i = 1; i <= n_self; i++) if (self_acct[i] == a) {
                scan = guild_scan[a, self_guild[i]]
                keep(a, self_guild[i], a, self_asset[i], self_item[i], self_uid[i], self_link[i],
                    scan, scan == "" ? "" : scan + 604800, guild_kiosk[a, self_guild[i]])
            }
        }
        for (g in need_guild) print "G\t" g
        for (u in pick_json) print "E\t" pick_guild[u] "\t" pick_json[u]
        for (i = 1; i <= n_nolink; i++) print "L\t" nolink[i]
        for (g in kiosks) if (g in need_guild) print "K\t" g "\t" kiosks[g]
        gsub(/"/, "", culture)
        print "C\t" culture
        print "N\t" newest
    }' "$1"
}

ttc_upload_remember() {
    tr '{' '\n' < "$1" | awk -v at="$2" '
        /"UID":/ { u = $0; sub(/.*"UID":/, "", u); sub(/[,}].*/, "", u); gsub(/"/, "", u) }
        /"DiscoverUnixTime":/ { d = $0; sub(/.*"DiscoverUnixTime":/, "", d); sub(/[,}].*/, "", d); print u "\t" d "\t" at }'
}

ttc_post_json() {
    curl -s -f -m 60 -X POST -A "$TTC_USER_AGENT" \
        -H "Content-Type: application/json; charset=UTF-8" \
        -H "WebClientVersion: $TTC_WEB_CLIENT_VERSION" \
        -H "ClientID: $TTC_CLIENT_ID" \
        --data-binary "@$2" "https://$1$3" > /dev/null 2>&1
}

ttc_upload_cache() { printf '%s/LTTC_TTC_Uploaded_%s.txt' "$DB_DIR" "$1"; }

ttc_upload() {
    local domain="$1" region="$2" sv="$3" now cache work map guild id ok=0 count=0 total
    TTC_UPLOAD_COUNT=0; TTC_UPLOAD_NEWEST=0
    ttc_client_id
    now="$(date +%s)"
    cache="$(ttc_upload_cache "$region")"
    [ -f "$cache" ] || : > "$cache" 2>/dev/null
    work="$(mktemp -d "$TEMP_DIR_ROOT/lttc_upload.XXXXXX")" || return 1
    ttc_upload_parse "$sv" "$region" "$now" "$cache" > "$work/parsed" 2>/dev/null || { rm -rf "$work"; return 1; }
    TTC_UPLOAD_NEWEST="$(awk -F '\t' '$1 == "N" { print $2 + 0 }' "$work/parsed")"
    map="$work/guilds"
    : > "$map"
    while IFS="$(printf '\t')" read -r kind guild _; do
        [ "$kind" = "G" ] || continue
        id="$(curl -s -f -m 30 -G -A "$TTC_USER_AGENT" -H "WebClientVersion: $TTC_WEB_CLIENT_VERSION" \
            -H "ClientID: $TTC_CLIENT_ID" --data-urlencode "guildName=$guild" \
            "https://$domain/api/PC/Trade/GetGuildID" 2>/dev/null | grep -oE '"GuildID":[0-9]+' | grep -oE '[0-9]+')"
        [ -n "$id" ] && printf '%s\t%s\n' "$guild" "$id" >> "$map"
    done < "$work/parsed"

    awk -F '\t' -v dir="$work" -v size="$TTC_BATCH_SIZE" '
        FILENAME == ARGV[1] { id[$1] = $2; next }
        $1 == "E" && ($2 in id) {
            j = $3; sub(/@@/, id[$2], j)
            n++; b = int((n - 1) / size) + 1
            f = dir "/batch" b
            printf "%s%s", (n % size == 1 || size == 1) ? "[" : ",", j > f
            last = f
        }
        $1 == "E" && !($2 in id) { missing++ }
        END {
            for (i = 1; i <= int((n + size - 1) / size); i++) printf "]" >> (dir "/batch" i)
            print n + 0 > (dir "/count"); print missing + 0 > (dir "/missing")
        }' "$map" "$work/parsed"

    total="$(cat "$work/count" 2>/dev/null)"
    [ "$(cat "$work/missing" 2>/dev/null)" != "0" ] && ok=1
    for batch in "$work"/batch*; do
        [ -f "$batch" ] || continue
        if ttc_post_json "$domain" "$batch" "/api/PC/Trade/PostAutoRecordedEntry"; then
            count=$((count + $(grep -o '"DiscoverUnixTime"' "$batch" | wc -l)))
            ttc_upload_remember "$batch" "$now" >> "$cache"
        else
            ok=1
        fi
    done

    if [ "${total:-0}" -gt 0 ]; then
        if [ "$(awk -F '\t' '$1 == "C" { print $2 }' "$work/parsed")" = "en" ]; then
            local links
            links="$(awk -F '\t' '$1 == "L" { gsub(/"/, "", $2); if (!seen[$2]++) printf "%s\"%s\"", (n++ ? "," : "["), $2 } END { if (n) print "]" }' "$work/parsed")"
            if [ -n "$links" ] && [ "$(printf '%s' "$links" | grep -o '|h|h' | wc -l)" -lt $((total / 5)) ]; then
                printf '%s' "$links" > "$work/links"
                ttc_post_json "$domain" "$work/links" "/api/PC/Trade/RecordItemLinks"
            fi
        fi
        awk -F '\t' 'FILENAME == ARGV[1] { id[$1] = $2; next } $1 == "K" && ($2 in id) && $3 != "" {
            printf "{\"GuildID\":%s,\"GuildKioskLocationID\":%s,\"Timestamp\":%s}\n", id[$2], $3, ($4 == "" ? 0 : $4) }' \
            "$map" "$work/parsed" | while read -r kiosk; do
                printf '%s' "$kiosk" > "$work/kiosk"
                ttc_post_json "$domain" "$work/kiosk" "/api/PC/Trade/VerifyKioskLocation"
            done
    fi

    if [ -s "$cache" ]; then
        awk -F '\t' -v cut=$((now - 172800)) '$2 + 0 >= cut' "$cache" > "$work/cache" && cat "$work/cache" > "$cache"
    fi
    TTC_UPLOAD_COUNT="$count"
    rm -rf "$work"
    return "$ok"
}

ttc_nothing_new_reason() {
    local newest="${TTC_UPLOAD_NEWEST:-0}" now
    now="$(date +%s)"
    if [ "$newest" -le 0 ]; then
        printf 'no listings in TamrielTradeCentre.lua yet'
    elif [ $((now - newest)) -gt 21600 ]; then
        printf 'newest scan saved is %s, TTC takes the last 6 hours; ESO saves new scans on /reloadui or logout' "$(ttc_clock "$newest")"
    else
        printf 'every listing up to %s was already uploaded; ESO saves new scans on /reloadui or logout' "$(ttc_clock "$newest")"
    fi
}

ttc_clock() {
    local z off
    z="$(date +%z)"
    off=$(( (10#${z:1:2} * 3600 + 10#${z:3:2} * 60) ))
    [ "${z:0:1}" = "-" ] && off=$((-off))
    printf '%02d:%02d' $(( (($1 + off) / 3600) % 24 )) $(( (($1 + off) / 60) % 60 ))
}
esohub_extract() {
    awk -v last_time="$2" -v now_time="$3" -v db_file="$DB_FILE" '
    '"$master_color_logic"'
    BEGIN {
        max_time = last_time
        count = 0
        scrape_count = 0
        stop_scraping = 0

        while ((getline line < db_file) > 0) {
            split(line, p, "|")
            if (p[1] == "GUILD") {
                db_guild_id[p[2]] = p[3]
                db_guild_name[p[3]] = p[2]
            } else if (p[1] ~ /^[0-9]+$/) {
                db_cols[p[1]] = length(p)
                db_qual[p[1]] = p[2]
                db_name[p[1]] = (length(p) >= 6) ? p[6] : p[3]
            }
        }
        close(db_file)
        '"$master_kiosk_logic"'
    }
    { sub(/\r$/, "") }
    /\["traderData"\]/ { in_trader_data = 1; in_guild_data = 0 }
    /\["guildData"\]/ { in_guild_data = 1; in_trader_data = 0 }

    in_trader_data && /^[ \t]*\["([^"]+)"\][ \t]*=[ \t]*$/ {
        match($0, /\["([^"]+)"\]/)
        val = substr($0, RSTART+2, RLENGTH-4)
        if (val != "NA Megaserver" && val != "EU Megaserver" && val != "PTS" && val != "guildHistory") {
            current_trader = val
        }
    }

    in_trader_data && /\["mapId"\][ \t]*=[ \t]*[0-9]+/ {
        match($0, /[0-9]+/)
        if (current_trader != "") {
            trader_maps[current_trader] = substr($0, RSTART, RLENGTH)
        }
    }

    in_trader_data && /^[ \t]*\[[0-9]+\][ \t]*=[ \t]*[0-9]+,?/ {
        match($0, /=[ \t]*[0-9]+/)
        if (RLENGTH > 0) {
            gid = substr($0, RSTART, RLENGTH)
            sub(/=[ \t]*/, "", gid)
            if (current_trader != "") {
                guild_kiosks[gid] = current_trader
                if (trader_maps[current_trader] != "") {
                    guild_maps[gid] = trader_maps[current_trader]
                }
            }
        }
    }

    in_guild_data && /^[ \t]*\[[0-9]+\][ \t]*=[ \t]*$/ {
        match($0, /[0-9]+/)
        current_guild_id = substr($0, RSTART, RLENGTH)
        buffered_gname = ""
        scan_type = ""
    }

    in_guild_data && /\["guildId"\][ \t]*=[ \t]*[0-9]+/ {
        match($0, /[0-9]+/)
        current_guild_id = substr($0, RSTART, RLENGTH)
        if (buffered_gname != "") {
            guild_names[current_guild_id] = buffered_gname
            db_guild_updated[buffered_gname] = current_guild_id
            buffered_gname = ""
        }
    }

    in_guild_data && /\["(traderGuildName|guildName)"\][ \t]*=[ \t]*"/ {
        match($0, /\["(traderGuildName|guildName)"\][ \t]*=[ \t]*"([^"]+)"/)
        if (RLENGTH > 0) {
            val = substr($0, RSTART, RLENGTH)
            sub(/.*\["(traderGuildName|guildName)"\][ \t]*=[ \t]*"/, "", val)
            sub(/".*$/, "", val)
            if (current_guild_id != "") {
                guild_names[current_guild_id] = val
                db_guild_updated[val] = current_guild_id
            } else {
                buffered_gname = val
            }
        }
    }

    /\["(scannedSales|scannedItems|cancelledItems|purchasedItems|traderHistory)"\]/ {
        match($0, /"(scannedSales|scannedItems|cancelledItems|purchasedItems|traderHistory)"/)
        stype = substr($0, RSTART+1, RLENGTH-2)
        if (stype == "scannedSales") scan_type = "Sold"
        else if (stype == "scannedItems") scan_type = "Listed"
        else if (stype == "cancelledItems") scan_type = "Cancelled"
        else if (stype == "purchasedItems") scan_type = "Purchased"
        else if (stype == "traderHistory") scan_type = "History"
    }

    index($0, ":item:") > 0 {
        if (scan_type == "") next
        s_idx = index($0, "\"|H")

        if (s_idx > 0) {
            t_str = substr($0, s_idx + 1)
            e_idx = index(t_str, "\",")
            if (e_idx == 0) e_idx = index(t_str, "\"")

            if (e_idx > 0) {
                full_val = substr(t_str, 1, e_idx - 1)
                split_idx = index(full_val, "|h|h,")
                offset = 5
                if (split_idx == 0) {
                    split_idx = index(full_val, "|h,")
                    offset = 3
                }

                if (split_idx > 0) {
                    item_link = substr(full_val, 1, split_idx + 1)
                    data_csv = substr(full_val, split_idx + offset)

                    split(item_link, lp, ":")
                    itemid = lp[3]
                    subtype = lp[4]
                    internal_level = lp[5]
                    s = subtype + 0
                    v = internal_level + 0

                    split(data_csv, arr, ",")
                    price = arr[1]
                    qty = arr[2]
                    buyer = ""
                    seller = ""
                    stime = 0

                    if (qty == "") qty = "1"

                    len = 0
                    for (i in arr) len++
                    if (len >= 5) {
                        buyer = arr[3]
                        seller = arr[4]
                        stime = arr[5] + 0
                    } else {
                        buyer = ""
                        seller = arr[3]
                        stime = arr[4] + 0
                    }

                    if (!(stime > 1400000000)) {
                        stime = 0
                        for (idx = length(arr); idx >= 3; idx--) {
                            if (arr[idx] ~ /^[0-9]+$/ && arr[idx] + 0 > 1400000000) {
                                stime = arr[idx] + 0
                                break
                            }
                        }
                    }

                    if (buyer != "" && buyer !~ /^@/) buyer = "@" buyer
                    if (seller != "" && seller !~ /^@/) seller = "@" seller

                    if (itemid in db_name && db_name[itemid] !~ /^Unknown Item/) {
                        real_name = db_name[itemid]
                    } else {
                        real_name = "Unknown Item (" itemid ")"
                    }

                    if (itemid in db_qual) {
                        real_qual = db_qual[itemid] + 0
                    } else {
                        real_qual = calc_quality(itemid, real_name, s, v)
                    }

                    needs_update = 0
                    if (index(real_name, "Unknown Item (") == 0) {
                        if (db_name[itemid] != real_name || db_qual[itemid] != real_qual) {
                            needs_update = 1
                        }
                        if (db_cols[itemid] < 7) needs_update = 1
                    }

                    if (needs_update) {
                        hq = get_hq(real_qual)
                        cat = get_cat(real_name, itemid, s, v)
                        update_str = itemid "|" real_qual "|" s "|" v "|" hq "|" real_name "|" cat
                        db_updated[itemid] = update_str
                        db_name[itemid] = real_name
                        db_qual[itemid] = real_qual
                        db_cols[itemid] = 7
                    }

                    if (real_name != "" && price != "") {
                        if (stime > max_time) max_time = stime
                        if (stime > last_time || stime == 0 || scan_type == "Listed") {
                            q_num = real_qual + 0
                            c = "\033[0m"
                            if(q_num==0) c="\033[90m"
                            else if(q_num==1) c="\033[97m"
                            else if(q_num==2) c="\033[32m"
                            else if(q_num==3) c="\033[36m"
                            else if(q_num==4) c="\033[35m"
                            else if(q_num==5) c="\033[33m"
                            else if(q_num==6) c="\033[38;5;214m"

                            link_start = "\033]8;;https://eso-hub.com/en/trading/" itemid "\033\\"
                            link_end = "\033]8;;\033\\"
                            item_display = link_start c real_name "\033[0m" link_end

                            trade_str = ""
                            if (seller != "" && buyer != "") {
                                trade_str = " by \033[36m" seller "\033[0m to \033[36m" buyer "\033[0m"
                            } else if (seller != "") {
                                trade_str = " by \033[36m" seller "\033[0m"
                            } else if (buyer != "") {
                                trade_str = " to \033[36m" buyer "\033[0m"
                            }

                            age = now_time - stime
                            status_tag = ""

                            if (scan_type == "Sold") {
                                status_tag = " \033[38;5;214m[SOLD]\033[0m"
                            } else if (scan_type == "Purchased") {
                                status_tag = " \033[92m[PURCHASED]\033[0m"
                            } else if (scan_type == "Cancelled") {
                                status_tag = " \033[31m[CANCELLED]\033[0m"
                            } else if (scan_type == "Listed") {
                                if (stime > 0 && age > 2592000) {
                                    status_tag = " \033[90m[EXPIRED]\033[0m"
                                } else {
                                    status_tag = " \033[34m[AVAILABLE]\033[0m"
                                }
                            }

                            lines[count] = stime "|" " \033[36m" scan_type "\033[0m for \033[32m" price \
                                           "\033[33mgold\033[0m - \033[32m" qty "x\033[0m " item_display \
                                           trade_str " in GUILD_PLACEHOLDER_" current_guild_id status_tag

                            if (current_guild_id != "") {
                                hist_lines[count] = "HISTORY|" stime "|" scan_type "|" price "|" qty "|" \
                                                    itemid "|" real_name "|" buyer "|" seller "|" \
                                                    current_guild_id "||" c "|ESO-Hub"
                            } else {
                                hist_lines[count] = ""
                            }

                            line_gid[count] = current_guild_id
                            count++
                        }
                    }
                }
            }
        }
    }
    END {
        for (gid in db_guild_name) {
            if (!(gid in guild_names)) {
                guild_names[gid] = db_guild_name[gid]
            }
        }

        for (i = 0; i < count; i++) {
            gid = line_gid[i]
            gname = guild_names[gid]
            if (gname == "") gname = db_guild_name[gid]

            l = lines[i]
            h = hist_lines[i]

            if (gname != "" && gname != "Unknown Guild") {
                g_link = "\033[35m\033]8;;|H1:guild:" gid "|h" gname "|h\033\\" gname "\033]8;;\033\\\033[0m"
            } else {
                g_link = "\033[35mUnknown Guild\033[0m"
                gname = "Unknown Guild"
            }

            kiosk = guild_kiosks[gid]
            k_str = ""
            if (kiosk != "") {
                map_id = guild_maps[gid]
                if (kiosk in k_dict) {
                    split(k_dict[kiosk], kp, "|")
                    k_loc = kp[1]
                    k_map = kp[2]
                    k_coords = kp[3]

                    if (k_map != "" && k_coords != "") {
                        k_str = " \033[90m(\033]8;;https://eso-hub.com/en/interactive-map" \
                                "?map=" k_map "&ping=" k_coords "\033\\" k_loc \
                                "\033]8;;\033\\)\033[0m"
                    } else if (k_map != "") {
                        k_str = " \033[90m(\033]8;;https://eso-hub.com/en/interactive-map" \
                                "?map=" k_map "\033\\" k_loc "\033]8;;\033\\)\033[0m"
                    } else {
                        k_str = " \033[90m(" k_loc ")\033[0m"
                    }
                } else if (map_id != "") {
                    k_str = " \033[90m(\033]8;;https://eso-hub.com/en/interactive-map" \
                            "?map=" map_id "\033\\" kiosk "\033]8;;\033\\)\033[0m"
                } else {
                    k_str = " \033[90m(" kiosk ")\033[0m"
                }
            }

            target_l = "GUILD_PLACEHOLDER_" gid
            idx_l = index(l, target_l)
            if (idx_l > 0) {
                l = substr(l, 1, idx_l - 1) g_link k_str substr(l, idx_l + length(target_l))
            }
            print l

            if (h != "") {
                target_h = gid "||"
                idx_h = index(h, target_h)
                if (idx_h > 0) {
                    h = substr(h, 1, idx_h - 1) gname "|" kiosk "|" substr(h, idx_h + length(target_h))
                }
                print h
            }
        }

        print "MAX_TIME:" max_time
        for (i in db_updated) {
            print "DB_UPDATE|" db_updated[i]
        }
        for (g in db_guild_updated) {
            print "DB_GUILD|" g "|" db_guild_updated[g]
        }
    }
    ' "$1"
}
AOM_REPO="$(_d 7571da8442f9e55021d9729e7b930306e69085fe2e 151)"
AOM_API="${LTTC_AOM_API:-$(_d d0d5663bff2f09d08179d31dd314ba8f7d134c78b388 23)}"
AOM_RAW="${LTTC_AOM_RAW:-$(_d abb079ae04222e5dd98d02a838291d72e676a85d221ab2ad154820b85bbe5a050e 202)}"
AOM_WORKFLOW_DIR="$(_d 6fd58258ddb3fdafde35a13f7b02e8df622d 88)"
AOM_ACCEPT="Accept: $(_d e72f300573f075a9472806feb415586bb146e4511f014fc70d78d6 117)"
AOM_WORKFLOWS="${AOM_WORKFLOW_DIR}data-tables-refresh.yml ${AOM_WORKFLOW_DIR}console-data-refresh.yml ${AOM_WORKFLOW_DIR}data-release.yml"
AOM_SLOTS="66 354 642 930 1218"
AOM_TABLES="KnownLibraries.lua KnownAddonVersions.lua KnownAddonDependencies.lua SuggestedCategories.lua KnownConsoleAddons.lua KnownConsoleLibraries.lua KnownConsoleAddonDependencies.lua ConsoleSuggestedCategories.lua"
AOM_SHOW_DETAILS=8
AOM_ASK_SECONDS=60
AOM_ASKED=false

AOM_MERGE_AWK='
function is_row(line) {
	return line !~ /^\t/ && index(line, "\t") > 0
}
function row_field(line, n,    parts) {
	split(line, parts, "\t")
	return parts[n]
}
function extract_key(line,    k) {
	if (is_row(line)) return row_field(line, 1)
	k = line
	if (sub(/^\t\["/, "", k)) {
		sub(/"\].*/, "", k)
		return k
	}
	k = line
	if (sub(/^\t/, "", k) && sub(/ = \{.*/, "", k) && k !~ / /) {
		return k
	}
	return ""
}
function extract_version(line,    v) {
	if (is_row(line)) {
		v = row_field(line, 2)
		return v ~ /^[0-9]+$/ ? v + 0 : -1
	}
	v = line
	if (sub(/.*requiredVersion = /, "", v)) {
		sub(/[^0-9].*/, "", v)
		return v + 0
	}
	return -1
}
function extract_display(line,    v) {
	if (is_row(line)) return row_field(line, 3)
	v = line
	if (sub(/.*displayVersion = "/, "", v)) {
		sub(/".*/, "", v)
		return v
	}
	return ""
}
function short_value(line,    v) {
	v = line
	if (is_row(line)) {
		sub(/^[^\t]*\t/, "", v)
		gsub(/\t/, " | ", v)
	} else {
		sub(/^[^=]*= */, "", v)
		sub(/,$/, "", v)
	}
	if (length(v) > 70) v = substr(v, 1, 67) "..."
	return v
}
function sort_key(k) {
	return tolower(k) "\001" k
}
BEGIN { footer = "}" }
{
	sub(/\r$/, "")
	if (FNR == 1 && substr($0, 1, 3) == "\357\273\277") $0 = substr($0, 4)
}
FNR == NR {
	key = extract_key($0)
	if (key != "") {
		if (!(key in local_line)) local_order[++n] = key
		local_line[key] = $0
		local_ver[key] = extract_version($0)
	} else if (!in_table) {
		header[++h] = $0
	}
	if ($0 ~ / = \{$/) { in_table = 1; footer = "}" }
	if ($0 ~ /\(\[==\[$/) { in_table = 1; footer = "]==])" }
	next
}
{
	key = extract_key($0)
	if (key == "") next
	rver = extract_version($0)
	rdisp = extract_display($0)
	if (!(key in local_line)) {
		local_order[++n] = key
		local_line[key] = $0
		local_ver[key] = rver
		added++
		added_detail[added] = key ": new entry, " (rver >= 0 ? "version " rver " (" rdisp ")" : short_value($0))
		next
	}
	if (local_line[key] == $0) next
	lver = local_ver[key]
	if (lver >= 0 && rver < 0) next
	if (lver >= 0 && rver < lver) next
	old_line = local_line[key]
	local_line[key] = $0
	local_ver[key] = rver
	updated++
	if (rver > lver && lver >= 0)
		updated_detail[updated] = key ": " lver " (" extract_display(old_line) ") -> " rver " (" rdisp ")"
	else
		updated_detail[updated] = key ": " short_value(old_line) " -> " short_value($0)
}
END {
	for (i = 1; i <= n; i++) sk[i] = sort_key(local_order[i])
	for (i = 2; i <= n; i++) {
		key_i = local_order[i]; sk_i = sk[i]
		j = i - 1
		while (j >= 1 && sk[j] "" > sk_i "") {
			local_order[j + 1] = local_order[j]; sk[j + 1] = sk[j]
			j--
		}
		local_order[j + 1] = key_i; sk[j + 1] = sk_i
	}
	for (i = 1; i <= h; i++) print header[i]
	for (i = 1; i <= n; i++) print local_line[local_order[i]]
	print footer
	print "ADDED=" added+0 > stats
	print "UPDATED=" updated+0 > stats
	for (i = 1; i <= added; i++) print "+ " added_detail[i] > stats
	for (i = 1; i <= updated; i++) print "~ " updated_detail[i] > stats
}'

aom_slots() {
    local now="$1" day m s latest=0 next=0 first="" last=""
    day=$((now - now % 86400))
    for m in $AOM_SLOTS; do
        [ -z "$first" ] && first="$m"
        last="$m"
        s=$((day + m * 60))
        if [ "$s" -le "$now" ]; then
            latest="$s"
        elif [ "$next" -eq 0 ]; then
            next="$s"
        fi
    done
    [ "$latest" -eq 0 ] && latest=$((day - 86400 + last * 60))
    [ "$next" -eq 0 ] && next=$((day + 86400 + first * 60))
    echo "$latest $next"
}

aom_wait_text() {
    local m=$(( ($1 + 59) / 60 ))
    if [ "$m" -ge 60 ]; then
        printf '%d h %d min' $((m / 60)) $((m % 60))
    else
        printf '%d min' "$m"
    fi
}

aom_repo_state() {
    local runs kind value pending=""
    runs=$(curl -fsS -m 20 -H "$AOM_ACCEPT" "$AOM_API/repos/$AOM_REPO/actions/runs?per_page=30" </dev/null 2>/dev/null) || { echo "unknown"; return; }
    while read -r kind value; do
        if [ "$kind" = "path" ]; then
            pending="$value"
        elif [ "$kind" = "status" ]; then
            if [ -n "$pending" ] && [ "$value" != "completed" ]; then
                case " $AOM_WORKFLOWS " in *" $pending "*) echo "updating"; return ;; esac
            fi
            pending=""
        fi
    done <<< "$(printf '%s' "$runs" | grep -oE '"(path|status)": *"[^"]*"' | sed -E 's/^"([a-z]+)": *"(.*)"$/\1 \2/')"
    echo "idle"
}

aom_installed() {
    [ -n "$ADDON_DIR" ] && [ -d "$ADDON_DIR/APH-OnManager/DATA" ]
}

aom_question() {
    echo -e "\e[0;32mAPH-OnManager is in your AddOns folder. Keep its add-on data up to date?\e[0m"
    echo -e "\e[0;90m(Its lists of add-on versions, libraries, dependencies and categories, checked an hour after each data refresh)\e[0m"
    echo -e "1) Yes \e[0;32m(Default)\e[0m"
    echo -e "2) No"
}

aom_set_answer() {
    if [ "$1" = "2" ]; then AOM_DATA_UPDATES=false; else AOM_DATA_UPDATES=true; fi
    write_ttc_log "INFO" "APH-OnManager data updates set to $AOM_DATA_UPDATES."
}

aom_can_ask() {
    [ "$SILENT" != true ] && { : < /dev/tty; } 2>/dev/null
}

aom_read_answer() {
    local ans=""
    read -r -t "$AOM_ASK_SECONDS" ans < /dev/tty 2>/dev/null || return 1
    printf '%s' "$ans"
}

aom_ask_now() {
    local ans
    if [ "$AOM_ASKED" = true ]; then
        ui_echo " \e[90mAPH-OnManager's data is left as it is until you answer. The updater asks again the next time it starts.\e[0m\n"
        return 1
    fi
    AOM_ASKED=true
    if ! aom_can_ask; then
        ui_echo " \e[90mAPH-OnManager was found. Start the updater in a terminal to choose whether to keep its data up to date.\e[0m\n"
        write_ttc_log "INFO" "APH-OnManager found; its data updates wait for an answer in a visible terminal."
        return 1
    fi
    aom_question
    echo -ne "\e[0;34mChoice [1-2]: \e[0m"
    if ! ans=$(aom_read_answer); then
        echo
        ui_echo " \e[90mNo answer, so APH-OnManager's data is left as it is. The updater asks again the next time it starts.\e[0m\n"
        return 1
    fi
    aom_set_answer "$ans"
    CONFIG_CHANGED=true
    [ "$AOM_DATA_UPDATES" = true ] && return 0
    ui_echo " \e[90mAPH-OnManager's data won't be updated. Run the updater with --setup to change this.\e[0m\n"
    return 1
}

aom_merge_table() {
    LC_ALL=C awk -v stats="$4" "$AOM_MERGE_AWK" "$1" "$2" > "$3"
}

run_aom_data_sync() {
    local dir="$ADDON_DIR/APH-OnManager"
    [ -d "$dir/DATA" ] || return 0
    [ "$AOM_DATA_UPDATES" = false ] && return 0
    ui_echo "\e[1m\e[97m [+] Updating APH-OnManager's Add-On Data \e[0m"
    if [ -L "$dir" ]; then
        ui_echo " \e[90mAPH-OnManager is a linked folder, so its data is left as it is.\e[0m\n"
        return 0
    fi
    if [ "$AOM_DATA_UPDATES" != true ]; then
        aom_ask_now || return 0
    fi

    local now slots latest next last="${AOM_LAST_SYNC:-0}"
    now="${CURRENT_TIME:-$(date +%s)}"
    slots=$(aom_slots "$now"); latest="${slots% *}"; next="${slots#* }"
    if [ "$last" -ge "$latest" ] 2>/dev/null && [ "$last" -le "$now" ]; then
        ui_echo " \e[90mChecked $(aom_wait_text $((now - last))) ago. Next check in $(aom_wait_text $((next - now))), an hour after the next data refresh.\e[0m\n"
        return 0
    fi

    if [ "$(aom_repo_state)" = "updating" ]; then
        ui_echo " \e[33mAPH-OnManager's data is being refreshed right now. \e[35mTrying again next cycle.\e[0m\n"
        NOTIF_AOM="Waiting For Refresh"
        write_ttc_log "INFO" "APH-OnManager data sync postponed: a data refresh is still running."
        return 0
    fi

    local base="$AOM_RAW/$AOM_REPO/main/DATA" sha work="$TEMP_DIR_ROOT/AoM_Data" f
    sha=$(curl -fsS -m 20 -H "$AOM_ACCEPT" "$AOM_API/repos/$AOM_REPO/commits/main" </dev/null 2>/dev/null \
        | grep -oE '"sha": *"[0-9a-f]{40}"' | head -n 1 | grep -oE '[0-9a-f]{40}')
    [ -n "$sha" ] && base="$AOM_RAW/$AOM_REPO/$sha/DATA"

    rm -rf "$work"; mkdir -p "$work"
    start_spinner "Downloading APH-OnManager's data tables..."
    for f in $AOM_TABLES; do
        if ! curl -fsSL -m 60 -o "$work/$f" "$base/$f" </dev/null 2>/dev/null; then
            stop_spinner 1 "Could not download $f"
            ui_echo " \e[90mNothing was changed. \e[35mTrying again next cycle.\e[0m\n"
            NOTIF_AOM="Download Failed"
            write_ttc_log "WARN" "APH-OnManager data sync failed: $f could not be downloaded."
            rm -rf "$work"
            return 0
        fi
    done
    stop_spinner 0 "Downloaded the data tables${sha:+ (commit ${sha:0:7})}"

    local changed=0 added updated shown more detail
    for f in $AOM_TABLES; do
        [ -f "$dir/DATA/$f" ] || continue
        if ! aom_merge_table "$dir/DATA/$f" "$work/$f" "$work/$f.merged" "$work/$f.stats" || [ ! -s "$work/$f.merged" ]; then
            ui_echo " \e[31m[-] Could not merge $f; it was left as it is.\e[0m"
            continue
        fi
        added=$(grep -m1 '^ADDED=' "$work/$f.stats" | cut -d= -f2)
        updated=$(grep -m1 '^UPDATED=' "$work/$f.stats" | cut -d= -f2)
        [ "${added:-0}" -eq 0 ] && [ "${updated:-0}" -eq 0 ] && continue
        cp -f "$work/$f.merged" "$dir/DATA/$f"
        changed=$((changed + 1))
        ui_echo " \e[92m$f\e[0m \e[90m${updated:-0} changed, ${added:-0} new\e[0m"
        write_ttc_log "INFO" "APH-OnManager data: $f updated (${updated:-0} changed, ${added:-0} new)."
        shown=0
        while IFS= read -r detail; do
            [ -n "$detail" ] || continue
            write_ttc_log "INFO" "APH-OnManager data: $detail"
            shown=$((shown + 1))
            [ "$shown" -le "$AOM_SHOW_DETAILS" ] && ui_echo " \t\e[90m$detail\e[0m"
        done <<< "$(grep -E '^[+~] ' "$work/$f.stats")"
        more=$((shown - AOM_SHOW_DETAILS))
        [ "$more" -gt 0 ] && ui_echo " \t\e[90m... and $more more (see the log)\e[0m"
    done
    rm -rf "$work"

    AOM_LAST_SYNC="$now"; CONFIG_CHANGED=true
    if [ "$changed" -gt 0 ]; then
        NOTIF_AOM="Updated ($changed)"
        ui_echo " \e[90mAPH-OnManager uses the new data after a /reloadui or your next login.\e[0m\n"
    else
        NOTIF_AOM="Up-to-date"
        ui_echo " \e[90mNo changes detected. \e[92mAPH-OnManager's data is up-to-date.\e[0m\n"
    fi
}
LEGACY_SCRIPT="$TARGET_DIR/Linux_Tamriel_Trade_Center.sh"
if [ -z "$LTTC_DEV" ] && [ -f "$LEGACY_SCRIPT" ] && ! cmp -s "$LTTC_SELF" "$LEGACY_SCRIPT"; then
    cp "$LTTC_SELF" "$LEGACY_SCRIPT" 2>/dev/null && chmod +x "$LEGACY_SCRIPT"
    write_ttc_log "INFO" "Replaced the old Linux script in $TARGET_DIR with the macOS script so existing shortcuts keep working."
fi
INSTALLED_SCRIPT="$TARGET_DIR/$SCRIPT_NAME"
if [ "$FORCE_SETUP" = true ]; then
    write_ttc_log "INFO" "Setup requested with --setup."
    wizard_first_run
elif [ "$SETUP_COMPLETE" = "true" ] && [ "$HAS_ARGS" = false ]; then
    if [ -f "$INSTALLED_SCRIPT" ] && [ -f "$CONFIG_FILE" ]; then
        clear
        echo -e "\e[0;32m[+] Configuration found! Using saved settings.\e[0m"
        echo -e "\e[0;36m-> Press 'y' to re-run setup, or wait 5 seconds...\e[0m\n"
        read -t 5 -p "Setup done, do you want to re-run setup? (y/N): " rerun_setup
        if [[ "$rerun_setup" =~ ^[Yy]$ ]]; then
            write_ttc_log "INFO" "User triggered setup wizard from startup."
            wizard_first_run
        else
            write_ttc_log "INFO" "Startup prompt timed out. Proceeding."
            if [ "$CURRENT_DIR" != "$TARGET_DIR" ]; then
                cp "$LTTC_SELF" "$TARGET_DIR/$SCRIPT_NAME" 2>/dev/null
            fi
        fi
    else
        write_ttc_log "WARN" "Config missing but flag true. Forcing setup."
        wizard_first_run
    fi
elif [ "$SETUP_COMPLETE" != "true" ] && [ "$HAS_ARGS" = false ]; then
    write_ttc_log "INFO" "No config found. Initiating setup."
    wizard_first_run
fi

if [ "$SILENT" = true ]; then exec >/dev/null 2>&1; fi
exec 3>&2

if [ "$AUTO_SRV" == "2" ]; then
    TTC_DOMAIN="eu.tamrieltradecentre.com"
else
    TTC_DOMAIN="us.tamrieltradecentre.com"
fi
TTC_URL="https://$TTC_DOMAIN/download/PriceTable"
SAVED_VAR_DIR="$(dirname "$ADDON_DIR")/SavedVariables"
repair_missing_names
TEMP_DIR="$TEMP_DIR_ROOT/Downloads"
[ -d "$HOME/Downloads/${OS_BRAND}_Tamriel_Trade_Center_Temp" ] && rm -rf "$HOME/Downloads/${OS_BRAND}_Tamriel_Trade_Center_Temp" 2>/dev/null
TTC_USER_AGENT="TamrielTradeCentreClient/1.0.0"
HM_USER_AGENT="HarvestMapClient/1.0.0"

USER_AGENTS=(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0"
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:121.0) Gecko/20100101 Firefox/121.0"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36 Edg/121.0.0.0"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 OPR/106.0.0.0"
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1"
)

ADDON_SETTINGS_FILE="$(dirname "$ADDON_DIR")/AddOnSettings.txt"

LAUNCH_METHOD="Terminal / .sh File"
if [ "$IS_STEAM_LAUNCH" = true ]; then LAUNCH_METHOD="Steam Launch Options"
elif [ "$IS_DESKTOP" = true ]; then LAUNCH_METHOD="Desktop Shortcut"
elif [ "$IS_TASK" = true ]; then LAUNCH_METHOD="Background Task"
fi
write_ttc_log "INFO" "========================================================="
write_ttc_log "INFO" "Script Initiated via: $LAUNCH_METHOD"

while true; do
    self_update_check
    CONFIG_CHANGED=false
    TEMP_DIR_USED=false
    CURRENT_TIME=$(date +%s)
    TEMP_SCAN_FILE="$TEMP_DIR_ROOT/LTTC_TempScan.log"
    > "$TEMP_SCAN_FILE"
    NOTIF_TTC="Up-to-date"
    NOTIF_EH="Up-to-date"
    NOTIF_HM="Up-to-date"
    NOTIF_ADDONS=""
    NOTIF_AOM=""
    FOUND_NEW_DATA=false
    > "$UI_STATE_FILE"
    write_ttc_log "INFO" "Main loop iteration started. Current time: $CURRENT_TIME"

    shuffled_uas=("${USER_AGENTS[@]}")
    for k in "${!shuffled_uas[@]}"; do
        j=$((RANDOM % ${#shuffled_uas[@]}))
        temp="${shuffled_uas[$k]}"
        shuffled_uas[$k]="${shuffled_uas[$j]}"
        shuffled_uas[$j]="$temp"
    done
    RAND_UA="${shuffled_uas[0]}"

    clear
    echo -ne "\033]0;$APP_TITLE - Created by @APHONIC\007"
    ui_echo "\e[0;92m===========================================================================\e[0m"
    ui_echo "\e[1m\e[0;94m                         $APP_TITLE\e[0m"
    ui_echo "\e[0;97m         Cross-Platform Auto-Updater for TTC, HarvestMap, ESO-Hub & ESOUI\e[0m"
    ui_echo "\e[0;90m                            Created by @APHONIC\e[0m"
    ui_echo "\e[0;92m===========================================================================\e[0m\n"
    ui_echo "Target AddOn Directory: \e[35m$ADDON_DIR\e[0m\n"

    mkdir -p "$TEMP_DIR" && cd "$TEMP_DIR" || exit
    
    download_if_missing "TamrielTradeCentre" "1245" "SKIP_DL_TTC"
    download_if_missing "HarvestMap" "57" "SKIP_DL_HM"
    download_if_missing "HarvestMapData" "3034" "SKIP_DL_HM"
    download_if_missing "LibEsoHubPrices" "4095" "SKIP_DL_EH"

    if [ "$SKIP_DL_EH" != true ]; then
        if [ ! -d "$ADDON_DIR/EsoTradingHub" ] || [ ! -d "$ADDON_DIR/EsoHubScanner" ]; then
            ans="y"
            if [ ! -f "/etc/os-release" ] || ! grep -qi "steamos" "/etc/os-release"; then
                echo -ne "\n \e[33m[?] ESO-Hub Addons missing. Download them? (y/N):\e[0m "
                read -r ans < /dev/tty
            fi
            
            if [[ "$ans" =~ ^[Yy]$ ]]; then
                write_ttc_log "INFO" "Fetching ESO-Hub addon versions."
                start_spinner "Downloading ESO-Hub Addons..."
                
                if ! esohub_fetch_addons; then
                    if [ "$ESOHUB_BLOCKED" = true ]; then
                        stop_spinner 1 "ESO-Hub's server is answering with a Cloudflare check; trying again next cycle"
                    else
                        stop_spinner 1 "Could not fetch ESO-Hub data ($ESOHUB_FAIL)"
                    fi
                    write_ttc_log "WARN" "ESO-Hub add-on install skipped ($ESOHUB_FAIL)."
                fi
                
                while IFS='|' read -r id_num fname srv_ver dl_url dl_sum _; do
                    if [ "$fname" = "LibEsoHubPrices" ]; then continue; fi
                    
                    if [ -n "$fname" ] && [ -n "$dl_url" ]; then
                        stop_spinner 0 "Fetching $fname"
                        start_spinner "Downloading $fname..."
                        if esohub_download "$dl_url" "$TEMP_DIR_ROOT/${fname}.zip" "$dl_sum"; then
                            
                            unzip -q -o "$TEMP_DIR_ROOT/${fname}.zip" -d "$ADDON_DIR/" > /dev/null 2>&1
                            rm -f "$TEMP_DIR_ROOT/${fname}.zip"
                            stop_spinner 0 "$fname installed"
                            write_ttc_log "INFO" "ESO-Hub Addon installed: $fname"
                            
                            var_name="EH_LOC_$id_num"
                            new_loc=$(esohub_local_version "$ADDON_DIR/$fname" "$fname")
                            printf -v "$var_name" "%s" "${new_loc:-$srv_ver}"
                            CONFIG_CHANGED=true
                            
                            settings_file="$ADDON_DIR/../AddOnSettings.txt"
                            if [ -f "$settings_file" ]; then
                                sed -i.bak -e "s/^$fname 0/$fname 1/g" "$settings_file" 2>/dev/null
                                grep -q "^$fname " "$settings_file" || echo "$fname 1" >> "$settings_file"
                                rm -f "$ADDON_DIR/../AddOnSettings.txt.bak" 2>/dev/null
                            fi
                        else
                            stop_spinner 1 "Download failed for $fname"
                        fi
                    fi
                done <<< "$ESOHUB_RECORDS"
            else
                ui_echo " \e[90mUser Declined ESO-Hub downloads.\e[0m"
                write_ttc_log "WARN" "Opted out of ESO-Hub."
                SKIP_DL_EH=true
                write_lttc_config
            fi
        fi
    fi

    HAS_TTC=$(is_addon_active "TamrielTradeCentre")
    HAS_HM=$(is_addon_active "HarvestMap")

    if [ "$ENABLE_LOCAL_MODE" != true ]; then
        ui_echo "\e[1m\e[97m [0/4] Synchronizing Local Database \e[0m\n \e[33mChecking updates...\e[0m"
        SRV_DB_VER="0.0.0"
        esoui_details "$ESOUI_DB_ID" && SRV_DB_VER="$ESOUI_VERSION"
        
        LOC_DB_VER="0.0.0"
        if [ -f "$DB_FILE" ]; then
            extracted_ver=$(head -n 1 "$DB_FILE" 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n 1)
            [ -n "$extracted_ver" ] && LOC_DB_VER="$extracted_ver"
        fi
        
        [ "$SRV_DB_VER" = "$LOC_DB_VER" ] && V_COL="\e[92m" || V_COL="\e[31m"
        ui_echo "\t\e[90mServer_DB_Version= ${V_COL}$SRV_DB_VER\e[0m"
        ui_echo "\t\e[90mLocal_DB_Version=  ${V_COL}$LOC_DB_VER\e[0m"

        HIST_SEEDED=false
        grep -q '^#HISTORY VERSION:' "$DB_DIR/LTTC_History.db" 2>/dev/null && HIST_SEEDED=true
        if [ "$SRV_DB_VER" != "0.0.0" ] && { version_newer "$SRV_DB_VER" "$LOC_DB_VER" || [ "$HIST_SEEDED" = false ]; }; then
            write_ttc_log "INFO" "Downloading database update v$SRV_DB_VER"
            start_spinner "Downloading database template v$SRV_DB_VER..."
            mkdir -p "$TEMP_DIR_ROOT/DB_Update"
            TEMP_DIR_USED=true
            
            if esoui_download "$ESOUI_DB_ID" "$TEMP_DIR_ROOT/DB_Update/db.zip"; then
                stop_spinner 0 "Database downloaded"
                unzip -q -o "$TEMP_DIR_ROOT/DB_Update/db.zip" -d "$TEMP_DIR_ROOT/DB_Update/" > /dev/null 2>&1
                NEW_DB=$(find "$TEMP_DIR_ROOT/DB_Update" -name "LTTC_Database.db" | head -n 1)
                NEW_HIST=$(find "$TEMP_DIR_ROOT/DB_Update" -name "LTTC_History.db" | head -n 1)
                
                if [ -n "$NEW_DB" ] && [ -f "$NEW_DB" ]; then
                    if [ ! -s "$DB_FILE" ]; then
                        echo "#DATABASE VERSION: $SRV_DB_VER" > "$DB_FILE"
                        grep -v '^#DATABASE VERSION:' "$NEW_DB" | tr -d '\r' >> "$DB_FILE"
                    else
                        start_spinner "Merging new database entries..."
                        awk -F'|' '
                        /^#DATABASE VERSION:/ { next }
                        {
                            sub(/\r$/, "")
                            if ($1 == "GUILD") key = "GUILD_"$2
                            else if ($1 == "KIOSK") key = "KIOSK_"$2
                            else if ($1 ~ /^[0-9]+$/) key = "ITEM_"$1
                            else key = $0
                            
                            if (!seen[key]) {
                                seen[key] = 1
                                print $0
                            }
                        }' "$DB_FILE" "$NEW_DB" > "$DB_FILE.tmp"
                        
                        echo "#DATABASE VERSION: $SRV_DB_VER" > "$DB_FILE"
                        cat "$DB_FILE.tmp" >> "$DB_FILE"
                        rm -f "$DB_FILE.tmp"
                        stop_spinner 0 "Database merged to v$SRV_DB_VER"
                    fi
                    
                    if [ -n "$NEW_HIST" ] && [ -f "$NEW_HIST" ]; then
                        start_spinner "Merging shared trade history..."
                        template_history_apply "$DB_DIR/LTTC_History.db" "$NEW_HIST" "$SRV_DB_VER"
                        stop_spinner 0 "Shared trade history merged"
                    else
                        template_history_apply "$DB_DIR/LTTC_History.db" /dev/null "$SRV_DB_VER"
                    fi
                else
                    stop_spinner 1 "LTTC_Database.db not found in zip"
                fi
                rm -rf "$TEMP_DIR_ROOT/DB_Update"
            else
                stop_spinner 1 "Database download failed"
            fi
        else
            ui_echo " \e[90mNo changes detected. \e[92mLocal database is up-to-date.\e[0m\n"
        fi
    fi

    [ "$ENABLE_LOCAL_MODE" != true ] && run_addon_updates
    if [ "$HAS_TTC" = "false" ]; then
        ui_echo "\e[1m\e[97m [1/4] & [2/4] Updating TTC Data (SKIPPED)\e[0m"
        ui_echo " \e[31m[-] TamrielTradeCentre not enabled.\e[0m\n"
        NOTIF_TTC="Skipped"
    else
        ui_echo "\e[1m\e[97m [1/4] Uploading your Local TTC Data \e[0m"
        TTC_CHANGED=true
        
        if [ -f "$SAVED_VAR_DIR/TamrielTradeCentre.lua" ] && [ -f "$SNAP_DIR/lttc_ttc_snapshot.lua" ]; then
            if [ ! "$SAVED_VAR_DIR/TamrielTradeCentre.lua" -nt "$SNAP_DIR/lttc_ttc_snapshot.lua" ]; then
                TTC_CHANGED=false
            fi
        fi
        
        if [ -f "$SAVED_VAR_DIR/TamrielTradeCentre.lua" ]; then
            if [ "$TTC_CHANGED" = false ]; then
                ui_echo " \e[90mNo TTC local changes detected. \e[35mSkipping upload.\e[0m\n"
            else
                TTC_EXTRACTED=false
                RAW_DATA=""
                if [ "$ENABLE_DISPLAY" = true ] && [ "$SILENT" = false ]; then
                    TTC_EXTRACTED=true
                    start_spinner "Parsing TamrielTradeCentre.lua..."
                    echo -e "\n\e[0;35m--- TTC Extracted Data ---\e[0m" >> "$TEMP_SCAN_FILE"
                    
                    ttc_extract "$SAVED_VAR_DIR/TamrielTradeCentre.lua" "$TTC_LAST_SALE" "$CURRENT_TIME" > "$TEMP_DIR_ROOT/lttc_ttc_tmp.out" 2>> "$LOG_FILE" &
                    
                    AWK_PID=$!
                    wait $AWK_PID
                    stop_spinner 0 "Extraction complete"
                    
                    AWK_OUT=$(< "$TEMP_DIR_ROOT/lttc_ttc_tmp.out")
                    rm -f "$TEMP_DIR_ROOT/lttc_ttc_tmp.out"
                    
                    NEXT_TIME=$(echo "$AWK_OUT" | grep "^MAX_TIME:" | cut -d':' -f2)
                    RAW_DATA=$(echo "$AWK_OUT" | grep -vE "^(MAX_TIME:|DB_UPDATE\||DB_GUILD\||DB_KIOSK\||HISTORY\|)")
                    DB_OUTPUT=$(echo "$AWK_OUT" | grep -E "^(DB_UPDATE\||DB_GUILD\||DB_KIOSK\|)")
                    HISTORY_OUTPUT=$(echo "$AWK_OUT" | grep "^HISTORY|")

                    if [ -n "$RAW_DATA" ]; then
                        FOUND_NEW_DATA=true
                        echo "$RAW_DATA" | while IFS='|' read -r ts output_str; do
                            if [ "$ts" = "0" ]; then
                                raw_line=" [\e[90mListing\e[0m]$output_str"
                            else
                                raw_line=" [TS:$ts]$output_str"
                            fi
                            ui_echo "$raw_line"
                            echo -e "$raw_line" >> "$TEMP_SCAN_FILE"
                        done
                    else
                        ui_echo " \e[90mNo new TTC items found. Upload skipped.\e[0m"
                    fi

                    if [ -n "$HISTORY_OUTPUT" ]; then
                        history_merge_report "$DB_DIR/LTTC_History.db" "$HISTORY_OUTPUT"
                    fi
                    
                    merge_db_updates "$DB_OUTPUT"
                    
                    if [ -n "$NEXT_TIME" ] && [ "$NEXT_TIME" != "$TTC_LAST_SALE" ]; then
                        TTC_LAST_SALE="$NEXT_TIME"
                        CONFIG_CHANGED=true
                    fi
                else
                    ui_echo " \e[90mExtraction disabled by user. Proceeding instantly...\e[0m"
                fi
                
                if [ "$ENABLE_LOCAL_MODE" = true ]; then
                    ui_echo "\n \e[90m[Local Mode] Skipping TTC Upload.\e[0m\n"
                    NOTIF_TTC="Extracted (No Upload)"
                    cp -f "$SAVED_VAR_DIR/TamrielTradeCentre.lua" "$SNAP_DIR/lttc_ttc_snapshot.lua" 2>/dev/null
                else
                    if [ "$TTC_EXTRACTED" = true ] && [ -z "$RAW_DATA" ]; then
                        NOTIF_TTC="No New Data"
                        cp -f "$SAVED_VAR_DIR/TamrielTradeCentre.lua" "$SNAP_DIR/lttc_ttc_snapshot.lua" 2>/dev/null
                    else
                        upload_domains="$TTC_DOMAIN"
                        [ "$AUTO_SRV" = "3" ] && upload_domains="us.tamrieltradecentre.com eu.tamrieltradecentre.com"
                        upload_ok=true
                        for up_domain in $upload_domains; do
                            up_region="NA"; [ "${up_domain%%.*}" = "eu" ] && up_region="EU"
                            start_spinner "Uploading to https://$up_domain..."
                            if ttc_upload "$up_domain" "$up_region" "$SAVED_VAR_DIR/TamrielTradeCentre.lua"; then
                                if [ "$TTC_UPLOAD_COUNT" -gt 0 ]; then
                                    stop_spinner 0 "Upload finished ($up_domain, $TTC_UPLOAD_COUNT listings)"
                                else
                                    stop_spinner 0 "Nothing new for $up_domain ($(ttc_nothing_new_reason))"
                                fi
                            else
                                upload_ok=false
                                stop_spinner 1 "Upload failed ($up_domain)"
                            fi
                        done
                        if [ "$upload_ok" = true ]; then
                            NOTIF_TTC="Data Uploaded"
                            cp -f "$SAVED_VAR_DIR/TamrielTradeCentre.lua" "$SNAP_DIR/lttc_ttc_snapshot.lua" 2>/dev/null
                        else
                            NOTIF_TTC="Upload Failed"
                        fi
                    fi
                fi
            fi
        else
            ui_echo " \e[33m[-] No TamrielTradeCentre.lua found. \e[35mSkipping.\e[0m\n"
        fi

        srv_list=()
        ttc_checked=false
        ttc_check_age=$((CURRENT_TIME - ${TTC_LAST_CHECK:-0}))
        if [ "$ttc_check_age" -ge 0 ] && [ "$ttc_check_age" -lt "$TTC_CHECK_EVERY" ]; then
            ui_echo "\e[1m\e[97m [2/4] Updating your Local TTC Data \e[0m"
            ui_echo " \e[90mTTC's price tables were checked $((ttc_check_age / 60)) min ago and change about once a day. \e[35mNext check in $(( (TTC_CHECK_EVERY - ttc_check_age + 59) / 60 )) min.\e[0m\n"
        else
            ui_echo "\e[1m\e[97m [2/4] Updating your Local TTC Data \e[0m\n \e[33mChecking TTC Server...\e[0m"
            TTC_LAST_CHECK="$CURRENT_TIME"
            CONFIG_CHANGED=true
            ttc_checked=true
            if [ "$AUTO_SRV" == "1" ] || [ "$AUTO_SRV" == "3" ]; then srv_list+=("NA"); fi
            if [ "$AUTO_SRV" == "2" ] || [ "$AUTO_SRV" == "3" ]; then srv_list+=("EU"); fi
        fi

        needs_dl=false
        dl_na=false
        dl_eu=false
        
        s_ver_na="0"; s_ver_eu="0"
        for srv in ${srv_list[@]+"${srv_list[@]}"}; do
            api_domain="us.tamrieltradecentre.com"
            if [ "$srv" == "EU" ]; then api_domain="eu.tamrieltradecentre.com"; fi
            
            API_RESP=$(curl -s -m 10 -A "$TTC_USER_AGENT" "https://$api_domain/api/GetTradeClientVersion" 2>/dev/null)
            s_ver=$(echo "$API_RESP" | grep -o '"PriceTableVersion":[^,}]*' | cut -d':' -f2 | tr -d ' ' | tr -d '"')
            
            if [ -z "$s_ver" ] || ! [[ "$s_ver" =~ ^[0-9]+$ ]]; then
                s_ver="0"
                ui_echo " \e[31m[-] Could not fetch TTC version for $srv.\e[0m"
            fi
            
            if [ "$srv" == "NA" ]; then s_ver_na="$s_ver"; else s_ver_eu="$s_ver"; fi
            
            pt_file="$ADDON_DIR/TamrielTradeCentre/PriceTable${srv}.lua"
            loc_ver="$(ttc_price_table_version "$pt_file")"
            
            loc_disp="$loc_ver"
            [ "$loc_ver" = "0" ] && loc_disp="None"
            s_ver_disp="$s_ver"
            [ "$s_ver" = "0" ] && s_ver_disp="Error"
            
            s_col="\e[92m"; [ "$s_ver" = "0" ] && s_col="\e[31m"
            loc_col="\e[92m"; { [ "$s_ver" != "0" ] && [ "$s_ver" != "$loc_ver" ]; } && loc_col="\e[31m"
            
            ui_echo " \t\e[90mServer Version ($srv): ${s_col}$s_ver_disp\e[0m"
            ui_echo " \t\e[90mLocal Version ($srv):  ${loc_col}$loc_disp\e[0m"
            
            if [ "$s_ver" != "0" ] && [ "$s_ver" -gt "$loc_ver" ] 2>/dev/null; then 
                needs_dl=true
                if [ "$srv" == "NA" ]; then dl_na=true; fi
                if [ "$srv" == "EU" ]; then dl_eu=true; fi
            fi
        done

        if [ "$needs_dl" = true ]; then
                ui_echo " \e[92mNew TTC Price Table available \e[0m"
                ttc_diff=$((CURRENT_TIME - TTC_LAST_DOWNLOAD))
                
                if [ "$ENABLE_LOCAL_MODE" = true ]; then
                    ui_echo " \e[90m[Local Mode] Download Skipped.\e[0m\n"
                elif [ "$ttc_diff" -lt 3600 ] && [ "$ttc_diff" -ge 0 ]; then
                    wait_m=$(( (3600 - ttc_diff) / 60 ))
                    if [ "$NOTIF_TTC" = "Data Uploaded" ]; then NOTIF_TTC="Uploaded (DL Cooldown)"
                    else NOTIF_TTC="Download Cooldown"; fi
                    ui_echo " \e[33mdownload is on cooldown ($wait_m min). \e[35mSkipping.\e[0m\n"
                else
                    success_all=true
                    TEMP_DIR_USED=true
                    rate_limit=false
                    
                    for srv in "${srv_list[@]}"; do
                        if [ "$srv" == "NA" ] && [ "$dl_na" = false ]; then continue; fi
                        if [ "$srv" == "EU" ] && [ "$dl_eu" = false ]; then continue; fi
                        
                        if [ "$srv" == "NA" ]; then
                            dl_url="https://us.tamrieltradecentre.com/download/PriceTable"
                        else
                            dl_url="https://eu.tamrieltradecentre.com/download/PriceTable"
                        fi
                        
                        start_spinner "Downloading TTC Price Table ($srv)..."
                        curl -s -f -A "$TTC_USER_AGENT" -L -o "TTC-data-${srv}.zip" "$dl_url"
                        c_exit=$?
                        
                        success=false
                        if [ $c_exit -eq 22 ]; then
                            rate_limit=true
                            stop_spinner 1 "TTC Rate Limit reached ($srv)"
                            success_all=false; break
                        elif [ $c_exit -eq 0 ] && unzip -t "TTC-data-${srv}.zip" >/dev/null 2>&1; then
                            success=true
                        fi
                        
                        if [ "$success" = false ] && [ "$rate_limit" = false ]; then
                            stop_spinner 1 "Primary UA blocked ($srv)"
                            start_spinner "Retrying with fallback User-Agent ($srv)..."
                            for UA in "${shuffled_uas[@]}"; do
                                curl -s -f -H "User-Agent: $UA" -L -o "TTC-data-${srv}.zip" "$dl_url"
                                c_exit=$?
                                if [ $c_exit -eq 22 ]; then
                                    rate_limit=true
                                    stop_spinner 1 "TTC Rate Limit reached ($srv)"
                                    success_all=false; break 2
                                elif [ $c_exit -eq 0 ] && unzip -t "TTC-data-${srv}.zip" >/dev/null 2>&1; then
                                    success=true; break
                                fi
                            done
                        fi
                        
                        if [ "$success" = true ]; then
                            unzip -o "TTC-data-${srv}.zip" -d "TTC_Extracted_${srv}" > /dev/null
                            stop_spinner 0 "TTC Updated ($srv)"
                        else
                            stop_spinner 1 "TTC download failed ($srv)"
                            success_all=false
                        fi
                    done
                    
                    has_na=false; [ -d "TTC_Extracted_NA" ] && has_na=true
                    has_eu=false; [ -d "TTC_Extracted_EU" ] && has_eu=true
                    
                    if [ "$success_all" = true ] || [ "$has_na" = true ] || [ "$has_eu" = true ]; then
                        mkdir -p "$ADDON_DIR/TamrielTradeCentre"
                        
                        if [ "$has_na" = true ]; then
                            cp -R TTC_Extracted_NA/. "$ADDON_DIR/TamrielTradeCentre/"
                        fi
                        
                        if [ "$has_eu" = true ]; then
                            cp -R TTC_Extracted_EU/. "$ADDON_DIR/TamrielTradeCentre/"
                        fi
                        
                        TTC_LAST_DOWNLOAD=$CURRENT_TIME
                        CONFIG_CHANGED=true
                        
                        if [ "$NOTIF_TTC" = "Data Uploaded" ]; then NOTIF_TTC="Uploaded & Updated"
                        else NOTIF_TTC="Updated"; fi
                        echo ""
                    elif [ "$rate_limit" = false ]; then
                        if [ "$NOTIF_TTC" = "Data Uploaded" ]; then NOTIF_TTC="Uploaded, DL Failed"
                        else NOTIF_TTC="Download Error"; fi
                    fi
                fi
            elif [ "$ttc_checked" = true ]; then
                ui_echo " \e[90mNo changes detected. \e[92mLocal PriceTable is up-to-date.\e[0m\n"
            fi
        fi

    ui_echo "\e[1m\e[97m [3/4] Updating ESO-Hub Prices & Uploading Scans \e[0m"
    ui_echo " \e[36mFetching latest ESO-Hub version data...\e[0m"

    esohub_reload_cf
    EH_LAST_CHECK="$CURRENT_TIME"
    CONFIG_CHANGED=true
    EH_UPLOAD_COUNT=0
    EH_UPDATE_COUNT=0

    EH_FETCHED=false
    esohub_fetch_addons && EH_FETCHED=true
    if [ "$EH_FETCHED" = false ] && [ "$ESOHUB_BLOCKED" = true ]; then
        if esohub_cf_ask_now; then
            ui_echo " \e[36mFetching latest ESO-Hub version data...\e[0m"
            if esohub_fetch_addons; then
                EH_FETCHED=true; ESOHUB_CF_ASKED=false
                write_ttc_log "INFO" "ESO-Hub accepted the browser check."
            elif [ "$ESOHUB_BLOCKED" = true ]; then
                ui_echo " \e[31m[-] ESO-Hub still answers with a Cloudflare check. Copy cf_clearance from the browser that opened, on this PC and network.\e[0m"
            fi
        elif [ -n "$ESOHUB_CF_HINT" ]; then
            ui_echo " \e[90m$ESOHUB_CF_HINT\e[0m"
        fi
    fi

    if [ "$EH_FETCHED" = false ]; then
        if [ "$ESOHUB_BLOCKED" = true ]; then
            NOTIF_EH="Skipped (ESO-Hub server check)"
            ui_echo " \e[35mSkipping ESO-Hub this cycle.\e[0m \e[90m($ESOHUB_FAIL)\e[0m\n"
            write_ttc_log "WARN" "ESO-Hub skipped: Cloudflare check instead of data ($ESOHUB_FAIL)."
        else
            NOTIF_EH="Download Error"
            ui_echo " \e[31m[-] Could not fetch ESO-Hub data.\e[0m \e[90m($ESOHUB_FAIL)\e[0m\n"
            write_ttc_log "ERROR" "Could not fetch ESO-Hub data ($ESOHUB_FAIL)."
        fi
    else
        EH_TIME_DIFF=$((CURRENT_TIME - EH_LAST_DOWNLOAD))
        EH_DOWNLOAD_OCCURRED=false

        while IFS='|' read -r ID_NUM FNAME SRV_VER DL_URL DL_SUM UP_EP SV_LIST; do
            if [ -z "$FNAME" ]; then continue; fi

            HAS_THIS_EH=$(is_addon_active "$FNAME")
            if [ "$HAS_THIS_EH" = "false" ]; then
                ui_echo " \e[31m[-] $FNAME missing. \e[35mSkipping.\e[0m"
                continue
            fi

            PREFIX="$FNAME"
            [ "$FNAME" = "EsoTradingHub" ] && PREFIX="ETH5"
            [ "$FNAME" = "LibEsoHubPrices" ] && PREFIX="LEHP7"
            [ "$FNAME" = "EsoHubScanner" ] && PREFIX="EHS"

            VAR_LOC_NAME="EH_LOC_$ID_NUM"
            LOC_VER=$(esohub_local_version "$ADDON_DIR/$FNAME" "$FNAME")
            if [ -n "$LOC_VER" ]; then
                if [ "${!VAR_LOC_NAME}" != "$LOC_VER" ]; then
                    printf -v "$VAR_LOC_NAME" "%s" "$LOC_VER"
                    CONFIG_CHANGED=true
                fi
            else
                LOC_VER="${!VAR_LOC_NAME}"
                [ -z "$LOC_VER" ] && LOC_VER="0"
                if [ "$LOC_VER" = "0" ] && [ -d "$ADDON_DIR/$FNAME" ]; then
                    LOC_VER="$SRV_VER"
                    printf -v "$VAR_LOC_NAME" "%s" "$SRV_VER"
                    CONFIG_CHANGED=true
                fi
            fi

            EH_NEWER=false
            esohub_is_newer "$SRV_VER" "$LOC_VER" && EH_NEWER=true
            EH_SRV_COL="\e[92m"; EH_LOC_COL="\e[92m"; [ "$EH_NEWER" = true ] && EH_LOC_COL="\e[31m"

            ui_echo " \e[33mChecking server for $FNAME.zip...\e[0m"
            ui_echo "\t\e[90m${PREFIX}_Server_Version= ${EH_SRV_COL}$SRV_VER\e[0m"
            ui_echo "\t\e[90m${PREFIX}_Local_Version= ${EH_LOC_COL}$LOC_VER\e[0m"

            EH_SEND=""
            EH_SENT_SNAPS=""
            EH_ALL_SV=""
            if [ -n "$UP_EP" ] && [ -n "$SV_LIST" ]; then
                while IFS= read -r SV_NAME; do
                    [ -z "$SV_NAME" ] && continue
                    [ -f "$SAVED_VAR_DIR/$SV_NAME" ] || continue
                    EH_ALL_SV="${EH_ALL_SV:+$EH_ALL_SV;}$SV_NAME"
                    eh_snap_name=$(echo "$SV_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/\.lua//')
                    UP_SNAP="$SNAP_DIR/lttc_eh_${eh_snap_name}_snapshot.lua"

                    if [ -f "$UP_SNAP" ] && [ ! "$SAVED_VAR_DIR/$SV_NAME" -nt "$UP_SNAP" ]; then
                        ui_echo " \e[90mNo changes detected in $SV_NAME. \e[35mSkipping upload.\e[0m"
                        continue
                    fi

                    EH_EXTRACTED=false
                    RAW_DATA=""
                    if [ "$SV_NAME" = "EsoTradingHub.lua" ] && [ "$ENABLE_DISPLAY" = true ] && [ "$SILENT" = false ]; then
                        EH_EXTRACTED=true
                        start_spinner "Parsing $SV_NAME..."
                        echo -e "\n\e[0;35m--- ESO-Hub Extracted Data ---\e[0m" >> "$TEMP_SCAN_FILE"

                        esohub_extract "$SAVED_VAR_DIR/$SV_NAME" "$EH_LAST_SALE" "$CURRENT_TIME" > "$TEMP_DIR_ROOT/lttc_eh_tmp.out" 2>> "$LOG_FILE" &

                        AWK_PID=$!
                        wait $AWK_PID
                        stop_spinner 0 "Extraction complete"

                        AWK_OUT=$(< "$TEMP_DIR_ROOT/lttc_eh_tmp.out")
                        rm -f "$TEMP_DIR_ROOT/lttc_eh_tmp.out"

                        NEXT_TIME=$(echo "$AWK_OUT" | grep "^MAX_TIME:" | cut -d':' -f2)
                        RAW_DATA=$(echo "$AWK_OUT" | grep -vE "^(MAX_TIME:|DB_UPDATE\||DB_GUILD\||HISTORY\|)")
                        DB_OUTPUT=$(echo "$AWK_OUT" | grep -E "^(DB_UPDATE\||DB_GUILD\|)")
                        HISTORY_OUTPUT=$(echo "$AWK_OUT" | grep "^HISTORY|")

                        if [ -n "$RAW_DATA" ]; then
                            FOUND_NEW_DATA=true
                            echo "$RAW_DATA" | while IFS='|' read -r ts output_str; do
                                if [ "$ts" = "0" ]; then
                                    raw_line=" [\e[90mListing\e[0m]$output_str"
                                else
                                    raw_line=" [TS:$ts]$output_str"
                                fi
                                ui_echo "$raw_line"
                                echo -e "$raw_line" >> "$TEMP_SCAN_FILE"
                            done
                        else
                            ui_echo " \e[90mNo new ESO-Hub items found. Upload skipped.\e[0m"
                        fi

                        if [ -n "$HISTORY_OUTPUT" ]; then
                            history_merge_report "$DB_DIR/LTTC_History.db" "$HISTORY_OUTPUT"
                        fi

                        merge_db_updates "$DB_OUTPUT"

                        if [ -n "$NEXT_TIME" ] && [ "$NEXT_TIME" != "$EH_LAST_SALE" ]; then
                            EH_LAST_SALE="$NEXT_TIME"
                            CONFIG_CHANGED=true
                        fi
                    else
                        if [ "$SV_NAME" = "EsoTradingHub.lua" ] && [ "$ENABLE_DISPLAY" = false ] && [ "$SILENT" = false ]; then
                            ui_echo " \e[90mExtraction disabled by user. Proceeding instantly to upload...\e[0m"
                        fi
                    fi

                    if [ "$ENABLE_LOCAL_MODE" = true ]; then
                        ui_echo " \e[90m[Local Mode] Skipping ESO-Hub Upload ($SV_NAME).\e[0m"
                        cp -f "$SAVED_VAR_DIR/$SV_NAME" "$UP_SNAP" 2>/dev/null
                    elif [ "$SV_NAME" = "EsoTradingHub.lua" ] && [ "$EH_EXTRACTED" = true ] && [ -z "$RAW_DATA" ]; then
                        cp -f "$SAVED_VAR_DIR/$SV_NAME" "$UP_SNAP" 2>/dev/null
                    elif [ "$SV_NAME" = "EsoHubScanner.lua" ] && ! grep -qE '\|H[0-9a-fA-F]*:item:[0-9]+' "$SAVED_VAR_DIR/$SV_NAME" 2>/dev/null; then
                        cp -f "$SAVED_VAR_DIR/$SV_NAME" "$UP_SNAP" 2>/dev/null
                    else
                        EH_SEND="${EH_SEND:+$EH_SEND;}$SV_NAME"
                        EH_SENT_SNAPS="${EH_SENT_SNAPS:+$EH_SENT_SNAPS;}$UP_SNAP"
                    fi
                done <<< "$(printf '%s' "$SV_LIST" | tr ';' '\n')"
            fi

            if [ -n "$EH_SEND" ]; then
                EH_SEND_SHOWN=$(printf '%s' "$EH_SEND" | sed 's/;/, /g')
                start_spinner "Uploading local scan data ($EH_SEND_SHOWN)..."
                if esohub_upload "$ESOHUB_API_USED" "$UP_EP" "$EH_SEND" "$EH_ALL_SV"; then
                    EH_I=1
                    while IFS= read -r SV_NAME; do
                        [ -z "$SV_NAME" ] && continue
                        UP_SNAP=$(printf '%s' "$EH_SENT_SNAPS" | cut -d';' -f"$EH_I")
                        cp -f "$SAVED_VAR_DIR/$SV_NAME" "$UP_SNAP" 2>/dev/null
                        EH_I=$((EH_I + 1))
                    done <<< "$(printf '%s' "$EH_SEND" | tr ';' '\n')"
                    EH_UPLOAD_COUNT=$((EH_UPLOAD_COUNT + 1))
                    stop_spinner 0 "Upload finished ($EH_SEND_SHOWN)"
                else
                    stop_spinner 1 "Upload failed ($EH_SEND_SHOWN)"
                    write_ttc_log "ERROR" "ESO-Hub upload of $EH_SEND_SHOWN failed on both API versions."
                fi
            fi

            if [ -n "$DL_URL" ]; then
                if [ "$EH_NEWER" = false ]; then
                    ui_echo " \e[90mNo changes detected. \e[92m($FNAME.zip) is up-to-date. \e[35mSkipping download.\e[0m"
                else
                    if [ "$ENABLE_LOCAL_MODE" = true ]; then
                        ui_echo " \e[90m[Local Mode] Skipping Download for $FNAME.zip.\e[0m"
                    elif [ "$EH_TIME_DIFF" -lt 3600 ] && [ "$EH_TIME_DIFF" -ge 0 ]; then
                        WAIT_MINS=$(( (3600 - EH_TIME_DIFF) / 60 ))
                        ui_echo " \e[33mNew $FNAME.zip available, but download is on cooldown for $WAIT_MINS more minutes. \e[35mSkipping.\e[0m"
                    else
                        start_spinner "Downloading $FNAME.zip..."
                        TEMP_DIR_USED=true
                        cd "$TEMP_DIR_ROOT" || continue

                        esohub_download "$DL_URL" "$TEMP_DIR_ROOT/EH_$ID_NUM.zip" "$DL_SUM"
                        EH_DL_RC=$?
                        if [ "$EH_DL_RC" -eq 0 ]; then
                            rm -rf ESOHub_Extracted
                            unzip -o "EH_$ID_NUM.zip" -d ESOHub_Extracted > /dev/null
                            cp -R ESOHub_Extracted/. "$ADDON_DIR/"

                            EH_NEW_LOC=$(esohub_local_version "$ADDON_DIR/$FNAME" "$FNAME")
                            printf -v "$VAR_LOC_NAME" "%s" "${EH_NEW_LOC:-$SRV_VER}"
                            CONFIG_CHANGED=true
                            EH_DOWNLOAD_OCCURRED=true
                            EH_UPDATE_COUNT=$((EH_UPDATE_COUNT + 1))
                            stop_spinner 0 "$FNAME.zip updated successfully"
                        elif [ "$EH_DL_RC" -eq 2 ]; then
                            stop_spinner 1 "Error: $FNAME.zip failed its checksum, not installed"
                        else
                            stop_spinner 1 "Error: $FNAME.zip download corrupted"
                        fi
                    fi
                fi
            fi
        done <<< "$ESOHUB_RECORDS"

        if [ "$EH_DOWNLOAD_OCCURRED" = true ]; then
            EH_LAST_DOWNLOAD=$CURRENT_TIME
        fi

        if [ "$EH_UPDATE_COUNT" -gt 0 ] || [ "$EH_UPLOAD_COUNT" -gt 0 ]; then
            NOTIF_EH="Updated ($EH_UPDATE_COUNT), Uploaded ($EH_UPLOAD_COUNT)"
        fi
        ui_echo ""
    fi
    if [ "$HAS_HM" = "false" ] || [ "$ENABLE_LOCAL_MODE" = true ]; then
        NOTIF_HM="Skipped"
        ui_echo "\e[1m\e[97m [4/4] Updating HarvestMap Data (SKIPPED) \e[0m"
        if [ "$ENABLE_LOCAL_MODE" = true ]; then
            ui_echo " \e[90m[Local Mode] Skipping HarvestMap updates.\e[0m\n"
        else
            ui_echo " \e[31m[-] HarvestMap not enabled in AddOnSettings.txt. \e[35mSkipping...\e[0m\n"
        fi
    else
        HM_DIR="$ADDON_DIR/HarvestMapData"
        EMPTY_FILE="$HM_DIR/Main/emptyTable.lua"
        MAIN_HM_FILE="$SAVED_VAR_DIR/HarvestMap.lua"
        HM_SNAP="$SNAP_DIR/lttc_hm_main_snapshot.lua"
        
        if [[ -d "$HM_DIR" ]]; then
            HM_CHANGED=true
            LOCAL_HM_STATUS="Out-of-Sync"
            
            if [[ -f "$MAIN_HM_FILE" ]]; then
                if [[ -f "$HM_SNAP" ]] && [ ! "$MAIN_HM_FILE" -nt "$HM_SNAP" ]; then
                    HM_CHANGED=false
                    LOCAL_HM_STATUS="Synced"
                fi
            fi
            
            HM_LAST_CHECK="$CURRENT_TIME"
            CONFIG_CHANGED=true
            [ "$HM_CHANGED" = false ] && V_COL="\e[92m" || V_COL="\e[31m"
            
            ui_echo "\e[1m\e[97m [4/4] Updating HarvestMap Data \e[0m"
            ui_echo " \e[33mVerifying HarvestMap local data state...\e[0m"
            if [ "${HM_LAST_DOWNLOAD:-0}" -gt 0 ] 2>/dev/null; then
                ui_echo "\t\e[90mLast_Download= \e[92m$(get_relative_time "$HM_LAST_DOWNLOAD")\e[0m"
            else
                ui_echo "\t\e[90mLast_Download= \e[31mNever\e[0m"
            fi
            ui_echo "\t\e[90mLocal_Data_Status= ${V_COL}$LOCAL_HM_STATUS\e[0m"
            
            if [[ "$HM_CHANGED" = false ]]; then
                ui_echo " \e[90mNo changes detected. \e[92mHarvestMap.lua up-to-date.\e[0m\n"
            else
                HM_TIME_DIFF=$((CURRENT_TIME - HM_LAST_DOWNLOAD))
                if [ "$HM_TIME_DIFF" -lt 3600 ] && [ "$HM_TIME_DIFF" -ge 0 ]; then
                    WAIT_MINS=$(( (3600 - HM_TIME_DIFF) / 60 ))
                    NOTIF_HM="Cooldown ($WAIT_MINS min)"
                    ui_echo " \e[33mLocal changes detected, but download is on cooldown for"
                    ui_echo " $WAIT_MINS more minutes. \e[35mSkipping.\e[0m\n"
                else
                    mkdir -p "$SAVED_VAR_DIR"
                    hmFailed=false
                    
                    ui_echo " \e[36mTargeting following database chunks for merge:\e[0m"
                    for zone in AD EP DC DLC NF; do
                        ui_echo " \e[90m-> $HM_DIR/Modules/HarvestMap${zone}/HarvestMap${zone}.lua\e[0m"
                    done
                    
                    start_spinner "Preparing HarvestMap data..."
                    for zone in AD EP DC DLC NF; do
                        update_spinner "Merging local HarvestMap ${zone} data..."
                        svfn1="$SAVED_VAR_DIR/HarvestMap${zone}.lua"
                        svfn2="${svfn1}~"
                        
                        if [[ -e "$svfn1" ]]; then
                            mv -f "$svfn1" "$svfn2"
                        else
                            name="Harvest${zone}_SavedVars"
                            if [[ -f "$EMPTY_FILE" ]]; then
                                echo -n "$name" | cat - "$EMPTY_FILE" > "$svfn2" 2>/dev/null
                            else
                                echo -n "$name={[\"data\"]={}}" > "$svfn2"
                            fi
                        fi
                        
                        mkdir -p "$HM_DIR/Modules/HarvestMap${zone}"
                        
                        update_spinner "Downloading HarvestMap ${zone} chunk..."
                        if ! curl -s -f -L -A "$HM_USER_AGENT" -d @"$svfn2" \
                            -o "$HM_DIR/Modules/HarvestMap${zone}/HarvestMap${zone}.lua" \
                            "http://harvestmap.binaryvector.net:8081"; then
                            
                            if ! curl -s -f -L -H "User-Agent: $RAND_UA" -d @"$svfn2" \
                                -o "$HM_DIR/Modules/HarvestMap${zone}/HarvestMap${zone}.lua" \
                                "http://harvestmap.binaryvector.net:8081"; then
                                hmFailed=true
                            fi
                        fi
                    done
                    
                    if [ "$hmFailed" = false ]; then
                        [[ -f "$MAIN_HM_FILE" ]] && cp -f "$MAIN_HM_FILE" "$HM_SNAP" 2>/dev/null
                        HM_LAST_DOWNLOAD=$CURRENT_TIME
                        CONFIG_CHANGED=true
                        NOTIF_HM="Updated successfully"
                        stop_spinner 0 "HarvestMap Data Successfully Updated"
                        echo ""
                    else
                        NOTIF_HM="Error (Server Blocked)"
                        stop_spinner 1 "HarvestMap Update Failed"
                        echo ""
                    fi
                fi
            fi
        else
            NOTIF_HM="Not Found (Skipped)"
            ui_echo "\e[1m\e[97m [4/4] Updating HarvestMap Data (SKIPPED) \e[0m"
            ui_echo " \e[31m[!] HarvestMapData folder not found in: $ADDON_DIR. \e[35mSkipping...\e[0m\n"
        fi
    fi

    [ "$ENABLE_LOCAL_MODE" != true ] && run_aom_data_sync
    if [ "$FOUND_NEW_DATA" = true ]; then mv -f "$TEMP_SCAN_FILE" "$LAST_SCAN_FILE"; fi
    
    prune_history
    
    if [ "$CONFIG_CHANGED" = true ]; then write_lttc_config; fi
    
    cd "$HOME" || exit
    start_spinner "Cleaning up temp files & old logs..."
    
    if [ -f "$LOG_FILE" ]; then
        cutoff_date=$(date -v-3d '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
        
        if [ -n "$cutoff_date" ]; then
            awk -v cutoff="$cutoff_date" '
            BEGIN { keep = 0 }
            /^\[[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\]/ {
                log_date = substr($0, 2, 19)
                keep = (log_date >= cutoff) ? 1 : 0
            }
            {
                if (keep) print $0
            }' "$LOG_FILE" > "$TEMP_DIR_ROOT/log_prune.tmp" 2>/dev/null
            
            if [ -f "$TEMP_DIR_ROOT/log_prune.tmp" ]; then
                cat "$TEMP_DIR_ROOT/log_prune.tmp" > "$LOG_FILE"
                rm -f "$TEMP_DIR_ROOT/log_prune.tmp"
            fi
        fi
    fi
    
    DEL_COUNT=0
    CLEAN_LOG="$TEMP_DIR_ROOT/cleanup.log"
    > "$CLEAN_LOG"
    
    for target in "$TEMP_DIR" "$TEMP_DIR_ROOT"/*.tmp "$TEMP_DIR_ROOT"/*.out \
                  "$TEMP_DIR_ROOT"/*.zip "$TEMP_DIR_ROOT"/ESOHub_Extracted \
                  "$TEMP_DIR_ROOT"/lttc_upload.* "$TEMP_DIR_ROOT"/DB_Update \
                  "$TEMP_DIR_ROOT"/AoM_Data; do
        if [ -e "$target" ]; then
            find "$target" -type f -o -type d 2>/dev/null >> "$CLEAN_LOG"
            rm -rf "$target" 2>/dev/null
        fi
    done
    
    if [ -f "$CLEAN_LOG" ]; then
    DEL_COUNT=$(wc -l < "$CLEAN_LOG" | tr -d ' ')
    
    if [ "$LOG_MODE" = "detailed" ] && [ "$DEL_COUNT" -gt 0 ]; then
        d_time=$(date '+%Y-%m-%d %H:%M:%S')
        awk -v dt="$d_time" '{
            print "["dt"] [ITEM] Deleted Temporary File/Folder: " $0
        }' "$CLEAN_LOG" >> "$LOG_FILE"
    fi
fi
    
    stop_spinner 0 "Cleanup complete ($DEL_COUNT items removed)"
    
    if [ "$DEL_COUNT" -gt 0 ] && [ "$SILENT" = false ]; then
        cat "$CLEAN_LOG" | while IFS= read -r f_path; do
            ui_echo " \e[90m-> Deleted: $f_path\e[0m"
        done
        echo ""
    fi
    rm -f "$CLEAN_LOG" 2>/dev/null
    
    if [ "$ENABLE_NOTIFS" = true ]; then
        notif_msg="TTC: $NOTIF_TTC\nESO-Hub: $NOTIF_EH\nHarvestMap: $NOTIF_HM"
        [ -n "$NOTIF_ADDONS" ] && notif_msg="$notif_msg\nAdd-ons: $NOTIF_ADDONS"
        [ -n "$NOTIF_AOM" ] && notif_msg="$notif_msg\nAPH-OnManager data: $NOTIF_AOM"
        push_sys_notif "$notif_msg"
    fi
    
    if [ "$AUTO_MODE" == "1" ]; then exit 0; fi
    
    if [ "$CURRENT_TIME" -ge "${TARGET_RUN_TIME:-0}" ]; then
        TARGET_RUN_TIME=$((CURRENT_TIME + 3600))
        write_lttc_config
    fi
    target_time=$TARGET_RUN_TIME
    last_eso_check=$(date +%s)
    
    if [ "$IS_STEAM_LAUNCH" = true ]; then
        if [ "$SILENT" = true ]; then
            while [ $(date +%s) -lt $target_time ]; do
                read -t 1 -n 1 -s key 2>/dev/null || true
                current_loop_time=$(date +%s)
                if (( current_loop_time - last_eso_check >= 10 )); then
                    last_eso_check=$current_loop_time
                    if ! is_eso_running; then exit 0; fi
                fi
            done 2>/dev/null
        else
            echo -e " \e[1;97;101m Restarting Sequence in 60 minutes... (Steam Mode) \e[0m\n"
            while [ $(date +%s) -lt $target_time ]; do
                rem_sec=$((target_time - $(date +%s)))
                min=$(( rem_sec / 60 )); sec=$(( rem_sec % 60 ))
                
                printf " \e[1;97;101m Countdown: %02d:%02d \e[0m \e[0;90m(Press 'b' to browse)\e[0m \033[0K\r" \
                       "$min" "$sec"
                
                read -t 1 -n 1 -s key 2>/dev/null || true
                if [[ "$key" == "b" || "$key" == "B" ]]; then
                    browse_database
                    echo -e "\n\e[0;36mResuming countdown...\e[0m"
                fi
                
                current_loop_time=$(date +%s)
                if (( current_loop_time - last_eso_check >= 5 )); then
                    last_eso_check=$current_loop_time
                    if ! is_eso_running; then
                        echo -e "\n\n \e[33mGame closed. Terminating updater...\e[0m"
                        exit 0
                    fi
                fi
            done 2>/dev/null
        fi
    else
        if [ "$SILENT" = true ]; then
            while [ $(date +%s) -lt $target_time ]; do
                sleep 5 & wait $!
            done
        else
            echo -e " \e[1;97;101m Restarting Sequence in 60 minutes... (Standalone Mode) \e[0m\n"
            while [ $(date +%s) -lt $target_time ]; do
                rem_sec=$((target_time - $(date +%s)))
                min=$(( rem_sec / 60 )); sec=$(( rem_sec % 60 ))
                
                printf " \e[1;97;101m Countdown: %02d:%02d \e[0m \e[0;90m(Press 'b' to browse)\e[0m \033[0K\r" \
                       "$min" "$sec"
                
                read -t 1 -n 1 -s key 2>/dev/null || true
                if [[ "$key" == "b" || "$key" == "B" ]]; then
                    browse_database
                    echo -e "\n\e[0;36mResuming countdown...\e[0m"
                fi
            done 2>/dev/null
        fi
    fi
done