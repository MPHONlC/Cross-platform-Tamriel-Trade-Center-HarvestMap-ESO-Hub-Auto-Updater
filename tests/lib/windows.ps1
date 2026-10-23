param([string]$DbFile, [string]$Cmd, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
$ErrorActionPreference = "Stop"
$SRC = Join-Path $PSScriptRoot "../../src/windows"
$ESC = [char]27
$global:SILENT = $true
$DB_FILE = $DbFile
$DB_DIR = Split-Path -Parent $DbFile
$UI_STATE_FILE = [System.IO.Path]::GetTempFileName()
function Log-Event($level, $message) { }
function UIEcho($msg) { }
. "$SRC/lib/files.ps1"
. "$SRC/data/kiosk_locations.ps1"
. "$SRC/data/item_quality.ps1"
. "$SRC/features/database/prune.ps1"
. "$SRC/features/database/browser.ps1"
. "$SRC/features/database/merge.ps1"
. "$SRC/features/esohub/extract.ps1"
. "$SRC/lib/secrets.ps1"
. "$SRC/features/esohub/api.ps1"
. "$SRC/lib/format.ps1"
$global:EH_BROWSERS = @()
function Open-EsoHubUrl($url) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo("bash")
    $psi.ArgumentList.Add((Join-Path $PSScriptRoot "fake_browser.sh")); $psi.ArgumentList.Add("$url")
    $psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi); $p.StandardInput.Close()
    $global:EH_BROWSERS += $p
}
function Wait-EsoHubCodePoll($seconds) { if ($env:EH_CODE_ENTER -eq "1") { return $true }; Start-Sleep -Seconds $seconds; return $false }
if ($env:EH_LISTEN -eq "none") { function New-EsoHubTcpListener { throw "the test blocked it" } }
$ESOHUB_UA_WAIT = if ($env:EH_UA_WAIT) { [int]$env:EH_UA_WAIT } else { 2 }
$ESOHUB_CODE_SECONDS = if ($env:EH_CODE_SECONDS) { [int]$env:EH_CODE_SECONDS } else { 6 }
$ESOHUB_CODE_POLL = if ($env:EH_CODE_POLL) { [int]$env:EH_CODE_POLL } else { 1 }
function Test-EsoHubCfCanAsk { return ($env:EH_CF_ANSWER -and $env:EH_CF_ANSWER -ne "cannot") }
function Read-EsoHubCfAnswer([bool]$secret) {
    if ($env:EH_CF_ANSWER -eq "timeout") { return $null }
    [Console]::Out.Write("`n")
    $p = "$env:EH_CF_ANSWER".Split([char]'|', 2)
    if ($secret -or $p.Count -lt 2) { return $p[0] }
    return $p[1]
}
$global:ESOHUB_CF_CLEARANCE = "$env:EH_CF_COOKIE"; $global:ESOHUB_CF_UA = "$env:EH_CF_UA"
. "$SRC/features/ttc/extract.ps1"
. "$SRC/features/ttc/upload.ps1"
. "$SRC/lib/esoui.ps1"
. "$SRC/features/addons/updater.ps1"
. "$SRC/features/self/update.ps1"

function Out-Lines($lines) { foreach ($l in $lines) { [Console]::Out.Write("$l`n") } }
function Out-Extract($res) {
    Out-Lines ($res.Lines | ForEach-Object { "L $_" })
    Out-Lines ($res.History | ForEach-Object { "H $_" })
    Out-Lines @("M $($res.MaxTime)")
    $d = [string[]]@($res.DbUpdates); [Array]::Sort($d, [StringComparer]::Ordinal)
    Out-Lines ($d | ForEach-Object { "D $_" })
}

