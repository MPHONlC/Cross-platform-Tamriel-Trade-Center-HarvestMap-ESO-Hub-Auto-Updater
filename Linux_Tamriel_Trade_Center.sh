#!/bin/bash

# ===========================================================================================
# Linux/Unix Tamriel Trade Center: Cross-Platform Auto-Updater for TTC, HarvestMap & ESO-Hub
# Created by @APHONIC
# ===========================================================================================

# ========================================================================================
# DISCLAIMER & CREDITS
# Icon Source: Official favicon from Tamriel Trade Centre (https://tamrieltradecentre.com)
# Data Sources: Tamriel Trade Centre, HarvestMap, UESP, and ESO-Hub.
# 
# This script is a utility to automate local data updates. It is not 
# affiliated with, nor does it claim ownership of, the aforementioned addons. 
# All rights belong to their original creators. Provided "as is" with no warranty;
# the author is not responsible for any data loss. Always back up SavedVariables.
# ========================================================================================

unset LD_PRELOAD
unset LD_LIBRARY_PATH
unset STEAM_LD_PRELOAD

APP_VERSION="4.9"
OS_TYPE=$(uname -s)
TARGET_DIR="$HOME/Documents"

if [ "$OS_TYPE" = "Darwin" ]; then
    OS_BRAND="Unix"
    TARGET_DIR="$TARGET_DIR/${OS_BRAND}_Tamriel_Trade_Center"
    SYS_ID="mac"
else
    OS_BRAND="Linux"
    TARGET_DIR="$TARGET_DIR/${OS_BRAND}_Tamriel_Trade_Center"
    SYS_ID="linux"
fi

# Folder Structure Setup & Migration
DB_DIR="$TARGET_DIR/Database"
LOG_DIR="$TARGET_DIR/Logs"
SNAP_DIR="$TARGET_DIR/Snapshots"
TEMP_DIR_ROOT="$TARGET_DIR/Temp"
mkdir -p "$DB_DIR" "$LOG_DIR" "$SNAP_DIR" "$TEMP_DIR_ROOT"

# Migrate older files to their new subfolders
[ -f "$TARGET_DIR/LTTC_Database.db" ] && mv "$TARGET_DIR/LTTC_Database.db" "$DB_DIR/" 2>/dev/null
[ -f "$TARGET_DIR/LTTC_History.db" ] && mv "$TARGET_DIR/LTTC_History.db" "$DB_DIR/" 2>/dev/null
[ -f "$TARGET_DIR/LTTC.log" ] && mv "$TARGET_DIR/LTTC.log" "$LOG_DIR/" 2>/dev/null
[ -f "$TARGET_DIR/UTTC.log" ] && mv "$TARGET_DIR/UTTC.log" "$LOG_DIR/" 2>/dev/null
[ -f "$TARGET_DIR/LTTC_LastScan.log" ] && mv "$TARGET_DIR/LTTC_LastScan.log" "$LOG_DIR/" 2>/dev/null
[ -f "$TARGET_DIR/LTTC_Display_State.log" ] && mv "$TARGET_DIR/LTTC_Display_State.log" "$LOG_DIR/" 2>/dev/null

