SELF_UPDATE_INTERVAL=21600

self_update_install() {
    local zip="$TEMP_DIR_ROOT/self_update.zip" work="$TEMP_DIR_ROOT/self_update" new new_ver dest tmp
    SELF_NEW_VERSION=""
    rm -rf "$work"; mkdir -p "$work"
    local rc
    esoui_download "$ESOUI_SELF_ID" "$zip"; rc=$?
    if [ "$rc" -ne 0 ]; then rm -rf "$work"; return "$rc"; fi
    unzip -q -o "$zip" -d "$work" >/dev/null 2>&1
    rm -f "$zip"
    new=$(find "$work" -type f -name "$SCRIPT_NAME" | head -n 1)
    if [ -z "$new" ] || ! bash -n "$new" 2>/dev/null; then rm -rf "$work"; return 2; fi
    new_ver=$(grep -m1 -o 'APP_VERSION="[^"]*"' "$new" | cut -d'"' -f2)
    if [ -z "$new_ver" ] || ! version_newer "$new_ver" "$APP_VERSION"; then rm -rf "$work"; return 3; fi

    for dest in "$TARGET_DIR/$SCRIPT_NAME" "$LTTC_SELF"; do
        [ -n "$dest" ] || continue
        tmp="$dest.new.$$"
        if cp "$new" "$tmp" 2>/dev/null && chmod +x "$tmp" && mv -f "$tmp" "$dest"; then
            write_ttc_log "INFO" "Self-update: installed v$new_ver at $dest"
        else
            rm -f "$tmp"
        fi
    done
    rm -rf "$work"
    SELF_NEW_VERSION="$new_ver"
    return 0
}

self_update_check() {
    [ "$AUTO_SELF_UPDATE" = false ] && return 0
    [ "$ENABLE_LOCAL_MODE" = true ] && return 0
    [ -n "$LTTC_DEV" ] && return 0
    local now since
    now=$(date +%s); since=$((now - ${SELF_LAST_CHECK:-0}))
    if [ "$since" -lt "$SELF_UPDATE_INTERVAL" ] && [ "$since" -ge 0 ]; then return 0; fi
    SELF_LAST_CHECK="$now"; write_lttc_config

    esoui_details "$ESOUI_SELF_ID" || { write_ttc_log "WARN" "Self-update: could not reach ESOUI."; return 0; }
    version_newer "$ESOUI_VERSION" "$APP_VERSION" || return 0

    start_spinner "Updating the updater to $ESOUI_VERSION..."
    if self_update_install; then
        stop_spinner 0 "Updated to v$SELF_NEW_VERSION, restarting"
        release_instance_lock
        trap - EXIT SIGHUP SIGINT SIGTERM
        exec bash "$LTTC_SELF" "${LTTC_ARGS[@]}"
    else
        stop_spinner 1 "Update to $ESOUI_VERSION failed, keeping v$APP_VERSION"
    fi
}
