#!/bin/bash
url="$1"
log="${EH_BROWSER_LOG:-/dev/null}"
mode="${EH_BROWSER:-none}"
ua="${EH_BROWSER_UA:-Mozilla/5.0 (X11; Linux x86_64) TestBrowser/1.0}"
clean() { sed -E 's/127\.0\.0\.1:[0-9]+/127.0.0.1:PORT/g; s/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/CODE/g'; }
case "$url" in
    http://127.0.0.1:*)
        if [ "$mode" = none ]; then
            echo "ignored $url" | clean >> "$log"
            exit 0
        fi
        if [ "$mode" = stray ]; then
            echo "stray $(curl -s -m 5 -o /dev/null -w '%{http_code}' -A "$ua" "${url%/*}/favicon.ico")" >> "$log"
        fi
        res="$(curl -s -m 5 -o /dev/null -w '%{http_code} %{redirect_url}' -A "$ua" "$url")"
        echo "visit $res" | clean >> "$log"
        url="${res#* }" ;;
    *) echo "open $url" | clean >> "$log" ;;
esac
[ "$mode" = approve ] || exit 0
case "$url" in
    *client-token-login\?code=*)
        echo "approve $(curl -s -m 5 -o /dev/null -w '%{http_code}' -X POST --data-urlencode "code=${url##*code=}" "$LTTC_ESOHUB_API/test/approve")" >> "$log" ;;
esac
