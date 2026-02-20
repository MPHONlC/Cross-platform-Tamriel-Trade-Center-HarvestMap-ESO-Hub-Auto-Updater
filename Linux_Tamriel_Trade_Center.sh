#!/bin/bash

# ==============================================================================
# Linux Tamriel Trade Center
# Created by @APHONIC (Updated)
# ==============================================================================

unset LD_PRELOAD
unset LD_LIBRARY_PATH

OS_TYPE=$(uname -s)
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

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

GAME_DIR=$(scan_game_dir)

# Save config globally AND locally in game dir
mkdir -p "$HOME/.config"
GLOBAL_CONFIG="$HOME/.config/lttc_updater.conf"

if [ -n "$GAME_DIR" ]; then
    CONFIG_FILE="$GAME_DIR/lttc_updater.conf"
    LAST_TIME_FILE="$GAME_DIR/lttc_last_sale.txt"
    LAST_DL_FILE="$GAME_DIR/lttc_last_download.txt"
    ESO_HUB_TRACKER="$GAME_DIR/lttc_esohub_tracker.txt"
else
    CONFIG_FILE="$GLOBAL_CONFIG"
    LAST_TIME_FILE="$HOME/.config/lttc_last_sale.txt"
    LAST_DL_FILE="$HOME/.config/lttc_last_download.txt"
    ESO_HUB_TRACKER="$HOME/.config/lttc_esohub_tracker.txt"
fi

# Config migration
if [ ! -f "$CONFIG_FILE" ] && [ -f "$GLOBAL_CONFIG" ]; then
    cp "$GLOBAL_CONFIG" "$CONFIG_FILE" 2>/dev/null
fi

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
elif [ -f "$GLOBAL_CONFIG" ]; then
    source "$GLOBAL_CONFIG"
fi

# Override configs if INSTALL_DIR was populated by the loaded config
if [ -n "$INSTALL_DIR" ]; then
    GAME_DIR="$INSTALL_DIR"
    CONFIG_FILE="$GAME_DIR/lttc_updater.conf"
    LAST_TIME_FILE="$GAME_DIR/lttc_last_sale.txt"
    LAST_DL_FILE="$GAME_DIR/lttc_last_download.txt"
    ESO_HUB_TRACKER="$GAME_DIR/lttc_esohub_tracker.txt"
fi

SILENT=false
AUTO_PATH=false
AUTO_SRV=""
AUTO_MODE=""
ADDON_DIR=""
SETUP_COMPLETE=false
HAS_ARGS=false

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

if [ "$#" -gt 0 ]; then HAS_ARGS=true; fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --silent) SILENT=true ;;
        --auto) AUTO_PATH=true ;;
        --na) AUTO_SRV="1" ;;
        --eu) AUTO_SRV="2" ;;
        --loop) AUTO_MODE="2" ;;
        --once) AUTO_MODE="1" ;;
        --addon-dir) shift; ADDON_DIR="$1" ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

if [ "$SILENT" = true ]; then exec >/dev/null 2>&1; fi

detect_terminal() {
    if [ "$OS_TYPE" = "Darwin" ]; then
        echo "Terminal"
    elif command -v alacritty &> /dev/null; then echo "alacritty -e"
    elif command -v konsole &> /dev/null; then echo "konsole -e"
    elif command -v gnome-terminal &> /dev/null; then echo "gnome-terminal --"
    elif command -v xfce4-terminal &> /dev/null; then echo "xfce4-terminal -e"
    elif command -v kitty &> /dev/null; then echo "kitty --"
    else echo "xterm -e"
    fi
}

