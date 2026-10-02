ttc_extract() {
    awk -v last_time="$2" -v now_time="$3" -v db_file="$DB_FILE" '
    '"$master_color_logic"'
    BEGIN {
        max_time = last_time
        count = 0
        while ((getline line < db_file) > 0) {
            split(line, p, "|")
            if (p[1] == "GUILD") {
                db_guild_id[p[2]] = p[3]
            } else if (p[1] ~ /^[0-9]+$/) {
                db_cols[p[1]] = length(p)
                db_qual[p[1]] = p[2]
                db_name[p[1]] = (length(p) >= 6) ? p[6] : p[3]
            }
        }
        close(db_file)
        '"$master_kiosk_logic"'
    }
    { sub(/\r$/, "") }
    /^[ \t]*\["?([^"]+)"?\][ \t]*=/ {
        match($0, /^[ \t]*/)
        lvl = RLENGTH + 0
        match($0, /^[ \t]*\["?([^"]+)"?\]/)
        key = substr($0, RSTART, RLENGTH)
        sub(/^[ \t]*\["?/, "", key)
        sub(/"?\]$/, "", key)

        for (i in path) {
            if ((i + 0) >= lvl) {
                delete path[i]
            }
        }
        path[lvl] = key

        if (key == "KioskLocationID") {
            n = 0
            for (i in path) { keys[n++] = i + 0 }
            for (i = 0; i < n; i++) {
                for (j = i + 1; j < n; j++) {
                    if (keys[i] > keys[j]) {
                        temp = keys[i]
                        keys[i] = keys[j]
                        keys[j] = temp
                    }
                }
            }
            gname = ""
            for (i = 0; i < n; i++) {
                if (path[keys[i]] == "Guilds" && i + 1 < n) {
                    gname = path[keys[i+1]]
                }
            }
            if (gname != "") {
                match($0, /[0-9]+/)
                guild_kiosks[gname] = substr($0, RSTART, RLENGTH)
            }
        }

        if (key ~ /^[0-9]+$/ && !in_item) {
            in_item = 1
            item_lvl = lvl
            n = 0
            for (i in path) { keys[n++] = i + 0 }
            for (i = 0; i < n; i++) {
                for (j = i + 1; j < n; j++) {
                    if (keys[i] > keys[j]) {
                        temp = keys[i]
                        keys[i] = keys[j]
                        keys[j] = temp
                    }
                }
            }

            action = "Listed"
            guild = ""
            player = ""
            seller = ""
            buyer = ""
            ttc_id = ""
            amt = ""; stime = ""; price = ""; itemid = ""
            subtype = ""; internal_level = ""; real_name = ""; game_qual = ""

            for (i = 0; i < n; i++) {
                k = path[keys[i]]
                if (k == "SaleHistoryEntries") action = "Sold"
                if (k == "AutoRecordEntries" || k == "Entries") action = "Listed"
                if (k == "Guilds" && i + 1 < n) guild = path[keys[i+1]]
                if (k == "PlayerListings" && i + 1 < n) player = path[keys[i+1]]
            }
        }
    }
    in_item && /\["Amount"\][ \t]*=/ {
        match($0, /[0-9]+/)
        amt=substr($0, RSTART, RLENGTH)
    }
    in_item && /\["SaleTime"\][ \t]*=/ {
        match($0, /[0-9]+/)
        stime=substr($0, RSTART, RLENGTH)
    }
    in_item && /\["Timestamp"\][ \t]*=/ {
        match($0, /[0-9]+/)
        if(stime=="") stime=substr($0, RSTART, RLENGTH)
    }
    in_item && /\["TimeStamp"\][ \t]*=/ {
        match($0, /[0-9]+/)
        if(stime=="") stime=substr($0, RSTART, RLENGTH)
    }
    in_item && /\["QualityID"\][ \t]*=/ {
        match($0, /[0-9]+/)
        game_qual = substr($0, RSTART, RLENGTH)
    }
    in_item && /\["TotalPrice"\][ \t]*=/ {
        match($0, /[0-9]+/)
        price=substr($0, RSTART, RLENGTH)
    }
    in_item && /\["Price"\][ \t]*=/ {
        if ($0 !~ /TotalPrice/) {
            match($0, /[0-9]+/)
            if(price=="") price=substr($0, RSTART, RLENGTH)
        }
    }
    in_item && /\["Buyer"\][ \t]*=/ {
        match($0, /\["Buyer"\][ \t]*=[ \t]*"([^"]+)"/)
        if(RLENGTH>0) {
            buyer=substr($0,RSTART,RLENGTH)
            sub(/.*\["Buyer"\][ \t]*=[ \t]*"/,"",buyer)
            sub(/"$/,"",buyer)
        }
    }
    in_item && /\["Seller"\][ \t]*=/ {
        match($0, /\["Seller"\][ \t]*=[ \t]*"([^"]+)"/)
        if(RLENGTH>0) {
            seller=substr($0,RSTART,RLENGTH)
            sub(/.*\["Seller"\][ \t]*=[ \t]*"/,"",seller)
            sub(/"$/,"",seller)
        }
    }
    in_item && /\["ItemLink"\][ \t]*=/ {
        if (match($0, /\|H[0-9a-fA-F]*:item:[0-9]+/)) {
            split(substr($0, RSTART, RLENGTH), ip, ":")
            itemid = ip[3]
        }
        if (match($0, /"(\|H[^"]+)"/)) {
            split(substr($0, RSTART+1, RLENGTH-2), lp, ":")
            subtype = lp[4]
            internal_level = lp[5]
        }
    }
    in_item && /\["Name"\][ \t]*=/ {
        val = $0
        sub(/.*Name"\][ \t]*=[ \t]*"/, "", val)
        sub(/",[ \t]*$/, "", val)
        gsub(/\\"/, "\"", val)
        real_name = val
    }
    in_item && /^[ \t]*\},?[ \t]*$/ {
        match($0, /^[ \t]*/)
        if (RLENGTH <= item_lvl) {
            in_item = 0
            stime_num = (stime == "") ? 0 : stime + 0
            if (stime_num > max_time) max_time = stime_num

            if (stime_num > last_time || last_time == 0 || action == "Listed") {
                if (amt == "") amt = "1"
                if (real_name == "" || real_name ~ /^\|[0-9]+\|$/) {
                    if (itemid in db_name && db_name[itemid] !~ /^Unknown Item/) {
                        real_name = db_name[itemid]
                    } else {
                        real_name = "Unknown Item (" itemid ")"
                    }
                }

                if (price != "") {
                    s = subtype + 0
                    v = internal_level + 0
                    needs_update = 0

                    if (itemid in db_name) {
                        if (real_name != db_name[itemid] && real_name !~ /^Unknown Item/) {
                            needs_update = 1
                        }
                        if (db_cols[itemid] < 7) needs_update = 1
                    } else {
                        needs_update = 1
                    }

                    if (game_qual != "") {
                        real_qual = game_qual + 1
                        if (!(itemid in db_qual) || db_qual[itemid] + 0 != real_qual) needs_update = 1
                    } else if (itemid in db_qual) {
                        real_qual = db_qual[itemid] + 0
                    } else {
                        real_qual = calc_quality(itemid, real_name, s, v)
                    }

                    if (index(real_name, "Unknown Item (") == 1) needs_update = 0

                    if (needs_update) {
                        hq = get_hq(real_qual)
                        cat = get_cat(real_name, itemid, s, v)

                        update_str = itemid "|" real_qual "|" s "|" v "|" hq "|" real_name "|" cat
                        db_updated[itemid] = update_str
                        db_name[itemid] = real_name
                        db_qual[itemid] = real_qual
                        db_cols[itemid] = 7
                    }

                    q_num = real_qual + 0
                    c = "\033[0m"
                    if(q_num==0) c="\033[90m"
                    else if(q_num==1) c="\033[97m"
                    else if(q_num==2) c="\033[32m"
                    else if(q_num==3) c="\033[36m"
                    else if(q_num==4) c="\033[35m"
                    else if(q_num==5) c="\033[33m"
                    else if(q_num==6) c="\033[38;5;214m"

                    guild_str = ""
                    kiosk = ""
                    if (guild != "" && guild != "Unknown Guild" && guild != "Guilds") {
                        if (guild in db_guild_id) {
                            gid = db_guild_id[guild]
                            g_display = "\033[35m\033]8;;|H1:guild:" gid "|h" guild \
                                        "|h\033\\" guild "\033]8;;\033\\\033[0m"
                        } else {
                            g_display = "\033[35m" guild "\033[0m"
                        }

                        kiosk = guild_kiosks[guild]
                        if (kiosk != "" && kiosk != "0") {
                            if (kiosk in k_dict) {
                                split(k_dict[kiosk], kp, "|")
                                k_loc = kp[1]
                                k_map = kp[2]
                                k_coords = kp[3]

                                if (k_map != "" && k_coords != "") {
                                    k_str = " \033[90m(\033]8;;https://eso-hub.com/en/" \
                                            "interactive-map?map=" k_map "&ping=" k_coords \
                                            "\033\\" k_loc "\033]8;;\033\\)\033[0m"
                                } else if (k_map != "") {
                                    k_str = " \033[90m(\033]8;;https://eso-hub.com/en/" \
                                            "interactive-map?map=" k_map "\033\\" k_loc \
                                            "\033]8;;\033\\)\033[0m"
                                } else {
                                    k_str = " \033[90m(" k_loc ")\033[0m"
                                }
                            } else {
                                k_str = " \033[90m(Kiosk ID: " kiosk ")\033[0m"
                            }
                        } else {
                            k_str = " \033[90m(Local Trader)\033[0m"
                        }
                        guild_str = " in " g_display k_str
                    }

                    player_str_clean = player
                    if (player_str_clean != "" && player_str_clean !~ /^@/) {
                        player_str_clean = "@" player_str_clean
                    }

                    if (buyer != "" && buyer !~ /^@/) buyer = "@" buyer
                    if (seller != "" && seller !~ /^@/) seller = "@" seller

                    if (seller == "" && player_str_clean != "") seller = player_str_clean

                    trade_str = ""
                    if (seller != "" && buyer != "") {
                        trade_str = " by \033[36m" seller "\033[0m to \033[36m" buyer "\033[0m"
                    } else if (seller != "") {
                        trade_str = " by \033[36m" seller "\033[0m"
                    } else if (buyer != "") {
                        trade_str = " to \033[36m" buyer "\033[0m"
                    } else if (player_str_clean != "" && player_str_clean != guild) {
                        trade_str = " by \033[36m" player_str_clean "\033[0m"
                    }

                    name_enc = real_name
                    gsub(/ /, "+", name_enc)
                    gsub(/'\''/, "%27", name_enc)

                    link_start = "\033]8;;https://us.tamrieltradecentre.com/pc/Trade/" \
                                 "SearchResult?SearchType=Sell&ItemNamePattern=" name_enc "\033\\"

                    age = now_time - stime_num
                    status_tag = ""

                    if (action == "Sold") {
                        status_tag = " \033[38;5;214m[SOLD]\033[0m"
                    } else if (action == "Listed") {
                        if (stime_num > 0 && age > 2592000) {
                            status_tag = " \033[90m[EXPIRED]\033[0m"
                        } else {
                            status_tag = " \033[34m[AVAILABLE]\033[0m"
                        }
                    }

                    ts_str = (stime_num > 0) ? stime_num "|" : "0|"

                    lines[count] = ts_str " \033[36m" action "\033[0m for \033[32m" price \
                                   "\033[33mgold\033[0m - \033[32m" amt "x\033[0m " link_start \
                                   c real_name "\033[0m\033]8;;\033\\" trade_str \
                                   guild_str status_tag

                    if (guild != "Guilds" && guild != "Unknown Guild" && guild != "") {
                        hist_lines[count] = "HISTORY|" ts_str action "|" price "|" amt "|" \
                                            itemid "|" real_name "|" buyer "|" seller "|" \
                                            guild "|" kiosk "|" c "|TTC"
                    } else if (action == "Listed" && seller != "") {
                        hist_lines[count] = "HISTORY|" ts_str action "|" price "|" amt "|" \
                                            itemid "|" real_name "|" buyer "|" seller "||" \
                                            kiosk "|" c "|TTC"
                    } else {
                        hist_lines[count] = ""
                    }
                    count++
                }
            }
        }
    }
    END {
        for (i = 0; i < count; i++) {
            print lines[i]
            if (hist_lines[i] != "") print hist_lines[i]
        }
        print "MAX_TIME:" max_time
        for (i in db_updated) {
            print "DB_UPDATE|" db_updated[i]
        }
        for (k in k_dict) {
            print "DB_KIOSK|" k "|" k_dict[k]
        }
    }
    ' "$1"
}
