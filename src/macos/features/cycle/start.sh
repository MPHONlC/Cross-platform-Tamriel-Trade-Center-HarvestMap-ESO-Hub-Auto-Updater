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

