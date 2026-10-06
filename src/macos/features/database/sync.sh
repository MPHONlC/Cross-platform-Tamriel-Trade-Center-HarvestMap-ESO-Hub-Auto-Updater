    HAS_TTC=$(is_addon_active "TamrielTradeCentre")
    HAS_HM=$(is_addon_active "HarvestMap")

    if [ "$ENABLE_LOCAL_MODE" != true ]; then
        ui_echo "\e[1m\e[97m [0/4] Synchronizing Local Database \e[0m\n \e[33mChecking updates...\e[0m"
        SRV_DB_VER="0.0.0"
        esoui_details "$ESOUI_DB_ID" && SRV_DB_VER="$ESOUI_VERSION"
        
        LOC_DB_VER="0.0.0"
        if [ -f "$DB_FILE" ]; then
            extracted_ver=$(head -n 1 "$DB_FILE" 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n 1)
            [ -n "$extracted_ver" ] && LOC_DB_VER="$extracted_ver"
        fi
        
        [ "$SRV_DB_VER" = "$LOC_DB_VER" ] && V_COL="\e[92m" || V_COL="\e[31m"
        ui_echo "\t\e[90mServer_DB_Version= ${V_COL}$SRV_DB_VER\e[0m"
        ui_echo "\t\e[90mLocal_DB_Version=  ${V_COL}$LOC_DB_VER\e[0m"

        HIST_SEEDED=false
        grep -q '^#HISTORY VERSION:' "$DB_DIR/LTTC_History.db" 2>/dev/null && HIST_SEEDED=true
        if [ "$SRV_DB_VER" != "0.0.0" ] && { version_newer "$SRV_DB_VER" "$LOC_DB_VER" || [ "$HIST_SEEDED" = false ]; }; then
            write_ttc_log "INFO" "Downloading database update v$SRV_DB_VER"
            start_spinner "Downloading database template v$SRV_DB_VER..."
            mkdir -p "$TEMP_DIR_ROOT/DB_Update"
            TEMP_DIR_USED=true
            
            if esoui_download "$ESOUI_DB_ID" "$TEMP_DIR_ROOT/DB_Update/db.zip"; then
                stop_spinner 0 "Database downloaded"
                unzip -q -o "$TEMP_DIR_ROOT/DB_Update/db.zip" -d "$TEMP_DIR_ROOT/DB_Update/" > /dev/null 2>&1
                NEW_DB=$(find "$TEMP_DIR_ROOT/DB_Update" -name "LTTC_Database.db" | head -n 1)
                NEW_HIST=$(find "$TEMP_DIR_ROOT/DB_Update" -name "LTTC_History.db" | head -n 1)
                
                if [ -n "$NEW_DB" ] && [ -f "$NEW_DB" ]; then
                    if [ ! -s "$DB_FILE" ]; then
                        echo "#DATABASE VERSION: $SRV_DB_VER" > "$DB_FILE"
                        grep -v '^#DATABASE VERSION:' "$NEW_DB" | tr -d '\r' >> "$DB_FILE"
                    else
                        start_spinner "Merging new database entries..."
                        awk -F'|' '
                        /^#DATABASE VERSION:/ { next }
                        {
                            sub(/\r$/, "")
                            if ($1 == "GUILD") key = "GUILD_"$2
                            else if ($1 == "KIOSK") key = "KIOSK_"$2
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
                        start_spinner "Merging shared trade history..."
                        template_history_apply "$DB_DIR/LTTC_History.db" "$NEW_HIST" "$SRV_DB_VER"
                        stop_spinner 0 "Shared trade history merged"
                    else
                        template_history_apply "$DB_DIR/LTTC_History.db" /dev/null "$SRV_DB_VER"
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

