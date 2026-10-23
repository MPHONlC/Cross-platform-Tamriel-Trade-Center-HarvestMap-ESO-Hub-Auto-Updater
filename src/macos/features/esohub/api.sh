ESOHUB_API="${LTTC_ESOHUB_API:-https://data.eso-hub.com}"
ESOHUB_V2_UA="ESO-Hub Client v2"
ESOHUB_V2_VERSION="0.2.23"
ESOHUB_V1_UA="ESOHubClient/1.0.9"
ESOHUB_LANGS="en"
esohub_lang() {
    local l="${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}"
    l=$(printf '%s' "$l" | cut -c1-2 | tr 'A-Z' 'a-z')
    case " $ESOHUB_LANGS " in *" $l "*) printf '%s' "$l" ;; *) printf 'en' ;; esac
}
ESOHUB_LANG="$(esohub_lang)"
ESOHUB_CF_PAGE="https://eso-hub.com/$ESOHUB_LANG/user/profile"
ESOHUB_LOGIN_PAGE="https://eso-hub.com/$ESOHUB_LANG/client-token-login?code="
ESOHUB_CF_ASK_SECONDS=300
ESOHUB_CODE_SECONDS=300
ESOHUB_CODE_POLL=2
ESOHUB_UA_WAIT=30
ESOHUB_LISTEN_TOOLS="python3 perl nc"
ESOHUB_CF_ASKED=false
ESOHUB_CF_HINT=""
ESOHUB_UA_SEEN=""
ESOHUB_UA_URL=""
ESOHUB_UA_DIR=""
ESOHUB_UA_PIDS=""
ESOHUB_UA_MISSING=""

ESOHUB_UA_PY='import os, socket, sys, time
target, path, out, limit = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(("127.0.0.1", 0))
s.listen(8)
with open(out + ".port.tmp", "w") as f:
    f.write(str(s.getsockname()[1]))
os.replace(out + ".port.tmp", out + ".port")
end = time.time() + limit
while time.time() < end:
    s.settimeout(max(0.2, end - time.time()))
    try:
        c, _ = s.accept()
    except OSError:
        break
    c.settimeout(5)
    data = b""
    try:
        while b"\r\n\r\n" not in data and len(data) < 32768:
            part = c.recv(4096)
            if not part:
                break
            data += part
    except OSError:
        pass
    lines = data.split(b"\r\n\r\n")[0].decode("latin-1").split("\r\n")
    hit = lines[0].startswith("GET " + path + " ")
    ua = ""
    for line in lines[1:]:
        key, _, value = line.partition(":")
        if key.strip().lower() == "user-agent":
            ua = value.strip()
    if hit:
        reply = "HTTP/1.1 302 Found\r\nLocation: " + target + "\r\nCache-Control: no-store\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    else:
        reply = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    try:
        c.sendall(reply.encode("latin-1"))
    except OSError:
        pass
    c.close()
    if hit:
        with open(out + ".tmp", "w", encoding="latin-1") as f:
            f.write(ua)
        os.replace(out + ".tmp", out)
        break
s.close()'

