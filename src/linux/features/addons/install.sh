download_if_missing() {
    local a_name="$1"; local a_id="$2"; local skip_var="$3"
    if [ "${!skip_var}" = true ]; then return 1; fi
    
    if [ ! -d "$ADDON_DIR/$a_name" ]; then
        local ans="y"
        if [ ! -f "/etc/os-release" ] || ! grep -qi "steamos" "/etc/os-release"; then
            echo -ne "\n \e[33m[?] $a_name is missing. Download it? (y/N):\e[0m "
            read -r ans < /dev/tty
        fi
        
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            start_spinner "Downloading $a_name from ESOUI..."
            
            if esoui_download "$a_id" "$TEMP_DIR_ROOT/${a_name}.zip"; then
                unzip -q -o "$TEMP_DIR_ROOT/${a_name}.zip" -d "$ADDON_DIR/" > /dev/null 2>&1
                rm -f "$TEMP_DIR_ROOT/${a_name}.zip"
                
                if [ "$a_name" = "TamrielTradeCentre" ]; then
                    TTC_LAST_CHECK=0
                    CONFIG_CHANGED=true
                fi
                
                if [ "$a_name" = "LibEsoHubPrices" ]; then
                    local loc_ver
                    loc_ver=$(esohub_local_version "$ADDON_DIR/LibEsoHubPrices" "LibEsoHubPrices")
                    if [ -n "$loc_ver" ]; then
                        EH_LOC_7="$loc_ver"
                        CONFIG_CHANGED=true
                    fi
                fi
                
                stop_spinner 0 "$a_name installed"
                
                local settings_file="$ADDON_DIR/../AddOnSettings.txt"
                if [ -f "$settings_file" ]; then
                    if [ "$a_name" = "EsoTradingHub" ]; then
                        sed -i -e "s/^EsoTradingHub 0/EsoTradingHub 1/g" \
                               -e "s/^EsoHubScanner 0/EsoHubScanner 1/g" \
                               -e "s/^LibEsoHubPrices 0/LibEsoHubPrices 1/g" \
                               "$settings_file" 2>/dev/null
                        grep -q "^EsoTradingHub " "$settings_file" || echo "EsoTradingHub 1" >> "$settings_file"
                        grep -q "^EsoHubScanner " "$settings_file" || echo "EsoHubScanner 1" >> "$settings_file"
                        grep -q "^LibEsoHubPrices " "$settings_file" || echo "LibEsoHubPrices 1" >> "$settings_file"
                    elif [ "$a_name" = "HarvestMap" ] || [ "$a_name" = "HarvestMapData" ]; then
                        sed -i -e "s/^HarvestMap 0/HarvestMap 1/g" \
                               -e "s/^HarvestMapData 0/HarvestMapData 1/g" \
                               "$settings_file" 2>/dev/null
                        grep -q "^HarvestMap " "$settings_file" || echo "HarvestMap 1" >> "$settings_file"
                        grep -q "^HarvestMapData " "$settings_file" || echo "HarvestMapData 1" >> "$settings_file"
                    else
                        sed -i -e "s/^$a_name 0/$a_name 1/g" "$settings_file" 2>/dev/null
                        grep -q "^$a_name " "$settings_file" || echo "$a_name 1" >> "$settings_file"
                    fi
                fi
                return 0
            else
                stop_spinner 1 "$a_name download failed"
                return 1
            fi
        else
            ui_echo " \e[90mUser Declined download of $a_name. Will not ask again.\e[0m"
            printf -v "$skip_var" "true"
            write_lttc_config
            return 1
        fi
    fi
    return 0
}

