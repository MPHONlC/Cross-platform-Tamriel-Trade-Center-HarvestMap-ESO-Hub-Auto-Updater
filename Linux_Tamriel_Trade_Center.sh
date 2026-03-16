#!/bin/bash

# ====================================================================================
# {Linux/Unix} Tamriel Trade Center Auto-Updater v6.0
# Created by @APHONlC | Icon by @THAMER_AKATOSH
# ------------------------------------------------------------------------------------
# A utility for ESO to automate TTC, HarvestMap, and ESO-Hub updates.
# I don't own these addons; this is just a tool to keep all their data updated.
#
# NOTICE: This script is READ-ONLY for your SavedVariables. It won't touch your 
# game data, but keep backups anyway just to be safe.
# ====================================================================================
# LICENSE & USAGE
# Copyright (c) 2021-2026 @APHONlC. All rights reserved.
# - Don't re-upload or mirror this on ESOUI/Nexus/etc without asking me first.
# - Don't release modified versions of this code publicly.
# - You're 100% free to tweak the code for your own private use on your machine.
# ====================================================================================

# Quick folder guide:
# /Backups   -> Snapshots of Steam .vdf files before it mess with launch options.
# /Cache     -> Persistent search data so the DB browser loads instantly.
# /Database  -> LTTC_Database.db (Items Formatting) & LTTC_History.db (Your 30-day history).
# /Logs      -> Simple or Detailed logs (LTTC.log / UTTC.log).
# /Snapshots -> Metadata checks to see if files changed before uploading.
# /Temp      -> Active downloads and extraction staging area.

# Cleanup note:
# Everything in /Temp (zips, extracted folders, .tmp files) gets nuked 
# automatically after every loop to keep things tidy.

unset LD_PRELOAD; unset LD_LIBRARY_PATH; unset STEAM_LD_PRELOAD
APP_VERSION="6.0"; OS_TYPE=$(uname -s); TARGET_DIR="$HOME/Documents"

if [ "$OS_TYPE" = "Darwin" ]; then
    OS_BRAND="Unix"
    TARGET_DIR="$TARGET_DIR/${OS_BRAND}_Tamriel_Trade_Center"
    SYS_ID="mac"
else
    OS_BRAND="Linux"
    TARGET_DIR="$TARGET_DIR/${OS_BRAND}_Tamriel_Trade_Center"
    SYS_ID="linux"
fi

DB_DIR="$TARGET_DIR/Database"; LOG_DIR="$TARGET_DIR/Logs"
SNAP_DIR="$TARGET_DIR/Snapshots"; TEMP_DIR_ROOT="$TARGET_DIR/Temp"
mkdir -p "$DB_DIR" "$LOG_DIR" "$SNAP_DIR" "$TEMP_DIR_ROOT"

[ -f "$TARGET_DIR/LTTC_Database.db" ] && mv "$TARGET_DIR/LTTC_Database.db" "$DB_DIR/" 2>/dev/null
[ -f "$TARGET_DIR/LTTC_History.db" ] && mv "$TARGET_DIR/LTTC_History.db" "$DB_DIR/" 2>/dev/null
[ -f "$TARGET_DIR/LTTC.log" ] && mv "$TARGET_DIR/LTTC.log" "$LOG_DIR/" 2>/dev/null
[ -f "$TARGET_DIR/UTTC.log" ] && mv "$TARGET_DIR/UTTC.log" "$LOG_DIR/" 2>/dev/null
[ -f "$TARGET_DIR/LTTC_LastScan.log" ] && mv "$TARGET_DIR/LTTC_LastScan.log" "$LOG_DIR/" 2>/dev/null
[ -f "$TARGET_DIR/LTTC_Display_State.log" ] && mv "$TARGET_DIR/LTTC_Display_State.log" "$LOG_DIR/" 2>/dev/null