ESOHUB_UA_PL='use strict; use IO::Socket::INET;
my ($target, $path, $out, $limit) = @ARGV;
my $s = IO::Socket::INET->new(LocalAddr => "127.0.0.1", LocalPort => 0, Listen => 8, Proto => "tcp") or exit 1;
open(my $pf, ">", "$out.port.tmp") or exit 1;
print $pf $s->sockport;
close($pf);
rename("$out.port.tmp", "$out.port") or exit 1;
my $end = time + $limit;
while (time < $end) {
    my $rin = "";
    vec($rin, fileno($s), 1) = 1;
    next unless select(my $rout = $rin, undef, undef, 0.5);
    my $c = $s->accept or next;
    my ($data, $stop) = ("", time + 5);
    while (index($data, "\r\n\r\n") < 0 && length($data) < 32768 && time < $stop) {
        my $cin = "";
        vec($cin, fileno($c), 1) = 1;
        last unless select(my $cout = $cin, undef, undef, 1);
        my $n = sysread($c, my $buf, 4096);
        last unless $n;
        $data .= $buf;
    }
    my @lines = split(/\r\n/, (split(/\r\n\r\n/, $data))[0] // "");
    my $hit = @lines && index($lines[0], "GET $path ") == 0;
    my $ua = "";
    for my $line (@lines[1 .. $#lines]) { $ua = $1 if $line =~ /^user-agent:\s*(.*?)\s*$/i; }
    print $c ($hit ? "HTTP/1.1 302 Found\r\nLocation: $target\r\nCache-Control: no-store\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        : "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
    close($c);
    if ($hit) {
        open(my $f, ">", "$out.tmp") or exit 1;
        print $f $ua;
        close($f);
        rename("$out.tmp", $out);
        last;
    }
}'

esohub_cf_ready() {
    [ -n "${ESOHUB_CF_CLEARANCE:-}" ] && [ -n "${ESOHUB_CF_UA:-}" ]
}

esohub_reload_cf() {
    [ -n "${CONFIG_FILE:-}" ] && [ -f "$CONFIG_FILE" ] || return 0
    local line val
    line=$(grep -m1 '^ESOHUB_CF_CLEARANCE=' "$CONFIG_FILE" 2>/dev/null); val="${line#ESOHUB_CF_CLEARANCE=}"; val="${val%\"}"; val="${val#\"}"; val=$(secret_decrypt "$val")
    [ -n "$val" ] && ESOHUB_CF_CLEARANCE="$val"
    line=$(grep -m1 '^ESOHUB_CF_UA=' "$CONFIG_FILE" 2>/dev/null); val="${line#ESOHUB_CF_UA=}"; val="${val%\"}"; val="${val#\"}"; val=$(secret_decrypt "$val")
    [ -n "$val" ] && ESOHUB_CF_UA="$val"
}

esohub_ua() {
    if esohub_cf_ready; then printf '%s' "$ESOHUB_CF_UA"; else printf '%s' "$1"; fi
}

esohub_cf_host_ok() {
    local host
    case "$1" in "$ESOHUB_API"/*) return 0 ;; https://*) ;; *) return 1 ;; esac
    host="${1#https://}"; host="${host%%[/?#]*}"
    case "$host" in *@*|*:*) return 1 ;; eso-hub.com|*.eso-hub.com) return 0 ;; esac
    return 1
}

esohub_cf_config() {
    if esohub_cf_ready && esohub_cf_host_ok "$1"; then
        printf 'header = "Cookie: cf_clearance=%s"\n' "$ESOHUB_CF_CLEARANCE"
    fi
    return 0
}

esohub_cf_clean_cookie() {
    local v
    v=$(printf '%s' "$1" | tr -d ' \t\r\n')
    v="${v#Cookie:}"; v="${v#cf_clearance=}"; v="${v%%;*}"
    case "$v" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac
    [ "${#v}" -ge 20 ] || return 1
    printf '%s' "$v"
}

esohub_cf_clean_ua() {
    local v
    v=$(printf '%s' "$1" | tr -d '\r\n' | sed "s/^[[:space:]]*//; s/[[:space:]]*\$//; s/^['\"]//; s/['\"]\$//")
    case "$v" in Mozilla/*) ;; *) return 1 ;; esac
    case "$v" in *[\"\$\`\\]*) return 1 ;; esac
    printf '%s' "$v"
}

esohub_cf_can_ask() {
    [ "$SILENT" != true ] && { : < /dev/tty; } 2>/dev/null
}

esohub_cf_read() {
    local ans=""
    if [ "${1:-}" = secret ]; then
        read -r -s -t "$ESOHUB_CF_ASK_SECONDS" ans < /dev/tty 2>/dev/null || return 1
    else
        read -r -t "$ESOHUB_CF_ASK_SECONDS" ans < /dev/tty 2>/dev/null || return 1
    fi
    printf '%s' "$ans"
}

esohub_open() {
    open_url "$1"
}

esohub_have() {
    command -v "$1" > /dev/null 2>&1 || return 1
    if [ "$1" = python3 ] && [ "$(command -v python3)" = /usr/bin/python3 ] && command -v xcode-select > /dev/null 2>&1; then
        xcode-select -p > /dev/null 2>&1 || return 1
    fi
    return 0
}

esohub_login_code() {
    local h
    h=$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
    case "$h" in ''|*[!0-9a-f]*) return 1 ;; esac
    [ "${#h}" -eq 32 ] || return 1
    printf '%s-%s-4%s-%x%s-%s' "${h:0:8}" "${h:8:4}" "${h:13:3}" $(( (16#${h:16:1} & 3) | 8 )) "${h:17:3}" "${h:20:12}"
}

esohub_ua_kill() {
    local pid
    for pid in $ESOHUB_UA_PIDS; do
        { pkill -P "$pid"; kill "$pid"; wait "$pid"; } > /dev/null 2>&1
    done
    ESOHUB_UA_PIDS=""
}

esohub_ua_stop() {
    esohub_ua_kill
    [ -n "$ESOHUB_UA_DIR" ] && rm -rf "$ESOHUB_UA_DIR"
    ESOHUB_UA_DIR=""; ESOHUB_UA_URL=""
}

esohub_ua_nc() {
    local target="$1" path="$2" out="$3" end=$((SECONDS + ESOHUB_UA_WAIT)) rc
    shift 3
    while [ "$SECONDS" -lt "$end" ]; do
        printf 'HTTP/1.1 302 Found\r\nLocation: %s\r\nCache-Control: no-store\r\nContent-Length: 0\r\nConnection: close\r\n\r\n' "$target" \
            | nc "$@" > "$out.req" 2> /dev/null
        rc=$?
        if head -n 1 "$out.req" 2> /dev/null | grep -q "^GET $path "; then
            sed -n 's/^[Uu][Ss][Ee][Rr]-[Aa][Gg][Ee][Nn][Tt]:[[:space:]]*//p' "$out.req" | tr -d '\r' | head -n 1 > "$out.tmp"
            mv -f "$out.tmp" "$out"
            break
        fi
        if [ "$rc" -ne 0 ] && [ ! -s "$out.req" ]; then
            : > "$out.fail"
            sleep 0.2
        fi
    done
    rm -f "$out.req"
}

esohub_ua_nc_start() {
    local target="$1" path="$2" out="$3" form first second port pid dog
    case "$(nc -h 2>&1 < /dev/null | head -n 40)" in
        *"GNU netcat"*|*"[v1.10"*|*BusyBox*|*"-q secs"*) first="-l -s 127.0.0.1 -p"; second="-l 127.0.0.1" ;;
        *) first="-l 127.0.0.1"; second="-l -s 127.0.0.1 -p" ;;
    esac
    for form in "$first" "$second"; do
        port=$((49152 + RANDOM % 16000))
        ( exec 3<> "/dev/tcp/127.0.0.1/$port" ) > /dev/null 2>&1 && continue
        rm -f "$out.fail"
        esohub_ua_nc "$target" "$path" "$out" $form "$port" < /dev/null > /dev/null 2>&1 &
        pid=$!
        ( sleep $((ESOHUB_UA_WAIT + 5)); pkill -P "$pid"; kill "$pid" ) < /dev/null > /dev/null 2>&1 &
        dog=$!
        ESOHUB_UA_PIDS="$pid $dog"
        sleep 0.4
        if [ ! -f "$out.fail" ]; then
            printf '%s' "$port" > "$out.port"
            return 0
        fi
        esohub_ua_kill
    done
    rm -f "$out.fail"
    return 1
}

esohub_ua_listen() {
    local target="$1" tool path port i tried=""
    esohub_ua_stop
    ESOHUB_UA_MISSING=""
    ESOHUB_UA_DIR=$(mktemp -d 2>/dev/null) || ESOHUB_UA_DIR=""
    if [ -z "$ESOHUB_UA_DIR" ] || ! path="/$(esohub_login_code)"; then
        ESOHUB_UA_MISSING="it couldn't make a temporary folder or a random page name"
        esohub_ua_stop
        return 1
    fi
    for tool in $ESOHUB_LISTEN_TOOLS; do
        esohub_have "$tool" || continue
        tried="${tried:+$tried, }$tool"
        case "$tool" in
            python3)
                python3 -I -c "$ESOHUB_UA_PY" "$target" "$path" "$ESOHUB_UA_DIR/ua" "$ESOHUB_UA_WAIT" < /dev/null > /dev/null 2>&1 &
                ESOHUB_UA_PIDS=$! ;;
            perl)
                perl -e "$ESOHUB_UA_PL" "$target" "$path" "$ESOHUB_UA_DIR/ua" "$ESOHUB_UA_WAIT" < /dev/null > /dev/null 2>&1 &
                ESOHUB_UA_PIDS=$! ;;
            nc) esohub_ua_nc_start "$target" "$path" "$ESOHUB_UA_DIR/ua" || continue ;;
            *) continue ;;
        esac
        i=0
        while [ ! -s "$ESOHUB_UA_DIR/ua.port" ] && [ "$i" -lt 30 ]; do sleep 0.1; i=$((i + 1)); done
        port=$(cat "$ESOHUB_UA_DIR/ua.port" 2>/dev/null)
        case "$port" in
            ''|*[!0-9]*) esohub_ua_kill; rm -f "$ESOHUB_UA_DIR/ua.port" ;;
            *) ESOHUB_UA_URL="http://127.0.0.1:$port$path"; return 0 ;;
        esac
    done
    if [ -n "$tried" ]; then
        ESOHUB_UA_MISSING="$tried couldn't open a local port on 127.0.0.1"
    else
        ESOHUB_UA_MISSING="that needs python3, perl or nc (netcat), and none of them is installed"
    fi
    esohub_ua_stop
    return 1
}

