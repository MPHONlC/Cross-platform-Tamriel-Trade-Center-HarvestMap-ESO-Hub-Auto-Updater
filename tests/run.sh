#!/bin/bash
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
FIX="tests/fixtures"
PWSH="${PWSH:-$(command -v pwsh || true)}"
MAC_BASH="${MAC_BASH:-bash}"
WORK="$(mktemp -d)"
MOCK_PID=""
trap '[ -n "$MOCK_PID" ] && kill "$MOCK_PID" 2>/dev/null; rm -rf "$WORK"' EXIT
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