auto_scan_addons() {
    declare -a addon_paths=()
    if [ "$OS_TYPE" = "Linux" ]; then
        addon_paths=(
            "$HOME/.local/share/Steam/steamapps/compatdata/306130/pfx/drive_c/users/steamuser/My Documents/Elder Scrolls Online/live/AddOns"
            "$HOME/.steam/steam/steamapps/compatdata/306130/pfx/drive_c/users/steamuser/My Documents/Elder Scrolls Online/live/AddOns"
            "$HOME/PortWINE/PortProton/drive_c/users/steamuser/My Documents/Elder Scrolls Online/live/AddOns"
            "$HOME/PortProton/prefixes/DEFAULT/drive_c/users/steamuser/My Documents/Elder Scrolls Online/live/AddOns/"
            "$HOME/.var/app/com.valvesoftware.Steam/.steam/root/steamapps/compatdata/306130/pfx/drive_c/users/steamuser/My Documents/Elder Scrolls Online/live/AddOns"
            "/var/lib/flatpak/app/com.valvesoftware.Steam/.steam/root/steamapps/compatdata/306130/pfx/drive_c/users/steamuser/My Documents/Elder Scrolls Online/live/AddOns"
            "$HOME/Games/elder-scrolls-online/drive_c/users/$USER/My Documents/Elder Scrolls Online/live/AddOns"
            "$HOME/Games/elder-scrolls-online/drive_c/users/steamuser/My Documents/Elder Scrolls Online/live/AddOns"
            "$HOME/.wine/drive_c/users/$USER/My Documents/Elder Scrolls Online/live/AddOns"
            "$HOME/.wine/drive_c/users/steamuser/My Documents/Elder Scrolls Online/live/AddOns"
            "$HOME/.var/app/com.usebottles.bottles/data/bottles/bottles/Elder-Scrolls-Online/drive_c/users/$USER/My Documents/Elder Scrolls Online/live/AddOns"
            "$HOME/Documents/Elder Scrolls Online/live/AddOns"
        )
    elif [ "$OS_TYPE" = "Darwin" ]; then
        addon_paths=(
            "$HOME/Documents/Elder Scrolls Online/live/AddOns"
        )
    fi

    for p in "${addon_paths[@]}"; do
        if [ -d "$p" ]; then
            echo "$p"
            return 0
        fi
    done
    
    if [ "$OS_TYPE" = "Linux" ]; then
        while IFS= read -r base_dir; do
            if [ -z "$base_dir" ]; then continue; fi
            for suffix in "/pfx/drive_c/users/steamuser/My Documents/Elder Scrolls Online/live/AddOns" "/drive_c/users/$USER/My Documents/Elder Scrolls Online/live/AddOns" "/live/AddOns"; do
                if [ -d "$base_dir$suffix" ]; then echo "$base_dir$suffix"; return 0; fi
            done
        done <<< "$(find "$HOME" /run/media /mnt /media -maxdepth 6 \( -type d -name "306130" -o -type d -name "Elder Scrolls Online" -o -type d -name "bottles" -o -type d -name "lutris" \) 2>/dev/null)"
    fi
    echo ""
}

