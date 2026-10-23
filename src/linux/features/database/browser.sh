awk_sort_logic='
function sort_num(a, n,    i, t) {
    for (i = int(n / 2) - 1; i >= 0; i--) sift_down(a, i, n)
    for (i = n - 1; i > 0; i--) { t = a[0]; a[0] = a[i]; a[i] = t; sift_down(a, 0, i) }
}
function sift_down(a, r, n,    c, t) {
    while ((c = 2 * r + 1) < n) {
        if (c + 1 < n && a[c + 1] > a[c]) c++
        if (a[r] >= a[c]) return
        t = a[r]; a[r] = a[c]; a[c] = t; r = c
    }
}
'

awk_browser_logic='
function name_enc(s) { gsub(/ /, "+", s); gsub(/'\''/, "%27", s); return s }
function ttc_url(name) { return "https://us.tamrieltradecentre.com/pc/Trade/SearchResult?SearchType=Sell&ItemNamePattern=" name_enc(name) }
function item_links(name, id,    u, out) {
    out = "\033[90m[\033]8;;" ttc_url(name) "\033\\TTC\033]8;;\033\\]\033[0m " \
          "\033[90m[\033]8;;https://eso-hub.com/en/trading/" id "\033\\ESO-Hub\033]8;;\033\\]\033[0m"
    if (name ~ /^(Blueprint|Praxis|Design|Pattern|Formula|Diagram|Sketch): /) {
        u = name; sub(/^[^:]+: /, "", u)
        gsub(/ /, "_", u); gsub(/'\''/, "%27", u)
        out = out " \033[90m[\033]8;;https://en.uesp.net/wiki/File:ON-furnishing-" u ".jpg\033\\UESP\033]8;;\033\\]\033[0m"
    } else if (name ~ /Crafting Motif/ || name ~ /Style Page:/) {
        u = name
        sub(/^.*Crafting Motif [^:]+: /, "", u)
        sub(/^.*Style Page: /, "", u)
        sub(/ (Axes|Belts|Boots|Bows|Chests|Daggers|Gloves|Helmets)$/, "", u)
        sub(/ (Legs|Maces|Shields|Shoulders|Staves|Swords|Cuirass)$/, "", u)
        sub(/ (Greaves|Helm|Pauldrons|Sabatons|Gauntlets|Bracers)$/, "", u)
        sub(/ (Epaulets|Jack|Guards|Belt|Shoes|Jerkin|Breeches|Hat)$/, "", u)
        sub(/ (Robes|Sash|Girdle|Corselet|Arm Cops)$/, "", u)
        sub(/ Style$/, "", u)
        gsub(/ /, "_", u); gsub(/'\''/, "%27", u)
        out = out " \033[90m[\033]8;;https://en.uesp.net/wiki/Online:" u "_Style\033\\UESP\033]8;;\033\\]\033[0m"
    }
    return out
}
function band_price(a, n,    trim, valid_n, ms, me, i, sum, c) {
    sort_num(a, n)
    trim = int(n * 0.10); if (trim == 0) trim = 1
    valid_n = n - (2 * trim); if (valid_n < 1) valid_n = 1
    ms = trim + int(valid_n * 0.45); me = trim + int(valid_n * 0.55)
    if (me < ms) me = ms
    sum = 0; c = 0
    for (i = ms; i <= me; i++) { sum += a[i]; c++ }
    return sum / c
}
function row_passes() {
    if (cutoff > 0 && $2 < cutoff) return 0
    if (src_filter != "" && index(tolower($13), src_filter) == 0) return 0
    if (t_user != "" && index(tolower($8), t_user) == 0 && index(tolower($9), t_user) == 0) return 0
    if (index($7, "Unknown Item (") == 1) return 0
    return 1
}
function rel_time(ts,    d) {
    if (ts == 0) return "Active"
    d = now - ts; if (d < 0) d = 0
    if (d < 60) return d "s ago"
    if (d < 3600) return int(d / 60) "m ago"
    if (d < 86400) return int(d / 3600) "h ago"
    return int(d / 86400) "d ago"
}
function sort_key(ts, price, name, idx,    k) {
    if (sort_opt == "2") k = sprintf("%010d", ts)
    else if (sort_opt == "3") k = sprintf("%018.3f", 100000000000000 - price)
    else if (sort_opt == "4") k = sprintf("%018.3f", price)
    else if (sort_opt == "5") k = tolower(name)
    else k = sprintf("%010d", 9999999999 - ts)
    return k "|" sprintf("%09d", idx)
}
'
awk_browser_logic="$awk_sort_logic$awk_browser_logic"

