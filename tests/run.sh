#!/bin/bash
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
FIX="tests/fixtures"
PWSH="${PWSH:-$(command -v pwsh || true)}"
MAC_BASH="${MAC_BASH:-bash}"
WORK="$(mktemp -d)"
MOCK_PID=""
EH_MOCK_PID=""
GH_MOCK_PID=""
trap '[ -n "$MOCK_PID" ] && kill "$MOCK_PID" 2>/dev/null; [ -n "$EH_MOCK_PID" ] && kill "$EH_MOCK_PID" 2>/dev/null; [ -n "$GH_MOCK_PID" ] && kill "$GH_MOCK_PID" 2>/dev/null; rm -rf "$WORK"' EXIT
pass=0; fail=0; skip=0

ok() { pass=$((pass + 1)); echo "  ok    $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL  $1"; }

mkdir -p "$WORK/bin"
if ! command -v md5 >/dev/null 2>&1; then
    printf '#!/bin/sh\n[ "$1" = "-q" ] && shift\nmd5sum "$@" | cut -d" " -f1\n' > "$WORK/bin/md5"
    chmod +x "$WORK/bin/md5"
fi
MAC_PATH="${MAC_PATH:+$MAC_PATH:}$WORK/bin"
if ! command -v curl.exe >/dev/null 2>&1; then
    printf '#!/bin/sh\nexec curl "$@"\n' > "$WORK/bin/curl.exe"
    chmod +x "$WORK/bin/curl.exe"
fi

run_linux() { bash tests/lib/linux.sh "$@"; }
run_macos() { PATH="$MAC_PATH:$PATH" LTTC_PLATFORM=macos "$MAC_BASH" tests/lib/linux.sh "$@"; }
run_windows() { PATH="$WORK/bin:$PATH" "$PWSH" -NoProfile -File tests/lib/windows.ps1 "$@"; }

norm() { sed -E 's/\x1b\[90m([0-9]+[smhd] ago|Active)\x1b\[0m/\x1b[90mT\x1b[0m/g' "$1"; }

compare() {
    local name="$1" other="$2" label="$3"
    if cmp -s <(norm "$WORK/lin") <(norm "$WORK/$other"); then return 0; fi
    bad "$name ($label differs from Linux)"
    diff <(norm "$WORK/lin" | cat -v) <(norm "$WORK/$other" | cat -v) | head -n 10
    head -n 5 "$WORK/$other.err"
    return 1
}

same() {
    local name="$1"; shift
    local db="$WORK/db" good=true
    cp "$FIX/LTTC_Database.db" "$db"; run_linux "$db" "$@" > "$WORK/lin" 2> "$WORK/lin.err"
    if [ ! -s "$WORK/lin" ] && [ "${ALLOW_EMPTY:-}" != 1 ]; then bad "$name: Linux printed nothing"; cat "$WORK/lin.err"; return; fi
    cp "$FIX/LTTC_Database.db" "$db"; run_macos "$db" "$@" > "$WORK/mac" 2> "$WORK/mac.err"
    compare "$name" mac macOS || good=false
    if [ -n "$PWSH" ]; then
        cp "$FIX/LTTC_Database.db" "$db"; run_windows "$db" "$@" > "$WORK/win" 2> "$WORK/win.err"
        compare "$name" win Windows || good=false
    else
        skip=$((skip + 1))
    fi
    [ "$good" = true ] && ok "$name ($(wc -l < "$WORK/lin" | tr -d ' ') lines)"
}

expect() {
    local name="$1" file="$2" want="$3"
    if grep -qF -- "$want" "$file"; then ok "$name"; else bad "$name (missing: $want)"; head -n 5 "$file"; fi
}

script_name() {
    case "$1" in
        linux) echo Linux_Tamriel_Trade_Center.sh ;;
        macos) echo macOS_Tamriel_Trade_Center.sh ;;
        windows) echo Windows_Tamriel_Trade_Center.bat ;;
    esac
}

expect_text() {
    local name="$1" file="$2" want="$3"
    if python3 -I -c 'import sys; sys.exit(0 if sys.argv[2].encode() in open(sys.argv[1], "rb").read() else 1)' "$file" "$want"; then ok "$name"; else bad "$name (missing text)"; head -n 5 "$file"; fi
}
platforms() { echo linux macos; [ -n "$PWSH" ] && echo windows; }

echo "build"
if bash scripts/build.sh --check > "$WORK/build" 2>&1; then ok "dist/ matches src/ and VERSION"; else bad "build check"; cat "$WORK/build"; fi
for f in dist/Linux_Tamriel_Trade_Center.sh dist/macOS_Tamriel_Trade_Center.sh; do
    if bash -n "$f"; then ok "$(basename "$f") parses"; else bad "$(basename "$f") parses"; fi
done
if "$MAC_BASH" -n dist/macOS_Tamriel_Trade_Center.sh; then ok "macOS script parses under $("$MAC_BASH" -c 'echo bash $BASH_VERSION')"; else bad "macOS script under $MAC_BASH"; fi
if grep -q ',,}\|\^\^}\|declare -A\|mapfile\|readarray' dist/macOS_Tamriel_Trade_Center.sh; then bad "macOS script uses bash 4 syntax"; else ok "macOS script avoids bash 4 syntax"; fi
if grep -q 'OS_TYPE" = "Darwin"\|osascript' dist/Linux_Tamriel_Trade_Center.sh; then bad "Linux script still carries macOS code"; else ok "Linux script is Linux-only"; fi
if grep -q 'notify-send\|xdg-\|flock\|md5sum\|date -d\|sed -i -e' dist/macOS_Tamriel_Trade_Center.sh; then bad "macOS script uses GNU/Linux-only tools"; else ok "macOS script avoids GNU/Linux-only tools"; fi
split_now=$(for f in $(cd src/linux && find . -name '*.sh'); do cmp -s "src/linux/$f" "src/macos/$f" || echo "${f#./}"; done | LC_ALL=C sort | tr '\n' ' ')
split_want="features/addons/install.sh features/cycle/cleanup.sh features/database/browser.sh features/setup/startup.sh features/setup/wizard.sh lib/esoui.sh lib/game_detect.sh lib/instance_lock.sh lib/output.sh lib/paths.sh lib/system.sh main.sh "
if [ "$split_now" = "$split_want" ]; then ok "Linux and macOS differ only in platform files"; else bad "Linux/macOS split changed: $split_now"; fi
if [ -n "$PWSH" ]; then
    if "$PWSH" -NoProfile -Command '$t=$null;$e=$null; $c=(Get-Content -Raw dist/Windows_Tamriel_Trade_Center.bat) -replace "(?sm)^.*?\n==POWERSHELL_START==\r?\n",""; [void][System.Management.Automation.Language.Parser]::ParseInput($c,[ref]$t,[ref]$e); if ($e) { $e | % { "$($_.Extent.StartLineNumber): $($_.Message)" }; exit 1 }'; then
        ok "Windows script parses"
    else bad "Windows script parses"; fi
fi
if grep -q $'\r$' dist/Windows_Tamriel_Trade_Center.bat && ! grep -q $'\r' dist/Linux_Tamriel_Trade_Center.sh dist/macOS_Tamriel_Trade_Center.sh; then ok "line endings (bat CRLF, sh LF)"; else bad "line endings"; fi

