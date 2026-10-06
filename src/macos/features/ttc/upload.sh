TTC_WEB_CLIENT_VERSION="3.1.0.0"
TTC_BATCH_SIZE=100

ttc_client_id() {
    if [ -z "${TTC_CLIENT_ID:-}" ]; then
        if command -v uuidgen > /dev/null 2>&1; then
            TTC_CLIENT_ID="$(uuidgen | tr 'A-Z' 'a-z')"
        elif [ -r /proc/sys/kernel/random/uuid ]; then
            TTC_CLIENT_ID="$(cat /proc/sys/kernel/random/uuid)"
        else
            TTC_CLIENT_ID="$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n' \
                | sed -E 's/^(.{8})(.{4})(.{4})(.{4})(.{12}).*/\1-\2-4\3-a\4-\5/' | cut -c1-36)"
        fi
        CONFIG_CHANGED=true
    fi
}

ttc_upload_parse() {
    awk -v region="$2" -v now="$3" -v cache="$4" '
    function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r,]+$/, "", s); return s }
    function unkey(s) { s = trim(s); sub(/^\[/, "", s); sub(/\]$/, "", s); if (s ~ /^".*"$/) s = substr(s, 2, length(s) - 2); return s }
    function jstr(s) { return "\"" s "\"" }
    function field(d, k) { return ((d, k) in val) ? val[d, k] : "" }
    function add(json, name, v) { if (v == "" || v == "nil") return json; return json (json == "" ? "" : ",") "\"" name "\":" v }
    function sorted_list(d,    n, i, j, t, a, out) {
        n = 0
        for (i = 0; i < 64; i++) if ((d, "#" i) in val) a[++n] = val[d, "#" i] + 0
        for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (a[j] < a[i]) { t = a[i]; a[i] = a[j]; a[j] = t }
        out = ""
        for (i = 1; i <= n; i++) out = out (i > 1 ? "," : "") a[i]
        return "[" out "]"
    }
    function put(d, k, v) { if (!((d, k) in val)) klist[d] = klist[d] (klist[d] == "" ? "" : SUBSEP) k; val[d, k] = v }
    function clear(d,    n, i, p) { n = split(klist[d], p, SUBSEP); for (i = 1; i <= n; i++) delete val[d, p[i]]; klist[d] = "" }
    function item_json(d,    j) {
        j = ""
        j = add(j, "ID", field(d, "ID"))
        j = add(j, "UID", field(d, "UID"))
        j = add(j, "QualityID", field(d, "QualityID"))
        j = add(j, "Category2IDOverWrite", field(d, "Category2IDOverWrite"))
        j = add(j, "TraitID", field(d, "TraitID"))
        j = add(j, "LevelTotal", field(d, "Level"))
        j = add(j, "PotionEffectIDs", field(d, "PotionEffects"))
        j = add(j, "MasterWritInfo", field(d, "MasterWritInfo") == "" ? "null" : field(d, "MasterWritInfo"))
        return "{" j "}"
    }
    function close_table(d,    sub_d, j, key) {
        key = stack[d]
        if (d >= 2 && stack[d - 1] != "" && (key == "PotionEffects" || key == "RequiredPotionEffectIDs")) {
            put(d - 1, key, sorted_list(d))
        } else if (key == "MasterWritInfo") {
            j = ""
            j = add(j, "RequiredItemID", field(d, "RequiredItemID"))
            j = add(j, "RequiredQualityID", field(d, "RequiredQualityID"))
            j = add(j, "RequiredTraitID", field(d, "RequiredTraitID"))
            j = add(j, "RequiredSetID", field(d, "RequiredSetID"))
            j = add(j, "RequiredStyleID", field(d, "RequiredStyleID"))
            j = add(j, "RequiredPotionEffectIDs", field(d, "RequiredPotionEffectIDs"))
            j = add(j, "NumVoucher", field(d, "NumVoucher"))
            put(d - 1, "MasterWritInfo", "{" j "}")
        } else if (d == 9 && stack[5] == region "Data" && stack[6] == "Guilds" && stack[8] == "Entries") {
            n_self++
            self_acct[n_self] = stack[3]; self_guild[n_self] = stack[7]
            self_asset[n_self] = add(add("", "Amount", field(d, "Amount")), "TotalPrice", field(d, "TotalPrice"))
            self_item[n_self] = item_json(d); self_uid[n_self] = field(d, "UID"); self_link[n_self] = field(d, "ItemLink")
        } else if (d == 7 && stack[5] == region "Data" && stack[6] == "Guilds") {
            guild_scan[stack[3], stack[7]] = field(d, "LastFullScan")
            guild_kiosk[stack[3], stack[7]] = field(d, "KioskLocationID")
        } else if (d == 11 && stack[5] == region "Data" && stack[6] == "AutoRecordEntries" && stack[9] == "PlayerListings") {
            n_auto++
            auto_acct[n_auto] = stack[3]; auto_guild[n_auto] = stack[8]; auto_player[n_auto] = stack[10]
            auto_asset[n_auto] = add(add("", "Amount", field(d, "Amount")), "TotalPrice", field(d, "TotalPrice"))
            auto_item[n_auto] = item_json(d); auto_uid[n_auto] = field(d, "UID"); auto_link[n_auto] = field(d, "ItemLink")
            auto_discover[n_auto] = field(d, "DiscoverTime"); auto_expire[n_auto] = field(d, "ExpireTime")
        } else if (d == 8 && stack[5] == region "Data" && stack[6] == "AutoRecordEntries" && stack[7] == "Guilds") {
            auto_kiosk[stack[3], stack[8]] = field(d, "KioskLocationID")
            auto_update[stack[3], stack[8]] = field(d, "LastUpdate")
        } else if (d == 5 && stack[5] == "Settings") {
            set_auto[stack[3]] = field(d, "EnableAutoRecordStoreEntries")
            set_self[stack[3]] = field(d, "EnableSelfEntriesUpload")
        } else if (d == 4 && stack[4] == "$AccountWide") {
            acct_version[stack[3]] = field(d, "ActualVersion")
            acct_culture[stack[3]] = field(d, "ClientCulture")
            accounts[stack[3]] = 1
        }
        clear(d)
    }
    function keep(acct, guild, player, asset, item, uid, link, discover, expire, kiosk,    u, j) {
        if (discover == "" || expire == "") return
        discover += 0; expire += 0
        if (discover <= now && discover > newest) newest = discover
        u = uid; gsub(/"/, "", u)
        if (u == "" || u == "0") return
        if (((u "|" discover) in sent) || now > expire || discover > now || now - discover > 21600) return
        if (item !~ /"ID":/) { gsub(/"/, "", link); if (link != "") nolink[++n_nolink] = link; return }
        j = "{\"TradeAsset\":{" asset ",\"Item\":" item "},\"PlayerID\":" jstr(player) ",\"GuildID\":@@"
        if (kiosk != "") j = j ",\"GuildKioskLocationID\":" kiosk
        j = j ",\"DiscoverUnixTime\":" discover ",\"ExpireUnixTime\":" expire "}"
        if ((u in best) && best[u] >= discover) return
        best[u] = discover; pick_guild[u] = guild; pick_json[u] = j
        need_guild[guild] = 1
    }
    BEGIN {
        depth = 0; pending = ""; newest = 0
        if (cache != "") while ((getline l < cache) > 0) { split(l, p, "\t"); sent[p[1] "|" p[2]] = 1 }
    }
    {
        line = $0; sub(/\r$/, "", line); t = trim(line)
        if (t == "{") { depth++; stack[depth] = pending; pending = ""; next }
        if (t == "}" || t == "},") { close_table(depth); depth--; next }
        eq = index(t, "=")
        if (eq == 0) next
        k = unkey(substr(t, 1, eq - 1)); v = trim(substr(t, eq + 1))
        if (v == "") { pending = k; next }
        if (k ~ /^[0-9]+$/) k = "#" k
        put(depth, k, v)
    }
    END {
        for (a in accounts) {
            if (acct_version[a] + 0 < 7) continue
            if (culture == "") culture = acct_culture[a]
            if (set_auto[a] == "true") for (i = 1; i <= n_auto; i++) if (auto_acct[i] == a && auto_kiosk[a, auto_guild[i]] != "") {
                keep(a, auto_guild[i], auto_player[i], auto_asset[i], auto_item[i], auto_uid[i], auto_link[i],
                    auto_discover[i], auto_expire[i], auto_kiosk[a, auto_guild[i]])
                kiosks[auto_guild[i]] = auto_kiosk[a, auto_guild[i]] "\t" auto_update[a, auto_guild[i]]
            }
            if (set_self[a] == "true") for (i = 1; i <= n_self; i++) if (self_acct[i] == a) {
                scan = guild_scan[a, self_guild[i]]
                keep(a, self_guild[i], a, self_asset[i], self_item[i], self_uid[i], self_link[i],
                    scan, scan == "" ? "" : scan + 604800, guild_kiosk[a, self_guild[i]])
            }
        }
        for (g in need_guild) print "G\t" g
        for (u in pick_json) print "E\t" pick_guild[u] "\t" pick_json[u]
        for (i = 1; i <= n_nolink; i++) print "L\t" nolink[i]
        for (g in kiosks) if (g in need_guild) print "K\t" g "\t" kiosks[g]
        gsub(/"/, "", culture)
        print "C\t" culture
        print "N\t" newest
    }' "$1"
}

ttc_upload_remember() {
    tr '{' '\n' < "$1" | awk -v at="$2" '
        /"UID":/ { u = $0; sub(/.*"UID":/, "", u); sub(/[,}].*/, "", u); gsub(/"/, "", u) }
        /"DiscoverUnixTime":/ { d = $0; sub(/.*"DiscoverUnixTime":/, "", d); sub(/[,}].*/, "", d); print u "\t" d "\t" at }'
}

ttc_post_json() {
    curl -s -f -m 60 -X POST -A "$TTC_USER_AGENT" \
        -H "Content-Type: application/json; charset=UTF-8" \
        -H "WebClientVersion: $TTC_WEB_CLIENT_VERSION" \
        -H "ClientID: $TTC_CLIENT_ID" \
        --data-binary "@$2" "https://$1$3" > /dev/null 2>&1
}

ttc_upload_cache() { printf '%s/LTTC_TTC_Uploaded_%s.txt' "$DB_DIR" "$1"; }

ttc_upload() {
    local domain="$1" region="$2" sv="$3" now cache work map guild id ok=0 count=0 total
    TTC_UPLOAD_COUNT=0; TTC_UPLOAD_NEWEST=0
    ttc_client_id
    now="$(date +%s)"
    cache="$(ttc_upload_cache "$region")"
    [ -f "$cache" ] || : > "$cache" 2>/dev/null
    work="$(mktemp -d "$TEMP_DIR_ROOT/lttc_upload.XXXXXX")" || return 1
    ttc_upload_parse "$sv" "$region" "$now" "$cache" > "$work/parsed" 2>/dev/null || { rm -rf "$work"; return 1; }
    TTC_UPLOAD_NEWEST="$(awk -F '\t' '$1 == "N" { print $2 + 0 }' "$work/parsed")"
    map="$work/guilds"
    : > "$map"
    while IFS="$(printf '\t')" read -r kind guild _; do
        [ "$kind" = "G" ] || continue
        id="$(curl -s -f -m 30 -G -A "$TTC_USER_AGENT" -H "WebClientVersion: $TTC_WEB_CLIENT_VERSION" \
            -H "ClientID: $TTC_CLIENT_ID" --data-urlencode "guildName=$guild" \
            "https://$domain/api/PC/Trade/GetGuildID" 2>/dev/null | grep -oE '"GuildID":[0-9]+' | grep -oE '[0-9]+')"
        [ -n "$id" ] && printf '%s\t%s\n' "$guild" "$id" >> "$map"
    done < "$work/parsed"

    awk -F '\t' -v dir="$work" -v size="$TTC_BATCH_SIZE" '
        FILENAME == ARGV[1] { id[$1] = $2; next }
        $1 == "E" && ($2 in id) {
            j = $3; sub(/@@/, id[$2], j)
            n++; b = int((n - 1) / size) + 1
            f = dir "/batch" b
            printf "%s%s", (n % size == 1 || size == 1) ? "[" : ",", j > f
            last = f
        }
        $1 == "E" && !($2 in id) { missing++ }
        END {
            for (i = 1; i <= int((n + size - 1) / size); i++) printf "]" >> (dir "/batch" i)
            print n + 0 > (dir "/count"); print missing + 0 > (dir "/missing")
        }' "$map" "$work/parsed"

    total="$(cat "$work/count" 2>/dev/null)"
    [ "$(cat "$work/missing" 2>/dev/null)" != "0" ] && ok=1
    for batch in "$work"/batch*; do
        [ -f "$batch" ] || continue
        if ttc_post_json "$domain" "$batch" "/api/PC/Trade/PostAutoRecordedEntry"; then
            count=$((count + $(grep -o '"DiscoverUnixTime"' "$batch" | wc -l)))
            ttc_upload_remember "$batch" "$now" >> "$cache"
        else
            ok=1
        fi
    done

    if [ "${total:-0}" -gt 0 ]; then
        if [ "$(awk -F '\t' '$1 == "C" { print $2 }' "$work/parsed")" = "en" ]; then
            local links
            links="$(awk -F '\t' '$1 == "L" { gsub(/"/, "", $2); if (!seen[$2]++) printf "%s\"%s\"", (n++ ? "," : "["), $2 } END { if (n) print "]" }' "$work/parsed")"
            if [ -n "$links" ] && [ "$(printf '%s' "$links" | grep -o '|h|h' | wc -l)" -lt $((total / 5)) ]; then
                printf '%s' "$links" > "$work/links"
                ttc_post_json "$domain" "$work/links" "/api/PC/Trade/RecordItemLinks"
            fi
        fi
        awk -F '\t' 'FILENAME == ARGV[1] { id[$1] = $2; next } $1 == "K" && ($2 in id) && $3 != "" {
            printf "{\"GuildID\":%s,\"GuildKioskLocationID\":%s,\"Timestamp\":%s}\n", id[$2], $3, ($4 == "" ? 0 : $4) }' \
            "$map" "$work/parsed" | while read -r kiosk; do
                printf '%s' "$kiosk" > "$work/kiosk"
                ttc_post_json "$domain" "$work/kiosk" "/api/PC/Trade/VerifyKioskLocation"
            done
    fi

    if [ -s "$cache" ]; then
        awk -F '\t' -v cut=$((now - 172800)) '$2 + 0 >= cut' "$cache" > "$work/cache" && cat "$work/cache" > "$cache"
    fi
    TTC_UPLOAD_COUNT="$count"
    rm -rf "$work"
    return "$ok"
}

ttc_nothing_new_reason() {
    local newest="${TTC_UPLOAD_NEWEST:-0}" now
    now="$(date +%s)"
    if [ "$newest" -le 0 ]; then
        printf 'no listings in TamrielTradeCentre.lua yet'
    elif [ $((now - newest)) -gt 21600 ]; then
        printf 'newest scan saved is %s, TTC takes the last 6 hours; ESO saves new scans on /reloadui or logout' "$(ttc_clock "$newest")"
    else
        printf 'every listing up to %s was already uploaded; ESO saves new scans on /reloadui or logout' "$(ttc_clock "$newest")"
    fi
}

ttc_clock() {
    local z off
    z="$(date +%z)"
    off=$(( (10#${z:1:2} * 3600 + 10#${z:3:2} * 60) ))
    [ "${z:0:1}" = "-" ] && off=$((-off))
    printf '%02d:%02d' $(( (($1 + off) / 3600) % 24 )) $(( (($1 + off) / 60) % 60 ))
}