run_setup() {
    clear
    echo -e "\n\e[0;33m--- Initial Setup & Configuration ---\e[0m"
    echo "Scanning for Game Directory..."
    INSTALL_DIR=$(scan_game_dir)
    
    if [ -n "$INSTALL_DIR" ]; then
        echo -e "\e[0;32m[+] Found Game Directory at:\e[0m $INSTALL_DIR"
        read -p "Is this the correct location? (y/n): " use_install
        if [[ ! "$use_install" =~ ^[Yy]$ ]]; then
            read -p "Please manually enter the full path to your game client folder: " INSTALL_DIR
        fi
    else
        echo -e "\e[0;31m[-] Failed to automatically locate game client.\e[0m"
        read -p "Please manually enter the full path to your game client folder: " INSTALL_DIR
    fi

    if [ "$CONFIG_FILE" != "$INSTALL_DIR/lttc_updater.conf" ]; then
        cp "$CONFIG_FILE" "$INSTALL_DIR/lttc_updater.conf" 2>/dev/null
        CONFIG_FILE="$INSTALL_DIR/lttc_updater.conf"
        LAST_TIME_FILE="$INSTALL_DIR/lttc_last_sale.txt"
        LAST_DL_FILE="$INSTALL_DIR/lttc_last_download.txt"
        ESO_HUB_TRACKER="$INSTALL_DIR/lttc_esohub_tracker.txt"
    fi

    if [ "$CURRENT_DIR" == "$INSTALL_DIR" ]; then
        echo -e "\e[0;36m-> Script is already running from the game directory. Skipping copy step.\e[0m"
    elif [ -f "$INSTALL_DIR/$SCRIPT_NAME" ]; then
        echo -e "\e[0;36m-> Script already exists in the game directory. Skipping copy step.\e[0m"
    else
        read -p "Do you want to copy this script to your game directory ($INSTALL_DIR) for Steam Launch Options? (y/n): " copy_script
        if [[ "$copy_script" =~ ^[Yy]$ ]]; then
            cp "$CURRENT_DIR/$SCRIPT_NAME" "$INSTALL_DIR/$SCRIPT_NAME"
            chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
            echo -e "\e[0;32m[+] Script successfully copied to:\e[0m $INSTALL_DIR"
        fi
    fi

    echo -e "\n\e[0;33m1. Which server do you play on? (For TTC Pricing)\e[0m"
    echo "1) North America (NA)"
    echo "2) Europe (EU)"
    read -p "Choice [1-2]: " AUTO_SRV

    echo -e "\n\e[0;33m2. Do you want the terminal to be visible when launching via Steam?\e[0m"
    echo "1) Show Terminal (Verbose output)"
    echo "2) Hide Terminal (Silent background mode)"
    read -p "Choice [1-2]: " term_choice
    [ "$term_choice" == "2" ] && SILENT=true || SILENT=false

    echo -e "\n\e[0;33m3. How should the script run during gameplay?\e[0m"
    echo "1) Run once and close immediately"
    echo "2) Loop continuously (Every 60 minutes to avoid rate-limit)"
    read -p "Choice [1-2]: " AUTO_MODE

    echo -e "\n\e[0;33m4. Addon Folder Location\e[0m"
    echo "Scanning default locations and drives for Addons folder..."
    FOUND_ADDONS=$(auto_scan_addons)
    
    if [ -n "$FOUND_ADDONS" ]; then
        echo -e "\e[0;32m[+] Found Addons at:\e[0m $FOUND_ADDONS"
        read -p "Is this the correct location? (y/n): " use_found
        if [[ "$use_found" =~ ^[Yy]$ ]]; then
            ADDON_DIR="$FOUND_ADDONS"
        else
            read -p "Enter full custom path to AddOns: " ADDON_DIR
        fi
    else
        echo -e "\e[0;31m[-] Could not find AddOns automatically.\e[0m"
        read -p "Enter full custom path to AddOns: " ADDON_DIR
    fi

    echo "INSTALL_DIR=\"$INSTALL_DIR\"" > "$CONFIG_FILE"
    echo "AUTO_SRV=\"$AUTO_SRV\"" >> "$CONFIG_FILE"
    echo "SILENT=$SILENT" >> "$CONFIG_FILE"
    echo "AUTO_MODE=\"$AUTO_MODE\"" >> "$CONFIG_FILE"
    echo "ADDON_DIR=\"$ADDON_DIR\"" >> "$CONFIG_FILE"
    echo "SETUP_COMPLETE=true" >> "$CONFIG_FILE"
    
    cp "$CONFIG_FILE" "$GLOBAL_CONFIG" 2>/dev/null

    echo -e "\n\e[0;33m5. Desktop Shortcut\e[0m"
    read -p "Create a desktop shortcut? (y/n): " make_shortcut
    
    SHORTCUT_SRV_FLAG="--na"
    [ "$AUTO_SRV" == "2" ] && SHORTCUT_SRV_FLAG="--eu"
    SILENT_FLAG=""
    [ "$SILENT" == true ] && SILENT_FLAG="--silent"
    LOOP_FLAG="--once"
    [ "$AUTO_MODE" == "2" ] && LOOP_FLAG="--loop"

    if [[ "$make_shortcut" =~ ^[Yy]$ ]]; then
        ICON_PATH="$INSTALL_DIR/ttc_icon.ico"
        echo -e " -> Downloading TTC favicon from https://us.tamrieltradecentre.com/favicon.ico"
        curl -s -L -o "$ICON_PATH" "https://us.tamrieltradecentre.com/favicon.ico"

        if [[ "$OS_TYPE" == "Linux" ]]; then
            DESKTOP_DIR=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")
            mkdir -p "$DESKTOP_DIR"
            DESKTOP_FILE="$DESKTOP_DIR/Linux_Tamriel_Trade_Center.desktop"
            APP_DIR="$HOME/.local/share/applications"
            
            cat <<EOF > "$DESKTOP_FILE"
[Desktop Entry]
Version=1.0
Name=Linux Tamriel Trade Center
Comment=TTC/ESO-Hub/HarvestMap Data Updater
Exec=bash -c '"$INSTALL_DIR/$SCRIPT_NAME" $SILENT_FLAG $SHORTCUT_SRV_FLAG $LOOP_FLAG --addon-dir "$ADDON_DIR"'
Icon=$ICON_PATH
Terminal=$([ "$SILENT" = true ] && echo "false" || echo "true")
Type=Application
Categories=Game;Utility;
EOF
            chmod +x "$DESKTOP_FILE"
            mkdir -p "$APP_DIR"
            cp "$DESKTOP_FILE" "$APP_DIR/"
            echo -e "\e[0;32m[+] Linux desktop shortcut installed to Desktop and Application Launcher.\e[0m"
        elif [[ "$OS_TYPE" == "Darwin" ]]; then
            echo -e "\e[0;33m[!] Automatic macOS App creation is not fully supported in this bash script yet.\e[0m"
        fi
    fi

    TERM_CMD=$(detect_terminal)
    echo -e "\n\e[0;92m================ SETUP COMPLETE ================\e[0m"
    echo -e "To run this automatically alongside your game, copy this string into your \e[1mSteam Launch Options\e[0m:\n"
    
    if [ "$SILENT" = true ]; then
        LAUNCH_CMD="\"$INSTALL_DIR/$SCRIPT_NAME\" $SILENT_FLAG $SHORTCUT_SRV_FLAG $LOOP_FLAG --addon-dir \"$ADDON_DIR\" & %command%"
        echo -e "\e[0;104m $LAUNCH_CMD \e[0m\n"
    else
        if [ "$OS_TYPE" = "Darwin" ]; then
            LAUNCH_CMD="osascript -e 'tell application \"Terminal\" to do script \"\\\"$INSTALL_DIR/$SCRIPT_NAME\\\" $SHORTCUT_SRV_FLAG $LOOP_FLAG --addon-dir \\\"$ADDON_DIR\\\"\"' & %command%"
            echo -e "\e[0;104m $LAUNCH_CMD \e[0m\n"
        else
            LAUNCH_CMD="$TERM_CMD \"$INSTALL_DIR/$SCRIPT_NAME\" $SHORTCUT_SRV_FLAG $LOOP_FLAG --addon-dir \"$ADDON_DIR\" & %command%"
            echo -e "\e[0;104m $LAUNCH_CMD \e[0m\n"
            echo -e "\e[0;33m(Note: Auto-detected your terminal as '$TERM_CMD'. If it doesn't open, change it to your preferred terminal emulator).\e[0m\n"
        fi
    fi
    
    echo -e "\e[0;33m6. Steam Launch Options\e[0m"
    echo "Would you like this script to automatically inject the Launch Command into your Steam configuration?"
    echo "(WARNING: Steam MUST be closed to do this. We can close it for you.)"
    read -p "Apply automatically? (y/n): " auto_steam
    
    if [[ "$auto_steam" =~ ^[Yy]$ ]]; then
        STEAM_PID=$(pgrep -x "steam" || pgrep -x "Steam" || pgrep -x "steam_osx" || pgrep -f "com.valvesoftware.Steam" | head -n 1)
        STEAM_CMD="steam"
        if [ -n "$STEAM_PID" ]; then
            echo -e "\e[0;33m[!] Steam is running. Closing Steam to safely inject options...\e[0m"
            STEAM_EXEC=$(ps -p $STEAM_PID -o args= | cut -d' ' -f1)
            if [[ "$STEAM_EXEC" == *"flatpak"* ]] || pgrep -f "flatpak run com.valvesoftware.Steam" > /dev/null 2>&1; then
                STEAM_CMD="flatpak run com.valvesoftware.Steam"
            fi
            
            pkill -x steam > /dev/null 2>&1
            pkill -x Steam > /dev/null 2>&1
            pkill -x steam_osx > /dev/null 2>&1
            pkill -f "com.valvesoftware.Steam" > /dev/null 2>&1
            sleep 5
        fi
        
        export LAUNCH_STR="$LAUNCH_CMD"
        for conf in "$HOME/.steam/steam/userdata"/*/config/localconfig.vdf \
                    "$HOME/.local/share/Steam/userdata"/*/config/localconfig.vdf \
                    "/var/lib/flatpak/app/com.valvesoftware.Steam/.steam/root/userdata"/*/config/localconfig.vdf \
                    "$HOME/Library/Application Support/Steam/userdata"/*/config/localconfig.vdf; do
            if [ -f "$conf" ]; then
                echo -e "\e[0;36m-> Injecting into $conf...\e[0m"
                perl -pi.bak -e 'BEGIN{undef $/;} my $ls=$ENV{LAUNCH_STR}; $ls=~s/"/\\"/g; if (/"306130"\s*\{/) { if (/"306130"\s*\{[^}]*"LaunchOptions"\s*"[^"]*"/) { s/("306130"\s*\{[^}]*)"LaunchOptions"\s*"[^"]*"/$1"LaunchOptions"\t\t"$ls"/s; } else { s/("306130"\s*\{)/$1\n\t\t\t\t"LaunchOptions"\t\t"$ls"/s; } } else { s/("apps"\s*\{)/$1\n\t\t\t"306130"\n\t\t\t{\n\t\t\t\t"LaunchOptions"\t\t"$ls"\n\t\t\t}/s; }' "$conf" 2>/dev/null
                echo -e "\e[0;32m[+] Successfully injected Launch Options into Steam!\e[0m"
            fi
        done
        
        echo -e "\e[0;33m[!] Restarting Steam...\e[0m"
        if [ "$OS_TYPE" = "Darwin" ]; then
            open -a Steam
        else
            nohup $STEAM_CMD >/dev/null 2>&1 &
        fi
    fi
    
    read -p "Press Enter to start the updater now..."
}

