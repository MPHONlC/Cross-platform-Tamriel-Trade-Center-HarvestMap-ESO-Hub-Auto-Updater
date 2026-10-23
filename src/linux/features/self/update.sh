SELF_UPDATE_INTERVAL=21600
GH_SELF_API="${LTTC_SELF_GH_API:-https://api.github.com}"
GH_SELF_REPO="MPHONlC/Cross-platform-Tamriel-Trade-Center-HarvestMap-ESO-Hub-Auto-Updater"
GH_SELF_ASSET="Tamriel_Trade_Center_Auto-Updater.zip"

github_self_details() {
    GH_SELF_VERSION=""; GH_SELF_URL=""
    local resp tag
    resp=$(curl -fsS -m 20 -H "Accept: application/vnd.github+json" "$GH_SELF_API/repos/$GH_SELF_REPO/releases/latest" < /dev/null 2>/dev/null) || return 1
    tag=$(printf '%s' "$resp" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/')
    GH_SELF_VERSION="${tag#Version-}"
    GH_SELF_URL=$(printf '%s' "$resp" | grep -o '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\(http[^"]*\)"$/\1/' | grep "$GH_SELF_ASSET" | head -n 1)
    [ -n "$GH_SELF_VERSION" ] && [ -n "$GH_SELF_URL" ]
}

self_update_install() {
    local src="${1:-esoui}" gh_url="$2"
    local zip="$TEMP_DIR_ROOT/self_update.zip" work="$TEMP_DIR_ROOT/self_update" new new_ver dest tmp
    SELF_NEW_VERSION=""
    rm -rf "$work"; mkdir -p "$work"
    local rc
    if [ "$src" = github ]; then
        rm -f "$zip"
        curl -fsSL -m 120 -A "${RAND_UA:-TTC-Updater}" -o "$zip" "$gh_url" < /dev/null 2>/dev/null; rc=$?
        [ "$rc" -eq 0 ] && [ -s "$zip" ] || rc=1
    else
        esoui_download "$ESOUI_SELF_ID" "$zip"; rc=$?
    fi
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

    ESOUI_VERSION=""
    esoui_details "$ESOUI_SELF_ID" || write_ttc_log "WARN" "Self-update: could not reach ESOUI."
    github_self_details || write_ttc_log "WARN" "Self-update: could not reach GitHub."

    local best_ver="$APP_VERSION" best_src="" best_url=""
    if [ -n "$ESOUI_VERSION" ] && version_newer "$ESOUI_VERSION" "$best_ver"; then best_ver="$ESOUI_VERSION"; best_src="esoui"; best_url=""; fi
    if [ -n "$GH_SELF_VERSION" ] && version_newer "$GH_SELF_VERSION" "$best_ver"; then best_ver="$GH_SELF_VERSION"; best_src="github"; best_url="$GH_SELF_URL"; fi
    [ -z "$best_src" ] && return 0

    start_spinner "Updating the updater to $best_ver (from $best_src)..."
    if self_update_install "$best_src" "$best_url"; then
        stop_spinner 0 "Updated to v$SELF_NEW_VERSION, restarting"
        release_instance_lock
        trap - EXIT SIGHUP SIGINT SIGTERM
        exec bash "$LTTC_SELF" "${LTTC_ARGS[@]}"
    else
        stop_spinner 1 "Update to $best_ver failed, keeping v$APP_VERSION"
    fi
}
