prune_history() {
    write_ttc_log "INFO" "prune_history: Initiating 30 days data prune and metadata sync."
    if [ -f "$DB_DIR/LTTC_History.db" ]; then
        start_spinner "Pruning history data (30 days)..."
        local cutoff=$((CURRENT_TIME - 2592000))
        
        local orig_lines=$(wc -l < "$DB_DIR/LTTC_History.db" 2>/dev/null)
        [ -z "$orig_lines" ] && orig_lines=0
        
        local del_log="$TEMP_DIR_ROOT/LTTC_History_Pruned.tmp"
        > "$del_log"
        
        awk -F'|' -v OFS='|' -v cutoff="$cutoff" -v db="$DB_FILE" -v del_log="$del_log" '
        BEGIN {
            if (db != "") {
                while ((getline line < db) > 0) {
                    split(line, p, "|")
                    if (p[1] ~ /^[0-9]+$/) {
                        db_name[p[1]] = (length(p) >= 6) ? p[6] : p[3]
                        db_qual[p[1]] = p[2] + 0
                    }
                }
                close(db)
            }
        }
        $1!="HISTORY" { if ($0 != "") print $0; next }
        $1=="HISTORY" {
            if ($2 < cutoff) {
                print $0 >> del_log
                next
            }
            if ($NF ~ /^[0-9]+$/) {
                scans = $NF + 0
                src = $(NF-1)
            } else {
                scans = 1
                src = $NF
            }
            if (src ~ /^(Unknown|\[Unknown\])$/ || src == "") src = "TTC"
            if ($6 in db_name && db_name[$6] != "" && db_name[$6] !~ /^Unknown Item/) {
                $7 = db_name[$6]
            }
            if ($6 in db_qual) {
                q_num = db_qual[$6]
                c = "\033[0m"
                if(q_num==0) c="\033[90m"
                else if(q_num==1) c="\033[97m"
                else if(q_num==2) c="\033[32m"
                else if(q_num==3) c="\033[36m"
                else if(q_num==4) c="\033[35m"
                else if(q_num==5) c="\033[33m"
                else if(q_num==6) c="\033[38;5;214m"
                $12 = c
            } else if ($12 !~ /^\033\[/) {
                $12 = "\033[0m"
            }
            $13 = src
            $14 = scans
            print $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14
        }' "$DB_DIR/LTTC_History.db" > "$TEMP_DIR_ROOT/LTTC_History.tmp" 2>/dev/null
        local awk_ok=$?
        
        local pruned_count=0
        if [ "$awk_ok" -eq 0 ] && [ -f "$TEMP_DIR_ROOT/LTTC_History.tmp" ]; then
            local new_lines=$(wc -l < "$TEMP_DIR_ROOT/LTTC_History.tmp" 2>/dev/null)
            pruned_count=$((orig_lines - new_lines))
            [ "$pruned_count" -lt 0 ] && pruned_count=0
            
            mv "$TEMP_DIR_ROOT/LTTC_History.tmp" "$DB_DIR/LTTC_History.db" 2>/dev/null
        fi
        
        if [ "$LOG_MODE" = "detailed" ] && [ -s "$del_log" ]; then
            local d_time=$(date '+%Y-%m-%d %H:%M:%S')
            awk -v dt="$d_time" '{
                gsub(/\033\[[0-9;]*m/, "", $0)
                print "["dt"] [ITEM] Pruned History Item: " $0
            }' "$del_log" >> "$LOG_FILE"
        fi
        rm -f "$del_log" 2>/dev/null
        
        stop_spinner 0 "History pruned ($pruned_count items removed)"
    fi
}