# Ensure script and local config exist in game dir, otherwise force setup to fix it
[ -z "$INSTALL_DIR" ] && INSTALL_DIR="$GAME_DIR"
INSTALLED_SCRIPT="$INSTALL_DIR/$SCRIPT_NAME"
INSTALLED_CONFIG="$INSTALL_DIR/lttc_updater.conf"

if [ "$SETUP_COMPLETE" = "true" ] && [ "$HAS_ARGS" = false ]; then
    if [ -f "$INSTALLED_SCRIPT" ] && [ -f "$INSTALLED_CONFIG" ]; then
        clear
        echo -e "\e[0;32m[+] Configuration found! Using saved settings.\e[0m"
        echo -e "\e[0;36m-> Press 'y' to re-run setup, or wait 5 seconds to continue automatically...\e[0m\n"
        read -t 5 -p "Setup done, do you want to re-run setup? (y/N): " rerun_setup
        if [[ "$rerun_setup" =~ ^[Yy]$ ]]; then
            run_setup
        fi
    else
        run_setup
    fi
elif [ "$SETUP_COMPLETE" != "true" ] && [ "$HAS_ARGS" = false ]; then
    run_setup
fi

[ "$AUTO_SRV" == "1" ] && TTC_DOMAIN="us.tamrieltradecentre.com" || TTC_DOMAIN="eu.tamrieltradecentre.com"
TTC_URL="https://$TTC_DOMAIN/download/PriceTable"
SAVED_VAR_DIR="$(dirname "$ADDON_DIR")/SavedVariables"
TEMP_DIR="$HOME/Downloads/Linux_Tamriel_Trade_Center_Temp"
ESO_HUB_TRACKER="$INSTALL_DIR/lttc_esohub_tracker.txt"