for snap in "$TARGET_DIR"/*_snapshot.lua; do
    [ -f "$snap" ] && mv "$snap" "$SNAP_DIR/" 2>/dev/null
done

# Clean old temporary files
rm -f "$TARGET_DIR"/*.tmp "$TARGET_DIR"/*.out 2>/dev/null

# Update Internal Paths
CONFIG_FILE="$TARGET_DIR/lttc_updater.conf"
DB_FILE="$DB_DIR/LTTC_Database.db"
LOG_FILE="$LOG_DIR/LTTC.log"
[ "$OS_TYPE" = "Darwin" ] && LOG_FILE="$LOG_DIR/UTTC.log"
LAST_SCAN_FILE="$LOG_DIR/LTTC_LastScan.log"
UI_STATE_FILE="$LOG_DIR/LTTC_Display_State.log"

APP_TITLE="$OS_BRAND Tamriel Trade Center v$APP_VERSION"
SCRIPT_NAME="${OS_BRAND}_Tamriel_Trade_Center.sh"
# trap & kill terminal
cleanup_on_close() {
    # Disable traps so it doesn't loop infinitely
    trap - EXIT SIGHUP SIGINT SIGTERM
    
    # Force delete any stuck lock files
    rm -f /tmp/ttc_updater_*.lock 2>/dev/null
    
    # Terminate ALL child processes spawned by this script
    pkill -P $$ 2>/dev/null
    
    exit 0
}
# Catch the Terminal GUI Close (SIGHUP), Ctrl+C (SIGINT), and standard Kills (SIGTERM)
trap cleanup_on_close EXIT SIGHUP SIGINT SIGTERM
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# only allow one instance to run
IS_BACKGROUND=false
for arg in "$@"; do
    if [ "$arg" = "--silent" ] || [ "$arg" = "--task" ] || [ "$arg" = "--steam" ]; then
        IS_BACKGROUND=true
    fi
done

handle_existing_process() {
    local old_pid=$1
    if [ "$IS_BACKGROUND" = true ]; then
        exit 0
    fi
    
    echo -e "\e[0;33m[!] Another instance of the updater (PID: ${old_pid:-Unknown}) is already running.\e[0m"
    read -t 10 -p "Do you want to terminate the existing process and continue? (y/n): " kill_choice || kill_choice="y"
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
        
        sleep 1
        return 0
    else
        echo -e "\e[0;32mKeeping the existing process safe. Exiting new instance.\e[0m"
        exit 1
    fi
}

if [ "$OS_TYPE" = "Linux" ] && command -v flock >/dev/null 2>&1; then
    LOCK_FILE="/tmp/ttc_updater_$APP_VERSION.lock"
    exec 200<>"$LOCK_FILE"
    if ! flock -n 200; then
            OLD_PID=$(cat "$LOCK_FILE" 2>/dev/null)
            handle_existing_process "$OLD_PID"
            
            # Force remove stuck lock files
            rm -rf /tmp/ttc_updater_*.lock 2>/dev/null
            exec 200<>"$LOCK_FILE"

            if ! flock -n 200; then
                sleep 1
                flock -n 200 || { echo -e "\e[0;31mFailed to acquire lock. Exiting.\e[0m"; exit 1; }
            fi
        fi
    > "$LOCK_FILE"
    echo $$ >&200
else
    LOCK_DIR="/tmp/ttc_updater_dir_$APP_VERSION"
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        echo $$ > "$LOCK_DIR/pid"
        trap 'rm -rf "$LOCK_DIR"; exit 0' EXIT SIGHUP SIGINT SIGTERM
    else
        OLD_PID=$(cat "$LOCK_DIR/pid" 2>/dev/null)
        handle_existing_process "$OLD_PID"
        rm -rf "$LOCK_DIR"
        mkdir "$LOCK_DIR" 2>/dev/null
        echo $$ > "$LOCK_DIR/pid"
        trap 'rm -rf "$LOCK_DIR"; exit 0' EXIT SIGHUP SIGINT SIGTERM
    fi
fi

mkdir -p "$TARGET_DIR"
CONFIG_FILE="$TARGET_DIR/lttc_updater.conf"

touch "$DB_FILE" 2>/dev/null
touch "$LOG_FILE" 2>/dev/null
touch "$LAST_SCAN_FILE" 2>/dev/null
touch "$UI_STATE_FILE" 2>/dev/null

LOG_MODE="simple"

log_event() {
    local level="$1"
    local message="$2"
    if [ "$LOG_MODE" != "detailed" ] && [ "$level" == "ITEM" ]; then return; fi
    clean_msg=$(echo "$message" | perl -pe 's/\e\[[0-9;]*m//g')
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $clean_msg" >> "$LOG_FILE"
}

scan_game_dir() {
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
            echo "$p"
            return 0
        fi
    done
    
    if [ "$OS_TYPE" = "Linux" ]; then
        FOUND_ZOS=$(find "$HOME" /run/media /mnt /media -maxdepth 6 -type d -name "Zenimax Online" 2>/dev/null | head -n 1)
        if [ -n "$FOUND_ZOS" ] && [ -f "$FOUND_ZOS/The Elder Scrolls Online/game/client/eso64.exe" ]; then
            echo "$FOUND_ZOS/The Elder Scrolls Online/game/client"; return 0;
        fi
    fi
    echo ""
}

check_game_active() {
    if pgrep -i -f 'eso64\.exe|steam_app_306130|eso\.app|Bethesda\.net_Launcher' > /dev/null 2>&1; then
        return 0
    fi
    return 1
}

SILENT=false
AUTO_PATH=false
AUTO_SRV=""
AUTO_MODE=""
ADDON_DIR=""
SETUP_COMPLETE=false
ENABLE_NOTIFS=false
HAS_ARGS=false
IS_TASK=false
IS_STEAM_LAUNCH=false
ENABLE_DISPLAY="true"
ENABLE_LOCAL_MODE=false

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

TTC_LAST_SALE="${TTC_LAST_SALE:-0}"
TTC_LAST_DOWNLOAD="${TTC_LAST_DOWNLOAD:-0}"
TTC_LAST_CHECK="${TTC_LAST_CHECK:-0}"
TTC_LOC_VERSION="${TTC_LOC_VERSION:-0}"
EH_LAST_SALE="${EH_LAST_SALE:-0}"
EH_LAST_DOWNLOAD="${EH_LAST_DOWNLOAD:-0}"
EH_LAST_CHECK="${EH_LAST_CHECK:-0}"
EH_LOC_5="${EH_LOC_5:-0}"
EH_LOC_7="${EH_LOC_7:-0}"
EH_LOC_9="${EH_LOC_9:-0}"
HM_LAST_DOWNLOAD="${HM_LAST_DOWNLOAD:-0}"
HM_LAST_CHECK="${HM_LAST_CHECK:-0}"
LOG_MODE="${LOG_MODE:-simple}"
EH_USER_TOKEN="${EH_USER_TOKEN:-}"
TARGET_RUN_TIME="${TARGET_RUN_TIME:-0}"
SKIP_DL_TTC="${SKIP_DL_TTC:-false}"
SKIP_DL_HM="${SKIP_DL_HM:-false}"
SKIP_DL_EH="${SKIP_DL_EH:-false}"

save_config() {
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
TTC_LOC_VERSION="$TTC_LOC_VERSION"
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

ensure_missing_addon() {
    local a_name="$1"
    local a_id="$2"
    local skip_var="$3"
    
    # Check if user declined this addon previously
    if [ "${!skip_var}" = true ]; then
        return 1
    fi
    
    if [ ! -d "$ADDON_DIR/$a_name" ]; then
        local ans="y"
        # Check if we are on Steamdeck
        if [ ! -f "/etc/os-release" ] || ! grep -qi "steamos" "/etc/os-release"; then
            echo -ne "\n \e[33m[?] $a_name is missing. Do you want to download it? (y/N):\e[0m "
            read -r ans < /dev/tty
        fi
        
        if [[ "$ans" =~ ^[Yy]$ ]]; then
                    ui_echo " \e[36mDownloading $a_name from ESOUI...\e[0m"
                    local api_resp=$(curl -s "https://api.mmoui.com/v3/game/ESO/filedetails/${a_id}.json")
                    local dl_url=$(echo "$api_resp" | grep -o '"downloadUrl":"[^"]*"' | cut -d'"' -f4 | sed 's/\\//g' | tr -d '\r\n\t ')
                    local addon_version=$(echo "$api_resp" | grep -o '"version":"[^"]*"' | cut -d'"' -f4 | tr -d '\r\n\t ')
                    
                    [ -z "$dl_url" ] && dl_url="https://cdn.esoui.com/downloads/file${a_id}/"
                    
                    if curl -s -f -m 30 -L -A "Mozilla/5.0" -o "$TEMP_DIR_ROOT/${a_name}.zip" "$dl_url" </dev/null; then
                        unzip -q -o "$TEMP_DIR_ROOT/${a_name}.zip" -d "$ADDON_DIR/" > /dev/null 2>&1
                        rm -f "$TEMP_DIR_ROOT/${a_name}.zip"
                        
                        # Save Local Version & Reset TTC Cooldown
                        if [ "$a_name" = "TamrielTradeCentre" ]; then
                            rm -f "$TEMP_DIR_ROOT/ttc_last_dl.txt" 2>/dev/null
                            if [ -n "$addon_version" ]; then
                                TTC_LOC_VERSION="$addon_version"
                                CONFIG_CHANGED=true
                            fi
                        fi
                        
                        # Sync LibEsoHubPrices timestamp
                        if [ "$a_name" = "LibEsoHubPrices" ]; then
                            local eh_api=$(curl -s -X POST -H "User-Agent: ESOHubClient/1.0.9" -d "user_token=&client_system=$SYS_ID&client_version=1.0.9&lang=en" "https://data.eso-hub.com/v1/api/get-addon-versions" 2>/dev/null)
                            local srv_ver=$(echo "$eh_api" | sed 's/{"folder_name"/\n{"folder_name"/g' | grep '"folder_name":"LibEsoHubPrices"' | grep -oE '"version":\{[^}]*\}' | grep -oE '"string":"[^"]+"' | cut -d'"' -f4 | tr -d '\r\n\t ')
                            if [ -n "$srv_ver" ]; then
                                EH_LOC_7="$srv_ver"
                                CONFIG_CHANGED=true
                            fi
                        fi
                    
                    ui_echo " \e[92m[+] $a_name installed successfully.\e[0m"
                    log_event "INFO" "Addon $a_name automatically downloaded and installed."
            
            # Enable in AddOnSettings.txt for all characters
                local settings_file="$ADDON_DIR/../AddOnSettings.txt"
                if [ -f "$settings_file" ]; then
                    if [ "$a_name" = "EsoTradingHub" ]; then
                        sed -i -e "s/^EsoTradingHub 0/EsoTradingHub 1/g" -e "s/^EsoHubScanner 0/EsoHubScanner 1/g" -e "s/^LibEsoHubPrices 0/LibEsoHubPrices 1/g" "$settings_file" 2>/dev/null
                        grep -q "^EsoTradingHub " "$settings_file" || echo "EsoTradingHub 1" >> "$settings_file"
                        grep -q "^EsoHubScanner " "$settings_file" || echo "EsoHubScanner 1" >> "$settings_file"
                        grep -q "^LibEsoHubPrices " "$settings_file" || echo "LibEsoHubPrices 1" >> "$settings_file"
                    elif [ "$a_name" = "HarvestMap" ] || [ "$a_name" = "HarvestMapData" ]; then
                        sed -i -e "s/^HarvestMap 0/HarvestMap 1/g" -e "s/^HarvestMapData 0/HarvestMapData 1/g" "$settings_file" 2>/dev/null
                        grep -q "^HarvestMap " "$settings_file" || echo "HarvestMap 1" >> "$settings_file"
                        grep -q "^HarvestMapData " "$settings_file" || echo "HarvestMapData 1" >> "$settings_file"
                    else
                        sed -i -e "s/^$a_name 0/$a_name 1/g" "$settings_file" 2>/dev/null
                        grep -q "^$a_name " "$settings_file" || echo "$a_name 1" >> "$settings_file"
                    fi
                fi
                return 0
            else
                ui_echo " \e[31m[-] Download failed for $a_name.\e[0m"
                log_event "ERROR" "Download failed for missing addon: $a_name."
                return 1
            fi
        else
            ui_echo " \e[90mUser Declined download of $a_name. Will not ask again.\e[0m"
            log_event "WARN" "User declined download for missing addon: $a_name."
            printf -v "$skip_var" "true"
            save_config
            return 1
        fi
    fi
    return 0
}

if [ "$#" -gt 0 ]; then HAS_ARGS=true; fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --silent) SILENT=true ;;
        --auto) AUTO_PATH=true ;;
        --na) AUTO_SRV="1" ;;
        --eu) AUTO_SRV="2" ;;
        --loop) AUTO_MODE="2" ;;
        --once) AUTO_MODE="1" ;;
        --task) IS_TASK=true; SILENT=true ;;
        --steam) IS_STEAM_LAUNCH=true ;;
        --addon-dir) shift; ADDON_DIR="$1" ;;
        --setup) rm -f "$CONFIG_FILE"; SETUP_COMPLETE=false ;;
    esac
    shift
done

# Standalone override
if [ "$IS_STEAM_LAUNCH" = false ] && [ "$IS_TASK" = false ]; then SILENT=false; fi
# Steam hidden mode notifications override
if [ "$IS_STEAM_LAUNCH" = true ] && [ "$SILENT" = true ]; then ENABLE_NOTIFS=true; fi

send_notification() {
    local msg="$1"
    if [ "$ENABLE_NOTIFS" = "false" ]; then return; fi
    
    if [ "$OS_TYPE" = "Darwin" ]; then
        osascript -e "display notification \"$msg\" with title \"$APP_TITLE\"" 2>/dev/null
    else
        if command -v notify-send > /dev/null; then
            notify-send -i "dialog-information" -t 5000 --hint=string:category:system "$APP_TITLE" "$msg" 2>/dev/null
        fi
    fi
}

detect_terminal() {
    if [ "$OS_TYPE" = "Darwin" ]; then echo "Terminal"
    elif command -v alacritty &> /dev/null; then echo "alacritty -e"
    elif command -v konsole &> /dev/null; then echo "konsole -e"
    elif command -v gnome-terminal &> /dev/null; then echo "gnome-terminal --"
    elif command -v xfce4-terminal &> /dev/null; then echo "xfce4-terminal -e"
    elif command -v kitty &> /dev/null; then echo "kitty --"
    else echo "xterm -e"; fi
}

auto_scan_addons() {
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
            "$HOME/Documents/Elder Scrolls Online/live/AddOns"
            "$HOME/PortWINE/PortProton/drive_c/users/steamuser/Documents/Elder Scrolls Online/live/AddOns"
            "$HOME/PortProton/prefixes/DEFAULT/drive_c/users/steamuser/Documents/Elder Scrolls Online/live/AddOns/"
        )
    elif [ "$OS_TYPE" = "Darwin" ]; then
        addon_paths=("$HOME/Documents/Elder Scrolls Online/live/AddOns")
    fi

    for p in "${addon_paths[@]}"; do [ -d "$p" ] && echo "$p" && return 0; done
    if [ "$OS_TYPE" = "Linux" ]; then
        while IFS= read -r base_dir; do
            [ -z "$base_dir" ] && continue
            for suffix in "/pfx/drive_c/users/steamuser/Documents/Elder Scrolls Online/live/AddOns" "/drive_c/users/$USER/Documents/Elder Scrolls Online/live/AddOns" "/live/AddOns"; do
                [ -d "$base_dir$suffix" ] && echo "$base_dir$suffix" && return 0
            done
        done <<< "$(find "$HOME" /run/media /mnt /media -maxdepth 6 \( -type d -name "306130" -o -type d -name "Elder Scrolls Online" -o -type d -name "bottles" -o -type d -name "lutris" \) 2>/dev/null)"
    fi
    echo ""
}

run_setup() {
    clear
    echo -e "\n\e[0;33m--- Initial Setup & Configuration ---\e[0m"
    log_event "INFO" "Starting initial setup process."

    if [ "$CURRENT_DIR" != "$TARGET_DIR" ]; then
        cp "${BASH_SOURCE[0]}" "$TARGET_DIR/$SCRIPT_NAME" 2>/dev/null
        chmod +x "$TARGET_DIR/$SCRIPT_NAME"
        echo -e "\e[0;32m[+] Script successfully copied/updated in Documents folder:\e[0m $TARGET_DIR"
        log_event "INFO" "Script installed to target directory: $TARGET_DIR"
    else
        echo -e "\e[0;36m-> Script is already running from the Documents folder.\e[0m\n"
    fi

    echo -e "\n\e[0;33m1. Which server do you play on? (For TTC Pricing)\e[0m"
    echo "1) North America (NA)"
    echo "2) Europe (EU)"
    read -p "Choice [1-2]: " AUTO_SRV

    echo -e "\n\e[0;33m2. Do you want the terminal to be visible when launching via Steam?\e[0m"
    echo "1) Show Terminal (Verbose visible output)"
    echo "2) Hide Terminal (Invisible background hidden)"
    read -p "Choice [1-2]: " term_choice
    [ "$term_choice" == "2" ] && SILENT=true || SILENT=false

    echo -e "\n\e[0;33m3. How should the script run during gameplay?\e[0m"
    echo "1) Run once and close immediately"
    echo "2) Loop continuously (Checks local file & server status every 60 minutes to avoid server rate-limit)"
    read -p "Choice [1-2]: " AUTO_MODE

    echo -e "\n\e[0;33m4. Extract & Display Data (Requires Database)\e[0m"
    echo "Do you want to extract and display item names/sales on the terminal?"
    echo "1) Yes (Extract, Display, and build LTTC_Database.db)"
    echo "2) No (Just upload the files instantly)"
    read -p "Choice [1-2]: " display_choice
    [ "$display_choice" == "2" ] && ENABLE_DISPLAY=false || ENABLE_DISPLAY=true

    echo -e "\n\e[0;33m5. Addon Folder Location\e[0m"
    if [ -n "$ADDON_DIR" ] && [ -d "$ADDON_DIR" ]; then
        echo -e "\e[0;32m[+] Found Saved Addons Directory at:\e[0m $ADDON_DIR"
        FOUND_ADDONS="$ADDON_DIR"
    else
        echo "Scanning default locations and drives for Addons folder..."
        FOUND_ADDONS=$(auto_scan_addons)
        if [ -n "$FOUND_ADDONS" ]; then
            echo -e "\e[0;32m[+] Found Addons folder at:\e[0m $FOUND_ADDONS"
            read -p "Is this the correct location? (y/n): " use_found
            if [[ ! "$use_found" =~ ^[Yy]$ ]]; then
                read -p "Enter full custom path to AddOns folder: " FOUND_ADDONS
            fi
        else
            echo -e "\e[0;31m[-] Could not find AddOns automatically.\e[0m"
            read -p "Enter full custom path to AddOns folder: " FOUND_ADDONS
        fi
    fi
    ADDON_DIR="$FOUND_ADDONS"
    log_event "INFO" "Addon directory set to: $ADDON_DIR"

    echo -e "\n\e[0;33m6. Enable Native System Notifications?\e[0m"
    echo "1) Yes (Summarizes updates, respects Do Not Disturb)"
    echo "2) No"
    read -p "Choice [1-2]: " notif_choice
    [ "$notif_choice" == "1" ] && ENABLE_NOTIFS=true || ENABLE_NOTIFS=false

    echo -e "\n\e[0;33m7. Logging Level\e[0m"
    echo "Creates a log file at $LOG_FILE"
    echo "1) Simple Logging (Default, records basic script events)"
    echo "2) Detailed Logging (Includes listed, sold items, and scans)"
    read -p "Choice [1-2]: " log_choice
    [ "$log_choice" == "2" ] && LOG_MODE="detailed" || LOG_MODE="simple"
    touch "$LOG_FILE" 2>/dev/null

    echo -e "\n\e[0;33m8. ESO-Hub Integration (Optional)\e[0m"
    echo -e "\n\e[0;33m(DO NOT SHARE YOUR TOKENS TO ANYONE)\e[0m"
    echo "1) Log in with Username and Password (Fetches API Token securely, and deletes your credentials.)"
    echo "2) Manually enter API Token (If you already know your token)"
    echo "3) Skip / Upload Anonymously No Login (Default)"
    read -p "Choice [1-3]: " eh_choice

    EH_USER_TOKEN=""
    if [ "$eh_choice" == "1" ]; then
        read -p "ESO-Hub Username: " EH_USER
        
        # Hide passwords in asterisks
        echo -n "ESO-Hub Password: "
        EH_PASS=""
        while IFS= read -r -s -n1 char; do
            if [[ -z $char ]]; then
                echo
                break
            fi
            # Handle backspace key
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
        
        # Use --data-urlencode to safely process @ symbols and complex passwords
        LOGIN_RESP=$(curl -s -X POST -H "User-Agent: ESOHubClient/1.0.9" \
             --data-urlencode "client_system=$SYS_ID" \
             --data-urlencode "client_version=1.0.9" \
             --data-urlencode "client_version_int=1009" \
             --data-urlencode "lang=en" \
             --data-urlencode "username=${EH_USER}" \
             --data-urlencode "password=${EH_PASS}" \
             "https://data.eso-hub.com/v1/api/login")
             
        EH_USER_TOKEN=$(echo "$LOGIN_RESP" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
        
        # Clear variables from memory immediately for security purposes (DELETES USERNAME & PASSWORD)
        EH_USER=""
        EH_PASS=""
        
        if [ -n "$EH_USER_TOKEN" ]; then
            echo -e "\e[0;32m[+] Successfully logged in! Token saved securely.\e[0m"
            log_event "INFO" "ESO-Hub user token successfully generated via API."
        else
            echo -e "\e[0;31m[-] Login failed. Please check your credentials. Falling back to anonymous mode.\e[0m"
            log_event "ERROR" "ESO-Hub login failed via API."
            EH_USER_TOKEN=""
        fi
    elif [ "$eh_choice" == "2" ]; then
        read -p "Token: " EH_USER_TOKEN
    fi

    SETUP_COMPLETE=true
    save_config
    log_event "INFO" "Setup complete. Configuration saved. Log Mode: $LOG_MODE"

    echo -e "\n\e[0;33m9. Desktop Shortcut\e[0m"
    read -p "Create a desktop shortcut? (y/n): " make_shortcut
    
    SHORTCUT_SRV_FLAG="--na"
    [ "$AUTO_SRV" == "2" ] && SHORTCUT_SRV_FLAG="--eu"
    SILENT_FLAG=""
    [ "$SILENT" == true ] && SILENT_FLAG="--silent"
    LOOP_FLAG="--once"
    [ "$AUTO_MODE" == "2" ] && LOOP_FLAG="--loop"

    if [[ "$make_shortcut" =~ ^[Yy]$ ]]; then
        ICON_PATH="$TARGET_DIR/ttc_icon.jpg"
        curl -s -L -o "$ICON_PATH" "https://eu.tamrieltradecentre.com/favicon.ico"

        if [[ "$OS_TYPE" == "Linux" ]]; then
            DESKTOP_DIR=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")
            APP_DIR="$HOME/.local/share/applications"
            
            # delete shortcuts
            rm -f "$HOME/Desktop/${OS_BRAND}_Tamriel_Trade_Center.desktop" 2>/dev/null
            rm -f "$HOME/.local/share/applications/${OS_BRAND}_Tamriel_Trade_Center.desktop" 2>/dev/null
            rm -f "$DESKTOP_DIR/${OS_BRAND}_Tamriel_Trade_Center.desktop" 2>/dev/null
            rm -f "$APP_DIR/${OS_BRAND}_Tamriel_Trade_Center.desktop" 2>/dev/null

            # Create shortcut
            mkdir -p "$DESKTOP_DIR"
            DESKTOP_FILE="$DESKTOP_DIR/${OS_BRAND}_Tamriel_Trade_Center.desktop"
            
            cat <<EOF > "$DESKTOP_FILE"
[Desktop Entry]
Version=1.0
Name=$APP_TITLE
Comment=Cross-Platform Auto-Updater for TTC, HarvestMap & ESO-Hub - Created by @APHONIC
Exec="$TARGET_DIR/$SCRIPT_NAME" $SILENT_FLAG $SHORTCUT_SRV_FLAG $LOOP_FLAG
Icon=$ICON_PATH
Terminal=$([ "$SILENT" = true ] && echo "false" || echo "true")
Type=Application
Categories=Game;Utility;
EOF
            chmod +x "$DESKTOP_FILE"
            mkdir -p "$APP_DIR"
            cp "$DESKTOP_FILE" "$APP_DIR/"
            
            # Force refresh visual cache
            update-desktop-database "$APP_DIR" 2>/dev/null || true
            
            echo -e "\e[0;32m[+] Linux desktop shortcut installed to Desktop and Application Launcher.\e[0m"
        elif [[ "$OS_TYPE" == "Darwin" ]]; then
            echo -e "\e[0;33m[!] Automatic macOS App creation is not fully supported in pure bash. A Terminal script alias can be used instead.\e[0m"
        fi
    else
        if [[ "$OS_TYPE" == "Linux" ]]; then
            DESKTOP_DIR=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")
            rm -f "$HOME/Desktop/${OS_BRAND}_Tamriel_Trade_Center.desktop" 2>/dev/null
            rm -f "$HOME/.local/share/applications/${OS_BRAND}_Tamriel_Trade_Center.desktop" 2>/dev/null
            rm -f "$DESKTOP_DIR/${OS_BRAND}_Tamriel_Trade_Center.desktop" 2>/dev/null
            rm -f "$HOME/.local/share/applications/${OS_BRAND}_Tamriel_Trade_Center.desktop" 2>/dev/null
            update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
        fi
    fi

    TERM_CMD=$(detect_terminal)
    echo -e "\n\e[0;92m================ SETUP COMPLETE ================\e[0m"
    echo -e "To run this automatically alongside your game, copy this string into your \e[1mSteam Launch Options\e[0m:\n"
    
    # Check user is on Steamdeck Gaming Mode
    IS_GAMESCOPE=false
    if [ "$XDG_CURRENT_DESKTOP" = "gamescope" ] || pgrep -x "gamescope" > /dev/null; then
        IS_GAMESCOPE=true
    fi

    # Detach process to runheadlessly and survive game runtime
    DETACHED_CMD="env -u LD_PRELOAD nohup bash -c '\"$TARGET_DIR/$SCRIPT_NAME\" $SHORTCUT_SRV_FLAG $LOOP_FLAG --silent --steam' >/dev/null 2>&1 & %command%"

    # Force detachment for steamdeck compatibility, regardless of user visibility choice
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
            LAUNCH_CMD="env -u LD_PRELOAD -u STEAM_LD_PRELOAD $TERM_CMD \"$TARGET_DIR/$SCRIPT_NAME\" $SHORTCUT_SRV_FLAG $LOOP_FLAG --steam & %command%"
            echo -e "\e[0;104m $LAUNCH_CMD \e[0m\n"
            echo -e "\e[0;33m(Note: Auto-detected your terminal as '$TERM_CMD').\e[0m\n"
        fi
    fi
    
    echo -e "\e[0;33m10. Steam Launch Options\e[0m"
    echo "Would you like this script to automatically inject the Launch Command into your Steam configuration?"
    echo "(WARNING: Steam MUST be closed to do this. We can close it for you.)"
    read -p "Apply automatically? (y/n): " auto_steam
    
    if [[ "$auto_steam" =~ ^[Yy]$ ]]; then
        STEAM_CMD="steam"
        if ! command -v steam >/dev/null 2>&1 && command -v flatpak >/dev/null 2>&1 && flatpak list | grep -qi com.valvesoftware.Steam; then
            STEAM_CMD="flatpak run com.valvesoftware.Steam"
        fi

        STEAM_PIDS=$(pgrep -x "steam" || pgrep -x "Steam" || pgrep -x "steam_osx" || pgrep -f "com.valvesoftware.Steam")
        if [ -n "$STEAM_PIDS" ]; then
            STEAM_PID=$(echo "$STEAM_PIDS" | head -n 1)
            echo -e "\e[0;33m[!] Steam is running. Closing Steam to safely inject options...\e[0m"
            log_event "WARN" "Steam was running during setup. Attempting to close."
            STEAM_EXEC=$(ps -p "$STEAM_PID" -o args= | cut -d' ' -f1)
            if [[ "$STEAM_EXEC" == *"flatpak"* ]] || pgrep -f "flatpak run com.valvesoftware.Steam" > /dev/null 2>&1; then
                STEAM_CMD="flatpak run com.valvesoftware.Steam"
            fi
            
            pkill -x steam > /dev/null 2>&1; pkill -x Steam > /dev/null 2>&1; pkill -x steam_osx > /dev/null 2>&1; pkill -f "com.valvesoftware.Steam" > /dev/null 2>&1
            read -t 5 -s 2>/dev/null || true
        fi
        
        # Override exported string for steamdeck compatibility
        [ "$IS_GAMESCOPE" = true ] && export LAUNCH_STR="$DETACHED_CMD" || export LAUNCH_STR="$LAUNCH_CMD"
        [ "$SILENT" = true ] && export LAUNCH_STR="$DETACHED_CMD"

        BACKUP_DIR="$TARGET_DIR/Backups"
        mkdir -p "$BACKUP_DIR"
        
        for conf in "$HOME/.steam/steam/userdata"/*/config/localconfig.vdf \
                    "$HOME/.local/share/Steam/userdata"/*/config/localconfig.vdf \
                    "/var/lib/flatpak/app/com.valvesoftware.Steam/.steam/root/userdata"/*/config/localconfig.vdf \
                    "$HOME/Library/Application Support/Steam/userdata"/*/config/localconfig.vdf; do
            if [ -f "$conf" ]; then
                TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
                STEAM_ID=$(basename $(dirname $(dirname "$conf")))
                BACKUP_FILE="$BACKUP_DIR/localconfig_${STEAM_ID}_${TIMESTAMP}.vdf"
                cp "$conf" "$BACKUP_FILE" 2>/dev/null
                echo -e "\e[0;36m-> Backed up Steam config to: $BACKUP_FILE\e[0m"
                log_event "INFO" "Backed up Steam config: $BACKUP_FILE"

                echo -e "\e[0;36m-> Injecting into $conf...\e[0m"
                perl -pi.bak -e 'BEGIN{undef $/;} my $ls=$ENV{LAUNCH_STR}; $ls=~s/"/\\"/g; if (/"306130"\s*\{/) { if (/"306130"\s*\{[^}]*"LaunchOptions"\s*"[^"]*"/) { s/("306130"\s*\{[^}]*)"LaunchOptions"\s*"[^"]*"/$1"LaunchOptions"\t\t"$ls"/s; } else { s/("306130"\s*\{)/$1\n\t\t\t\t"LaunchOptions"\t\t"$ls"/s; } } else { s/("apps"\s*\{)/$1\n\t\t\t"306130"\n\t\t\t{\n\t\t\t\t"LaunchOptions"\t\t"$ls"\n\t\t\t}/s; }' "$conf" 2>/dev/null
                echo -e "\e[0;32m[+] Successfully injected Launch Options into Steam!\e[0m"
                log_event "INFO" "Injected launch options into Steam config."
            fi
        done
        
        echo -e "\e[0;33m[!] Restarting Steam...\e[0m"
        if [ "$OS_TYPE" = "Darwin" ]; then
            open -a Steam
        else
            if [[ "$STEAM_CMD" == *"flatpak"* ]]; then
                nohup flatpak run com.valvesoftware.Steam </dev/null >/dev/null 2>&1 &
            else
                nohup steam </dev/null >/dev/null 2>&1 &
            fi
        fi
    fi
    
    if ! read -p "Press Enter to start the updater now..."; then
        echo -e "\nUser Closed The Terminal. Exiting safely."
        exit 0
    fi
    SILENT=false
}

awk_time_formatter='
{
    while (match($0, /\[TS:([0-9]+)\]/)) {
        ts = substr($0, RSTART+4, RLENGTH-5) + 0
        diff = now - ts
        if (diff < 0) diff = 0
        if (diff < 60) { rel = diff (diff == 1 ? " second ago" : " seconds ago") }
        else if (diff < 3600) { v = int(diff/60); rel = v (v==1 ? " minute ago" : " minutes ago") }
        else if (diff < 86400) { v = int(diff/3600); rel = v (v==1 ? " hour ago" : " hours ago") }
        else { v = int(diff/86400); rel = v (v==1 ? " day ago" : " days ago") }
        
        pre = substr($0, 1, RSTART-1)
        post = substr($0, RSTART+RLENGTH)
        $0 = pre "[\033[90m" rel "\033[0m]" post
    }
    print $0
}'

print_dynamic_log() {
    local file="$1"
    if [ -s "$file" ]; then
        awk -v now="$(date +%s)" "$awk_time_formatter" "$file"
    fi
}

ui_echo() {
    if [ "$SILENT" = false ]; then
        echo -e "$1" | awk -v now="$(date +%s)" "$awk_time_formatter"
        echo -e "$1" >> "$UI_STATE_FILE"
    fi
}

master_kiosk_logic='
# TTC Kiosk Location IDs
k_dict["0"] = "Belkarth"
k_dict["1"] = "Belkarth Outlaws Refuge"
k_dict["2"] = "The Hollow City"
k_dict["3"] = "Haj Uxith"
k_dict["4"] = "Court of Contempt"
k_dict["5"] = "Rawl\047kha"
k_dict["6"] = "Rawl\047kha Outlaws Refuge"
k_dict["7"] = "Vinedusk"
k_dict["8"] = "Dune"
k_dict["9"] = "Baandari Trading Post"
k_dict["10"] = "Dra\047bul"
k_dict["11"] = "Valeguard"
k_dict["12"] = "Velyn Harbor Outlaws Refuge"
k_dict["13"] = "Marbruk"
k_dict["14"] = "Marbruk Outlaws Refuge"
k_dict["15"] = "Verrant Morass"
k_dict["16"] = "Greenheart"
k_dict["17"] = "Elden Root"
k_dict["18"] = "Elden Root Outlaws Refuge"
k_dict["19"] = "Cormount"
k_dict["20"] = "Southpoint"
k_dict["21"] = "Skywatch"
k_dict["22"] = "Firsthold"
k_dict["23"] = "Vulkhel Guard"
k_dict["24"] = "Vulkhel Guard Outlaws Refuge"
k_dict["25"] = "Mistral"
k_dict["26"] = "Evermore"
k_dict["27"] = "Evermore Outlaws Refuge"
k_dict["28"] = "Bangkorai Pass"
k_dict["29"] = "Hallin\047s Stand"
k_dict["30"] = "Sentinel"
k_dict["31"] = "Sentinel Outlaws Refuge"
k_dict["32"] = "Morwha\047s Bounty"
k_dict["33"] = "Bergama"
k_dict["34"] = "Shornhelm"
k_dict["35"] = "Shornhelm Outlaws Refuge"
k_dict["36"] = "Hoarfrost Downs"
k_dict["37"] = "Oldgate"
k_dict["38"] = "Wayrest"
k_dict["39"] = "Wayrest Outlaws Refuge"
k_dict["40"] = "Firebrand Keep"
k_dict["41"] = "Koeglin Village"
k_dict["42"] = "Daggerfall"
k_dict["43"] = "Daggerfall Outlaws Refuge"
k_dict["44"] = "Lion Guard Redoubt"
k_dict["45"] = "Wyrd Tree"
k_dict["46"] = "Stonetooth"
k_dict["47"] = "Port Hunding"
k_dict["48"] = "Riften"
k_dict["49"] = "Riften Outlaws Refuge"
k_dict["50"] = "Nimalten"
k_dict["51"] = "Fallowstone Hall"
k_dict["52"] = "Windhelm"
k_dict["53"] = "Windhelm Outlaws Refuge"
k_dict["54"] = "Voljar Meadery"
k_dict["55"] = "Fort Amol"
k_dict["56"] = "Stormhold"
k_dict["57"] = "Stormhold Outlaws Refuge"
k_dict["58"] = "Venomous Fens"
k_dict["59"] = "Hissmir"
k_dict["60"] = "Mournhold"
k_dict["61"] = "Mournhold Outlaws Refuge"
k_dict["62"] = "Tal\047Deic Grounds"
k_dict["63"] = "Muth Gnaar Hills"
k_dict["64"] = "Ebonheart"
k_dict["65"] = "Kragenmoor"
k_dict["66"] = "Davon\047s Watch"
k_dict["67"] = "Davon\047s Watch Outlaws Refuge"
k_dict["68"] = "Dhalmora"
k_dict["69"] = "Bleakrock"
k_dict["70"] = "Orsinium"
k_dict["71"] = "Orsinium Outlaws Refuge"
k_dict["72"] = "Morkul Stronghold"
k_dict["73"] = "Thieves Den"
k_dict["74"] = "Abah\047s Landing"
k_dict["75"] = "Anvil"
k_dict["76"] = "Kvatch"
k_dict["77"] = "Anvil Outlaws Refuge"
k_dict["78"] = "Vive City"
k_dict["79"] = "Vive City Outlaws Refuge"
k_dict["80"] = "Sadrith Mora"
k_dict["81"] = "Balmora"
k_dict["82"] = "Brass Fortress"
k_dict["83"] = "Brass Fortress Outlaws Refuge"
k_dict["84"] = "Lillandril"
k_dict["85"] = "Shimmerene"
k_dict["86"] = "Alinor"
k_dict["87"] = "Alinor Outlaws Refuge"
k_dict["88"] = "Lilmoth"
k_dict["89"] = "Lilmoth Outlaws Refuge"
k_dict["90"] = "Rimmen"
k_dict["91"] = "Rimmen Outlaws Refuge"
k_dict["92"] = "Senchal"
k_dict["93"] = "Senchal Outlaws Refuge"
k_dict["94"] = "Solitude"
k_dict["95"] = "Solitude Outlaws Refuge"
k_dict["96"] = "Markarth"
k_dict["97"] = "Markarth Outlaws Refuge"
k_dict["98"] = "Leyawiin"
k_dict["99"] = "Leyawiin Outlaws Refuge"
k_dict["100"] = "Fargrave"
k_dict["101"] = "Fargrave Outlaws Refuge"
k_dict["102"] = "Gonfalon Bay"
k_dict["103"] = "Gonfalon Bay Outlaws Refuge"
k_dict["104"] = "Vastyr"
k_dict["105"] = "Vastyr Outlaws Refuge"
k_dict["106"] = "Necrom"
k_dict["107"] = "Necrom Outlaws Refuge"
k_dict["108"] = "Skingrad"
k_dict["109"] = "Skingrad Outlaws Refuge"
k_dict["110"] = "Sunport"
k_dict["111"] = "Sunport Outlaws Refuge"

# ESO-HUB Trader Names & Map Locations
k_dict["Lejesha"] = "Bergama Wayshrine - Alik\047r Desert|104"
k_dict["Manidah"] = "Morwha\047s Bounty Wayshrine - Alik\047r Desert|104"
k_dict["Laknar"] = "Sentinel - Alik\047r Desert|104"
k_dict["Saymimah"] = "Sentinel - Alik\047r Desert|104"
k_dict["Uurwaerion"] = "Sentinel - Alik\047r Desert|104"
k_dict["Vinder Hlaran"] = "Sentinel - Alik\047r Desert|104"
k_dict["Yat"] = "Sentinel - Alik\047r Desert|104"
k_dict["Panersewen"] = "Firsthold Wayshrine - Auridon|381"
k_dict["Cerweriell"] = "Skywatch - Auridon|545"
k_dict["Ferzhela"] = "Skywatch - Auridon|545"
k_dict["Guzg"] = "Skywatch - Auridon|545"
k_dict["Lanirsare"] = "Skywatch - Auridon|545"
k_dict["Renzaiq"] = "Skywatch - Auridon|545"
k_dict["Carillda"] = "Vulkhel Guard - Auridon|381"
k_dict["Galam Seleth"] = "Dhalmora - Bal Foyen|281"
k_dict["Malirzzaka"] = "Bangkorai Pass Wayshrine - Bangkorai|92"
k_dict["Arver Falos"] = "Evermore - Bangkorai|92"
k_dict["Tilinarie"] = "Evermore - Bangkorai|92"
k_dict["Values-Many-Things"] = "Evermore - Bangkorai|92"
k_dict["Kaale"] = "Evermore - Bangkorai|92"
k_dict["Zunlog"] = "Evermore - Bangkorai|92"
k_dict["Glorgzorgo"] = "Hallin\047s Stand - Bangkorai|92"
k_dict["Ghatrugh"] = "Stonetooth Fortress - Betnikh|539"
k_dict["Amirudda"] = "Leyawiin - Blackwood|1963"
k_dict["Dandras Omayn"] = "Leyawiin - Blackwood|1963"
k_dict["Lhotahir"] = "Leyawiin - Blackwood|1963"
k_dict["Sihrimaya"] = "Leyawiin - Blackwood|1963"
k_dict["Shuruthikh"] = "Leyawiin - Blackwood|1963"
k_dict["Praxedes Vestalis"] = "Leyawiin - Blackwood|1963"
k_dict["Inishez"] = "Bleakrock Wayshrine - Bleakrock Isle|280"
k_dict["Commerce Delegate"] = "Brass Fortress - Clockwork City|1643"
k_dict["Ravam Sedas"] = "Brass Fortress - Clockwork City|1643"
k_dict["Orstag"] = "Brass Fortress - Clockwork City|1643"
k_dict["Noveni Adrano"] = "Brass Fortress - Clockwork City|1643"
k_dict["Valowende"] = "Brass Fortress - Clockwork City|1643"
k_dict["Shogarz"] = "Brass Fortress - Clockwork City|1643"
k_dict["Harzdak"] = "Court of Contempt Wayshrine - Coldharbour|345"
k_dict["Shuliish"] = "Haj Uxith Wayshrine - Coldharbour|255"
k_dict["Nistyniel"] = "The Hollow City - Coldharbour|345"
k_dict["Ramzasa"] = "The Hollow City - Coldharbour|345"
k_dict["Balver Sarvani"] = "The Hollow City - Coldharbour|345"
k_dict["Virwillaure"] = "The Hollow City - Coldharbour|345"
k_dict["Donnaelain"] = "Belkarth - Craglorn|888"
k_dict["Glegokh"] = "Belkarth - Craglorn|888"
k_dict["Shelzaka"] = "Belkarth - Craglorn|888"
k_dict["Keen-Eyes"] = "Belkarth - Craglorn|888"
k_dict["Shuhasa"] = "Belkarth - Craglorn|888"
k_dict["Nelvon Galen"] = "Belkarth - Craglorn|888"
k_dict["Mengilwaen"] = "Belkarth - Craglorn|888"
k_dict["Endoriell"] = "Mournhold - Deshaan|57"
k_dict["Through-Gilded-Eyes"] = "Mournhold - Deshaan|57"
k_dict["Zarum"] = "Mournhold - Deshaan|57"
k_dict["Gals Fendyn"] = "Mournhold - Deshaan|57"
k_dict["Razgugul"] = "Mournhold - Deshaan|57"
k_dict["Hayaia"] = "Mournhold - Deshaan|57"
k_dict["Erwurlde"] = "Mournhold - Deshaan|57"
k_dict["Feran Relenim"] = "Muth Gnaar Hills Wayshrine - Deshaan|57"
k_dict["Telvon Arobar"] = "Tal\047Deic Grounds Wayshrine - Deshaan|57"
k_dict["Muslabliz"] = "Fort Amol - Eastmarch|101"
k_dict["Alareth"] = "Voljar Meadery Wayshrine - Eastmarch|101"
k_dict["Alisewen"] = "Windhelm - Eastmarch|101"
k_dict["Celorien"] = "Windhelm - Eastmarch|101"
k_dict["Dosa"] = "Windhelm - Eastmarch|101"
k_dict["Deras Golathyn"] = "Windhelm - Eastmarch|101"
k_dict["Ghogurz"] = "Windhelm - Eastmarch|101"
k_dict["Bodsa Manas"] = "The Bazaar - Fargrave|2058"
k_dict["Furnvekh"] = "The Bazaar - Fargrave|2058"
k_dict["Livia Tappo"] = "The Bazaar - Fargrave|2058"
k_dict["Ven"] = "The Bazaar - Fargrave|2058"
k_dict["Vesakta"] = "The Bazaar - Fargrave|2058"
k_dict["Zenelaz"] = "The Bazaar - Fargrave|2058"
k_dict["Arzalaya"] = "Vastyr - Galen|2275"
k_dict["Sharflekh"] = "Vastyr - Galen|2275"
k_dict["Gei"] = "Vastyr - Galen|2275"
k_dict["Stephenn Surilie"] = "Vastyr - Galen|2275"
k_dict["Tildinfanya"] = "Vastyr - Galen|2275"
k_dict["Var the Vague"] = "Vastyr - Galen|2275"
k_dict["Sintilfalion"] = "Daggerfall - Glenumbra|97"
k_dict["Murgoz"] = "Daggerfall - Glenumbra|97"
k_dict["Khalatah"] = "Daggerfall - Glenumbra|97"
k_dict["Faedre"] = "Daggerfall - Glenumbra|97"
k_dict["Brara Hlaalo"] = "Daggerfall - Glenumbra|97"
k_dict["Nameel"] = "Lion Guard Redoubt Wayshrine - Glenumbra|97"
k_dict["Mogazgur"] = "Wyrd Tree Wayshrine - Glenumbra|97"
k_dict["Daynas Sadrano"] = "Anvil - Gold Coast|1403"
k_dict["Majhasur"] = "Anvil - Gold Coast|1403"
k_dict["Onurai-Maht"] = "Anvil - Gold Coast|1403"
k_dict["Erluramar"] = "Kvatch - Gold Coast|1403"
k_dict["Farul"] = "Kvatch - Gold Coast|1403"
k_dict["Zagh gro-Stugh"] = "Kvatch - Gold Coast|1403"
k_dict["Nirywy"] = "Cormount Wayshrine - Grahtwood|383"
k_dict["Fintilorwe"] = "Elden Root - Grahtwood|383"
k_dict["Walks-In-Leaves"] = "Elden Root - Grahtwood|383"
k_dict["Mizul"] = "Elden Root - Grahtwood|383"
k_dict["Iannianith"] = "Elden Root - Grahtwood|383"
k_dict["Bols Thirandus"] = "Elden Root - Grahtwood|383"
k_dict["Goh"] = "Elden Root - Grahtwood|383"
k_dict["Naifineh"] = "Elden Root - Grahtwood|383"
k_dict["Glothozug"] = "Southpoint Wayshrine - Grahtwood|383"
k_dict["Halash"] = "Greenheart Wayshrine - Greenshade|108"
k_dict["Camyaale"] = "Marbruk - Greenshade|108"
k_dict["Fendros Faryon"] = "Marbruk - Greenshade|108"
k_dict["Ghobargh"] = "Marbruk - Greenshade|108"
k_dict["Goudadul"] = "Marbruk - Greenshade|108"
k_dict["Hasiwen"] = "Marbruk - Greenshade|108"
k_dict["Seeks-Better-Deals"] = "Verrant Morass Wayshrine - Greenshade|108"
k_dict["Farvyn Rethan"] = "Abah\047s Landing - Hew\047s Bane|1353"
k_dict["Gathewen"] = "Abah\047s Landing - Hew\047s Bane|1353"
k_dict["Qanliz"] = "Abah\047s Landing - Hew\047s Bane|1353"
k_dict["Shiny-Trades"] = "Abah\047s Landing - Hew\047s Bane|1353"
k_dict["Snegbug"] = "Abah\047s Landing - Hew\047s Bane|1353"
k_dict["Dahnadreel"] = "Thieves Den - Hew\047s Bane|1353"
k_dict["Innryk"] = "Gonfalon Bay - High Isle|2235"
k_dict["Kemshelar"] = "Gonfalon Bay - High Isle|2235"
k_dict["Marcelle Fanis"] = "Gonfalon Bay - High Isle|2235"
k_dict["Pugereau Laffoon"] = "Gonfalon Bay - High Isle|2235"
k_dict["Shakhrath"] = "Gonfalon Bay - High Isle|2235"
k_dict["Zoe Frernile"] = "Gonfalon Bay - High Isle|2235"
k_dict["Janne Jonnicent"] = "Gonfalon Bay Outlaws Refuge - High Isle|2235"
k_dict["Dulia"] = "Mistral - Khenarthi\047s Roost|534"
k_dict["Shamuniz"] = "Mistral - Khenarthi\047s Roost|534"
k_dict["Mani"] = "Baandari Trading Post - Malabal Tor|58"
k_dict["Murgrud"] = "Baandari Trading Post - Malabal Tor|58"
k_dict["Jalaima"] = "Baandari Trading Post - Malabal Tor|58"
k_dict["Nindenel"] = "Baandari Trading Post - Malabal Tor|58"
k_dict["Teromawen"] = "Baandari Trading Post - Malabal Tor|58"
k_dict["Ulyn Marys"] = "Dra\047bul Wayshrine - Malabal Tor|22"
k_dict["Kharg"] = "Valeguard Wayshrine - Malabal Tor|58"
k_dict["Aki-Osheeja"] = "Lilmoth - Murkmire|1533"
k_dict["Faelemar"] = "Lilmoth - Murkmire|1533"
k_dict["Ordasha"] = "Lilmoth - Murkmire|1533"
k_dict["Xokomar"] = "Lilmoth - Murkmire|1533"
k_dict["Mahadal at-Bergama"] = "Lilmoth - Murkmire|1533"
k_dict["Thaloril"] = "Lilmoth - Murkmire|1533"
k_dict["Maelanrith"] = "Rimmen - Northern Elsweyr|1576"
k_dict["Artura Pamarc"] = "Rimmen - Northern Elsweyr|1576"
k_dict["Razzamin"] = "Rimmen - Northern Elsweyr|1576"
k_dict["Nirshala"] = "Rimmen - Northern Elsweyr|1576"
k_dict["Adiblargo"] = "Rimmen - Northern Elsweyr|1576"
k_dict["Fortis Asina"] = "Rimmen - Northern Elsweyr|1576"
k_dict["Uzarrur"] = "Dune - Reaper\047s March|382"
k_dict["Muheh"] = "Rawl\047kha - Reaper\047s March|382"
k_dict["Shiniraer"] = "Rawl\047kha - Reaper\047s March|382"
k_dict["Heat-On-Scales"] = "Rawl\047kha - Reaper\047s March|382"
k_dict["Canda"] = "Rawl\047kha - Reaper\047s March|382"
k_dict["Ronuril"] = "Rawl\047kha - Reaper\047s March|382"
k_dict["Ambarys Teran"] = "Vinedusk Wayshrine - Reaper\047s March|382"
k_dict["Aldam Urvyn"] = "Hoarfrost Downs - Rivenspire|19"
k_dict["Fanwyearie"] = "Oldgate Wayshrine - Rivenspire|19"
k_dict["Frenidela"] = "Shornhelm - Rivenspire|19"
k_dict["Roudi"] = "Shornhelm - Rivenspire|19"
k_dict["Shakh"] = "Shornhelm - Rivenspire|19"
k_dict["Tendir Vlaren"] = "Shornhelm - Rivenspire|19"
k_dict["Vorh"] = "Shornhelm - Rivenspire|19"
k_dict["Talen-Dum"] = "Hissmir Wayshrine - Shadowfen|117"
k_dict["Emuin"] = "Stormhold - Shadowfen|117"
k_dict["Gasheg"] = "Stormhold - Shadowfen|117"
k_dict["Tar-Shehs"] = "Stormhold - Shadowfen|117"
k_dict["Vals Salvani"] = "Stormhold - Shadowfen|117"
k_dict["Zino"] = "Stormhold - Shadowfen|117"
k_dict["Junal-Nakal"] = "Venomous Fens Wayshrine - Shadowfen|117"
k_dict["Florentina Verus"] = "Solitude - Western Skyrim|1765"
k_dict["Gilur Vules"] = "Solitude - Western Skyrim|1765"
k_dict["Grobert Agnan"] = "Solitude - Western Skyrim|1765"
k_dict["Mandyl"] = "Solitude - Western Skyrim|1765"
k_dict["Ohanath"] = "Solitude - Western Skyrim|1765"
k_dict["Tuhdri"] = "Solitude - Western Skyrim|1765"
k_dict["Fanyehna"] = "Solitude Outlaws Refuge - Western Skyrim|1765"
k_dict["Glaetaldo"] = "Senchal - Southern Elsweyr|1693"
k_dict["Golgakul"] = "Senchal - Southern Elsweyr|1693"
k_dict["Jafinna"] = "Senchal - Southern Elsweyr|1693"
k_dict["Maguzak"] = "Senchal - Southern Elsweyr|1693"
k_dict["Saden Sarvani"] = "Senchal - Southern Elsweyr|1693"
k_dict["Wusava"] = "Senchal - Southern Elsweyr|1693"
k_dict["Tanur Llervu"] = "Davon\047s Watch - Stonefalls|41"
k_dict["Silver-Scales"] = "Ebonheart - Stonefalls|41"
k_dict["Gananith"] = "Ebonheart - Stonefalls|41"
k_dict["Luz"] = "Ebonheart - Stonefalls|41"
k_dict["J\047zaraer"] = "Ebonheart - Stonefalls|41"
k_dict["Urvel Hlaren"] = "Ebonheart - Stonefalls|41"
k_dict["Ma\047jidid"] = "Kragenmoor - Stonefalls|41"
k_dict["Dromash"] = "Firebrand Keep Wayshrine - Stormhaven|19"
k_dict["Aniama"] = "Koeglin Village - Stormhaven|19"
k_dict["Azarati"] = "Wayrest - Stormhaven|19"
k_dict["Morg"] = "Wayrest - Stormhaven|19"
k_dict["Atin"] = "Wayrest - Stormhaven|19"
k_dict["Tredyn Daram"] = "Wayrest - Stormhaven|19"
k_dict["Estilldo"] = "Wayrest - Stormhaven|19"
k_dict["Aerchith"] = "Wayrest - Stormhaven|19"
k_dict["Ah-Zish"] = "Wayrest - Stormhaven|19"
k_dict["Makmargo"] = "Port Hunding - Stros M\047Kai|535"
k_dict["Talwullaure"] = "Alinor - Summerset|1455"
k_dict["Irna Dren"] = "Alinor - Summerset|1455"
k_dict["Rubyn Denile"] = "Alinor - Summerset|1455"
k_dict["Yggurz Strongbow"] = "Alinor - Summerset|1455"
k_dict["Huzzin"] = "Alinor - Summerset|1455"
k_dict["Rialilrin"] = "Alinor - Summerset|1455"
k_dict["Ambalor"] = "Lillandril - Summerset|1455"
k_dict["Nowajan"] = "Lillandril - Summerset|1455"
k_dict["Quelilmor"] = "Shimmerene - Summerset|1455"
k_dict["Shargalash"] = "Shimmerene - Summerset|1455"
k_dict["Varandia"] = "Shimmerene - Summerset|1455"
k_dict["Rinedel"] = "Lillandril - Summerset|1455"
k_dict["Grudogg"] = "Necrom - Telvanni Peninsula|2394"
k_dict["Tuls Madryon"] = "Necrom - Telvanni Peninsula|2394"
k_dict["Alvura Thenim"] = "Necrom - Telvanni Peninsula|2394"
k_dict["Falani"] = "Necrom - Telvanni Peninsula|2394"
k_dict["Runethyne Brenur"] = "Necrom - Telvanni Peninsula|2394"
k_dict["Wyn Serpe"] = "Necrom - Telvanni Peninsula|2394"
k_dict["Thredis"] = "Necrom Outlaws Refuge - Telvanni Peninsula|2394"
k_dict["Dion Hassildor"] = "Leyawiin Outlaws Refuge - Blackwood|1963"
k_dict["Nardhil Barys"] = "Slag Town Outlaws Refuge - Clockwork City|1643"
k_dict["Tuxutl"] = "Fargrave Outlaws Refuge - Fargrave|2058"
k_dict["Virwen"] = "Abah\047s Landing - Hew\047s Bane|1353"
k_dict["Begok"] = "Rimmen Outlaws Refuge - Northern Elsweyr|1664"
k_dict["Laytiva Sendris"] = "Senchal Outlaws Refuge - Southern Elsweyr|1693"
k_dict["Bodfira"] = "Markarth - The Reach|1855"
k_dict["Atazha"] = "Vivec City - Vvardenfell|1287"
k_dict["Jena Calvus"] = "Vivec City - Vvardenfell|1287"
k_dict["Lorthodaer"] = "Vivec City - Vvardenfell|1287"
k_dict["Mauhoth"] = "Vivec City - Vvardenfell|1287"
k_dict["Rinami"] = "Vivec City - Vvardenfell|1287"
k_dict["Sebastian Brutya"] = "Vivec City - Vvardenfell|1287"
k_dict["Relieves-Burdens"] = "Vivec City Outlaws Refuge - Vvardenfell|1287"
k_dict["Narril"] = "Balmora - Vvardenfell|1290"
k_dict["Ruxultav"] = "Sadrith Mora - Vvardenfell|1288"
k_dict["Felayn Uvaram"] = "Sadrith Mora - Vvardenfell|1288"
k_dict["Eralian"] = "Riften - The Rift|103"
k_dict["Arnyeana"] = "Riften - The Rift|103"
k_dict["Jeelus-Lei"] = "Riften - The Rift|103"
k_dict["Llether Nilem"] = "Riften - The Rift|103"
k_dict["Atheval"] = "Nimalten - The Rift|103"
k_dict["Borgrara"] = "Morkul Stronghold - Wrothgar|684"
k_dict["Henriette Panoit"] = "Morkul Stronghold - Wrothgar|684"
k_dict["Nagrul gro-Stugbaz"] = "Morkul Stronghold - Wrothgar|684"
k_dict["Oorgurn"] = "Morkul Stronghold - Wrothgar|684"
k_dict["Jee-Ma"] = "Orsinium - Wrothgar|684"
k_dict["Terorne"] = "Orsinium - Wrothgar|684"
k_dict["Narkhukulg"] = "Orsinium Outlaws Refuge - Wrothgar|684"
k_dict["Adzi-Dool"] = "Skingrad - West Weald|2542"
k_dict["Catro Catius"] = "Skingrad - West Weald|2542"
k_dict["Curinwe"] = "Skingrad - West Weald|2542"
k_dict["Ildare Berel"] = "Skingrad - West Weald|2542"
k_dict["Lucius Lento"] = "Skingrad - West Weald|2542"
k_dict["Otho Tatius"] = "Skingrad - West Weald|2542"

# Merge TTC Kiosk IDs with ESO-Hub Map Strings
for (k in k_dict) {
    if (k ~ /^[0-9]+$/) {
        ttc_name = k_dict[k]
        for (t in k_dict) {
            if (t !~ /^[0-9]+$/) {
                if (index(k_dict[t], ttc_name " - ") == 1 || index(k_dict[t], ttc_name " Wayshrine") == 1 || k_dict[t] == ttc_name) {
                    k_dict[k] = k_dict[t]
                    break
                }
            }
        }
    }
}
'

browse_database() {
    clear
    echo -e "\n\033[92m===========================================================================\033[0m"
    echo -e "\033[1m\033[94m                         TTC & ESO-Hub Database Browser\033[0m"
    echo -e "\033[97m                 (Data automatically retained for the last 90 days)\033[0m"
    echo -e "\033[92m===========================================================================\033[0m\n"
    
    if [ ! -f "$DB_DIR/LTTC_History.db" ]; then
        echo -e "\033[31m[!] No history database found. Wait for the script to extract data first.\033[0m\n"
        echo -e "\033[31m[!] (or go visit a guild store in-game and press scan then /reloadui)\033[0m\n"
        echo -ne "\033[33mPress Enter to return...\033[0m "
        read dummy_var
        return
    fi

    while true; do
        echo -e "\n\033[33mSelect a Database Function:\033[0m"
        echo -e " 1) View / Search Database (Paginated & Sorted)"
        echo -e " 2) Top 10 Most Selling Items (By Volume)"
        echo -e " 3) Top 10 Highest Grossing Items (By Total Gold)"
        echo -e " 4) Suggested Price Calculator (Outlier Elimination)"
        echo -e " 5) View Previous Extraction History (Paginated & Sorted)"
        echo -e " 6) Exit Browser & Resume Updater"
        echo -ne "\033[33mChoice [1-8]:\033[0m "
        read b_opt
        
        case $b_opt in
            1)
                echo -ne "\033[33mEnter search term (leave empty for ALL data):\033[0m "
                read s_term
                
                echo -e "\n\033[33mSort By:\033[0m"
                echo " 1) Date (Newest First)"
                echo " 2) Date (Oldest First)"
                echo " 3) Price (Highest First)"
                echo " 4) Price (Lowest First)"
                echo " 5) Alphabetical (A-Z)"
                echo -ne "\033[33mChoice [1-5]:\033[0m "
                read sort_opt
                
                view_tmp="$TEMP_DIR_ROOT/lttc_search_view.tmp"
                sort_tmp="$TEMP_DIR_ROOT/lttc_search_sort.tmp"
                
                echo -e "\n\033[36mProcessing data...\033[0m"
                
                # Filter by search term
                awk -F'|' -v term="$(echo "$s_term" | awk '{print tolower($0)}')" '
                BEGIN { '"$master_kiosk_logic"' }
                $1 == "HISTORY" {
                    kiosk = $11
                    name = $7
                    guild = $10
                    
                    # Hide Unknown Data
                    if (name ~ /^Unknown Item/ || guild == "Unknown Guild" || guild == "Guilds" || guild == "") {
                        next
                    }
                    
                    if (kiosk != "" && kiosk != "0" && k_dict[kiosk] != "") {
                        split(k_dict[kiosk], kp, "|")
                        kiosk = kp[1]
                    }
                    search_str = tolower($0 "|" kiosk)
                    if (term == "" || index(search_str, term) > 0) {
                        print $0
                    }
                }' "$DB_DIR/LTTC_History.db" > "$view_tmp"
                
                if [ ! -s "$view_tmp" ]; then
                    echo -e " \033[31m[-] No results found.\033[0m\n"
                    echo -ne "\033[33mPress Enter to return...\033[0m "
                    read dummy_var
                    continue
                fi
                
                # Apply Sorting
                case "$sort_opt" in
                    1) sort -t'|' -k2,2nr "$view_tmp" > "$sort_tmp" ;;
                    2) sort -t'|' -k2,2n "$view_tmp" > "$sort_tmp" ;;
                    3) sort -t'|' -k4,4nr "$view_tmp" > "$sort_tmp" ;;
                    4) sort -t'|' -k4,4n "$view_tmp" > "$sort_tmp" ;;
                    5) sort -t'|' -k7,7f "$view_tmp" > "$sort_tmp" ;;
                    *) sort -t'|' -k2,2nr "$view_tmp" > "$sort_tmp" ;;
                esac
                
                # Format UI lines
                awk -F'|' -v db_file="$DB_FILE" '
                BEGIN { 
                    '"$master_kiosk_logic"' 
                    while ((getline line < db_file) > 0) {
                        split(line, p, "|")
                        if (p[1] == "GUILD") db_guild_id[p[2]] = p[3]
                    }
                    close(db_file)
                }
                {
                    ts=$2; action=$3; price=$4; qty=$5; itemid=$6; name=$7; buyer=$8; seller=$9; guild=$10; kiosk=$11; color=$12; src=$13
                    
                    now_cmd = "date +%s"; now_cmd | getline now_ts; close(now_cmd)
                    if (ts == 0 || ts == "") { rel = "Active" } else {
                        diff = now_ts - ts; if (diff < 0) diff = 0
                        if (diff < 60) rel = diff "s ago"
                        else if (diff < 3600) rel = int(diff/60) "m ago"
                        else if (diff < 86400) rel = int(diff/3600) "h ago"
                        else rel = int(diff/86400) "d ago"
                    }
                    
                    action_col = "\033[36m"
                    if (action == "Sold") action_col = "\033[38;5;214m"
                    if (action == "Purchased") action_col = "\033[92m"
                    if (action == "Cancelled") action_col = "\033[31m"
                    
                    trade_str = ""
                    if (seller != "" && buyer != "") {
                        trade_str = " by \033[36m" seller "\033[0m to \033[36m" buyer "\033[0m"
                    } else if (seller != "") {
                        trade_str = " by \033[36m" seller "\033[0m"
                    } else if (buyer != "") {
                        trade_str = " to \033[36m" buyer "\033[0m"
                    }
                    
                    k_str = ""
                    if (kiosk != "" && kiosk != "0" && k_dict[kiosk] != "") {
                        split(k_dict[kiosk], kp, "|")
                        k_loc = kp[1]; k_map = kp[2]
                        if (k_map != "") k_str = " \033[90m(\033]8;;https://eso-hub.com/en/interactive-map?map=" k_map "\033\\" k_loc "\033]8;;\033\\)\033[0m"
                        else k_str = " \033[90m(" k_loc ")\033[0m"
                    } else if (kiosk != "" && kiosk != "0") {
                        k_str = " \033[90m(" kiosk ")\033[0m"
                    }
                    
                    g_str = ""
                    if (guild != "" && guild != "Unknown Guild" && guild != "Guilds") {
                        if (guild in db_guild_id) {
                            gid = db_guild_id[guild]; fake_url = "|H1:guild:" gid "|h" guild "|h"
                            g_str = " in \033[35m\033]8;;" fake_url "\033\\" guild "\033]8;;\033\\\033[0m"
                        } else {
                            g_str = " in \033[35m" guild "\033[0m"
                        }
                    }
                    
                    link_start = "\033]8;;https://eso-hub.com/en/trading/" itemid "\033\\"
                    if (src == "TTC") link_start = "\033]8;;https://us.tamrieltradecentre.com/pc/Trade/SearchResult?ItemID=" itemid "\033\\"
                    link_end = "\033]8;;\033\\"
                    
                    printf " [\033[90m%-9s\033[0m] %s%-7s\033[0m for \033[32m%s\033[33mg\033[0m - \033[32m%sx\033[0m %s%s%s\033[0m%s%s%s%s [\033[90m%s\033[0m]\n", rel, action_col, action, price, qty, link_start, color, name, link_end, trade_str, g_str, k_str, src
                }' "$sort_tmp" > "$view_tmp"
                
                # Display using less pager
                less -R -K -N -P "Page %d (Press SPACE to scroll down, 'q' to quit) " "$view_tmp"
                
                rm -f "$view_tmp" "$sort_tmp" 2>/dev/null
                ;;
            2)
                echo -e "\n\033[36m--- Top 10 Selling Items (By Volume) ---\033[0m"
                awk -F'|' '
                    $1=="HISTORY" && ($3=="Sold" || $3=="Purchased" || $3=="Listed") && $5 > 0 {
                    if (index($7, "Unknown Item (") == 1) next;
                        qty = ($5 > 0) ? $5 : 1
                        unit_p = $4 / qty
                        name = $7
                        prices[name, count[name]++] = unit_p
                        colors[name] = ($12 != "") ? $12 : "\033[0m"
                        if ($3=="Sold" || $3=="Purchased") vol[name] += qty
                    }
                    END {
                        for (name in vol) {
                            n = count[name]
                            if (n < 5) { sugg = 0 }
                            else {
                                for (i=0; i<n; i++) {
                                    for (j=i+1; j<n; j++) {
                                        if (prices[name, i] > prices[name, j]) {
                                            temp = prices[name, i]; prices[name, i] = prices[name, j]; prices[name, j] = temp
                                        }
                                    }
                                }
                                trim = int(n * 0.10)
                                if (trim == 0) trim = 1
                                valid_n = n - (2 * trim)
                                if (valid_n < 1) valid_n = 1
                                
                                mid_start = trim + int(valid_n * 0.45)
                                mid_end = trim + int(valid_n * 0.55)
                                if (mid_end < mid_start) mid_end = mid_start
                                
                                sum = 0; c = 0
                                for (i=mid_start; i<=mid_end; i++) { sum += prices[name, i]; c++ }
                                sugg = sum / c
                            }
                            print vol[name] "|" name "|" sugg "|" colors[name]
                        }
                    }' "$DB_DIR/LTTC_History.db" | sort -t'|' -k1,1nr | head -n 10 | awk -F'|' '{
                        if ($3 == 0) p_str = "Not enough data for avg"
                        else p_str = sprintf("%.2f", $3) "g"
                        print " \033[36m" $1 "x\033[0m sold - " $4 $2 "\033[0m (Avg: \033[33m" p_str "\033[0m)"
                    }'
                echo ""
                ;;
            3)
                echo -e "\n\033[36m--- Top 10 Highest Grossing Items (By Total Gold) ---\033[0m"
                awk -F'|' '
                    $1=="HISTORY" && ($3=="Sold" || $3=="Purchased" || $3=="Listed") && $5 > 0 {
                        if (index($7, "Unknown Item (") == 1) next;
                        qty = ($5 > 0) ? $5 : 1
                        unit_p = $4 / qty
                        name = $7
                        prices[name, count[name]++] = unit_p
                        colors[name] = ($12 != "") ? $12 : "\033[0m"
                        if ($3=="Sold" || $3=="Purchased") gold[name] += $4
                    }
                    END {
                        for (name in gold) {
                            n = count[name]
                            if (n < 5) { sugg = 0 }
                            else {
                                for (i=0; i<n; i++) {
                                    for (j=i+1; j<n; j++) {
                                        if (prices[name, i] > prices[name, j]) {
                                            temp = prices[name, i]; prices[name, i] = prices[name, j]; prices[name, j] = temp
                                        }
                                    }
                                }
                                trim = int(n * 0.10)
                                if (trim == 0) trim = 1
                                valid_n = n - (2 * trim)
                                if (valid_n < 1) valid_n = 1
                                
                                mid_start = trim + int(valid_n * 0.45)
                                mid_end = trim + int(valid_n * 0.55)
                                if (mid_end < mid_start) mid_end = mid_start
                                
                                sum = 0; c = 0
                                for (i=mid_start; i<=mid_end; i++) { sum += prices[name, i]; c++ }
                                sugg = sum / c
                            }
                            print gold[name] "|" name "|" sugg "|" colors[name]
                        }
                    }' "$DB_DIR/LTTC_History.db" | sort -t'|' -k1,1nr | head -n 10 | awk -F'|' '{
                        if ($3 == 0) p_str = "Not enough data for avg"
                        else p_str = sprintf("%.2f", $3) "g"
                        print " \033[33m" $1 "g\033[0m grossed - " $4 $2 "\033[0m (Avg: \033[33m" p_str "\033[0m)"
                    }'
                echo ""
                ;;
            4)
                echo -ne "\033[33mEnter exact or partial item name for price check:\033[0m "
                read p_term
                echo -e "\n\033[36m--- Suggested Price Check ---\033[0m"
                awk -F'|' -v term="$(echo "$p_term" | awk '{print tolower($0)}')" '
                    $1=="HISTORY" && tolower($7) ~ term && ($3=="Listed" || $3=="Sold" || $3=="Purchased") && $4 ~ /^[0-9]+(\.[0-9]+)?$/ && $5 > 0 {
                    if (index($7, "Unknown Item (") == 1) next;
                        qty = ($5 > 0) ? $5 : 1
                        unit_p = $4 / qty
                        prices[$7, count[$7]++] = unit_p
                        colors[$7] = ($12 != "") ? $12 : "\033[0m"
                    }
                    END {
                        for (item in count) {
                            split(item, parts, SUBSEP)
                            name = parts[1]
                            n = count[name]
                            if (n < 5) continue;
                            delete p_arr
                            for (i=0; i<n; i++) { p_arr[i] = prices[name, i] }
                            for (i=0; i<n; i++) {
                                for (j=i+1; j<n; j++) {
                                    if (p_arr[i] > p_arr[j]) { temp=p_arr[i]; p_arr[i]=p_arr[j]; p_arr[j]=temp }
                                }
                            }
                            trim = int(n * 0.10)
                            if (trim == 0) trim = 1
                            valid_n = n - (2 * trim)
                            if (valid_n < 1) valid_n = 1
                            
                            mid_start = trim + int(valid_n * 0.45)
                            mid_end = trim + int(valid_n * 0.55)
                            if (mid_end < mid_start) mid_end = mid_start
                            
                            sum = 0; c = 0
                            for (i=mid_start; i<=mid_end; i++) { sum += p_arr[i]; c++ }
                            sugg = sum / c
                            
                            print colors[name] name "\033[0m - Suggested Price: \033[33m" sprintf("%.2f", sugg) "g\033[0m (Based on " n " data points)"
                        }
                    }
                ' "$DB_DIR/LTTC_History.db"
                echo ""
                ;;
            5)
                echo -e "\n\033[36m--- View Previous Extraction History ---\033[0m"
                echo -ne "\033[33mSearch by Source [TTC or ESO-Hub] (leave empty for ALL data):\033[0m "
                read hist_source
                
                echo -e "\n\033[33mSort By:\033[0m"
                echo " 1) Date (Newest First)"
                echo " 2) Date (Oldest First)"
                echo " 3) Price (Highest First)"
                echo " 4) Price (Lowest First)"
                echo " 5) Alphabetical (A-Z)"
                echo -ne "\033[33mChoice [1-5]:\033[0m "
                read hist_sort
                
                view_tmp="$TEMP_DIR_ROOT/lttc_hist_view.tmp"
                sort_tmp="$TEMP_DIR_ROOT/lttc_hist_sort.tmp"
                
                awk -F'|' -v src="$hist_source" '
                BEGIN { src = tolower(src) }
                $1 == "HISTORY" {
                    item_src = tolower($13)
                    if (src == "" || index(item_src, src) > 0) {
                        print $0
                    }
                }' "$DB_DIR/LTTC_History.db" > "$view_tmp"
                
                if [ ! -s "$view_tmp" ]; then
                    echo -e " \033[31m[-] No history found for that source.\033[0m\n"
                    echo -ne "\033[33mPress Enter to return...\033[0m "
                    read dummy_var
                    continue
                fi
                
                # Apply Sorting
                case "$hist_sort" in
                    1) sort -t'|' -k2,2nr "$view_tmp" > "$sort_tmp" ;;
                    2) sort -t'|' -k2,2n "$view_tmp" > "$sort_tmp" ;;
                    3) sort -t'|' -k4,4nr "$view_tmp" > "$sort_tmp" ;;
                    4) sort -t'|' -k4,4n "$view_tmp" > "$sort_tmp" ;;
                    5) sort -t'|' -k7,7f "$view_tmp" > "$sort_tmp" ;;
                    *) sort -t'|' -k2,2nr "$view_tmp" > "$sort_tmp" ;;
                esac
                
                # Format UI lines
                awk -F'|' -v db_file="$DB_FILE" '
                BEGIN { 
                    '"$master_kiosk_logic"' 
                    while ((getline line < db_file) > 0) {
                        split(line, p, "|")
                        if (p[1] == "GUILD") db_guild_id[p[2]] = p[3]
                    }
                    close(db_file)
                }
                {
                    ts=$2; action=$3; price=$4; qty=$5; itemid=$6; name=$7; buyer=$8; seller=$9; guild=$10; kiosk=$11; color=$12; src=$13
                    
                    now_cmd = "date +%s"; now_cmd | getline now_ts; close(now_cmd)
                    if (ts == 0 || ts == "") { rel = "Active" } else {
                        diff = now_ts - ts; if (diff < 0) diff = 0
                        if (diff < 60) rel = diff "s ago"
                        else if (diff < 3600) rel = int(diff/60) "m ago"
                        else if (diff < 86400) rel = int(diff/3600) "h ago"
                        else rel = int(diff/86400) "d ago"
                    }
                    
                    action_col = "\033[36m"
                    if (action == "Sold") action_col = "\033[38;5;214m"
                    if (action == "Purchased") action_col = "\033[92m"
                    if (action == "Cancelled") action_col = "\033[31m"
                    
                    trade_str = ""
                    if (seller != "" && buyer != "") {
                        trade_str = " by \033[36m" seller "\033[0m to \033[36m" buyer "\033[0m"
                    } else if (seller != "") {
                        trade_str = " by \033[36m" seller "\033[0m"
                    } else if (buyer != "") {
                        trade_str = " to \033[36m" buyer "\033[0m"
                    }
                    
                    k_str = ""
                    if (kiosk != "" && kiosk != "0" && k_dict[kiosk] != "") {
                        split(k_dict[kiosk], kp, "|")
                        k_loc = kp[1]; k_map = kp[2]
                        if (k_map != "") k_str = " \033[90m(\033]8;;https://eso-hub.com/en/interactive-map?map=" k_map "\033\\" k_loc "\033]8;;\033\\)\033[0m"
                        else k_str = " \033[90m(" k_loc ")\033[0m"
                    } else if (kiosk != "" && kiosk != "0") {
                        k_str = " \033[90m(" kiosk ")\033[0m"
                    }
                    
                    g_str = ""
                    if (guild != "" && guild != "Unknown Guild" && guild != "Guilds") {
                        if (guild in db_guild_id) {
                            gid = db_guild_id[guild]; fake_url = "|H1:guild:" gid "|h" guild "|h"
                            g_str = " in \033[35m\033]8;;" fake_url "\033\\" guild "\033]8;;\033\\\033[0m"
                        } else {
                            g_str = " in \033[35m" guild "\033[0m"
                        }
                    }
                    
                    link_start = "\033]8;;https://eso-hub.com/en/trading/" itemid "\033\\"
                    if (src == "TTC") link_start = "\033]8;;https://us.tamrieltradecentre.com/pc/Trade/SearchResult?ItemID=" itemid "\033\\"
                    link_end = "\033]8;;\033\\"
                    
                    printf " [\033[90m%-9s\033[0m] %s%-7s\033[0m for \033[32m%s\033[33mg\033[0m - \033[32m%sx\033[0m %s%s%s\033[0m%s%s%s%s [\033[90m%s\033[0m]\n", rel, action_col, action, price, qty, link_start, color, name, link_end, trade_str, g_str, k_str, src
                }' "$sort_tmp" > "$view_tmp"
                
                # Display 50 items at a time
                less -R -K -N -P "Page %d (Press SPACE for next 50, 'q' to quit) " "$view_tmp"
                
                rm -f "$view_tmp" "$sort_tmp" 2>/dev/null
                ;;
            6)
                break
                ;;
            *)
                echo -e "\033[31mInvalid option.\033[0m"
                ;;
        esac
    done
    
    clear
    if [ "$SILENT" = false ]; then
        echo -ne "\033]0;$APP_TITLE - Created by @APHONIC\007"
        if [ -s "$UI_STATE_FILE" ]; then
            print_dynamic_log "$UI_STATE_FILE"
        fi
    fi
}

prune_history() {
    if [ -f "$DB_DIR/LTTC_History.db" ]; then
        local cutoff=$((CURRENT_TIME - 7776000))
        awk -F'|' -OFS='|' -v cutoff="$cutoff" -v db="$DB_FILE" '
        BEGIN {
            if (db != "") {
                while ((getline line < db) > 0) {
                    split(line, p, "|")
                    if (p[1] ~ /^[0-9]+$/) {
                        db_name[p[1]] = (length(p) >= 6) ? p[6] : p[3]
                        db_qual[p[1]] = p[2] + 0 # Store the corrected quality
                    }
                }
                close(db)
            }
        }
        $1=="HISTORY" && $2 >= cutoff {
            # Update the name if a better one was found in the database
            if ($6 in db_name && db_name[$6] != "" && db_name[$6] !~ /^Unknown Item/) {
                $7 = db_name[$6]
            }
            # Sync the ANSI color tag with the repaired database
            if ($6 in db_qual) {
                q_num = db_qual[$6]
                c = "\033[0m"
                if(q_num==0) c="\033[90m"; else if(q_num==1) c="\033[97m"; else if(q_num==2) c="\033[32m"
                else if(q_num==3) c="\033[36m"; else if(q_num==4) c="\033[35m"; else if(q_num==5) c="\033[33m"
                else if(q_num==6) c="\033[38;5;214m"
                $12 = c
            }
            print $0
        }' "$DB_DIR/LTTC_History.db" > "$TEMP_DIR_ROOT/LTTC_History.tmp" 2>/dev/null
        
        if [ -s "$TEMP_DIR_ROOT/LTTC_History.tmp" ]; then
            mv "$TEMP_DIR_ROOT/LTTC_History.tmp" "$DB_DIR/LTTC_History.db" 2>/dev/null
        fi
    fi
}

INSTALLED_SCRIPT="$TARGET_DIR/$SCRIPT_NAME"

if [ "$SETUP_COMPLETE" = "true" ] && [ "$HAS_ARGS" = false ]; then
    if [ -f "$INSTALLED_SCRIPT" ] && [ -f "$CONFIG_FILE" ]; then
        clear
        echo -e "\e[0;32m[+] Configuration found! Using saved settings.\e[0m"
        echo -e "\e[0;36m-> Press 'y' to re-run setup, or wait 5 seconds to continue automatically...\e[0m\n"
        read -t 5 -p "Setup done, do you want to re-run setup? (y/N): " rerun_setup
        if [[ "$rerun_setup" =~ ^[Yy]$ ]]; then run_setup
        else
            if [ "$CURRENT_DIR" != "$TARGET_DIR" ]; then cp "${BASH_SOURCE[0]}" "$TARGET_DIR/$SCRIPT_NAME" 2>/dev/null; fi
        fi
    else run_setup
    fi
elif [ "$SETUP_COMPLETE" != "true" ] && [ "$HAS_ARGS" = false ]; then run_setup
fi

if [ "$SILENT" = true ]; then exec >/dev/null 2>&1; fi
exec 3>&2

[ "$AUTO_SRV" == "1" ] && TTC_DOMAIN="us.tamrieltradecentre.com" || TTC_DOMAIN="eu.tamrieltradecentre.com"
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

check_addon_enabled() {
    local addon="$1"
    
    # If the physical folder is missing, instantly report it as disabled.
    if [ ! -d "$ADDON_DIR/$addon" ]; then
        echo "false"
        return
    fi
    
    # Detect if the user is on a Steamdeck
    local is_deck=false
    if [ "$OS_TYPE" = "Linux" ]; then
        if [ "$XDG_CURRENT_DESKTOP" = "gamescope" ] || pgrep -x "gamescope" > /dev/null || grep -qi "steamos" /etc/os-release 2>/dev/null; then
            is_deck=true
        fi
    fi

    # Ignore AddOnSettings.txt on a Steamdeck Just check if the addon is installed in the folder
    if [ "$is_deck" = true ]; then
        if [ -d "$ADDON_DIR/$addon" ]; then
            echo "true"
        else
            echo "false"
        fi
        return
    fi

    # Read AddOnSettings.txt on LINUX/MAC
    if [ -f "$ADDON_SETTINGS_FILE" ]; then
        if grep -qw "$addon" "$ADDON_SETTINGS_FILE"; then 
            echo "true"
        else 
            echo "false"
        fi
    else
        if [ -d "$ADDON_DIR/$addon" ]; then echo "true"; else echo "false"; fi
    fi
}

get_relative_time() {
    local ts=$1
    local now=$(date +%s)
    local diff=$((now - ts))
    
    if (( diff < 60 )); then
        (( diff == 1 )) && echo "1 second ago" || echo "$diff seconds ago"
    elif (( diff < 3600 )); then
        local m=$((diff / 60))
        (( m == 1 )) && echo "1 minute ago" || echo "$m minutes ago"
    elif (( diff < 86400 )); then
        local h=$((diff / 3600))
        (( h == 1 )) && echo "1 hour ago" || echo "$h hours ago"
    else
        local d=$((diff / 86400))
        (( d == 1 )) && echo "1 day ago" || echo "$d days ago"
    fi
}

format_date() {
    local ts="$1"
    if [ "$OS_TYPE" = "Darwin" ]; then
        date -r "$ts" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "Unknown Date"
    else
        date -d "@$ts" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "Unknown Date"
    fi
}

apply_db_updates() {
    local updates="$1"
    if [ -n "$updates" ]; then
        # extract the version header first
        local header=$(grep "^#DATABASE VERSION" "$DB_FILE" 2>/dev/null)
        
        echo "$updates" | awk -F'|' -v db="$DB_FILE" '
        BEGIN {
            while ((getline < db) > 0) {
                if ($1 == "GUILD") { lines["GUILD_"$2] = $0 }
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
                gname = $2; gid = $3
                lines["GUILD_"gname] = "GUILD|" gname "|" gid
            }
        }
        END {
            for (k in lines) { print lines[k] }
        }' > "$DB_FILE.tmp"
        
        # Sort only the raw data inside the temporary file
        sort -t'|' -k1,1 -k7,7 -k6,6 "$DB_FILE.tmp" -o "$DB_FILE.tmp" 2>/dev/null
        
        # Reconstruct the DB with the protected header safely at the top
        if [ -n "$header" ]; then
            echo "$header" > "$DB_FILE"
            cat "$DB_FILE.tmp" >> "$DB_FILE"
        else
            mv "$DB_FILE.tmp" "$DB_FILE"
        fi
        rm -f "$DB_FILE.tmp" 2>/dev/null
        
        log_event "INFO" "Database updated and sorted, preserving version header."
    fi
}

# Item Quality
master_color_logic='
function get_hq(q) {
    if(q==6)return "Mythic (Orange) 6"; if(q==5)return "Legendary (Gold) 5"; if(q==4)return "Epic (Purple) 4";
    if(q==3)return "Superior (Blue) 3"; if(q==2)return "Fine (Green) 2"; if(q==1)return "Normal (White) 1";
    return "Trash (Grey) 0"
}
function get_cat(n,i,s,v) {
    ln = tolower(n)
    if(ln~/motif/)return "Crafting Motif"; if(ln~/blueprint|praxis|design|pattern|formula|diagram|sketch/)return "Furniture Plan";
    if(ln~/style page|runebox/)return "Style/Collectible"; 
    if(ln~/tea blends of tamriel|tin of high isle taffy|assorted stolen shiny trinkets|lightly used fiddle|stuffed bear|grisly trophy|companion gift/)return "Companion Gift"; 
    if(v>1||s>=20)return "Equipment (Armor/Weapon)"; return "Materials/Misc"
}
function calc_quality(id, name, s, v) {
    ln = tolower(name)
    
    # 1. Mythics
    if(id~/^(165899|187648|171437|165910|175510|181971|181961|175402|184206|191067)$/) return 6
    
    # 2. Hardcoded Overrides (Mats/Collectibles/Gifts)
    if(ln~/citation|truly superb glyph|tempering alloy|dreugh wax|rosin|kuta|perfect roe|aetherial dust|chromium plating|style page:|runebox:|research scroll|psijic ambrosia|master .* writ|indoril inks:/) return 5
    if(ln~/unknown .* writ|welkynar binding|rekuta|grain solvent|mastic|elegant lining|zircon plating|potent nirncrux|fortified nirncrux|culanda lacquer|harvested soul fragment/) return 4
    if(ln~/tea blends of tamriel|twenty-year ruby port|assorted stolen shiny trinkets|lightly used fiddle|stuffed bear|grisly trophy|companion gift|tin of high isle taffy|angler\047s knife set|dried fish biscuits|beginner\047s bowfishing kit/) return 3
    if(ln~/survey report|dwarven oil|turpen|embroidery|iridium plating|treasure map|bervez juice|frost mirriam/) return 3
    if(ln~/hemming|honing stone|pitch|terne plating|soul gem/) return 2
    if(ln~/^(recipe|design|blueprint|pattern|praxis|formula|diagram|sketch):/) {
        if(s==6) return 5; if(s==5) return 4; if(s==4) return 3; if(s==3) return 2; return 1
    }

    # 3. ItemLink Mathematical SubType Decoding
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
    if(s == 366) return 6; if(s == 358) return 2; if(s == 360) return 3
    
    return 1
}
'

log_event "INFO" "Updater started. OS: $OS_BRAND. Version: $APP_VERSION"

target_time=0

# Sanitize data
sanitize_legacy_data() {
    local found_dirt=false
    for db in "$DB_FILE" "$DB_DIR/LTTC_History.db"; do
        if [ -f "$db" ] && grep -q "<title>" "$db"; then
            # Use -i.bak for macOS/Linux cross compatibility
            sed -i.bak -e 's/<title>UESP:ESO Item -- //g' -e 's/<title>ESO Item -- //g' -e 's/<\/title>//g' "$db" 2>/dev/null
            rm -f "${db}.bak" 2>/dev/null
            found_dirt=true
        fi
    done
    if [ "$found_dirt" = true ]; then
        log_event "INFO" "Sanitized legacy tags from databases."
        echo -e " \e[92m[+] Successfully cleaned legacy tags from databases.\e[0m"
    fi
}
sanitize_legacy_data

# Repair Database
auto_repair_database() {
    if [ ! -f "$DB_FILE" ]; then return; fi
    local tmp_db="$DB_FILE.repair"
    local missing_ids="$TEMP_DIR_ROOT/lttc_db_missing.tmp"
    local offline_dict="$TEMP_DIR_ROOT/offline_name_dict.tmp"
    
    # Check if we have missing items
    awk -F'|' '$1 ~ /^[0-9]+$/ && (length($0) >= 6 ? $6 : $3) ~ /^Unknown Item \(/ { print $1 }' "$DB_FILE" | tr -d '\r' > "$missing_ids"
    local missing_count=$(wc -l < "$missing_ids" 2>/dev/null)
    [ -z "$missing_count" ] && missing_count=0
    
    if (( missing_count > 0 )); then
        if [ "$SILENT" = false ]; then echo -e " \e[33m[!] Auto-Repair: Scanning local TTC data to resolve $missing_count items offline...\e[0m"; fi
        
        # Get Item Names directly from local TTC Item Links
        grep -oE '\|H[^:]*:item:[0-9]+[^|]*\|h[^|]+\|h' "$SAVED_VAR_DIR/TamrielTradeCentre.lua" 2>/dev/null | \
        awk -F'\\|h' '{
            split($1, parts, ":"); id = parts[3]; name = $2
            sub(/\^.*$/, "", name)
            if (id ~ /^[0-9]+$/ && name != "") print id "|" name
        }' | sort -u > "$offline_dict"
        
        # Apply Names & Colors to the Database instantly
        awk -F'|' -OFS='|' -v lookup="$offline_dict" '
        '"$master_color_logic"'
        BEGIN {
            while ((getline line < lookup) > 0) { split(line, p, "|"); names[p[1]] = p[2] }
            close(lookup)
        }
        {
            if ($1 ~ /^[0-9]+$/ && NF >= 6) {
                if ($6 ~ /^Unknown Item \(/ || $6 == "") {
                    if (names[$1] != "") {
                        $6 = names[$1]
                        real_qual = calc_quality($1, $6, $3+0, $4+0)
                        $2 = real_qual; $5 = get_hq(real_qual); $7 = get_cat($6, $1, $3+0, $4+0)
                    }
                }
            }
            print $0
        }' "$DB_FILE" > "$tmp_db" 2>/dev/null
        
        if [ -s "$tmp_db" ]; then 
            mv "$tmp_db" "$DB_FILE"
            if [ "$SILENT" = false ]; then echo -e " \e[92m[✓]\e[0m Offline Database repair complete!"; fi
        fi
    fi
    rm -f "$missing_ids" "$offline_dict" 2>/dev/null
}
        
auto_repair_database

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

    shuffled_uas=("${USER_AGENTS[@]}")
    for k in "${!shuffled_uas[@]}"; do
        j=$((RANDOM % ${#shuffled_uas[@]})); temp="${shuffled_uas[$k]}"; shuffled_uas[$k]="${shuffled_uas[$j]}"; shuffled_uas[$j]="$temp"
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

    # Prompt for missing addons outside of any background loops
    ensure_missing_addon "TamrielTradeCentre" "1245" "SKIP_DL_TTC"
    ensure_missing_addon "HarvestMap" "57" "SKIP_DL_HM"
    ensure_missing_addon "HarvestMapData" "3034" "SKIP_DL_HM"
    ensure_missing_addon "LibEsoHubPrices" "4095" "SKIP_DL_EH"
    
    # ESO-Hub Downloader
    if [ "$SKIP_DL_EH" != true ]; then
        if [ ! -d "$ADDON_DIR/EsoTradingHub" ] || [ ! -d "$ADDON_DIR/EsoHubScanner" ]; then
            ans="y"
        if [ ! -f "/etc/os-release" ] || ! grep -qi "steamos" "/etc/os-release"; then
            echo -ne "\n \e[33m[?] ESO-Hub Addons are missing. Do you want to download them? (y/N):\e[0m "
            read -r ans < /dev/tty
        fi
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            ui_echo " \e[36mDownloading ESO-Hub Addon...\e[0m"
            api_resp=$(curl -s -X POST -H "User-Agent: ESOHubClient/1.0.9" -d "user_token=&client_system=$SYS_ID&client_version=1.0.9&lang=en" "https://data.eso-hub.com/v1/api/get-addon-versions" 2>/dev/null)
            addon_lines=$(echo "$api_resp" | sed 's/{"folder_name"/\n{"folder_name"/g' | grep '"folder_name"')
            
            while read -r line; do
                # Strip out hidden characters (\r, \n, tabs, spaces)
                fname=$(echo "$line" | grep -oE '"folder_name":"[^"]+"' | cut -d'"' -f4 | tr -d '\r\n\t ')
                if [ "$fname" = "LibEsoHubPrices" ]; then continue; fi
                dl_url=$(echo "$line" | grep -oE '"file":"[^"]+"' | cut -d'"' -f4 | sed 's/\\//g' | tr -d '\r\n\t ')
                srv_ver=$(echo "$line" | grep -oE '"version":\{[^}]*\}' | grep -oE '"string":"[^"]+"' | cut -d'"' -f4 | tr -d '\r\n\t ')
                id_num=$(echo "$dl_url" | grep -oE '[0-9]+$')
                [ -z "$id_num" ] && id_num="0"
                
                if [ -n "$fname" ] && [ -n "$dl_url" ]; then
                    ui_echo " \e[36mDownloading $fname...\e[0m"
                    
                    # timeout in 30 seconds to prevent freezing
                    # </dev/null to prevent curl from stealing the while loop's stream
                    if curl -s -f -m 30 -L -A "ESOHubClient/1.0.9" -o "$TEMP_DIR_ROOT/${fname}.zip" --url "$dl_url" </dev/null; then
                        unzip -q -o "$TEMP_DIR_ROOT/${fname}.zip" -d "$ADDON_DIR/" > /dev/null 2>&1
                        rm -f "$TEMP_DIR_ROOT/${fname}.zip"
                        ui_echo " \e[92m[+] $fname installed successfully.\e[0m"
                        log_event "INFO" "ESO-Hub Addon initially downloaded & installed: $fname"
                        
                        # Save version so it skips redownloading
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
                        ui_echo " \e[31m[-] Download failed for $fname (Timeout or Blocked).\e[0m"
                        log_event "ERROR" "Initial download failed for ESO-Hub Addon: $fname"
                    fi
            fi
        done <<< "$addon_lines"
    else
        ui_echo " \e[90mUser Declined download of ESO-Hub Addons. Will not ask again.\e[0m"
        SKIP_DL_EH=true
        save_config
    fi
        fi
    fi

    HAS_TTC=$(check_addon_enabled "TamrielTradeCentre")
    HAS_HM=$(check_addon_enabled "HarvestMap")

    # [0/4] Database Update
    if [ "$ENABLE_LOCAL_MODE" != true ]; then
        ui_echo "\e[1m\e[97m [0/4] Synchronizing Local Database \e[0m"
        ui_echo " \e[33mChecking ESOUI for database updates...\e[0m"
        
        # Fetch database from ESOUI
        DB_API_RESP=$(curl -s -m 30 "https://api.mmoui.com/v3/game/ESO/filedetails/4428.json" 2>/dev/null)
        SRV_DB_VER=$(echo "$DB_API_RESP" | grep -ioE '"(version|uiversion)":"[^"]*"' | head -n 1 | cut -d'"' -f4 | tr -d '\r\n\t ')
        DB_DL_URL=$(echo "$DB_API_RESP" | grep -ioE '"downloadurl":"[^"]*"' | head -n 1 | cut -d'"' -f4 | sed 's/\\//g' | tr -d '\r\n\t ')
        
        
        [ -z "$DB_DL_URL" ] && DB_DL_URL="https://cdn.esoui.com/downloads/file4428/"
        [ -z "$SRV_DB_VER" ] && SRV_DB_VER="0.0.0"

        # Check Local Version
        LOC_DB_VER="0.0.0"
        if [ -f "$DB_FILE" ]; then
            extracted_ver=$(head -n 1 "$DB_FILE" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
            [ -n "$extracted_ver" ] && LOC_DB_VER="$extracted_ver"
        fi

        [ "$SRV_DB_VER" = "$LOC_DB_VER" ] && V_COL="\e[92m" || V_COL="\e[31m"
        
        ui_echo "\t\e[90mServer_DB_Version= ${V_COL}$SRV_DB_VER\e[0m"
        ui_echo "\t\e[90mLocal_DB_Version=  ${V_COL}$LOC_DB_VER\e[0m"

        if [ "$SRV_DB_VER" != "$LOC_DB_VER" ] && [ "$SRV_DB_VER" != "0.0.0" ]; then
            ui_echo " \e[36mDownloading latest database template...\e[0m"
            log_event "INFO" "Downloading database update (v$SRV_DB_VER)"
            
            curl -s -A "Mozilla/5.0" -o /dev/null "https://www.esoui.com/downloads/download4428.zip" &
            
            mkdir -p "$TEMP_DIR_ROOT/DB_Update"
            if curl -s -f -m 60 -L -A "Mozilla/5.0" -o "$TEMP_DIR_ROOT/DB_Update/db.zip" "$DB_DL_URL" </dev/null; then
                unzip -q -o "$TEMP_DIR_ROOT/DB_Update/db.zip" -d "$TEMP_DIR_ROOT/DB_Update/" > /dev/null 2>&1
                
                NEW_DB=$(find "$TEMP_DIR_ROOT/DB_Update" -name "LTTC_Database.db" | head -n 1)
                NEW_HIST=$(find "$TEMP_DIR_ROOT/DB_Update" -name "LTTC_History.db" | head -n 1)
                
                if [ -n "$NEW_DB" ] && [ -f "$NEW_DB" ]; then
                    if [ ! -s "$DB_FILE" ]; then
                        echo "#DATABASE VERSION: $SRV_DB_VER" > "$DB_FILE"
                        cat "$NEW_DB" >> "$DB_FILE"
                        ui_echo " \e[92m[+] Database downloaded and installed!\e[0m\n"
                    else
                        ui_echo " \e[33mMerging new database entries (Preventing Duplicates)...\e[0m"
                        # Read Local DB first to preserve data, then add missing Server data.
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
                        ui_echo " \e[92m[+] Database successfully merged to v$SRV_DB_VER!\e[0m\n"
                    fi
                    
                    if [ -n "$NEW_HIST" ] && [ -f "$NEW_HIST" ]; then
                        if [ ! -f "$DB_DIR/LTTC_History.db" ]; then
                            echo "#HISTORY VERSION: $SRV_DB_VER" > "$DB_DIR/LTTC_History.db"
                            cat "$NEW_HIST" >> "$DB_DIR/LTTC_History.db"
                        else
                            # update just the history header without destroying data
                            sed -i.bak '/^#HISTORY VERSION:/d' "$DB_DIR/LTTC_History.db" 2>/dev/null
                            sed -i.bak "1i\\#HISTORY VERSION: $SRV_DB_VER" "$DB_DIR/LTTC_History.db" 2>/dev/null
                            rm -f "$DB_DIR/LTTC_History.db.bak" 2>/dev/null
                        fi
                    fi
                    log_event "INFO" "Database update/merge completed successfully."
                else
                    ui_echo " \e[31m[-] LTTC_Database.db not found in the downloaded archive.\e[0m\n"
                    log_event "ERROR" "Failed to locate DB file inside downloaded archive."
                fi
                rm -rf "$TEMP_DIR_ROOT/DB_Update"
            else
                ui_echo " \e[31m[-] Database download failed (Timeout or Blocked).\e[0m\n"
                log_event "ERROR" "Database download failed."
            fi
        else
            ui_echo " \e[90mNo changes detected. \e[92mLocal database is up-to-date. \e[35mSkipping download.\e[0m\n"
        fi
    fi

    # TTC Data extraction & upload
    if [ "$HAS_TTC" = "false" ]; then
        ui_echo "\e[1m\e[97m [1/4] & [2/4] Updating TTC Data (SKIPPED)\e[0m"
        ui_echo " \e[31m[-] TamrielTradeCentre is not installed or enabled in AddOnSettings.txt. \e[35mSkipping TTC updates.\e[0m\n"
        NOTIF_TTC="Not Installed (Skipped)"
        log_event "WARN" "TTC not found or enabled. Skipping TTC updates."
    else
        ui_echo "\e[1m\e[97m [1/4] Uploading your Local TTC Data to TTC Server \e[0m"
        TTC_CHANGED=true
        if [ -f "$SAVED_VAR_DIR/TamrielTradeCentre.lua" ]; then
            if [ -f "$SNAP_DIR/lttc_ttc_snapshot.lua" ]; then
                if cmp -s "$SAVED_VAR_DIR/TamrielTradeCentre.lua" "$SNAP_DIR/lttc_ttc_snapshot.lua"; then
                    TTC_CHANGED=false
                fi
            fi
        fi

        if [ -f "$SAVED_VAR_DIR/TamrielTradeCentre.lua" ]; then
            if [ "$TTC_CHANGED" = false ]; then
                ui_echo " \e[90mNo changes detected in TamrielTradeCentre.lua. \e[35mSkipping upload.\e[0m\n"
                log_event "INFO" "No changes in local TTC data. Skipping upload."
            else
                if [ "$ENABLE_DISPLAY" = true ] && [ "$SILENT" = false ]; then
                    ui_echo " \e[36mExtracting new local listings & sales data from TTC...\e[0m"
                    log_event "INFO" "Extracting new TTC sales data."
                    echo -e "\n\e[0;35m--- TTC Extracted Data ---\e[0m" >> "$TEMP_SCAN_FILE"

                    awk -v last_time="$TTC_LAST_SALE" -v now_time="$CURRENT_TIME" -v db_file="$DB_FILE" '
                    '"$master_color_logic"'
                    BEGIN { 
                        max_time = last_time; count = 0;
                        while ((getline line < db_file) > 0) {
                            split(line, p, "|")
                            if (p[1] == "GUILD") {
                                db_guild_id[p[2]] = p[3]
                            } else if (p[1] ~ /^[0-9]+$/) {
                                db_cols[p[1]] = length(p); db_qual[p[1]] = p[2]
                                if (length(p) >= 6) { db_name[p[1]] = p[6] } else { db_name[p[1]] = p[3] }
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
                        sub(/^[ \t]*\["?/, "", key); sub(/"?\]$/, "", key)
                        for (i in path) { if ((i + 0) >= lvl) { delete path[i] } }
                        path[lvl] = key
                        
                        if (key == "KioskLocationID") {
                            n = 0; for (i in path) { keys[n++] = i + 0 }
                            for (i = 0; i < n; i++) { for (j = i + 1; j < n; j++) { if (keys[i] > keys[j]) { temp = keys[i]; keys[i] = keys[j]; keys[j] = temp; } } }
                            gname = ""
                            for (i = 0; i < n; i++) { if (path[keys[i]] == "Guilds" && i + 1 < n) { gname = path[keys[i+1]] } }
                            if (gname != "") { match($0, /[0-9]+/); guild_kiosks[gname] = substr($0, RSTART, RLENGTH) }
                        }
                        
                        if (key ~ /^[0-9]+$/ && !in_item) {
                            in_item = 1; item_lvl = lvl; n = 0; for (i in path) { keys[n++] = i + 0 }
                            for (i = 0; i < n; i++) { for (j = i + 1; j < n; j++) { if (keys[i] > keys[j]) { temp = keys[i]; keys[i] = keys[j]; keys[j] = temp; } } }
                            action = "Listed"; guild = ""; player = ""; seller = ""; buyer = ""
                            for (i = 0; i < n; i++) {
                                k = path[keys[i]]
                                if (k == "SaleHistoryEntries") action = "Sold"
                                if (k == "AutoRecordEntries" || k == "Entries") action = "Listed"
                                if (k == "Guilds" && i + 1 < n) guild = path[keys[i+1]]
                                if (k == "PlayerListings" && i + 1 < n) player = path[keys[i+1]]
                            }
                        }
                    }
                    
                    in_item && /\["Amount"\][ \t]*=/ { match($0, /[0-9]+/); amt=substr($0, RSTART, RLENGTH) }
                    in_item && /\["SaleTime"\][ \t]*=/ { match($0, /[0-9]+/); stime=substr($0, RSTART, RLENGTH) }
                    in_item && /\["Timestamp"\][ \t]*=/ { match($0, /[0-9]+/); if(stime=="") stime=substr($0, RSTART, RLENGTH) }
                    in_item && /\["TimeStamp"\][ \t]*=/ { match($0, /[0-9]+/); if(stime=="") stime=substr($0, RSTART, RLENGTH) }
                    in_item && /\["TotalPrice"\][ \t]*=/ { match($0, /[0-9]+/); price=substr($0, RSTART, RLENGTH) }
                    in_item && /\["Price"\][ \t]*=/ { if ($0 !~ /TotalPrice/) { match($0, /[0-9]+/); if(price=="") price=substr($0, RSTART, RLENGTH) } }
                    in_item && /\["Buyer"\][ \t]*=/ { match($0, /\["Buyer"\][ \t]*=[ \t]*"([^"]+)"/); if(RLENGTH>0) { buyer=substr($0,RSTART,RLENGTH); sub(/.*\["Buyer"\][ \t]*=[ \t]*"/,"",buyer); sub(/"$/,"",buyer) } }
                    in_item && /\["Seller"\][ \t]*=/ { match($0, /\["Seller"\][ \t]*=[ \t]*"([^"]+)"/); if(RLENGTH>0) { seller=substr($0,RSTART,RLENGTH); sub(/.*\["Seller"\][ \t]*=[ \t]*"/,"",seller); sub(/"$/,"",seller) } }
                    in_item && /\["ItemLink"\][ \t]*=/ {
                        if (match($0, /\|H[0-9a-fA-F]*:item:[0-9]+/)) {
                            item_part = substr($0, RSTART, RLENGTH)
                            split(item_part, ip, ":")
                            itemid = ip[3]
                        }
                        if (match($0, /"(\|H[^"]+)"/)) {
                            full_link = substr($0, RSTART+1, RLENGTH-2)
                            split(full_link, lp, ":")
                            subtype = lp[4]; internal_level = lp[5]
                        }
                    }
                    in_item && /\["Name"\][ \t]*=/ { val = $0; sub(/.*Name"\][ \t]*=[ \t]*"/, "", val); sub(/",[ \t]*$/, "", val); real_name = val }
                    
                    in_item && /^[ \t]*\},?[ \t]*$/ {
                        match($0, /^[ \t]*/)
                        if (RLENGTH <= item_lvl) {
                            in_item = 0; stime_num = (stime == "") ? 0 : stime + 0
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
                                    s = subtype + 0; v = internal_level + 0; needs_update = 0;
                                    if (itemid in db_name) {
                                        if (real_name != db_name[itemid] && real_name !~ /^Unknown Item/) needs_update = 1
                                        if (db_cols[itemid] < 7) needs_update = 1
                                    } else { needs_update = 1 }

                                    if (itemid in db_qual) {
                                        real_qual = db_qual[itemid] + 0
                                    } else {
                                        real_qual = calc_quality(itemid, real_name, s, v)
                                    }
                                    
                                    if (index(real_name, "Unknown Item (") == 1) needs_update = 0
                                    if (needs_update) {
                                        hq = get_hq(real_qual); cat = get_cat(real_name, itemid, s, v)
                                        db_updated[itemid] = itemid "|" real_qual "|" s "|" v "|" hq "|" real_name "|" cat
                                        db_name[itemid] = real_name; db_qual[itemid] = real_qual; db_cols[itemid] = 7
                                    }

                                    # Always format colors for display
                                    q_num = real_qual + 0; c = "\033[0m"
                                    if(q_num==0) c="\033[90m"; else if(q_num==1) c="\033[97m"; else if(q_num==2) c="\033[32m"
                                    else if(q_num==3) c="\033[36m"; else if(q_num==4) c="\033[35m"; else if(q_num==5) c="\033[33m"
                                    else if(q_num==6) c="\033[38;5;214m"
                                    
                                    guild_str = ""
                                    if (guild != "" && guild != "Guilds") {
                                        if (guild in db_guild_id) {
                                            gid = db_guild_id[guild]; fake_url = "|H1:guild:" gid "|h" guild "|h"
                                            g_display = "\033[35m\033]8;;" fake_url "\033\\" guild "\033]8;;\033\\\033[0m"
                                        } else { g_display = "\033[35m" guild "\033[0m" }
                                        
                                        kiosk = guild_kiosks[guild]
                                        if (kiosk != "" && kiosk != "0") {
                                            if (kiosk in k_dict) {
                                                split(k_dict[kiosk], kp, "|")
                                                k_loc = kp[1]; k_map = kp[2]
                                                if (k_map != "") k_str = " \033[90m(\033]8;;https://eso-hub.com/en/interactive-map?map=" k_map "\033\\" k_loc "\033]8;;\033\\)\033[0m"
                                                else k_str = " \033[90m(" k_loc ")\033[0m"
                                            } else k_str = " \033[90m(Kiosk ID: " kiosk ")\033[0m"
                                        } else { k_str = " \033[90m(Local Trader)\033[0m" }
                                        guild_str = " in " g_display k_str
                                    }
                                    
                                    player_str_clean = player
                                    if (player_str_clean != "" && player_str_clean !~ /^@/) player_str_clean = "@" player_str_clean
                                    
                                    if (buyer != "" && buyer !~ /^@/) buyer = "@" buyer
                                    if (seller != "" && seller !~ /^@/) seller = "@" seller

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
                                    
                                    link_start = "\033]8;;https://us.tamrieltradecentre.com/pc/Trade/SearchResult?ItemID=" itemid "\033\\"
                                    link_end = "\033]8;;\033\\"
                                    
                                    age = now_time - stime_num; status_tag = ""
                                    if (action == "Sold") { status_tag = " \033[38;5;214m[SOLD]\033[0m" } 
                                    else if (action == "Listed") {
                                        if (stime_num > 0 && age > 2592000) status_tag = " \033[90m[EXPIRED]\033[0m"
                                        else status_tag = " \033[34m[AVAILABLE]\033[0m"
                                    }

                                    ts_str = (stime_num > 0) ? stime_num "|" : "0|"
                                    
                                    # ALWAYS Display the item
                                    lines[count] = ts_str " \033[36m" action "\033[0m for \033[32m" price "\033[33mgold\033[0m - \033[32m" amt "x\033[0m " link_start c real_name "\033[0m" link_end trade_str guild_str status_tag
                                    
                                    # ONLY save to History if it is a known item
                                    if (index(real_name, "Unknown Item (") == 0 && guild != "Guilds" && guild != "Unknown Guild" && guild != "") {
                                        hist_lines[count] = "HISTORY|" ts_str action "|" price "|" amt "|" itemid "|" real_name "|" buyer "|" seller "|" guild "|" kiosk "|" c "|TTC"
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
                        for (i in db_updated) { print "DB_UPDATE|" db_updated[i] }
                    }' "$SAVED_VAR_DIR/TamrielTradeCentre.lua" > "$TEMP_DIR_ROOT/lttc_ttc_tmp.out" 2>> "$LOG_FILE" &
                    
                    AWK_PID=$!
                    spinstr='|/-\'
                    tput civis
                    while kill -0 $AWK_PID 2>/dev/null; do
                        temp=${spinstr#?}
                        printf " \e[33m[%c]\e[0m Parsing TamrielTradeCentre.lua... " "$spinstr"
                        spinstr=$temp${spinstr%"$temp"}
                        sleep 0.1
                        printf "\r"
                    done
                    tput cnorm
                    AWK_OUT=$(< "$TEMP_DIR_ROOT/lttc_ttc_tmp.out")
                    rm -f "$TEMP_DIR_ROOT/lttc_ttc_tmp.out"
                    
                    NEXT_TIME=$(echo "$AWK_OUT" | grep "^MAX_TIME:" | cut -d':' -f2)
                    RAW_DATA=$(echo "$AWK_OUT" | grep -vE "^(MAX_TIME:|DB_UPDATE\||HISTORY\|)")
                    DB_OUTPUT=$(echo "$AWK_OUT" | grep "^DB_UPDATE|")
                    HISTORY_OUTPUT=$(echo "$AWK_OUT" | grep "^HISTORY|")

                    if [ -n "$RAW_DATA" ]; then
                        printf " \e[92m[✓]\e[0m Extraction complete!                  \033[K\n"
                        FOUND_NEW_DATA=true
                        echo "$RAW_DATA" | while IFS='|' read -r ts output_str; do
                            if [ "$ts" = "0" ]; then 
                                raw_line=" [\e[90mListing\e[0m]$output_str"
                            else 
                                raw_line=" [TS:$ts]$output_str"
                            fi
                            ui_echo "$raw_line"
                            echo -e "$raw_line" >> "$TEMP_SCAN_FILE"
                            log_event "ITEM" "$raw_line"
                        done
                    else
                        printf "\r\033[K"
                        ui_echo " \e[90mNo new TTC items found. Upload skipped.\e[0m"
                        log_event "INFO" "No new TTC sales or listings found."
                    fi

                    if [ -n "$HISTORY_OUTPUT" ]; then echo "$HISTORY_OUTPUT" >> "$DB_DIR/LTTC_History.db"; fi
                    apply_db_updates "$DB_OUTPUT"
                    
                    if [ -n "$NEXT_TIME" ] && [ "$NEXT_TIME" != "$TTC_LAST_SALE" ]; then
                        TTC_LAST_SALE="$NEXT_TIME"
                        CONFIG_CHANGED=true
                    fi
                else
                    ui_echo " \e[90mExtraction disabled by user. Proceeding instantly to upload...\e[0m"
                    log_event "INFO" "TTC extraction disabled. Skipping to upload."
                fi
                if [ "$ENABLE_LOCAL_MODE" = true ]; then
                    ui_echo "\n \e[90m[Local Mode] Skipping TTC Upload. Data extracted to local DB only.\e[0m\n"
                    NOTIF_TTC="Extracted (No Upload)"
                    cp -f "$SAVED_VAR_DIR/TamrielTradeCentre.lua" "$SNAP_DIR/lttc_ttc_snapshot.lua" 2>/dev/null
                else
                    if [ -z "$RAW_DATA" ]; then
                        NOTIF_TTC="No New Data"
                        cp -f "$SAVED_VAR_DIR/TamrielTradeCentre.lua" "$SNAP_DIR/lttc_ttc_snapshot.lua" 2>/dev/null
                    else
                        ui_echo "\n \e[36mUploading to:\e[0m https://$TTC_DOMAIN/pc/Trade/WebClient/Upload"
                        
                        if (curl -s -A "$TTC_USER_AGENT" -F "SavedVarFileInput=@$SAVED_VAR_DIR/TamrielTradeCentre.lua" "https://$TTC_DOMAIN/pc/Trade/WebClient/Upload" > /dev/null 2>&1); then
                            NOTIF_TTC="Data Uploaded"
                            ui_echo " \e[92m[+] Upload finished.\e[0m\n"
                            log_event "INFO" "TTC data upload successful."
                            cp -f "$SAVED_VAR_DIR/TamrielTradeCentre.lua" "$SNAP_DIR/lttc_ttc_snapshot.lua" 2>/dev/null
                        else
                            NOTIF_TTC="Upload Failed"
                            ui_echo " \e[31m[!] Upload failed.\e[0m\n"
                            log_event "ERROR" "TTC data upload failed."
                        fi
                    fi
                fi
            fi
        else
            ui_echo " \e[33m[-] No TamrielTradeCentre.lua found. \e[35mSkipping upload.\e[0m\n"
            log_event "WARN" "TamrielTradeCentre.lua not found. Skipping upload."
        fi

        # TTC DOWNLOAD 
        ui_echo "\e[1m\e[97m [2/4] Updating your Local TTC Data \e[0m"
        ui_echo " \e[33mChecking TTC API for price table version...\e[0m"
        log_event "INFO" "Checking TTC API for updates."
        
        TTC_LAST_CHECK="$CURRENT_TIME"
        CONFIG_CHANGED=true

        API_RESP=$(curl -s -A "$TTC_USER_AGENT" "https://$TTC_DOMAIN/api/GetTradeClientVersion" 2>/dev/null)
        SRV_VERSION=$(echo "$API_RESP" | grep -o '"PriceTableVersion":[^,}]*' | cut -d':' -f2 | tr -d ' ' | tr -d '"')

        if [ -z "$SRV_VERSION" ] || ! [[ "$SRV_VERSION" =~ ^[0-9]+$ ]]; then
            NOTIF_TTC="Download Error"
            ui_echo " \e[31m[-] Could not fetch version from TTC API. \e[35mSkipping download.\e[0m\n"
            log_event "ERROR" "Failed to fetch TTC API version."
        else
            LOCAL_VERSION="0"
            PT_FILE="$ADDON_DIR/TamrielTradeCentre/PriceTableNA.lua"
            [ "$AUTO_SRV" == "2" ] && PT_FILE="$ADDON_DIR/TamrielTradeCentre/PriceTableEU.lua"
            
            if [ -f "$PT_FILE" ]; then
                LOCAL_VERSION=$(head -n 5 "$PT_FILE" 2>/dev/null | grep -iE '^--Version[ \t]*=[ \t]*[0-9]+' | grep -oE '[0-9]+' | head -n 1)
                [ -z "$LOCAL_VERSION" ] && LOCAL_VERSION="0"
            fi

            LOCAL_DISPLAY="$LOCAL_VERSION"
            [ "$LOCAL_VERSION" = "0" ] && LOCAL_DISPLAY="None / Not Found"
            [ "$SRV_VERSION" = "$LOCAL_VERSION" ] && V_COL="\e[92m" || V_COL="\e[31m"

            if [ "$SRV_VERSION" -gt "$LOCAL_VERSION" ] 2>/dev/null; then
                ui_echo " \e[92mNew TTC Price Table available \e[0m"
                log_event "INFO" "New TTC Price Table available (Server: $SRV_VERSION, Local: $LOCAL_VERSION)."
                
                TTC_TIME_DIFF=$((CURRENT_TIME - TTC_LAST_DOWNLOAD))
                if [ "$ENABLE_LOCAL_MODE" = true ]; then
                    ui_echo " \t\e[90mServer Version: ${V_COL}$SRV_VERSION\e[0m"
                    ui_echo " \t\e[90mLocal Version: ${V_COL}$LOCAL_DISPLAY\e[0m"
                    ui_echo " \e[90m[Local Mode] Download Skipped.\e[0m\n"
                elif [ "$TTC_TIME_DIFF" -lt 3600 ] && [ "$TTC_TIME_DIFF" -ge 0 ]; then
                    WAIT_MINS=$(( (3600 - TTC_TIME_DIFF) / 60 ))
                    [ "$NOTIF_TTC" = "Data Uploaded" ] && NOTIF_TTC="Uploaded (DL Cooldown)" || NOTIF_TTC="Download Cooldown"
                    ui_echo " \t\e[90mServer Version: ${V_COL}$SRV_VERSION\e[0m"
                    ui_echo " \t\e[90mLocal Version: ${V_COL}$LOCAL_DISPLAY\e[0m"
                    ui_echo " \e[33mbut download is on cooldown. Please wait $WAIT_MINS minutes. \e[35mSkipping.\e[0m\n"
                    log_event "WARN" "TTC download on cooldown ($WAIT_MINS mins remaining). Skipping."
                else
                    ui_echo " \t\e[90mServer Version: ${V_COL}$SRV_VERSION\e[0m"
                    ui_echo " \t\e[90mLocal Version: ${V_COL}$LOCAL_DISPLAY\e[0m"
                    
                    SUCCESS=false
                    TEMP_DIR_USED=true
                    
                    if curl -s -f -A "$TTC_USER_AGENT" -# -L -o "TTC-data.zip" "$TTC_URL" 2>&3; then
                        if unzip -t "TTC-data.zip" > /dev/null 2>&1; then SUCCESS=true; fi
                    fi
                    
                    if [ "$SUCCESS" = false ]; then
                        ui_echo " \e[33m[-] Primary User-Agent blocked. Falling back...\e[0m"
                        log_event "WARN" "TTC primary UA blocked. Retrying."
                        for UA in "${shuffled_uas[@]}"; do
                            if curl -s -f -H "User-Agent: $UA" -# -L -o "TTC-data.zip" "$TTC_URL" 2>&3; then
                                if unzip -t "TTC-data.zip" > /dev/null 2>&1; then SUCCESS=true; break; fi
                            fi
                        done
                    fi

                    if [ "$SUCCESS" = true ]; then
                        unzip -o "TTC-data.zip" -d TTC_Extracted > /dev/null
                        mkdir -p "$ADDON_DIR/TamrielTradeCentre"
                        rsync -avh TTC_Extracted/ "$ADDON_DIR/TamrielTradeCentre/" > /dev/null
                        
                        TTC_LAST_DOWNLOAD=$CURRENT_TIME
                        TTC_LOC_VERSION="$SRV_VERSION"
                        CONFIG_CHANGED=true
                        
                        [ "$NOTIF_TTC" = "Data Uploaded" ] && NOTIF_TTC="Uploaded & Updated" || NOTIF_TTC="Updated"
                        ui_echo " \e[92m[+] TTC Data Successfully Updated.\e[0m\n"
                        log_event "INFO" "TTC PriceTable updated successfully."
                    else
                        [ "$NOTIF_TTC" = "Data Uploaded" ] && NOTIF_TTC="Uploaded, DL Failed" || NOTIF_TTC="Download Error"
                        ui_echo " \e[31m[!] Error: TTC Data download was blocked by the server.\e[0m\n"
                        log_event "ERROR" "TTC Data download failed (blocked or corrupted)."
                    fi
                fi
            else
                TTC_LOC_VERSION="$LOCAL_VERSION"
                CONFIG_CHANGED=true
                ui_echo " \t\e[90mServer Version: ${V_COL}$SRV_VERSION\e[0m"
                ui_echo " \t\e[90mLocal Version: ${V_COL}$LOCAL_DISPLAY\e[0m\n"
                ui_echo " \e[90mNo changes detected. \e[92mLocal PriceTable is up-to-date. \e[35mSkipping download.\e[0m"
                log_event "INFO" "TTC PriceTable is up-to-date."
            fi
        fi
    fi

    # ESO-HUB extraction & upload
    ui_echo "\e[1m\e[97m [3/4] Updating ESO-Hub Prices & Uploading Scans \e[0m"
    ui_echo " \e[36mFetching latest ESO-Hub version data...\e[0m"
    log_event "INFO" "Checking ESO-Hub API for updates."
    
    EH_LAST_CHECK="$CURRENT_TIME"
    CONFIG_CHANGED=true
    EH_UPLOAD_COUNT=0
    EH_UPDATE_COUNT=0

    API_RESP=$(curl -s -X POST -H "User-Agent: ESOHubClient/1.0.9" -d "user_token=&client_system=$SYS_ID&client_version=1.0.9&lang=en" "https://data.eso-hub.com/v1/api/get-addon-versions" 2>/dev/null)
    ADDON_LINES=$(echo "$API_RESP" | sed 's/{"folder_name"/\n{"folder_name"/g' | grep '"folder_name"')
    
    if [ -z "$ADDON_LINES" ]; then
        NOTIF_EH="Download Error"
        ui_echo " \e[31m[-] Could not fetch ESO-Hub data.\e[0m\n"
        log_event "ERROR" "Failed to fetch ESO-Hub API data."
    else
        EH_TIME_DIFF=$((CURRENT_TIME - EH_LAST_DOWNLOAD))
        EH_DOWNLOAD_OCCURRED=false

        while read -r line; do
            FNAME=$(echo "$line" | grep -oE '"folder_name":"[^"]+"' | cut -d'"' -f4)
            SV_NAME=$(echo "$line" | grep -oE '"sv_file_name":"[^"]+"' | cut -d'"' -f4)
            UP_EP=$(echo "$line" | grep -oE '"endpoint":"[^"]+"' | cut -d'"' -f4 | sed 's/\\//g')
            DL_URL=$(echo "$line" | grep -oE '"file":"[^"]+"' | cut -d'"' -f4 | sed 's/\\//g')
            
            if [ -z "$FNAME" ]; then continue; fi
            
            HAS_THIS_EH=$(check_addon_enabled "$FNAME")

            if [ "$HAS_THIS_EH" = "false" ]; then
                ui_echo " \e[31m[-] $FNAME installed or enabled in AddOnSettings.txt. \e[35mSkipping.\e[0m"
                log_event "INFO" "$FNAME not enabled. Skipping."
                continue
            fi

            ID_NUM=$(echo "$DL_URL" | grep -oE '[0-9]+$')
            [ -z "$ID_NUM" ] && ID_NUM="0"
            SRV_VER=$(echo "$line" | grep -oE '"version":\{[^}]*\}' | grep -oE '"string":"[^"]+"' | cut -d'"' -f4)
            
            PREFIX="$FNAME"
            [ "$FNAME" = "EsoTradingHub" ] && PREFIX="ETH5"
            [ "$FNAME" = "LibEsoHubPrices" ] && PREFIX="LEHP7"
            [ "$FNAME" = "EsoHubScanner" ] && PREFIX="EHS"

            VAR_LOC_NAME="EH_LOC_$ID_NUM"
            LOC_VER="${!VAR_LOC_NAME}"
            [ -z "$LOC_VER" ] && LOC_VER="0"
            
            # Adopt server version if the addon exists physically but config is 0
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
                UP_SNAP="$SNAP_DIR/lttc_eh_$(echo "$SV_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/\.lua//')_snapshot.lua"
                EH_LOCAL_CHANGED=true
                if [ -f "$UP_SNAP" ] && cmp -s "$SAVED_VAR_DIR/$SV_NAME" "$UP_SNAP"; then
                    EH_LOCAL_CHANGED=false
                fi

                if [ "$EH_LOCAL_CHANGED" = false ]; then
                    ui_echo " \e[90mNo changes detected in $SV_NAME. \e[35mSkipping upload.\e[0m"
                    log_event "INFO" "No changes in $SV_NAME. Skipping upload."
                else
                    if [ "$SV_NAME" = "EsoTradingHub.lua" ] && [ "$ENABLE_DISPLAY" = true ] && [ "$SILENT" = false ]; then
                        ui_echo " \e[36mExtracting new sales & scan data from EsoTradingHub...\e[0m"
                        log_event "INFO" "Extracting EsoTradingHub data."
                        echo -e "\n\e[0;35m--- ESO-Hub Extracted Data ---\e[0m" >> "$TEMP_SCAN_FILE"

                        awk -v last_time="$EH_LAST_SALE" -v now_time="$CURRENT_TIME" -v db_file="$DB_FILE" '
                        '"$master_color_logic"'
                        BEGIN { 
                            max_time = last_time; count = 0; scrape_count = 0; stop_scraping = 0
                            
                            while ((getline line < db_file) > 0) {
                                split(line, p, "|")
                                if (p[1] == "GUILD") {
                                    db_guild_id[p[2]] = p[3]
                                    db_guild_name[p[3]] = p[2]
                                } else if (p[1] ~ /^[0-9]+$/) {
                                    db_cols[p[1]] = length(p)
                                    db_qual[p[1]] = p[2]
                                    if (length(p) >= 6) { db_name[p[1]] = p[6] } else { db_name[p[1]] = p[3] }
                                }
                            }
                            close(db_file)
                            '"$master_kiosk_logic"'
                        }
                        { sub(/\r$/, "") }
                        
                        /\["traderData"\]/ { in_trader_data = 1; in_guild_data = 0 }
                        /\["guildData"\]/ { in_guild_data = 1; in_trader_data = 0 }
                        
                        # Capture Trader Name directly from the Parent Node Key
                        in_trader_data && /^[ \t]*\["([^"]+)"\][ \t]*=[ \t]*$/ {
                            match($0, /\["([^"]+)"\]/)
                            val = substr($0, RSTART+2, RLENGTH-4)
                            if (val != "NA Megaserver" && val != "EU Megaserver" && val != "PTS" && val != "guildHistory") {
                                current_trader = val
                            }
                        }
                        
                        in_trader_data && /\["mapId"\][ \t]*=[ \t]*[0-9]+/ {
                            match($0, /[0-9]+/)
                            if (current_trader != "") trader_maps[current_trader] = substr($0, RSTART, RLENGTH)
                        }
                        
                        # Map the Guild ID to the active Trader Name & Map ID
                        in_trader_data && /^[ \t]*\[[0-9]+\][ \t]*=[ \t]*[0-9]+,?/ {
                            match($0, /=[ \t]*[0-9]+/)
                            if (RLENGTH > 0) {
                                gid = substr($0, RSTART, RLENGTH)
                                sub(/=[ \t]*/, "", gid)
                                if (current_trader != "") {
                                    guild_kiosks[gid] = current_trader
                                    if (trader_maps[current_trader] != "") guild_maps[gid] = trader_maps[current_trader]
                                }
                            }
                        }

                        # Capture Guild ID from the Parent Node immediately
                        in_guild_data && /^[ \t]*\[[0-9]+\][ \t]*=[ \t]*$/ {
                            match($0, /[0-9]+/)
                            current_guild_id = substr($0, RSTART, RLENGTH)
                            buffered_gname = ""
                            scan_type = ""
                        }
                        
                        # Capture from guildId key securely
                        in_guild_data && /\["guildId"\][ \t]*=[ \t]*[0-9]+/ {
                            match($0, /[0-9]+/)
                            current_guild_id = substr($0, RSTART, RLENGTH)
                            if (buffered_gname != "") {
                                guild_names[current_guild_id] = buffered_gname
                                db_guild_updated[buffered_gname] = current_guild_id
                                buffered_gname = ""
                            }
                        }
                        
                        # Capture Guild Name
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
                            if (scan_type == "") next;

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
                                        itemid = lp[3]; subtype = lp[4]; internal_level = lp[5]
                                        s = subtype + 0; v = internal_level + 0
                                        
                                        split(data_csv, arr, ",")
                                        price = arr[1]; qty = arr[2]; buyer = ""; seller = ""; stime = 0
                                        if (qty == "") qty = "1"
                                        
                                        for (idx = length(arr); idx >= 3; idx--) {
                                            if (arr[idx] ~ /^[0-9]+$/ && arr[idx] + 0 > 1400000000) {
                                                stime = arr[idx] + 0
                                                break
                                            }
                                        }

                                        if (scan_type == "Sold" || scan_type == "Purchased") {
                                            seller = arr[3]; buyer = arr[4]
                                        } else {
                                            seller = arr[3]
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
                                            if (db_name[itemid] != real_name) needs_update = 1
                                            if (db_qual[itemid] != real_qual) needs_update = 1
                                            if (db_cols[itemid] < 7) needs_update = 1
                                        }

                                        if (needs_update) {
                                            hq = get_hq(real_qual)
                                            cat = get_cat(real_name, itemid, s, v)
                                            db_updated[itemid] = itemid "|" real_qual "|" s "|" v "|" hq "|" real_name "|" cat
                                            db_name[itemid] = real_name
                                            db_qual[itemid] = real_qual
                                            db_cols[itemid] = 7
                                        }

                                        if (real_name != "" && price != "") {
                                            if (stime > max_time) max_time = stime
                                            if (stime > last_time || stime == 0 || scan_type == "Listed") {
                                                q_num = real_qual + 0
                                                c = "\033[0m"
                                                if(q_num==0) c="\033[90m"; else if(q_num==1) c="\033[97m"; else if(q_num==2) c="\033[32m"
                                                else if(q_num==3) c="\033[36m"; else if(q_num==4) c="\033[35m"; else if(q_num==5) c="\033[33m"
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
                                                    if (stime > 0 && age > 2592000) status_tag = " \033[90m[EXPIRED]\033[0m"
                                                    else status_tag = " \033[34m[AVAILABLE]\033[0m"
                                                }

                                                lines[count] = stime "|" " \033[36m" scan_type "\033[0m for \033[32m" price "\033[33mgold\033[0m - \033[32m" qty "x\033[0m " item_display trade_str " in GUILD_PLACEHOLDER_" current_guild_id status_tag
                                                
                                                # ONLY save to History if it is a known item
                                                if (index(real_name, "Unknown Item (") == 0 && current_guild_id != "") {
                                                    hist_lines[count] = "HISTORY|" stime "|" scan_type "|" price "|" qty "|" itemid "|" real_name "|" buyer "|" seller "|" current_guild_id "||" c "|ESO-Hub"
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
                                        k_loc = kp[1]; k_map = kp[2]
                                        k_str = " \033[90m(\033]8;;https://eso-hub.com/en/interactive-map?map=" k_map "\033\\" k_loc "\033]8;;\033\\)\033[0m"
                                    } else if (map_id != "") {
                                        k_str = " \033[90m(\033]8;;https://eso-hub.com/en/interactive-map?map=" map_id "\033\\" kiosk "\033]8;;\033\\)\033[0m"
                                    } else {
                                        k_str = " \033[90m(" kiosk ")\033[0m"
                                    }
                                }
                                
                                gsub("GUILD_PLACEHOLDER_" gid, g_link k_str, l)
                                
                                print l
                                if (h != "") {
                                    gsub(gid "\\|\\|", gname "|" kiosk "|", h)
                                    print h 
                                }
                            }
                            print "MAX_TIME:" max_time
                            for (i in db_updated) { print "DB_UPDATE|" db_updated[i] }
                            for (g in db_guild_updated) { print "DB_GUILD|" g "|" db_guild_updated[g] }
                        }' "$SAVED_VAR_DIR/$SV_NAME" > "$TEMP_DIR_ROOT/lttc_eh_tmp.out" 2>> "$LOG_FILE" &
                        
                        AWK_PID=$!
                        spinstr='|/-\'
                        tput civis
                        while kill -0 $AWK_PID 2>/dev/null; do
                            temp=${spinstr#?}
                            printf " \e[33m[%c]\e[0m Parsing %s... " "$spinstr" "$SV_NAME"
                            spinstr=$temp${spinstr%"$temp"}
                            sleep 0.1
                            printf "\r"
                        done
                        tput cnorm
                        AWK_OUT=$(< "$TEMP_DIR_ROOT/lttc_eh_tmp.out")
                        rm -f "$TEMP_DIR_ROOT/lttc_eh_tmp.out"
                        
                        NEXT_TIME=$(echo "$AWK_OUT" | grep "^MAX_TIME:" | cut -d':' -f2)
                        RAW_DATA=$(echo "$AWK_OUT" | grep -vE "^(MAX_TIME:|DB_UPDATE\||DB_GUILD\||HISTORY\|)")
                        DB_OUTPUT=$(echo "$AWK_OUT" | grep -E "^(DB_UPDATE\||DB_GUILD\|)")
                        HISTORY_OUTPUT=$(echo "$AWK_OUT" | grep "^HISTORY|")

                        if [ -n "$RAW_DATA" ]; then
                            printf " \e[92m[✓]\e[0m Extraction complete!             \033[K\n"
                            FOUND_NEW_DATA=true
                            echo "$RAW_DATA" | while IFS='|' read -r ts output_str; do
                                if [ "$ts" = "0" ]; then 
                                    raw_line=" [\e[90mListing\e[0m]$output_str"
                                else 
                                    raw_line=" [TS:$ts]$output_str"
                               fi
                                ui_echo "$raw_line"
                                echo -e "$raw_line" >> "$TEMP_SCAN_FILE"
                                log_event "ITEM" "$raw_line"
                            done
                        else
                            printf "\r\033[K"
                            ui_echo " \e[90mNo new ESO-Hub items found. Upload skipped.\e[0m"
                            log_event "INFO" "No new ESO-Hub sales found."
                        fi

                        if [ -n "$HISTORY_OUTPUT" ]; then
                            echo "$HISTORY_OUTPUT" >> "$DB_DIR/LTTC_History.db"
                        fi
                        apply_db_updates "$DB_OUTPUT"
                        
                        if [ -n "$NEXT_TIME" ] && [ "$NEXT_TIME" != "$EH_LAST_SALE" ]; then
                            EH_LAST_SALE="$NEXT_TIME"
                            CONFIG_CHANGED=true
                        fi
                        rm -f "$SCRAPED_JOURNAL" 2>/dev/null
                    else
                         if [ "$SV_NAME" = "EsoTradingHub.lua" ] && [ "$ENABLE_DISPLAY" = false ] && [ "$SILENT" = false ]; then
                             ui_echo " \e[90mExtraction disabled by user. Proceeding instantly to upload...\e[0m"
                             log_event "INFO" "EsoTradingHub extraction disabled."
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
                            ui_echo " \e[36mUploading local scan data ($SV_NAME)...\e[0m"
                            if (curl -s -m 60 -A "ESOHubClient/1.0.9" -F "file=@$SAVED_VAR_DIR/$SV_NAME" "https://data.eso-hub.com$UP_EP?user_token=$EH_USER_TOKEN" > /dev/null 2>&1); then
                                cp -f "$SAVED_VAR_DIR/$SV_NAME" "$UP_SNAP" 2>/dev/null
                                EH_UPLOAD_COUNT=$((EH_UPLOAD_COUNT + 1))
                                ui_echo " \e[92m[+] Upload finished ($SV_NAME).\e[0m"
                                log_event "INFO" "Uploaded $SV_NAME successfully."
                            else
                                ui_echo " \e[31m[-] Upload failed ($SV_NAME).\e[0m"
                                log_event "ERROR" "Failed to upload $SV_NAME."
                            fi
                        fi
                    fi
                fi
            fi

            if [ -n "$DL_URL" ]; then
                if [ "$SRV_VER" = "$LOC_VER" ]; then
                    ui_echo " \e[90mNo changes detected. \e[92m($FNAME.zip) is up-to-date. \e[35mSkipping download.\e[0m"
                    log_event "INFO" "$FNAME is up-to-date."
                else
                    if [ "$ENABLE_LOCAL_MODE" = true ]; then
                        ui_echo " \e[90m[Local Mode] Skipping Download for $FNAME.zip.\e[0m"
                    elif [ "$EH_TIME_DIFF" -lt 3600 ] && [ "$EH_TIME_DIFF" -ge 0 ]; then
                        WAIT_MINS=$(( (3600 - EH_TIME_DIFF) / 60 ))
                        ui_echo " \e[33mNew $FNAME.zip available, but download is on cooldown for $WAIT_MINS more minutes. \e[35mSkipping.\e[0m"
                        log_event "WARN" "$FNAME download on cooldown ($WAIT_MINS mins)."
                    else
                        ui_echo " \e[36mDownloading: $FNAME.zip\e[0m"
                        log_event "INFO" "Downloading $FNAME.zip"
                        TEMP_DIR_USED=true
                        
                        if ! curl -s -f -# -m 30 -L -A "ESOHubClient/1.0.9" -o "EH_$ID_NUM.zip" --url "$DL_URL" </dev/null 2>&3; then
                            curl -s -f -# -m 30 -L -A "$RAND_UA" -o "EH_$ID_NUM.zip" --url "$DL_URL" </dev/null 2>&3
                        fi
                        
                        if unzip -t "EH_$ID_NUM.zip" > /dev/null 2>&1; then
                            unzip -o "EH_$ID_NUM.zip" -d ESOHub_Extracted > /dev/null
                            rsync -avh ESOHub_Extracted/ "$ADDON_DIR/" > /dev/null
                            
                            printf -v "$VAR_LOC_NAME" "%s" "$SRV_VER"
                            CONFIG_CHANGED=true
                            EH_DOWNLOAD_OCCURRED=true
                            EH_UPDATE_COUNT=$((EH_UPDATE_COUNT + 1))
                            
                            ui_echo " \e[92m[+] $FNAME.zip updated successfully.\e[0m"
                            log_event "INFO" "$FNAME updated successfully."
                        else
                            ui_echo " \e[31m[!] Error: $FNAME.zip download corrupted.\e[0m"
                            log_event "ERROR" "$FNAME download corrupted."
                        fi
                    fi
                fi
            fi
        done <<< "$ADDON_LINES"
        
        if [ "$EH_DOWNLOAD_OCCURRED" = true ]; then EH_LAST_DOWNLOAD=$CURRENT_TIME; fi
        if [ "$EH_UPDATE_COUNT" -gt 0 ] || [ "$EH_UPLOAD_COUNT" -gt 0 ]; then
            NOTIF_EH="Updated ($EH_UPDATE_COUNT), Uploaded ($EH_UPLOAD_COUNT)"
        fi
        ui_echo ""
    fi

    # HarvestMap extraction & upload
    if [ "$HAS_HM" = "false" ] || [ "$ENABLE_LOCAL_MODE" = true ]; then
        NOTIF_HM="Skipped"
        ui_echo "\e[1m\e[97m [4/4] Updating HarvestMap Data (SKIPPED) \e[0m"
        if [ "$ENABLE_LOCAL_MODE" = true ]; then
            ui_echo " \e[90m[Local Mode] Skipping HarvestMap updates.\e[0m\n"
        else
            ui_echo " \e[31m[-] HarvestMap installed or enabled in AddOnSettings.txt. \e[35mSkipping...\e[0m\n"
        fi
        log_event "WARN" "HarvestMap skipped."
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
                if [[ -f "$HM_SNAP" ]] && cmp -s "$MAIN_HM_FILE" "$HM_SNAP"; then
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
                ui_echo " \e[90mNo changes detected. \e[92mHarvestMap.lua is up-to-date. \e[35mSkipping process.\e[0m\n"
                log_event "INFO" "HarvestMap is up-to-date."
            else
                HM_TIME_DIFF=$((CURRENT_TIME - HM_LAST_DOWNLOAD))
                
                if [ "$HM_TIME_DIFF" -lt 3600 ] && [ "$HM_TIME_DIFF" -ge 0 ]; then
                    WAIT_MINS=$(( (3600 - HM_TIME_DIFF) / 60 ))
                    NOTIF_HM="Cooldown ($WAIT_MINS min)"
                    ui_echo " \e[33mHarvestMap local changes detected, but download is on cooldown for $WAIT_MINS more minutes. \e[35mSkipping.\e[0m\n"
                    log_event "WARN" "HarvestMap download on cooldown ($WAIT_MINS mins)."
                else
                    [[ -f "$MAIN_HM_FILE" ]] && cp -f "$MAIN_HM_FILE" "$HM_SNAP" 2>/dev/null
                    mkdir -p "$SAVED_VAR_DIR"
                    log_event "INFO" "Starting HarvestMap update process."
                    
                    hmFailed=false
                    for zone in AD EP DC DLC NF; do
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
                        ui_echo " \e[36mDownloading database chunk to:\e[0m $HM_DIR/Modules/HarvestMap${zone}/HarvestMap${zone}.lua"
                        
                        if ! curl -s -f -L -A "$HM_USER_AGENT" -d @"$svfn2" -o "$HM_DIR/Modules/HarvestMap${zone}/HarvestMap${zone}.lua" "http://harvestmap.binaryvector.net:8081"; then
                            ui_echo "  \e[33m[-] Primary UA blocked. Retrying with fallback UA...\e[0m"
                            log_event "WARN" "HarvestMap primary UA blocked. Retrying."
                            if ! curl -s -f -L -H "User-Agent: $RAND_UA" -d @"$svfn2" -o "$HM_DIR/Modules/HarvestMap${zone}/HarvestMap${zone}.lua" "http://harvestmap.binaryvector.net:8081"; then
                                hmFailed=true
                                log_event "ERROR" "Failed to download HarvestMap zone: $zone"
                            fi
                        fi
                    done
                    
                    if [ "$hmFailed" = false ]; then
                        HM_LAST_DOWNLOAD=$CURRENT_TIME
                        CONFIG_CHANGED=true
                        NOTIF_HM="Updated successfully"
                        ui_echo "\n \e[92m[+] HarvestMap Data Successfully Updated.\e[0m\n"
                        log_event "INFO" "HarvestMap updated successfully."
                    else
                        NOTIF_HM="Error (Server Blocked)"
                        log_event "ERROR" "HarvestMap update failed."
                    fi
                fi
            fi
        else
            NOTIF_HM="Not Found (Skipped)"
            ui_echo "\e[1m\e[97m [4/4] Updating HarvestMap Data (SKIPPED) \e[0m"
            ui_echo " \e[31m[!] HarvestMapData folder not found in: $ADDON_DIR. \e[35mSkipping...\e[0m\n"
            log_event "WARN" "HarvestMap folder not found."
        fi
    fi

    if [ "$FOUND_NEW_DATA" = true ]; then
        mv -f "$TEMP_SCAN_FILE" "$LAST_SCAN_FILE"
    fi

    prune_history
    if [ "$CONFIG_CHANGED" = true ]; then save_config; fi

    if [ "$TEMP_DIR_USED" = true ]; then
        ui_echo "\e[31mCleaning up temporary files...\e[0m\n\e[31mDeleting Temp Directory at: $TEMP_DIR\e[0m"
    fi
    cd "$HOME" || exit
    rm -rvf "$TEMP_DIR" > /dev/null
    rm -f "$TEMP_DIR_ROOT"/*.tmp "$TEMP_DIR_ROOT"/*.out 2>/dev/null
    
    if [ "$TEMP_DIR_USED" = true ]; then
        ui_echo "\e[92m[+] Cleanup Complete.\e[0m\n"
    fi

    if [ "$ENABLE_NOTIFS" = true ]; then
        send_notification "TTC: $NOTIF_TTC\nESO-Hub: $NOTIF_EH\nHarvestMap: $NOTIF_HM"
    fi

    if [ "$AUTO_MODE" == "1" ]; then 
        log_event "INFO" "Run-once mode complete. Exiting."
        exit 0
    fi

    if [ "$CURRENT_TIME" -ge "${TARGET_RUN_TIME:-0}" ]; then
        TARGET_RUN_TIME=$((CURRENT_TIME + 3600))
        save_config
    fi
    target_time=$TARGET_RUN_TIME
    
    if [ "$IS_STEAM_LAUNCH" = true ]; then
        log_event "INFO" "Entering Steam background loop."
        if [ "$SILENT" = true ]; then
            while [ $(date +%s) -lt $target_time ]; do
                read -t 1 -n 1 -s key 2>/dev/null || true
                current_loop_time=$(date +%s)
                if (( current_loop_time % 10 == 0 )); then
                    if ! check_game_active; then 
                        log_event "INFO" "Game closed. Exiting."
                        exit 0; 
                    fi
                fi
            done 2>/dev/null
        else
            echo -e " \e[1;97;101m Restarting Sequence in 60 minutes... (Steam Mode) \e[0m\n"
            while [ $(date +%s) -lt $target_time ]; do
                rem_sec=$((target_time - $(date +%s)))
                min=$(( rem_sec / 60 )); sec=$(( rem_sec % 60 ))
                printf " \e[1;97;101m Countdown: %02d:%02d \e[0m \e[0;90m(Press 'b' to browse data)\e[0m \033[0K\r" "$min" "$sec"
                read -t 1 -n 1 -s key 2>/dev/null || true
                if [[ "$key" == "b" || "$key" == "B" ]]; then
                    browse_database
                    echo -e "\n\e[0;36mResuming countdown...\e[0m"
                fi
                current_loop_time=$(date +%s)
                if (( current_loop_time % 5 == 0 )); then
                    if ! check_game_active; then
                        echo -e "\n\n \e[33mGame closed. Terminating updater...\e[0m"
                        log_event "INFO" "Game closed. Exiting."
                        exit 0
                    fi
                fi
            done 2>/dev/null
        fi
    else
        log_event "INFO" "Entering standalone background loop."
        if [ "$SILENT" = true ]; then
            while [ $(date +%s) -lt $target_time ]; do
                sleep 5
                
                current_loop_time=$(date +%s)
                if (( current_loop_time % 5 == 0 )); then
                    if ! check_game_active; then
                        log_event "INFO" "Game closed. Exiting."
                        exit 0
                    fi
                fi
            done
        else
            echo -e " \e[1;97;101m Restarting Sequence in 60 minutes... (Standalone Mode) \e[0m\n"
            while [ $(date +%s) -lt $target_time ]; do
                rem_sec=$((target_time - $(date +%s)))
                min=$(( rem_sec / 60 )); sec=$(( rem_sec % 60 ))
                printf " \e[1;97;101m Countdown: %02d:%02d \e[0m \e[0;90m(Press 'b' to browse data)\e[0m \033[0K\r" "$min" "$sec"
                read -t 1 -n 1 -s key 2>/dev/null || true
                if [[ "$key" == "b" || "$key" == "B" ]]; then
                    browse_database
                    echo -e "\n\e[0;36mResuming countdown...\e[0m"
                fi
            done 2>/dev/null
        fi
    fi
done
