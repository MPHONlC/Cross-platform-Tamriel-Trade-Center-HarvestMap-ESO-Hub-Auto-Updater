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

    echo -e "\n\e[0;33m9. Keep Your Other Add-Ons Up To Date \e[0;32m(Optional)\e[0m"
    echo -e "\e[0;32mAlso check ESOUI for newer versions of the add-ons and libraries in your AddOns folder and install them?\e[0m"
    echo -e "\e[0;90m(Checks every 6 hours, keeps the previous version in $TARGET_DIR/Backups/AddOns, skips linked folders)\e[0m"
    echo -e "1) Yes"
    echo -e "2) No \e[0;32m(Default)\e[0m"
    read -p $'\e[0;34mChoice [1-2]: \e[0m' addon_update_choice
    [ "$addon_update_choice" == "1" ] && ENABLE_ADDON_UPDATES=true || ENABLE_ADDON_UPDATES=false

    SETUP_COMPLETE=true; write_lttc_config

    echo -e "\n\e[0;33m10. Desktop Shortcut\e[0m"
    DESKTOP_DIR=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")
    APP_DIR="$HOME/.local/share/applications"
    echo -e "Creates a shortcut at \e[0;35m$DESKTOP_DIR\e[0m & \e[0;35m$APP_DIR\e[0m"
    read -p "Create a desktop shortcut? (Y/n): " make_shortcut
    [ -z "$make_shortcut" ] && make_shortcut="y"
    
    SHORTCUT_SRV_FLAG="--na"
    [ "$AUTO_SRV" == "2" ] && SHORTCUT_SRV_FLAG="--eu"
    [ "$AUTO_SRV" == "3" ] && SHORTCUT_SRV_FLAG="--both"
    LOOP_FLAG="--once"
    [ "$AUTO_MODE" == "2" ] && LOOP_FLAG="--loop"

    if [[ "$make_shortcut" =~ ^[Yy]$ ]]; then
        ICON_PATH="$TARGET_DIR/lttc_icon.png"
        if curl -s -f -L -o "$ICON_PATH.tmp" "$(_d a04556abef9f19a082f8bdeda364aa1f6d6307d88907e5302e1d7ffd60f34d2805fe8f2b740a9843d31629110bde0d3ac8cd733fea7a5492cd5ddb5ec614ab8b2525107ab8805b8c55b77e66766056d62a37d79858f8a7efadec099c79551be5855077cf13a8431fb418dec6d6c2cc329e927de3a934024c0f249b1a9a92674427df8c327f4a 167)"; then
            mv -f "$ICON_PATH.tmp" "$ICON_PATH"
        fi
        rm -f "$ICON_PATH.tmp" 2>/dev/null
        
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
Comment=Cross-Platform Auto-Updater for TTC, HarvestMap, ESO-Hub & ESOUI - Created by @APHONIC
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
    else
        DESKTOP_DIR=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")
        APP_DIR="$HOME/.local/share/applications"
        
        rm -f "$HOME/Desktop/"*Tamriel_Trade_Center*.desktop \
              "$HOME/.local/share/applications/"*Tamriel_Trade_Center*.desktop \
              "$DESKTOP_DIR/"*Tamriel_Trade_Center*.desktop \
              "$APP_DIR/"*Tamriel_Trade_Center*.desktop 2>/dev/null
        update-desktop-database "$APP_DIR" 2>/dev/null || true
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
        LAUNCH_CMD="env -u LD_PRELOAD -u STEAM_LD_PRELOAD $TERM_CMD '$TARGET_DIR/$SCRIPT_NAME' $SHORTCUT_SRV_FLAG $LOOP_FLAG --steam & %command%"
        echo -e "\e[0;104m $LAUNCH_CMD \e[0m\n"
        echo -e "\e[0;33m(Note: Auto-detected your terminal as '$TERM_CMD').\e[0m\n"
    fi
    
    echo -e "\e[0;33m11. Steam Launch Options\e[0m"
    echo -e "\e[0;32mAutomatically inject the Launch Command into Steam?\e[0m"
    echo -e "\e[31m(WARNING: Steam MUST be closed to do this.)\e[0m"
    read -p "Apply automatically? (Y/n): " auto_steam
    [ -z "$auto_steam" ] && auto_steam="y"
    
    if [[ "$auto_steam" =~ ^[Yy]$ ]] && ! command -v perl >/dev/null 2>&1; then
        echo -e "\e[0;33m[!] perl is not installed, so the launch options can't be added for you. Paste the line above into Steam > ESO > Properties > Launch Options.\e[0m"
        auto_steam="n"
    fi
    if [[ "$auto_steam" =~ ^[Yy]$ ]]; then
        STEAM_CMD="steam"
        if ! command -v steam >/dev/null 2>&1 && command -v flatpak >/dev/null 2>&1 && flatpak list | grep -qi com.valvesoftware.Steam; then
            STEAM_CMD="flatpak run com.valvesoftware.Steam"
        fi
        
        STEAM_PIDS=$(pgrep -x "steam|Steam" || pgrep -f "com.valvesoftware.Steam")
        if [ -n "$STEAM_PIDS" ]; then
            ui_echo "\e[0;33m[!] Steam is running. Closing Steam to inject options...\e[0m"
            if pgrep -f "flatpak run com.valvesoftware.Steam" > /dev/null 2>&1; then
                STEAM_CMD="flatpak run com.valvesoftware.Steam"
            fi
            pkill -x "steam|Steam" > /dev/null 2>&1
            pkill -f "com.valvesoftware.Steam" > /dev/null 2>&1
            read -t 5 -s 2>/dev/null || true
        fi
        
        [ "$IS_GAMESCOPE" = true ] && export LAUNCH_STR="$DETACHED_CMD" || export LAUNCH_STR="$LAUNCH_CMD"
        [ "$SILENT" = true ] && export LAUNCH_STR="$DETACHED_CMD"

        BACKUP_DIR="$TARGET_DIR/Backups"; mkdir -p "$BACKUP_DIR"
        
        local seen_confs=" " real_conf
        for conf in "$HOME/.steam/steam/userdata"/*/config/localconfig.vdf \
                    "$HOME/.local/share/Steam/userdata"/*/config/localconfig.vdf \
                    "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/userdata"/*/config/localconfig.vdf \
                    "/var/lib/flatpak/app/com.valvesoftware.Steam/.steam/root/userdata"/*/config/localconfig.vdf; do
            if [ -f "$conf" ]; then
                real_conf=$(readlink -f "$conf" 2>/dev/null || printf '%s' "$conf")
                case "$seen_confs" in *" $real_conf "*) continue ;; esac
                seen_confs="$seen_confs$real_conf "
                TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
                STEAM_ID=$(basename "$(dirname "$(dirname "$conf")")")
                BACKUP_FILE="$BACKUP_DIR/localconfig_${STEAM_ID}_${TIMESTAMP}.vdf"
                cp "$conf" "$BACKUP_FILE" 2>/dev/null
                ui_echo "\e[0;36m-> Backed up Steam config to: $BACKUP_FILE\e[0m"
                ui_echo "\e[0;36m-> Injecting Launch Options into ESO config (AppID: 306130)...\e[0m"
                
                if perl -pi.bak -e '
                    BEGIN{undef $/;} 
                    sub lttc_merge { my ($cur, $ls) = @_; (my $pfx = $ls) =~ s{\s*%command%\s*$}{}i; my @keep; for my $s (split m{\s+&(?=\s|$)}, $cur) { $s =~ s{\s*(?:(?:nohup\s+)?env\s+-u\s+LD_PRELOAD|nohup\s+bash\s+-c)\b.*Tamriel_Trade_Center.*$}{}s; $s =~ s{^\s+|\s+$}{}g; push @keep, $s if length $s; } my $n = grep { m{%command%}i } @keep; @keep = grep { !(m{^%command%$}i && $n-- > 1) } @keep; my $rest = join " & ", @keep; return $rest eq "" ? "$pfx %command%" : ($rest =~ m{%command%}i ? "$pfx $rest" : "$pfx %command% $rest"); }
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
        
        if [[ "$STEAM_CMD" == *"flatpak"* ]]; then
            nohup flatpak run com.valvesoftware.Steam "steam://open/main" </dev/null >/dev/null 2>&1 &
        else
            nohup steam "steam://open/main" </dev/null >/dev/null 2>&1 &
        fi
        
        ui_echo "\e[0;36m-> Verifying Steam launch...\e[0m"
        steam_started=false
        for i in {1..10}; do
            if pgrep -x "steam|Steam" > /dev/null 2>&1 || pgrep -f "com.valvesoftware.Steam" > /dev/null 2>&1; then
                steam_started=true; break
            fi
            sleep 1
        done
        
        if [ "$steam_started" = true ]; then
            ui_echo "\e[0;32m[+] Steam launched successfully.\e[0m"
        else
            ui_echo "\e[0;31m[-] Steam launch timed out. Attempting fallback...\e[0m"
            
            if command -v xdg-open >/dev/null 2>&1; then
                xdg-open "steam://open/main" >/dev/null 2>&1
            elif command -v setsid >/dev/null 2>&1; then
                setsid $STEAM_CMD "steam://open/main" </dev/null >/dev/null 2>&1 &
            else
                (nohup $STEAM_CMD "steam://open/main" </dev/null >/dev/null 2>&1 &)
            fi
            
            sleep 3
            if pgrep -x "steam|Steam" > /dev/null 2>&1 || pgrep -f "com.valvesoftware.Steam" > /dev/null 2>&1; then
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

