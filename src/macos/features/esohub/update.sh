    ui_echo "\e[1m\e[97m [3/4] Updating ESO-Hub Prices & Uploading Scans \e[0m"
    ui_echo " \e[36mFetching latest ESO-Hub version data...\e[0m"
    
    EH_LAST_CHECK="$CURRENT_TIME"
    CONFIG_CHANGED=true
    EH_UPLOAD_COUNT=0
    EH_UPDATE_COUNT=0
    
    API_RESP=$(curl -s -X POST -H "User-Agent: ESOHubClient/1.0.9" \
        -d "user_token=&client_system=$SYS_ID&client_version=1.0.9&lang=en" \
        "https://data.eso-hub.com/v1/api/get-addon-versions" 2>/dev/null)
        
    ADDON_LINES=$(echo "$API_RESP" | awk '{ gsub(/\{"folder_name"/, "\n{\"folder_name\""); print }' | grep '"folder_name"')
    
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
                            touch "$DB_DIR/LTTC_History.db" 2>/dev/null
                            history_merge "$DB_DIR/LTTC_History.db" "$HISTORY_OUTPUT" > "$TEMP_DIR_ROOT/LTTC_History_Merged.tmp" 2>/dev/null
                            
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
                        if [ "$SV_NAME" = "EsoTradingHub.lua" ] && [ "$EH_EXTRACTED" = true ] && [ -z "$RAW_DATA" ]; then
                            cp -f "$SAVED_VAR_DIR/$SV_NAME" "$UP_SNAP" 2>/dev/null
                        elif [ "$SV_NAME" = "EsoHubScanner.lua" ] && ! grep -qE '\|H[0-9a-fA-F]*:item:[0-9]+' "$SAVED_VAR_DIR/$SV_NAME" 2>/dev/null; then
                            cp -f "$SAVED_VAR_DIR/$SV_NAME" "$UP_SNAP" 2>/dev/null
                        else
                            start_spinner "Uploading local scan data ($SV_NAME)..."
                            if curl -s -f -m 60 -A "ESOHubClient/1.0.9" \
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
                            cp -R ESOHub_Extracted/. "$ADDON_DIR/"
                            
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