switch ($Cmd) {
    "ttc" { Out-Extract (Invoke-TtcExtraction $Rest[0] $Rest[1] $Rest[2]) }
    "esohub" { Out-Extract (Invoke-EsoHubExtraction $Rest[0] $Rest[1] $Rest[2]) }
    "ttcupload" {
        $r = Read-TTCUpload $Rest[0] $Rest[1] ([long]$Rest[2]) $Rest[3]
        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($e in $r.Entries) { $lines.Add("E`t$($e.Guild)`t$($e.Json)") }
        foreach ($g in @($r.Entries | ForEach-Object { $_.Guild } | Sort-Object -Unique)) { $lines.Add("G`t$g") }
        foreach ($l in $r.NoId) { $lines.Add("L`t$l") }
        foreach ($g in $r.Kiosks.Keys) { if (@($r.Entries | Where-Object { $_.Guild -eq $g }).Count -gt 0) { $lines.Add("K`t$g`t$($r.Kiosks[$g][0])`t$($r.Kiosks[$g][1])") } }
        $lines.Add("C`t$($r.Culture)")
        $lines.Add("N`t$($r.Newest)")
        $a = $lines.ToArray(); [Array]::Sort($a, [StringComparer]::Ordinal)
        Out-Lines $a
    }
    "merge" {
        $dbColors = New-Object System.Collections.Hashtable
        foreach ($l in [System.IO.File]::ReadLines($DB_FILE)) { $p = $l.Split('|'); if ($p[0] -match '^[0-9]+$' -and $p.Length -ge 2) { $dbColors[$p[0]] = Get-QualityColor $p[1] } }
        Out-Lines (Merge-HistoryLines ([System.IO.File]::ReadAllLines($Rest[0])) ([System.IO.File]::ReadAllLines($Rest[1])) $dbColors)
    }
    "tplhist" {
        $h = [System.IO.Path]::GetTempFileName(); Remove-Item $h
        if ($Rest[0] -ne "-") { Copy-Item -LiteralPath $Rest[0] -Destination $h -Force }
        Merge-TemplateHistory $h $Rest[1] $Rest[2]
        [Console]::Out.Write([System.IO.File]::ReadAllText($h)); Remove-Item $h
    }
    "prune" {
        $HIST_FILE = [System.IO.Path]::GetTempFileName()
        Copy-Item -LiteralPath $Rest[0] -Destination $HIST_FILE -Force
        $CURRENT_TIME = [long]$Rest[1]; $global:LOG_MODE = "simple"
        function UIEcho($msg) { [Console]::Out.Write("$msg`n") }
        Prune-History
        [Console]::Out.Write([System.IO.File]::ReadAllText($HIST_FILE)); Remove-Item $HIST_FILE
    }
    "dbapply" { Apply-DB-Updates ([System.IO.File]::ReadAllLines($Rest[0])); [Console]::Out.Write([System.IO.File]::ReadAllText($DB_FILE)) }
    "listing" {
        $script:bSrc = $Rest[3]; $script:bUser = $Rest[4]; $script:bCutoff = [double]$Rest[5]
        Out-Lines (Get-HistoryRows $Rest[0] (To-LowerAscii $Rest[2]) $Rest[1])
    }
    "scan" { Out-Lines (Get-ScanRows $Rest[0] (To-LowerAscii $Rest[2]) $Rest[1]) }
    "top" {
        $script:bSrc = $Rest[2]; $script:bUser = $Rest[3]; $script:bCutoff = [double]$Rest[4]
        Out-Lines (Get-TopLines $Rest[1] $Rest[0])
    }
    "price" {
        $script:bSrc = $Rest[2]; $script:bUser = $Rest[3]; $script:bCutoff = [double]$Rest[4]
        Out-Lines (Get-PriceLines (To-LowerAscii $Rest[1]) $Rest[0])
    }
    "vnewer" { if (Test-VersionNewer $Rest[0] $Rest[1]) { Out-Lines @("yes") } else { Out-Lines @("no") } }
    "localist" {
        $l = [string[]](Get-AddonLocalList $Rest[0]); [Array]::Sort($l, [StringComparer]::Ordinal); Out-Lines $l
    }
    "plan" { Out-Lines (Get-AddonUpdatePlan (Get-AddonLocalList $Rest[0]) ([System.IO.File]::ReadAllText($Rest[1])) $(if ($Rest.Count -gt 2) { $Rest[2] } else { "" })) }
    "install" {
        $ADDON_DIR = $Rest[0]; $TARGET_DIR = $Rest[1]; $TEMP_DIR_ROOT = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $TEMP_DIR_ROOT | Out-Null
        if (Install-AddonZip $Rest[2]) { Out-Lines @("installed: " + ($script:ADDON_INSTALLED -join " ")) } else { Out-Lines @("installed: none") }
        Remove-Item -LiteralPath $TEMP_DIR_ROOT -Recurse -Force -ErrorAction SilentlyContinue
    }
    "dbsync" {
        $TARGET_DIR = $Rest[0]; $DB_DIR = Join-Path $TARGET_DIR "Database"; $DB_FILE = Join-Path $DB_DIR "LTTC_Database.db"
        $HIST_FILE = Join-Path $DB_DIR "LTTC_History.db"; $TEMP_DIR_ROOT = Join-Path $TARGET_DIR "Temp"
        New-Item -ItemType Directory -Force -Path $DB_DIR, $TEMP_DIR_ROOT | Out-Null
        $global:ENABLE_LOCAL_MODE = $false
        function Check-Addon-Enabled($name) { return $false }
        . "$SRC/features/database/sync.ps1"
        $dbHead = ([System.IO.File]::ReadAllLines($DB_FILE))[0]
        $items = @([System.IO.File]::ReadAllLines($DB_FILE) | Where-Object { !$_.StartsWith("#") }).Count
        $histLines = if (Test-Path $HIST_FILE) { [System.IO.File]::ReadAllLines($HIST_FILE) } else { @() }
        $histHead = if ($histLines.Count -gt 0) { $histLines[0] } else { "" }
        $hist = @($histLines | Where-Object { $_.StartsWith("HISTORY|") }).Count
        $left = @(Get-ChildItem -LiteralPath $TEMP_DIR_ROOT -Recurse -Force).Count
        Out-Lines @("database $dbHead items=$items", "history $histHead lines=$hist", "temp_left=$left")
    }
    "backupprune" {
        $TARGET_DIR = $Rest[0]; Remove-OldAddonBackups
        $l = [string[]](Get-ChildItem -LiteralPath (Join-Path (Join-Path $TARGET_DIR "Backups") "AddOns") -Directory | ForEach-Object { $_.Name }); [Array]::Sort($l, [StringComparer]::Ordinal); Out-Lines $l
    }
    "selfinstall" {
        $TARGET_DIR = $Rest[0]; $SCRIPT_NAME = $Rest[1]; $FULL_SCRIPT_PATH = $Rest[2]; $APP_VERSION = $Rest[3]
        $TEMP_DIR_ROOT = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $TEMP_DIR_ROOT | Out-Null
        $rc = Install-SelfUpdate $(if ($Rest.Count -gt 4) { $Rest[4] } else { "" }) $(if ($Rest.Count -gt 5) { $Rest[5] } else { "" })
        Out-Lines @("rc=$rc new=$($script:SELF_NEW_VERSION)")
        foreach ($f in @((Join-Path $TARGET_DIR $SCRIPT_NAME), "$FULL_SCRIPT_PATH.new")) {
            if (Test-Path -LiteralPath $f) {
                $v = if ([System.IO.File]::ReadAllText($f) -cmatch '\$APP_VERSION = "([^"]+)"') { $matches[1] } else { "" }
                Out-Lines @("$(Split-Path (Split-Path $f -Parent) -Leaf)/$(Split-Path $f -Leaf): APP_VERSION=`"$v`"")
            }
        }
        Remove-Item -LiteralPath $TEMP_DIR_ROOT -Recurse -Force -ErrorAction SilentlyContinue
    }
    "ghself" {
        $null = Get-GithubSelfDetails
        Out-Lines @("ver=$($script:GH_SELF_VERSION) url=$($script:GH_SELF_URL)")
    }
    "ehparse2" { Out-Lines (ConvertFrom-EsoHubV2 ([System.IO.File]::ReadAllText($Rest[0]))) }
    "ehparse1" { Out-Lines (ConvertFrom-EsoHubV1 ([System.IO.File]::ReadAllText($Rest[0]))) }
    "ehlocal" { Out-Lines @("v=$(Get-EsoHubLocalVersion $Rest[0] $Rest[1])") }
    "ehnewer" { if (Test-EsoHubNewer $Rest[0] $Rest[1]) { Out-Lines @("yes") } else { Out-Lines @("no") } }
    "ehfetch" {
        $TEMP_DIR_ROOT = $Rest[0]; $global:EH_USER_TOKEN = if ($Rest.Count -gt 1) { $Rest[1] } else { "" }; $SYS_ID = "test"
        if (Get-EsoHubAddons) { Out-Lines @("rc=0") } else { Out-Lines @("rc=1") }
        Out-Lines @("api=$($global:ESOHUB_API_USED) blocked=$(if ($global:ESOHUB_BLOCKED) { 'true' } else { 'false' }) fail=$($global:ESOHUB_FAIL)")
        Out-Lines @($global:ESOHUB_RECORDS)
        Out-Lines @("temp_left=$(@(Get-ChildItem -LiteralPath $TEMP_DIR_ROOT -Recurse -Force).Count)")
    }
    "ehdownload" {
        $global:EH_USER_TOKEN = ""; $RAND_UA = ""
        $rc = Get-EsoHubFile $Rest[0] $Rest[1] $(if ($Rest.Count -gt 2) { $Rest[2] } else { "" })
        Out-Lines @("rc=$rc file=$(if (Test-Path -LiteralPath $Rest[1]) { 'yes' } else { 'no' })")
    }
    "ehupload" {
        $SAVED_VAR_DIR = $Rest[4]; $TEMP_DIR_ROOT = $Rest[5]; $global:EH_USER_TOKEN = if ($Rest.Count -gt 6) { $Rest[6] } else { "" }
        if (Send-EsoHubUpload $Rest[0] $Rest[1] $Rest[2] $Rest[3]) { Out-Lines @("rc=0") } else { Out-Lines @("rc=1") }
        Out-Lines @("temp_left=$(@(Get-ChildItem -LiteralPath $TEMP_DIR_ROOT -Recurse -Force).Count)")
    }
    "ehtoken" { $SYS_ID = "test"; Out-Lines @("token=$(Get-EsoHubToken $Rest[0] $Rest[1])") }
    "ehlogin" {
        $SYS_ID = "test"; $t = Get-EsoHubToken $Rest[0] $Rest[1]
        Out-Lines @("token=$t blocked=$(if ($global:ESOHUB_LOGIN_BLOCKED) { 'true' } else { 'false' }) fail=$($global:ESOHUB_LOGIN_FAIL)")
    }
    "secret" {
        foreach ($v in $Rest) {
            $e = Protect-Secret $v; $d = Unprotect-Secret $e
            $enc = if ("$e" -match "^ENC1:") { "ENC1" } else { "plain" }
            if ($d -eq $v) { Out-Lines @("roundtrip ok enc=$enc [$v]") } else { Out-Lines @("roundtrip FAIL [$v] -> [$d]") }
        }
    }
    "mergereport" {
        $TEMP_DIR_ROOT = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $TEMP_DIR_ROOT | Out-Null
        $HIST_FILE = Join-Path $TEMP_DIR_ROOT "hist"
        Copy-Item -LiteralPath $Rest[0] -Destination $HIST_FILE
        function UIEcho($msg) { [Console]::Out.Write("$msg`n") }
        Merge-HistoryReport ([System.IO.File]::ReadAllLines($Rest[1]))
        Remove-Item -LiteralPath $TEMP_DIR_ROOT -Recurse -Force
    }
    "ehreload" {
        $global:ESOHUB_CF_CLEARANCE = $Rest[0]; $global:ESOHUB_CF_UA = $Rest[1]; $CONFIG_FILE = $Rest[2]
        Import-EsoHubCf
        Out-Lines @("cookie=$($global:ESOHUB_CF_CLEARANCE) ua=$($global:ESOHUB_CF_UA)")
    }
    "ehuaprobe" {
        $page = if ($Rest.Count -gt 0 -and $Rest[0]) { $Rest[0] } else { "https://eso-hub.com/en" }
        [void](Invoke-EsoHubBrowserOpen $page)
        Out-Lines @("seen=[$($global:ESOHUB_UA_SEEN)] left=[]")
    }
    "ehcodelogin" {
        $SYS_ID = "test"; $global:CONFIG_CHANGED = $false
        [void](Invoke-EsoHubCodeLogin)
        Out-Lines @("token=$($global:ESOHUB_TOKEN) user=$($global:ESOHUB_LOGIN_USER) fail=$($global:ESOHUB_LOGIN_FAIL)")
        Out-Lines @("cf_saved=$(if ($global:ESOHUB_CF_CLEARANCE) { 'yes' } else { 'no' }) ua=$($global:ESOHUB_CF_UA) changed=$(if ($global:CONFIG_CHANGED) { 'true' } else { 'false' })")
    }
    "vdiff" {
        foreach ($a in $Rest) { $pp = $a.Split(",", 2); Out-Lines @(((Get-VersionDiff $pp[0] $pp[1]) -replace [char]27, "<ESC>")) }
    }
    "ehcfclean" {
        foreach ($a in $Rest) {
            $v = Get-EsoHubCleanCookie $a
            Out-Lines @("cookie [$a] -> $(if ($null -ne $v) { "[$v]" } else { 'invalid' })")
            $v = Get-EsoHubCleanUA $a
            Out-Lines @("ua [$a] -> $(if ($null -ne $v) { "[$v]" } else { 'invalid' })")
        }
    }
    "ehcycle" {
        $W = $Rest[0]; $ADDON_DIR = Join-Path $W "AddOns"; $SAVED_VAR_DIR = Join-Path $W "SavedVariables"; $SNAP_DIR = Join-Path $W "Snapshots"
        $TEMP_DIR_ROOT = Join-Path $W "Temp"; $DB_DIR = Join-Path $W "Database"
        New-Item -ItemType Directory -Force -Path $SNAP_DIR, $TEMP_DIR_ROOT, $DB_DIR | Out-Null
        $TEMP_SCAN_FILE = Join-Path $TEMP_DIR_ROOT "scan.log"; [System.IO.File]::WriteAllText($TEMP_SCAN_FILE, "")
        $CURRENT_TIME = 1759300000; $global:EH_LAST_DOWNLOAD = if ($Rest.Count -gt 2) { $Rest[2] } else { "0" }; $global:EH_LAST_SALE = 0; $global:EH_LAST_CHECK = 0
        $global:EH_LOC_5 = "0"; $global:EH_LOC_7 = "0"; $global:EH_LOC_9 = "0"; $global:EH_USER_TOKEN = if ($Rest.Count -gt 1) { $Rest[1] } else { "" }
        $global:ENABLE_LOCAL_MODE = $false; $global:ENABLE_DISPLAY = $false; $global:SILENT = $false; $SYS_ID = "test"; $RAND_UA = ""
        $notifEH = "Up-to-date"; $FOUND_NEW_DATA = $false; $TEMP_DIR_USED = $false; $global:CONFIG_CHANGED = $false
        function UIEcho($msg) { [Console]::Out.Write("$msg`n") }
        function Start-Spinner($msg) { [Console]::Out.Write("spin: $msg`n") }
        function Stop-Spinner($rc, $msg) { [Console]::Out.Write("done ${rc}: $msg`n") }
        function Check-Addon-Enabled($name) { return (Test-Path -LiteralPath (Join-Path $ADDON_DIR $name)) }
        . "$SRC/features/esohub/update.ps1"
        Out-Lines @("notif=$notifEH", "cf_saved=$(if ($global:ESOHUB_CF_CLEARANCE) { 'yes' } else { 'no' }) asked=$(if ($global:ESOHUB_CF_ASKED) { 'true' } else { 'false' })", "loc=$($global:EH_LOC_5) $($global:EH_LOC_7) $($global:EH_LOC_9) last_download=$($global:EH_LAST_DOWNLOAD)")
        foreach ($a in @("EsoTradingHub", "LibEsoHubPrices", "EsoHubScanner")) { Out-Lines @("$a=$(Get-EsoHubLocalVersion (Join-Path $ADDON_DIR $a) $a)") }
        $snaps = [string[]]@(Get-ChildItem -LiteralPath $SNAP_DIR | ForEach-Object { $_.Name }); [Array]::Sort($snaps, [StringComparer]::Ordinal)
        Out-Lines @("snapshots: $(($snaps | ForEach-Object { "$_ " }) -join '')")
    }
    "ttcver" { Out-Lines @("v=$(Get-TTCPriceTableVersion $Rest[0])") }
    "ttccycle" {
        $W = $Rest[0]; $ADDON_DIR = Join-Path $W "AddOns"; $SAVED_VAR_DIR = Join-Path $W "SavedVariables"; $SNAP_DIR = Join-Path $W "Snapshots"
        $TEMP_DIR_ROOT = Join-Path $W "Temp"; $DB_DIR = Join-Path $W "Database"; $TEMP_DIR = $TEMP_DIR_ROOT
        New-Item -ItemType Directory -Force -Path $SNAP_DIR, $TEMP_DIR_ROOT, $DB_DIR, $SAVED_VAR_DIR | Out-Null
        $TEMP_SCAN_FILE = Join-Path $TEMP_DIR_ROOT "scan.log"; [System.IO.File]::WriteAllText($TEMP_SCAN_FILE, "")
        $CURRENT_TIME = 1759300000; $global:TTC_LAST_CHECK = $Rest[1]; $AUTO_SRV = $Rest[2]
        $global:ENABLE_LOCAL_MODE = ($Rest.Count -gt 3 -and $Rest[3] -eq "true")
        $HAS_TTC = $true; $global:TTC_LAST_DOWNLOAD = 0; $global:TTC_LAST_SALE = 0
        $global:ENABLE_DISPLAY = $false; $global:SILENT = $false; $TTC_USER_AGENT = "test"; $TTC_DOMAIN = "us.tamrieltradecentre.com"
        $notifTTC = "Up-to-date"; $FOUND_NEW_DATA = $false; $TEMP_DIR_USED = $false; $global:CONFIG_CHANGED = $false
        function UIEcho($msg) { [Console]::Out.Write("$msg`n") }
        . "$SRC/features/ttc/update.ps1"
        Out-Lines @("notif=$notifTTC last_check=$($global:TTC_LAST_CHECK) changed=$(if ($global:CONFIG_CHANGED) { 'true' } else { 'false' })")
    }
    { $_ -in @("aomslots", "aommerge", "aomcycle", "aomask") } {
        Invoke-Expression ([regex]::Match((Get-Content -Raw "$SRC/lib/constants.ps1"), "(?s)function Get-Part.*?\n}\n").Value)
        . "$SRC/features/aom/sync.ps1"
    }
    "aomslots" {
        foreach ($t in $Rest) {
            $slots = Get-AomSlots ([long]$t)
            Out-Lines @("$t -> $($slots[0]) $($slots[1]) wait=$(Get-AomWaitText ($slots[1] - [long]$t))")
        }
    }
    "aommerge" {
        $res = Merge-AomTable (Read-AomLines $Rest[0]) (Read-AomLines $Rest[1])
        [Console]::Out.Write($res.Text)
        Out-Lines @("ADDED=$($res.Added)", "UPDATED=$($res.Updated)")
        Out-Lines $res.Details
    }
    "aomask" {
        $global:ADDON_DIR = $Rest[0]
        Out-Lines @("installed=$(if (Test-AomInstalled) { 'yes' } else { 'no' })")
        Show-AomQuestion
        foreach ($a in @("", "1", "2", "x")) { Set-AomAnswer $a; Out-Lines @("answer '$a' -> $($global:AOM_DATA_UPDATES)") }
    }
    "aomcycle" {
        $W = $Rest[0]; $ADDON_DIR = Join-Path $W "AddOns"; $TEMP_DIR_ROOT = Join-Path $W "Temp"
        New-Item -ItemType Directory -Force -Path $TEMP_DIR_ROOT | Out-Null
        $CURRENT_TIME = $Rest[1]; $global:AOM_LAST_SYNC = $Rest[2]; $global:CONFIG_CHANGED = $false; $global:notifAom = ""; $global:SILENT = $false
        $global:AOM_DATA_UPDATES = if ($Rest.Count -gt 3 -and $Rest[3]) { $Rest[3] } else { "true" }
        if ($global:AOM_DATA_UPDATES -eq "unset") { $global:AOM_DATA_UPDATES = "" }
        $global:AOM_TEST_ANSWER = if ($Rest.Count -gt 4 -and $Rest[4]) { $Rest[4] } else { "cannot" }
        $cycles = if ($Rest.Count -gt 5 -and $Rest[5]) { [int]$Rest[5] } else { 1 }
        function UIEcho($msg) { [Console]::Out.Write("$msg`n") }
        function Start-Spinner($msg) { [Console]::Out.Write("spin: $msg`n") }
        function Stop-Spinner($rc, $msg) { [Console]::Out.Write("done ${rc}: $msg`n") }
        function Test-AomCanAsk { return ($global:AOM_TEST_ANSWER -ne "cannot") }
        function Read-AomAnswer {
            if ($global:AOM_TEST_ANSWER -eq "timeout") { return $null }
            if ($global:AOM_TEST_ANSWER -eq "enter") { return "" }
            return $global:AOM_TEST_ANSWER
        }
        for ($c = 0; $c -lt $cycles; $c++) { Invoke-AomDataSync }
        Out-Lines @("aom_data_updates=$($global:AOM_DATA_UPDATES) asked=$(if ($global:AOM_ASKED) { 'true' } else { 'false' })")
        Out-Lines @("notif=$($global:notifAom) last_sync=$($global:AOM_LAST_SYNC) changed=$(if ($global:CONFIG_CHANGED) { 'true' } else { 'false' }) temp_left=$(@(Get-ChildItem -LiteralPath $TEMP_DIR_ROOT -Force).Count)")
        $so = [Console]::OpenStandardOutput()
        foreach ($f in $AOM_TABLES) {
            $p = Join-Path (Join-Path (Join-Path $ADDON_DIR "APH-OnManager") "DATA") $f
            if (!(Test-Path -LiteralPath $p -PathType Leaf)) { continue }
            Out-Lines @("== $f")
            $b = [System.IO.File]::ReadAllBytes($p); $so.Write($b, 0, $b.Length); $so.Flush()
        }
    }
    default { throw "windows.ps1: unknown command $Cmd" }
}
foreach ($p in $global:EH_BROWSERS) { $p.WaitForExit() }
Remove-Item $UI_STATE_FILE -ErrorAction SilentlyContinue