esohub_ua_wait() {
    local i=0 limit=$((ESOHUB_UA_WAIT * 10))
    while [ "$i" -lt "$limit" ]; do
        if [ -f "$ESOHUB_UA_DIR/ua" ]; then
            cat "$ESOHUB_UA_DIR/ua"
            return 0
        fi
        sleep 0.1
        i=$((i + 1))
    done
    return 1
}

esohub_browser_open() {
    local page="$1" ua
    ESOHUB_UA_SEEN=""
    if ! esohub_ua_listen "$page"; then
        echo -e " \e[33m[-] The updater can't read your browser's User-Agent by itself: $ESOHUB_UA_MISSING. Step 4 asks you to paste it.\e[0m"
        esohub_open "$page"
        return 1
    fi
    esohub_open "$ESOHUB_UA_URL"
    if ua=$(esohub_ua_wait); then
        esohub_ua_stop
        if ua=$(esohub_cf_clean_ua "$ua"); then
            ESOHUB_UA_SEEN="$ua"
            echo -e " \e[0;32m[+] Login and Verify.\e[0m"
            return 0
        fi
        echo -e " \e[33m[-] Your browser sent a User-Agent the updater can't use. Step 4 asks you to paste it.\e[0m"
        return 1
    fi
    esohub_ua_stop
    echo -e " \e[33m[-] Your browser didn't reach the updater's page within $ESOHUB_UA_WAIT seconds, so ESO-Hub opens directly. Step 4 asks you to paste the User-Agent.\e[0m"
    esohub_open "$page"
    return 1
}