browser_prompt_filters() {
    echo -ne "\033[33mSearch by Source [TTC or ESO-Hub] (leave empty for ALL):\033[0m "; read -r source_filter
    echo -ne "\033[33mFilter to your @Username only? (y/N):\033[0m "; read -r personal_opt

    echo -e "\n\033[33mTime Filter:\033[0m"
    echo -e " 1) Past 1 Week\n 2) Past 2 Weeks\n 3) Past 3 Weeks\n 4) All Data"
    echo -ne "\033[33mChoice [1-4] (default 4):\033[0m "; read -r time_opt

    cutoff_time=0; now_ts=$(date +%s)
    case "$time_opt" in
        1) cutoff_time=$((now_ts - 604800)) ;;
        2) cutoff_time=$((now_ts - 1209600)) ;;
        3) cutoff_time=$((now_ts - 1814400)) ;;
    esac

    t_user=""
    if [[ "$personal_opt" == [Yy] ]]; then
        if [ -z "$TARGET_USERNAME" ]; then echo -e "\033[31m[!] @Username not set!\033[0m"
        else t_user="$TARGET_USERNAME"; fi
    fi
    src_lc="$(printf '%s' "$source_filter" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
    user_lc="$(printf '%s' "$t_user" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
}

browser_cache_file() {
    local hash
    hash=$(echo "$1" | md5sum | awk '{print $1}')
    echo "$CACHE_DIR/cache_${hash}.txt"
}

browser_page() {
    local file="$1" total page=1 pages start key
    total=$(wc -l < "$file" | tr -d ' ')
    pages=$(( (total + 49) / 50 ))
    while true; do
        clear
        echo -e "\033[36m--- Results Page $page of $pages ---\033[0m\n"
        start=$(( (page - 1) * 50 + 1 ))
        sed -n "${start},$((start + 49))p" "$file"
        echo -e "\n\033[33mPress [SPACE] for next page, or 'q' to quit...\033[0m"
        read -rsn1 key
        [[ "$key" == "q" || "$key" == "Q" ]] && break
        [ $((page * 50)) -ge "$total" ] && break
        page=$((page + 1))
    done
}

browser_listing() {
    local mode="$1" s_term sort_opt out
    echo -ne "\033[33mEnter search term (leave empty for ALL data):\033[0m "; read -r s_term
    browser_prompt_filters
    echo -e "\n\033[33mSort By:\033[0m"
    echo -e " 1) Date (Newest First)\n 2) Date (Oldest First)\n 3) Price (Highest First)\n 4) Price (Lowest First)\n 5) Alphabetical (A-Z)"
    echo -ne "\033[33mChoice [1-5]:\033[0m "; read -r sort_opt

    if [ "$mode" = "scan" ]; then echo -e "\n\033[36m--- View Previous Extraction History ---\033[0m"
    else echo -e "\n\033[36mProcessing data...\033[0m"; fi

    out="$TEMP_DIR_ROOT/lttc_browse.out"
    start_spinner "Filtering and sorting..."
    if [ "$mode" = "scan" ]; then
        browser_scan_rows "$LAST_SCAN_FILE" "$s_term" "$sort_opt" > "$out"
    else
        browser_history_rows "$DB_DIR/LTTC_History.db" "$s_term" "$sort_opt" > "$out"
    fi
    stop_spinner 0 "$(wc -l < "$out" | tr -d ' ') results"

    if [ ! -s "$out" ]; then
        echo -e " \033[31m[-] No results found.\033[0m"
        echo -ne "\n\033[33mPress Enter to return...\033[0m "; read -r _
    else
        browser_page "$out"
    fi
    rm -f "$out"
}

