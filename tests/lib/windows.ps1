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
    "backupprune" {
        $TARGET_DIR = $Rest[0]; Remove-OldAddonBackups
        $l = [string[]](Get-ChildItem -LiteralPath (Join-Path (Join-Path $TARGET_DIR "Backups") "AddOns") -Directory | ForEach-Object { $_.Name }); [Array]::Sort($l, [StringComparer]::Ordinal); Out-Lines $l
    }
    "selfinstall" {
        $TARGET_DIR = $Rest[0]; $SCRIPT_NAME = $Rest[1]; $FULL_SCRIPT_PATH = $Rest[2]; $APP_VERSION = $Rest[3]
        $TEMP_DIR_ROOT = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $TEMP_DIR_ROOT | Out-Null
        $rc = Install-SelfUpdate
        Out-Lines @("rc=$rc new=$($script:SELF_NEW_VERSION)")
        foreach ($f in @((Join-Path $TARGET_DIR $SCRIPT_NAME), "$FULL_SCRIPT_PATH.new")) {
            if (Test-Path -LiteralPath $f) {
                $v = if ([System.IO.File]::ReadAllText($f) -cmatch '\$APP_VERSION = "([^"]+)"') { $matches[1] } else { "" }
                Out-Lines @("$(Split-Path (Split-Path $f -Parent) -Leaf)/$(Split-Path $f -Leaf): APP_VERSION=`"$v`"")
            }
        }
        Remove-Item -LiteralPath $TEMP_DIR_ROOT -Recurse -Force -ErrorAction SilentlyContinue
    }
    default { throw "windows.ps1: unknown command $Cmd" }
}
Remove-Item $UI_STATE_FILE -ErrorAction SilentlyContinue