for snap in "$TARGET_DIR"/*_snapshot.lua; do
    [ -f "$snap" ] && mv "$snap" "$SNAP_DIR/" 2>/dev/null
done
rm -f "$TARGET_DIR"/*.tmp "$TARGET_DIR"/*.out 2>/dev/null

CONFIG_FILE="$TARGET_DIR/lttc_updater.conf"; DB_FILE="$DB_DIR/LTTC_Database.db"
LOG_FILE="$LOG_DIR/LTTC.log"; [ "$OS_TYPE" = "Darwin" ] && LOG_FILE="$LOG_DIR/UTTC.log"
LAST_SCAN_FILE="$LOG_DIR/LTTC_LastScan.log"; UI_STATE_FILE="$LOG_DIR/LTTC_Display_State.log"
APP_TITLE="$OS_BRAND Tamriel Trade Center v$APP_VERSION"
SCRIPT_NAME="${OS_BRAND}_Tamriel_Trade_Center.sh"

kill_zombie_updater() {
    trap - EXIT SIGHUP SIGINT SIGTERM
    if [ "$SETUP_COMPLETE" != "true" ] && [ "$HAS_ARGS" = false ]; then
        write_ttc_log "WARN" "User aborted or closed script before completing setup."
    fi
    write_ttc_log "INFO" "Script execution terminated/closed by user or system."
    rm -f /tmp/ttc_updater_*.lock 2>/dev/null
    pkill -P $$ 2>/dev/null
    exit 0
}
trap kill_zombie_updater EXIT SIGHUP SIGINT SIGTERM
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

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
    clean_msg=$(echo "$message" | perl -pe 's/\e\[[0-9;]*m//g')
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $clean_msg" >> "$LOG_FILE"
}

SPINNER_PID=0
SPIN_START=0
SPIN_MSG_FILE="/tmp/lttc_spin.tmp"

start_spinner() {
    local msg="$1"
    echo "$msg" > "$SPIN_MSG_FILE"
    SPIN_START=$(date +%s)
    if [ "$SILENT" = true ]; then return; fi
    tput civis 2>/dev/null
    while :; do
        for s in / - \\ \|; do
            read -r cur_msg < "$SPIN_MSG_FILE" 2>/dev/null
            printf "\r\033[K \e[33m[%c]\e[0m %s" "$s" "${cur_msg:-$msg}"
            sleep 0.1
        done
    done &
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
        if [ "$ok" = "0" ]; then out_str=" \e[92m[✓]\e[0m $msg (${el}s)"
        else out_str=" \e[31m[✗]\e[0m $msg (${el}s)"; fi
        printf "\r\033[K%b\n" "$out_str"
        echo -e "$out_str" >> "$UI_STATE_FILE"
        SPINNER_PID=0
    fi
    write_ttc_log "INFO" "Task '$msg' finished in ${el}s (Status: $ok)."
}

if [ "$OS_TYPE" = "Linux" ] && command -v flock >/dev/null 2>&1; then
    LOCK_FILE="/tmp/ttc_updater_$APP_VERSION.lock"
    exec 200<>"$LOCK_FILE"
    if ! flock -n 200; then
        OLD_PID=$(cat "$LOCK_FILE" 2>/dev/null)
        manage_old_pid "$OLD_PID"
        rm -rf /tmp/ttc_updater_*.lock 2>/dev/null
        exec 200<>"$LOCK_FILE"
        if ! flock -n 200; then
            sleep 1
            flock -n 200 || { echo -e "\e[0;31mFailed to acquire lock. Exiting.\e[0m"; exit 1; }
        fi
    fi
    > "$LOCK_FILE"; echo $$ >&200
    write_ttc_log "INFO" "Acquired instance lock ($LOCK_FILE), PID=$$"
else
    LOCK_DIR="/tmp/ttc_updater_dir_$APP_VERSION"
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        echo $$ > "$LOCK_DIR/pid"
        trap 'rm -rf "$LOCK_DIR"; exit 0' EXIT SIGHUP SIGINT SIGTERM
    else
        OLD_PID=$(cat "$LOCK_DIR/pid" 2>/dev/null)
        manage_old_pid "$OLD_PID"
        rm -rf "$LOCK_DIR"
        mkdir "$LOCK_DIR" 2>/dev/null
        echo $$ > "$LOCK_DIR/pid"
        trap 'rm -rf "$LOCK_DIR"; exit 0' EXIT SIGHUP SIGINT SIGTERM
    fi
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
        sort -t'|' -k1,1 -k7,7 -k6,6 "$DB_FILE.tmp" -o "$DB_FILE.tmp" 2>/dev/null
        if [ -n "$header" ]; then
            echo "$header" > "$DB_FILE"
            cat "$DB_FILE.tmp" >> "$DB_FILE"
        else
            mv "$DB_FILE.tmp" "$DB_FILE"
        fi
        rm -f "$DB_FILE.tmp" 2>/dev/null
    fi
}

find_eso_paths() {
    declare -a game_paths=()
    if [ "$OS_TYPE" = "Linux" ]; then
        game_paths=(
            "$HOME/.local/share/Steam/steamapps/common/Zenimax Online/The Elder Scrolls Online/game/client"
            "$HOME/.steam/steam/steamapps/common/Zenimax Online/The Elder Scrolls Online/game/client"
            "$HOME/.var/app/com.valvesoftware.Steam/.steam/root/steamapps/common/Zenimax Online/The Elder Scrolls Online/game/client"
            "/var/lib/flatpak/app/com.valvesoftware.Steam/.steam/root/steamapps/common/Zenimax Online/The Elder Scrolls Online/game/client"
        )
    elif [ "$OS_TYPE" = "Darwin" ]; then
        game_paths=(
            "$HOME/Library/Application Support/Steam/steamapps/common/Zenimax Online/The Elder Scrolls Online/game/client"
            "$HOME/Library/Application Support/Steam/steamapps/common/Zenimax Online/The Elder Scrolls Online"
        )
    fi
    for p in "${game_paths[@]}"; do
        if [ -f "$p/eso64.exe" ] || [ -f "$p/eso.app/Contents/MacOS/eso" ] || [ -d "$p/eso.app" ]; then
            echo "$p"; return 0
        fi
    done
    if [ "$OS_TYPE" = "Linux" ]; then
        FOUND_ZOS=$(find "$HOME" /run/media /mnt /media -maxdepth 6 -type d -name "Zenimax Online" 2>/dev/null | head -n 1)
        if [ -n "$FOUND_ZOS" ] && [ -f "$FOUND_ZOS/The Elder Scrolls Online/game/client/eso64.exe" ]; then
            echo "$FOUND_ZOS/The Elder Scrolls Online/game/client"; return 0
        fi
    fi
    echo ""
}

is_eso_running() {
    if pgrep -i -f 'eso64\.exe|steam_app_306130|eso\.app|Bethesda\.net_Launcher' > /dev/null 2>&1; then
        return 0
    fi
    return 1
}

SILENT=false; AUTO_PATH=false; AUTO_SRV=""; AUTO_MODE=""; ADDON_DIR=""
SETUP_COMPLETE=false; ENABLE_NOTIFS=false; HAS_ARGS=false; IS_TASK=false
IS_STEAM_LAUNCH=false; ENABLE_DISPLAY="true"; ENABLE_LOCAL_MODE=false

if [ -f "$CONFIG_FILE" ]; then source "$CONFIG_FILE"; fi

TTC_LAST_SALE="${TTC_LAST_SALE:-0}"
TTC_LAST_DOWNLOAD="${TTC_LAST_DOWNLOAD:-0}"
TTC_LAST_CHECK="${TTC_LAST_CHECK:-0}"
TTC_NA_VERSION="${TTC_NA_VERSION:-0}"
TTC_EU_VERSION="${TTC_EU_VERSION:-0}"
EH_LAST_SALE="${EH_LAST_SALE:-0}"
EH_LAST_DOWNLOAD="${EH_LAST_DOWNLOAD:-0}"
EH_LAST_CHECK="${EH_LAST_CHECK:-0}"
EH_LOC_5="${EH_LOC_5:-0}"; EH_LOC_7="${EH_LOC_7:-0}"; EH_LOC_9="${EH_LOC_9:-0}"
HM_LAST_DOWNLOAD="${HM_LAST_DOWNLOAD:-0}"
HM_LAST_CHECK="${HM_LAST_CHECK:-0}"
LOG_MODE="${LOG_MODE:-simple}"
EH_USER_TOKEN="${EH_USER_TOKEN:-}"
TARGET_RUN_TIME="${TARGET_RUN_TIME:-0}"
SKIP_DL_TTC="${SKIP_DL_TTC:-false}"
SKIP_DL_HM="${SKIP_DL_HM:-false}"
SKIP_DL_EH="${SKIP_DL_EH:-false}"

write_lttc_config() {
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
TTC_NA_VERSION="$TTC_NA_VERSION"
TTC_EU_VERSION="$TTC_EU_VERSION"
EH_LAST_SALE="$EH_LAST_SALE"
EH_LAST_DOWNLOAD="$EH_LAST_DOWNLOAD"
EH_LAST_CHECK="$EH_LAST_CHECK"
EH_LOC_5="$EH_LOC_5"
EH_LOC_7="$EH_LOC_7"
EH_LOC_9="$EH_LOC_9"
HM_LAST_DOWNLOAD="$HM_LAST_DOWNLOAD"
HM_LAST_CHECK="$HM_LAST_CHECK"
EH_USER_TOKEN="$EH_USER_TOKEN"
TARGET_RUN_TIME="$TARGET_RUN_TIME"
SKIP_DL_TTC=$SKIP_DL_TTC
SKIP_DL_HM=$SKIP_DL_HM
SKIP_DL_EH=$SKIP_DL_EH
EOF
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
            
            local api_resp=$(curl -s "https://api.mmoui.com/v3/game/ESO/filedetails/${a_id}.json")
            local dl_url=$(echo "$api_resp" | grep -o '"downloadUrl":"[^"]*"' | cut -d'"' -f4 | sed 's/\\//g' | tr -d '\r\n\t ')
            local addon_version=$(echo "$api_resp" | grep -o '"version":"[^"]*"' | cut -d'"' -f4 | tr -d '\r\n\t ')
            
            [ -z "$dl_url" ] && dl_url="https://cdn.esoui.com/downloads/file${a_id}/"
            
            if curl -s -f -m 30 -L -A "Mozilla/5.0" -o "$TEMP_DIR_ROOT/${a_name}.zip" "$dl_url" </dev/null; then
                unzip -q -o "$TEMP_DIR_ROOT/${a_name}.zip" -d "$ADDON_DIR/" > /dev/null 2>&1
                rm -f "$TEMP_DIR_ROOT/${a_name}.zip"
                
                if [ "$a_name" = "TamrielTradeCentre" ]; then
                    rm -f "$TEMP_DIR_ROOT/ttc_last_dl.txt" 2>/dev/null
                    if [ -n "$addon_version" ]; then
                        TTC_NA_VERSION="$addon_version"
                        TTC_EU_VERSION="$addon_version"
                        CONFIG_CHANGED=true
                    fi
                fi
                
                if [ "$a_name" = "LibEsoHubPrices" ]; then
                    local eh_api=$(curl -s -X POST -H "User-Agent: ESOHubClient/1.0.9" \
                        -d "user_token=&client_system=$SYS_ID&client_version=1.0.9&lang=en" \
                        "https://data.eso-hub.com/v1/api/get-addon-versions" 2>/dev/null)
                    local srv_ver=$(echo "$eh_api" | sed 's/{"folder_name"/\n{"folder_name"/g' \
                        | grep '"folder_name":"LibEsoHubPrices"' \
                        | grep -oE '"version":\{[^}]*\}' \
                        | grep -oE '"string":"[^"]+"' | cut -d'"' -f4 | tr -d '\r\n\t ')
                    if [ -n "$srv_ver" ]; then
                        EH_LOC_7="$srv_ver"
                        CONFIG_CHANGED=true
                    fi
                fi
                
                stop_spinner 0 "$a_name installed"
                
                local settings_file="$ADDON_DIR/../AddOnSettings.txt"
                if [ -f "$settings_file" ]; then
                    if [ "$a_name" = "EsoTradingHub" ]; then
                        sed -i -e "s/^EsoTradingHub 0/EsoTradingHub 1/g" \
                               -e "s/^EsoHubScanner 0/EsoHubScanner 1/g" \
                               -e "s/^LibEsoHubPrices 0/LibEsoHubPrices 1/g" \
                               "$settings_file" 2>/dev/null
                        grep -q "^EsoTradingHub " "$settings_file" || echo "EsoTradingHub 1" >> "$settings_file"
                        grep -q "^EsoHubScanner " "$settings_file" || echo "EsoHubScanner 1" >> "$settings_file"
                        grep -q "^LibEsoHubPrices " "$settings_file" || echo "LibEsoHubPrices 1" >> "$settings_file"
                    elif [ "$a_name" = "HarvestMap" ] || [ "$a_name" = "HarvestMapData" ]; then
                        sed -i -e "s/^HarvestMap 0/HarvestMap 1/g" \
                               -e "s/^HarvestMapData 0/HarvestMapData 1/g" \
                               "$settings_file" 2>/dev/null
                        grep -q "^HarvestMap " "$settings_file" || echo "HarvestMap 1" >> "$settings_file"
                        grep -q "^HarvestMapData " "$settings_file" || echo "HarvestMapData 1" >> "$settings_file"
                    else
                        sed -i -e "s/^$a_name 0/$a_name 1/g" "$settings_file" 2>/dev/null
                        grep -q "^$a_name " "$settings_file" || echo "$a_name 1" >> "$settings_file"
                    fi
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

IS_DESKTOP=false
if [ "$#" -gt 0 ]; then HAS_ARGS=true; fi
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --silent) SILENT=true ;;
        --auto) AUTO_PATH=true ;;
        --na) AUTO_SRV="1" ;;
        --eu) AUTO_SRV="2" ;;
        --both) AUTO_SRV="3" ;;
        --loop) AUTO_MODE="2" ;;
        --once) AUTO_MODE="1" ;;
        --task) IS_TASK=true; SILENT=true ;;
        --steam) IS_STEAM_LAUNCH=true ;;
        --addon-dir) shift; ADDON_DIR="$1" ;;
        --setup) rm -f "$CONFIG_FILE"; SETUP_COMPLETE=false ;;
        --desktop) IS_DESKTOP=true ;;
    esac
    shift
done

if [ "$IS_STEAM_LAUNCH" = false ] && [ "$IS_TASK" = false ]; then SILENT=false; fi
if [ "$IS_STEAM_LAUNCH" = true ] && [ "$SILENT" = true ]; then ENABLE_NOTIFS=true; fi

push_sys_notif() {
    local msg="$1"
    if [ "$ENABLE_NOTIFS" = "false" ]; then return; fi
    if [ "$OS_TYPE" = "Darwin" ]; then
        osascript -e "display notification \"$msg\" with title \"$APP_TITLE\"" 2>/dev/null
    else
        if command -v notify-send > /dev/null; then
            notify-send -i "dialog-information" -t 5000 \
                --hint=string:category:system "$APP_TITLE" "$msg" 2>/dev/null
        fi
    fi
}

get_active_terminal() {
    local term
    if [ "$OS_TYPE" = "Darwin" ]; then term="Terminal"
    elif command -v alacritty &> /dev/null; then term="alacritty -e"
    elif command -v konsole &> /dev/null; then term="konsole -e"
    elif command -v gnome-terminal &> /dev/null; then term="gnome-terminal --"
    elif command -v xfce4-terminal &> /dev/null; then term="xfce4-terminal -e"
    elif command -v kitty &> /dev/null; then term="kitty --"
    else term="xterm -e"; fi
    echo "$term"
}

find_addon_folder() {
    declare -a addon_paths=()
    if [ "$OS_TYPE" = "Linux" ]; then
        addon_paths=(
            "$HOME/.local/share/Steam/steamapps/compatdata/306130/pfx/drive_c/users/steamuser/Documents/Elder Scrolls Online/live/AddOns"
            "$HOME/.steam/steam/steamapps/compatdata/306130/pfx/drive_c/users/steamuser/Documents/Elder Scrolls Online/live/AddOns"
            "$HOME/.var/app/com.valvesoftware.Steam/.steam/root/steamapps/compatdata/306130/pfx/drive_c/users/steamuser/Documents/Elder Scrolls Online/live/AddOns"
            "/var/lib/flatpak/app/com.valvesoftware.Steam/.steam/root/steamapps/compatdata/306130/pfx/drive_c/users/steamuser/Documents/Elder Scrolls Online/live/AddOns"
            "$HOME/Games/elder-scrolls-online/drive_c/users/$USER/Documents/Elder Scrolls Online/live/AddOns"
            "$HOME/Games/elder-scrolls-online/drive_c/users/steamuser/Documents/Elder Scrolls Online/live/AddOns"
            "$HOME/Documents/Elder Scrolls Online/live/AddOns"
            "/home/user/Documents/Elder Scrolls Online/live/AddOns"
            "$HOME/.wine/drive_c/users/$USER/Documents/Elder Scrolls Online/live/AddOns"
            "$HOME/.wine/drive_c/users/steamuser/Documents/Elder Scrolls Online/live/AddOns"
            "$HOME/.var/app/com.usebottles.bottles/data/bottles/bottles/Elder-Scrolls-Online/drive_c/users/$USER/Documents/Elder Scrolls Online/live/AddOns"
            "$HOME/PortWINE/PortProton/drive_c/users/steamuser/Documents/Elder Scrolls Online/live/AddOns"
            "$HOME/PortProton/prefixes/DEFAULT/drive_c/users/steamuser/Documents/Elder Scrolls Online/live/AddOns/"
        )
    elif [ "$OS_TYPE" = "Darwin" ]; then
        addon_paths=("$HOME/Documents/Elder Scrolls Online/live/AddOns")
    fi

    for p in "${addon_paths[@]}"; do
        if [ -d "$p" ]; then echo "$p"; return 0; fi
    done

    if [ "$OS_TYPE" = "Linux" ]; then
        while IFS= read -r base_dir; do
            [ -z "$base_dir" ] && continue
            for suffix in "/pfx/drive_c/users/steamuser/Documents/Elder Scrolls Online/live/AddOns" \
                          "/drive_c/users/$USER/Documents/Elder Scrolls Online/live/AddOns" \
                          "/live/AddOns"; do
                if [ -d "$base_dir$suffix" ]; then echo "$base_dir$suffix"; return 0; fi
            done
        done <<< "$(find "$HOME" /run/media /mnt /media -maxdepth 6 \
            \( -type d -name "306130" -o -type d -name "Elder Scrolls Online" \
            -o -type d -name "bottles" -o -type d -name "lutris" \) 2>/dev/null)"
    fi
    echo ""
}

wizard_first_run() {
    clear
    echo -e "\n\e[0;33m--- Initial Setup & Configuration ---\e[0m"
    
    if [ "$CURRENT_DIR" != "$TARGET_DIR" ]; then
        cp "${BASH_SOURCE[0]}" "$TARGET_DIR/$SCRIPT_NAME" 2>/dev/null
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
    echo -e "1) Log in with Username and Password \e[0;32m(Fetches API Token securely)\e[0m"
    echo -e "2) Manually enter API Token \e[38;5;212m(If you already know your token)\e[0m"
    echo -e "3) Skip / \e[0;90mUpload Anonymously No Login\e[0m \e[0;32m(Default)\e[0m"
    read -p $'\e[0;34mChoice [1-3]: \e[0m' eh_choice
    
    EH_USER_TOKEN=""
    if [ "$eh_choice" == "1" ]; then
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
        LOGIN_RESP=$(curl -s -X POST -H "User-Agent: ESOHubClient/1.0.9" \
            --data-urlencode "client_system=$SYS_ID" \
            --data-urlencode "client_version=1.0.9" \
            --data-urlencode "client_version_int=1009" \
            --data-urlencode "lang=en" \
            --data-urlencode "username=${EH_USER}" \
            --data-urlencode "password=${EH_PASS}" \
            "https://data.eso-hub.com/v1/api/login")
            
        EH_USER_TOKEN=$(echo "$LOGIN_RESP" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
        EH_USER=""; EH_PASS=""
        
        if [ -n "$EH_USER_TOKEN" ]; then
            echo -e "\e[0;32m[+] Successfully logged in! Token saved securely.\e[0m"
        else
            echo -e "\e[0;31m[-] Login failed. Falling back to anonymous mode.\e[0m"
            EH_USER_TOKEN=""
        fi
    elif [ "$eh_choice" == "2" ]; then
        read -p "Token: " EH_USER_TOKEN
    fi

    SETUP_COMPLETE=true; write_lttc_config

    echo -e "\n\e[0;33m9. Desktop Shortcut\e[0m"
    if [[ "$OS_TYPE" == "Linux" ]]; then
        DESKTOP_DIR=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")
        APP_DIR="$HOME/.local/share/applications"
        echo -e "Creates a shortcut at \e[0;35m$DESKTOP_DIR\e[0m & \e[0;35m$APP_DIR\e[0m"
    fi
    read -p "Create a desktop shortcut? (Y/n): " make_shortcut
    [ -z "$make_shortcut" ] && make_shortcut="y"
    
    SHORTCUT_SRV_FLAG="--na"
    [ "$AUTO_SRV" == "2" ] && SHORTCUT_SRV_FLAG="--eu"
    [ "$AUTO_SRV" == "3" ] && SHORTCUT_SRV_FLAG="--both"
    LOOP_FLAG="--once"
    [ "$AUTO_MODE" == "2" ] && LOOP_FLAG="--loop"

    if [[ "$make_shortcut" =~ ^[Yy]$ ]]; then
        ICON_PATH="$TARGET_DIR/lttc_icon.png"
        curl -s -L -o "$ICON_PATH" "https://raw.githubusercontent.com/MPHONlC/Cross-platform-Tamriel-Trade-Center-HarvestMap-ESO-Hub-Auto-Updater/refs/heads/main/icon.ico"
        
        if [[ "$OS_TYPE" == "Linux" ]]; then
            DESKTOP_DIR=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")
            APP_DIR="$HOME/.local/share/applications"
            
            rm -f "$HOME/Desktop/"*Tamriel_Trade_Center*.desktop \
                  "$HOME/.local/share/applications/"*Tamriel_Trade_Center*.desktop \
                  "$DESKTOP_DIR/"*Tamriel_Trade_Center*.desktop \
                  "$APP_DIR/"*Tamriel_Trade_Center*.desktop 2>/dev/null
                  
            update-desktop-database "$APP_DIR" 2>/dev/null || true
            sleep 1
            
            mkdir -p "$DESKTOP_DIR"
            DESKTOP_FILE="$DESKTOP_DIR/${OS_BRAND}_Tamriel_Trade_Center.desktop"
            
            cat <<EOF > "$DESKTOP_FILE"
[Desktop Entry]
Version=1.0
Name=$APP_TITLE
Comment=Cross-Platform Auto-Updater for TTC, HarvestMap & ESO-Hub - Created by @APHONIC
Exec="$TARGET_DIR/$SCRIPT_NAME" $SHORTCUT_SRV_FLAG $LOOP_FLAG --desktop
Icon=$ICON_PATH
Terminal=true
Type=Application
Categories=Game;Utility;
EOF
            chmod +x "$DESKTOP_FILE"
            mkdir -p "$APP_DIR"
            cp "$DESKTOP_FILE" "$APP_DIR/"
            update-desktop-database "$APP_DIR" 2>/dev/null || true
            
            echo -e "\e[0;32m[+] Linux desktop shortcut installed.\e[0m"
        elif [[ "$OS_TYPE" == "Darwin" ]]; then
            echo -e "\e[0;33m[!] Automatic macOS App creation is not supported in Bash.\e[0m"
        fi
    else
        if [[ "$OS_TYPE" == "Linux" ]]; then
            DESKTOP_DIR=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")
            APP_DIR="$HOME/.local/share/applications"
            
            rm -f "$HOME/Desktop/"*Tamriel_Trade_Center*.desktop \
                  "$HOME/.local/share/applications/"*Tamriel_Trade_Center*.desktop \
                  "$DESKTOP_DIR/"*Tamriel_Trade_Center*.desktop \
                  "$APP_DIR/"*Tamriel_Trade_Center*.desktop 2>/dev/null
            update-desktop-database "$APP_DIR" 2>/dev/null || true
        fi
    fi

    TERM_CMD=$(get_active_terminal)
    echo -e "\n\e[0;92m================ SETUP COMPLETE ================\e[0m"
    echo -e "Copy this string into your \e[1mSteam Launch Options\e[0m:\n"
    
    IS_GAMESCOPE=false
    if grep -qi "steamos" /etc/os-release 2>/dev/null; then IS_GAMESCOPE=true; fi
    
    DETACHED_CMD="env -u LD_PRELOAD nohup bash -c '$TARGET_DIR/$SCRIPT_NAME $SHORTCUT_SRV_FLAG $LOOP_FLAG --silent --steam' >/dev/null 2>&1 & %command%"

    if [ "$IS_GAMESCOPE" = true ]; then
        echo -e "\e[0;104m $DETACHED_CMD \e[0m\n"
        echo -e "\e[0;33m(Note: For Gaming Mode compatibility, Launch Options are forced to invisible background mode.)\e[0m\n"
    elif [ "$SILENT" = true ]; then
        echo -e "\e[0;104m $DETACHED_CMD \e[0m\n"
    else
        if [ "$OS_TYPE" = "Darwin" ]; then
            LAUNCH_CMD="osascript -e 'tell application \"Terminal\" to do script \"\\\"$TARGET_DIR/$SCRIPT_NAME\\\" $SHORTCUT_SRV_FLAG $LOOP_FLAG --steam\"' & %command%"
            echo -e "\e[0;104m $LAUNCH_CMD \e[0m\n"
        else
            LAUNCH_CMD="env -u LD_PRELOAD -u STEAM_LD_PRELOAD $TERM_CMD '$TARGET_DIR/$SCRIPT_NAME' $SHORTCUT_SRV_FLAG $LOOP_FLAG --steam & %command%"
            echo -e "\e[0;104m $LAUNCH_CMD \e[0m\n"
            echo -e "\e[0;33m(Note: Auto-detected your terminal as '$TERM_CMD').\e[0m\n"
        fi
    fi
    
    echo -e "\e[0;33m10. Steam Launch Options\e[0m"
    echo -e "\e[0;32mAutomatically inject the Launch Command into Steam?\e[0m"
    echo -e "\e[31m(WARNING: Steam MUST be closed to do this.)\e[0m"
    read -p "Apply automatically? (Y/n): " auto_steam
    [ -z "$auto_steam" ] && auto_steam="y"
    
    if [[ "$auto_steam" =~ ^[Yy]$ ]]; then
        STEAM_CMD="steam"
        if ! command -v steam >/dev/null 2>&1 && command -v flatpak >/dev/null 2>&1 && flatpak list | grep -qi com.valvesoftware.Steam; then
            STEAM_CMD="flatpak run com.valvesoftware.Steam"
        fi
        
        STEAM_PIDS=$(pgrep -x "steam|Steam|steam_osx" || pgrep -f "com.valvesoftware.Steam")
        if [ -n "$STEAM_PIDS" ]; then
            ui_echo "\e[0;33m[!] Steam is running. Closing Steam to inject options...\e[0m"
            if pgrep -f "flatpak run com.valvesoftware.Steam" > /dev/null 2>&1; then
                STEAM_CMD="flatpak run com.valvesoftware.Steam"
            fi
            pkill -x "steam|Steam|steam_osx" > /dev/null 2>&1
            pkill -f "com.valvesoftware.Steam" > /dev/null 2>&1
            read -t 5 -s 2>/dev/null || true
        fi
        
        [ "$IS_GAMESCOPE" = true ] && export LAUNCH_STR="$DETACHED_CMD" || export LAUNCH_STR="$LAUNCH_CMD"
        [ "$SILENT" = true ] && export LAUNCH_STR="$DETACHED_CMD"

        BACKUP_DIR="$TARGET_DIR/Backups"; mkdir -p "$BACKUP_DIR"
        
        for conf in "$HOME/.steam/steam/userdata"/*/config/localconfig.vdf \
                    "$HOME/.local/share/Steam/userdata"/*/config/localconfig.vdf \
                    "/var/lib/flatpak/app/com.valvesoftware.Steam/.steam/root/userdata"/*/config/localconfig.vdf \
                    "$HOME/Library/Application Support/Steam/userdata"/*/config/localconfig.vdf; do
            if [ -f "$conf" ]; then
                TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
                STEAM_ID=$(basename $(dirname $(dirname "$conf")))
                BACKUP_FILE="$BACKUP_DIR/localconfig_${STEAM_ID}_${TIMESTAMP}.vdf"
                cp "$conf" "$BACKUP_FILE" 2>/dev/null
                ui_echo "\e[0;36m-> Backed up Steam config to: $BACKUP_FILE\e[0m"
                ui_echo "\e[0;36m-> Injecting Launch Options into ESO config (AppID: 306130)...\e[0m"
                
                if perl -pi.bak -e '
                    BEGIN{undef $/;} 
                    my $ls=$ENV{LAUNCH_STR}; $ls=~s/"/\\"/g; 
                    if (/"306130"\s*\{/) { 
                        if (s/("306130"\s*\{[^}]*"LaunchOptions"\s*)"((?:\\"|[^"])*)"/ 
                            my $pre=$1; my $cur=$2; 
                            $cur =~ s{\s*(?:nohup\s+)?env -u LD_PRELOAD.*?%command%}{ %command%}g; 
                            $cur =~ s{\s*(?:nohup\s+)?env -u LD_PRELOAD.*?(?:Tamriel_Trade_Center|--steam).*?$}{}g; 
                            $cur =~ s{\s*env -u LD_PRELOAD.*?alacritty -e\s*$}{}g; 
                            if ($cur =~ m{%command%}) { $cur =~ s{%command%}{$ls}g; } 
                            else { $cur =~ s{^\s+|\s+$}{}g; $cur = $cur eq "" ? $ls : "$cur $ls"; } 
                            "$pre\"$cur\"" 
                        /se) {} 
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
        
        if [ "$OS_TYPE" = "Darwin" ]; then
            open -a Steam "steam://open/main"
        elif [[ "$STEAM_CMD" == *"flatpak"* ]]; then
            nohup flatpak run com.valvesoftware.Steam "steam://open/main" </dev/null >/dev/null 2>&1 &
        else
            nohup steam "steam://open/main" </dev/null >/dev/null 2>&1 &
        fi
        
        ui_echo "\e[0;36m-> Verifying Steam launch...\e[0m"
        steam_started=false
        for i in {1..10}; do
            if pgrep -x "steam|Steam|steam_osx" > /dev/null 2>&1 || pgrep -f "com.valvesoftware.Steam" > /dev/null 2>&1; then
                steam_started=true; break
            fi
            sleep 1
        done
        
        if [ "$steam_started" = true ]; then
            ui_echo "\e[0;32m[+] Steam launched successfully.\e[0m"
        else
            ui_echo "\e[0;31m[-] Steam launch timed out. Attempting fallback...\e[0m"
            
            if [ "$OS_TYPE" = "Darwin" ]; then
                open "steam://open/main"
            elif command -v xdg-open >/dev/null 2>&1; then
                xdg-open "steam://open/main" >/dev/null 2>&1
            elif command -v setsid >/dev/null 2>&1; then
                setsid $STEAM_CMD "steam://open/main" </dev/null >/dev/null 2>&1 &
            else
                (nohup $STEAM_CMD "steam://open/main" </dev/null >/dev/null 2>&1 &)
            fi
            
            sleep 3
            if pgrep -x "steam|Steam|steam_osx" > /dev/null 2>&1 || pgrep -f "com.valvesoftware.Steam" > /dev/null 2>&1; then
                ui_echo "\e[0;32m[+] Steam launched successfully via fallback.\e[0m"
            else
                ui_echo "\e[0;31m[-] Could not verify Steam is running.\e[0m"
            fi
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
    local os_log_id="(Linux)"
    
    local is_deck=false
    if [ "$OS_TYPE" = "Linux" ]; then
        if [ "$XDG_CURRENT_DESKTOP" = "gamescope" ] || pgrep -x "gamescope" > /dev/null || grep -qi "steamos" /etc/os-release 2>/dev/null; then
            is_deck=true
            os_log_id="(Steamdeck)"
        fi
    elif [ "$OS_TYPE" = "Darwin" ]; then
        os_log_id="(macOS)"
    fi

    if [ ! -d "$ADDON_DIR/$addon" ]; then 
        write_ttc_log "INFO" "is_addon_active: $addon not present in addon folder $os_log_id"
        echo "false"
        return
    fi
    
    if [ "$is_deck" = true ]; then
        if [ -d "$ADDON_DIR/$addon" ]; then 
            write_ttc_log "INFO" "is_addon_active: $addon present $os_log_id"
            echo "true"
        else 
            write_ttc_log "INFO" "is_addon_active: $addon missing $os_log_id"
            echo "false"
        fi
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
    if [ "$OS_TYPE" = "Darwin" ]; then
        date -r "$ts" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "Unknown Date"
    else
        date -d "@$ts" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "Unknown Date"
    fi
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
        for (t in k_dict) {
            if (t !~ /^[0-9]+$/) {
                split(k_dict[t], tparts, "|")
                t_loc = tparts[1]; t_map = tparts[2]
                if (index(t_loc, loc_name " - ") == 1 || index(t_loc, loc_name " Wayshrine") == 1 || t_loc == loc_name) {
                    k_dict[t] = t_loc "|" t_map "|" coord_str
                    k_dict[k] = t_loc "|" t_map "|" coord_str
                }
            }
        }
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
    if(ln~/master .* writ|indoril inks:/) return 5
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
        
        awk -F'|' -OFS='|' -v lookup="$offline_dict" '
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
                echo -e " \e[92m[✓]\e[0m Offline Database repair complete!"
            fi
            write_ttc_log "INFO" "Auto-Repair done."
        fi
    fi
    rm -f "$missing_ids" "$offline_dict" 2>/dev/null
}
repair_missing_names

browse_database() {
    write_ttc_log "INFO" "browse_database: entering DB browser"
    clear
    echo -e "\n\033[92m===========================================================================\033[0m"
    echo -e "\033[1m\033[94m                         TTC & ESO-Hub Database Browser\033[0m"
    echo -e "\033[97m                 (Data automatically retained for the last 30 days)\033[0m"
    echo -e "\033[92m===========================================================================\033[0m\n"
    
    if [ ! -f "$DB_DIR/LTTC_History.db" ]; then
        echo -e "\033[31m[!] No history database found. Wait for extraction first.\033[0m\n"
        echo -e "\033[31m[!] (or go visit a guild store in-game and press scan then /reloadui)\033[0m\n"
        echo -ne "\033[33mPress Enter to return...\033[0m "; read dummy_var; return
    fi
    
    if [ -f "$CONFIG_FILE" ]; then source "$CONFIG_FILE"; fi
    
    CACHE_DIR="$TARGET_DIR/Cache"
    mkdir -p "$CACHE_DIR"
    
    while true; do
        echo -e "\n\033[33mSelect a Database Function:\033[0m"
        echo -e " 1) Top 10 Most Selling Items (By Volume)"
        echo -e " 2) Top 10 Highest Grossing Items (By Total Gold)"
        echo -e " 3) Suggested Price Calculator (Outlier Elimination)"
        echo -e " 4) Settings: Edit My Target Username \033[90m(Current: ${TARGET_USERNAME:-None})\033[0m"
        echo -e " 5) Exit Browser & Resume Updater"
        echo -ne "\033[33mChoice [1-5]:\033[0m "; read b_opt
        
        case $b_opt in
            1)
                write_ttc_log "INFO" "DB Browser: Generating Top 10 Selling Items list."
                echo -ne "\033[33mSearch by Source [TTC or ESO-Hub] (leave empty for ALL):\033[0m "
                read source_filter
                echo -ne "\033[33mFilter to your @Username only? (y/N):\033[0m "; read personal_opt
                
                echo -e "\n\033[33mTime Filter:\033[0m"
                echo -e " 1) Past 1 Week\n 2) Past 2 Weeks\n 3) Past 3 Weeks\n 4) All Data"
                echo -ne "\033[33mChoice [1-4] (default 4):\033[0m "; read time_opt
                
                cutoff_time=0; now_ts=$(date +%s)
                case "$time_opt" in
                    1) cutoff_time=$((now_ts - 604800)) ;;
                    2) cutoff_time=$((now_ts - 1209600)) ;;
                    3) cutoff_time=$((now_ts - 1814400)) ;;
                esac
                
                t_user=""
                if [[ "${personal_opt,,}" == "y" ]]; then
                    if [ -z "$TARGET_USERNAME" ]; then echo -e "\033[31m[!] @Username not set!\033[0m"
                    else t_user="$TARGET_USERNAME"; fi
                fi
                
                if [ -n "$t_user" ]; then echo -e "\n\033[36m--- Top 10 Selling [$t_user] ---\033[0m"
                else echo -e "\n\033[36m--- Top 10 Selling Items (By Volume) [Global] ---\033[0m"; fi
                
                search_hash=$(echo "O1v3|$source_filter|$personal_opt|$time_opt" \
                              | md5sum | awk '{print $1}')
                cache_file="$CACHE_DIR/cache_${search_hash}.txt"
                
                if [ -f "$cache_file" ] && [ "$cache_file" -nt "$DB_DIR/LTTC_History.db" ]; then
                    echo -e " \033[32m[+] Loading instantly from persistent cache...\033[0m\n"
                    cat "$cache_file"
                else
                    echo ""
                    start_spinner "Calculating Top 10 by Volume (Building Cache)..."
                    awk -F'|' -v cutoff="$cutoff_time" \
                        -v src_filter="$(echo "$source_filter" | awk '{print tolower($0)}')" \
                        -v t_user="$(echo "$t_user" | awk '{print tolower($0)}')" '
                        $1=="HISTORY" && ($3=="Sold" || $3=="Purchased" || $3=="Listed") && $5 > 0 {
                            if (cutoff > 0 && $2 < cutoff) next;
                            if (src_filter != "" && index(tolower($13), src_filter) == 0) next;
                            if (t_user != "") {
                                if (index(tolower($8), t_user) == 0 && index(tolower($9), t_user) == 0) next;
                            }
                            if (index($7, "Unknown Item (") == 1) next;
                            
                            qty = ($5 > 0) ? $5 : 1; unit_p = $4 / qty; name = $7
                            scans = ($14 != "" && $14 > 0) ? $14 + 0 : 1
                            colors[name] = ($12 != "") ? $12 : "\033[0m"
                            item_ids[name] = $6
                            
                            for (s=0; s<scans; s++) {
                                prices[name, count[name]++] = unit_p
                                if ($3=="Sold" || $3=="Purchased") vol[name] += qty
                            }
                        }
                        END {
                            for (name in vol) {
                                n = count[name]
                                if (n < 5) { sugg = 0 } else {
                                    for (i=0; i<n; i++) {
                                        for (j=i+1; j<n; j++) {
                                            if (prices[name, i] > prices[name, j]) {
                                                temp = prices[name, i]
                                                prices[name, i] = prices[name, j]
                                                prices[name, j] = temp
                                            }
                                        }
                                    }
                                    trim = int(n * 0.10); if (trim == 0) trim = 1
                                    valid_n = n - (2 * trim); if (valid_n < 1) valid_n = 1
                                    
                                    mid_start = trim + int(valid_n * 0.45)
                                    mid_end = trim + int(valid_n * 0.55)
                                    if (mid_end < mid_start) mid_end = mid_start
                                    
                                    sum = 0; c = 0
                                    for (i=mid_start; i<=mid_end; i++) {
                                        sum += prices[name, i]; c++
                                    }
                                    sugg = sum / c
                                }
                                print vol[name] "|" name "|" sugg "|" colors[name] "|" item_ids[name]
                            }
                        }' "$DB_DIR/LTTC_History.db" | sort -t'|' -k1,1nr | head -n 10 | awk -F'|' '{
                            p_str = ($3 == 0) ? "Not enough data" : sprintf("%.2f", $3 + 0) "g"
                            vol_fmt = sprintf("%.0f", $1 + 0)
                            
                            name_enc = $2; gsub(/ /, "+", name_enc); gsub(/'\''/, "%27", name_enc)
                            
                            ttc_l = "\033[90m[\033]8;;https://us.tamrieltradecentre.com/pc/Trade/" \
                                    "SearchResult?SearchType=Sell&ItemNamePattern=" name_enc \
                                    "\033\\TTC\033]8;;\033\\]\033[0m"
                            eso_l = "\033[90m[\033]8;;https://eso-hub.com/en/trading/" $5 \
                                    "\033\\ESO-Hub\033]8;;\033\\]\033[0m"
                            
                            uesp_l = ""
                            if ($2 ~ /^(Blueprint|Praxis|Design|Pattern|Formula|Diagram|Sketch): /) {
                                u_name = $2; sub(/^[^:]+: /, "", u_name)
                                gsub(/ /, "_", u_name); gsub(/'\''/, "%27", u_name)
                                uesp_l = " \033[90m[\033]8;;https://en.uesp.net/wiki/File:ON-" \
                                         "furnishing-" u_name ".jpg\033\\UESP\033]8;;\033\\]\033[0m"
                            } else if ($2 ~ /Crafting Motif/ || $2 ~ /Style Page:/) {
                                u_name = $2
                                sub(/^.*Crafting Motif [^:]+: /, "", u_name)
                                sub(/^.*Style Page: /, "", u_name)
                                sub(/ (Axes|Belts|Boots|Bows|Chests|Daggers|Gloves|Helmets)$/, "", u_name)
                                sub(/ (Legs|Maces|Shields|Shoulders|Staves|Swords|Cuirass)$/, "", u_name)
                                sub(/ (Greaves|Helm|Pauldrons|Sabatons|Gauntlets|Bracers)$/, "", u_name)
                                sub(/ (Epaulets|Jack|Guards|Belt|Shoes|Jerkin|Breeches|Hat)$/, "", u_name)
                                sub(/ (Robes|Sash|Girdle|Corselet|Arm Cops)$/, "", u_name)
                                sub(/ Style$/, "", u_name)
                                gsub(/ /, "_", u_name); gsub(/'\''/, "%27", u_name)
                                uesp_l = " \033[90m[\033]8;;https://en.uesp.net/wiki/Online:" \
                                         u_name "_Style\033\\UESP\033]8;;\033\\]\033[0m"
                            }
                            
                            print " \033[36m" vol_fmt "x\033[0m sold - " $4 $2 "\033[0m " \
                                  "(Avg: \033[33m" p_str "\033[0m) " ttc_l " " eso_l uesp_l
                        }' > "$cache_file"
                    stop_spinner 0 "Calculation complete"
                    echo ""
                    cat "$cache_file"
                fi
                echo ""
                ;;
            2)
                write_ttc_log "INFO" "DB Browser: Generating Top 10 Highest Grossing Items list."
                echo -ne "\033[33mSearch by Source [TTC or ESO-Hub] (leave empty for ALL):\033[0m "
                read source_filter
                echo -ne "\033[33mFilter to your @Username only? (y/N):\033[0m "; read personal_opt
                
                echo -e "\n\033[33mTime Filter:\033[0m"
                echo -e " 1) Past 1 Week\n 2) Past 2 Weeks\n 3) Past 3 Weeks\n 4) All Data"
                echo -ne "\033[33mChoice [1-4] (default 4):\033[0m "; read time_opt
                
                cutoff_time=0; now_ts=$(date +%s)
                case "$time_opt" in
                    1) cutoff_time=$((now_ts - 604800)) ;;
                    2) cutoff_time=$((now_ts - 1209600)) ;;
                    3) cutoff_time=$((now_ts - 1814400)) ;;
                esac
                
                t_user=""
                if [[ "${personal_opt,,}" == "y" ]]; then
                    if [ -z "$TARGET_USERNAME" ]; then echo -e "\033[31m[!] @Username not set!\033[0m"
                    else t_user="$TARGET_USERNAME"; fi
                fi
                
                if [ -n "$t_user" ]; then echo -e "\n\033[36m--- Top 10 Highest Grossing [$t_user] ---\033[0m"
                else echo -e "\n\033[36m--- Top 10 Highest Grossing Items [Global] ---\033[0m"; fi
                
                search_hash=$(echo "O2v3|$source_filter|$personal_opt|$time_opt" \
                              | md5sum | awk '{print $1}')
                cache_file="$CACHE_DIR/cache_${search_hash}.txt"
                
                if [ -f "$cache_file" ] && [ "$cache_file" -nt "$DB_DIR/LTTC_History.db" ]; then
                    echo -e " \033[32m[+] Loading instantly from persistent cache...\033[0m\n"
                    cat "$cache_file"
                else
                    echo ""
                    start_spinner "Calculating Top 10 by Grossing (Building Cache)..."
                    awk -F'|' -v cutoff="$cutoff_time" \
                        -v src_filter="$(echo "$source_filter" | awk '{print tolower($0)}')" \
                        -v t_user="$(echo "$t_user" | awk '{print tolower($0)}')" '
                        $1=="HISTORY" && ($3=="Sold" || $3=="Purchased" || $3=="Listed") && $5 > 0 {
                            if (cutoff > 0 && $2 < cutoff) next;
                            if (src_filter != "" && index(tolower($13), src_filter) == 0) next;
                            if (t_user != "") {
                                if (index(tolower($8), t_user) == 0 && index(tolower($9), t_user) == 0) next;
                            }
                            if (index($7, "Unknown Item (") == 1) next;
                            
                            qty = ($5 > 0) ? $5 : 1; unit_p = $4 / qty; name = $7
                            scans = ($14 != "" && $14 > 0) ? $14 + 0 : 1
                            colors[name] = ($12 != "") ? $12 : "\033[0m"
                            item_ids[name] = $6
                            
                            for (s=0; s<scans; s++) {
                                prices[name, count[name]++] = unit_p
                                if ($3=="Sold" || $3=="Purchased") gold[name] += $4
                            }
                        }
                        END {
                            for (name in gold) {
                                n = count[name]
                                if (n < 5) { sugg = 0 } else {
                                    for (i=0; i<n; i++) {
                                        for (j=i+1; j<n; j++) {
                                            if (prices[name, i] > prices[name, j]) {
                                                temp = prices[name, i]
                                                prices[name, i] = prices[name, j]
                                                prices[name, j] = temp
                                            }
                                        }
                                    }
                                    trim = int(n * 0.10); if (trim == 0) trim = 1
                                    valid_n = n - (2 * trim); if (valid_n < 1) valid_n = 1
                                    
                                    mid_start = trim + int(valid_n * 0.45)
                                    mid_end = trim + int(valid_n * 0.55)
                                    if (mid_end < mid_start) mid_end = mid_start
                                    
                                    sum = 0; c = 0
                                    for (i=mid_start; i<=mid_end; i++) {
                                        sum += prices[name, i]; c++
                                    }
                                    sugg = sum / c
                                }
                                print gold[name] "|" name "|" sugg "|" colors[name] "|" item_ids[name]
                            }
                        }' "$DB_DIR/LTTC_History.db" | sort -t'|' -k1,1nr | head -n 10 | awk -F'|' '{
                            p_str = ($3 == 0) ? "Not enough data" : sprintf("%.2f", $3 + 0) "g"
                            gross_fmt = sprintf("%.0f", $1 + 0)
                            
                            name_enc = $2; gsub(/ /, "+", name_enc); gsub(/'\''/, "%27", name_enc)
                            
                            ttc_l = "\033[90m[\033]8;;https://us.tamrieltradecentre.com/pc/Trade/" \
                                    "SearchResult?SearchType=Sell&ItemNamePattern=" name_enc \
                                    "\033\\TTC\033]8;;\033\\]\033[0m"
                            eso_l = "\033[90m[\033]8;;https://eso-hub.com/en/trading/" $5 \
                                    "\033\\ESO-Hub\033]8;;\033\\]\033[0m"
                            
                            uesp_l = ""
                            if ($2 ~ /^(Blueprint|Praxis|Design|Pattern|Formula|Diagram|Sketch): /) {
                                u_name = $2; sub(/^[^:]+: /, "", u_name)
                                gsub(/ /, "_", u_name); gsub(/'\''/, "%27", u_name)
                                uesp_l = " \033[90m[\033]8;;https://en.uesp.net/wiki/File:ON-" \
                                         "furnishing-" u_name ".jpg\033\\UESP\033]8;;\033\\]\033[0m"
                            } else if ($2 ~ /Crafting Motif/ || $2 ~ /Style Page:/) {
                                u_name = $2
                                sub(/^.*Crafting Motif [^:]+: /, "", u_name)
                                sub(/^.*Style Page: /, "", u_name)
                                sub(/ (Axes|Belts|Boots|Bows|Chests|Daggers|Gloves|Helmets)$/, "", u_name)
                                sub(/ (Legs|Maces|Shields|Shoulders|Staves|Swords|Cuirass)$/, "", u_name)
                                sub(/ (Greaves|Helm|Pauldrons|Sabatons|Gauntlets|Bracers)$/, "", u_name)
                                sub(/ (Epaulets|Jack|Guards|Belt|Shoes|Jerkin|Breeches|Hat)$/, "", u_name)
                                sub(/ (Robes|Sash|Girdle|Corselet|Arm Cops)$/, "", u_name)
                                sub(/ Style$/, "", u_name)
                                gsub(/ /, "_", u_name); gsub(/'\''/, "%27", u_name)
                                uesp_l = " \033[90m[\033]8;;https://en.uesp.net/wiki/Online:" \
                                         u_name "_Style\033\\UESP\033]8;;\033\\]\033[0m"
                            }
                            
                            print " \033[33m" gross_fmt "g\033[0m grossed - " $4 $2 "\033[0m " \
                                  "(Avg: \033[33m" p_str "\033[0m) " ttc_l " " eso_l uesp_l
                        }' > "$cache_file"
                    stop_spinner 0 "Calculation complete"
                    echo ""
                    cat "$cache_file"
                fi
                echo ""
                ;;
            3)
                echo -ne "\033[33mEnter exact or partial item name for price check:\033[0m "; read p_term
                echo -ne "\033[33mSearch by Source [TTC or ESO-Hub] (leave empty for ALL):\033[0m "
                read source_filter
                echo -ne "\033[33mFilter to your @Username only? (y/N):\033[0m "; read personal_opt
                
                write_ttc_log "INFO" "DB Browser: Executed Suggested Price Check for '$p_term'"
                echo -e "\n\033[33mTime Filter:\033[0m"
                echo -e " 1) Past 1 Week\n 2) Past 2 Weeks\n 3) Past 3 Weeks\n 4) All Data"
                echo -ne "\033[33mChoice [1-4] (default 4):\033[0m "; read time_opt
                
                cutoff_time=0; now_ts=$(date +%s)
                case "$time_opt" in
                    1) cutoff_time=$((now_ts - 604800)) ;;
                    2) cutoff_time=$((now_ts - 1209600)) ;;
                    3) cutoff_time=$((now_ts - 1814400)) ;;
                esac
                
                t_user=""
                if [[ "${personal_opt,,}" == "y" ]]; then
                    if [ -z "$TARGET_USERNAME" ]; then echo -e "\033[31m[!] @Username not set!\033[0m"
                    else t_user="$TARGET_USERNAME"; fi
                fi
                
                echo -e "\n\033[36m--- Suggested Price Check ---\033[0m"
                search_hash=$(echo "O3v3|$p_term|$source_filter|$personal_opt|$time_opt" \
                              | md5sum | awk '{print $1}')
                cache_file="$CACHE_DIR/cache_${search_hash}.txt"
                
                if [ -f "$cache_file" ] && [ "$cache_file" -nt "$DB_DIR/LTTC_History.db" ]; then
                    echo -e " \033[32m[+] Loading instantly from persistent cache...\033[0m\n"
                    cat "$cache_file"
                else
                    echo ""
                    start_spinner "Calculating Outlier Eliminations (Building Cache)..."
                    awk -F'|' \
                        -v term="$(echo "$p_term" | awk '{print tolower($0)}')" \
                        -v cutoff="$cutoff_time" \
                        -v src_filter="$(echo "$source_filter" | awk '{print tolower($0)}')" \
                        -v t_user="$(echo "$t_user" | awk '{print tolower($0)}')" '
                        $1=="HISTORY" && tolower($7) ~ term && \
                        ($3=="Listed" || $3=="Sold" || $3=="Purchased") && \
                        $4 ~ /^[0-9]+(\.[0-9]+)?$/ && $5 > 0 {
                            
                            if (cutoff > 0 && $2 < cutoff) next;
                            if (src_filter != "" && index(tolower($13), src_filter) == 0) next;
                            if (t_user != "") {
                                if (index(tolower($8), t_user) == 0 && index(tolower($9), t_user) == 0) next;
                            }
                            if (index($7, "Unknown Item (") == 1) next;
                            
                            qty = ($5 > 0) ? $5 : 1; unit_p = $4 / qty; name = $7
                            scans = ($14 != "" && $14 > 0) ? $14 + 0 : 1
                            colors[name] = ($12 != "") ? $12 : "\033[0m"
                            item_ids[name] = $6
                            
                            for (s=0; s<scans; s++) { prices[name, count[name]++] = unit_p }
                        }
                        END {
                            for (item in count) {
                                split(item, parts, SUBSEP)
                                name = parts[1]; n = count[name]
                                if (n < 5) continue;
                                
                                delete p_arr
                                for (i=0; i<n; i++) { p_arr[i] = prices[name, i] }
                                for (i=0; i<n; i++) {
                                    for (j=i+1; j<n; j++) {
                                        if (p_arr[i] > p_arr[j]) {
                                            temp=p_arr[i]; p_arr[i]=p_arr[j]; p_arr[j]=temp
                                        }
                                    }
                                }
                                
                                trim = int(n * 0.10); if (trim == 0) trim = 1
                                valid_n = n - (2 * trim); if (valid_n < 1) valid_n = 1
                                
                                mid_start = trim + int(valid_n * 0.45)
                                mid_end = trim + int(valid_n * 0.55)
                                if (mid_end < mid_start) mid_end = mid_start
                                
                                sum = 0; c = 0
                                for (i=mid_start; i<=mid_end; i++) { sum += p_arr[i]; c++ }
                                sugg = sum / c
                                sugg_fmt = sprintf("%.2f", sugg + 0)
                                
                                name_enc = name; gsub(/ /, "+", name_enc); gsub(/'\''/, "%27", name_enc)
                                ttc_l = "\033[90m[\033]8;;https://us.tamrieltradecentre.com/pc/Trade/" \
                                        "SearchResult?SearchType=Sell&ItemNamePattern=" name_enc \
                                        "\033\\TTC\033]8;;\033\\]\033[0m"
                                eso_l = "\033[90m[\033]8;;https://eso-hub.com/en/trading/" \
                                        item_ids[name] "\033\\ESO-Hub\033]8;;\033\\]\033[0m"
                                
                                uesp_l = ""
                                if (name ~ /^(Blueprint|Praxis|Design|Pattern|Formula|Diagram|Sketch): /) {
                                    u_name = name; sub(/^[^:]+: /, "", u_name)
                                    gsub(/ /, "_", u_name); gsub(/'\''/, "%27", u_name)
                                    uesp_l = " \033[90m[\033]8;;https://en.uesp.net/wiki/File:ON-" \
                                             "furnishing-" u_name ".jpg\033\\UESP\033]8;;\033\\]\033[0m"
                                } else if (name ~ /Crafting Motif/ || name ~ /Style Page:/) {
                                    u_name = name
                                    sub(/^.*Crafting Motif [^:]+: /, "", u_name)
                                    sub(/^.*Style Page: /, "", u_name)
                                    sub(/ (Axes|Belts|Boots|Bows|Chests|Daggers|Gloves|Helmets)$/, "", u_name)
                                    sub(/ (Legs|Maces|Shields|Shoulders|Staves|Swords|Cuirass)$/, "", u_name)
                                    sub(/ (Greaves|Helm|Pauldrons|Sabatons|Gauntlets|Bracers)$/, "", u_name)
                                    sub(/ (Epaulets|Jack|Guards|Belt|Shoes|Jerkin|Breeches|Hat)$/, "", u_name)
                                    sub(/ (Robes|Sash|Girdle|Corselet|Arm Cops)$/, "", u_name)
                                    sub(/ Style$/, "", u_name)
                                    gsub(/ /, "_", u_name); gsub(/'\''/, "%27", u_name)
                                    uesp_l = " \033[90m[\033]8;;https://en.uesp.net/wiki/Online:" \
                                             u_name "_Style\033\\UESP\033]8;;\033\\]\033[0m"
                                }
                                
                                print colors[name] name "\033[0m - Suggested Price: \033[33m" \
                                      sugg_fmt "g\033[0m (Based on " n " data points) " \
                                      ttc_l " " eso_l uesp_l
                            }
                        }' "$DB_DIR/LTTC_History.db" > "$cache_file"
                    
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
                ;;
            4)
                echo -e "\n\033[36m--- Settings: Edit My Target Username ---\033[0m"
                echo -ne "\033[33mEnter your exact @Username (leave blank to clear): \033[0m"
                read input_user
                
                if [ -z "$input_user" ]; then
                    if grep -q "^TARGET_USERNAME=" "$CONFIG_FILE"; then
                        sed -i.bak 's/^TARGET_USERNAME=.*/TARGET_USERNAME=""/' "$CONFIG_FILE"
                        rm -f "$CONFIG_FILE.bak" 2>/dev/null
                    else echo "TARGET_USERNAME=\"\"" >> "$CONFIG_FILE"; fi
                    TARGET_USERNAME=""
                    echo -e " \033[90m[-] Username cleared.\033[0m\n"
                    write_ttc_log "INFO" "DB Browser: Target Username cleared."
                else
                    input_user="${input_user#@}"; input_user="@$input_user"
                    if grep -q "^TARGET_USERNAME=" "$CONFIG_FILE"; then
                        sed -i.bak "s/^TARGET_USERNAME=.*/TARGET_USERNAME=\"$input_user\"/" "$CONFIG_FILE"
                        rm -f "$CONFIG_FILE.bak" 2>/dev/null
                    else echo "TARGET_USERNAME=\"$input_user\"" >> "$CONFIG_FILE"; fi
                    TARGET_USERNAME="$input_user"
                    echo -e " \033[92m[+] Username saved as $TARGET_USERNAME\033[0m\n"
                    write_ttc_log "INFO" "DB Browser: Target Username updated to '$TARGET_USERNAME'"
                fi
                echo -ne "\033[33mPress Enter to return...\033[0m "; read dummy_var
                ;;
            5) 
                write_ttc_log "INFO" "browse_database: exiting DB browser"; break 
                ;;
            *) 
                echo -e "\033[31mInvalid option.\033[0m" 
                ;;
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
        
        awk -F'|' -OFS='|' -v cutoff="$cutoff" -v db="$DB_FILE" -v del_log="$del_log" '
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
        $1=="HISTORY" {
            if ($2 < cutoff) {
                print $0 >> del_log
                next
            }
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
            if (index($11, "|") > 0) {
                split($11, kp, "|")
                $11 = kp[1]
            }
            if ($NF ~ /^[0-9]+$/) {
                scans = $NF + 0
                src = $(NF-1)
            } else {
                scans = 1
                src = $NF
            }
            if (src ~ /^(Unknown|\[Unknown\])$/ || src == "") src = "TTC"
            $13 = src
            $14 = scans
            print $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14
        }' "$DB_DIR/LTTC_History.db" > "$TEMP_DIR_ROOT/LTTC_History.tmp" 2>/dev/null
        
        local pruned_count=0
        if [ -s "$TEMP_DIR_ROOT/LTTC_History.tmp" ]; then
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
    fi
}