browser_history_rows() {
    LC_ALL=C awk -F'|' -v term="$(printf '%s' "$2" | LC_ALL=C tr '[:upper:]' '[:lower:]')" -v sort_opt="$3" \
        -v cutoff="$cutoff_time" -v src_filter="$src_lc" -v t_user="$user_lc" \
        -v now="$(date +%s)" -v db_file="$DB_FILE" '
    '"$awk_browser_logic"'
    BEGIN {
        while ((getline line < db_file) > 0) {
            split(line, p, "|")
            if (p[1] == "GUILD") guild_id[p[2]] = p[3]
        }
        close(db_file)
        '"$master_kiosk_logic"'
    }
    { sub(/\r$/, "") }
    $1 == "HISTORY" {
        if (!row_passes()) next
        if ($10 == "Unknown Guild" || $10 == "Guilds") next
        kname = $11
        if (kname != "" && kname != "0" && (kname in k_dict)) { split(k_dict[kname], kp, "|"); kname = kp[1] }
        if (term != "" && index(tolower($0 "|" kname), term) == 0) next

        act_col = "\033[36m"
        if ($3 == "Sold") act_col = "\033[38;5;214m"
        if ($3 == "Purchased") act_col = "\033[92m"
        if ($3 == "Cancelled") act_col = "\033[31m"

        k_str = ""
        if ($11 != "" && $11 != "0") {
            if ($11 in k_dict) {
                split(k_dict[$11], kp, "|")
                if (kp[2] != "" && kp[3] != "") k_str = " \033[90m(\033]8;;https://eso-hub.com/en/interactive-map?map=" kp[2] "&ping=" kp[3] "\033\\" kp[1] "\033]8;;\033\\)\033[0m"
                else if (kp[2] != "") k_str = " \033[90m(\033]8;;https://eso-hub.com/en/interactive-map?map=" kp[2] "\033\\" kp[1] "\033]8;;\033\\)\033[0m"
                else k_str = " \033[90m(" kp[1] ")\033[0m"
            } else k_str = " \033[90m(Kiosk ID: " $11 ")\033[0m"
        }

        g_str = ""
        if ($10 != "") {
            if ($10 in guild_id) g_str = " in \033[35m\033]8;;|H1:guild:" guild_id[$10] "|h" $10 "|h\033\\" $10 "\033]8;;\033\\\033[0m"
            else g_str = " in \033[35m" $10 "\033[0m"
        }

        link = ($13 == "TTC") ? ttc_url($7) : "https://eso-hub.com/en/trading/" $6
        scans = $14 + 0
        scan_str = (scans > 1) ? " \033[96m[" scans "x Scans]\033[0m" : ""

        trade = ""
        if ($9 != "" && $8 != "") trade = " by \033[36m" $9 "\033[0m to \033[36m" $8 "\033[0m"
        else if ($9 != "") trade = " by \033[36m" $9 "\033[0m"
        else if ($8 != "") trade = " to \033[36m" $8 "\033[0m"

        ts = $2 + 0
        row = " [\033[90m" rel_time(ts) "\033[0m] " act_col $3 "\033[0m for \033[32m" $4 "\033[33mgold\033[0m - \033[32m" $5 "x\033[0m \033]8;;" link "\033\\" $12 $7 "\033[0m\033]8;;\033\\" trade g_str k_str " [\033[90m" $13 "\033[0m]" scan_str
        print sort_key(ts, $4 + 0, $7, NR) "\t" row
    }' "$1" | LC_ALL=C sort -t$'\t' -k1,1 | cut -f2-
}