esohub_cf_prompt() {
    local page="${1:-$ESOHUB_CF_PAGE}" step="${2:-}" ck ua
    [ -n "$step" ] || step="Opening \e[0;35m$page\e[0m in your browser \e[90m(opening it now)\e[0m wait until ESO-Hub's page shows."
    echo -e " \e[0;33m[-] ESO-Hub Human Verification Required:\e[0m"
    echo -e "  \e[0;32m1)\e[0m $step"
    esohub_browser_open "$page"
    echo -e "  \e[0;32m2)\e[0m Press F12, then open \e[0;36mApplication\e[0m \e[90m(Chrome, Edge, Brave)\e[0m or \e[0;36mStorage\e[0m \e[90m(Firefox)\e[0m > \e[0;36mCookies\e[0m > https://eso-hub.com."
    echo -e "  \e[0;32m3)\e[0m Copy the value of \e[0;36mcf_clearance\e[0m and paste it here."
    echo -e "     \e[90mcf_clearance is ESO-Hub's proof that a human, not a bot, passed this check. The updater\e[0m"
    echo -e "     \e[90msends it with each request so ESO-Hub answers with data instead of the check again. It\e[0m"
    echo -e "     \e[90mstays on this PC and is sent only to eso-hub.com.\e[0m"
    echo -ne " \e[0;34mcf_clearance \e[90m(hidden while you paste, Enter skips)\e[0;34m: \e[0m"
    if ! ck=$(esohub_cf_read secret); then
        echo
        echo -e " \e[90mNo answer, so ESO-Hub is skipped this time.\e[0m"
        write_ttc_log "WARN" "ESO-Hub browser check skipped: no cf_clearance entered within $((ESOHUB_CF_ASK_SECONDS / 60)) minutes; the updater continues."
        return 1
    fi
    echo
    if [ -z "$ck" ]; then
        echo -e " \e[90mSkipped.\e[0m"
        return 1
    fi
    if ! ck=$(esohub_cf_clean_cookie "$ck"); then
        echo -e " \e[31m[-] That isn't a cf_clearance value. Copy the Value column of the cf_clearance row.\e[0m"
        return 1
    fi
    if [ -n "$ESOHUB_UA_SEEN" ]; then
        ua="$ESOHUB_UA_SEEN"
    else
        echo -e "  \e[0;32m4)\e[0m In the same DevTools window open \e[0;36mConsole\e[0m, type \e[0;36mnavigator.userAgent\e[0m, press Enter and copy the text it shows."
        echo -ne " \e[0;34mUser-Agent: \e[0m"
        if ! ua=$(esohub_cf_read); then
            echo
            echo -e " \e[90mNo answer, so ESO-Hub is skipped this time.\e[0m"
            write_ttc_log "WARN" "ESO-Hub browser check skipped: no cf_clearance entered within $((ESOHUB_CF_ASK_SECONDS / 60)) minutes; the updater continues."
            return 1
        fi
        if ! ua=$(esohub_cf_clean_ua "$ua"); then
            echo -e " \e[31m[-] That isn't a browser User-Agent. It starts with Mozilla/5.0.\e[0m"
            return 1
        fi
    fi
    ESOHUB_CF_CLEARANCE="$ck"; ESOHUB_CF_UA="$ua"; CONFIG_CHANGED=true
    echo -e " \e[0;32m[+] Saved (${#ck} characters). The updater only sends it to eso-hub.com.\e[0m"
    write_ttc_log "INFO" "ESO-Hub browser check saved (cf_clearance and User-Agent)."
    return 0
}

esohub_cf_ask_now() {
    if [ "${ESOHUB_COOKIE_IMPORT:-false}" = true ] && esohub_cookie_fetch; then
        ESOHUB_CF_HINT=""
        return 0
    fi
    if [ "$ESOHUB_CF_ASKED" = true ]; then
        ESOHUB_CF_HINT="The updater asks for ESO-Hub's browser check again the next time it starts."
        return 1
    fi
    ESOHUB_CF_ASKED=true
    if ! esohub_cf_can_ask; then
        ESOHUB_CF_HINT="Start the updater in a terminal or run --setup to refresh ESO-Hub's cf_clearance; a running copy picks it up next cycle."
        return 1
    fi
    ESOHUB_CF_HINT=""
    esohub_cf_prompt
}