# user agents
USER_AGENTS=(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:123.0) Gecko/20100101 Firefox/123.0"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:123.0) Gecko/20100101 Firefox/123.0"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 Edg/122.0.0.0"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3.1 Safari/605.1.15"
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
    "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:123.0) Gecko/20100101 Firefox/123.0"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36 OPR/107.0.0.0"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36 OPR/107.0.0.0"
)

while true; do
    # Shuffle UAs for random order per loop
    shuffled_uas=("${USER_AGENTS[@]}")
    for i in "${!shuffled_uas[@]}"; do
        j=$((RANDOM % ${#shuffled_uas[@]}))
        temp="${shuffled_uas[$i]}"
        shuffled_uas[$i]="${shuffled_uas[$j]}"
        shuffled_uas[$j]="$temp"
    done
    RAND_UA="${shuffled_uas[0]}"

    if [ "$SILENT" = false ]; then
        clear
        echo -e "\e[0;92m==================================================\e[0m"
        echo -e "\e[1m\e[0;94m           Linux Tamriel Trade Center\e[0m"
        echo -e "\e[0;92m==================================================\e[0m\n"
        echo -e "\e[0;35mTarget AddOn Directory: $ADDON_DIR\e[0m\n"
    fi
    
    mkdir -p "$TEMP_DIR" && cd "$TEMP_DIR" || exit

    # UPLOAD TTC DATA
    [ "$SILENT" = false ] && echo -e "\e[0;104m\e[1m\e[0;97m [1/4] Uploading your Local TTC Data to TTC Server \e[0m"
    if [ -f "$SAVED_VAR_DIR/TamrielTradeCentre.lua" ]; then
        if [ "$SILENT" = false ]; then
            echo -e "\e[0;36mExtracting recent sales data from Lua (Showing up to 30 recent entries)...\e[0m"
            [ ! -f "$LAST_TIME_FILE" ] && echo "0" > "$LAST_TIME_FILE"
            LAST_TIME=$(cat "$LAST_TIME_FILE" 2>/dev/null)
            [ -z "$LAST_TIME" ] && LAST_TIME="0"
            
            AWK_OUT=$(awk -v last_time="$LAST_TIME" '
                BEGIN { max_time = last_time; count = 0 }
                /\["Amount"\]/ { match($0, /[0-9]+/); amt=substr($0, RSTART, RLENGTH) }
                /\["QualityID"\]/ { match($0, /[0-9]+/); qual=substr($0, RSTART, RLENGTH) }
                /\["SaleTime"\]/ { match($0, /[0-9]+/); stime=substr($0, RSTART, RLENGTH) }
                /\["TotalPrice"\]/ { match($0, /[0-9]+/); price=substr($0, RSTART, RLENGTH) }
                /\["Name"\]/ { sub(/.*\["Name"\]\s*=\s*"/, ""); sub(/",?\s*$/, ""); name=$0 }
                /\}/ { 
                    if (name != "" && price != "") {
                        if (stime + 0 > max_time) { max_time = stime }
                        if (stime + 0 > last_time) {
                            if(qual==0) c="\033[90m";
                            else if(qual==1) c="\033[97m";
                            else if(qual==2) c="\033[32m";
                            else if(qual==3) c="\033[36m";
                            else if(qual==4) c="\033[35m";
                            else if(qual==5) c="\033[33m";
                            else if(qual==6) c="\033[38;5;214m";
                            else c="\033[0m";
                            lines[count++] = " for \033[32m" price "\033[33mgold\033[0m - \033[32m" amt "x\033[0m " c name "\033[0m"
                        }
                        name=""; price=""; amt=""; qual=""; stime="";
                    }
                }
                END {
                    start = count > 30 ? count - 30 : 0
                    for (i = start; i < count; i++) { print lines[i] }
                    print "MAX_TIME:" max_time
                }
            ' "$SAVED_VAR_DIR/TamrielTradeCentre.lua")
            
            NEXT_TIME=$(echo "$AWK_OUT" | grep "^MAX_TIME:" | cut -d':' -f2)
            DATA_OUT=$(echo "$AWK_OUT" | grep -v "^MAX_TIME:")
            
            if [ -n "$DATA_OUT" ]; then
                echo "$DATA_OUT"
            else
                echo -e " \e[90mNo new sales found since last upload.\e[0m"
            fi
            
            if [ -n "$NEXT_TIME" ] && [ "$NEXT_TIME" != "$LAST_TIME" ]; then
                echo "$NEXT_TIME" > "$LAST_TIME_FILE"
            fi
            
            echo ""
            echo -e "\e[0;36mUploading to:\e[0m https://$TTC_DOMAIN/pc/Trade/WebClient/Upload"
        fi
        
        curl -s -A "$RAND_UA" \
             -H "Accept: text/html,application/xhtml+xml,application/xml" \
             -F "SavedVarFileInput=@$SAVED_VAR_DIR/TamrielTradeCentre.lua" "https://$TTC_DOMAIN/pc/Trade/WebClient/Upload" > /dev/null 2>&1
        [ "$SILENT" = false ] && echo -e "\e[0;92m[+] Upload finished.\e[0m\n"
    else
        [ "$SILENT" = false ] && echo -e "\e[0;33m[-] No TamrielTradeCentre.lua found. Skipping upload.\e[0m\n"
    fi

    # DOWNLOAD TTC DATA
    CURRENT_TIME=$(date +%s)
    LAST_DL_TIME=0
    if [ -f "$LAST_DL_FILE" ]; then
        LAST_DL_TIME=$(cat "$LAST_DL_FILE" 2>/dev/null | grep -o '[0-9]*' | head -1)
        [ -z "$LAST_DL_TIME" ] && LAST_DL_TIME=0
    fi
    TIME_DIFF=$((CURRENT_TIME - LAST_DL_TIME))

    if [ "$TIME_DIFF" -lt 3600 ]; then
        WAIT_MINS=$(( (3600 - TIME_DIFF) / 60 ))
        [ "$SILENT" = false ] && echo -e "\e[0;104m\e[1m\e[0;97m [2/4] Updating your Local TTC Data (SKIPPED) \e[0m"
        [ "$SILENT" = false ] && echo -e "\e[0;33mAlready downloaded within the last hour. Please wait $WAIT_MINS more minutes to avoid spam.\e[0m\n"
    else
        [ "$SILENT" = false ] && echo -e "\e[0;104m\e[1m\e[0;97m [2/4] Updating your Local TTC Data \e[0m"
        [ "$SILENT" = false ] && echo -e "\e[0;36mDownloading from:\e[0m $TTC_URL"
        [ "$SILENT" = false ] && echo -e "\e[0;36mDropping zip temporarily to:\e[0m $TEMP_DIR/Linux_Tamriel_Trade_Center-TTC-data.zip"
        
        SUCCESS=false
        for UA in "${shuffled_uas[@]}"; do
            [ "$SILENT" = false ] && echo -e "\e[0;36mAttempting download with random User-Agent...\e[0m"
            curl -H "User-Agent: $UA" \
                 -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8" \
                 -H "Accept-Language: en-US,en;q=0.5" \
                 -H "Connection: keep-alive" \
                 -H "Upgrade-Insecure-Requests: 1" \
                 -H "Sec-Fetch-Dest: document" \
                 -H "Sec-Fetch-Mode: navigate" \
                 -H "Sec-Fetch-Site: none" \
                 -H "Sec-Fetch-User: ?1" \
                 -# -L -o Linux_Tamriel_Trade_Center-TTC-data.zip "$TTC_URL"
            
            if unzip -t Linux_Tamriel_Trade_Center-TTC-data.zip > /dev/null 2>&1; then
                SUCCESS=true
                break
            else
                [ "$SILENT" = false ] && echo -e "\e[0;33m[-] Download failed or blocked. Trying another User-Agent...\e[0m"
            fi
        done

        echo "$CURRENT_TIME" > "$LAST_DL_FILE"

        if [ "$SUCCESS" = true ]; then
            [ "$SILENT" = false ] && echo -e "\e[0;36mExtracting archive to:\e[0m $TEMP_DIR/TTC_Extracted/"
            unzip -o Linux_Tamriel_Trade_Center-TTC-data.zip -d TTC_Extracted > /dev/null
            [ "$SILENT" = false ] && echo -e "\e[0;36mCopying files to:\e[0m $ADDON_DIR/TamrielTradeCentre/"
            mkdir -p "$ADDON_DIR/TamrielTradeCentre"
            rsync -avh --progress TTC_Extracted/ "$ADDON_DIR/TamrielTradeCentre/" > /dev/null
            [ "$SILENT" = false ] && echo -e "\e[0;92m[+] TTC Data Successfully Updated.\e[0m\n"
        else
            [ "$SILENT" = false ] && echo -e "\e[0;31m[!] Error: All User-Agents failed. TTC Data download was blocked by the server, Please try again later.\e[0m\n"
        fi
    fi

    # ESO HUB
    DAY_OF_WEEK=$(date +%u); HOUR=$(date +%H); WEEK_NUM=$(date +%V); YEAR=$(date +%Y)
    if [ "$DAY_OF_WEEK" -eq 1 ] && [ "$HOUR" -lt 12 ]; then WEEK_NUM=$(( 10#$WEEK_NUM - 1 )); fi
    CURRENT_ESO_HUB_WEEK="${YEAR}-W${WEEK_NUM}"
    LAST_ESO_HUB_WEEK=""
    [ -f "$ESO_HUB_TRACKER" ] && LAST_ESO_HUB_WEEK=$(cat "$ESO_HUB_TRACKER" 2>/dev/null)

    if [ "$CURRENT_ESO_HUB_WEEK" != "$LAST_ESO_HUB_WEEK" ]; then
        [ "$SILENT" = false ] && echo -e "\e[0;104m\e[1m\e[0;97m [3/4] Updating ESO-Hub Prices \e[0m"
        [ "$SILENT" = false ] && echo -e "\e[0;36mDownloading from:\e[0m https://www.esoui.com/downloads/dl4095/"
        [ "$SILENT" = false ] && echo -e "\e[0;36mDropping zip temporarily to:\e[0m $TEMP_DIR/Linux_Tamriel_Trade_Center-ESOHUb-data.zip"
        
        HUB_SUCCESS=false
        for UA in "${shuffled_uas[@]}"; do
            curl -# -L -A "$UA" -o Linux_Tamriel_Trade_Center-ESOHUb-data.zip "https://www.esoui.com/downloads/dl4095/"
            
            if unzip -t Linux_Tamriel_Trade_Center-ESOHUb-data.zip > /dev/null 2>&1; then
                HUB_SUCCESS=true
                break
            else
                [ "$SILENT" = false ] && echo -e "\e[0;33m[-] Download failed or corrupted. Trying another User-Agent...\e[0m"
            fi
        done

        if [ "$HUB_SUCCESS" = true ]; then
            [ "$SILENT" = false ] && echo -e "\e[0;36mExtracting archive to:\e[0m $TEMP_DIR/ESOHub_Extracted/"
            unzip -o Linux_Tamriel_Trade_Center-ESOHUb-data.zip -d ESOHub_Extracted > /dev/null
            [ "$SILENT" = false ] && echo -e "\e[0;36mCopying files to:\e[0m $ADDON_DIR/"
            rsync -avh --progress ESOHub_Extracted/ "$ADDON_DIR/" > /dev/null
            echo "$CURRENT_ESO_HUB_WEEK" > "$ESO_HUB_TRACKER"
            [ "$SILENT" = false ] && echo -e "\e[0;92m[+] ESO-Hub Prices Successfully Updated.\e[0m\n"
        else
            [ "$SILENT" = false ] && echo -e "\e[0;31m[!] Error: All User-Agents failed. ESO-Hub Prices download failed or was corrupted.\e[0m\n"
        fi
    else
        [ "$SILENT" = false ] && echo -e "\e[0;104m\e[1m\e[0;97m [3/4] Updating ESO-Hub Prices (SKIPPED) \e[0m"
        [ "$SILENT" = false ] && echo -e "\e[0;33mAlready matches ESOUI schedule. Next check after Monday 12:00 PM.\e[0m\n"
    fi

    # HARVESTMAP
    HM_DIR="$ADDON_DIR/HarvestMapData"
    EMPTY_FILE="$HM_DIR/Main/emptyTable.lua"
    
    if [[ -d "$HM_DIR" ]]; then
        [ "$SILENT" = false ] && echo -e "\e[0;104m\e[1m\e[0;97m [4/4] Updating HarvestMap Data \e[0m"
        mkdir -p "$SAVED_VAR_DIR"
        for zone in AD EP DC DLC NF; do
            fn="HarvestMap${zone}.lua"
            svfn1="$SAVED_VAR_DIR/$fn"
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
            [ "$SILENT" = false ] && echo -e "\e[0;36mDownloading database chunk to:\e[0m $HM_DIR/Modules/HarvestMap${zone}/$fn"
            curl -f -s -L -A "$RAND_UA" -d @"$svfn2" -o "$HM_DIR/Modules/HarvestMap${zone}/$fn" "http://harvestmap.binaryvector.net:8081"
        done
        [ "$SILENT" = false ] && echo -e "\n\e[0;92m[+] HarvestMap Data Successfully Updated.\e[0m\n"
    else
        [ "$SILENT" = false ] && echo -e "\e[0;104m\e[1m\e[0;97m [4/4] Updating HarvestMap Data (SKIPPED) \e[0m"
        [ "$SILENT" = false ] && echo -e "\e[0;31m[!] HarvestMapData folder not found in: $ADDON_DIR. Skipping...\e[0m\n"
    fi

    # Cleanup
    [ "$SILENT" = false ] && echo -e "\e[0;33mCleaning up temporary files...\e[0m"
    cd "$HOME" || exit
    [ "$SILENT" = false ] && echo -e "\e[0;36mDeleting Temp Directory and all downloaded files at:\e[0m $TEMP_DIR"
    rm -rvf "$TEMP_DIR" > /dev/null
    [ "$SILENT" = false ] && echo -e "\e[0;92m[+] Cleanup Complete.\e[0m\n"

    if [ "$AUTO_MODE" == "1" ]; then exit 0; fi

    if [ "$SILENT" = true ]; then
        for (( i=0; i<360; i++ )); do
            sleep 10
            if ! pgrep -fi "eso64|zos|steam_app_306130|eso\.app|eso" > /dev/null 2>&1; then exit 0; fi
        done
    else
        echo -e "\e[0;101m Restarting Sequence in 60 minutes... \e[0m\n"
        for (( i=3600; i>0; i-- )); do
            min=$(( i / 60 )); sec=$(( i % 60 ))
            echo -ne "\e[0;101m\e[1m\e[0;94m Countdown: $min:$sec\033[0K\r\e[0m"
            if (( i % 5 == 0 )); then
                if ! pgrep -fi "eso64|zos|steam_app_306130|eso\.app|eso" > /dev/null 2>&1; then
                    echo -e "\n\n\e[0;33mGame closed. Terminating updater...\e[0m"
                    sleep 2
                    exit 0
                fi
            fi
            sleep 1
        done
    fi
done
