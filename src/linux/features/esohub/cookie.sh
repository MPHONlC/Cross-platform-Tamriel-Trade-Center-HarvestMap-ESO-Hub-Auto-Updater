esohub_cookie_roots() {
    if [ "$OS_TYPE" = Darwin ]; then
        printf '%s\n' \
            "brave|$HOME/Library/Application Support/BraveSoftware/Brave-Browser" \
            "chrome|$HOME/Library/Application Support/Google/Chrome" \
            "chromium|$HOME/Library/Application Support/Chromium" \
            "Microsoft Edge|$HOME/Library/Application Support/Microsoft Edge" \
            "Vivaldi|$HOME/Library/Application Support/Vivaldi"
    else
        printf '%s\n' \
            "brave|$HOME/.config/BraveSoftware/Brave-Browser" \
            "brave|$HOME/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser" \
            "chrome|$HOME/.config/google-chrome" \
            "chrome|$HOME/.var/app/com.google.Chrome/config/google-chrome" \
            "chromium|$HOME/.config/chromium" \
            "chromium|$HOME/.var/app/org.chromium.Chromium/config/chromium" \
            "Microsoft Edge|$HOME/.config/microsoft-edge" \
            "Vivaldi|$HOME/.config/vivaldi"
    fi
}

esohub_cookie_firefox_roots() {
    if [ "$OS_TYPE" = Darwin ]; then
        printf '%s\n' "$HOME/Library/Application Support/Firefox/Profiles"
    else
        printf '%s\n' "$HOME/.mozilla/firefox" "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox"
    fi
}

esohub_cookie_key() {
    local label="$1" pw=""
    if [ "$OS_TYPE" = Darwin ]; then
        pw=$(security find-generic-password -ws "$label Safe Storage" 2>/dev/null)
    else
        local app
        case "$label" in
            brave) app=brave ;;
            chrome) app=chrome ;;
            chromium) app=chromium ;;
            "Microsoft Edge") app=chrome ;;
            Vivaldi) app=vivaldi ;;
            *) app=chrome ;;
        esac
        command -v secret-tool > /dev/null 2>&1 && pw=$(secret-tool lookup application "$app" 2>/dev/null)
    fi
    [ -n "$pw" ] && { printf '%s' "$pw"; return 0; }
    printf 'peanuts'
}

esohub_cookie_decrypt() {
    local hexblob="$1" pw="$2" iters prefix cthex keyhex plainhex n core cand
    command -v python3 > /dev/null 2>&1 || return 1
    command -v openssl > /dev/null 2>&1 || return 1
    if [ "$OS_TYPE" = Darwin ]; then iters=1003; else iters=1; fi
    prefix="${hexblob:0:6}"
    case "$prefix" in 763130|763131) cthex="${hexblob:6}" ;; *) return 1 ;; esac
    keyhex=$(PW="$pw" IT="$iters" python3 -I -c 'import os,hashlib;print(hashlib.pbkdf2_hmac("sha1",os.environ["PW"].encode(),b"saltysalt",int(os.environ["IT"]),16).hex())' 2>/dev/null)
    case "$keyhex" in ''|*[!0-9a-f]*) return 1 ;; esac
    plainhex=$(printf '%s' "$cthex" | xxd -r -p 2>/dev/null | openssl enc -d -aes-128-cbc -K "$keyhex" -iv 20202020202020202020202020202020 -nopad 2>/dev/null | xxd -p 2>/dev/null | tr -d '\n')
    case "$plainhex" in ''|*[!0-9a-f]*) return 1 ;; esac
    [ "${#plainhex}" -ge 4 ] || return 1
    n=$(( 16#${plainhex:$((${#plainhex}-2))} ))
    [ "$n" -ge 1 ] && [ "$n" -le 16 ] && [ $(( n*2 )) -le "${#plainhex}" ] && core="${plainhex:0:$((${#plainhex}-n*2))}" || core="$plainhex"
    cand=$(printf '%s' "${core:64}" | xxd -r -p 2>/dev/null)
    esohub_cf_clean_cookie "$cand" 2>/dev/null && return 0
    cand=$(printf '%s' "$core" | xxd -r -p 2>/dev/null)
    esohub_cf_clean_cookie "$cand" 2>/dev/null && return 0
    return 1
}

esohub_cookie_ua_guess() {
    local root="$1" ver major
    [ -n "$ESOHUB_CF_UA" ] && { printf '%s' "$ESOHUB_CF_UA"; return 0; }
    ver=$(head -c 40 "$root/Last Version" 2>/dev/null | tr -d '\r\n')
    major="${ver%%.*}"
    case "$major" in ''|*[!0-9]*) return 1 ;; esac
    if [ "$OS_TYPE" = Darwin ]; then
        printf 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/%s.0.0.0 Safari/537.36' "$major"
    else
        printf 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/%s.0.0.0 Safari/537.36' "$major"
    fi
}