esohub_v2_parse() {
    awk '
    { s = s $0 "\n" }
    function path(   k, p) {
        p = ""
        for (k = 1; k <= d; k++) p = p (k > 1 ? "." : "") (typ[k] == "o" ? key[k] : idx[k])
        return p
    }
    function keep(p, v,   n, rest, field) {
        if (substr(p, 1, 7) != "addons.") return
        rest = substr(p, 8)
        n = rest; sub(/\..*$/, "", n)
        if (n !~ /^[0-9]+$/) return
        field = substr(rest, length(n) + 2)
        if (v == "null") v = ""
        gsub(/[|\t\r\n]/, " ", v)
        n = n + 0
        if (n > last) last = n
        seen[n] = 1
        if (field == "id") aid[n] = v
        else if (field == "folder_name") folder[n] = v
        else if (field == "file") file[n] = v
        else if (field == "checksum") sum[n] = v
        else if (field == "version.integer") vint[n] = v
        else if (field == "version.string") vstr[n] = v
        else if (field == "transfer.endpoint") ep[n] = v
        else if (field ~ /^transfer\.sv_file_names\.[0-9]+$/ && v != "") sv[n] = (sv[n] == "" ? v : sv[n] ";" v)
    }
    END {
        n = length(s); d = 0; i = 1; last = -1
        while (i <= n) {
            c = substr(s, i, 1)
            if (c == "{") { d++; typ[d] = "o"; key[d] = ""; want[d] = 1; i++; continue }
            if (c == "[") { d++; typ[d] = "a"; idx[d] = 0; i++; continue }
            if (c == "}" || c == "]") { d--; i++; continue }
            if (c == ",") { if (typ[d] == "a") idx[d]++; else want[d] = 1; i++; continue }
            if (c == ":") { want[d] = 0; i++; continue }
            if (c == " " || c == "\t" || c == "\r" || c == "\n") { i++; continue }
            if (c == "\"") {
                str = ""; i++
                while (i <= n) {
                    c = substr(s, i, 1)
                    if (c == "\\") {
                        e = substr(s, i + 1, 1)
                        if (e == "n" || e == "t" || e == "r") str = str " "
                        else if (e == "u") { str = str "\\u" substr(s, i + 2, 4); i += 4 }
                        else str = str e
                        i += 2; continue
                    }
                    if (c == "\"") { i++; break }
                    str = str c; i++
                }
                if (d > 0 && typ[d] == "o" && want[d]) { key[d] = str; continue }
                keep(path(), str); continue
            }
            j = i
            while (j <= n) {
                c = substr(s, j, 1)
                if (c == "," || c == "}" || c == "]" || c == " " || c == "\t" || c == "\r" || c == "\n") break
                j++
            }
            keep(path(), substr(s, i, j - i)); i = j
        }
        for (k = 0; k <= last; k++) {
            if (!seen[k] || folder[k] == "") continue
            id = aid[k]
            if (match(file[k], /[0-9]+$/)) id = substr(file[k], RSTART)
            if (id == "") id = "0"
            ver = (vint[k] != "" ? vint[k] : vstr[k])
            printf "%s|%s|%s|%s|%s|%s|%s\n", id, folder[k], ver, file[k], sum[k], ep[k], sv[k]
        }
    }' "$1"
}

esohub_v1_parse() {
    local line fname sv ep file ver id
    awk '{ gsub(/\{"folder_name"/, "\n{\"folder_name\""); print }' "$1" | grep '"folder_name"' | while read -r line; do
        fname=$(echo "$line" | grep -oE '"folder_name":"[^"]+"' | cut -d'"' -f4)
        [ -z "$fname" ] && continue
        sv=$(echo "$line" | grep -oE '"sv_file_name":"[^"]+"' | cut -d'"' -f4)
        ep=$(echo "$line" | grep -oE '"endpoint":"[^"]+"' | cut -d'"' -f4 | sed 's/\\//g')
        file=$(echo "$line" | grep -oE '"file":"[^"]+"' | cut -d'"' -f4 | sed 's/\\//g')
        ver=$(echo "$line" | grep -oE '"version":\{[^}]*\}' | grep -oE '"string":"[^"]+"' | cut -d'"' -f4)
        id=$(echo "$file" | grep -oE '[0-9]+$')
        [ -z "$id" ] && id="0"
        printf '%s|%s|%s|%s||%s|%s\n' "$id" "$fname" "$ver" "$file" "$ep" "$sv"
    done
}

esohub_http() {
    local body="$1" head="$2" url="$3"; shift 3
    rm -f "$body" "$head"
    esohub_cf_config "$url" | curl -s -m 30 -K - -D "$head" -o "$body" -w '%{http_code}' "$@" "$url" 2>/dev/null
}

esohub_reason() {
    local code="$1" head="$2"
    if [ -z "$code" ] || [ "$code" = "000" ]; then echo "no connection"; return; fi
    if grep -qi '^cf-mitigated: *challenge' "$head" 2>/dev/null; then echo "HTTP $code (Cloudflare challenge)"; return; fi
    echo "HTTP $code"
}

esohub_fetch_addons() {
    local body="$TEMP_DIR_ROOT/lttc_eh_list.json" head="$TEMP_DIR_ROOT/lttc_eh_list.head" code why_v2 why_v1
    ESOHUB_RECORDS=""; ESOHUB_API_USED=""; ESOHUB_FAIL=""; ESOHUB_BLOCKED=false
    mkdir -p "$TEMP_DIR_ROOT" 2>/dev/null

    code=$(esohub_http "$body" "$head" "$ESOHUB_API/v2/api/get-addon-versions" -H "User-Agent: $(esohub_ua "$ESOHUB_V2_UA")" \
        -H "X-ESO-Hub-Client-Version: $ESOHUB_V2_VERSION" -H "Accept: application/json" ${EH_USER_TOKEN:+-H "Authorization: Bearer $EH_USER_TOKEN"})
    if [ -n "${EH_USER_TOKEN:-}" ] && [ "$code" = "401" ] && ! grep -qi '^cf-mitigated' "$head" 2>/dev/null; then
        write_ttc_log "WARN" "ESO-Hub did not accept the saved token (HTTP 401); asking again without it."
        code=$(esohub_http "$body" "$head" "$ESOHUB_API/v2/api/get-addon-versions" -H "User-Agent: $(esohub_ua "$ESOHUB_V2_UA")" \
            -H "X-ESO-Hub-Client-Version: $ESOHUB_V2_VERSION" -H "Accept: application/json")
    fi
    [ "$code" = "200" ] && ESOHUB_RECORDS=$(esohub_v2_parse "$body")
    if [ -n "$ESOHUB_RECORDS" ]; then
        ESOHUB_API_USED="v2"; rm -f "$body" "$head"; return 0
    fi
    why_v2=$(esohub_reason "$code" "$head")
    [ "$code" = "200" ] && why_v2="HTTP 200 without an add-on list"

    code=$(esohub_http "$body" "$head" "$ESOHUB_API/v1/api/get-addon-versions" -X POST -H "User-Agent: $(esohub_ua "$ESOHUB_V1_UA")" \
        -d "user_token=&client_system=${SYS_ID:-linux}&client_version=1.0.9&lang=en")
    [ "$code" = "200" ] && ESOHUB_RECORDS=$(esohub_v1_parse "$body")
    if [ -n "$ESOHUB_RECORDS" ]; then
        ESOHUB_API_USED="v1"; rm -f "$body" "$head"
        write_ttc_log "WARN" "ESO-Hub v2 add-on list failed ($why_v2); the v1 list answered."
        return 0
    fi
    why_v1=$(esohub_reason "$code" "$head")
    [ "$code" = "200" ] && why_v1="HTTP 200 without an add-on list"
    rm -f "$body" "$head"

    ESOHUB_FAIL="v2: $why_v2, v1: $why_v1"
    case "$ESOHUB_FAIL" in *Cloudflare*) ESOHUB_BLOCKED=true ;; esac
    return 1
}

