_d() {
    local h="$1" s="$2" o="" i b
    for (( i = 0; i < ${#h}; i += 2 )); do
        s=$(( (s * 73 + 41) % 256 ))
        b=$(( 16#${h:i:2} ^ s ))
        o="${o}$(printf "\\$(printf '%03o' "$b")")"
    done
    printf '%s' "$o"
}

push_sys_notif() {
    local msg="$1" body
    if [ "$ENABLE_NOTIFS" = "false" ]; then return; fi
    body="$(printf '%b' "$msg")"
    if command -v notify-send > /dev/null && notify-send -i "dialog-information" -t 5000 \
            --hint=string:category:system "$APP_TITLE" "$body" 2>/dev/null; then
        return 0
    fi
    if command -v kdialog > /dev/null && kdialog --title "$APP_TITLE" --passivepopup "$body" 8 2>/dev/null; then
        return 0
    fi
    if command -v gdbus > /dev/null && gdbus call --session --dest org.freedesktop.Notifications \
            --object-path /org/freedesktop/Notifications --method org.freedesktop.Notifications.Notify \
            "$APP_TITLE" 0 "dialog-information" "$APP_TITLE" "$body" "[]" "{}" 5000 > /dev/null 2>&1; then
        return 0
    fi
    write_ttc_log "WARN" "No desktop notification service answered (notify-send, kdialog, gdbus); Steam Deck Gaming Mode has none"
    return 1
}

get_active_terminal() {
    local term
    if command -v alacritty &> /dev/null; then term="alacritty -e"
    elif command -v konsole &> /dev/null; then term="konsole -e"
    elif command -v gnome-terminal &> /dev/null; then term="gnome-terminal --"
    elif command -v xfce4-terminal &> /dev/null; then term="xfce4-terminal -e"
    elif command -v kitty &> /dev/null; then term="kitty --"
    else term="xterm -e"; fi
    echo "$term"
}

find_addon_folder() {
    declare -a addon_paths=()
    addon_paths=(
            "$HOME/.local/share/Steam/steamapps/compatdata/306130/pfx/drive_c/users/steamuser/Documents/Elder Scrolls Online/live/AddOns"
            "$HOME/.steam/steam/steamapps/compatdata/306130/pfx/drive_c/users/steamuser/Documents/Elder Scrolls Online/live/AddOns"
            "$HOME/.var/app/com.valvesoftware.Steam/.steam/root/steamapps/compatdata/306130/pfx/drive_c/users/steamuser/Documents/Elder Scrolls Online/live/AddOns"
            "/var/lib/flatpak/app/com.valvesoftware.Steam/.steam/root/steamapps/compatdata/306130/pfx/drive_c/users/steamuser/Documents/Elder Scrolls Online/live/AddOns"
            "$HOME/Games/elder-scrolls-online/drive_c/users/$USER/Documents/Elder Scrolls Online/live/AddOns"
            "$HOME/Games/elder-scrolls-online/drive_c/users/steamuser/Documents/Elder Scrolls Online/live/AddOns"
            "$HOME/Documents/Elder Scrolls Online/live/AddOns"
            "$HOME/.wine/drive_c/users/$USER/Documents/Elder Scrolls Online/live/AddOns"
            "$HOME/.wine/drive_c/users/steamuser/Documents/Elder Scrolls Online/live/AddOns"
            "$HOME/.var/app/com.usebottles.bottles/data/bottles/bottles/Elder-Scrolls-Online/drive_c/users/$USER/Documents/Elder Scrolls Online/live/AddOns"
            "$HOME/PortWINE/PortProton/drive_c/users/steamuser/Documents/Elder Scrolls Online/live/AddOns"
            "$HOME/PortProton/prefixes/DEFAULT/drive_c/users/steamuser/Documents/Elder Scrolls Online/live/AddOns/"
    )

    for p in "${addon_paths[@]}"; do
        if [ -d "$p" ]; then echo "$p"; return 0; fi
    done

    while IFS= read -r base_dir; do
        [ -z "$base_dir" ] && continue
        for suffix in "/pfx/drive_c/users/steamuser/Documents/Elder Scrolls Online/live/AddOns" \
                      "/drive_c/users/$USER/Documents/Elder Scrolls Online/live/AddOns" \
                      "/live/AddOns"; do
            if [ -d "$base_dir$suffix" ]; then echo "$base_dir$suffix"; return 0; fi
        done
    done <<< "$(find "$HOME" /run/media /mnt /media -maxdepth 6 \
        \( -type d -name "306130" -o -type d -name "Elder Scrolls Online" \
        -o -type d -name "bottles" -o -type d -name "lutris" \) 2>/dev/null)"
    echo ""
}

