ADDON_UPDATE_EXCLUDE="HarvestMapData EsoTradingHub EsoHubScanner LibEsoHubPrices"
ADDON_UPDATE_INTERVAL=21600
ADDON_BOM="$(printf '\357\273\277')"

addon_local_list() {
    local dir="$1" top d rel name mf av ver
    for top in "$dir"/*/; do
        top="${top%/}"
        [ -L "$top" ] && continue
        while IFS= read -r d; do
            rel="${d#"$dir"/}"; name="${d##*/}"
            mf="$d/$name.addon"; [ -f "$mf" ] || mf="$d/$name.txt"; [ -f "$mf" ] || continue
            av=$(LC_ALL=C sed "1s/^$ADDON_BOM//" "$mf" | LC_ALL=C grep -a -m1 -i '^##[[:space:]]*AddOnVersion:' | tr -d '\r' \
                | tr -d '|' | sed 's/^[^:]*:[[:space:]]*//' | awk '{ print $1 }')
            ver=$(LC_ALL=C sed "1s/^$ADDON_BOM//" "$mf" | LC_ALL=C grep -a -m1 -i '^##[[:space:]]*Version:' | tr -d '\r|' \
                | sed 's/^[^:]*:[[:space:]]*//; s/[[:space:]]*$//')
            printf '%s|%s|%s\n' "$rel" "$av" "$ver"
        done <<< "$(find "$top" -maxdepth 3 -type d 2>/dev/null)"
    done
}

addon_update_plan() {
    LC_ALL=C awk -F'|' -v skip="$ADDON_UPDATE_EXCLUDE ${ADDON_UPDATE_SKIP:-}" -v records="${3:-}" '
    function jstr(s, key,   p, i, c, out) {
        p = index(s, "\"" key "\":\"")
        if (p == 0) return ""
        i = p + length(key) + 4; out = ""
        while (i <= length(s)) {
            c = substr(s, i, 1)
            if (c == "\\") {
                c = substr(s, i + 1, 1)
                if (c == "u") { if (tolower(substr(s, i + 2, 4)) != "feff") out = out "?"; i += 6; continue }
                out = out c; i += 2; continue
            }
            if (c == "\"") break
            out = out c; i++
        }
        return out
    }
    function dotted(v) { return v ~ /^[vV]?[0-9]+(\.[0-9]+)*$/ }
    function parts(v,   x) { sub(/^[vV]/, "", v); return split(v, x, ".") }
    function newer(a, b,   x, y, na, nb, n, i, p, q) {
        sub(/^[vV]/, "", a); sub(/^[vV]/, "", b)
        na = split(a, x, /[^0-9]+/); nb = split(b, y, /[^0-9]+/)
        n = (na > nb) ? na : nb
        for (i = 1; i <= n; i++) { p = x[i] + 0; q = y[i] + 0; if (p > q) return 1; if (p < q) return 0 }
        return 0
    }
    function vnorm(v) { sub(/^[vV]/, "", v); return v }
    function listing(s,   id, title, lver, lu, a, rest, p, nxt, obj, path, av, npaths, nt, k, f, score, mine, all) {
        if (!match(s, /"id":[0-9]+/)) return
        if (s ~ /"categoryId":157[,}]/) return
        id = substr(s, RSTART + 5, RLENGTH - 5)
        lu = match(s, /"lastUpdate":[0-9]+/) ? substr(s, RSTART + 13, RLENGTH - 13) : ""
        title = tolower(jstr(s, "title"))
        lver = jstr(s, "version")
        a = index(s, "\"addons\":[")
        if (a == 0) return
        rest = substr(s, a); npaths = 0; nt = 0; all = ""
        while ((p = index(rest, "\"path\":\"")) > 0) {
            rest = substr(rest, p)
            path = jstr(rest, "path")
            nxt = index(substr(rest, 9), "\"path\":\"")
            obj = (nxt > 0) ? substr(rest, 1, nxt + 7) : rest
            av = jstr(obj, "addOnVersion")
            npaths++
            all = all path "=" av "\n"
            if (index(path, "/") == 0) { nt++; tp[nt] = path; tav[nt] = av }
            rest = substr(rest, 9)
        }
        paths_of[id] = all
        for (k = 1; k <= nt; k++) {
            f = tp[k]
            if (!(f in local_av) || (f in skipped)) continue
            score = (npaths == 1 ? 2 : 0) + (title == tolower(f) ? 1 : 0)
            mine = ((tav[k] != "" && tav[k] == local_av[f]) || (lver != "" && vnorm(lver) == vnorm(local_ver[f]))) ? 1 : 0
            if (!(f in best_id) || score > best_score[f] || (score == best_score[f] && (mine > best_mine[f] || (mine == best_mine[f] && lu + 0 > best_lu[f] + 0)))) {
                best_id[f] = id; best_score[f] = score; best_mine[f] = mine; best_ver[f] = lver; best_tav[f] = tav[k]; best_lu[f] = lu
            }
        }
    }
    BEGIN {
        n = split(skip, sk, " "); for (i = 1; i <= n; i++) skipped[sk[i]] = 1
        if (records != "") {
            while ((getline line < records) > 0) { split(line, r, "|"); rec_id[r[1]] = r[2]; rec_lu[r[1]] = r[3] }
            close(records)
        }
    }
    FNR == NR { local_av[$1] = $2; local_ver[$1] = $3; next }
    {
        gsub(/\},\{"id":/, "}\n{\"id\":")
        nl = split($0, L, "\n")
        for (li = 1; li <= nl; li++) listing(L[li])
    }
    END {
        for (f in best_id) {
            id = best_id[f]; state = ""; lshow = local_av[f]; rshow = best_tav[f]
            np = split(paths_of[id], pl, "\n")
            for (i = 1; i <= np; i++) {
                if (pl[i] == "") continue
                eq = index(pl[i], "="); path = substr(pl[i], 1, eq - 1); ra = substr(pl[i], eq + 1)
                if (path != f && index(path, f "/") != 1) continue
                if (!(path in local_av)) continue
                la = local_av[path]
                if (la ~ /^[0-9]+$/ && ra ~ /^[0-9]+$/) {
                    if (ra + 0 > la + 0) { state = "UPDATE"; lshow = la; rshow = ra; break }
                    if (state == "") { state = "CURRENT"; if (path == f) { lshow = la; rshow = ra } }
                } else if (dotted(la) && dotted(ra) && parts(la) == parts(ra)) {
                    if (newer(ra, la)) { state = "UPDATE"; lshow = la; rshow = ra; break }
                    if (state == "") { state = "CURRENT"; if (path == f) { lshow = la; rshow = ra } }
                }
            }
            lv = local_ver[f]; rv = best_ver[f]
            if (state == "" && (f in rec_id) && rec_id[f] == id && best_lu[f] != "") {
                state = (best_lu[f] + 0 > rec_lu[f] + 0) ? "UPDATE" : "CURRENT"; lshow = lv; rshow = rv
            }
            if (state == "" && rv != "" && (vnorm(lv) == vnorm(rv) || vnorm(local_av[f]) == vnorm(rv))) { state = "CURRENT"; lshow = rv; rshow = rv }
            if (state == "") {
                if (dotted(lv) && dotted(rv) && parts(lv) == parts(rv)) { state = newer(rv, lv) ? "UPDATE" : "CURRENT"; lshow = lv; rshow = rv }
                else { state = "UNKNOWN"; lshow = (local_av[f] != "" ? local_av[f] : lv); rshow = (best_tav[f] != "" ? best_tav[f] : rv) }
            }
            print state "|" id "|" f "|" lshow "|" rshow "|" best_lu[f]
        }
    }' "$1" "$2" | LC_ALL=C sort -t'|' -k3,3
}