esohub_local_version() {
    local f
    for f in "$1/$2.txt" "$1/$2.addon"; do
        [ -f "$f" ] || continue
        awk '/IntVersion:/ { sub(/^.*IntVersion:[ \t]*/, ""); sub(/\r$/, ""); sub(/[ \t].*$/, ""); print; exit }' "$f"
        return
    done
}

esohub_is_newer() {
    [ -n "$1" ] || return 1
    case "$1$2" in *[!0-9]*) [ "$1" != "$2" ]; return ;; esac
    [ -n "$2" ] || return 0
    [ "$1" -gt "$2" ]
}

esohub_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
    elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 "$1" | awk '{ print $NF }'
    fi
}

esohub_download() {
    local url="$1" out="$2" want="$3" got
    rm -f "$out"
    esohub_cf_config "$url" | curl -s -f -L -m 60 -K - -H "User-Agent: $(esohub_ua "$ESOHUB_V2_UA")" -H "X-ESO-Hub-Client-Version: $ESOHUB_V2_VERSION" \
        ${EH_USER_TOKEN:+-H "Authorization: Bearer $EH_USER_TOKEN"} -o "$out" --url "$url" \
        || esohub_cf_config "$url" | curl -s -f -L -m 30 -K - -A "$(esohub_ua "$ESOHUB_V1_UA")" -o "$out" --url "$url" \
        || curl -s -f -L -m 30 -A "${RAND_UA:-Mozilla/5.0}" -o "$out" --url "$url" </dev/null \
        || { rm -f "$out"; return 1; }
    if [ -n "$want" ]; then
        got=$(esohub_sha256 "$out")
        if [ -n "$got" ] && [ "$(printf '%s' "$got" | tr 'A-F' 'a-f')" != "$(printf '%s' "$want" | tr 'A-F' 'a-f')" ]; then
            write_ttc_log "ERROR" "ESO-Hub download $url failed its checksum (expected $want, got $got)."
            rm -f "$out"; return 2
        fi
    fi
    unzip -t "$out" > /dev/null 2>&1 || { rm -f "$out"; return 1; }
    return 0
}

esohub_zip() {
    local out="$1" dir="$2"; shift 2
    rm -f "$out"
    if command -v zip >/dev/null 2>&1 && (cd "$dir" && zip -q -X "$out" "$@") >/dev/null 2>&1 && [ -s "$out" ]; then return 0; fi
    rm -f "$out"
    if command -v bsdtar >/dev/null 2>&1 && bsdtar --format zip -cf "$out" -C "$dir" "$@" >/dev/null 2>&1 && [ -s "$out" ]; then return 0; fi
    rm -f "$out"
    if tar --version 2>/dev/null | grep -qi bsdtar && tar --format zip -cf "$out" -C "$dir" "$@" >/dev/null 2>&1 && [ -s "$out" ]; then return 0; fi
    rm -f "$out"
    if command -v python3 >/dev/null 2>&1 && python3 -I -c 'import os, sys, zipfile
z = zipfile.ZipFile(sys.argv[1], "w", zipfile.ZIP_DEFLATED)
for n in sys.argv[3:]: z.write(os.path.join(sys.argv[2], n), n)
z.close()' "$out" "$dir" "$@" >/dev/null 2>&1 && [ -s "$out" ]; then return 0; fi
    rm -f "$out"
    return 1
}

esohub_upload_name() {
    printf '%04x%04x-%04x-4%03x-%04x-%04x%04x%04x' $RANDOM $RANDOM $RANDOM $((RANDOM % 4096)) $((RANDOM % 16384 + 32768)) $RANDOM $RANDOM $RANDOM
}

