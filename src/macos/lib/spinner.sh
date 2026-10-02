SPINNER_PID=0
SPIN_START=0
SPIN_MSG_FILE="/tmp/lttc_spin.tmp"

start_spinner() {
    local msg="$1"
    echo "$msg" > "$SPIN_MSG_FILE"
    SPIN_START=$(date +%s)
    if [ "$SILENT" = true ]; then return; fi
    tput civis 2>/dev/null
    while :; do
        for s in / - \\ \|; do
            read -r cur_msg < "$SPIN_MSG_FILE" 2>/dev/null
            printf "\r\033[K \e[33m[%c]\e[0m %s" "$s" "${cur_msg:-$msg}"
            sleep 0.1
        done
    done &
    SPINNER_PID=$!
}

update_spinner() {
    echo "$1" > "$SPIN_MSG_FILE"
}

stop_spinner() {
    local ok="$1"; local msg="$2"
    local el=$(( $(date +%s) - SPIN_START ))
    if [ "$SILENT" = false ] && [ "$SPINNER_PID" != "0" ]; then
        kill "$SPINNER_PID" 2>/dev/null; wait "$SPINNER_PID" 2>/dev/null
        tput cnorm 2>/dev/null
        local out_str=""
        if [ "$ok" = "0" ]; then out_str=" \e[92m[✓]\e[0m $msg (${el}s)"
        else out_str=" \e[31m[✗]\e[0m $msg (${el}s)"; fi
        printf "\r\033[K%b\n" "$out_str"
        echo -e "$out_str" >> "$UI_STATE_FILE"
        SPINNER_PID=0
    fi
    write_ttc_log "INFO" "Task '$msg' finished in ${el}s (Status: $ok)."
}

