merge_db_updates() {
    local updates="$1"
    if [ -n "$updates" ]; then
        local header=$(grep "^#DATABASE VERSION" "$DB_FILE" 2>/dev/null)
        echo "$updates" | awk -F'|' -v db="$DB_FILE" '
        BEGIN {
            while ((getline < db) > 0) {
                if ($1 == "GUILD") { lines["GUILD_"$2] = $0 }
                else if ($1 == "KIOSK") { lines["KIOSK_"$2] = $0 }
                else if ($1 ~ /^[0-9]+$/) { lines["ITEM_"$1] = $0 }
            }
            close(db)
        }
        {
            if ($1 == "DB_UPDATE") {
                id = $2; val = $2
                for(i=3; i<=NF; i++) val = val "|" $i
                lines["ITEM_"id] = val
            } else if ($1 == "DB_GUILD") {
                gname = $2; gid = $3; lines["GUILD_"gname] = "GUILD|" gname "|" gid
            } else if ($1 == "DB_KIOSK") {
                lines["KIOSK_"$2] = "KIOSK|" $2 "|" $3 "|" $4 "|" $5
            }
        }
        END { for (k in lines) { print lines[k] } }' > "$DB_FILE.tmp"
        LC_ALL=C sort -t'|' -k1,1 -k7,7 -k6,6 "$DB_FILE.tmp" -o "$DB_FILE.tmp" 2>/dev/null
        if [ -n "$header" ]; then
            echo "$header" > "$DB_FILE"
            cat "$DB_FILE.tmp" >> "$DB_FILE"
        else
            mv "$DB_FILE.tmp" "$DB_FILE"
        fi
        rm -f "$DB_FILE.tmp" 2>/dev/null
    fi
}

history_merge() {
    awk -F'|' -v OFS='|' -v db="$DB_FILE" -v scan_mode="${3:-add}" '
    BEGIN {
        uid_count = 0
        while ((getline line < db) > 0) {
            split(line, p, "|")
            if (p[1] ~ /^[0-9]+$/) {
                q_num = p[2] + 0
                c = "\033[0m"
                if(q_num==0) c="\033[90m"
                else if(q_num==1) c="\033[97m"
                else if(q_num==2) c="\033[32m"
                else if(q_num==3) c="\033[36m"
                else if(q_num==4) c="\033[35m"
                else if(q_num==5) c="\033[33m"
                else if(q_num==6) c="\033[38;5;214m"
                db_colors[p[1]] = c
            }
        }
        close(db)
    }
    {
        sub(/\r$/, "")
        if ($1 != "HISTORY") {
            if ($0 != "") print $0
            next
        }

        if ($NF ~ /^[0-9]+$/) {
            scans = $NF + 0
            src = $(NF-1)
        } else {
            scans = 1
            src = $NF
        }
        if (src ~ /^(Unknown|\[Unknown\])$/ || src == "") src = "TTC"

        kiosk = $11
        if (index(kiosk, "|") > 0) {
            split(kiosk, kp, "|")
            kiosk = kp[1]
        }

        uid = $6"|"$3"|"$4"|"$5"|"src
        ts = $2 + 0
        buyer = $8; seller = $9; guild = $10

        color = db_colors[$6]
        if (color == "") {
            color = $12
            if (color !~ /^\033\[/) color = "\033[0m"
        }

        if (!(uid in seen)) {
            seen[uid] = 1
            uids[++uid_count] = uid
            db_ts[uid] = ts
            db_name[uid] = $7
            db_buyer[uid] = buyer
            db_seller[uid] = seller
            db_guild[uid] = guild
            db_kiosk[uid] = kiosk
            db_color[uid] = color
            db_scans[uid] = scans
        } else {
            if (ts > db_ts[uid]) db_ts[uid] = ts

            if (buyer != "" && index(db_buyer[uid], buyer) == 0) {
                db_buyer[uid] = (db_buyer[uid]=="") ? buyer : db_buyer[uid]", "buyer
            }
            if (seller != "" && index(db_seller[uid], seller) == 0) {
                db_seller[uid] = (db_seller[uid]=="") ? seller : db_seller[uid]", "seller
            }
            if (guild != "" && index(db_guild[uid], guild) == 0) {
                db_guild[uid] = (db_guild[uid]=="") ? guild : db_guild[uid]", "guild
            }
            if (kiosk != "" && index(db_kiosk[uid], kiosk) == 0) {
                db_kiosk[uid] = (db_kiosk[uid]=="") ? kiosk : db_kiosk[uid]", "kiosk
            }
            if (scan_mode == "max") { if (scans > db_scans[uid]) db_scans[uid] = scans }
            else db_scans[uid] += scans
        }
    }
    END {
        for (i = 1; i <= uid_count; i++) {
            u = uids[i]
            split(u, p, "|")
            print "HISTORY", db_ts[u], p[2], p[3], p[4], p[1], db_name[u], \
                  db_buyer[u], db_seller[u], db_guild[u], db_kiosk[u], \
                  db_color[u], p[5], db_scans[u]
        }
    }
    ' "$1" <(printf '%s\n' "$2")
}

template_history_apply() {
    local hist="$1" tpl="$2" ver="$3" tmp="$1.template.tmp"
    [ -f "$hist" ] || : > "$hist"
    {
        echo "#HISTORY VERSION: $ver"
        history_merge <(grep -v '^#HISTORY VERSION:' "$hist" | tr -d '\r') "$(grep '^HISTORY|' "$tpl" | tr -d '\r')" max
    } > "$tmp" && mv -f "$tmp" "$hist"
}
