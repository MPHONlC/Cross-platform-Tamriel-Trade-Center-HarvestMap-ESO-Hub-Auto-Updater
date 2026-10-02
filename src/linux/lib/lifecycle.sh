
kill_zombie_updater() {
    trap - EXIT SIGHUP SIGINT SIGTERM
    if [ "$SETUP_COMPLETE" != "true" ] && [ "$HAS_ARGS" = false ]; then
        write_ttc_log "WARN" "User aborted or closed script before completing setup."
    fi
    write_ttc_log "INFO" "Script execution terminated/closed by user or system."
    release_instance_lock 2>/dev/null
    pkill -P $$ 2>/dev/null
    exit 0
}
trap kill_zombie_updater EXIT SIGHUP SIGINT SIGTERM
CURRENT_DIR="$(cd "$(dirname "$LTTC_SELF")" &> /dev/null && pwd)"

IS_BACKGROUND=false
for arg in "$@"; do
    if [ "$arg" = "--silent" ] || [ "$arg" = "--task" ] || [ "$arg" = "--steam" ]; then
        IS_BACKGROUND=true
    fi
done

manage_old_pid() {
    local old_pid=$1
    if [ "$IS_BACKGROUND" = true ]; then exit 0; fi
    echo -e "\e[0;33m[!] Another updater instance (PID: ${old_pid:-Unknown}) is running.\e[0m"
    read -t 10 -p "Do you want to terminate the existing process and continue? (y/n): " k_choice
    kill_choice="${k_choice:-y}"
    echo ""
    if [[ "$kill_choice" =~ ^[Yy]$ ]]; then
        echo -e "\e[0;31mTerminating old process...\e[0m"
        if [ -n "$old_pid" ] && [ "$old_pid" != "Unknown" ]; then
            kill -9 "$old_pid" 2>/dev/null || true
        fi
        for p in $(pgrep -f "$SCRIPT_NAME"); do
            if [ "$p" != "$$" ] && [ "$p" != "$PPID" ]; then
                kill -9 "$p" 2>/dev/null || true
            fi
        done
        sleep 1; return 0
    else
        echo -e "\e[0;32mKeeping the existing process safe. Exiting new instance.\e[0m"
        exit 1
    fi
}