esohub_upload_v2() {
    local url="$1" zipf="$TEMP_DIR_ROOT/lttc_eh_upload.zip" rc f
    local -a found
    shift
    found=()
    for f in "$@"; do [ -f "$SAVED_VAR_DIR/$f" ] && found+=("$f"); done
    [ "${#found[@]}" -gt 0 ] || return 1
    if ! esohub_zip "$zipf" "$SAVED_VAR_DIR" "${found[@]}"; then
        write_ttc_log "WARN" "ESO-Hub v2 upload needs zip, bsdtar or python3 to pack ${found[*]}; none worked."
        return 1
    fi
    esohub_cf_config "$url" | curl -s -f -m 60 -K - -H "User-Agent: $(esohub_ua "$ESOHUB_V2_UA")" -H "X-ESO-Hub-Client-Version: $ESOHUB_V2_VERSION" \
        -H "Accept: application/json" ${EH_USER_TOKEN:+-H "Authorization: Bearer $EH_USER_TOKEN"} \
        -F "archive=@\"$zipf\";filename=$(esohub_upload_name).zip;type=application/zip" -F "server=live" \
        "$url" > /dev/null 2>&1
    rc=$?
    rm -f "$zipf"
    return $rc
}

esohub_upload_v1() {
    local url="$1" f
    shift
    for f in "$@"; do
        esohub_cf_config "$url" | curl -s -f -m 60 -K - -A "$(esohub_ua "$ESOHUB_V1_UA")" -F "file=@\"$SAVED_VAR_DIR/$f\"" \
            "$url?user_token=${EH_USER_TOKEN:-}" > /dev/null 2>&1 || return 1
    done
    return 0
}

esohub_upload() {
    local api="$1" endpoint="$2" send="$3" all="$4" url
    local -a send_files all_files
    case "$endpoint" in http://*|https://*) url="$endpoint" ;; *) url="$ESOHUB_API$endpoint" ;; esac
    send_files=(); all_files=()
    while IFS= read -r f; do [ -n "$f" ] && send_files+=("$f"); done <<< "$(printf '%s' "$send" | tr ';' '\n')"
    while IFS= read -r f; do [ -n "$f" ] && all_files+=("$f"); done <<< "$(printf '%s' "$all" | tr ';' '\n')"
    [ "${#send_files[@]}" -gt 0 ] || return 1
    [ "${#all_files[@]}" -gt 0 ] || all_files=("${send_files[@]}")
    if [ "$api" = "v1" ]; then
        esohub_upload_v1 "$url" "${send_files[@]}" && return 0
        esohub_upload_v2 "$url" "${all_files[@]}" && return 0
    else
        esohub_upload_v2 "$url" "${all_files[@]}" && return 0
        esohub_upload_v1 "$url" "${send_files[@]}" && return 0
    fi
    return 1
}

esohub_curl_quote() {
    printf '%s' "$1" | sed 's/[\\"]/\\&/g'
}

esohub_login_reason() {
    local code="$1" head="$2" msg
    if [ -z "$code" ] || [ "$code" = "000" ]; then echo "no connection to ESO-Hub"; return; fi
    if grep -qi '^cf-mitigated: *challenge' "$head" 2>/dev/null; then echo "ESO-Hub's server answered with a Cloudflare check"; return; fi
    msg=$(grep -o '"message" *: *"[^"]*"' "$3" 2>/dev/null | head -n 1 | cut -d'"' -f4 | tr -cd '[:print:]' | tr -d '\\' | cut -c1-120)
    case "$code" in 200|401|403|422) echo "ESO-Hub did not accept that username and password${msg:+ ($msg)}"; return ;; esac
    echo "ESO-Hub answered HTTP $code${msg:+ ($msg)}"
}

esohub_request_token() {
    local user pass work code why_v2
    ESOHUB_TOKEN=""; ESOHUB_LOGIN_FAIL=""; ESOHUB_LOGIN_BLOCKED=false
    user=$(esohub_curl_quote "$1"); pass=$(esohub_curl_quote "$2")
    work=$(mktemp -d 2>/dev/null) || return 1
    code=$({ printf 'user = "%s:%s"\n' "$user" "$pass"; esohub_cf_config "$ESOHUB_API/v2/api/request-token"; } | curl -s -m 30 -K - -X POST \
        -D "$work/h" -o "$work/b" -w '%{http_code}' \
        -H "User-Agent: $(esohub_ua "$ESOHUB_V2_UA")" -H "X-ESO-Hub-Client-Version: $ESOHUB_V2_VERSION" -H "Accept: application/json" \
        "$ESOHUB_API/v2/api/request-token" 2>/dev/null)
    ESOHUB_TOKEN=$(grep -o '"token" *: *"[^"]*"' "$work/b" 2>/dev/null | head -n 1 | cut -d'"' -f4)
    why_v2=$(esohub_login_reason "$code" "$work/h" "$work/b")
    if [ -z "$ESOHUB_TOKEN" ]; then
        rm -f "$work/h" "$work/b"
        code=$({ printf 'data-urlencode = "username=%s"\ndata-urlencode = "password=%s"\n' "$user" "$pass"; esohub_cf_config "$ESOHUB_API/v1/api/login"; } \
            | curl -s -m 30 -K - -X POST -D "$work/h" -o "$work/b" -w '%{http_code}' \
            -H "User-Agent: $(esohub_ua "$ESOHUB_V1_UA")" \
            --data-urlencode "client_system=${SYS_ID:-linux}" \
            --data-urlencode "client_version=1.0.9" \
            --data-urlencode "client_version_int=1009" \
            --data-urlencode "lang=en" \
            "$ESOHUB_API/v1/api/login" 2>/dev/null)
        ESOHUB_TOKEN=$(grep -o '"token" *: *"[^"]*"' "$work/b" 2>/dev/null | head -n 1 | cut -d'"' -f4)
        if [ -z "$ESOHUB_TOKEN" ]; then
            case "$why_v2" in
                *Cloudflare*)
                    ESOHUB_LOGIN_FAIL=$(esohub_login_reason "$code" "$work/h" "$work/b")
                    case "$ESOHUB_LOGIN_FAIL" in *Cloudflare*) ESOHUB_LOGIN_BLOCKED=true ;; esac ;;
                *) ESOHUB_LOGIN_FAIL="$why_v2" ;;
            esac
        fi
    fi
    rm -rf "$work"
    [ -n "$ESOHUB_TOKEN" ]
}

