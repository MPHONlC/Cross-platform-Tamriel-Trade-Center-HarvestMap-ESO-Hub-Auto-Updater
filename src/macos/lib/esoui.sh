ESOUI_API="${LTTC_ESOUI_API:-https://api.mmoui.com}"
ESOUI_UA="Mozilla/5.0"
ESOUI_SELF_ID="3249"
ESOUI_DB_ID="4428"

md5_of() {
    md5 -q "$1" 2>/dev/null
}

version_newer() {
    awk -v a="$1" -v b="$2" 'BEGIN {
        sub(/^[vV]/, "", a); sub(/^[vV]/, "", b)
        na = split(a, x, /[^0-9]+/); nb = split(b, y, /[^0-9]+/)
        n = (na > nb) ? na : nb
        for (i = 1; i <= n; i++) {
            p = x[i] + 0; q = y[i] + 0
            if (p > q) exit 0
            if (p < q) exit 1
        }
        exit 1
    }'
}

json_value() {
    printf '%s' "$1" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -n 1 | cut -d'"' -f4 | sed 's/\\\//\//g'
}

esoui_details() {
    ESOUI_VERSION=""; ESOUI_DOWNLOAD=""; ESOUI_MD5=""
    local resp
    resp=$(curl -s -f -m 30 -A "$ESOUI_UA" "$ESOUI_API/v3/game/ESO/filedetails/$1.json" 2>/dev/null) || return 1
    ESOUI_VERSION=$(json_value "$resp" "UIVersion")
    ESOUI_DOWNLOAD=$(json_value "$resp" "UIDownload")
    ESOUI_MD5=$(json_value "$resp" "UIMD5" | tr 'A-F' 'a-f')
    [ -n "$ESOUI_VERSION" ] && [ -n "$ESOUI_DOWNLOAD" ]
}

esoui_download() {
    local id="$1" dest="$2"
    esoui_details "$id" || return 1
    rm -f "$dest"
    curl -s -f -L -m 180 -A "$ESOUI_UA" -o "$dest" "$ESOUI_DOWNLOAD" </dev/null || { rm -f "$dest"; return 1; }
    if [ -n "$ESOUI_MD5" ] && [ "$(md5_of "$dest")" != "$ESOUI_MD5" ]; then
        write_ttc_log "WARN" "ESOUI file $id failed its checksum, discarded."
        rm -f "$dest"; return 2
    fi
    if ! unzip -t "$dest" >/dev/null 2>&1; then
        rm -f "$dest"; return 2
    fi
    return 0
}
