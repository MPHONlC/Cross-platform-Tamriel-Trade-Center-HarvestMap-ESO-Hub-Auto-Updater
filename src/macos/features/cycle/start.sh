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
                
                api_resp=$(curl -s -X POST -H "User-Agent: ESOHubClient/1.0.9" \
                    -d "user_token=&client_system=$SYS_ID&client_version=1.0.9&lang=en" \
                    "https://data.eso-hub.com/v1/api/get-addon-versions" 2>/dev/null)
                    
                addon_lines=$(echo "$api_resp" | awk '{ gsub(/\{"folder_name"/, "\n{\"folder_name\""); print }' \
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

