secret_key() {
    local id=""
    [ -r /etc/machine-id ] && id=$(cat /etc/machine-id 2>/dev/null)
    [ -z "$id" ] && command -v ioreg > /dev/null 2>&1 && id=$(ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null | awk -F'"' '/IOPlatformUUID/{print $4; exit}')
    [ -z "$id" ] && id=$(hostname 2>/dev/null)
    printf 'LTTC-secret-v1-%s' "${id:-fallback}"
}

secret_encrypt() {
    local v="$1" out
    [ -z "$v" ] && return 0
    case "$v" in ENC1:*) printf '%s' "$v"; return 0 ;; esac
    command -v openssl > /dev/null 2>&1 || { printf '%s' "$v"; return 0; }
    out=$(printf '%s' "$v" | openssl enc -aes-256-cbc -base64 -A -salt -pass "pass:$(secret_key)" 2>/dev/null)
    if [ -n "$out" ]; then printf 'ENC1:%s' "$out"; else printf '%s' "$v"; fi
}

secret_decrypt() {
    local v="$1"
    case "$v" in
        ENC1:*) printf '%s' "${v#ENC1:}" | openssl enc -aes-256-cbc -d -base64 -A -pass "pass:$(secret_key)" 2>/dev/null ;;
        *) printf '%s' "$v" ;;
    esac
}
