clean_legacy_tags() {
    write_ttc_log "INFO" "clean_legacy_tags: sanitizing legacy DB files"
    local found_dirt=false
    for db in "$DB_FILE" "$DB_DIR/LTTC_History.db"; do
        if [ -f "$db" ] && grep -q "<title>" "$db"; then
            sed -i.bak -e 's/<title>UESP:ESO Item -- //g' \
                       -e 's/<title>ESO Item -- //g' \
                       -e 's/<\/title>//g' "$db" 2>/dev/null
            rm -f "${db}.bak" 2>/dev/null
            found_dirt=true
        fi
    done
    if [ "$found_dirt" = true ]; then
        write_ttc_log "INFO" "Sanitized legacy tags."
        echo -e " \e[92m[+] Cleaned legacy tags.\e[0m"
    fi
}
clean_legacy_tags

repair_missing_names() {
    write_ttc_log "INFO" "repair_missing_names: repairing DB entries with local SavedVariables"
    if [ ! -f "$DB_FILE" ]; then return; fi
    
    local tmp_db="$DB_FILE.repair"
    local missing_ids="$TEMP_DIR_ROOT/lttc_db_missing.tmp"
    local offline_dict="$TEMP_DIR_ROOT/offline_name_dict.tmp"
    
    awk -F'|' '$1 ~ /^[0-9]+$/ && (length($0) >= 6 ? $6 : $3) ~ /^Unknown Item \(/ { print $1 }' \
        "$DB_FILE" | tr -d '\r' > "$missing_ids"
        
    local missing_count=$(wc -l < "$missing_ids" 2>/dev/null)
    [ -z "$missing_count" ] && missing_count=0
    
    if (( missing_count > 0 )); then
        if [ "$SILENT" = false ]; then
            echo -e " \e[33m[!] Auto-Repair: Scanning local data for $missing_count unknown items...\e[0m"
        fi
        write_ttc_log "INFO" "Auto-Repair: Found $missing_count unknown items."
        
        grep -oE '\|H[^:]*:item:[0-9]+[^|]*\|h[^|]+\|h' "$SAVED_VAR_DIR/TamrielTradeCentre.lua" 2>/dev/null | \
        awk -F'\\|h' '{ 
            split($1, parts, ":")
            id = parts[3]; name = $2
            sub(/\^.*$/, "", name)
            if (id ~ /^[0-9]+$/ && name != "") print id "|" name 
        }' | sort -u > "$offline_dict"
        
        awk -F'|' -v OFS='|' -v lookup="$offline_dict" '
        '"$master_color_logic"'
        BEGIN {
            while ((getline line < lookup) > 0) {
                split(line, p, "|")
                names[p[1]] = p[2]
            }
            close(lookup)
        }
        {
            if ($1 ~ /^[0-9]+$/ && NF >= 6) {
                if ($6 ~ /^Unknown Item \(/ || $6 == "") {
                    if (names[$1] != "") {
                        $6 = names[$1]
                        real_qual = calc_quality($1, $6, $3+0, $4+0)
                        $2 = real_qual
                        $5 = get_hq(real_qual)
                        $7 = get_cat($6, $1, $3+0, $4+0)
                    }
                }
            }
            print $0
        }' "$DB_FILE" > "$tmp_db" 2>/dev/null
        
        if [ -s "$tmp_db" ]; then
            mv "$tmp_db" "$DB_FILE"
            if [ "$SILENT" = false ]; then
                echo -e " \e[92m[\0342\0234\0223]\e[0m Offline Database repair complete!"
            fi
            write_ttc_log "INFO" "Auto-Repair done."
        fi
    fi
    rm -f "$missing_ids" "$offline_dict" 2>/dev/null
}