echo "extraction"
same "TTC, full"           ttc    "$FIX/TamrielTradeCentre.lua" 0 1759300000
same "TTC, since last"     ttc    "$FIX/TamrielTradeCentre.lua" 1759150000 1759300000
cat > "$WORK/qual.lua" <<'QUAL'
TamrielTradeCentreVars =
{
    ["Default"] = 
    {
        ["@ExampleUser"] = 
        {
            ["$AccountWide"] = 
            {
                ["NAData"] = 
                {
                    ["AutoRecordEntries"] = 
                    {
                        ["Guilds"] = 
                        {
                            ["Example Traders Guild"] = 
                            {
                                ["Entries"] = 
                                {
                                    [0] = 
                                    {
                                        ["TotalPrice"] = 30286,
                                        ["QualityID"] = 3,
                                        ["ItemLink"] = "|H0:item:119563:5:1:0:0:0:62:188:4:678:26:11:0:0:0:0:0:0:0:0:528000|h|h",
                                        ["MasterWritInfo"] = 
                                        {
                                            ["RequiredQualityID"] = 4,
                                        },
                                        ["Name"] = "Master Blacksmithing Writ",
                                        ["Amount"] = 1,
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    },
}
QUAL
printf '#DATABASE VERSION: 1.0.0\n119563|5|5|1|Legendary (Gold) 5|Master Blacksmithing Writ|Materials/Misc\n' > "$WORK/qualdb"
bash tests/lib/linux.sh "$WORK/qualdb" ttc "$WORK/qual.lua" 0 1759300000 > "$WORK/qual" 2>&1
if grep -q $'\033\[35mMaster Blacksmithing Writ' "$WORK/qual" && grep -q 'DB_UPDATE|119563|4|' "$WORK/qual"; then
    ok "TTC colors come from the game's QualityID (purple master writ), fixing a wrong cached gold"
else bad "TTC QualityID color"; cat "$WORK/qual"; fi
same "TTC QualityID, every platform" ttc "$WORK/qual.lua" 0 1759300000
same "TTC upload, NA"      ttcupload "$FIX/TamrielTradeCentre_upload.lua" NA 1759300000 ""
same "TTC upload, EU"      ttcupload "$FIX/TamrielTradeCentre_upload.lua" EU 1759300000 ""
same "TTC upload, with an upload cache" ttcupload "$FIX/TamrielTradeCentre_upload.lua" NA 1759300000 "$FIX/ttc_uploaded_cache.txt"
bash tests/lib/linux.sh "$FIX/LTTC_Database.db" ttcupload "$FIX/TamrielTradeCentre_upload.lua" NA 1759300000 "$FIX/ttc_uploaded_cache.txt" > "$WORK/upc"
if [ "$(grep -c '^E' "$WORK/upc")" = 2 ] && ! grep -q '"UID":"900000000000000001"' "$WORK/upc"; then ok "TTC upload skips listings already in the upload cache, resends a UID seen again later"; else bad "TTC upload cache"; cat "$WORK/upc"; fi
expect "TTC upload reports the newest listing in the file" "$WORK/upc" "N	1759295500"
printf '[{"TradeAsset":{"Amount":1,"Item":{"ID":5,"UID":"77","MasterWritInfo":{"RequiredItemID":4}}},"PlayerID":"@a","GuildID":9,"DiscoverUnixTime":1759290000,"ExpireUnixTime":1759900000},{"TradeAsset":{"Item":{"ID":6,"UID":"78"}},"PlayerID":"@b","GuildID":9,"DiscoverUnixTime":1759291000,"ExpireUnixTime":1759900000}]' > "$WORK/batch"
bash -c 'source src/linux/features/ttc/upload.sh; ttc_upload_remember "$1" 1759299999' _ "$WORK/batch" > "$WORK/remember"
if [ "$(cat "$WORK/remember")" = "$(printf '77\t1759290000\t1759299999\n78\t1759291000\t1759299999')" ]; then ok "TTC upload remembers every accepted listing (uid, seen, uploaded)"; else bad "TTC upload remember"; cat "$WORK/remember"; fi
bash tests/lib/linux.sh "$FIX/LTTC_Database.db" ttcupload "$FIX/TamrielTradeCentre_upload.lua" NA 1759300000 "" > "$WORK/up"
expect "TTC upload sorts potion effects"   "$WORK/up" '"PotionEffectIDs":[3,9]'
expect "TTC upload keeps master writ info" "$WORK/up" '"MasterWritInfo":{"RequiredItemID":44,"RequiredPotionEffectIDs":[5,20],"NumVoucher":7}'
expect "TTC upload keeps the newest copy"  "$WORK/up" '"TotalPrice":800'
expect "TTC upload sends unknown items as links" "$WORK/up" 'L	|H0:item:999999'
expect "TTC upload confirms kiosks"        "$WORK/up" 'K	Seen Guild	34	1759295000'
if [ "$(grep -c '^E' "$WORK/up")" = 3 ]; then ok "TTC upload drops old, expired, no-kiosk, UID 0 and old-client entries"; else bad "TTC upload entry count ($(grep -c '^E' "$WORK/up"))"; cat "$WORK/up"; fi
same "ESO-Hub, full"       esohub "$FIX/EsoTradingHub.lua" 0 1759300000
same "ESO-Hub, since last" esohub "$FIX/EsoTradingHub.lua" 1759215000 1759300000

echo "database"
same "history merge"      merge   "$FIX/LTTC_History.db" "$FIX/incoming_history.txt"
same "shared history from the template" tplhist "$FIX/LTTC_History.db" "$FIX/template_history.db" 2026.09.30.16.00
expect "  -> the history takes the template's CalVer version" "$WORK/lin" "#HISTORY VERSION: 2026.09.30.16.00"
expect "  -> a sale both copies have is merged, keeping the higher scan count" "$WORK/lin" "@ExampleUser, @TemplateSeller|Second Example Guild|12|"$'\033'"[32m|TTC|5"
expect "  -> a listing is not counted twice" "$WORK/lin" "|Lockpick||@OtherBuyer|Second Example Guild|999|"$'\033'"[97m|TTC|3"
expect "  -> new entries from the template are added" "$WORK/lin" "|Sold|1500|10|30357|Lockpick|@TemplateBuyer|@TemplateSeller|Template Guild|42|"
same "shared history into an empty history" tplhist - "$FIX/template_history.db" 2026.09.30.16.00
same "30-day prune"       prune   "$FIX/LTTC_History.db" 1761700000
expect "  -> the prune line reports count, size, ages and the near-cutoff count" "$WORK/lin" "near the 30-day cutoff."
expect "  -> it shows the history file size" "$WORK/lin" "entries, "
ALLOW_EMPTY=1 same "prune, all expired" prune "$FIX/LTTC_History.db" 1900000000
same "item DB updates"    dbapply "$FIX/db_updates.txt"

echo "browser"
for s in 1 2 3 4 5; do same "search, sort $s" listing "$FIX/LTTC_History.db" "$s" "" "" "" 0; done
same "search term + source"   listing "$FIX/LTTC_History.db" 1 "khajiit" "ttc" "" 0
same "search user + cutoff"   listing "$FIX/LTTC_History.db" 3 "" "" "@examplebuyer" 1759100000
same "search by kiosk name"   listing "$FIX/LTTC_History.db" 5 "stormhaven" "" "" 0
for s in 1 3 5; do same "previous scan, sort $s" scan "$FIX/LTTC_LastScan.log" "$s" ""; done
same "top 10 by volume"       top   "$FIX/LTTC_History.db" vol "" "" 0
same "top 10 by gold"         top   "$FIX/LTTC_History.db" gold "" "" 0
same "top 10, ESO-Hub only"   top   "$FIX/LTTC_History.db" vol "eso-hub" "" 0
same "price check, all"       price "$FIX/LTTC_History.db" "" "" "" 0
same "price check, term"      price "$FIX/LTTC_History.db" "JUTE" "" "" 0

echo "add-on updates"
for pair in "2026.09.30.12.47|v6.0|yes" "v6.0|2026.09.30.12.47|no" "0.0.3|0.0.2|yes" "0.0.2|0.0.2|no" "1.01|1|yes" "2.0 r43|2.0 r42|yes"; do
    IFS='|' read -r va vb vwant <<< "$pair"
    same "version $va vs $vb" vnewer "$va" "$vb"
    expect "  -> $va newer than $vb: $vwant" "$WORK/lin" "$vwant"
done
add_bom() {
    for f in "$1/BomLib/BomLib.addon" "$1/NestMap/NestMap.addon"; do
        { printf '\357\273\277'; cat "$f"; } > "$f.bom" && mv "$f.bom" "$f"
    done
}
cp -a "$FIX/AddOns" "$WORK/AddOns"
add_bom "$WORK/AddOns"
mkdir -p "$WORK/linked/LinkedLib"; printf '## AddOnVersion: 1\n' > "$WORK/linked/LinkedLib/LinkedLib.addon"
ln -s "$WORK/linked/LinkedLib" "$WORK/AddOns/LinkedLib"
same "scan of the AddOns folder" localist "$WORK/AddOns"
same "update plan against ESOUI" plan "$WORK/AddOns" "$FIX/esoui_filelist.json"
expect "  -> nested module newer than its folder is caught" "$WORK/lin" "UPDATE|103|NestMap|316004|316012"
expect "  -> folder without AddOnVersion compares Version" "$WORK/lin" "UPDATE|104|Dotted|4.26.1|4.27.281"
expect "  -> single listing beats a bundle" "$WORK/lin" "UPDATE|101|LibFoo|9|10"
expect "  -> byte order mark in a version is ignored" "$WORK/lin" "UPDATE|109|BomLib|19|20"
expect "  -> first of two equal listings wins" "$WORK/lin" "UPDATE|110|TieLib|2|3"
expect "  -> versions that cannot be compared are left alone" "$WORK/lin" "UNKNOWN|106|WeirdOne"
expect "  -> a local copy newer than ESOUI is not downgraded" "$WORK/lin" "CURRENT|112|AheadLib|12|10"
expect "  -> versions with a different number of parts (v2.1 and 2.1.0) are not updated" "$WORK/lin" "UNKNOWN|113|SameDotted|2.1.0|v2.1"
expect "  -> a manifest the author never bumped (1.0 vs ESOUI 1.0.6) is not updated blindly" "$WORK/lin" "UNKNOWN|114|StaleManifest|1.0|1.0.6"
expect "  -> an add-on already at the ESOUI version is left alone" "$WORK/lin" "CURRENT|105|CurrentOne|7|7"
expect "  -> a discontinued fork with a bigger number is ignored for the newest upload" "$WORK/lin" "CURRENT|121|ForkChain|11.4.2|11.4.2"
expect "  -> of two listings, the newest upload wins over a bigger number" "$WORK/lin" "UPDATE|124|ForkNewer|5|6"
expect "  -> the listing matching the installed copy beats a newer look-alike" "$WORK/lin" "CURRENT|125|LocalFork|2.4.47|2.4.47"
expect "  -> identical versions (2.14.0-beta) count as current" "$WORK/lin" "CURRENT|127|BetaOne|2.14.0-beta|2.14.0-beta"
expect "  -> a dotted AddOnVersion (1.2.3 vs 1.2.4) is compared" "$WORK/lin" "UPDATE|128|DottedAv|1.2.3|1.2.4"
if [ "$(grep -c '^UPDATE|' "$WORK/lin")" = 7 ]; then ok "  -> exactly the 7 outdated add-ons are planned"; else bad "  -> planned $(grep -c '^UPDATE|' "$WORK/lin") updates, expected 7"; fi
same "update plan with an install record, same ESOUI upload" plan "$WORK/AddOns" "$FIX/esoui_filelist.json" "$FIX/addon_records.txt"
expect "  -> installed by the updater and unchanged on ESOUI: left alone" "$WORK/lin" "CURRENT|114|StaleManifest|1.0|1.0.6"
sed 's/"lastUpdate":2000/"lastUpdate":3000/' "$FIX/esoui_filelist.json" > "$WORK/catalog_newer.json"
same "update plan with an install record, newer ESOUI upload" plan "$WORK/AddOns" "$WORK/catalog_newer.json" "$FIX/addon_records.txt"
expect "  -> installed by the updater and re-uploaded on ESOUI: updated" "$WORK/lin" "UPDATE|114|StaleManifest|1.0|1.0.6|3000"
same "update plan against ESOUI (again, for the folder checks)" plan "$WORK/AddOns" "$FIX/esoui_filelist.json"
if grep -q "HarvestMapData\|LinkedLib\|NoManifest\|hidden" "$WORK/lin"; then bad "  -> excluded, linked or manifest-less folders were planned"; else ok "  -> excluded, linked and manifest-less folders are skipped"; fi

python3 - "$WORK/pkg.zip" <<'PYEOF'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("LibFoo/LibFoo.addon", "## Title: LibFoo\n## AddOnVersion: 10\n")
    z.writestr("LibFoo/LibFoo.lua", "-- new\n")
    z.writestr("HarvestMapData/HarvestMapData.addon", "## AddOnVersion: 99999\n")
    z.writestr("LinkedLib/LinkedLib.addon", "## AddOnVersion: 999\n")
PYEOF
for plat in $(platforms); do
    rm -rf "$WORK/inst"; mkdir -p "$WORK/inst/target"; cp -a "$FIX/AddOns" "$WORK/inst/AddOns"
    add_bom "$WORK/inst/AddOns"
    ln -s "$WORK/linked/LinkedLib" "$WORK/inst/AddOns/LinkedLib"
    "run_$plat" "$WORK/db" install "$WORK/inst/AddOns" "$WORK/inst/target" "$WORK/pkg.zip" > "$WORK/inst.out" 2>&1
    if grep -q "installed: LibFoo$" "$WORK/inst.out" \
        && grep -q "AddOnVersion: 10" "$WORK/inst/AddOns/LibFoo/LibFoo.addon" \
        && grep -q "AddOnVersion: 9" "$WORK/inst/target/Backups/AddOns/LibFoo/LibFoo.addon" \
        && grep -q "AddOnVersion: 1$" "$WORK/inst/AddOns/HarvestMapData/HarvestMapData.addon" \
        && grep -q "AddOnVersion: 1$" "$WORK/linked/LinkedLib/LinkedLib.addon"; then
        ok "add-on install on $plat (replaced, backed up, excluded and linked folders untouched)"
        "run_$plat" "$WORK/db" plan "$WORK/inst/AddOns" "$FIX/esoui_filelist.json" > "$WORK/replan.out" 2>&1
        expect "  -> after installing, $plat sees LibFoo as current (no update loop)" "$WORK/replan.out" "CURRENT|101|LibFoo|10|10"
    else
        bad "add-on install on $plat"; cat "$WORK/inst.out"
    fi
    if [ -n "$(find "$WORK/inst/target/Backups/AddOns/LibFoo" -maxdepth 0 -mmin -5 2>/dev/null)" ]; then
        ok "  -> the $plat backup is dated when it is made, so its 30 days start from the update"
    else
        bad "  -> $plat backup keeps the old add-on's date"
    fi
done

for plat in $(platforms); do
    rm -rf "$WORK/prune"; mkdir -p "$WORK/prune/Backups/AddOns/OldLib" "$WORK/prune/Backups/AddOns/FreshLib" "$WORK/prune/Backups/AddOns/EdgeLib"
    touch -t "$(python3 -c 'import time; print(time.strftime("%Y%m%d%H%M", time.localtime(time.time() - 40 * 86400)))')" "$WORK/prune/Backups/AddOns/OldLib"
    touch -t "$(python3 -c 'import time; print(time.strftime("%Y%m%d%H%M", time.localtime(time.time() - 29 * 86400)))')" "$WORK/prune/Backups/AddOns/EdgeLib"
    "run_$plat" "$WORK/db" backupprune "$WORK/prune" > "$WORK/prune.out" 2>&1
    if [ "$(tr '\n' ' ' < "$WORK/prune.out")" = "EdgeLib FreshLib " ]; then
        ok "$plat prunes add-on backups untouched for more than 30 days and keeps newer ones"
    else
        bad "$plat backup prune"; cat "$WORK/prune.out"
    fi
done

echo "temp files stay in the updater's Temp folder"
for f in dist/Linux_Tamriel_Trade_Center.sh dist/macOS_Tamriel_Trade_Center.sh; do
    if grep -qE '"/tmp/|TMPDIR|GetTempPath' "$f"; then
        bad "$(basename "$f") writes to the system temp folder"
    elif ! grep -q 'TEMP_DIR="\$TEMP_DIR_ROOT/Downloads"' "$f"; then
        bad "$(basename "$f") downloads outside Temp"
    else
        ok "$(basename "$f") keeps downloads, uploads, locks and merges in Temp"
    fi
done
if grep -qE 'GetTempPath|\$env:TEMP\b|\$env:TMP\b' dist/Windows_Tamriel_Trade_Center.bat; then
    bad "Windows_Tamriel_Trade_Center.bat writes to the system temp folder"
elif ! grep -q '\$TEMP_DIR = "\$TEMP_DIR_ROOT\\Downloads"' dist/Windows_Tamriel_Trade_Center.bat; then
    bad "Windows_Tamriel_Trade_Center.bat downloads outside Temp"
else
    ok "Windows_Tamriel_Trade_Center.bat keeps downloads and uploads in Temp"
fi

echo "self-update and ESOUI downloads"
MOCK="$WORK/mock"; mkdir -p "$MOCK/v3/game/ESO/filedetails" "$MOCK/getfile"
python3 tests/lib/mock_esoui.py "$MOCK" "$WORK/port" "$WORK/requests.log" &
MOCK_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$WORK/port" ] && break; sleep 0.3; done
PORT="$(cat "$WORK/port" 2>/dev/null)"
export LTTC_ESOUI_API="http://127.0.0.1:$PORT"
NEWV="2099.01.01.00.00"
OLDV="$(tr -d ' \r\n' < VERSION)"
mkdir -p "$WORK/newpkg" "$WORK/oldpkg"
cp dist/Linux_Tamriel_Trade_Center.sh dist/macOS_Tamriel_Trade_Center.sh dist/Windows_Tamriel_Trade_Center.bat "$WORK/oldpkg/"
sed "s/^APP_VERSION=\"[^\"]*\"/APP_VERSION=\"$NEWV\"/" dist/Linux_Tamriel_Trade_Center.sh > "$WORK/newpkg/Linux_Tamriel_Trade_Center.sh"
sed "s/^APP_VERSION=\"[^\"]*\"/APP_VERSION=\"$NEWV\"/" dist/macOS_Tamriel_Trade_Center.sh > "$WORK/newpkg/macOS_Tamriel_Trade_Center.sh"
perl -pe "s/^\\\$APP_VERSION = \"[^\"]*\"/\\\$APP_VERSION = \"$NEWV\"/" dist/Windows_Tamriel_Trade_Center.bat > "$WORK/newpkg/Windows_Tamriel_Trade_Center.bat"
publish() {
    python3 - "$MOCK" "$PORT" "$WORK/newpkg" "$NEWV" "$1" <<'PYEOF'
import hashlib, json, os, sys, zipfile
mock, port, pkg, ver, digest = sys.argv[1:6]
zpath = os.path.join(mock, "getfile", "3249.zip")
with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
    for name in sorted(os.listdir(pkg)):
        z.write(os.path.join(pkg, name), "Tamriel Trade Center Auto-Updater/" + name)
md5 = hashlib.md5(open(zpath, "rb").read()).hexdigest() if digest == "real" else "0" * 32
details = [{"UID": "3249", "UIVersion": ver, "UIMD5": md5,
            "UIDownload": "http:\\/\\/127.0.0.1:%s\\/downloads\\/getfile.php?id=3249&d=1&minion" % port}]
open(os.path.join(mock, "v3/game/ESO/filedetails/3249.json"), "w").write(json.dumps(details, separators=(",", ":")).replace("\\\\/", "\\/"))
PYEOF
}
publish real
for plat in $(platforms); do
    name="$(script_name "$plat")"
    rm -rf "$WORK/self"; mkdir -p "$WORK/self/installed" "$WORK/self/elsewhere"
    cp "$WORK/oldpkg/$name" "$WORK/self/installed/$name"; cp "$WORK/oldpkg/$name" "$WORK/self/elsewhere/$name"
    : > "$WORK/requests.log"
    "run_$plat" "$WORK/db" selfinstall "$WORK/self/installed" "$name" "$WORK/self/elsewhere/$name" "$OLDV" > "$WORK/self.out" 2>&1
    if grep -q "rc=0 new=$NEWV" "$WORK/self.out" && grep -q "installed/$name: APP_VERSION=\"$NEWV\"" "$WORK/self.out" \
        && grep -q "elsewhere/$name.*APP_VERSION=\"$NEWV\"" "$WORK/self.out"; then
        ok "self-update on $plat installs the newer ESOUI version"
    else
        bad "self-update on $plat"; cat "$WORK/self.out"
    fi
    expect "  -> downloaded through ESOUI's counted getfile.php link" "$WORK/requests.log" "/downloads/getfile.php?id=3249"
    "run_$plat" "$WORK/db" selfinstall "$WORK/self/installed" "$name" "$WORK/self/elsewhere/$name" "$NEWV" > "$WORK/self.out" 2>&1
    expect "  -> refuses a version that is not newer" "$WORK/self.out" "rc=3"
done

GHS="$WORK/ghself"; mkdir -p "$GHS"
python3 tests/lib/mock_github.py "$GHS" "$WORK/ghsport" "$WORK/ghs_requests.log" &
GH_MOCK_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$WORK/ghsport" ] && break; sleep 0.3; done
GHSPORT="$(cat "$WORK/ghsport" 2>/dev/null)"
export LTTC_SELF_GH_API="http://127.0.0.1:$GHSPORT"
echo "$NEWV" > "$GHS/selfver"
python3 - "$GHS/self.zip" "$WORK/newpkg" <<'PYZIP'
import os, sys, zipfile
dst, pkg = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as z:
    for name in sorted(os.listdir(pkg)):
        z.write(os.path.join(pkg, name), "Tamriel Trade Center Auto-Updater/" + name)
PYZIP
GHS_URL="http://127.0.0.1:$GHSPORT/ghdl/Tamriel_Trade_Center_Auto-Updater.zip"
for plat in $(platforms); do
    out="$("run_$plat" "$WORK/db" ghself 2>&1)"
    if echo "$out" | grep -q "ver=$NEWV url=$GHS_URL"; then
        ok "self-update reads the GitHub release on $plat (version $NEWV, picks the updater asset)"
    else
        bad "ghself on $plat"; echo "$out"
    fi
    name="$(script_name "$plat")"
    rm -rf "$WORK/self"; mkdir -p "$WORK/self/installed" "$WORK/self/elsewhere"
    cp "$WORK/oldpkg/$name" "$WORK/self/installed/$name"; cp "$WORK/oldpkg/$name" "$WORK/self/elsewhere/$name"
    "run_$plat" "$WORK/db" selfinstall "$WORK/self/installed" "$name" "$WORK/self/elsewhere/$name" "$OLDV" github "$GHS_URL" > "$WORK/self.out" 2>&1
    if grep -q "rc=0 new=$NEWV" "$WORK/self.out" && grep -q "installed/$name: APP_VERSION=\"$NEWV\"" "$WORK/self.out"; then
        ok "  -> $plat installs the newer version from the GitHub release asset"
    else
        bad "  -> $plat github install"; cat "$WORK/self.out"
    fi
done
kill "$GH_MOCK_PID" 2>/dev/null; GH_MOCK_PID=""; unset LTTC_SELF_GH_API
python3 - "$MOCK" "$PORT" tests/fixtures/LTTC_Database.db tests/fixtures/template_history.db <<'PYEOF'
import json, os, sys, zipfile
mock, port, db, hist = sys.argv[1:5]
zpath = os.path.join(mock, "getfile", "4428.zip")
with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
    z.write(db, "LTTC_Database.db")
    z.write(hist, "LTTC_History.db")
details = [{"UID": "4428", "UIVersion": "2026.09.30.16.00", "UIMD5": "",
            "UIDownload": "http:\\/\\/127.0.0.1:%s\\/downloads\\/getfile.php?id=4428&d=1&minion" % port}]
open(os.path.join(mock, "v3/game/ESO/filedetails/4428.json"), "w").write(json.dumps(details, separators=(",", ":")).replace("\\\\/", "\\/"))
PYEOF
want_items="$(grep -vc '^#' tests/fixtures/LTTC_Database.db)"
want_hist="$(grep -c '^HISTORY|' tests/fixtures/template_history.db)"
for plat in $(platforms); do
    rm -rf "$WORK/fresh"; mkdir -p "$WORK/fresh"
    "run_$plat" "$WORK/db" dbsync "$WORK/fresh" > "$WORK/fresh.out" 2>&1
    if grep -q "database #DATABASE VERSION: 2026.09.30.16.00 items=$want_items" "$WORK/fresh.out" \
        && grep -q "history #HISTORY VERSION: 2026.09.30.16.00 lines=$want_hist" "$WORK/fresh.out" \
        && grep -q "temp_left=0" "$WORK/fresh.out"; then
        ok "fresh install on $plat fills LTTC_Database.db and LTTC_History.db from the ESOUI template"
    else
        bad "fresh install on $plat (template)"; cat "$WORK/fresh.out"
    fi
done
for plat in $(platforms); do
    rm -rf "$WORK/fresh"; mkdir -p "$WORK/fresh/Database"
    { echo "#DATABASE VERSION: 2026.09.30.16.00"; grep -v '^#' tests/fixtures/LTTC_Database.db; } > "$WORK/fresh/Database/LTTC_Database.db"
    : > "$WORK/fresh/Database/LTTC_History.db"
    "run_$plat" "$WORK/db" dbsync "$WORK/fresh" > "$WORK/fresh.out" 2>&1
    expect "  -> $plat: up-to-date item database with an empty history gets the template's history once" "$WORK/fresh.out" "history #HISTORY VERSION: 2026.09.30.16.00 lines=$want_hist"
    : > "$WORK/requests.log"
    "run_$plat" "$WORK/db" dbsync "$WORK/fresh" > "$WORK/fresh.out" 2>&1
    if grep -q "getfile.php?id=4428" "$WORK/requests.log"; then
        bad "  -> $plat downloads the template again although nothing changed"
    else
        ok "  -> $plat: after that, no template download until a newer version is out"
    fi
done
publish broken
for plat in $(platforms); do
    name="$(script_name "$plat")"
    rm -rf "$WORK/self"; mkdir -p "$WORK/self/installed"; cp "$WORK/oldpkg/$name" "$WORK/self/installed/$name"
    "run_$plat" "$WORK/db" selfinstall "$WORK/self/installed" "$name" "$WORK/self/installed/$name" "$OLDV" > "$WORK/self.out" 2>&1
    if grep -q "rc=2" "$WORK/self.out" && cmp -s "$WORK/self/installed/$name" "$WORK/oldpkg/$name" && [ ! -e "$WORK/self/installed/$name.new" ]; then
        ok "self-update on $plat rejects a download with the wrong checksum"
    else
        bad "self-update on $plat checksum"; cat "$WORK/self.out"
    fi
done

echo "ESO-Hub (v2 API first, v1 as fallback)"
same "ESO-Hub v2 add-on list" ehparse2 "$FIX/esohub_v2.json"
expect "  -> escaped slashes, any key order, an upper-case checksum and two save files" "$WORK/lin" "5|EsoTradingHub|1790604800|https://files.example.com/addons/download/5|5F0C6A1E2B3D4C5E6F708192A3B4C5D6E7F8091A2B3C4D5E6F708192A3B4C5D6|https://upload.example.com/upload/5|EsoTradingHub.lua;EsoTradingHubExtra.lua"
expect "  -> an add-on without uploads (transfer null) is download-only" "$WORK/lin" "7|LibEsoHubPrices|1792500000|https://files.example.com/addons/download/7|0000000000000000000000000000000000000000000000000000000000000000||"
expect "  -> version.string is used when version.integer is null, the id field when the file URL has none" "$WORK/lin" "14|StringOnly|3.1|https://files.example.com/addons/get||/upload/14|"
if grep -q "|12|\|No Folder" "$WORK/lin"; then bad "  -> an entry without a folder name was kept"; else ok "  -> entries without a folder name are dropped"; fi
same "ESO-Hub v1 add-on list" ehparse1 "$FIX/esohub_v1.json"
expect "  -> v1 records use the same format" "$WORK/lin" "5|EsoTradingHub|1790604761|https://files.example.com/addons/download/5||/upload/5|EsoTradingHub.lua"
expect "  -> a null sv_file_name leaves the add-on download-only" "$WORK/lin" "7|LibEsoHubPrices|1792421684|https://files.example.com/addons/download/7|||"
for pair in "1790604800|1790604761|yes" "1790604797|1790604799|no" "1792500000|1792500000|no" "|1790604761|no" "1790604761||yes" "3.1|3.0|yes"; do
    IFS='|' read -r va vb vwant <<< "$pair"
    same "ESO-Hub version ${va:-(none)} vs ${vb:-(none)}" ehnewer "$va" "$vb"
    expect "  -> server newer: $vwant" "$WORK/lin" "$vwant"
done
mkdir -p "$WORK/ehman/CrLf" "$WORK/ehman/AddonFile"
printf '## Title: CrLf\r\n## IntVersion: 1790604761\r\n' > "$WORK/ehman/CrLf/CrLf.txt"
printf '## Title: AddonFile\n## IntVersion:   42 trailing\n' > "$WORK/ehman/AddonFile/AddonFile.addon"
same "ESO-Hub installed version, Windows line endings" ehlocal "$WORK/ehman/CrLf" CrLf
expect "  -> IntVersion read from the .txt manifest" "$WORK/lin" "v=1790604761"
same "ESO-Hub installed version, .addon manifest" ehlocal "$WORK/ehman/AddonFile" AddonFile
expect "  -> IntVersion read from the .addon manifest" "$WORK/lin" "v=42"

EHM="$WORK/ehmock"; mkdir -p "$EHM" "$WORK/ehtmp" "$WORK/ehsv"
python3 tests/lib/mock_esohub.py "$EHM" "$WORK/ehport" "$WORK/eh_requests.log" &
EH_MOCK_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$WORK/ehport" ] && break; sleep 0.3; done
EHPORT="$(cat "$WORK/ehport" 2>/dev/null)"
export LTTC_ESOHUB_API="http://127.0.0.1:$EHPORT"
python3 - "$EHM" "$EHPORT" "$FIX/esohub_v2.json" "$FIX/esohub_v1.json" <<'PYEOF'
import hashlib, os, sys, zipfile
mock, port, v2src, v1src = sys.argv[1:5]
os.makedirs(os.path.join(mock, "addons", "download"), exist_ok=True)
def pack(num, folder, ver):
    path = os.path.join(mock, "addons", "download", str(num))
    with zipfile.ZipFile(path, "w") as z:
        z.writestr(folder + "/" + folder + ".txt", "## Title: %s\n## IntVersion: %d\n" % (folder, ver))
        z.writestr(folder + "/" + folder + ".lua", "-- new\n")
    return hashlib.sha256(open(path, "rb").read()).hexdigest()
s5 = pack(5, "EsoTradingHub", 1790604800)
s9 = pack(9, "EsoHubScanner", 1790604797)
base = "http:\\/\\/127.0.0.1:" + port
v2 = open(v2src).read().replace("https:\\/\\/files.example.com", base).replace("https:\\/\\/upload.example.com", base)
v2 = v2.replace("5F0C6A1E2B3D4C5E6F708192A3B4C5D6E7F8091A2B3C4D5E6F708192A3B4C5D6", s5.upper()).replace('"checksum":"abc"', '"checksum":"%s"' % s9)
open(os.path.join(mock, "v2.json"), "w").write(v2)
open(os.path.join(mock, "v1.json"), "w").write(open(v1src).read().replace("https:\\/\\/files.example.com", base))
open(os.path.join(mock, "sha5"), "w").write(s5)
PYEOF
eh_mode() { echo "$1" > "$EHM/mode"; }
eh_mode ok
same "ESO-Hub list from v2" ehfetch "$WORK/ehtmp"
expect "  -> v2 answered" "$WORK/lin" "api=v2 blocked=false fail="
expect "  -> the list file is removed from Temp afterwards" "$WORK/lin" "temp_left=0"
eh_mode v2block
same "ESO-Hub list, v2 behind a Cloudflare check" ehfetch "$WORK/ehtmp"
expect "  -> falls back to the v1 list" "$WORK/lin" "api=v1 blocked=false fail="
eh_mode allblock
same "ESO-Hub list, both APIs behind a Cloudflare check" ehfetch "$WORK/ehtmp"
expect "  -> no list, the step reports failure" "$WORK/lin" "rc=1"
expect "  -> names the reason for each API" "$WORK/lin" "blocked=true fail=v2: HTTP 403 (Cloudflare challenge), v1: HTTP 403 (Cloudflare challenge)"
eh_mode down
same "ESO-Hub list, server error" ehfetch "$WORK/ehtmp"
expect "  -> an error that is not Cloudflare is reported as one" "$WORK/lin" "blocked=false fail=v2: HTTP 500, v1: HTTP 500"
eh_mode ok
for plat in $(platforms); do
    : > "$WORK/eh_requests.log"
    "run_$plat" "$WORK/db" ehfetch "$WORK/ehtmp" stale-token > "$WORK/eh.out" 2>&1
    if grep -q "api=v2" "$WORK/eh.out" && [ "$(grep -c '"auth": "Bearer stale-token"' "$WORK/eh_requests.log")" = 1 ] \
        && [ "$(grep -c '"auth": "", "client": "0.2.23"' "$WORK/eh_requests.log")" = 1 ]; then
        ok "ESO-Hub on $plat asks again without a token ESO-Hub no longer accepts (HTTP 401)"
    else
        bad "ESO-Hub stale token on $plat"; cat "$WORK/eh.out" "$WORK/eh_requests.log"
    fi
    if grep -q '"client": "0.2.23"' "$WORK/eh_requests.log" && grep -q '"ua": "ESO-Hub Client v2"' "$WORK/eh_requests.log"; then
        ok "  -> $plat sends the official client's User-Agent and X-ESO-Hub-Client-Version"
    else
        bad "  -> $plat v2 headers"; cat "$WORK/eh_requests.log"
    fi
done
for mode in ok v2block; do
    eh_mode "$mode"
    want="tok-v2-example"; [ "$mode" = v2block ] && want="tok-v1-example"
    for plat in $(platforms); do
        : > "$WORK/eh_requests.log"
        good="$("run_$plat" "$WORK/db" ehtoken "Example User" 'p@ss"w\rd:x' 2>&1)"
        wrong="$("run_$plat" "$WORK/db" ehtoken "Example User" "not-it" 2>&1)"
        if [ "$good" = "token=$want" ] && [ "$wrong" = "token=" ] && ! grep -q 'p@ss\|not-it' "$WORK/eh_requests.log"; then
            ok "ESO-Hub login on $plat ($mode): token from $( [ "$mode" = ok ] && echo v2 || echo v1), quotes, backslash and colon in the password survive, no password in a URL"
        else
            bad "ESO-Hub login on $plat ($mode)"; echo "$good / $wrong"; cat "$WORK/eh_requests.log"
        fi
    done
done
eh_mode ok
EHSUM="$(cat "$EHM/sha5")"
for plat in $(platforms); do
    a="$("run_$plat" "$WORK/db" ehdownload "$LTTC_ESOHUB_API/addons/download/5" "$WORK/ehtmp/dl.zip" "$EHSUM" 2>&1)"
    b="$("run_$plat" "$WORK/db" ehdownload "$LTTC_ESOHUB_API/addons/download/5" "$WORK/ehtmp/dl.zip" "0123abcd" 2>&1)"
    c="$("run_$plat" "$WORK/db" ehdownload "$LTTC_ESOHUB_API/addons/download/77" "$WORK/ehtmp/dl.zip" "" 2>&1)"
    if [ "$a" = "rc=0 file=yes" ] && [ "$b" = "rc=2 file=no" ] && [ "$c" = "rc=1 file=no" ]; then
        ok "ESO-Hub download on $plat: SHA-256 checked, a wrong checksum is refused and deleted, a missing file fails"
    else
        bad "ESO-Hub download on $plat"; echo "$a / $b / $c"
    fi
    rm -f "$WORK/ehtmp/dl.zip"
done
echo 'EsoTradingHubVars = {}' > "$WORK/ehsv/EsoTradingHub.lua"
echo 'EsoHubScannerVars = {"|H1:item:12345:1|h|h"}' > "$WORK/ehsv/EsoHubScanner.lua"
for plat in $(platforms); do
    eh_mode ok; : > "$WORK/eh_requests.log"
    out="$("run_$plat" "$WORK/db" ehupload v2 "$LTTC_ESOHUB_API/upload/5" "EsoTradingHub.lua" "EsoTradingHub.lua;EsoHubScanner.lua;Missing.lua" "$WORK/ehsv" "$WORK/ehtmp" tok-1 2>&1 | tr '\n' ' ')"
    if [ "$out" = "rc=0 temp_left=0 " ] && grep -qF '"entries": ["EsoHubScanner.lua", "EsoTradingHub.lua"]' "$WORK/eh_requests.log" \
        && grep -qF '"name": "server", "type": "text/plain", "value": "live"' "$WORK/eh_requests.log" && grep -qF '"auth": "Bearer tok-1"' "$WORK/eh_requests.log"; then
        ok "ESO-Hub upload on $plat: one zip named archive with every listed save file that exists, server=live, Bearer token"
    else
        bad "ESO-Hub v2 upload on $plat"; echo "$out"; cat "$WORK/eh_requests.log"
    fi
    eh_mode v2upfail; : > "$WORK/eh_requests.log"
    out="$("run_$plat" "$WORK/db" ehupload v2 /upload/5 "EsoTradingHub.lua" "EsoTradingHub.lua" "$WORK/ehsv" "$WORK/ehtmp" tok-1 2>&1 | tr '\n' ' ')"
    if [ "$out" = "rc=0 temp_left=0 " ] && grep -qF '"name": "file"' "$WORK/eh_requests.log" && grep -qF '"query": "user_token=tok-1"' "$WORK/eh_requests.log"; then
        ok "  -> $plat falls back to the v1 upload (one file, user_token) when the zip upload is refused"
    else
        bad "  -> $plat upload fallback"; echo "$out"; cat "$WORK/eh_requests.log"
    fi
done
eh_cycle() {
    local label="$1" mode="$2" token="$3" lastdl="$4" good=true
    for plat in $(platforms); do
        rm -rf "$WORK/ehcyc"; mkdir -p "$WORK/ehcyc/AddOns/EsoTradingHub" "$WORK/ehcyc/AddOns/LibEsoHubPrices" "$WORK/ehcyc/AddOns/EsoHubScanner" "$WORK/ehcyc/SavedVariables"
        printf '## Title: EsoTradingHub\r\n## IntVersion: 1790604761\r\n' > "$WORK/ehcyc/AddOns/EsoTradingHub/EsoTradingHub.txt"
        printf '## IntVersion: 1792500000\n' > "$WORK/ehcyc/AddOns/LibEsoHubPrices/LibEsoHubPrices.txt"
        printf '## IntVersion: 1790604799\n' > "$WORK/ehcyc/AddOns/EsoHubScanner/EsoHubScanner.addon"
        cp "$WORK/ehsv/EsoTradingHub.lua" "$WORK/ehsv/EsoHubScanner.lua" "$WORK/ehcyc/SavedVariables/"
        eh_mode "$mode"; : > "$WORK/eh_requests.log"
        "run_$plat" "$WORK/db" ehcycle "$WORK/ehcyc" "$token" "$lastdl" > "$WORK/ehc.$plat" 2>&1
        cp "$WORK/eh_requests.log" "$WORK/ehc_req.$plat"
        if [ "$plat" != linux ] && ! cmp -s "$WORK/ehc.linux" "$WORK/ehc.$plat"; then
            good=false; bad "$label ($plat differs from Linux)"; diff <(cat -v "$WORK/ehc.linux") <(cat -v "$WORK/ehc.$plat") | head -n 10
        fi
    done
    [ "$good" = true ] && ok "$label ($(wc -l < "$WORK/ehc.linux" | tr -d ' ') lines)"
}
eh_cycle "ESO-Hub hourly step through v2" ok tok-1 0
expect "  -> the older EsoTradingHub is updated from the checked zip" "$WORK/ehc.linux" "EsoTradingHub=1790604800"
expect "  -> a local EsoHubScanner newer than ESO-Hub is not downgraded" "$WORK/ehc.linux" "EsoHubScanner=1790604799"
expect "  -> both changed save files are uploaded" "$WORK/ehc.linux" "notif=Updated (1), Uploaded (2)"
expect "  -> snapshots are written after the uploads" "$WORK/ehc.linux" "snapshots: lttc_eh_esohubscanner_snapshot.lua lttc_eh_esotradinghub_snapshot.lua "
expect "  -> an add-on that is not installed is skipped" "$WORK/ehc.linux" "StringOnly missing."
expect "  -> the zip holds only the save files that exist" "$WORK/ehc_req.linux" '"entries": ["EsoTradingHub.lua"]'
eh_cycle "ESO-Hub hourly step through the v1 fallback" v2block "" 0
expect "  -> v1 uploads one file per request" "$WORK/ehc_req.linux" '"name": "file"'
expect "  -> nothing is downgraded to the older v1 versions" "$WORK/ehc.linux" "loc=1790604761 1792500000 1790604799"
eh_cycle "ESO-Hub hourly step while Cloudflare blocks both APIs" allblock "" 0
expect "  -> skipped with the reason, not a download error" "$WORK/ehc.linux" "notif=Skipped (ESO-Hub server check)"
expect "  -> the reason is shown" "$WORK/ehc.linux" "(v2: HTTP 403 (Cloudflare challenge), v1: HTTP 403 (Cloudflare challenge))"
eh_cycle "ESO-Hub hourly step inside the download cooldown" ok "" 1759299400
expect "  -> the update waits for the cooldown" "$WORK/ehc.linux" "download is on cooldown for 50 more minutes"

CF_OK="cfok.TEST-fixture_0123456789abcdef"
CF_BROWSER="Mozilla/5.0 (X11; Linux x86_64) TestBrowser/1.0"
same "ESO-Hub browser check, pasted values are cleaned the same way" ehcfclean \
    "  cf_clearance=$CF_OK; __cf_bm=other  " "Cookie: cf_clearance=$CF_OK" "short" 'abc"def$ghi`jkl0123456789' \
    "\"$CF_BROWSER\"" "  Mozilla/5.0 (Windows NT 10.0; Win64; x64) Example/2.0  " "Opera/9.80" 'Mozilla/5.0 $(id)'
expect "  -> cf_clearance= and the other cookies are cut away" "$WORK/lin" "cookie [  cf_clearance=$CF_OK; __cf_bm=other  ] -> [$CF_OK]"
expect "  -> a pasted Cookie: header works too" "$WORK/lin" "cookie [Cookie: cf_clearance=$CF_OK] -> [$CF_OK]"
expect "  -> a short value is refused" "$WORK/lin" "cookie [short] -> invalid"
expect "  -> quotes, dollar signs and backticks are refused" "$WORK/lin" 'cookie [abc"def$ghi`jkl0123456789] -> invalid'
expect "  -> quotes around the User-Agent are removed" "$WORK/lin" "ua [\"$CF_BROWSER\"] -> [$CF_BROWSER]"
expect "  -> spaces around the User-Agent are removed" "$WORK/lin" "-> [Mozilla/5.0 (Windows NT 10.0; Win64; x64) Example/2.0]"
expect "  -> a User-Agent that isn't a browser's is refused" "$WORK/lin" "ua [Opera/9.80] -> invalid"
expect "  -> a User-Agent with shell characters is refused" "$WORK/lin" 'ua [Mozilla/5.0 $(id)] -> invalid'

CKDIR="$WORK/cookies"; mkdir -p "$CKDIR"
CK_KEY=$(PW=peanuts python3 -I -c 'import os,hashlib;print(hashlib.pbkdf2_hmac("sha1",os.environ["PW"].encode(),b"saltysalt",1,16).hex())' 2>/dev/null || true)
if [ -n "$CK_KEY" ] && command -v sqlite3 >/dev/null 2>&1 && command -v xxd >/dev/null 2>&1 && command -v openssl >/dev/null 2>&1; then
    CK_PT="$(printf '%064d' 0)$(printf '%s' "$CF_OK" | xxd -p | tr -d '\n')"
    CK_CT=$(printf '%s' "$CK_PT" | xxd -r -p | openssl enc -aes-128-cbc -K "$CK_KEY" -iv 20202020202020202020202020202020 | xxd -p | tr -d '\n')
    CK_BLOB="763130$CK_CT"
    CKDB="$CKDIR/Cookies"
    sqlite3 "$CKDB" "CREATE TABLE cookies(host_key TEXT,name TEXT,encrypted_value BLOB); INSERT INTO cookies VALUES('.eso-hub.com','cf_clearance',x'$CK_BLOB'); INSERT INTO cookies VALUES('.other.com','cf_clearance',x'763130dead');"
    FFDB="$CKDIR/cookies.sqlite"
    sqlite3 "$FFDB" "CREATE TABLE moz_cookies(name TEXT,value TEXT,host TEXT,expiry INTEGER); INSERT INTO moz_cookies VALUES('cf_clearance','$CF_OK','.eso-hub.com',9999999999);"
    printf '131.0.6778.86' > "$CKDIR/Last Version"
    same "ESO-Hub cookie import, a Chromium cookie value is decrypted" cookie decrypt "$CK_BLOB" peanuts
    expect "  -> the real cf_clearance comes back" "$WORK/lin" "$CF_OK"
    same "ESO-Hub cookie import, only ESO-Hub's cookie is read from the browser database" cookie chromium "$CKDB" peanuts brave
    expect "  -> cf_clearance for eso-hub.com is returned" "$WORK/lin" "$CF_OK"
    same "ESO-Hub cookie import, Firefox keeps the value in the clear" cookie firefox "$FFDB"
    expect "  -> the Firefox value is read without decryption" "$WORK/lin" "$CF_OK"
    same "ESO-Hub cookie import, the User-Agent is rebuilt from the browser version" cookie uaguess "$CKDIR"
    expect "  -> a frozen Chrome User-Agent is produced" "$WORK/lin" "Chrome/131.0.0.0"
else
    ok "ESO-Hub cookie import tests skipped (sqlite3, python3, openssl or xxd missing)"
fi

eh_mode cfgate
same "ESO-Hub list behind a browser check, no cf_clearance saved" ehfetch "$WORK/ehtmp"
expect "  -> reported as the Cloudflare check" "$WORK/lin" "rc=1"
expect "  -> both APIs name it" "$WORK/lin" "blocked=true fail=v2: HTTP 403 (Cloudflare challenge), v1: HTTP 403 (Cloudflare challenge)"
export EH_CF_COOKIE="$CF_OK" EH_CF_UA="$CF_BROWSER"
same "ESO-Hub list behind a browser check, cf_clearance saved" ehfetch "$WORK/ehtmp"
expect "  -> v2 answers" "$WORK/lin" "api=v2 blocked=false fail="
for plat in $(platforms); do
    eh_mode cfgate; : > "$WORK/eh_requests.log"
    "run_$plat" "$WORK/db" ehfetch "$WORK/ehtmp" > "$WORK/eh.out" 2>&1
    if grep -q "api=v2" "$WORK/eh.out" && grep -qF "\"cookie\": \"$CF_OK\"" "$WORK/eh_requests.log" \
        && grep -qF "\"ua\": \"$CF_BROWSER\"" "$WORK/eh_requests.log" && ! grep -q '"ua": "ESO' "$WORK/eh_requests.log"; then
        ok "  -> $plat sends cf_clearance with the browser's User-Agent"
    else
        bad "  -> $plat browser check headers"; cat "$WORK/eh.out" "$WORK/eh_requests.log"
    fi
    eh_mode ok; : > "$WORK/eh_requests.log"
    a="$("run_$plat" "$WORK/db" ehdownload "$LTTC_ESOHUB_API/addons/download/5" "$WORK/ehtmp/dl.zip" "$EHSUM" 2>&1)"; rm -f "$WORK/ehtmp/dl.zip"
    b="$("run_$plat" "$WORK/db" ehdownload "http://localhost:$EHPORT/addons/download/5" "$WORK/ehtmp/dl.zip" "$EHSUM" 2>&1)"; rm -f "$WORK/ehtmp/dl.zip"
    if [ "$a" = "rc=0 file=yes" ] && [ "$b" = "rc=0 file=yes" ] && [ "$(grep -cF "\"cookie\": \"$CF_OK\"" "$WORK/eh_requests.log")" = 1 ] \
        && [ "$(grep -c '"cookie": ""' "$WORK/eh_requests.log")" = 1 ]; then
        ok "  -> $plat sends cf_clearance only to ESO-Hub, never to another host"
    else
        bad "  -> $plat cf_clearance scope"; echo "$a / $b"; cat "$WORK/eh_requests.log"
    fi
done
unset EH_CF_COOKIE EH_CF_UA

eh_mode cfgate
same "ESO-Hub login behind a browser check, no cf_clearance saved" ehlogin "Example User" 'p@ss"w\rd:x'
expect "  -> the login says Cloudflare stopped it" "$WORK/lin" "token= blocked=true fail=ESO-Hub's server answered with a Cloudflare check"
export EH_CF_COOKIE="$CF_OK" EH_CF_UA="$CF_BROWSER"
same "ESO-Hub login behind a browser check, cf_clearance saved" ehlogin "Example User" 'p@ss"w\rd:x'
expect "  -> the login goes through" "$WORK/lin" "token=tok-v2-example blocked=false fail="
unset EH_CF_COOKIE EH_CF_UA
eh_mode ok
same "ESO-Hub login with a wrong password" ehlogin "Example User" "not-it"
expect "  -> ESO-Hub's own message is shown" "$WORK/lin" "token= blocked=false fail=ESO-Hub did not accept that username and password (Invalid credentials)"

export EH_CF_ANSWER=cannot
eh_cycle "ESO-Hub hourly step behind a browser check, hidden run" cfgate "" 0
expect "  -> says how to refresh the cookie" "$WORK/ehc.linux" "a running copy picks it up next cycle."
expect "  -> skipped with the reason" "$WORK/ehc.linux" "notif=Skipped (ESO-Hub server check)"
expect "  -> nothing saved" "$WORK/ehc.linux" "cf_saved=no asked=true"
export EH_CF_ANSWER="cf_clearance=$CF_OK|$CF_BROWSER"
eh_cycle "ESO-Hub hourly step behind a browser check, cf_clearance pasted" cfgate tok-1 0
expect "  -> shows the human-verification header" "$WORK/ehc.linux" "[-] ESO-Hub Human Verification Required:"
expect "  -> shows the steps" "$WORK/ehc.linux" "Copy the value of"
expect "  -> no browser reached the updater's page, so the User-Agent is asked" "$WORK/ehc.linux" "didn't reach the updater's page within 2 seconds, so ESO-Hub opens directly. Step 4 asks you to paste the User-Agent."
expect "  -> the step goes on with the pasted check" "$WORK/ehc.linux" "notif=Updated (1), Uploaded (2)"
expect "  -> saved, and re-armed for the next real expiry" "$WORK/ehc.linux" "cf_saved=yes asked=false"
for plat in $(platforms); do
    if [ "$(grep -c '"cookie": ""' "$WORK/ehc_req.$plat")" = 2 ] && [ "$(grep -cF "\"cookie\": \"$CF_OK\"" "$WORK/ehc_req.$plat")" -ge 4 ]; then
        ok "  -> on $plat every request after the paste carries it"
    else
        bad "  -> $plat requests after the paste"; cat "$WORK/ehc_req.$plat"
    fi
done
export EH_CF_ANSWER=timeout
eh_cycle "ESO-Hub hourly step behind a browser check, no answer" cfgate "" 0
expect "  -> no answer skips ESO-Hub" "$WORK/ehc.linux" "No answer, so ESO-Hub is skipped this time."
expect "  -> asked once per start" "$WORK/ehc.linux" "cf_saved=no asked=true"
export EH_CF_ANSWER="not a cookie|x"
eh_cycle "ESO-Hub hourly step behind a browser check, wrong value pasted" cfgate "" 0
expect "  -> a wrong value is refused" "$WORK/ehc.linux" "That isn't a cf_clearance value."
export EH_CF_ANSWER=cannot EH_CF_COOKIE="expired.TEST-fixture_0123456789" EH_CF_UA="$CF_BROWSER"
eh_cycle "ESO-Hub hourly step with an expired browser check" cfgate "" 0
expect "  -> a hidden run says how to refresh" "$WORK/ehc.linux" "a running copy picks it up next cycle."
unset EH_CF_ANSWER EH_CF_COOKIE EH_CF_UA
eh_mode ok

EHB="$WORK/ehb"; mkdir -p "$WORK/ncbin"
printf '#!/bin/sh\nexec python3 -I "%s" "$@"\n' "$PWD/tests/lib/fake_nc.py" > "$WORK/ncbin/nc"; chmod +x "$WORK/ncbin/nc"
eh_browser() {
    local label="$1" mode="$2" check="$3" good=true; shift 3
    for plat in $(platforms); do
        eh_mode "$mode"; : > "$WORK/eh_requests.log"; : > "$EHM/approved"; : > "$EHB.log.$plat"
        EH_BROWSER_LOG="$EHB.log.$plat" "run_$plat" "$WORK/db" "$@" > "$EHB.$plat" 2>&1
        cp "$WORK/eh_requests.log" "$EHB.req.$plat"
        [ "$check" = same ] && [ "$plat" != linux ] || continue
        if ! cmp -s "$EHB.linux" "$EHB.$plat" || ! cmp -s "$EHB.log.linux" "$EHB.log.$plat"; then
            good=false; bad "$label ($plat differs from Linux)"
            diff <(cat -v "$EHB.linux" "$EHB.log.linux") <(cat -v "$EHB.$plat" "$EHB.log.$plat") | head -n 10
        fi
    done
    [ "$good" = true ] && ok "$label ($(wc -l < "$EHB.linux" | tr -d ' ') lines)"
}
not_in() {
    local name="$1" file="$2" unwanted="$3"
    if grep -qF -- "$unwanted" "$file"; then bad "$name (found: $unwanted)"; head -n 12 "$file"; else ok "$name"; fi
}
listeners_gone() {
    if pgrep -f -- 'out, limit|\$out, \$limit|fake_nc\.py' > /dev/null 2>&1; then bad "  -> a listener is still running"; pgrep -af -- 'out, limit|\$out, \$limit|fake_nc\.py'; else ok "  -> no listener is left running"; fi
}
export EH_BROWSER_UA="$CF_BROWSER"
for tool in python3 perl; do
    EH_LISTEN=$tool EH_BROWSER=stray eh_browser "ESO-Hub reads the browser User-Agent through $tool" ok same ehuaprobe
    expect "  -> the User-Agent is read" "$EHB.linux" "seen=[$CF_BROWSER] left=[]"
    expect "  -> another page on that port gets a 404 and the wait goes on" "$EHB.log.linux" "stray 404"
    expect "  -> the browser is sent on to ESO-Hub" "$EHB.log.linux" "visit 302 https://eso-hub.com/en"
    listeners_gone
done
for style in openbsd traditional; do
    PATH="$WORK/ncbin:$PATH" NC_STYLE=$style EH_LISTEN=nc EH_BROWSER=visit eh_browser "ESO-Hub reads the browser User-Agent through nc ($style options)" ok same ehuaprobe
    expect "  -> the User-Agent is read" "$EHB.linux" "seen=[$CF_BROWSER] left=[]"
    listeners_gone
done
EH_BROWSER=visit EH_BROWSER_UA="curl/8.0" eh_browser "ESO-Hub gets a User-Agent that isn't a browser's" ok same ehuaprobe
expect "  -> refused, the paste step stays" "$EHB.linux" "Your browser sent a User-Agent the updater can't use. Step 4 asks you to paste it."
EH_LISTEN=none EH_BROWSER=visit eh_browser "ESO-Hub without a way to listen on 127.0.0.1" ok each ehuaprobe
for plat in linux macos; do
    expect "  -> $plat names the missing tools" "$EHB.$plat" "The updater can't read your browser's User-Agent by itself: that needs python3, perl or nc (netcat), and none of them is installed. Step 4 asks you to paste it."
    expect "  -> $plat still opens ESO-Hub" "$EHB.log.$plat" "open https://eso-hub.com/en"
done
if [ -n "$PWSH" ]; then
    expect "  -> windows names the TcpListener" "$EHB.windows" "The updater can't read your browser's User-Agent by itself: Windows didn't allow a local TcpListener on 127.0.0.1 (the test blocked it). Step 4 asks you to paste it."
    expect "  -> windows still opens ESO-Hub" "$EHB.log.windows" "open https://eso-hub.com/en"
fi

EH_BROWSER=approve eh_browser "ESO-Hub login through the browser" ok same ehcodelogin
expect "  -> ESO-Hub's login page opens with the code" "$EHB.log.linux" "open https://eso-hub.com/en/client-token-login?code=CODE"
expect "  -> the token and the account name come back" "$EHB.linux" "token=tok-code-example user=Example User fail="
not_in "  -> no browser check is asked when ESO-Hub lets the client in" "$EHB.linux" "cf_clearance"
for plat in $(platforms); do
    if [ -s "$EHB.req.$plat" ] && ! grep -v '"code": "uuid4"' "$EHB.req.$plat" | grep -q . && ! grep -v '"ctype": "application/json"' "$EHB.req.$plat" | grep -q . \
        && ! grep -v '"ua": "ESO-Hub Client v2"' "$EHB.req.$plat" | grep -q .; then
        ok "  -> $plat polls with a UUID v4 as JSON and the client's own headers"
    else
        bad "  -> $plat login polls"; cat "$EHB.req.$plat"
    fi
done
EH_CF_ANSWER="cf_clearance=$CF_OK|not used" EH_BROWSER=approve eh_browser "ESO-Hub login through the browser behind a browser check" cfgate same ehcodelogin
expect "  -> the browser's User-Agent is read, so step 4 is skipped" "$EHB.linux" "[+] Login and Verify."
not_in "  -> only cf_clearance is asked" "$EHB.linux" "navigator.userAgent"
expect "  -> the browser lands on the login page" "$EHB.log.linux" "visit 302 https://eso-hub.com/en/client-token-login?code=CODE"
expect "  -> the login goes through" "$EHB.linux" "token=tok-code-example user=Example User fail="
expect "  -> saved with the browser's User-Agent" "$EHB.linux" "cf_saved=yes ua=$CF_BROWSER changed=true"
EH_LISTEN=none EH_CF_ANSWER="cf_clearance=$CF_OK|$CF_BROWSER" EH_BROWSER=approve eh_browser "ESO-Hub login behind a browser check without a local listener" cfgate each ehcodelogin
for plat in $(platforms); do
    expect "  -> $plat asks for the User-Agent by hand" "$EHB.$plat" "navigator.userAgent"
    expect "  -> $plat logs in with the pasted values" "$EHB.$plat" "token=tok-code-example user=Example User fail="
done
EH_CF_ANSWER="cf_clearance=$CF_OK|$CF_BROWSER" EH_BROWSER=none EH_CODE_SECONDS=3 eh_browser "ESO-Hub login behind a browser check, the browser never opens the updater's page" cfgate same ehcodelogin
expect "  -> says so and opens ESO-Hub directly" "$EHB.linux" "Your browser didn't reach the updater's page within 2 seconds, so ESO-Hub opens directly."
expect "  -> the login page still opens" "$EHB.log.linux" "open https://eso-hub.com/en/client-token-login?code=CODE"
expect "  -> asks for the User-Agent by hand" "$EHB.linux" "navigator.userAgent"
expect "  -> stops at the time limit with ESO-Hub's last answer" "$EHB.linux" "fail=ESO-Hub didn't confirm the login within 3 seconds (last answer: HTTP 404, Code not found)"
EH_CF_ANSWER="|$CF_BROWSER" EH_BROWSER=approve eh_browser "ESO-Hub login behind a browser check, cf_clearance skipped" cfgate same ehcodelogin
expect "  -> the prompt explains what cf_clearance is for" "$EHB.linux" "cf_clearance is ESO-Hub's proof that a human, not a bot, passed this check."
expect "  -> the reason names the Login Token" "$EHB.linux" "fail=the updater can't pick up the Login Token without cf_clearance, because ESO-Hub's data server answers with a Cloudflare check"
EH_CF_ANSWER="cf_clearance=$CF_OK|$CF_BROWSER" EH_BROWSER=approve EH_BROWSER_UA="Mozilla/5.0 (X11; Linux x86_64) OtherBrowser/2.0" eh_browser "ESO-Hub login with cf_clearance from another browser" cfgate same ehcodelogin
expect "  -> says to copy it from the browser that opened" "$EHB.linux" "fail=ESO-Hub's server still answers with a Cloudflare check; copy cf_clearance from the browser that opened, on this PC and network"
EH_BROWSER=none EH_CODE_ENTER=1 eh_browser "ESO-Hub login through the browser, Enter pressed" ok same ehcodelogin
expect "  -> stops waiting" "$EHB.linux" "token= user= fail=you stopped waiting"
LTTC_ESOHUB_API="http://127.0.0.1:9" EH_BROWSER=none eh_browser "ESO-Hub login through the browser without a connection" ok same ehcodelogin
expect "  -> no browser opens and the reason is shown" "$EHB.linux" "token= user= fail=no connection to ESO-Hub"
not_in "  -> nothing was opened" "$EHB.log.linux" "open"
export EH_CF_ANSWER="cf_clearance=$CF_OK|not used" EH_BROWSER=visit
eh_cycle "ESO-Hub hourly step behind a browser check, User-Agent read from the browser" cfgate tok-1 0
expect "  -> the User-Agent is read" "$WORK/ehc.linux" "[+] Login and Verify."
expect "  -> the step goes on" "$WORK/ehc.linux" "notif=Updated (1), Uploaded (2)"
unset EH_CF_ANSWER EH_BROWSER EH_BROWSER_UA
eh_mode ok

same "trade history merge summary: new, updated, and size before/after" mergereport "$FIX/LTTC_History.db" "$FIX/incoming_history.txt"
expect "  -> it reports new and updated counts with the size change" "$WORK/lin" "39 updated (9.8 KB -> 9.6 KB)."

printf 'ESOHUB_CF_CLEARANCE="fresh.TEST-fixture_abcdef123456"\nESOHUB_CF_UA="Mozilla/5.0 (X11) Fresh/3.0"\n' > "$WORK/eh_reload.conf"
same "ESO-Hub re-reads a refreshed cf_clearance from the config each cycle" ehreload "stale.cookie.value.0000" "Mozilla/5.0 Old/1.0" "$WORK/eh_reload.conf"
expect "  -> a cookie refreshed out-of-band replaces the stale one in memory" "$WORK/lin" "cookie=fresh.TEST-fixture_abcdef123456 ua=Mozilla/5.0 (X11) Fresh/3.0"
same "ESO-Hub keeps the current cf_clearance when no config file is there" ehreload "keep.this.cookie.0000" "Mozilla/5.0 Keep/1.0" "$WORK/no_such.conf"
expect "  -> the in-memory cookie is unchanged" "$WORK/lin" "cookie=keep.this.cookie.0000 ua=Mozilla/5.0 Keep/1.0"

echo "Secret scrambling (machine-bound, DPAPI on Windows)"
for plat in $(platforms); do
    "run_$plat" "$WORK/db" secret "tok-secret-123" "cfok.cookie_value_0123456789" "@My Account" "Mozilla/5.0 (X11; Linux) Brave/1.0" > "$WORK/sec.$plat" 2>&1
    if grep -q "roundtrip FAIL" "$WORK/sec.$plat"; then bad "secrets round-trip on $plat"; head -5 "$WORK/sec.$plat"; else ok "secrets round-trip on $plat (encrypt then decrypt restores the value)"; fi
done
expect "  -> on Linux the value is scrambled, not stored as plain text" "$WORK/sec.linux" "roundtrip ok enc=ENC1 [tok-secret-123]"

echo "Version diff coloring (pacman-style old red, new green)"
same "version diff: only the changed part is colored, identical on every platform" vdiff \
    "22700,22800" "80309,80310" "1790604761,1792680868" "2.1.1792349434+dd3b243-1.1,2.1.1792588164+a4c0645-1.1"
expect "  -> the common prefix and suffix stay uncolored" "$WORK/lin" "<ESC>[0m22<ESC>[31m7<ESC>[0m00"
expect "  -> the old digits are red" "$WORK/lin" "<ESC>[31m09<ESC>[0m"
expect "  -> the new digits are green" "$WORK/lin" "<ESC>[92m10<ESC>[0m"
expect "  -> a long id keeps the shared head and tail plain" "$WORK/lin" "2.1.1792<ESC>[31m349434+dd3b243<ESC>[0m-1.1"
expect "  -> and colors only the changed middle green" "$WORK/lin" "2.1.1792<ESC>[92m588164+a4c0645<ESC>[0m-1.1"

echo "TTC price tables (checked at most every 45 minutes)"
mkdir -p "$WORK/ttcpt"
printf -- '--Version = 3751\r\nfunction TamrielTradeCentrePrice:LoadPriceTableNA()\r\n' > "$WORK/ttcpt/crlf.lua"
printf -- '--version=12\n' > "$WORK/ttcpt/tight.lua"
printf -- 'function TamrielTradeCentrePrice:LoadPriceTableNA()\n--Version = 99\n' > "$WORK/ttcpt/late.lua"
same "TTC price table version, Windows line endings" ttcver "$WORK/ttcpt/crlf.lua"
expect "  -> read from the --Version line" "$WORK/lin" "v=3751"
same "TTC price table version, no spaces" ttcver "$WORK/ttcpt/tight.lua"
expect "  -> case and spacing do not matter" "$WORK/lin" "v=12"
same "TTC price table version, missing file" ttcver "$WORK/ttcpt/none.lua"
expect "  -> a missing file counts as version 0" "$WORK/lin" "v=0"
mkdir -p "$WORK/ttcbin"
cat > "$WORK/ttcbin/curl" <<'CURLEOF'
#!/bin/sh
printf '%s\n' "$*" >> "$TTC_CURL_LOG"
case "$*" in
    *GetTradeClientVersion*) printf '{"ClientVersion":"4.27.9595.38660","PriceTableVersion":%s,"Message":null}' "$TTC_MOCK_VER" ;;
    *) exit 7 ;;
esac
CURLEOF
chmod +x "$WORK/ttcbin/curl"
export TTC_CURL_LOG="$WORK/ttc_curl.log"
ttc_cycle() {
    local label="$1" lastcheck="$2" srv="$3" localmode="$4" mockver="$5" good=true
    for plat in $(platforms); do
        rm -rf "$WORK/ttccyc"; mkdir -p "$WORK/ttccyc/AddOns/TamrielTradeCentre"
        printf -- '--Version = 3751\r\nfunction TamrielTradeCentrePrice:LoadPriceTableNA()\r\n' > "$WORK/ttccyc/AddOns/TamrielTradeCentre/PriceTableNA.lua"
        printf -- '--Version = 3750\r\nfunction TamrielTradeCentrePrice:LoadPriceTableEU()\r\n' > "$WORK/ttccyc/AddOns/TamrielTradeCentre/PriceTableEU.lua"
        : > "$TTC_CURL_LOG"
        PATH="$WORK/ttcbin:$PATH" TTC_MOCK_VER="$mockver" "run_$plat" "$WORK/db" ttccycle "$WORK/ttccyc" "$lastcheck" "$srv" "$localmode" > "$WORK/ttcc.$plat" 2>&1
        echo "api_calls=$(grep -c GetTradeClientVersion "$TTC_CURL_LOG")" >> "$WORK/ttcc.$plat"
        if [ "$plat" != linux ] && ! cmp -s "$WORK/ttcc.linux" "$WORK/ttcc.$plat"; then
            good=false; bad "$label ($plat differs from Linux)"; diff <(cat -v "$WORK/ttcc.linux") <(cat -v "$WORK/ttcc.$plat") | head -n 10
        fi
    done
    [ "$good" = true ] && ok "$label ($(wc -l < "$WORK/ttcc.linux" | tr -d ' ') lines)"
}
ttc_cycle "TTC check 10 minutes after the last one" 1759299400 1 false 3751
expect "  -> TTC is not asked again" "$WORK/ttcc.linux" "api_calls=0"
expect "  -> the wait is shown" "$WORK/ttcc.linux" "checked 10 min ago and change about once a day."
expect "  -> next check in 35 minutes" "$WORK/ttcc.linux" "Next check in 35 min."
expect "  -> the last check time is kept" "$WORK/ttcc.linux" "notif=Up-to-date last_check=1759299400 changed=false"
ttc_cycle "TTC check 45 minutes after the last one, same version" 1759297300 1 false 3751
expect "  -> TTC is asked once" "$WORK/ttcc.linux" "api_calls=1"
expect "  -> the step says Checking TTC Server" "$WORK/ttcc.linux" "Checking TTC Server..."
expect "  -> the local version comes from PriceTableNA.lua" "$WORK/ttcc.linux" "Local Version (NA):  "$'\e[92m'"3751"
expect "  -> nothing to download" "$WORK/ttcc.linux" "Local PriceTable is up-to-date."
expect "  -> the check time is saved" "$WORK/ttcc.linux" "last_check=1759300000 changed=true"
ttc_cycle "TTC check for both servers, NA has a newer table" 0 3 true 3752
expect "  -> both servers are asked" "$WORK/ttcc.linux" "api_calls=2"
expect "  -> the newer table is found" "$WORK/ttcc.linux" "New TTC Price Table available"
expect "  -> local mode skips the download" "$WORK/ttcc.linux" "[Local Mode] Download Skipped."
ttc_cycle "TTC check with a clock that went backwards" 1759400000 2 false 3750
expect "  -> a check time in the future does not block checks" "$WORK/ttcc.linux" "api_calls=1"
unset TTC_CURL_LOG

echo "APH-OnManager data from GitHub (an hour after each data refresh)"
AOM_MAC_PATH="$MAC_PATH"
mac_awk="$(PATH="$MAC_PATH:$PATH" command -v awk)"
if [ "$(uname)" = Linux ] && [ -n "$mac_awk" ] && [ "$mac_awk" != "$(command -v awk)" ]; then
    mkdir -p "$WORK/macawk"
    printf '#!/bin/sh\n[ "$LC_ALL" = C ] && LC_ALL=C.UTF-8 && export LC_ALL\nexec "%s" "$@"\n' "$mac_awk" > "$WORK/macawk/awk"
    chmod +x "$WORK/macawk/awk"
    AOM_MAC_PATH="$WORK/macawk:$MAC_PATH"
fi
same_slots() {
    local good=true
    run_linux "$WORK/db" aomslots "$@" > "$WORK/lin" 2> "$WORK/lin.err"
    MAC_PATH="$AOM_MAC_PATH" run_macos "$WORK/db" aomslots "$@" > "$WORK/mac" 2> "$WORK/mac.err"
    compare "APH-OnManager check times" mac macOS || good=false
    if [ -n "$PWSH" ]; then run_windows "$WORK/db" aomslots "$@" > "$WORK/win" 2> "$WORK/win.err"; compare "APH-OnManager check times" win Windows || good=false; fi
    [ "$good" = true ] && ok "APH-OnManager check times ($(wc -l < "$WORK/lin" | tr -d ' ') lines)"
}
same_slots 1761004800 1761008759 1761008760 1761026040 1761078480 1761090000
expect "  -> before the first check of the day, the last one was yesterday at 20:18 UTC" "$WORK/lin" "1761004800 -> 1760991480 1761008760 wait=1 h 6 min"
expect "  -> the first check is at 01:06 UTC, an hour after the 00:06 refresh" "$WORK/lin" "1761008760 -> 1761008760 1761026040 wait=4 h 48 min"
expect "  -> the checks stay 4 h 48 min apart" "$WORK/lin" "1761026040 -> 1761026040 1761043320"
expect "  -> after 20:18 UTC the next check waits for the next day" "$WORK/lin" "1761090000 -> 1761077880 1761095160 wait=1 h 26 min"

AOM_HEAD=$'--[[\n    Copyright \xc2\xa9 2026 @APHONlC. All rights reserved.\n]]\n\nlocal AoM = APHOnManagerCore\n'
aom_table() { printf '%sAoM.%s = AoM.CreateKnownTable([==[\n%s]==])\n' "$AOM_HEAD" "$1" "$2"; }
aom_dict() { printf '%sAoM.%s = {\n%s}\n' "$AOM_HEAD" "$1" "$2"; }
GHM="$WORK/ghmock"; mkdir -p "$GHM/data"
aom_table KnownAddonVersions $'Alpha\t5\t1.5\t100\t101050\nbeta\t3\t1.3\t101\t101050\nBeta\t2\t1.2\t102\t101050\nGamma\t1\t1.0\t103\t101050\n' > "$GHM/data/KnownAddonVersions.lua"
aom_dict SuggestedCategories $'\t["Alpha"] = "Utility Mods",\n\t["Delta"] = "Combat Mods",\n' > "$GHM/data/SuggestedCategories.lua"
aom_table KnownLibraries $'LibOne\t3\t3.0\t200\t101050\tLibOne\tLibOne\n' > "$GHM/data/KnownLibraries.lua"
aom_table KnownConsoleAddons "$(for i in 01 02 03 04 05 06 07 08 09 10; do printf 'Console%s\t\tVersion 1.%s\t101050 101051\tConsole %s\tExample\t00000000-0000-0000-0000-0000000000%s\n' "$i" "$i" "$i" "$i"; done)
" > "$GHM/data/KnownConsoleAddons.lua"
for t in KnownAddonDependencies KnownConsoleLibraries KnownConsoleAddonDependencies ConsoleSuggestedCategories; do aom_table "$t" "" > "$GHM/data/$t.lua"; done
python3 tests/lib/mock_github.py "$GHM" "$WORK/ghport" "$WORK/gh_requests.log" &
GH_MOCK_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$WORK/ghport" ] && break; sleep 0.3; done
GHPORT="$(cat "$WORK/ghport" 2>/dev/null)"
export LTTC_AOM_API="http://127.0.0.1:$GHPORT" LTTC_AOM_RAW="http://127.0.0.1:$GHPORT"
gh_mode() { echo "$1" > "$GHM/mode"; }
aom_setup_mixed() {
    local d="$1/AddOns/APH-OnManager/DATA"; mkdir -p "$d"
    { printf '\xef\xbb\xbf'; aom_table KnownAddonVersions $'Alpha\t4\t1.4\t100\t101050\nGamma\t2\t1.1\t103\t101050\nZeta\t1\t1.0\t104\t101050\n' | sed 's/$/\r/'; } > "$d/KnownAddonVersions.lua"
    aom_dict SuggestedCategories $'\t["Alpha"] = "Misc",\n' > "$d/SuggestedCategories.lua"
    cp "$GHM/data/KnownLibraries.lua" "$d/KnownLibraries.lua"
    aom_table KnownConsoleAddons "" > "$d/KnownConsoleAddons.lua"
}
aom_setup_same() { mkdir -p "$1/AddOns/APH-OnManager/DATA"; cp "$GHM/data/"*.lua "$1/AddOns/APH-OnManager/DATA/"; }
aom_setup_linked() { mkdir -p "$1/AddOns" "$1/Source/DATA"; cp "$GHM/data/KnownLibraries.lua" "$1/Source/DATA/"; ln -s "$1/Source" "$1/AddOns/APH-OnManager"; }
aom_cycle() {
    local label="$1" setup="$2" now="$3" last="$4" good=true
    shift 4
    for plat in $(platforms); do
        rm -rf "$WORK/aomcyc"; mkdir -p "$WORK/aomcyc"; "$setup" "$WORK/aomcyc"
        : > "$WORK/gh_requests.log"
        if [ "$plat" = macos ]; then
            MAC_PATH="$AOM_MAC_PATH" run_macos "$WORK/db" aomcycle "$WORK/aomcyc" "$now" "$last" "$@" > "$WORK/aomc.$plat" 2>&1
        else
            "run_$plat" "$WORK/db" aomcycle "$WORK/aomcyc" "$now" "$last" "$@" > "$WORK/aomc.$plat" 2>&1
        fi
        printf 'requests: runs=%s commit=%s data_at_commit=%s data_at_main=%s accept=%s\n' \
            "$(grep -c '/actions/runs"' "$WORK/gh_requests.log")" "$(grep -c '/commits/main"' "$WORK/gh_requests.log")" \
            "$(grep -c '/0123456789abcdef0123456789abcdef01234567/DATA/' "$WORK/gh_requests.log")" \
            "$(grep -c '/main/DATA/' "$WORK/gh_requests.log")" "$(grep -c '"accept": "application/vnd.github+json"' "$WORK/gh_requests.log")" >> "$WORK/aomc.$plat"
        if [ "$plat" != linux ] && ! cmp -s "$WORK/aomc.linux" "$WORK/aomc.$plat"; then
            good=false; bad "$label ($plat differs from Linux)"; diff <(cat -v "$WORK/aomc.linux") <(cat -v "$WORK/aomc.$plat") | head -n 10
        fi
    done
    [ "$good" = true ] && ok "$label ($(wc -l < "$WORK/aomc.linux" | tr -d ' ') lines)"
}
gh_mode ok
aom_cycle "APH-OnManager data checked 17 minutes ago" aom_setup_mixed 1761010000 1761009000
expect "  -> GitHub is not asked again" "$WORK/aomc.linux" "requests: runs=0 commit=0 data_at_commit=0 data_at_main=0 accept=0"
expect "  -> the wait shows when the next check is" "$WORK/aomc.linux" "Checked 17 min ago. Next check in 4 h 28 min, an hour after the next data refresh."
expect "  -> the last check time is kept" "$WORK/aomc.linux" "notif= last_sync=1761009000 changed=false"
aom_cycle "APH-OnManager data after the 01:06 UTC check time" aom_setup_mixed 1761010000 1761008759
expect "  -> the tables come from the latest commit" "$WORK/aomc.linux" "requests: runs=1 commit=1 data_at_commit=8 data_at_main=0 accept=2"
expect "  -> a newer version replaces the old one" "$WORK/aomc.linux" "Alpha: 4 (1.4) -> 5 (1.5)"
expect_text "  -> both case variants of a new name are added, upper case first" "$WORK/aomc.linux" $'Alpha\t5\t1.5\t100\t101050\nBeta\t2\t1.2\t102\t101050\nbeta\t3\t1.3\t101\t101050\nGamma\t2\t1.1\t103\t101050\nZeta\t1\t1.0\t104\t101050\n]==])'
expect "  -> a value without a version is replaced" "$WORK/aomc.linux" 'Alpha: "Misc" -> "Utility Mods"'
expect_text "  -> the line endings and the BOM are cleaned up" "$WORK/aomc.linux" $'== KnownAddonVersions.lua\n--[['
expect "  -> long lists stop after 8 lines" "$WORK/aomc.linux" "... and 2 more (see the log)"
expect "  -> tables you do not have are not added" "$WORK/aomc.linux" "notif=Updated (3) last_sync=1761010000 changed=true temp_left=0"
if grep -q '== KnownConsoleLibraries.lua' "$WORK/aomc.linux"; then bad "  -> a table that is not installed was created"; else ok "  -> only installed tables are written"; fi
aom_cycle "APH-OnManager data that matches GitHub in a different order" aom_setup_same 1761010000 0
expect "  -> nothing is rewritten for order alone" "$WORK/aomc.linux" "No changes detected."
expect_text "  -> the file keeps its order" "$WORK/aomc.linux" $'beta\t3\t1.3\t101\t101050\nBeta\t2\t1.2\t102\t101050\n'
expect "  -> the check time is saved" "$WORK/aomc.linux" "notif=Up-to-date last_sync=1761010000 changed=true temp_left=0"
gh_mode refreshing
aom_cycle "APH-OnManager data while a refresh is running" aom_setup_mixed 1761010000 0
expect "  -> nothing is downloaded" "$WORK/aomc.linux" "requests: runs=1 commit=0 data_at_commit=0 data_at_main=0 accept=1"
expect "  -> the check waits for the next cycle" "$WORK/aomc.linux" "notif=Waiting For Refresh last_sync=0 changed=false temp_left=0"
gh_mode rawfail
aom_cycle "APH-OnManager data when one table cannot be downloaded" aom_setup_mixed 1761010000 0
expect "  -> no table is changed" "$WORK/aomc.linux" "Nothing was changed."
expect "  -> the check is tried again next cycle" "$WORK/aomc.linux" "notif=Download Failed last_sync=0 changed=false temp_left=0"
gh_mode apidown
aom_cycle "APH-OnManager data when the GitHub API is down, clock went backwards" aom_setup_mixed 1761010000 1761100000
expect "  -> the tables come from the main branch" "$WORK/aomc.linux" "requests: runs=1 commit=1 data_at_commit=0 data_at_main=8 accept=2"
expect "  -> the tables are still merged" "$WORK/aomc.linux" "notif=Updated (3) last_sync=1761010000"
gh_mode ok
aom_cycle "APH-OnManager installed as a linked folder" aom_setup_linked 1761010000 0
expect "  -> its data is left alone" "$WORK/aomc.linux" "APH-OnManager is a linked folder, so its data is left as it is."
expect "  -> GitHub is not asked" "$WORK/aomc.linux" "requests: runs=0 commit=0 data_at_commit=0 data_at_main=0 accept=0"
aom_ask() {
    local label="$1" dir="$2" good=true
    run_linux "$WORK/db" aomask "$dir" > "$WORK/lin" 2> "$WORK/lin.err"
    MAC_PATH="$AOM_MAC_PATH" run_macos "$WORK/db" aomask "$dir" > "$WORK/mac" 2> "$WORK/mac.err"
    compare "$label" mac macOS || good=false
    if [ -n "$PWSH" ]; then run_windows "$WORK/db" aomask "$dir" > "$WORK/win" 2> "$WORK/win.err"; compare "$label" win Windows || good=false; fi
    [ "$good" = true ] && ok "$label ($(wc -l < "$WORK/lin" | tr -d ' ') lines)"
}
rm -rf "$WORK/aomask"; mkdir -p "$WORK/aomask/with/APH-OnManager/DATA" "$WORK/aomask/without/LibFoo"
aom_ask "setup question when APH-OnManager is installed" "$WORK/aomask/with"
expect "  -> APH-OnManager is found" "$WORK/lin" "installed=yes"
expect "  -> the question says what it keeps up to date" "$WORK/lin" "(Its lists of add-on versions, libraries, dependencies and categories, checked an hour after each data refresh)"
expect "  -> Enter means Yes" "$WORK/lin" "answer '' -> true"
expect "  -> 2 means No" "$WORK/lin" "answer '2' -> false"
expect "  -> anything else means Yes" "$WORK/lin" "answer 'x' -> true"
aom_ask "setup question when APH-OnManager is not installed" "$WORK/aomask/without"
expect "  -> the question is skipped" "$WORK/lin" "installed=no"
aom_cycle "APH-OnManager data updates turned off" aom_setup_mixed 1761010000 0 false
if grep -q "Updating APH-OnManager" "$WORK/aomc.linux"; then bad "  -> the section is shown"; else ok "  -> the section is left out"; fi
expect "  -> GitHub is not asked and nothing changes" "$WORK/aomc.linux" "requests: runs=0 commit=0 data_at_commit=0 data_at_main=0 accept=0"
expect "  -> the answer is kept" "$WORK/aomc.linux" "aom_data_updates=false asked=false"
aom_cycle "APH-OnManager found by a hidden run before anyone answered" aom_setup_mixed 1761010000 0 unset cannot 2
expect "  -> it says how to answer" "$WORK/aomc.linux" "APH-OnManager was found. Start the updater in a terminal to choose whether to keep its data up to date."
if grep -q "Keep its add-on data up to date?" "$WORK/aomc.linux"; then bad "  -> a hidden run asked the question"; else ok "  -> a hidden run never asks"; fi
expect "  -> nothing is downloaded or saved" "$WORK/aomc.linux" "notif= last_sync=0 changed=false temp_left=0"
expect "  -> GitHub is not asked" "$WORK/aomc.linux" "requests: runs=0 commit=0 data_at_commit=0 data_at_main=0 accept=0"
expect "  -> the answer stays open" "$WORK/aomc.linux" "aom_data_updates= asked=true"
aom_cycle "APH-OnManager found later, the player answers Yes" aom_setup_mixed 1761010000 0 unset 1
expect "  -> the question is shown" "$WORK/aomc.linux" "APH-OnManager is in your AddOns folder. Keep its add-on data up to date?"
expect "  -> the data is updated in the same cycle" "$WORK/aomc.linux" "notif=Updated (3) last_sync=1761010000 changed=true temp_left=0"
expect "  -> the answer is saved" "$WORK/aomc.linux" "aom_data_updates=true asked=true"
aom_cycle "APH-OnManager found later, the player presses Enter" aom_setup_mixed 1761010000 0 unset enter
expect "  -> Enter means Yes" "$WORK/aomc.linux" "aom_data_updates=true asked=true"
aom_cycle "APH-OnManager found later, the player answers No" aom_setup_mixed 1761010000 0 unset 2 2
expect "  -> it says how to change it" "$WORK/aomc.linux" "APH-OnManager's data won't be updated. Run the updater with --setup to change this."
expect "  -> the answer is saved and nothing is downloaded" "$WORK/aomc.linux" "notif= last_sync=0 changed=true temp_left=0"
expect "  -> GitHub is not asked" "$WORK/aomc.linux" "requests: runs=0 commit=0 data_at_commit=0 data_at_main=0 accept=0"
if [ "$(grep -c 'Keep its add-on data up to date?' "$WORK/aomc.linux")" = 1 ]; then ok "  -> it is asked once, the next cycle stays quiet"; else bad "  -> it is asked once, the next cycle stays quiet"; fi
expect "  -> the answer is No" "$WORK/aomc.linux" "aom_data_updates=false asked=true"
aom_cycle "APH-OnManager found later, nobody answers" aom_setup_mixed 1761010000 0 unset timeout 2
expect "  -> the data is left as it is" "$WORK/aomc.linux" "No answer, so APH-OnManager's data is left as it is. The updater asks again the next time it starts."
expect "  -> the next cycle does not ask again" "$WORK/aomc.linux" "APH-OnManager's data is left as it is until you answer. The updater asks again the next time it starts."
if [ "$(grep -c 'Keep its add-on data up to date?' "$WORK/aomc.linux")" = 1 ]; then ok "  -> it waited once"; else bad "  -> it waited once"; fi
expect "  -> nothing is saved" "$WORK/aomc.linux" "notif= last_sync=0 changed=false temp_left=0"
expect "  -> the answer stays open" "$WORK/aomc.linux" "aom_data_updates= asked=true"
aom_cycle "APH-OnManager as a linked folder before anyone answered" aom_setup_linked 1761010000 0 unset 1
if grep -q "Keep its add-on data up to date?" "$WORK/aomc.linux"; then bad "  -> a linked folder asked the question"; else ok "  -> a linked folder is not asked about"; fi
unset LTTC_AOM_API LTTC_AOM_RAW

echo "Steam launch options"
steam_vdf() {
    printf '"UserLocalConfigStore"\n{\n\t"apps"\n\t{\n\t\t"306130"\n\t\t{\n\t\t\t"LastPlayed"\t\t"1"\n\t\t\t"LaunchOptions"\t\t"%s"\n\t\t}\n\t}\n}\n' "$1" > "$WORK/localconfig.vdf"
}
for plat in linux macos; do
    python3 - "src/$plat/features/setup/wizard.sh" "$WORK/inject_$plat.pl" <<'PYEOF2'
import re, sys
m = re.search(r"if perl -pi\.bak -e '(.*?)' \"\$conf\"", open(sys.argv[1], encoding="utf-8").read(), re.S)
open(sys.argv[2], "w", encoding="utf-8").write(m.group(1))
PYEOF2
done
LIN_LAUNCH="env -u LD_PRELOAD -u STEAM_LD_PRELOAD alacritty -e '/home/example/Documents/Linux_Tamriel_Trade_Center/Linux_Tamriel_Trade_Center.sh' --both --loop --steam & %command%"
steam_vdf "WINEDLLOVERRIDES=dxgi.dll=n,b %COMMAND% $LIN_LAUNCH"
LAUNCH_STR="$LIN_LAUNCH" perl -pi -e "$(cat "$WORK/inject_linux.pl")" "$WORK/localconfig.vdf"
LAUNCH_STR="$LIN_LAUNCH" perl -pi -e "$(cat "$WORK/inject_linux.pl")" "$WORK/localconfig.vdf"
expect "Linux: an earlier bad merge is repaired and your own options stay after the updater" "$WORK/localconfig.vdf" "\"LaunchOptions\"		\"env -u LD_PRELOAD -u STEAM_LD_PRELOAD alacritty -e '/home/example/Documents/Linux_Tamriel_Trade_Center/Linux_Tamriel_Trade_Center.sh' --both --loop --steam & WINEDLLOVERRIDES=dxgi.dll=n,b %COMMAND%\""
steam_vdf "-nosplash"
LAUNCH_STR="$LIN_LAUNCH" perl -pi -e "$(cat "$WORK/inject_linux.pl")" "$WORK/localconfig.vdf"
expect "Linux: options without %command% are kept as game arguments" "$WORK/localconfig.vdf" "--steam & %command% -nosplash\""
MAC_LAUNCH="osascript -e 'tell application \"Terminal\" to do script \"\\\"/Users/example/Documents/Unix_Tamriel_Trade_Center/macOS_Tamriel_Trade_Center.sh\\\" --both --loop --steam\"' & %command%"
steam_vdf "mangohud %command%"
LAUNCH_STR="$MAC_LAUNCH" perl -pi -e "$(cat "$WORK/inject_macos.pl")" "$WORK/localconfig.vdf"
LAUNCH_STR="$MAC_LAUNCH" perl -pi -e "$(cat "$WORK/inject_macos.pl")" "$WORK/localconfig.vdf"
if [ "$(grep -o 'osascript' "$WORK/localconfig.vdf" | wc -l | tr -d ' ')" = 1 ] && grep -q "' & mangohud %command%\"" "$WORK/localconfig.vdf"; then
    ok "macOS: running setup twice keeps one launcher before your own options"
else
    bad "macOS launch options"; grep LaunchOptions "$WORK/localconfig.vdf"
fi
if [ -n "$PWSH" ]; then
    cat > "$WORK/launch.ps1" <<'PSEOF'
param($wiz)
$src = Get-Content -Raw $wiz; Invoke-Expression ([regex]::Match($src, "(?s)function Merge-LaunchOptions.*?\n}\n").Value)
$ls = 'cmd /c start \"\" \"C:\\Users\\example\\Documents\\Windows_Tamriel_Trade_Center\\Windows_Tamriel_Trade_Center.bat\" --both --loop --steam & %command%'
$once = Merge-LaunchOptions '-dx11 %COMMAND%' $ls
$twice = Merge-LaunchOptions $once $ls
[Console]::Out.Write("$twice`n")
PSEOF
    "$PWSH" -NoProfile -File "$WORK/launch.ps1" src/windows/features/setup/wizard.ps1 > "$WORK/launch.out" 2>&1
    if [ "$(grep -o 'cmd /c start' "$WORK/launch.out" | wc -l | tr -d ' ')" = 1 ] && grep -q -- '--steam & -dx11 %COMMAND%' "$WORK/launch.out"; then ok "Windows: running setup twice keeps one launcher before your own options"; else bad "Windows launch options"; cat "$WORK/launch.out"; fi
fi

echo
echo "$pass passed, $fail failed$( [ "$skip" -gt 0 ] && echo ", $skip without a Windows comparison")"
[ "$fail" -eq 0 ]
