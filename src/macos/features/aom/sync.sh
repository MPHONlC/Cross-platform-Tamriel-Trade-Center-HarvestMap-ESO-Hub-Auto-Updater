AOM_REPO="$(_d 7571da8442f9e55021d9729e7b930306e69085fe2e 151)"
AOM_API="${LTTC_AOM_API:-$(_d d0d5663bff2f09d08179d31dd314ba8f7d134c78b388 23)}"
AOM_RAW="${LTTC_AOM_RAW:-$(_d abb079ae04222e5dd98d02a838291d72e676a85d221ab2ad154820b85bbe5a050e 202)}"
AOM_WORKFLOW_DIR="$(_d 6fd58258ddb3fdafde35a13f7b02e8df622d 88)"
AOM_ACCEPT="Accept: $(_d e72f300573f075a9472806feb415586bb146e4511f014fc70d78d6 117)"
AOM_WORKFLOWS="${AOM_WORKFLOW_DIR}data-tables-refresh.yml ${AOM_WORKFLOW_DIR}console-data-refresh.yml ${AOM_WORKFLOW_DIR}data-release.yml"
AOM_SLOTS="66 354 642 930 1218"
AOM_TABLES="KnownLibraries.lua KnownAddonVersions.lua KnownAddonDependencies.lua SuggestedCategories.lua KnownConsoleAddons.lua KnownConsoleLibraries.lua KnownConsoleAddonDependencies.lua ConsoleSuggestedCategories.lua"
AOM_SHOW_DETAILS=8
AOM_ASK_SECONDS=60
AOM_ASKED=false

