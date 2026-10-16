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
                        touch "$DB_DIR/LTTC_History.db" 2>/dev/null
                        history_merge "$DB_DIR/LTTC_History.db" "$HISTORY_OUTPUT" > "$TEMP_DIR_ROOT/LTTC_History_Merged.tmp" 2>/dev/null
                        
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
                            TTC_NA_VERSION="$s_ver_na"
                        fi
                        
                        if [ "$has_eu" = true ]; then
                            cp -R TTC_Extracted_EU/. "$ADDON_DIR/TamrielTradeCentre/"
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