browser_scan_rows() {
    LC_ALL=C awk -v term="$(printf '%s' "$2" | LC_ALL=C tr '[:upper:]' '[:lower:]')" -v sort_opt="$3" -v now="$(date +%s)" '
    '"$awk_browser_logic"'
    { sub(/\r$/, "") }
    /\[TS:[0-9]+\]|\[\033\[90mListing\033\[0m\]/ {
        plain = $0
        gsub(/\033\]8;;[^\033]*\033\\/, "", plain)
        gsub(/\033\[[0-9;]*m/, "", plain)
        if (term != "" && index(tolower(plain), term) == 0) next
        ts = 0
        if (match($0, /\[TS:[0-9]+\]/)) ts = substr($0, RSTART + 4, RLENGTH - 5) + 0
        price = 0
        if (match(plain, / for [0-9]+gold/)) price = substr(plain, RSTART + 5, RLENGTH - 9) + 0
        name = plain; sub(/^[^-]* - [0-9]+x /, "", name)
        row = $0
        if (ts > 0) sub(/\[TS:[0-9]+\]/, "[\033[90m" rel_time(ts) "\033[0m]", row)
        print sort_key(ts, price, name, NR) "\t" row
    }' "$1" | LC_ALL=C sort -t$'\t' -k1,1 | cut -f2-
}

browser_top_lines() {
    LC_ALL=C awk -F'|' -v kind="$1" -v cutoff="$cutoff_time" -v src_filter="$src_lc" -v t_user="$user_lc" '
    '"$awk_browser_logic"'
    { sub(/\r$/, "") }
    $1 == "HISTORY" && ($3 == "Sold" || $3 == "Purchased" || $3 == "Listed") && $5 > 0 {
        if (!row_passes()) next
        qty = $5 + 0; unit_p = $4 / qty; name = $7
        scans = ($14 != "" && $14 > 0) ? $14 + 0 : 1
        colors[name] = ($12 != "") ? $12 : "\033[0m"
        ids[name] = $6
        for (s = 0; s < scans; s++) {
            prices[name, count[name]++] = unit_p
            if ($3 == "Sold" || $3 == "Purchased") total[name] += (kind == "vol") ? qty : $4
        }
    }
    END {
        for (name in total) {
            n = count[name]; sugg = 0
            if (n >= 5) {
                delete p_arr
                for (i = 0; i < n; i++) p_arr[i] = prices[name, i]
                sugg = band_price(p_arr, n)
            }
            p_str = (sugg == 0) ? "Not enough data" : sprintf("%.2f", sugg) "g"
            if (kind == "vol") lead = " \033[36m" sprintf("%.0f", total[name]) "x\033[0m sold - "
            else lead = " \033[33m" sprintf("%.0f", total[name]) "g\033[0m grossed - "
            printf "%020.3f\t%s\t%s\n", total[name], name, lead colors[name] name "\033[0m (Avg: \033[33m" p_str "\033[0m) " item_links(name, ids[name])
        }
    }' "$2" \
        | LC_ALL=C sort -t$'\t' -k1,1r -k2,2 | head -n 10 | cut -f3-
}

browser_price_lines() {
    LC_ALL=C awk -F'|' -v term="$(printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]')" \
        -v cutoff="$cutoff_time" -v src_filter="$src_lc" -v t_user="$user_lc" '
    '"$awk_browser_logic"'
    { sub(/\r$/, "") }
    $1 == "HISTORY" && index(tolower($7), term) > 0 && ($3 == "Listed" || $3 == "Sold" || $3 == "Purchased") && \
    $4 ~ /^[0-9]+(\.[0-9]+)?$/ && $5 > 0 {
        if (!row_passes()) next
        qty = $5 + 0; unit_p = $4 / qty; name = $7
        scans = ($14 != "" && $14 > 0) ? $14 + 0 : 1
        colors[name] = ($12 != "") ? $12 : "\033[0m"
        ids[name] = $6
        for (s = 0; s < scans; s++) prices[name, count[name]++] = unit_p
    }
    END {
        for (name in count) {
            n = count[name]
            if (n < 5) continue
            delete p_arr
            for (i = 0; i < n; i++) p_arr[i] = prices[name, i]
            sugg = band_price(p_arr, n)
            printf "%s\t%s\n", name, colors[name] name "\033[0m - Suggested Price: \033[33m" sprintf("%.2f", sugg) "g\033[0m (Based on " n " data points) " item_links(name, ids[name])
        }
    }' "$2" \
        | LC_ALL=C sort -t$'\t' -k1,1 | cut -f2-
}

browser_top() {
    local kind="$1" tag title cache_file
    if [ "$kind" = "vol" ]; then
        write_ttc_log "INFO" "DB Browser: Generating Top 10 Selling Items list."; tag="O1v4"
    else
        write_ttc_log "INFO" "DB Browser: Generating Top 10 Highest Grossing Items list."; tag="O2v4"
    fi
    browser_prompt_filters

    if [ "$kind" = "vol" ]; then title="Top 10 Selling Items (By Volume)"; else title="Top 10 Highest Grossing Items"; fi
    if [ -n "$t_user" ]; then echo -e "\n\033[36m--- $title [$t_user] ---\033[0m"
    else echo -e "\n\033[36m--- $title [Global] ---\033[0m"; fi

    cache_file="$(browser_cache_file "$tag|$source_filter|$personal_opt|$time_opt")"
    if [ -f "$cache_file" ] && [ "$cache_file" -nt "$DB_DIR/LTTC_History.db" ]; then
        echo -e " \033[32m[+] Loading instantly from persistent cache...\033[0m\n"
        cat "$cache_file"
    else
        echo ""
        if [ "$kind" = "vol" ]; then start_spinner "Calculating Top 10 by Volume (Building Cache)..."
        else start_spinner "Calculating Top 10 by Grossing (Building Cache)..."; fi
        browser_top_lines "$kind" "$DB_DIR/LTTC_History.db" > "$cache_file"
        stop_spinner 0 "Calculation complete"
        echo ""
        cat "$cache_file"
    fi
    echo ""
}

browser_price_check() {
    local p_term cache_file
    echo -ne "\033[33mEnter exact or partial item name for price check:\033[0m "; read -r p_term
    browser_prompt_filters
    write_ttc_log "INFO" "DB Browser: Executed Suggested Price Check for '$p_term'"

    echo -e "\n\033[36m--- Suggested Price Check ---\033[0m"
    cache_file="$(browser_cache_file "O3v4|$p_term|$source_filter|$personal_opt|$time_opt")"
    if [ -f "$cache_file" ] && [ "$cache_file" -nt "$DB_DIR/LTTC_History.db" ]; then
        echo -e " \033[32m[+] Loading instantly from persistent cache...\033[0m\n"
        cat "$cache_file"
    else
        echo ""
        start_spinner "Calculating Outlier Eliminations (Building Cache)..."
        browser_price_lines "$p_term" "$DB_DIR/LTTC_History.db" > "$cache_file"

        if [ -s "$cache_file" ]; then
            stop_spinner 0 "Calculation complete"
            echo ""
            cat "$cache_file"
        else
            stop_spinner 1 "Not enough data to display anything"
            rm -f "$cache_file" 2>/dev/null
        fi
    fi
    echo ""
}

browser_set_user() {
    local input_user
    echo -e "\n\033[36m--- Settings: Edit My Target Username ---\033[0m"
    echo -ne "\033[33mEnter your exact @Username (leave blank to clear): \033[0m"
    read -r input_user

    if [ -n "$input_user" ]; then input_user="@${input_user#@}"; fi
    if grep -q "^TARGET_USERNAME=" "$CONFIG_FILE" 2>/dev/null; then
        awk -v u="$input_user" '/^TARGET_USERNAME=/ { print "TARGET_USERNAME=\"" u "\""; next } { print }' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" \
            && mv -f "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    else
        echo "TARGET_USERNAME=\"$input_user\"" >> "$CONFIG_FILE"
    fi
    TARGET_USERNAME="$input_user"

    if [ -z "$input_user" ]; then
        echo -e " \033[90m[-] Username cleared.\033[0m\n"
        write_ttc_log "INFO" "DB Browser: Target Username cleared."
    else
        echo -e " \033[92m[+] Username saved as $TARGET_USERNAME\033[0m\n"
        write_ttc_log "INFO" "DB Browser: Target Username updated to '$TARGET_USERNAME'"
    fi
    echo -ne "\033[33mPress Enter to return...\033[0m "; read -r _
}

browse_database() {
    write_ttc_log "INFO" "browse_database: entering DB browser"
    clear
    echo -e "\n\033[92m===========================================================================\033[0m"
    echo -e "\033[1m\033[94m                         TTC & ESO-Hub Database Browser\033[0m"
    echo -e "\033[97m                 (Data automatically retained for the last 30 days)\033[0m"
    echo -e "\033[92m===========================================================================\033[0m\n"

    if [ ! -s "$DB_DIR/LTTC_History.db" ]; then
        echo -e "\033[31m[!] No history database found. Wait for extraction first.\033[0m\n"
        echo -e "\033[31m[!] (or go visit a guild store in-game and press scan then /reloadui)\033[0m\n"
        echo -ne "\033[33mPress Enter to return...\033[0m "; read -r _; return
    fi

    if [ -f "$CONFIG_FILE" ] && grep -q '^TARGET_USERNAME=' "$CONFIG_FILE"; then
        TARGET_USERNAME="$(sed -n 's/^TARGET_USERNAME="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$CONFIG_FILE" | tail -n 1)"
    fi

    CACHE_DIR="$TARGET_DIR/Cache"
    mkdir -p "$CACHE_DIR"

    while true; do
        echo -e "\n\033[33mSelect a Database Function:\033[0m"
        echo -e " 1) View / Search Database (Paginated & Sorted)"
        echo -e " 2) Top 10 Most Selling Items (By Volume)"
        echo -e " 3) Top 10 Highest Grossing Items (By Total Gold)"
        echo -e " 4) Suggested Price Calculator (Outlier Elimination)"
        echo -e " 5) View Previous Extraction History (Paginated & Sorted)"
        echo -e " 6) Settings: Edit My Target Username \033[90m(Current: ${TARGET_USERNAME:-None})\033[0m"
        echo -e " 7) Exit Browser & Resume Updater"
        echo -ne "\033[33mChoice [1-7]:\033[0m "; read -r b_opt

        case $b_opt in
            1) browser_listing db ;;
            2) browser_top vol ;;
            3) browser_top gold ;;
            4) browser_price_check ;;
            5) browser_listing scan ;;
            6) browser_set_user ;;
            7) write_ttc_log "INFO" "browse_database: exiting DB browser"; break ;;
            *) echo -e "\033[31mInvalid option.\033[0m" ;;
        esac
    done
    clear
    if [ "$SILENT" = false ]; then
        echo -ne "\033]0;$APP_TITLE - Created by @APHONIC\007"
        if [ -s "$UI_STATE_FILE" ]; then print_dynamic_log "$UI_STATE_FILE"; fi
    fi
}
