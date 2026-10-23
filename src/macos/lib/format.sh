version_diff() {
    local old="$1" new="$2" no nn min pre=0 suf=0
    no=${#old}; nn=${#new}; min=$no; [ "$nn" -lt "$min" ] && min=$nn
    while [ "$pre" -lt "$min" ] && [ "${old:pre:1}" = "${new:pre:1}" ]; do pre=$((pre + 1)); done
    while [ "$suf" -lt $((min - pre)) ] && [ "${old:$((no - 1 - suf)):1}" = "${new:$((nn - 1 - suf)):1}" ]; do suf=$((suf + 1)); done
    local opre="${old:0:pre}" omid="${old:pre:$((no - pre - suf))}" osuf="${old:$((no - suf))}" nmid="${new:pre:$((nn - pre - suf))}"
    printf '\e[0m%s\e[31m%s\e[0m%s \e[90m->\e[0m \e[0m%s\e[92m%s\e[0m%s' "$opre" "$omid" "$osuf" "$opre" "$nmid" "$osuf"
}

age_short() {
    local s="$1"
    [ "$s" -lt 0 ] 2>/dev/null && s=0
    if [ "$s" -ge 86400 ]; then echo "$((s / 86400))d $(((s % 86400) / 3600))h"
    elif [ "$s" -ge 3600 ]; then echo "$((s / 3600))h $(((s % 3600) / 60))m"
    elif [ "$s" -ge 60 ]; then echo "$((s / 60))m"
    else echo "${s}s"; fi
}

size_human() {
    local b="$1"
    if [ "$b" -ge 1048576 ]; then printf '%d.%d MB' "$((b / 1048576))" "$(((b % 1048576) * 10 / 1048576))"
    elif [ "$b" -ge 1024 ]; then printf '%d.%d KB' "$((b / 1024))" "$(((b % 1024) * 10 / 1024))"
    else printf '%d B' "$b"; fi
}

count_history_uids() {
    awk -F'|' '
    $1 == "HISTORY" {
        if ($NF ~ /^[0-9]+$/) src = $(NF - 1); else src = $NF
        if (src ~ /^(Unknown|\[Unknown\])$/ || src == "") src = "TTC"
        u = $6 "|" $3 "|" $4 "|" $5 "|" src
        if (!(u in seen)) { seen[u] = 1; c++ }
    }
    END { print c + 0 }
    ' "$1" 2>/dev/null
}