install_addon_zip() {
    local zip="$1" work="$TEMP_DIR_ROOT/addon_update" d name ex installed=""
    rm -rf "$work"; mkdir -p "$work"
    unzip -q -o "$zip" -d "$work" >/dev/null 2>&1 || { rm -rf "$work"; return 1; }
    mkdir -p "$TARGET_DIR/Backups/AddOns"
    for d in "$work"/*/; do
        d="${d%/}"; name="${d##*/}"
        [ -d "$d" ] || continue
        for ex in $ADDON_UPDATE_EXCLUDE ${ADDON_UPDATE_SKIP:-}; do [ "$name" = "$ex" ] && continue 2; done
        [ -L "$ADDON_DIR/$name" ] && continue
        rm -rf "$TARGET_DIR/Backups/AddOns/$name"
        [ -d "$ADDON_DIR/$name" ] && mv "$ADDON_DIR/$name" "$TARGET_DIR/Backups/AddOns/$name" && touch "$TARGET_DIR/Backups/AddOns/$name"
        if mv "$d" "$ADDON_DIR/$name"; then
            installed="$installed $name"
            write_ttc_log "INFO" "Add-on updated: $name"
        elif [ -d "$TARGET_DIR/Backups/AddOns/$name" ]; then
            mv "$TARGET_DIR/Backups/AddOns/$name" "$ADDON_DIR/$name"
        fi
    done
    rm -rf "$work"
    ADDON_INSTALLED="$installed"
    [ -n "$installed" ]
}

ADDON_RECORDS="${DB_DIR:-.}/LTTC_AddonUpdates.db"

record_addon_install() {
    local id="$1" lu="$2" name
    [ -n "$lu" ] || return 0
    touch "$ADDON_RECORDS"
    for name in $ADDON_INSTALLED; do
        awk -F'|' -v n="$name" '$1 != n' "$ADDON_RECORDS" > "$ADDON_RECORDS.tmp" && mv -f "$ADDON_RECORDS.tmp" "$ADDON_RECORDS"
        printf '%s|%s|%s\n' "$name" "$id" "$lu" >> "$ADDON_RECORDS"
    done
}

