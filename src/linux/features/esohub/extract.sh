esohub_extract() {
    awk -v last_time="$2" -v now_time="$3" -v db_file="$DB_FILE" '
    '"$master_color_logic"'
    BEGIN {
        max_time = last_time
        count = 0
        scrape_count = 0
        stop_scraping = 0

        while ((getline line < db_file) > 0) {
            split(line, p, "|")
            if (p[1] == "GUILD") {
                db_guild_id[p[2]] = p[3]
                db_guild_name[p[3]] = p[2]
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
    /\["traderData"\]/ { in_trader_data = 1; in_guild_data = 0 }
    /\["guildData"\]/ { in_guild_data = 1; in_trader_data = 0 }

    in_trader_data && /^[ \t]*\["([^"]+)"\][ \t]*=[ \t]*$/ {
        match($0, /\["([^"]+)"\]/)
        val = substr($0, RSTART+2, RLENGTH-4)
        if (val != "NA Megaserver" && val != "EU Megaserver" && val != "PTS" && val != "guildHistory") {
            current_trader = val
        }
    }

    in_trader_data && /\["mapId"\][ \t]*=[ \t]*[0-9]+/ {
        match($0, /[0-9]+/)
        if (current_trader != "") {
            trader_maps[current_trader] = substr($0, RSTART, RLENGTH)
        }
    }

    in_trader_data && /^[ \t]*\[[0-9]+\][ \t]*=[ \t]*[0-9]+,?/ {
        match($0, /=[ \t]*[0-9]+/)
        if (RLENGTH > 0) {
            gid = substr($0, RSTART, RLENGTH)
            sub(/=[ \t]*/, "", gid)
            if (current_trader != "") {
                guild_kiosks[gid] = current_trader
                if (trader_maps[current_trader] != "") {
                    guild_maps[gid] = trader_maps[current_trader]
                }
            }
        }
    }

    in_guild_data && /^[ \t]*\[[0-9]+\][ \t]*=[ \t]*$/ {
        match($0, /[0-9]+/)
        current_guild_id = substr($0, RSTART, RLENGTH)
        buffered_gname = ""
        scan_type = ""
    }

    in_guild_data && /\["guildId"\][ \t]*=[ \t]*[0-9]+/ {
        match($0, /[0-9]+/)
        current_guild_id = substr($0, RSTART, RLENGTH)
        if (buffered_gname != "") {
            guild_names[current_guild_id] = buffered_gname
            db_guild_updated[buffered_gname] = current_guild_id
            buffered_gname = ""
        }
    }

    in_guild_data && /\["(traderGuildName|guildName)"\][ \t]*=[ \t]*"/ {
        match($0, /\["(traderGuildName|guildName)"\][ \t]*=[ \t]*"([^"]+)"/)
        if (RLENGTH > 0) {
            val = substr($0, RSTART, RLENGTH)
            sub(/.*\["(traderGuildName|guildName)"\][ \t]*=[ \t]*"/, "", val)
            sub(/".*$/, "", val)
            if (current_guild_id != "") {
                guild_names[current_guild_id] = val
                db_guild_updated[val] = current_guild_id
            } else {
                buffered_gname = val
            }
        }
    }

    /\["(scannedSales|scannedItems|cancelledItems|purchasedItems|traderHistory)"\]/ {
        match($0, /"(scannedSales|scannedItems|cancelledItems|purchasedItems|traderHistory)"/)
        stype = substr($0, RSTART+1, RLENGTH-2)
        if (stype == "scannedSales") scan_type = "Sold"
        else if (stype == "scannedItems") scan_type = "Listed"
        else if (stype == "cancelledItems") scan_type = "Cancelled"
        else if (stype == "purchasedItems") scan_type = "Purchased"
        else if (stype == "traderHistory") scan_type = "History"
    }

    index($0, ":item:") > 0 {
        if (scan_type == "") next
        s_idx = index($0, "\"|H")

        if (s_idx > 0) {
            t_str = substr($0, s_idx + 1)
            e_idx = index(t_str, "\",")
            if (e_idx == 0) e_idx = index(t_str, "\"")

            if (e_idx > 0) {
                full_val = substr(t_str, 1, e_idx - 1)
                split_idx = index(full_val, "|h|h,")
                offset = 5
                if (split_idx == 0) {
                    split_idx = index(full_val, "|h,")
                    offset = 3
                }

                if (split_idx > 0) {
                    item_link = substr(full_val, 1, split_idx + 1)
                    data_csv = substr(full_val, split_idx + offset)

                    split(item_link, lp, ":")
                    itemid = lp[3]
                    subtype = lp[4]
                    internal_level = lp[5]
                    s = subtype + 0
                    v = internal_level + 0

                    split(data_csv, arr, ",")
                    price = arr[1]
                    qty = arr[2]
                    buyer = ""
                    seller = ""
                    stime = 0

                    if (qty == "") qty = "1"

                    len = 0
                    for (i in arr) len++
                    if (len >= 5) {
                        buyer = arr[3]
                        seller = arr[4]
                        stime = arr[5] + 0
                    } else {
                        buyer = ""
                        seller = arr[3]
                        stime = arr[4] + 0
                    }

                    if (!(stime > 1400000000)) {
                        stime = 0
                        for (idx = length(arr); idx >= 3; idx--) {
                            if (arr[idx] ~ /^[0-9]+$/ && arr[idx] + 0 > 1400000000) {
                                stime = arr[idx] + 0
                                break
                            }
                        }
                    }

                    if (buyer != "" && buyer !~ /^@/) buyer = "@" buyer
                    if (seller != "" && seller !~ /^@/) seller = "@" seller

                    if (itemid in db_name && db_name[itemid] !~ /^Unknown Item/) {
                        real_name = db_name[itemid]
                    } else {
                        real_name = "Unknown Item (" itemid ")"
                    }

                    if (itemid in db_qual) {
                        real_qual = db_qual[itemid] + 0
                    } else {
                        real_qual = calc_quality(itemid, real_name, s, v)
                    }

                    needs_update = 0
                    if (index(real_name, "Unknown Item (") == 0) {
                        if (db_name[itemid] != real_name || db_qual[itemid] != real_qual) {
                            needs_update = 1
                        }
                        if (db_cols[itemid] < 7) needs_update = 1
                    }

                    if (needs_update) {
                        hq = get_hq(real_qual)
                        cat = get_cat(real_name, itemid, s, v)
                        update_str = itemid "|" real_qual "|" s "|" v "|" hq "|" real_name "|" cat
                        db_updated[itemid] = update_str
                        db_name[itemid] = real_name
                        db_qual[itemid] = real_qual
                        db_cols[itemid] = 7
                    }

                    if (real_name != "" && price != "") {
                        if (stime > max_time) max_time = stime
                        if (stime > last_time || stime == 0 || scan_type == "Listed") {
                            q_num = real_qual + 0
                            c = "\033[0m"
                            if(q_num==0) c="\033[90m"
                            else if(q_num==1) c="\033[97m"
                            else if(q_num==2) c="\033[32m"
                            else if(q_num==3) c="\033[36m"
                            else if(q_num==4) c="\033[35m"
                            else if(q_num==5) c="\033[33m"
                            else if(q_num==6) c="\033[38;5;214m"

                            link_start = "\033]8;;https://eso-hub.com/en/trading/" itemid "\033\\"
                            link_end = "\033]8;;\033\\"
                            item_display = link_start c real_name "\033[0m" link_end

                            trade_str = ""
                            if (seller != "" && buyer != "") {
                                trade_str = " by \033[36m" seller "\033[0m to \033[36m" buyer "\033[0m"
                            } else if (seller != "") {
                                trade_str = " by \033[36m" seller "\033[0m"
                            } else if (buyer != "") {
                                trade_str = " to \033[36m" buyer "\033[0m"
                            }

                            age = now_time - stime
                            status_tag = ""

                            if (scan_type == "Sold") {
                                status_tag = " \033[38;5;214m[SOLD]\033[0m"
                            } else if (scan_type == "Purchased") {
                                status_tag = " \033[92m[PURCHASED]\033[0m"
                            } else if (scan_type == "Cancelled") {
                                status_tag = " \033[31m[CANCELLED]\033[0m"
                            } else if (scan_type == "Listed") {
                                if (stime > 0 && age > 2592000) {
                                    status_tag = " \033[90m[EXPIRED]\033[0m"
                                } else {
                                    status_tag = " \033[34m[AVAILABLE]\033[0m"
                                }
                            }

                            lines[count] = stime "|" " \033[36m" scan_type "\033[0m for \033[32m" price \
                                           "\033[33mgold\033[0m - \033[32m" qty "x\033[0m " item_display \
                                           trade_str " in GUILD_PLACEHOLDER_" current_guild_id status_tag

                            if (current_guild_id != "") {
                                hist_lines[count] = "HISTORY|" stime "|" scan_type "|" price "|" qty "|" \
                                                    itemid "|" real_name "|" buyer "|" seller "|" \
                                                    current_guild_id "||" c "|ESO-Hub"
                            } else {
                                hist_lines[count] = ""
                            }

                            line_gid[count] = current_guild_id
                            count++
                        }
                    }
                }
            }
        }
    }
    END {
        for (gid in db_guild_name) {
            if (!(gid in guild_names)) {
                guild_names[gid] = db_guild_name[gid]
            }
        }

        for (i = 0; i < count; i++) {
            gid = line_gid[i]
            gname = guild_names[gid]
            if (gname == "") gname = db_guild_name[gid]

            l = lines[i]
            h = hist_lines[i]

            if (gname != "" && gname != "Unknown Guild") {
                g_link = "\033[35m\033]8;;|H1:guild:" gid "|h" gname "|h\033\\" gname "\033]8;;\033\\\033[0m"
            } else {
                g_link = "\033[35mUnknown Guild\033[0m"
                gname = "Unknown Guild"
            }

            kiosk = guild_kiosks[gid]
            k_str = ""
            if (kiosk != "") {
                map_id = guild_maps[gid]
                if (kiosk in k_dict) {
                    split(k_dict[kiosk], kp, "|")
                    k_loc = kp[1]
                    k_map = kp[2]
                    k_coords = kp[3]

                    if (k_map != "" && k_coords != "") {
                        k_str = " \033[90m(\033]8;;https://eso-hub.com/en/interactive-map" \
                                "?map=" k_map "&ping=" k_coords "\033\\" k_loc \
                                "\033]8;;\033\\)\033[0m"
                    } else if (k_map != "") {
                        k_str = " \033[90m(\033]8;;https://eso-hub.com/en/interactive-map" \
                                "?map=" k_map "\033\\" k_loc "\033]8;;\033\\)\033[0m"
                    } else {
                        k_str = " \033[90m(" k_loc ")\033[0m"
                    }
                } else if (map_id != "") {
                    k_str = " \033[90m(\033]8;;https://eso-hub.com/en/interactive-map" \
                            "?map=" map_id "\033\\" kiosk "\033]8;;\033\\)\033[0m"
                } else {
                    k_str = " \033[90m(" kiosk ")\033[0m"
                }
            }

            target_l = "GUILD_PLACEHOLDER_" gid
            idx_l = index(l, target_l)
            if (idx_l > 0) {
                l = substr(l, 1, idx_l - 1) g_link k_str substr(l, idx_l + length(target_l))
            }
            print l

            if (h != "") {
                target_h = gid "||"
                idx_h = index(h, target_h)
                if (idx_h > 0) {
                    h = substr(h, 1, idx_h - 1) gname "|" kiosk "|" substr(h, idx_h + length(target_h))
                }
                print h
            }
        }

        print "MAX_TIME:" max_time
        for (i in db_updated) {
            print "DB_UPDATE|" db_updated[i]
        }
        for (g in db_guild_updated) {
            print "DB_GUILD|" g "|" db_guild_updated[g]
        }
    }
    ' "$1"
}