esohub_cookie_from_db() {
    local db="$1" label="$2" tmp hexblob pw ck
    [ -f "$db" ] || return 1
    tmp="${TEMP_DIR:-/tmp}/lttc_ck.$$"
    cp "$db" "$tmp" 2>/dev/null || return 1
    hexblob=$(sqlite3 "file:$tmp?immutable=1" "SELECT hex(encrypted_value) FROM cookies WHERE name='cf_clearance' AND host_key LIKE '%eso-hub.com' ORDER BY length(encrypted_value) DESC LIMIT 1;" 2>/dev/null)
    rm -f "$tmp" 2>/dev/null
    case "$hexblob" in ''|*[!0-9A-Fa-f]*) return 1 ;; esac
    pw=$(esohub_cookie_key "$label")
    ck=$(esohub_cookie_decrypt "$hexblob" "$pw") || return 1
    printf '%s' "$ck"
}

esohub_cookie_from_firefox() {
    local db="$1" tmp val
    [ -f "$db" ] || return 1
    tmp="${TEMP_DIR:-/tmp}/lttc_ffck.$$"
    cp "$db" "$tmp" 2>/dev/null || return 1
    val=$(sqlite3 "file:$tmp?immutable=1" "SELECT value FROM moz_cookies WHERE name='cf_clearance' AND host LIKE '%eso-hub.com' ORDER BY expiry DESC LIMIT 1;" 2>/dev/null)
    rm -f "$tmp" 2>/dev/null
    esohub_cf_clean_cookie "$val" 2>/dev/null
}

esohub_cookie_fetch() {
    command -v sqlite3 > /dev/null 2>&1 || return 1
    local line label root db ck ua
    while IFS='|' read -r label root; do
        [ -d "$root" ] || continue
        for db in "$root"/*/Network/Cookies "$root"/*/Cookies; do
            [ -f "$db" ] || continue
            if ck=$(esohub_cookie_from_db "$db" "$label"); then
                ua=$(esohub_cookie_ua_guess "$root") || continue
                ua=$(esohub_cf_clean_ua "$ua") || continue
                ESOHUB_CF_CLEARANCE="$ck"; ESOHUB_CF_UA="$ua"; CONFIG_CHANGED=true
                write_ttc_log "INFO" "ESO-Hub cf_clearance read from the local browser cookie store ($label)."
                return 0
            fi
        done
    done <<EOF
$(esohub_cookie_roots)
EOF
    if [ -n "$ESOHUB_CF_UA" ]; then
        for root in $(esohub_cookie_firefox_roots); do
            [ -d "$root" ] || continue
            for db in "$root"/*/cookies.sqlite; do
                [ -f "$db" ] || continue
                if ck=$(esohub_cookie_from_firefox "$db"); then
                    ESOHUB_CF_CLEARANCE="$ck"; ESOHUB_CF_UA="$ESOHUB_CF_UA"; CONFIG_CHANGED=true
                    write_ttc_log "INFO" "ESO-Hub cf_clearance read from the local browser cookie store (firefox)."
                    return 0
                fi
            done
        done
    fi
    return 1
}