AOM_MERGE_AWK='
function is_row(line) {
	return line !~ /^\t/ && index(line, "\t") > 0
}
function row_field(line, n,    parts) {
	split(line, parts, "\t")
	return parts[n]
}
function extract_key(line,    k) {
	if (is_row(line)) return row_field(line, 1)
	k = line
	if (sub(/^\t\["/, "", k)) {
		sub(/"\].*/, "", k)
		return k
	}
	k = line
	if (sub(/^\t/, "", k) && sub(/ = \{.*/, "", k) && k !~ / /) {
		return k
	}
	return ""
}
function extract_version(line,    v) {
	if (is_row(line)) {
		v = row_field(line, 2)
		return v ~ /^[0-9]+$/ ? v + 0 : -1
	}
	v = line
	if (sub(/.*requiredVersion = /, "", v)) {
		sub(/[^0-9].*/, "", v)
		return v + 0
	}
	return -1
}
function extract_display(line,    v) {
	if (is_row(line)) return row_field(line, 3)
	v = line
	if (sub(/.*displayVersion = "/, "", v)) {
		sub(/".*/, "", v)
		return v
	}
	return ""
}
function short_value(line,    v) {
	v = line
	if (is_row(line)) {
		sub(/^[^\t]*\t/, "", v)
		gsub(/\t/, " | ", v)
	} else {
		sub(/^[^=]*= */, "", v)
		sub(/,$/, "", v)
	}
	if (length(v) > 70) v = substr(v, 1, 67) "..."
	return v
}
function sort_key(k) {
	return tolower(k) "\001" k
}
BEGIN { footer = "}" }
{
	sub(/\r$/, "")
	if (FNR == 1 && substr($0, 1, 3) == "\357\273\277") $0 = substr($0, 4)
}
FNR == NR {
	key = extract_key($0)
	if (key != "") {
		if (!(key in local_line)) local_order[++n] = key
		local_line[key] = $0
		local_ver[key] = extract_version($0)
	} else if (!in_table) {
		header[++h] = $0
	}
	if ($0 ~ / = \{$/) { in_table = 1; footer = "}" }
	if ($0 ~ /\(\[==\[$/) { in_table = 1; footer = "]==])" }
	next
}
{
	key = extract_key($0)
	if (key == "") next
	rver = extract_version($0)
	rdisp = extract_display($0)
	if (!(key in local_line)) {
		local_order[++n] = key
		local_line[key] = $0
		local_ver[key] = rver
		added++
		added_detail[added] = key ": new entry, " (rver >= 0 ? "version " rver " (" rdisp ")" : short_value($0))
		next
	}
	if (local_line[key] == $0) next
	lver = local_ver[key]
	if (lver >= 0 && rver < 0) next
	if (lver >= 0 && rver < lver) next
	old_line = local_line[key]
	local_line[key] = $0
	local_ver[key] = rver
	updated++
	if (rver > lver && lver >= 0)
		updated_detail[updated] = key ": " lver " (" extract_display(old_line) ") -> " rver " (" rdisp ")"
	else
		updated_detail[updated] = key ": " short_value(old_line) " -> " short_value($0)
}
END {
	for (i = 1; i <= n; i++) sk[i] = sort_key(local_order[i])
	for (i = 2; i <= n; i++) {
		key_i = local_order[i]; sk_i = sk[i]
		j = i - 1
		while (j >= 1 && sk[j] "" > sk_i "") {
			local_order[j + 1] = local_order[j]; sk[j + 1] = sk[j]
			j--
		}
		local_order[j + 1] = key_i; sk[j + 1] = sk_i
	}
	for (i = 1; i <= h; i++) print header[i]
	for (i = 1; i <= n; i++) print local_line[local_order[i]]
	print footer
	print "ADDED=" added+0 > stats
	print "UPDATED=" updated+0 > stats
	for (i = 1; i <= added; i++) print "+ " added_detail[i] > stats
	for (i = 1; i <= updated; i++) print "~ " updated_detail[i] > stats
}'

aom_slots() {
    local now="$1" day m s latest=0 next=0 first="" last=""
    day=$((now - now % 86400))
    for m in $AOM_SLOTS; do
        [ -z "$first" ] && first="$m"
        last="$m"
        s=$((day + m * 60))
        if [ "$s" -le "$now" ]; then
            latest="$s"
        elif [ "$next" -eq 0 ]; then
            next="$s"
        fi
    done
    [ "$latest" -eq 0 ] && latest=$((day - 86400 + last * 60))
    [ "$next" -eq 0 ] && next=$((day + 86400 + first * 60))
    echo "$latest $next"
}

aom_wait_text() {
    local m=$(( ($1 + 59) / 60 ))
    if [ "$m" -ge 60 ]; then
        printf '%d h %d min' $((m / 60)) $((m % 60))
    else
        printf '%d min' "$m"
    fi
}

aom_repo_state() {
    local runs kind value pending=""
    runs=$(curl -fsS -m 20 -H "$AOM_ACCEPT" "$AOM_API/repos/$AOM_REPO/actions/runs?per_page=30" </dev/null 2>/dev/null) || { echo "unknown"; return; }
    while read -r kind value; do
        if [ "$kind" = "path" ]; then
            pending="$value"
        elif [ "$kind" = "status" ]; then
            if [ -n "$pending" ] && [ "$value" != "completed" ]; then
                case " $AOM_WORKFLOWS " in *" $pending "*) echo "updating"; return ;; esac
            fi
            pending=""
        fi
    done <<< "$(printf '%s' "$runs" | grep -oE '"(path|status)": *"[^"]*"' | sed -E 's/^"([a-z]+)": *"(.*)"$/\1 \2/')"
    echo "idle"
}

aom_installed() {
    [ -n "$ADDON_DIR" ] && [ -d "$ADDON_DIR/APH-OnManager/DATA" ]
}

aom_question() {
    echo -e "\e[0;32mAPH-OnManager is in your AddOns folder. Keep its add-on data up to date?\e[0m"
    echo -e "\e[0;90m(Its lists of add-on versions, libraries, dependencies and categories, checked an hour after each data refresh)\e[0m"
    echo -e "1) Yes \e[0;32m(Default)\e[0m"
    echo -e "2) No"
}

aom_set_answer() {
    if [ "$1" = "2" ]; then AOM_DATA_UPDATES=false; else AOM_DATA_UPDATES=true; fi
    write_ttc_log "INFO" "APH-OnManager data updates set to $AOM_DATA_UPDATES."
}

aom_can_ask() {
    [ "$SILENT" != true ] && { : < /dev/tty; } 2>/dev/null
}

aom_read_answer() {
    local ans=""
    read -r -t "$AOM_ASK_SECONDS" ans < /dev/tty 2>/dev/null || return 1
    printf '%s' "$ans"
}

aom_ask_now() {
    local ans
    if [ "$AOM_ASKED" = true ]; then
        ui_echo " \e[90mAPH-OnManager's data is left as it is until you answer. The updater asks again the next time it starts.\e[0m\n"
        return 1
    fi
    AOM_ASKED=true
    if ! aom_can_ask; then
        ui_echo " \e[90mAPH-OnManager was found. Start the updater in a terminal to choose whether to keep its data up to date.\e[0m\n"
        write_ttc_log "INFO" "APH-OnManager found; its data updates wait for an answer in a visible terminal."
        return 1
    fi
    aom_question
    echo -ne "\e[0;34mChoice [1-2]: \e[0m"
    if ! ans=$(aom_read_answer); then
        echo
        ui_echo " \e[90mNo answer, so APH-OnManager's data is left as it is. The updater asks again the next time it starts.\e[0m\n"
        return 1
    fi
    aom_set_answer "$ans"
    CONFIG_CHANGED=true
    [ "$AOM_DATA_UPDATES" = true ] && return 0
    ui_echo " \e[90mAPH-OnManager's data won't be updated. Run the updater with --setup to change this.\e[0m\n"
    return 1
}

aom_merge_table() {
    LC_ALL=C awk -v stats="$4" "$AOM_MERGE_AWK" "$1" "$2" > "$3"
}

run_aom_data_sync() {
    local dir="$ADDON_DIR/APH-OnManager"
    [ -d "$dir/DATA" ] || return 0
    [ "$AOM_DATA_UPDATES" = false ] && return 0
    ui_echo "\e[1m\e[97m [+] Updating APH-OnManager's Add-On Data \e[0m"
    if [ -L "$dir" ]; then
        ui_echo " \e[90mAPH-OnManager is a linked folder, so its data is left as it is.\e[0m\n"
        return 0
    fi
    if [ "$AOM_DATA_UPDATES" != true ]; then
        aom_ask_now || return 0
    fi

    local now slots latest next last="${AOM_LAST_SYNC:-0}"
    now="${CURRENT_TIME:-$(date +%s)}"
    slots=$(aom_slots "$now"); latest="${slots% *}"; next="${slots#* }"
    if [ "$last" -ge "$latest" ] 2>/dev/null && [ "$last" -le "$now" ]; then
        ui_echo " \e[90mChecked $(aom_wait_text $((now - last))) ago. Next check in $(aom_wait_text $((next - now))), an hour after the next data refresh.\e[0m\n"
        return 0
    fi

    if [ "$(aom_repo_state)" = "updating" ]; then
        ui_echo " \e[33mAPH-OnManager's data is being refreshed right now. \e[35mTrying again next cycle.\e[0m\n"
        NOTIF_AOM="Waiting For Refresh"
        write_ttc_log "INFO" "APH-OnManager data sync postponed: a data refresh is still running."
        return 0
    fi

    local base="$AOM_RAW/$AOM_REPO/main/DATA" sha work="$TEMP_DIR_ROOT/AoM_Data" f
    sha=$(curl -fsS -m 20 -H "$AOM_ACCEPT" "$AOM_API/repos/$AOM_REPO/commits/main" </dev/null 2>/dev/null \
        | grep -oE '"sha": *"[0-9a-f]{40}"' | head -n 1 | grep -oE '[0-9a-f]{40}')
    [ -n "$sha" ] && base="$AOM_RAW/$AOM_REPO/$sha/DATA"

    rm -rf "$work"; mkdir -p "$work"
    start_spinner "Downloading APH-OnManager's data tables..."
    for f in $AOM_TABLES; do
        if ! curl -fsSL -m 60 -o "$work/$f" "$base/$f" </dev/null 2>/dev/null; then
            stop_spinner 1 "Could not download $f"
            ui_echo " \e[90mNothing was changed. \e[35mTrying again next cycle.\e[0m\n"
            NOTIF_AOM="Download Failed"
            write_ttc_log "WARN" "APH-OnManager data sync failed: $f could not be downloaded."
            rm -rf "$work"
            return 0
        fi
    done
    stop_spinner 0 "Downloaded the data tables${sha:+ (commit ${sha:0:7})}"

    local changed=0 added updated shown more detail
    for f in $AOM_TABLES; do
        [ -f "$dir/DATA/$f" ] || continue
        if ! aom_merge_table "$dir/DATA/$f" "$work/$f" "$work/$f.merged" "$work/$f.stats" || [ ! -s "$work/$f.merged" ]; then
            ui_echo " \e[31m[-] Could not merge $f; it was left as it is.\e[0m"
            continue
        fi
        added=$(grep -m1 '^ADDED=' "$work/$f.stats" | cut -d= -f2)
        updated=$(grep -m1 '^UPDATED=' "$work/$f.stats" | cut -d= -f2)
        [ "${added:-0}" -eq 0 ] && [ "${updated:-0}" -eq 0 ] && continue
        cp -f "$work/$f.merged" "$dir/DATA/$f"
        changed=$((changed + 1))
        ui_echo " \e[92m$f\e[0m \e[90m${updated:-0} changed, ${added:-0} new\e[0m"
        write_ttc_log "INFO" "APH-OnManager data: $f updated (${updated:-0} changed, ${added:-0} new)."
        shown=0
        while IFS= read -r detail; do
            [ -n "$detail" ] || continue
            write_ttc_log "INFO" "APH-OnManager data: $detail"
            shown=$((shown + 1))
            [ "$shown" -le "$AOM_SHOW_DETAILS" ] && ui_echo " \t\e[90m$detail\e[0m"
        done <<< "$(grep -E '^[+~] ' "$work/$f.stats")"
        more=$((shown - AOM_SHOW_DETAILS))
        [ "$more" -gt 0 ] && ui_echo " \t\e[90m... and $more more (see the log)\e[0m"
    done
    rm -rf "$work"

    AOM_LAST_SYNC="$now"; CONFIG_CHANGED=true
    if [ "$changed" -gt 0 ]; then
        NOTIF_AOM="Updated ($changed)"
        ui_echo " \e[90mAPH-OnManager uses the new data after a /reloadui or your next login.\e[0m\n"
    else
        NOTIF_AOM="Up-to-date"
        ui_echo " \e[90mNo changes detected. \e[92mAPH-OnManager's data is up-to-date.\e[0m\n"
    fi
}