esohub_code_poll() {
    esohub_http "$2/b" "$2/h" "$ESOHUB_API/v2/api/request-token-with-code" -X POST \
        -H "User-Agent: $(esohub_ua "$ESOHUB_V2_UA")" -H "X-ESO-Hub-Client-Version: $ESOHUB_V2_VERSION" \
        -H "Accept: application/json" -H "Content-Type: application/json" --data "{\"code\":\"$1\"}"
}

esohub_code_wait() {
    local start=$SECONDS ans
    if read -r -t "$1" ans < /dev/tty 2>/dev/null; then return 0; fi
    [ $((SECONDS - start)) -ge 1 ] || sleep "$1"
    return 1
}

esohub_wait_text() {
    if [ "$1" -ge 120 ]; then echo "$(($1 / 60)) minutes"; else echo "$1 seconds"; fi
}

esohub_code_answer() {
    local msg
    if [ -z "$1" ] || [ "$1" = "000" ]; then echo "no connection"; return; fi
    msg=$(grep -o '"message" *: *"[^"]*"' "$2" 2>/dev/null | head -n 1 | cut -d'"' -f4 | tr -cd '[:print:]' | tr -d '\\' | cut -c1-120)
    echo "HTTP $1${msg:+, $msg}"
}

esohub_code_login() {
    local code url work deadline http
    ESOHUB_TOKEN=""; ESOHUB_LOGIN_USER=""; ESOHUB_LOGIN_FAIL=""
    if ! code=$(esohub_login_code); then
        ESOHUB_LOGIN_FAIL="this system couldn't make a login code from /dev/urandom"
        return 1
    fi
    if ! work=$(mktemp -d 2>/dev/null); then
        ESOHUB_LOGIN_FAIL="the updater couldn't make a temporary folder"
        return 1
    fi
    url="$ESOHUB_LOGIN_PAGE$code"
    http=$(esohub_code_poll "$code" "$work")
    if [ -z "$http" ] || [ "$http" = "000" ]; then
        ESOHUB_LOGIN_FAIL="no connection to ESO-Hub"
        rm -rf "$work"
        return 1
    fi
    if grep -qi '^cf-mitigated: *challenge' "$work/h" 2>/dev/null; then
        if ! esohub_cf_prompt "$url" "Opening ESO-Hub's login page in your browser \e[90m(opening it now)\e[0m, log in and link this device, then stay on that tab for the next steps."; then
            ESOHUB_LOGIN_FAIL="the updater can't pick up the Login Token without cf_clearance, because ESO-Hub's data server answers with a Cloudflare check"
            rm -rf "$work"
            return 1
        fi
    else
        echo -e " \e[0;33mLog in to ESO-Hub in your browser \e[90m(opening it now)\e[0;33m and link this device when ESO-Hub asks.\e[0m"
        esohub_open "$url"
    fi
    deadline=$((SECONDS + ESOHUB_CODE_SECONDS))
    echo -e " \e[36mWaiting for ESO-Hub to confirm the login \e[90m(up to $(esohub_wait_text "$ESOHUB_CODE_SECONDS"), Enter stops waiting)\e[36m...\e[0m"
    while :; do
        http=$(esohub_code_poll "$code" "$work")
        ESOHUB_TOKEN=$(grep -o '"token" *: *"[^"]*"' "$work/b" 2>/dev/null | head -n 1 | cut -d'"' -f4)
        if [ -n "$ESOHUB_TOKEN" ]; then
            ESOHUB_LOGIN_USER=$(grep -o '"username" *: *"[^"]*"' "$work/b" 2>/dev/null | head -n 1 | cut -d'"' -f4 | tr -cd '[:print:]' | tr -d '\\' | cut -c1-60)
            break
        fi
        if grep -qi '^cf-mitigated: *challenge' "$work/h" 2>/dev/null; then
            ESOHUB_LOGIN_FAIL="ESO-Hub's server still answers with a Cloudflare check; copy cf_clearance from the browser that opened, on this PC and network"
            break
        fi
        if [ "$SECONDS" -ge "$deadline" ]; then
            ESOHUB_LOGIN_FAIL="ESO-Hub didn't confirm the login within $(esohub_wait_text "$ESOHUB_CODE_SECONDS") (last answer: $(esohub_code_answer "$http" "$work/b"))"
            break
        fi
        if esohub_code_wait "$ESOHUB_CODE_POLL"; then
            ESOHUB_LOGIN_FAIL="you stopped waiting"
            break
        fi
    done
    rm -rf "$work"
    [ -n "$ESOHUB_TOKEN" ]
}