ADDON_BACKUP_DAYS=30

prune_addon_backups() {
    local dir="$TARGET_DIR/Backups/AddOns" old
    [ -d "$dir" ] || return 0
    find "$dir" -mindepth 1 -maxdepth 1 -type d -mmin +$(( ADDON_BACKUP_DAYS * 1440 )) 2>/dev/null | while IFS= read -r old; do
        rm -rf "$old"
        write_ttc_log "INFO" "Add-on backup older than ${ADDON_BACKUP_DAYS} days removed: ${old##*/}"
    done
}

run_addon_updates() {
    prune_addon_backups
    [ "$ENABLE_ADDON_UPDATES" = true ] || return 0
    [ -d "$ADDON_DIR" ] || return 0
    ui_echo "\e[1m\e[97m [+] Updating Your Add-Ons & Libraries \e[0m"
    local now since
    now=$(date +%s); since=$((now - ${ADDON_LAST_CHECK:-0}))
    if [ "$since" -lt "$ADDON_UPDATE_INTERVAL" ] && [ "$since" -ge 0 ]; then
        ui_echo " \e[90mChecked $(( since / 60 )) minutes ago. Next check in $(( (ADDON_UPDATE_INTERVAL - since) / 60 )) minutes.\e[0m\n"
        return 0
    fi

    local catalog="$TEMP_DIR_ROOT/esoui_filelist.json" locals="$TEMP_DIR_ROOT/addon_local.lst" plan
    start_spinner "Reading the ESOUI add-on list..."
    if ! curl -s -f -m 120 -A "$ESOUI_UA" -o "$catalog" "$ESOUI_API/v4/game/ESO/filelist.json" </dev/null; then
        stop_spinner 1 "Could not reach ESOUI"
        NOTIF_ADDONS="Check Failed"
        rm -f "$catalog"; echo ""; return 0
    fi
    addon_local_list "$ADDON_DIR" > "$locals"
    plan=$(addon_update_plan "$locals" "$catalog" "$ADDON_RECORDS")
    rm -f "$catalog" "$locals"
    stop_spinner 0 "Compared $(printf '%s\n' "$plan" | grep -c '|') add-ons with ESOUI"
    ADDON_LAST_CHECK="$now"; CONFIG_CHANGED=true

    local updates ids id line folder lv rv count=0 failed=0
    updates=$(printf '%s\n' "$plan" | grep '^UPDATE|')
    if [ -z "$updates" ]; then
        ui_echo " \e[90mNo changes detected. \e[92mAll add-ons are up-to-date.\e[0m\n"
        NOTIF_ADDONS="Up-to-date"
        return 0
    fi

    while IFS='|' read -r _ id folder lv rv _; do
        ui_echo " \e[33m$folder\e[0m \e[90m$lv\e[0m -> \e[92m$rv\e[0m"
    done <<< "$updates"
    printf '%s\n' "$plan" | grep '^UNKNOWN|' | while IFS='|' read -r _ id folder lv rv _; do
        write_ttc_log "INFO" "Add-on update skipped for $folder: its version ($lv) can't be compared with ESOUI's ($rv)."
    done

    ids=$(printf '%s\n' "$updates" | cut -d'|' -f2 | awk '!seen[$0]++')
    for id in $ids; do
        folder=$(printf '%s\n' "$updates" | awk -F'|' -v i="$id" '$2 == i { print $3; exit }')
        start_spinner "Downloading $folder from ESOUI..."
        TEMP_DIR_USED=true
        if esoui_download "$id" "$TEMP_DIR_ROOT/addon_$id.zip" && install_addon_zip "$TEMP_DIR_ROOT/addon_$id.zip"; then
            stop_spinner 0 "Installed:$ADDON_INSTALLED"
            count=$((count + 1))
            record_addon_install "$id" "$(printf '%s\n' "$updates" | awk -F'|' -v i="$id" '$2 == i { print $6; exit }')"
            case " $ADDON_INSTALLED " in
                *" TamrielTradeCentre "*) TTC_NA_VERSION=0; TTC_EU_VERSION=0 ;;
            esac
        else
            stop_spinner 1 "Update failed for $folder"
            write_ttc_log "WARN" "Add-on update failed for $folder: ESOUI file $id could not be downloaded or installed."
            failed=$((failed + 1))
        fi
        rm -f "$TEMP_DIR_ROOT/addon_$id.zip"
    done
    NOTIF_ADDONS="Updated ($count)"
    [ "$failed" -gt 0 ] && NOTIF_ADDONS="$NOTIF_ADDONS, Failed ($failed)"
    ui_echo ""
}
