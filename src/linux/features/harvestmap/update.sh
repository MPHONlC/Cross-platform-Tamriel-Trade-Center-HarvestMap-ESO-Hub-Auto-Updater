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

