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
