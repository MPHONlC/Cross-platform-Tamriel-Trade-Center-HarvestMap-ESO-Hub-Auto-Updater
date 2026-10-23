awk_time_formatter='
{
    while (match($0, /\[TS:([0-9]+)\]/)) {
        ts = substr($0, RSTART+4, RLENGTH-5) + 0; diff = now - ts
        if (diff < 0) diff = 0
        if (diff < 60) { rel = diff (diff == 1 ? " second ago" : " seconds ago") }
        else if (diff < 3600) { v = int(diff/60); rel = v (v==1 ? " minute ago" : " minutes ago") }
        else if (diff < 86400) { v = int(diff/3600); rel = v (v==1 ? " hour ago" : " hours ago") }
        else { v = int(diff/86400); rel = v (v==1 ? " day ago" : " days ago") }
        pre = substr($0, 1, RSTART-1); post = substr($0, RSTART+RLENGTH)
        $0 = pre "[\033[90m" rel "\033[0m]" post
    }
    print $0
}'

print_dynamic_log() {
    local file="$1"
    if [ -s "$file" ]; then awk -v now="$(date +%s)" "$awk_time_formatter" "$file"; fi
}

ui_echo() {
    if [ "$SILENT" = false ]; then
        echo -e "$1" | awk -v now="$(date +%s)" "$awk_time_formatter"
        echo -e "$1" >> "$UI_STATE_FILE"
    fi
}

is_addon_active() {
    local addon="$1"
    local os_log_id="(macOS)"

    if [ ! -d "$ADDON_DIR/$addon" ]; then 
        write_ttc_log "INFO" "is_addon_active: $addon not present in addon folder $os_log_id"
        echo "false"
        return
    fi

    if [ -f "$ADDON_SETTINGS_FILE" ]; then
        if grep -qw "$addon" "$ADDON_SETTINGS_FILE"; then 
            write_ttc_log "INFO" "is_addon_active: $addon enabled in AddOnSettings.txt $os_log_id"
            echo "true"
        else 
            write_ttc_log "INFO" "is_addon_active: $addon not listed in AddOnSettings.txt $os_log_id"
            echo "false"
        fi
    else
        if [ -d "$ADDON_DIR/$addon" ]; then 
            write_ttc_log "INFO" "is_addon_active: $addon present (no AddOnSettings.txt) $os_log_id"
            echo "true"
        else 
            write_ttc_log "INFO" "is_addon_active: $addon missing (no AddOnSettings.txt) $os_log_id"
            echo "false"
        fi
    fi
}

get_relative_time() {
    local ts=$1; local now=$(date +%s); local diff=$((now - ts))
    if (( diff < 60 )); then (( diff == 1 )) && echo "1 second ago" || echo "$diff seconds ago"
    elif (( diff < 3600 )); then local m=$((diff / 60)); (( m == 1 )) && echo "1 minute ago" || echo "$m minutes ago"
    elif (( diff < 86400 )); then local h=$((diff / 3600)); (( h == 1 )) && echo "1 hour ago" || echo "$h hours ago"
    else local d=$((diff / 86400)); (( d == 1 )) && echo "1 day ago" || echo "$d days ago"; fi
}

format_date() {
    local ts="$1"
    date -r "$ts" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "Unknown Date"
}