INSTALLED_SCRIPT="$TARGET_DIR/$SCRIPT_NAME"
if [ "$SETUP_COMPLETE" = "true" ] && [ "$HAS_ARGS" = false ]; then
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
                cp "${BASH_SOURCE[0]}" "$TARGET_DIR/$SCRIPT_NAME" 2>/dev/null
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
TEMP_DIR="$HOME/Downloads/${OS_BRAND}_Tamriel_Trade_Center_Temp"
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
    CONFIG_CHANGED=false
    TEMP_DIR_USED=false
    CURRENT_TIME=$(date +%s)
    TEMP_SCAN_FILE="$TEMP_DIR_ROOT/LTTC_TempScan.log"
    > "$TEMP_SCAN_FILE"
    NOTIF_TTC="Up-to-date"
    NOTIF_EH="Up-to-date"
    NOTIF_HM="Up-to-date"
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
    ui_echo "\e[0;97m         Cross-Platform Auto-Updater for TTC, HarvestMap & ESO-Hub\e[0m"
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
                
                api_resp=$(curl -s -X POST -H "User-Agent: ESOHubClient/1.0.9" \
                    -d "user_token=&client_system=$SYS_ID&client_version=1.0.9&lang=en" \
                    "https://data.eso-hub.com/v1/api/get-addon-versions" 2>/dev/null)
                    
                addon_lines=$(echo "$api_resp" | sed 's/{"folder_name"/\n{"folder_name"/g' \
                    | grep '"folder_name"')
                    
                while read -r line; do
                    fname=$(echo "$line" | grep -oE '"folder_name":"[^"]+"' \
                        | cut -d'"' -f4 | tr -d '\r\n\t ')
                        
                    if [ "$fname" = "LibEsoHubPrices" ]; then continue; fi
                    
                    dl_url=$(echo "$line" | grep -oE '"file":"[^"]+"' \
                        | cut -d'"' -f4 | sed 's/\\//g' | tr -d '\r\n\t ')
                        
                    srv_ver=$(echo "$line" | grep -oE '"version":\{[^}]*\}' \
                        | grep -oE '"string":"[^"]+"' | cut -d'"' -f4 | tr -d '\r\n\t ')
                        
                    id_num=$(echo "$dl_url" | grep -oE '[0-9]+$')
                    [ -z "$id_num" ] && id_num="0"
                    
                    if [ -n "$fname" ] && [ -n "$dl_url" ]; then
                        stop_spinner 0 "Fetching $fname"
                        start_spinner "Downloading $fname..."
                        if curl -s -f -m 30 -L -A "ESOHubClient/1.0.9" \
                            -o "$TEMP_DIR_ROOT/${fname}.zip" --url "$dl_url" </dev/null; then
                            
                            unzip -q -o "$TEMP_DIR_ROOT/${fname}.zip" -d "$ADDON_DIR/" > /dev/null 2>&1
                            rm -f "$TEMP_DIR_ROOT/${fname}.zip"
                            stop_spinner 0 "$fname installed"
                            write_ttc_log "INFO" "ESO-Hub Addon installed: $fname"
                            
                            var_name="EH_LOC_$id_num"
                            printf -v "$var_name" "%s" "$srv_ver"
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
                done <<< "$addon_lines"
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
        DB_API_RESP=$(curl -s -m 30 "https://api.mmoui.com/v3/game/ESO/filedetails/4428.json" 2>/dev/null)
        SRV_DB_VER=$(echo "$DB_API_RESP" | grep -ioE '"(version|uiversion)":"[^"]*"' | head -n 1 \
            | cut -d'"' -f4 | tr -d '\r\n\t ')
        DB_DL_URL=$(echo "$DB_API_RESP" | grep -ioE '"downloadurl":"[^"]*"' | head -n 1 \
            | cut -d'"' -f4 | sed 's/\\//g' | tr -d '\r\n\t ')
            
        [ -z "$DB_DL_URL" ] && DB_DL_URL="https://cdn.esoui.com/downloads/file4428/"
        [ -z "$SRV_DB_VER" ] && SRV_DB_VER="0.0.0"
        
        LOC_DB_VER="0.0.0"
        if [ -f "$DB_FILE" ]; then
            extracted_ver=$(head -n 1 "$DB_FILE" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
            [ -n "$extracted_ver" ] && LOC_DB_VER="$extracted_ver"
        fi
        
        [ "$SRV_DB_VER" = "$LOC_DB_VER" ] && V_COL="\e[92m" || V_COL="\e[31m"
        ui_echo "\t\e[90mServer_DB_Version= ${V_COL}$SRV_DB_VER\e[0m"
        ui_echo "\t\e[90mLocal_DB_Version=  ${V_COL}$LOC_DB_VER\e[0m"

        if [ "$SRV_DB_VER" != "$LOC_DB_VER" ] && [ "$SRV_DB_VER" != "0.0.0" ]; then
            write_ttc_log "INFO" "Downloading database update v$SRV_DB_VER"
            start_spinner "Downloading database template v$SRV_DB_VER..."
            curl -s -A "Mozilla/5.0" -o /dev/null "https://www.esoui.com/downloads/download4428.zip" &
            mkdir -p "$TEMP_DIR_ROOT/DB_Update"
            
            if curl -s -f -m 60 -L -A "Mozilla/5.0" -o "$TEMP_DIR_ROOT/DB_Update/db.zip" "$DB_DL_URL" </dev/null; then
                stop_spinner 0 "Database downloaded"
                unzip -q -o "$TEMP_DIR_ROOT/DB_Update/db.zip" -d "$TEMP_DIR_ROOT/DB_Update/" > /dev/null 2>&1
                NEW_DB=$(find "$TEMP_DIR_ROOT/DB_Update" -name "LTTC_Database.db" | head -n 1)
                NEW_HIST=$(find "$TEMP_DIR_ROOT/DB_Update" -name "LTTC_History.db" | head -n 1)
                
                if [ -n "$NEW_DB" ] && [ -f "$NEW_DB" ]; then
                    if [ ! -s "$DB_FILE" ]; then
                        echo "#DATABASE VERSION: $SRV_DB_VER" > "$DB_FILE"
                        cat "$NEW_DB" >> "$DB_FILE"
                    else
                        start_spinner "Merging new database entries..."
                        awk -F'|' '
                        /^#DATABASE VERSION:/ { next }
                        {
                            sub(/\r$/, "")
                            if ($1 == "GUILD") key = "GUILD_"$2
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
                        if [ ! -f "$DB_DIR/LTTC_History.db" ]; then
                            echo "#HISTORY VERSION: $SRV_DB_VER" > "$DB_DIR/LTTC_History.db"
                            cat "$NEW_HIST" >> "$DB_DIR/LTTC_History.db"
                        else
                            sed -i.bak '/^#HISTORY VERSION:/d' "$DB_DIR/LTTC_History.db" 2>/dev/null
                            sed -i.bak "1i\\#HISTORY VERSION: $SRV_DB_VER" "$DB_DIR/LTTC_History.db" 2>/dev/null
                            rm -f "$DB_DIR/LTTC_History.db.bak" 2>/dev/null
                        fi
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
                if [ "$ENABLE_DISPLAY" = true ] && [ "$SILENT" = false ]; then
                    start_spinner "Parsing TamrielTradeCentre.lua..."
                    echo -e "\n\e[0;35m--- TTC Extracted Data ---\e[0m" >> "$TEMP_SCAN_FILE"
                    
                    awk -v last_time="$TTC_LAST_SALE" -v now_time="$CURRENT_TIME" -v db_file="$DB_FILE" '
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
                                    
                                    if (itemid in db_qual) {
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
                                                            "interactive-map?map=" k_map "\\&ping=" k_coords \
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
                    ' "$SAVED_VAR_DIR/TamrielTradeCentre.lua" > "$TEMP_DIR_ROOT/lttc_ttc_tmp.out" 2>> "$LOG_FILE" &
                    
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
                        touch "$DB_DIR/LTTC_History.db" 2>/dev/null
                        awk -F'|' -v OFS='|' -v db="$DB_FILE" '
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
                                db_scans[uid] += scans
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
                        ' "$DB_DIR/LTTC_History.db" <(echo "$HISTORY_OUTPUT") \
                        > "$TEMP_DIR_ROOT/LTTC_History_Merged.tmp" 2>/dev/null
                        
                        if [ -s "$TEMP_DIR_ROOT/LTTC_History_Merged.tmp" ]; then
                            mv "$TEMP_DIR_ROOT/LTTC_History_Merged.tmp" "$DB_DIR/LTTC_History.db"
                        fi
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
                    if [ -z "$RAW_DATA" ] && [ "$ENABLE_DISPLAY" = true ]; then
                        NOTIF_TTC="No New Data"
                        cp -f "$SAVED_VAR_DIR/TamrielTradeCentre.lua" "$SNAP_DIR/lttc_ttc_snapshot.lua" 2>/dev/null
                    else
                        start_spinner "Uploading to https://$TTC_DOMAIN..."
                        if curl -s -A "$TTC_USER_AGENT" -F "SavedVarFileInput=@$SAVED_VAR_DIR/TamrielTradeCentre.lua" \
                            "https://$TTC_DOMAIN/pc/Trade/WebClient/Upload" > /dev/null 2>&1; then
                            NOTIF_TTC="Data Uploaded"
                            stop_spinner 0 "Upload finished"
                            cp -f "$SAVED_VAR_DIR/TamrielTradeCentre.lua" "$SNAP_DIR/lttc_ttc_snapshot.lua" 2>/dev/null
                        else
                            NOTIF_TTC="Upload Failed"
                            stop_spinner 1 "Upload failed"
                        fi
                    fi
                fi
            fi
        else
            ui_echo " \e[33m[-] No TamrielTradeCentre.lua found. \e[35mSkipping.\e[0m\n"
        fi

        ui_echo "\e[1m\e[97m [2/4] Updating your Local TTC Data \e[0m\n \e[33mChecking TTC APIs...\e[0m"
        TTC_LAST_CHECK="$CURRENT_TIME"
        CONFIG_CHANGED=true
        
        srv_list=()
        if [ "$AUTO_SRV" == "1" ] || [ "$AUTO_SRV" == "3" ]; then srv_list+=("NA"); fi
        if [ "$AUTO_SRV" == "2" ] || [ "$AUTO_SRV" == "3" ]; then srv_list+=("EU"); fi

        needs_dl=false
        dl_na=false
        dl_eu=false
        highest_srv_version="0"
        
        s_ver_na="0"; s_ver_eu="0"
        for srv in "${srv_list[@]}"; do
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
            if [ "$srv" == "NA" ]; then loc_ver="${TTC_NA_VERSION:-0}"; else loc_ver="${TTC_EU_VERSION:-0}"; fi
            
            if [ "$loc_ver" == "0" ] && [ -f "$pt_file" ]; then
                loc_ver=$(head -n 5 "$pt_file" 2>/dev/null | grep -iE '^--Version[ \t]*=[ \t]*[0-9]+' \
                    | grep -oE '[0-9]+' | head -n 1)
                [ -z "$loc_ver" ] && loc_ver="0"
            fi
            
            loc_disp="$loc_ver"
            [ "$loc_ver" = "0" ] && loc_disp="None"
            s_ver_disp="$s_ver"
            [ "$s_ver" = "0" ] && s_ver_disp="Error"
            
            [ "$s_ver" = "$loc_ver" ] && v_col="\e[92m" || v_col="\e[31m"
            
            ui_echo " \t\e[90mServer Version ($srv): ${v_col}$s_ver_disp\e[0m"
            ui_echo " \t\e[90mLocal Version ($srv):  ${v_col}$loc_disp\e[0m"
            
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
                            success_all=false
                        fi
                    done
                    
                    has_na=false; [ -d "TTC_Extracted_NA" ] && has_na=true
                    has_eu=false; [ -d "TTC_Extracted_EU" ] && has_eu=true
                    
                    if [ "$success_all" = true ] || [ "$has_na" = true ] || [ "$has_eu" = true ]; then
                        mkdir -p "$ADDON_DIR/TamrielTradeCentre"
                        
                        if [ "$has_na" = true ]; then
                            rsync -avh TTC_Extracted_NA/ "$ADDON_DIR/TamrielTradeCentre/" > /dev/null
                            TTC_NA_VERSION="$s_ver_na"
                        fi
                        
                        if [ "$has_eu" = true ]; then
                            rsync -avh TTC_Extracted_EU/ "$ADDON_DIR/TamrielTradeCentre/" > /dev/null
                            TTC_EU_VERSION="$s_ver_eu"
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
            else
                if [ "$s_ver_na" != "0" ] && [ "$s_ver_na" -ge "${TTC_NA_VERSION:-0}" ]; then
                    TTC_NA_VERSION="$s_ver_na"
                    CONFIG_CHANGED=true
                fi
                if [ "$s_ver_eu" != "0" ] && [ "$s_ver_eu" -ge "${TTC_EU_VERSION:-0}" ]; then
                    TTC_EU_VERSION="$s_ver_eu"
                    CONFIG_CHANGED=true
                fi
                ui_echo " \e[90mNo changes detected. \e[92mLocal PriceTable is up-to-date.\e[0m\n"
            fi
        fi

    ui_echo "\e[1m\e[97m [3/4] Updating ESO-Hub Prices & Uploading Scans \e[0m"
    ui_echo " \e[36mFetching latest ESO-Hub version data...\e[0m"
    
    EH_LAST_CHECK="$CURRENT_TIME"
    CONFIG_CHANGED=true
    EH_UPLOAD_COUNT=0
    EH_UPDATE_COUNT=0
    
    API_RESP=$(curl -s -X POST -H "User-Agent: ESOHubClient/1.0.9" \
        -d "user_token=&client_system=$SYS_ID&client_version=1.0.9&lang=en" \
        "https://data.eso-hub.com/v1/api/get-addon-versions" 2>/dev/null)
        
    ADDON_LINES=$(echo "$API_RESP" | sed 's/{"folder_name"/\n{"folder_name"/g' | grep '"folder_name"')
    
    if [ -z "$ADDON_LINES" ]; then
        NOTIF_EH="Download Error"
        ui_echo " \e[31m[-] Could not fetch ESO-Hub data.\e[0m\n"
    else
        EH_TIME_DIFF=$((CURRENT_TIME - EH_LAST_DOWNLOAD))
        EH_DOWNLOAD_OCCURRED=false
        
        while read -r line; do
            FNAME=$(echo "$line" | grep -oE '"folder_name":"[^"]+"' | cut -d'"' -f4)
            SV_NAME=$(echo "$line" | grep -oE '"sv_file_name":"[^"]+"' | cut -d'"' -f4)
            UP_EP=$(echo "$line" | grep -oE '"endpoint":"[^"]+"' | cut -d'"' -f4 | sed 's/\\//g')
            DL_URL=$(echo "$line" | grep -oE '"file":"[^"]+"' | cut -d'"' -f4 | sed 's/\\//g')
            
            if [ -z "$FNAME" ]; then continue; fi
            
            HAS_THIS_EH=$(is_addon_active "$FNAME")
            if [ "$HAS_THIS_EH" = "false" ]; then
                ui_echo " \e[31m[-] $FNAME missing. \e[35mSkipping.\e[0m"
                continue
            fi
            
            ID_NUM=$(echo "$DL_URL" | grep -oE '[0-9]+$')
            [ -z "$ID_NUM" ] && ID_NUM="0"
            
            SRV_VER=$(echo "$line" | grep -oE '"version":\{[^}]*\}' \
                | grep -oE '"string":"[^"]+"' | cut -d'"' -f4)
                
            PREFIX="$FNAME"
            [ "$FNAME" = "EsoTradingHub" ] && PREFIX="ETH5"
            [ "$FNAME" = "LibEsoHubPrices" ] && PREFIX="LEHP7"
            [ "$FNAME" = "EsoHubScanner" ] && PREFIX="EHS"
            
            VAR_LOC_NAME="EH_LOC_$ID_NUM"
            LOC_VER="${!VAR_LOC_NAME}"
            [ -z "$LOC_VER" ] && LOC_VER="0"
            
            if [ "$LOC_VER" = "0" ] && [ -d "$ADDON_DIR/$FNAME" ]; then
                LOC_VER="$SRV_VER"
                printf -v "$VAR_LOC_NAME" "%s" "$SRV_VER"
                CONFIG_CHANGED=true
            fi
            
            [ "$SRV_VER" = "$LOC_VER" ] && V_COL="\e[92m" || V_COL="\e[31m"
            
            ui_echo " \e[33mChecking server for $FNAME.zip...\e[0m"
            ui_echo "\t\e[90m${PREFIX}_Server_Version= ${V_COL}$SRV_VER\e[0m"
            ui_echo "\t\e[90m${PREFIX}_Local_Version= ${V_COL}$LOC_VER\e[0m"
            
            if [ -n "$SV_NAME" ] && [ -n "$UP_EP" ] && [ -f "$SAVED_VAR_DIR/$SV_NAME" ]; then
                eh_snap_name=$(echo "$SV_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/\.lua//')
                UP_SNAP="$SNAP_DIR/lttc_eh_${eh_snap_name}_snapshot.lua"
                EH_LOCAL_CHANGED=true
                
                if [ -f "$UP_SNAP" ] && [ ! "$SAVED_VAR_DIR/$SV_NAME" -nt "$UP_SNAP" ]; then
                    EH_LOCAL_CHANGED=false
                fi
                
                if [ "$EH_LOCAL_CHANGED" = false ]; then
                    ui_echo " \e[90mNo changes detected in $SV_NAME. \e[35mSkipping upload.\e[0m"
                else
                    if [ "$SV_NAME" = "EsoTradingHub.lua" ] && [ "$ENABLE_DISPLAY" = true ] && [ "$SILENT" = false ]; then
                        start_spinner "Parsing $SV_NAME..."
                        echo -e "\n\e[0;35m--- ESO-Hub Extracted Data ---\e[0m" >> "$TEMP_SCAN_FILE"
                        
                        awk -v last_time="$EH_LAST_SALE" -v now_time="$CURRENT_TIME" -v db_file="$DB_FILE" '
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
                        ' "$SAVED_VAR_DIR/$SV_NAME" > "$TEMP_DIR_ROOT/lttc_eh_tmp.out" 2>> "$LOG_FILE" &
                        
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
                            touch "$DB_DIR/LTTC_History.db" 2>/dev/null
                            awk -F'|' -v OFS='|' -v db="$DB_FILE" '
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
                                    db_scans[uid] += scans
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
                            }' "$DB_DIR/LTTC_History.db" <(echo "$HISTORY_OUTPUT") \
                            > "$TEMP_DIR_ROOT/LTTC_History_Merged.tmp" 2>/dev/null
                            
                            if [ -s "$TEMP_DIR_ROOT/LTTC_History_Merged.tmp" ]; then
                                mv "$TEMP_DIR_ROOT/LTTC_History_Merged.tmp" "$DB_DIR/LTTC_History.db"
                            fi
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
                    else
                        if [ "$SV_NAME" = "EsoTradingHub.lua" ] && [ -z "$RAW_DATA" ]; then
                            cp -f "$SAVED_VAR_DIR/$SV_NAME" "$UP_SNAP" 2>/dev/null
                        elif [ "$SV_NAME" = "EsoHubScanner.lua" ] && ! grep -qE '\|H[0-9a-fA-F]*:item:[0-9]+' "$SAVED_VAR_DIR/$SV_NAME" 2>/dev/null; then
                            cp -f "$SAVED_VAR_DIR/$SV_NAME" "$UP_SNAP" 2>/dev/null
                        else
                            start_spinner "Uploading local scan data ($SV_NAME)..."
                            if curl -s -m 60 -A "ESOHubClient/1.0.9" \
                                -F "file=@$SAVED_VAR_DIR/$SV_NAME" \
                                "https://data.eso-hub.com$UP_EP?user_token=$EH_USER_TOKEN" > /dev/null 2>&1; then
                                
                                cp -f "$SAVED_VAR_DIR/$SV_NAME" "$UP_SNAP" 2>/dev/null
                                EH_UPLOAD_COUNT=$((EH_UPLOAD_COUNT + 1))
                                stop_spinner 0 "Upload finished ($SV_NAME)"
                            else
                                stop_spinner 1 "Upload failed ($SV_NAME)"
                            fi
                        fi
                    fi
                fi
            fi
            
            if [ -n "$DL_URL" ]; then
                if [ "$SRV_VER" = "$LOC_VER" ]; then
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
                        
                        if ! curl -s -f -L -m 30 -A "ESOHubClient/1.0.9" -o "EH_$ID_NUM.zip" --url "$DL_URL"; then
                            curl -s -f -L -m 30 -A "$RAND_UA" -o "EH_$ID_NUM.zip" --url "$DL_URL"
                        fi
                        
                        if unzip -t "EH_$ID_NUM.zip" > /dev/null 2>&1; then
                            unzip -o "EH_$ID_NUM.zip" -d ESOHub_Extracted > /dev/null
                            rsync -avh ESOHub_Extracted/ "$ADDON_DIR/" > /dev/null
                            
                            printf -v "$VAR_LOC_NAME" "%s" "$SRV_VER"
                            CONFIG_CHANGED=true
                            EH_DOWNLOAD_OCCURRED=true
                            EH_UPDATE_COUNT=$((EH_UPDATE_COUNT + 1))
                            stop_spinner 0 "$FNAME.zip updated successfully"
                        else
                            stop_spinner 1 "Error: $FNAME.zip download corrupted"
                        fi
                    fi
                fi
            fi
        done <<< "$ADDON_LINES"
        
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
            SRV_HM_STATUS="Latest"
            
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
            ui_echo "\t\e[90mServer_Data_Status= \e[92m$SRV_HM_STATUS\e[0m"
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
                    [[ -f "$MAIN_HM_FILE" ]] && cp -f "$MAIN_HM_FILE" "$HM_SNAP" 2>/dev/null
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

    if [ "$FOUND_NEW_DATA" = true ]; then mv -f "$TEMP_SCAN_FILE" "$LAST_SCAN_FILE"; fi
    
    prune_history
    
    if [ "$CONFIG_CHANGED" = true ]; then write_lttc_config; fi
    
    cd "$HOME" || exit
    start_spinner "Cleaning up temp files & old logs..."
    
    if [ -f "$LOG_FILE" ]; then
        if [ "$OS_TYPE" = "Darwin" ]; then
            cutoff_date=$(date -v-3d '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
        else
            cutoff_date=$(date -d "3 days ago" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
        fi
        
        if [ -n "$cutoff_date" ]; then
            awk -v cutoff="$cutoff_date" '
            BEGIN { keep = 0 }
            /^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\]/ {
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
                  "$TEMP_DIR_ROOT"/*.zip "$TEMP_DIR_ROOT"/ESOHub_Extracted; do
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
        push_sys_notif "TTC: $NOTIF_TTC\nESO-Hub: $NOTIF_EH\nHarvestMap: $NOTIF_HM"
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
                sleep 5
                current_loop_time=$(date +%s)
                if (( current_loop_time - last_eso_check >= 5 )); then
                    last_eso_check=$current_loop_time
                    if ! is_eso_running; then exit 0; fi
                fi
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
