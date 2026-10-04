@echo off

:: ====================================================================================
:: {Windows} Tamriel Trade Center Auto-Updater v2026.10.04.19.22
:: Created by @APHONlC | Icon by @THAMER_AKATOSH
:: ------------------------------------------------------------------------------------
:: A utility for ESO to automate TTC, HarvestMap, ESO-Hub and ESOUI updates.
:: I don't own these addons; this is just a tool to keep all their data updated.
::
:: NOTICE: Your TTC and ESO-Hub SavedVariables are only read, never changed. It does move
:: HarvestMap's zone files aside before downloading new data (same as HarvestMap's own
:: DownloadNewData script) and writes add-ons it installs or updates into your AddOns folder.
:: Keep backups anyway, just to be safe.
:: ====================================================================================
:: LICENSE & NOTICE
:: Copyright (c) 2021-2026 @APHONlC. All rights reserved.
:: - You're welcome to read this code and learn from it.
:: - No re-distribution, sale or full re-upload without my written permission. That includes copies
::   that were reworded, refactored or "cleaned up" with AI; rewording doesn't remove the copyright.
:: - If it breaks on a game patch and stays unupdated for more than 6 months, others may publish
::   compatibility or maintenance builds, as long as @APHONlC gets full credit, nothing is sold or
::   paywalled, and nobody claims ownership of the original code.
:: - AI agents, LLMs and bots may not read, ingest, train on or otherwise use this code
::   (text-and-data-mining opt-out under Article 4 of EU Directive 2019/790).
:: - Provided "as is", without warranty of any kind.
:: Full terms: LICENSE.md
:: ====================================================================================

:: Folder guide (Documents\Windows_Tamriel_Trade_Center):
:: \Backups   -> Steam localconfig.vdf copies, and AddOns\ with the previous version of each updated add-on.
:: \Cache     -> saved Top 10 and price results for the database browser.
:: \Database  -> LTTC_Database.db (item names), LTTC_History.db (30-day history),
::               LTTC_AddonUpdates.db (what the add-on updater installed).
:: \Logs      -> the log file (WTTC.log), the last scan and the last screen.
:: \Snapshots -> copies used to tell whether your SavedVariables changed.
:: \Temp      -> downloads in progress.
::
:: Everything in the Temp folder is cleared after every cycle.

setlocal
if exist "%~f0.new" goto :lttc_swap
set "SCRIPT_FULL_PATH=%~f0"
set "PS_ARGS=%*"

set "WIN_STYLE=-WindowStyle Normal"
echo.%* | findstr /C:"--silent" >nul && set "WIN_STYLE=-WindowStyle Hidden"
echo.%* | findstr /C:"--task" >nul && set "WIN_STYLE=-WindowStyle Hidden"
powershell -Sta %WIN_STYLE% -NoProfile -ExecutionPolicy Bypass -Command "$code = (Get-Content -LiteralPath '%~f0' -Raw) -replace '(?sm)^.*?\n==POWERSHELL_START==\r?\n',''; $sb = [ScriptBlock]::Create($code); & $sb"

if %errorlevel% equ 3 if exist "%~f0.new" goto :lttc_swap
if %errorlevel% neq 0 pause
exit /b %errorlevel%

:lttc_swap
move /y "%~f0.new" "%~f0" >nul & start "" /b "%~f0" %* & exit /b 0

==POWERSHELL_START==
function Get-Part([string]$h, [int]$s) {
    $o = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $h.Length; $i += 2) {
        $s = ($s * 73 + 41) % 256
        [void]$o.Append([char]([Convert]::ToInt32($h.Substring($i, 2), 16) -bxor $s))
    }
    return $o.ToString()
}

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
$ErrorActionPreference = "SilentlyContinue"

$APP_VERSION = "2026.10.04.19.22"
$APP_TITLE = "Windows Tamriel Trade Center v$APP_VERSION"
$TASK_NAME = "Windows Tamriel Trade Center"
$SYS_ID = "windows"
$RESTORE_EVENT_NAME = "Global\WTTC_RestoreEvent"

$ESC = [char]27
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$host.UI.RawUI.WindowTitle = $APP_TITLE

$ESOUI_API = if ($env:LTTC_ESOUI_API) { $env:LTTC_ESOUI_API } else { "https://api.mmoui.com" }
$ESOUI_UA = "Mozilla/5.0"
$ESOUI_SELF_ID = "3249"
$ESOUI_DB_ID = "4428"

function Get-Md5Hex($path) {
    try { return (Get-FileHash -LiteralPath $path -Algorithm MD5).Hash.ToLowerInvariant() } catch { return "" }
}

function Test-VersionNewer([string]$a, [string]$b) {
    $a = $a -replace '^[vV]', ''; $b = $b -replace '^[vV]', ''
    $x = [regex]::Split($a, '[^0-9]+'); $y = [regex]::Split($b, '[^0-9]+')
    $n = [math]::Max($x.Length, $y.Length)
    for ($i = 0; $i -lt $n; $i++) {
        $p = if ($i -lt $x.Length) { To-Num $x[$i] } else { 0 }
        $q = if ($i -lt $y.Length) { To-Num $y[$i] } else { 0 }
        if ($p -gt $q) { return $true }
        if ($p -lt $q) { return $false }
    }
    return $false
}

function Get-JsonValue([string]$json, [string]$key) {
    if ($json -cmatch ('"' + [regex]::Escape($key) + '"\s*:\s*"([^"]*)"')) { return $matches[1].Replace('\/', '/') }
    return ""
}

function Get-EsouiDetails($id) {
    $script:ESOUI_VERSION = ""; $script:ESOUI_DOWNLOAD = ""; $script:ESOUI_MD5 = ""
    $resp = (& curl.exe -s -f -m 30 -A $ESOUI_UA "$ESOUI_API/v3/game/ESO/filedetails/$id.json" 2>$null) -join ""
    if ($LASTEXITCODE -ne 0 -or !$resp) { return $false }
    $script:ESOUI_VERSION = Get-JsonValue $resp "UIVersion"
    $script:ESOUI_DOWNLOAD = Get-JsonValue $resp "UIDownload"
    $script:ESOUI_MD5 = (Get-JsonValue $resp "UIMD5").ToLowerInvariant()
    return ($script:ESOUI_VERSION -ne "" -and $script:ESOUI_DOWNLOAD -ne "")
}

function Invoke-EsouiDownload($id, $dest) {
    if (!(Get-EsouiDetails $id)) { return 1 }
    Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
    & curl.exe -s -f -L -m 180 -A $ESOUI_UA -o $dest $script:ESOUI_DOWNLOAD 2>$null
    if ($LASTEXITCODE -ne 0) { Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue; return 1 }
    if ($script:ESOUI_MD5 -and (Get-Md5Hex $dest) -ne $script:ESOUI_MD5) {
        Log-Event "WARN" "ESOUI file $id failed its checksum, discarded."
        Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue; return 2
    }
    if (!(Test-ZipFile $dest)) { Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue; return 2 }
    return 0
}
try {
    $csharp = @"
    using System;
    using System.Runtime.InteropServices;
    public class ConsoleConfig {
        const int SW_HIDE = 0;
        const int SW_RESTORE = 9;
        const int SW_SHOW = 5;
        const uint ENABLE_QUICK_EDIT = 0x0040;
        const int STD_INPUT_HANDLE = -10;
        const int STD_OUTPUT_HANDLE = -11;
        const uint ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004;
        
        [DllImport("kernel32.dll", ExactSpelling = true)]
        public static extern IntPtr GetConsoleWindow();
        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")]
        public static extern bool IsIconic(IntPtr hWnd);
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr GetStdHandle(int nStdHandle);
        [DllImport("kernel32.dll")]
        public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
        [DllImport("kernel32.dll")]
        public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);

        public static void DisableQuickEdit() {
            IntPtr consoleHandle = GetStdHandle(STD_INPUT_HANDLE);
            uint consoleMode;
            if (GetConsoleMode(consoleHandle, out consoleMode)) {
                consoleMode &= ~ENABLE_QUICK_EDIT;
                SetConsoleMode(consoleHandle, consoleMode);
            }
        }

        public static void EnableANSI() {
            IntPtr handle = GetStdHandle(STD_OUTPUT_HANDLE);
            uint mode;
            if (GetConsoleMode(handle, out mode)) {
                mode |= ENABLE_VIRTUAL_TERMINAL_PROCESSING;
                SetConsoleMode(handle, mode);
            }
        }
        
        public static void HideWindow() {
            IntPtr hWnd = GetConsoleWindow();
            if (hWnd != IntPtr.Zero) ShowWindow(hWnd, SW_HIDE);
        }
        public static void RestoreWindow() {
            IntPtr hWnd = GetConsoleWindow();
            if (hWnd != IntPtr.Zero) {
                ShowWindow(hWnd, SW_RESTORE);
                ShowWindow(hWnd, SW_SHOW);
                SetForegroundWindow(hWnd);
            }
        }
        public static bool CheckMinimizedAndHide() {
            IntPtr hWnd = GetConsoleWindow();
            if (hWnd != IntPtr.Zero && IsIconic(hWnd)) {
                ShowWindow(hWnd, SW_HIDE);
                return true;
            }
            return false;
        }
    }
"@
    Add-Type -TypeDefinition $csharp -Language CSharp -IgnoreWarnings
    [ConsoleConfig]::DisableQuickEdit()
    [ConsoleConfig]::EnableANSI()
} catch {}

$TARGET_DIR = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "Windows_Tamriel_Trade_Center"
$DB_DIR = "$TARGET_DIR\Database"
$LOG_DIR = "$TARGET_DIR\Logs"
$SNAP_DIR = "$TARGET_DIR\Snapshots"
$TEMP_DIR_ROOT = "$TARGET_DIR\Temp"

foreach ($dir in @($TARGET_DIR, $DB_DIR, $LOG_DIR, $SNAP_DIR, $TEMP_DIR_ROOT)) {
    if (!(Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
}

if (Test-Path "$TARGET_DIR\LTTC_Database.db") { Move-Item "$TARGET_DIR\LTTC_Database.db" "$DB_DIR\" -Force }
if (Test-Path "$TARGET_DIR\LTTC_History.db") { Move-Item "$TARGET_DIR\LTTC_History.db" "$DB_DIR\" -Force }
if (Test-Path "$TARGET_DIR\wttc.logs") { Move-Item "$TARGET_DIR\wttc.logs" "$LOG_DIR\WTTC.log" -Force }
if (Test-Path "$TARGET_DIR\LTTC_LastScan.log") { Move-Item "$TARGET_DIR\LTTC_LastScan.log" "$LOG_DIR\" -Force }
if (Test-Path "$TARGET_DIR\LTTC_Display_State.log") { Move-Item "$TARGET_DIR\LTTC_Display_State.log" "$LOG_DIR\" -Force }
Get-ChildItem -Path $TARGET_DIR -Filter "*_snapshot.lua" | ForEach-Object { Move-Item $_.FullName "$SNAP_DIR\" -Force }
Get-ChildItem -Path $TARGET_DIR -Filter "*.tmp" | Remove-Item -Force
Get-ChildItem -Path $TARGET_DIR -Filter "*.out" | Remove-Item -Force

$CONFIG_FILE = "$TARGET_DIR\lttc_updater.conf"
$ICON_FILE = "$TARGET_DIR\lttc_icon.ico"
$DB_FILE = "$DB_DIR\LTTC_Database.db"
$HIST_FILE = "$DB_DIR\LTTC_History.db"
$LOG_FILE = "$LOG_DIR\WTTC.log"
$LAST_SCAN_FILE = "$LOG_DIR\LTTC_LastScan.log"
$UI_STATE_FILE = "$LOG_DIR\LTTC_Display_State.log"

foreach ($f in @($DB_FILE, $HIST_FILE, $LOG_FILE, $LAST_SCAN_FILE, $UI_STATE_FILE)) {
    if (!(Test-Path $f)) { New-Item -ItemType File -Force -Path $f | Out-Null }
}

if ((Test-Path $ICON_FILE) -and (Get-Item $ICON_FILE).Length -lt 1024) { Remove-Item $ICON_FILE -Force -ErrorAction SilentlyContinue }
if (!(Test-Path $ICON_FILE)) {
    try { & curl.exe -s -f -m 15 -L -o $ICON_FILE (Get-Part "a04556abef9f19a082f8bdeda364aa1f6d6307d88907e5302e1d7ffd60f34d2805fe8f2b740a9843d31629110bde0d3ac8cd733fea7a5492cd5ddb5ec614ab8b2525107ab8805b8c55b77e66766056d62a37d79858f8a7efadec099c79551be5855077cf13a8431fb418dec6d6c2cc329e927de3a934024c0f249b1a9a92674427df8c327f4a" 167) } catch {}
}

$currentPid = $PID
$existingProcess = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' AND ProcessId != $currentPid" | Where-Object { $_.CommandLine -match "Windows_Tamriel_Trade_Center" } | Select-Object -First 1

if ($existingProcess) {
    $isBackground = ($env:PS_ARGS -match "--silent|--task|--steam")
    if ($isBackground) {
        try {
            $evt = [System.Threading.EventWaitHandle]::OpenExisting($RESTORE_EVENT_NAME)
            $evt.Set()
        } catch {}
        [ConsoleConfig]::HideWindow()
        [Environment]::Exit(0)
    }

    [ConsoleConfig]::RestoreWindow()
    
    $oldPid = $existingProcess.ProcessId
    Write-Host "`n$ESC[0;33m[!] Another instance of the auto-updater (PID: $oldPid) is already running.$ESC[0m"
    Write-Host "Do you want to terminate the existing process and continue? (y/n): " -NoNewline
    
    $timeout = 10
    $killChoice = 'y'
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($stopwatch.Elapsed.TotalSeconds -lt $timeout) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            $killChoice = $key.KeyChar
            Write-Host $killChoice
            break
        }
        Start-Sleep -Milliseconds 100
    }
    $stopwatch.Stop()
    
    if ($stopwatch.Elapsed.TotalSeconds -ge $timeout) { Write-Host "y" }

    if ($killChoice -match '^[Yy]$') {
        Write-Host "$ESC[0;31mTerminating old process...$ESC[0m"
        
        Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' AND ProcessId != $currentPid" | ForEach-Object {
            if ($_.CommandLine -match "Windows_Tamriel_Trade_Center") {
                $targetProcId = $_.ProcessId
                
                $oldParent = Get-CimInstance Win32_Process -Filter "ProcessId = $targetProcId"
                if ($oldParent.ParentProcessId) {
                    $oldParentProc = Get-Process -Id $oldParent.ParentProcessId -ErrorAction SilentlyContinue
                    if ($oldParentProc -and $oldParentProc.Name -eq "cmd") { Stop-Process -Id $oldParentProc.Id -Force }
                }
                
                Stop-Process -Id $targetProcId -Force -ErrorAction SilentlyContinue
            }
        }
        Start-Sleep -Seconds 1
    } else {
        Write-Host "$ESC[0;32mKeeping the existing process safe. Exiting new instance.$ESC[0m"
        Start-Sleep -Seconds 1
        [Environment]::Exit(1)
    }
}

$parsedArgs = @()
if ([string]::IsNullOrWhiteSpace($env:PS_ARGS) -eq $false) {
    $parsedArgs = [System.Text.RegularExpressions.Regex]::Matches($env:PS_ARGS, '[\"]([^\"]+)[\"]|([^ ]+)') |
        ForEach-Object { if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value } }
}
$global:HAS_ARGS = if ($parsedArgs.Count -gt 0) {$true} else {$false}
$global:IS_TASK = $false
$global:IS_STEAM_LAUNCH = $false

for ($i = 0; $i -lt $parsedArgs.Count; $i++) {
    if ($parsedArgs[$i] -eq "--task" -or $parsedArgs[$i] -eq "--silent") { 
        $global:IS_TASK = $true 
        [ConsoleConfig]::HideWindow()
    }
    if ($parsedArgs[$i] -eq "--steam") { $global:IS_STEAM_LAUNCH = $true }
}

$script:restoreEvent = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, $RESTORE_EVENT_NAME)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if ($global:IS_TASK) {
    $script:trayIcon = New-Object System.Windows.Forms.NotifyIcon
    $script:trayIcon.Text = $APP_TITLE
    if (Test-Path $ICON_FILE) { $script:trayIcon.Icon = New-Object System.Drawing.Icon($ICON_FILE) } 
    else { $script:trayIcon.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon((Get-Process -id $PID).Path) }

    $menu = New-Object System.Windows.Forms.ContextMenu
    $exitItem = New-Object System.Windows.Forms.MenuItem "Exit Updater"
    $exitItem.add_Click({
        Log-Event "INFO" "WTTC Updater Service Terminated by User via Tray."
        $script:trayIcon.Visible = $false
        try {
            $parent = Get-CimInstance Win32_Process -Filter "ProcessId = $PID"
            if ($parent.ParentProcessId) {
                $parentProc = Get-Process -Id $parent.ParentProcessId -ErrorAction SilentlyContinue
                if ($parentProc.Name -eq "cmd") { Stop-Process -Id $parentProc.Id -Force }
            }
        } catch {}
        [Environment]::Exit(0)
    })
    
    [void]$menu.MenuItems.Add($exitItem)
    $script:trayIcon.ContextMenu = $menu
    $script:trayIcon.Visible = $true
}

function Wait-WithEvents($seconds) {
    $endTime = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $endTime) {
        [ConsoleConfig]::CheckMinimizedAndHide() | Out-Null
        if ($script:restoreEvent.WaitOne(0)) { [ConsoleConfig]::RestoreWindow() }
        if ([System.Console]::KeyAvailable) {
            $key = [System.Console]::ReadKey($true)
            if ($key.KeyChar -eq 'b' -or $key.KeyChar -eq 'B') { Browse-Database; Write-Host "`n$ESC[0;36mResuming countdown...$ESC[0m" }
        }
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 200
    }
}

function Send-Notification([string]$title, [string]$msg) {
    $esc = [System.Security.SecurityElement]
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime] | Out-Null
        $appId = "{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe"
        $template = "<toast><visual><binding template=`"ToastText02`"><text id=`"1`">$($esc::Escape($title))</text><text id=`"2`">$($esc::Escape($msg))</text></binding></visual></toast>"
        $xmlDocument = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xmlDocument.LoadXml($template)
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xmlDocument)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
        return $true
    } catch {
        Log-Event "WARN" "Toast notification failed, using a tray balloon instead: $($_.Exception.Message)"
    }
    try {
        $icon = $script:trayIcon
        $temporary = $false
        if (!$icon) {
            $icon = New-Object System.Windows.Forms.NotifyIcon
            $icon.Icon = if (Test-Path $ICON_FILE) { New-Object System.Drawing.Icon($ICON_FILE) } else { [System.Drawing.Icon]::ExtractAssociatedIcon((Get-Process -Id $PID).Path) }
            $icon.Visible = $true
            $temporary = $true
        }
        $icon.ShowBalloonTip(8000, $title, $msg, [System.Windows.Forms.ToolTipIcon]::Info)
        if ($temporary) {
            Start-Sleep -Seconds 6
            $icon.Visible = $false
            $icon.Dispose()
        }
        return $true
    } catch {
        Log-Event "WARN" "Tray notification failed too: $($_.Exception.Message)"
        return $false
    }
}
$FULL_SCRIPT_PATH = $env:SCRIPT_FULL_PATH
if ([string]::IsNullOrEmpty($FULL_SCRIPT_PATH)) { $FULL_SCRIPT_PATH = "Windows_Tamriel_Trade_Center.bat" }
$CURRENT_DIR = Split-Path $FULL_SCRIPT_PATH
$SCRIPT_NAME = Split-Path $FULL_SCRIPT_PATH -Leaf

function Load-Config($path) {
    if (Test-Path $path) {
        Get-Content $path | ForEach-Object {
            if ($_ -match '^\s*([^=]+)\s*=\s*(.*)$') {
                $key = $matches[1].Trim()
                $val = $matches[2].Trim().Trim('"').Trim("'")
                Set-Variable -Name $key -Value $val -Scope Global
            }
        }
    }
}

if (Test-Path $CONFIG_FILE) { Load-Config $CONFIG_FILE }

$global:SILENT = $false
$global:AUTO_PATH = if ($AUTO_PATH -eq 'true') {$true} else {$false}
$global:SETUP_COMPLETE = if ($SETUP_COMPLETE -eq 'true') {$true} else {$false}
$global:ENABLE_NOTIFS = if ($ENABLE_NOTIFS -eq 'true') {$true} else {$false}
$global:ENABLE_DISPLAY = if ($ENABLE_DISPLAY -eq 'false') {$false} else {$true}
$global:ENABLE_LOCAL_MODE = if ($ENABLE_LOCAL_MODE -eq 'true') {$true} else {$false}
if (!$STARTUP_MODE) { $global:STARTUP_MODE = "0" }
if (!$LOG_MODE) { $global:LOG_MODE = "simple" }

if (!$TTC_LAST_SALE) { $global:TTC_LAST_SALE = 0 }
if (!$TTC_LAST_DOWNLOAD) { $global:TTC_LAST_DOWNLOAD = 0 }
if (!$TTC_LAST_CHECK) { $global:TTC_LAST_CHECK = 0 }
if (!$TTC_NA_VERSION) { $global:TTC_NA_VERSION = 0 }
if (!$TTC_EU_VERSION) { $global:TTC_EU_VERSION = 0 }
if (!$EH_LAST_SALE) { $global:EH_LAST_SALE = 0 }
if (!$EH_LAST_DOWNLOAD) { $global:EH_LAST_DOWNLOAD = 0 }
if (!$EH_LAST_CHECK) { $global:EH_LAST_CHECK = 0 }
if (!$EH_LOC_5) { $global:EH_LOC_5 = 0 }
if (!$EH_LOC_7) { $global:EH_LOC_7 = 0 }
if (!$EH_LOC_9) { $global:EH_LOC_9 = 0 }
if (!$HM_LAST_DOWNLOAD) { $global:HM_LAST_DOWNLOAD = 0 }
if (!$HM_LAST_CHECK) { $global:HM_LAST_CHECK = 0 }
if (!$EH_USER_TOKEN) { $global:EH_USER_TOKEN = "" }
if (!$TTC_CLIENT_ID) { $global:TTC_CLIENT_ID = "" }
if (!$TARGET_RUN_TIME) { $global:TARGET_RUN_TIME = 0 }
if (!$TARGET_USERNAME) { $global:TARGET_USERNAME = "" }
$global:ENABLE_ADDON_UPDATES = if ($ENABLE_ADDON_UPDATES -eq 'true') {$true} else {$false}
$global:AUTO_SELF_UPDATE = if ($AUTO_SELF_UPDATE -eq 'false') {$false} else {$true}
if (!$ADDON_LAST_CHECK) { $global:ADDON_LAST_CHECK = 0 }
if (!$SELF_LAST_CHECK) { $global:SELF_LAST_CHECK = 0 }
if (!$ADDON_UPDATE_SKIP) { $global:ADDON_UPDATE_SKIP = "" }

function save_config {
    $c = @"
AUTO_SRV="$AUTO_SRV"
SILENT=$($SILENT.ToString().ToLower())
AUTO_MODE="$AUTO_MODE"
ADDON_DIR="$ADDON_DIR"
SETUP_COMPLETE=$($SETUP_COMPLETE.ToString().ToLower())
ENABLE_NOTIFS=$($ENABLE_NOTIFS.ToString().ToLower())
ENABLE_DISPLAY=$($ENABLE_DISPLAY.ToString().ToLower())
ENABLE_LOCAL_MODE=$($ENABLE_LOCAL_MODE.ToString().ToLower())
LOG_MODE="$LOG_MODE"
STARTUP_MODE="$STARTUP_MODE"
TTC_LAST_SALE="$TTC_LAST_SALE"
TTC_LAST_DOWNLOAD="$TTC_LAST_DOWNLOAD"
TTC_LAST_CHECK="$TTC_LAST_CHECK"
TTC_NA_VERSION="$TTC_NA_VERSION"
TTC_EU_VERSION="$TTC_EU_VERSION"
EH_LAST_SALE="$EH_LAST_SALE"
EH_LAST_DOWNLOAD="$EH_LAST_DOWNLOAD"
EH_LAST_CHECK="$EH_LAST_CHECK"
EH_LOC_5="$EH_LOC_5"
EH_LOC_7="$EH_LOC_7"
EH_LOC_9="$EH_LOC_9"
HM_LAST_DOWNLOAD="$HM_LAST_DOWNLOAD"
HM_LAST_CHECK="$HM_LAST_CHECK"
EH_USER_TOKEN="$EH_USER_TOKEN"
TTC_CLIENT_ID="$TTC_CLIENT_ID"
TARGET_RUN_TIME="$TARGET_RUN_TIME"
TARGET_USERNAME="$TARGET_USERNAME"
SKIP_DL_TTC="$SKIP_DL_TTC"
SKIP_DL_HM="$SKIP_DL_HM"
SKIP_DL_EH="$SKIP_DL_EH"
ENABLE_ADDON_UPDATES=$($ENABLE_ADDON_UPDATES.ToString().ToLower())
ADDON_LAST_CHECK="$ADDON_LAST_CHECK"
ADDON_UPDATE_SKIP="$ADDON_UPDATE_SKIP"
AUTO_SELF_UPDATE=$($AUTO_SELF_UPDATE.ToString().ToLower())
SELF_LAST_CHECK="$SELF_LAST_CHECK"
"@
    $c | Out-File -FilePath $CONFIG_FILE -Encoding UTF8 -Force
    Log-Event "INFO" "Configuration saved to lttc_updater.conf"
}

function Log-Event($level, $message) {
    if ($level -eq "ITEM" -and $global:LOG_MODE -ne "detailed") { return }
    $clean_msg = $message -replace "\e\[[0-9;]*m", ""
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] [$level] $clean_msg" | Out-File -FilePath $LOG_FILE -Append -Encoding UTF8
}

function Convert-TimeStr($ts) {
    $now = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $diff = $now - $ts
    if ($diff -lt 0) { $diff = 0 }
    if ($ts -eq 0) { return "Active" }
    if ($diff -lt 60) { return "$diff" + "s ago" }
    if ($diff -lt 3600) { return "$([math]::Floor($diff/60))m ago" }
    if ($diff -lt 86400) { return "$([math]::Floor($diff/3600))h ago" }
    return "$([math]::Floor($diff/86400))d ago"
}

function UIEcho($msg) {
    if (!$global:SILENT) {
        $formatted = [System.Text.RegularExpressions.Regex]::Replace($msg, '\[TS:(\d+)\]', { 
            param($m) 
            $rel = Convert-TimeStr ([int]$m.Groups[1].Value)
            return "[$ESC[90m$rel$ESC[0m]" 
        })
        [Console]::WriteLine($formatted)
        [System.IO.File]::AppendAllText($UI_STATE_FILE, "$formatted`n", [System.Text.Encoding]::UTF8)
    }
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.Numerics

$USER_AGENTS = @(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0"
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:121.0) Gecko/20100101 Firefox/121.0"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36 Edg/121.0.0.0"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 OPR/106.0.0.0"
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1"
)

function Test-FileNewer($src, $snap) {
    if (!(Test-Path -LiteralPath $snap)) { return $true }
    return ((Get-Item -LiteralPath $src).LastWriteTimeUtc -gt (Get-Item -LiteralPath $snap).LastWriteTimeUtc)
}

function Test-ZipFile($path) {
    if (!(Test-Path -LiteralPath $path)) { return $false }
    try { $z = [System.IO.Compression.ZipFile]::OpenRead($path); $ok = $z.Entries.Count -gt 0; $z.Dispose(); return $ok } catch { return $false }
}

function To-Num($v) {
    if ("$v" -match '^\s*([0-9]+(\.[0-9]+)?)') { return [double]$matches[1] }
    return 0
}

$script:spinMsg = ""; $script:spinStart = 0
function Start-Spinner($msg) {
    $script:spinMsg = $msg; $script:spinStart = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if (!$global:SILENT) { Write-Host -NoNewline "`r$ESC[K $ESC[33m[~]$ESC[0m $msg" }
}
function Update-Spinner($msg) {
    $script:spinMsg = $msg
    if (!$global:SILENT) { Write-Host -NoNewline "`r$ESC[K $ESC[33m[~]$ESC[0m $msg" }
}
function Stop-Spinner($ok, $msg) {
    $el = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $script:spinStart
    if (!$global:SILENT) {
        $mark = if ("$ok" -eq "0") { " $ESC[92m[" + [char]0x2713 + "]$ESC[0m" } else { " $ESC[31m[" + [char]0x2717 + "]$ESC[0m" }
        $out = "$mark $msg (${el}s)"
        Write-Host "`r$ESC[K$out"
        [System.IO.File]::AppendAllText($UI_STATE_FILE, "$out`n", [System.Text.Encoding]::UTF8)
    }
    Log-Event "INFO" "Task '$msg' finished in ${el}s (Status: $ok)."
}

function Get-QualityColor($q) {
    switch ([int](To-Num $q)) {
        0 { return "$ESC[90m" }; 1 { return "$ESC[97m" }; 2 { return "$ESC[32m" }; 3 { return "$ESC[36m" }
        4 { return "$ESC[35m" }; 5 { return "$ESC[33m" }; 6 { return "$ESC[38;5;214m" }
    }
    return "$ESC[0m"
}

function Merge-HistoryLines([string[]]$existing, [string[]]$incoming, [hashtable]$dbColors, [switch]$MaxScans) {
    $out = New-Object System.Collections.Generic.List[string]
    $order = New-Object System.Collections.Generic.List[string]
    $rows = @{}
    foreach ($raw in @($existing) + @($incoming)) {
        if ($null -eq $raw) { continue }
        $line = $raw.TrimEnd("`r")
        $f = $line.Split('|')
        if ($f[0] -ne "HISTORY") { if ($line -ne "") { $out.Add($line) }; continue }
        $nf = $f.Length
        if ($f[$nf - 1] -match '^[0-9]+$') { $scans = [int]$f[$nf - 1]; $src = $f[$nf - 2] } else { $scans = 1; $src = $f[$nf - 1] }
        if ($src -match '^(Unknown|\[Unknown\])$' -or $src -eq "") { $src = "TTC" }
        if ($nf -lt 13) { $f = $f + (,"" * (13 - $nf)) }
        $kiosk = $f[10]
        $uid = "$($f[5])|$($f[2])|$($f[3])|$($f[4])|$src"
        $ts = To-Num $f[1]
        $buyer = $f[7]; $seller = $f[8]; $guild = $f[9]
        $color = $dbColors[$f[5]]
        if (!$color) { $color = $f[11]; if (!$color.StartsWith("$ESC[")) { $color = "$ESC[0m" } }
        if (!$rows.ContainsKey($uid)) {
            $order.Add($uid)
            $rows[$uid] = @{ TS = $ts; Name = $f[6]; Buyer = $buyer; Seller = $seller; Guild = $guild; Kiosk = $kiosk; Color = $color; Scans = $scans }
        } else {
            $r = $rows[$uid]
            if ($ts -gt $r.TS) { $r.TS = $ts }
            if ($buyer -ne "" -and $r.Buyer.IndexOf($buyer) -lt 0) { $r.Buyer = if ($r.Buyer -eq "") { $buyer } else { "$($r.Buyer), $buyer" } }
            if ($seller -ne "" -and $r.Seller.IndexOf($seller) -lt 0) { $r.Seller = if ($r.Seller -eq "") { $seller } else { "$($r.Seller), $seller" } }
            if ($guild -ne "" -and $r.Guild.IndexOf($guild) -lt 0) { $r.Guild = if ($r.Guild -eq "") { $guild } else { "$($r.Guild), $guild" } }
            if ($kiosk -ne "" -and $r.Kiosk.IndexOf($kiosk) -lt 0) { $r.Kiosk = if ($r.Kiosk -eq "") { $kiosk } else { "$($r.Kiosk), $kiosk" } }
            if ($MaxScans) { if ($scans -gt $r.Scans) { $r.Scans = $scans } } else { $r.Scans += $scans }
        }
    }
    foreach ($uid in $order) {
        $p = $uid.Split('|'); $r = $rows[$uid]
        $out.Add("HISTORY|$([long]$r.TS)|$($p[1])|$($p[2])|$($p[3])|$($p[0])|$($r.Name)|$($r.Buyer)|$($r.Seller)|$($r.Guild)|$($r.Kiosk)|$($r.Color)|$($p[4])|$($r.Scans)")
    }
    return ,$out.ToArray()
}

function Merge-History($newLines) {
    if (!$newLines -or @($newLines).Count -eq 0) { return }
    if (!(Test-Path $HIST_FILE)) { New-Item -ItemType File -Force -Path $HIST_FILE | Out-Null }
    $dbColors = @{}
    if (Test-Path $DB_FILE) {
        foreach ($l in [System.IO.File]::ReadLines($DB_FILE)) {
            $p = $l.Split('|')
            if ($p[0] -match '^[0-9]+$' -and $p.Length -ge 2) { $dbColors[$p[0]] = Get-QualityColor $p[1] }
        }
    }
    $merged = Merge-HistoryLines ([System.IO.File]::ReadAllLines($HIST_FILE)) @($newLines) $dbColors
    if ($merged.Count -gt 0) { [System.IO.File]::WriteAllLines($HIST_FILE, $merged, (New-Object System.Text.UTF8Encoding $false)) }
}

function Merge-TemplateHistory([string]$histFile, [string]$templateFile, [string]$ver) {
    $dbColors = @{}
    if (Test-Path $DB_FILE) {
        foreach ($l in [System.IO.File]::ReadLines($DB_FILE)) {
            $p = $l.Split('|')
            if ($p[0] -match '^[0-9]+$' -and $p.Length -ge 2) { $dbColors[$p[0]] = Get-QualityColor $p[1] }
        }
    }
    $existing = if (Test-Path -LiteralPath $histFile) { @([System.IO.File]::ReadAllLines($histFile) | Where-Object { !$_.StartsWith("#HISTORY VERSION:") }) } else { @() }
    $incoming = @([System.IO.File]::ReadAllLines($templateFile) | Where-Object { $_.StartsWith("HISTORY|") })
    $lines = Merge-HistoryLines $existing $incoming $dbColors -MaxScans
    $merged = @("#HISTORY VERSION: $ver") + $lines
    [System.IO.File]::WriteAllText($histFile, ($merged -join "`n") + "`n", (New-Object System.Text.UTF8Encoding $false))
}

function Format-Fixed([double]$x, [int]$d) {
    $bits = [BitConverter]::DoubleToInt64Bits($x)
    $neg = $bits -lt 0
    $e = [int](($bits -shr 52) -band 0x7FF)
    $m = [System.Numerics.BigInteger]($bits -band 0xFFFFFFFFFFFFF)
    if ($e -eq 0) { $e = 1 } else { $m += [System.Numerics.BigInteger]::Pow(2, 52) }
    $e -= 1075
    $num = $m * [System.Numerics.BigInteger]::Pow(10, $d)
    if ($e -ge 0) {
        $q = $num * [System.Numerics.BigInteger]::Pow(2, $e)
    } else {
        $den = [System.Numerics.BigInteger]::Pow(2, -$e)
        $r = [System.Numerics.BigInteger]::Zero
        $q = [System.Numerics.BigInteger]::DivRem($num, $den, [ref]$r)
        $c = [System.Numerics.BigInteger]::Compare($r * 2, $den)
        if ($c -gt 0 -or ($c -eq 0 -and !$q.IsEven)) { $q += 1 }
    }
    $s = $q.ToString().PadLeft($d + 1, '0')
    if ($d -gt 0) { $s = $s.Substring(0, $s.Length - $d) + "." + $s.Substring($s.Length - $d) }
    if ($neg -and !$q.IsZero) { $s = "-" + $s }
    return $s
}

function To-LowerAscii([string]$s) {
    if (!$s) { return "" }
    $b = $s.ToCharArray()
    for ($i = 0; $i -lt $b.Length; $i++) { if ($b[$i] -ge 'A' -and $b[$i] -le 'Z') { $b[$i] = [char]([int]$b[$i] + 32) } }
    return -join $b
}
$global:IS_DESKTOP = $false; $global:FORCE_SETUP = $false
for ($i = 0; $i -lt $parsedArgs.Count; $i++) {
    switch ($parsedArgs[$i]) {
        "--silent" { $global:SILENT = $true }
        "--auto" { $global:AUTO_PATH = $true }
        "--na" { $global:AUTO_SRV = "1" }
        "--eu" { $global:AUTO_SRV = "2" }
        "--both" { $global:AUTO_SRV = "3" }
        "--loop" { $global:AUTO_MODE = "2" }
        "--once" { $global:AUTO_MODE = "1" }
        "--addon-dir" { if ($i + 1 -lt $parsedArgs.Count) { $i++; $global:ADDON_DIR = $parsedArgs[$i] } }
        "--desktop" { $global:IS_DESKTOP = $true }
        "--setup" {
            Remove-Item -LiteralPath $CONFIG_FILE -Force -ErrorAction SilentlyContinue
            $global:SETUP_COMPLETE = $false; $global:FORCE_SETUP = $true
        }
    }
}

if ($global:IS_STEAM_LAUNCH -and !$parsedArgs.Contains("--silent")) { $global:SILENT = $false }
if (!$IS_STEAM_LAUNCH -and !$IS_TASK) { $global:SILENT = $false }
if ($IS_STEAM_LAUNCH -and $SILENT) { $global:ENABLE_NOTIFS = $true }

function auto_scan_addons {
    Write-Host "$ESC[0;34mScanning default locations and drives for Addons folder...$ESC[0m"
    $docs = [Environment]::GetFolderPath("MyDocuments")
    $publicDocs = [Environment]::GetFolderPath("CommonDocuments")
    $oneDrive = $env:OneDrive

    $quickPaths = @(
        "$docs\Elder Scrolls Online\live\AddOns",
        "$oneDrive\Documents\Elder Scrolls Online\live\AddOns",
        "$publicDocs\Elder Scrolls Online\live\AddOns"
    )

    foreach ($p in $quickPaths) {
        if (Test-Path $p) {
            $liveDir = (Get-Item $p).Parent.FullName
            if ((Test-Path "$liveDir\UserSettings.txt") -and (Test-Path "$liveDir\AddOnSettings.txt")) { return $p }
        }
    }
    
    Log-Event "INFO" "auto_scan_addons: Performing deep drive scan"
    $drives = Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Root
    $suffixes = @("Documents\Elder Scrolls Online\live\AddOns", "*\Documents\Elder Scrolls Online\live\AddOns", "Elder Scrolls Online\live\AddOns", "*\Elder Scrolls Online\live\AddOns", "*\*\Elder Scrolls Online\live\AddOns", "live\AddOns", "*\live\AddOns", "*\*\live\AddOns")

    foreach ($drive in $drives) {
        foreach ($s in $suffixes) {
            $checkPath = Join-Path $drive $s
            $found = Resolve-Path $checkPath -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                $liveDir = (Get-Item $found.Path).Parent.FullName
                if ((Test-Path "$liveDir\UserSettings.txt") -and (Test-Path "$liveDir\AddOnSettings.txt")) { return $found.Path }
            }
        }
    }
    return ""
}

function Merge-LaunchOptions([string]$cur, [string]$ls) {
    $pfx = [regex]::Replace($ls, '\s*%command%\s*$', '', 'IgnoreCase')
    $keep = @()
    foreach ($seg in [regex]::Split($cur, '\s+&(?=\s|$)')) {
        $seg = [regex]::Replace($seg, '\s*cmd\s+/c\s+start\b.*Tamriel_Trade_Center.*$', '', 'IgnoreCase, Singleline').Trim()
        if ($seg.Length -gt 0) { $keep += $seg }
    }
    $n = @($keep | Where-Object { $_ -match '%command%' }).Count
    $keep = @($keep | Where-Object { if ($_ -match '^%command%$' -and $n -gt 1) { $n--; $false } else { $true } })
    $rest = $keep -join ' & '
    if ($rest -eq '') { return "$pfx %command%" }
    if ($rest -match '%command%') { return "$pfx $rest" }
    return "$pfx %command% $rest"
}

function run_setup {
    [ConsoleConfig]::RestoreWindow()
    Clear-Host
    Write-Host "`n$ESC[0;33m--- Initial Setup & Configuration ---$ESC[0m"
    Log-Event "INFO" "Starting initial setup process."

    if ($CURRENT_DIR -ne $TARGET_DIR) {
        Copy-Item -Path $FULL_SCRIPT_PATH -Destination "$TARGET_DIR\$SCRIPT_NAME" -Force
        Write-Host "$ESC[0;32m[+] Script successfully copied/updated in Documents folder: $ESC[0;35m$TARGET_DIR$ESC[0m"
        Log-Event "INFO" "Script installed to target directory: $TARGET_DIR"
    } else {
        Write-Host "$ESC[0;36m-> Script is already running from the Documents folder.$ESC[0m`n"
    }

    Write-Host "`n$ESC[0;33m1. Which server do you play on? $ESC[0;32m(For TTC Pricetable Updates)$ESC[0m"
    Write-Host "1) North America (NA)`n2) Europe (EU)`n3) Both (NA & EU)"
    $global:AUTO_SRV = Read-Host "$ESC[0;34mChoice [1-3]$ESC[0m"

    Write-Host "`n$ESC[0;33m2. Do you want the terminal to be visible when launching via Steam?$ESC[0m"
    Write-Host "1) Show Terminal $ESC[38;5;212m(Default: Verbose visible output)$ESC[0m"
    Write-Host "2) Hide Terminal $ESC[0;90m(Invisible background hidden)$ESC[0m"
    $ans = Read-Host "$ESC[0;34mChoice [1-2]$ESC[0m"
    if ($ans -eq "2") { $global:SILENT = $true } else { $global:SILENT = $false }

    Write-Host "`n$ESC[0;33m3. How should the script run during gameplay?$ESC[0m"
    Write-Host "1) Run once and close immediately"
    Write-Host "2) Loop continuously $ESC[0;32m(Default: Checks local file & server status every 60 minutes to avoid server rate-limit)$ESC[0m"
    $global:AUTO_MODE = Read-Host "$ESC[0;34mChoice [1-2]$ESC[0m"
    if ([string]::IsNullOrWhiteSpace($global:AUTO_MODE)) { $global:AUTO_MODE = "2" }

    Write-Host "`n$ESC[0;33m4. Extract & Display Data $ESC[0;35m(Requires Creation of Database)$ESC[0m"
    Write-Host "$ESC[0;32mDo you want to extract and display item names/sales on the terminal?$ESC[0m"
    Write-Host "1) Yes $ESC[38;5;212m(Default: Extract, Display, and build WTTC_Database.db)$ESC[0m"
    Write-Host "2) No $ESC[0;90m(Just upload the files instantly)$ESC[0m"
    $display_choice = Read-Host "$ESC[0;34mChoice [1-2]$ESC[0m"
    if ($display_choice -eq "2") { $global:ENABLE_DISPLAY = $false } else { $global:ENABLE_DISPLAY = $true }

    Write-Host "`n$ESC[0;33m5. Addon Folder Location$ESC[0m"
    if ($ADDON_DIR -and (Test-Path $ADDON_DIR)) {
        Write-Host "$ESC[0;32m[+] Found Saved Addons Directory at: $ESC[0;35m$ADDON_DIR$ESC[0m"
        $FOUND_ADDONS = $ADDON_DIR
    } else {
        $FOUND_ADDONS = auto_scan_addons
        if ($FOUND_ADDONS) {
            Write-Host "$ESC[0;32m[+] Found Addons folder at: $ESC[0;35m$FOUND_ADDONS$ESC[0m"
            $ans = Read-Host "Is this the correct location? (y/N)"
            if ($ans -notmatch '^[Yy]$') { $FOUND_ADDONS = Read-Host "$ESC[0;34mEnter full custom path to AddOns folder: $ESC[0m" }
        } else {
            Write-Host "$ESC[0;31m[-] Could not find AddOns automatically.$ESC[0m"
            $FOUND_ADDONS = Read-Host "$ESC[0;34mEnter full custom path to AddOns folder: $ESC[0m"
        }
    }
    $global:ADDON_DIR = $FOUND_ADDONS
    Log-Event "INFO" "Addon directory set to: $ADDON_DIR"

    Write-Host "`n$ESC[0;33m6. Enable Native System Notifications?$ESC[0m"
    Write-Host "1) Yes $ESC[38;5;212m(Summarizes updates, respects Do Not Disturb)$ESC[0m"
    Write-Host "2) No $ESC[0;32m(Default)$ESC[0m"
    $ans = Read-Host "$ESC[0;34mChoice [1-2]$ESC[0m"
    $global:ENABLE_NOTIFS = if ($ans -eq "1") {$true} else {$false}

    Write-Host "`n$ESC[0;33m7. Logging Level$ESC[0m"
    Write-Host "Creates a log file at $ESC[0;35m$LOG_FILE$ESC[0m"
    Write-Host "1) Simple Logging $ESC[0;32m(Default: records script events)$ESC[0m"
    Write-Host "2) Detailed Logging $ESC[0;31m(WARNING: records script events and item extraction events)$ESC[0m"
    $log_choice = Read-Host "$ESC[0;34mChoice [1-2]$ESC[0m"
    if ($log_choice -eq "2") { $global:LOG_MODE = "detailed" } else { $global:LOG_MODE = "simple" }

    Write-Host "`n$ESC[0;33m8. ESO-Hub Integration $ESC[0;32m(Optional)$ESC[0m"
    Write-Host "`n$ESC[0;31m(DO NOT SHARE YOUR TOKENS TO ANYONE)$ESC[0m"
    Write-Host "1) Log in with Username and Password $ESC[0;32m(Fetches API Token securely, and deletes your credentials.)$ESC[0m"
    Write-Host "2) Manually enter API Token $ESC[38;5;212m(If you already know your token)$ESC[0m"
    Write-Host "3) Skip / $ESC[0;90mUpload Anonymously No Login$ESC[0m $ESC[0;32m(Default)$ESC[0m"
    $eh_choice = Read-Host "$ESC[0;34mChoice [1-3]$ESC[0m"

    $global:EH_USER_TOKEN = ""
    if ($eh_choice -eq "1") {
        $EH_USER = (Read-Host "ESO-Hub Username").Trim()
        try {
            $securePass = Read-Host "ESO-Hub Password" -AsSecureString
            $EH_PASS = (New-Object System.Management.Automation.PSCredential("user", $securePass)).GetNetworkCredential().Password.Trim()
        } catch { $EH_PASS = "" }

        if ([string]::IsNullOrEmpty($EH_PASS)) {
            Write-Host "$ESC[0;31m[-] Invalid password input. Falling back to anonymous mode.$ESC[0m"
        } else {
            Write-Host "`n$ESC[36mAuthenticating with ESO-Hub API...$ESC[0m"
            $curlArgs = @("-s", "-X", "POST", "-H", "User-Agent: ESOHubClient/1.0.9", "--data-urlencode", "client_system=windows", "--data-urlencode", "client_version=1.0.9", "--data-urlencode", "client_version_int=1009", "--data-urlencode", "lang=en", "--data-urlencode", "username=$EH_USER", "--data-urlencode", "password=$EH_PASS", "https://data.eso-hub.com/v1/api/login")
            try {
                $loginRespRaw = (& curl.exe $curlArgs) -join ""
                if ($loginRespRaw -match '"token"\s*:\s*"([^"]+)"') {
                    $global:EH_USER_TOKEN = $matches[1]
                    Write-Host "$ESC[0;32m[+] Successfully logged in! Token saved securely.$ESC[0m"
                    Log-Event "INFO" "ESO-Hub user token successfully generated via API."
                } else {
                    Write-Host "$ESC[0;31m[-] Login failed. Please check your credentials. Falling back to anonymous mode.$ESC[0m"
                    Log-Event "ERROR" "ESO-Hub login failed via API."
                }
            } catch { Write-Host "$ESC[0;31m[-] Network error reaching API. Falling back to anonymous mode.$ESC[0m" }
        }
        $EH_USER = ""; $EH_PASS = ""; $securePass = $null
    } elseif ($eh_choice -eq "2") {
        $global:EH_USER_TOKEN = Read-Host "Token"
        Log-Event "INFO" "User manually provided an ESO-Hub API token."
    }

    Write-Host "`n$ESC[0;33m9. Keep Your Other Add-Ons Up To Date $ESC[0;32m(Optional)$ESC[0m"
    Write-Host "$ESC[0;32mAlso check ESOUI for newer versions of the add-ons and libraries in your AddOns folder and install them?$ESC[0m"
    Write-Host "$ESC[0;90m(Checks every 6 hours, keeps the previous version in $TARGET_DIR\Backups\AddOns, skips linked folders)$ESC[0m"
    Write-Host "1) Yes"
    Write-Host "2) No $ESC[0;32m(Default)$ESC[0m"
    $ans = Read-Host "$ESC[0;34mChoice [1-2]$ESC[0m"
    $global:ENABLE_ADDON_UPDATES = ($ans -eq "1")

    $DesktopPath = [Environment]::GetFolderPath("Desktop")
    $startupPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    $startupShortcut = "$startupPath\Windows_TTC_Updater.lnk"
    $vbsLauncher = "$TARGET_DIR\wttc_launcher.vbs"
    
    if (Test-Path "$DesktopPath\Windows Tamriel Trade Center.lnk") { Remove-Item "$DesktopPath\Windows Tamriel Trade Center.lnk" -Force -ErrorAction SilentlyContinue }

    Write-Host "`n$ESC[0;33m10. Run automatically in the background when PC Starts?$ESC[0m"
    Write-Host "`n$ESC[0;33mOptions that require to delete Scheduled Task will always ask for UAC (Admin Access)$ESC[0m"
    Write-Host "1) Yes - Advanced Mode $ESC[31m(Requires Admin, completely invisible Scheduled Task)$ESC[0m"
    Write-Host "2) Yes - Standard Mode $ESC[38;5;212m(No Admin, places hidden shortcut in Startup folder)$ESC[0m"
    Write-Host "3) No  - $ESC[90m(Do not run at startup, cleans up previous startup choices)$ESC[0m"
    $ans = Read-Host "Choice [1-3]"
    
    if ($ans -eq "1") { 
        $global:STARTUP_MODE = "1" 
        if (Test-Path $startupShortcut) { Remove-Item $startupShortcut -Force -ErrorAction SilentlyContinue }
    }
    elseif ($ans -eq "2") { 
        $global:STARTUP_MODE = "2" 
        $tasksToRemove = Get-ScheduledTask | Where-Object {$_.TaskName -match "Windows_TTC_Updater|Windows Tamriel Trade Center"} -ErrorAction SilentlyContinue
        if ($tasksToRemove) {
            Write-Host " -> Removing old Scheduled Task (Requires Admin to unregister)..." -ForegroundColor Yellow
            $delCmd = "Get-ScheduledTask | Where-Object {`$_.TaskName -match 'Windows_TTC_Updater|Windows Tamriel Trade Center'} | Unregister-ScheduledTask -Confirm:`$false"
            $encCmd = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($delCmd))
            try { Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand $encCmd" -Wait -ErrorAction SilentlyContinue } catch {}
        }
        if (Test-Path $vbsLauncher) { Remove-Item $vbsLauncher -Force -ErrorAction SilentlyContinue }
    }
    else { 
         $global:STARTUP_MODE = "0" 
        if (Test-Path $startupShortcut) { Remove-Item $startupShortcut -Force -ErrorAction SilentlyContinue }
        $tasksToRemove = Get-ScheduledTask | Where-Object {$_.TaskName -match "Windows_TTC_Updater|Windows Tamriel Trade Center"} -ErrorAction SilentlyContinue
        if ($tasksToRemove) {
            Write-Host " -> Removing old Scheduled Task (Requires Admin to unregister)..." -ForegroundColor Yellow
            $delCmd = "Get-ScheduledTask | Where-Object {`$_.TaskName -match 'Windows_TTC_Updater|Windows Tamriel Trade Center'} | Unregister-ScheduledTask -Confirm:`$false"
            $encCmd = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($delCmd))
            try { Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand $encCmd" -Wait -ErrorAction SilentlyContinue } catch {}
        }
        if (Test-Path $vbsLauncher) { Remove-Item $vbsLauncher -Force -ErrorAction SilentlyContinue }
    }

    if ($global:STARTUP_MODE -eq "1") {
        Write-Host "`n -> Registering Scheduled Task & Event Log $ESC[32m(Please click '$ESC[33mYes$ESC[32m' on the Admin prompt)...$ESC[0m"
        $vbsContent = 'Set objShell = CreateObject("WScript.Shell")' + "`r`n" + 'objShell.Run """' + "$TARGET_DIR\$SCRIPT_NAME" + '"" --silent --loop --task", 0, False'
        Set-Content -Path $vbsLauncher -Value $vbsContent -Encoding ASCII -Force
        
        $taskScript = @"
try { if (![System.Diagnostics.EventLog]::SourceExists('$APP_TITLE')) { New-EventLog -LogName '$APP_TITLE' -Source '$APP_TITLE' -ErrorAction SilentlyContinue } } catch {}
`$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "`"`"$vbsLauncher`"`""
`$trigger = New-ScheduledTaskTrigger -AtLogon
`$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable
Get-ScheduledTask | Where-Object { `$_.TaskName -match 'Windows_TTC_Updater|Windows Tamriel Trade Center' } | Unregister-ScheduledTask -Confirm:`$false -ErrorAction SilentlyContinue
Register-ScheduledTask -Action `$action -Trigger `$trigger -Settings `$settings -TaskName '$TASK_NAME' -Description 'Cross-Platform Auto-Updater for TTC, HarvestMap, ESO-Hub & ESOUI. Created by @APHONIC' -Force
"@
        $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($taskScript))
        try { Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand $encodedCommand" -Wait -ErrorAction Stop } catch {}
        
        Start-Sleep -Seconds 2
        if (Get-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue) {
            Write-Host "$ESC[0;32m[+] Background Startup Task created successfully.$ESC[0m"
            Log-Event "INFO" "Background Startup Task registered."
        } else {
            Write-Host "$ESC[0;31m[-] Failed to get proper admin privileges or action was canceled.$ESC[0m"
            Write-Host "$ESC[0;33m -> Falling back to Windows Startup Folder method.$ESC[0m"
            Log-Event "WARN" "Failed to elevate. Used Fallback Startup Shortcut."
            try {
                $WshShell = New-Object -comObject WScript.Shell
                $fallbackShortcut = $WshShell.CreateShortcut($startupShortcut)
                $fallbackShortcut.TargetPath = "powershell.exe"
                $fallbackShortcut.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -Command `"Start-Process -FilePath '$TARGET_DIR\$SCRIPT_NAME' -ArgumentList '--silent --loop --task' -WindowStyle Hidden`""
                $fallbackShortcut.WindowStyle = 7
                if (Test-Path $ICON_FILE) { $fallbackShortcut.IconLocation = $ICON_FILE }
                $fallbackShortcut.Save()
                Write-Host "$ESC[0;32m[+] Fallback startup shortcut created successfully at: $startupPath $ESC[0m"
            } catch { Write-Host "$ESC[0;31m[-] Failed to create fallback shortcut.$ESC[0m" }
        }
    } elseif ($global:STARTUP_MODE -eq "2") {
        Write-Host "`n -> Creating Startup Shortcut..."
        try {
            $WshShell = New-Object -comObject WScript.Shell
            $fallbackShortcut = $WshShell.CreateShortcut($startupShortcut)
            $fallbackShortcut.TargetPath = "powershell.exe"
            $fallbackShortcut.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -Command `"Start-Process -FilePath '$TARGET_DIR\$SCRIPT_NAME' -ArgumentList '--silent --loop --task' -WindowStyle Hidden`""
            $fallbackShortcut.WindowStyle = 7
            if (Test-Path $ICON_FILE) { $fallbackShortcut.IconLocation = $ICON_FILE }
            $fallbackShortcut.Save()
            Write-Host "$ESC[0;32m[+] Startup shortcut created successfully.$ESC[0m"
            Log-Event "INFO" "Startup Shortcut registered."
        } catch { Write-Host "$ESC[0;31m[-] Failed to create startup shortcut.$ESC[0m" }
    } else {
        Write-Host "`n -> Skipping startup registration & ensuring clean state.$ESC[0m"
    }
    
    $global:SETUP_COMPLETE = $true
    save_config
    Log-Event "INFO" "Setup complete. Configuration saved. Log Mode: $LOG_MODE"

    Write-Host "`n$ESC[0;33m11. Desktop Shortcut$ESC[0m"
    $ans = Read-Host "Create a desktop shortcut? (Y/n)"
    if ([string]::IsNullOrWhiteSpace($ans)) { $ans = "y" }
    
    $SHORTCUT_SRV_FLAG = if ($AUTO_SRV -eq "3") {"--both"} elseif ($AUTO_SRV -eq "2") {"--eu"} else {"--na"}
    $LOOP_FLAG = if ($AUTO_MODE -eq "2") {"--loop"} else {"--once"}

    if ($ans -match '^[Yy]$') {
        Log-Event "INFO" "User opted to create a desktop shortcut."
        Write-Host " -> Creating desktop icon..."
        try {
            $WshShell = New-Object -comObject WScript.Shell
            $Shortcut = $WshShell.CreateShortcut("$DesktopPath\Windows Tamriel Trade Center.lnk")
            $Shortcut.TargetPath = "$TARGET_DIR\$SCRIPT_NAME"
            $Shortcut.Arguments = "$SHORTCUT_SRV_FLAG $LOOP_FLAG --desktop"
            $Shortcut.WindowStyle = 1
            if (Test-Path $ICON_FILE) { $Shortcut.IconLocation = $ICON_FILE }
            $Shortcut.Save()
            Write-Host "$ESC[0;32m[+] Windows desktop shortcut installed.$ESC[0m"
        } catch { Write-Host "$ESC[0;31m[-] Failed to create shortcut.$ESC[0m" }
    }

    Write-Host "`n$ESC[0;92m================ SETUP COMPLETE ================$ESC[0m"
    Write-Host "To run this automatically alongside your game, copy this string into your $ESC[1mSteam Launch Options$ESC[0m:`n"
    
    $HIDE_FLAG = if ($SILENT) { "--silent" } else { "" }
    $LAUNCH_CMD = "cmd /c start `"`" `"$TARGET_DIR\$SCRIPT_NAME`" $SHORTCUT_SRV_FLAG $LOOP_FLAG $HIDE_FLAG --steam & %command%"
    Write-Host "$ESC[0;104m $LAUNCH_CMD $ESC[0m`n"
    
    Write-Host "$ESC[0;33m12. Steam Launch Options$ESC[0m"
    Write-Host "$ESC[0;32mWould you like this script to automatically inject the Launch Command into your Steam configuration?$ESC[0m"
    Write-Host "$ESC[31m(WARNING: Steam MUST be closed to do this. We can close it for you.)$ESC[0m"
    $ans = Read-Host "Apply automatically? (Y/n)"
    if ([string]::IsNullOrWhiteSpace($ans)) { $ans = "y" }
    
    if ($ans -match '^[Yy]$') {
        Log-Event "INFO" "User opted for automatic Steam Launch Option injection."
        $pids = Get-Process "steam" -ErrorAction SilentlyContinue
        if ($pids) {
            Write-Host "$ESC[0;33m[!] Steam is running. Closing Steam to safely inject launch options...$ESC[0m"
            Stop-Process -Name "steam" -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 5
        }
        
        $backupDir = Join-Path $TARGET_DIR "Backups"
        if (!(Test-Path $backupDir)) { New-Item -ItemType Directory -Force -Path $backupDir | Out-Null }
        
        $confPaths = @("${env:ProgramFiles(x86)}\Steam\userdata\*\config\localconfig.vdf", "$env:ProgramFiles\Steam\userdata\*\config\localconfig.vdf")
        $confFiles = Get-ChildItem -Path $confPaths -ErrorAction SilentlyContinue

        foreach ($conf in $confFiles) {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $steamId = (Get-Item $conf.FullName).Directory.Parent.Name
            $backupFile = Join-Path $backupDir "localconfig_${steamId}_${timestamp}.vdf"
            Copy-Item -Path $conf.FullName -Destination $backupFile -Force
            Write-Host "$ESC[0;36m-> Backed up Steam config to: $backupFile$ESC[0m"

            Write-Host "$ESC[0;36m-> Injecting Launch Options into ESO config (AppID: 306130)...$ESC[0m"
            $text = [System.IO.File]::ReadAllText($conf.FullName)
            
            $escapedStr = $LAUNCH_CMD.Replace('\', '\\').Replace('"', '\"')
            
            if ($text -match '"306130"\s*\{') {
                $optRx = [regex]'("306130"\s*\{[^}]*?"LaunchOptions"\s*)"((?:\\"|[^"])*)"'
                if ($optRx.IsMatch($text)) {
                    $text = $optRx.Replace($text, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $m.Groups[1].Value + '"' + (Merge-LaunchOptions $m.Groups[2].Value $escapedStr) + '"' }, 1)
                } else {
                    $text = [regex]::Replace($text, '("306130"\s*\{)', "`${1}`n`t`t`t`t`"LaunchOptions`"`t`t`"$escapedStr`"")
                }
            } else {
                $text = [regex]::Replace($text, '("apps"\s*\{)', "`${1}`n`t`t`t`"306130`"`n`t`t`t{`n`t`t`t`t`"LaunchOptions`"`t`t`"$escapedStr`"`n`t`t`t}")
            }
            
            $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
            [System.IO.File]::WriteAllText($conf.FullName, $text, $Utf8NoBomEncoding)
            Write-Host "$ESC[0;32m[+] Successfully injected Launch Options into Steam!$ESC[0m"
            Log-Event "INFO" "Launch options successfully merged and injected into $($conf.FullName)"
        }
        Write-Host "$ESC[0;33m[!] Restarting Steam...$ESC[0m"
        Start-Process "steam://open/main" -ErrorAction SilentlyContinue
    }
    
    $startNow = Read-Host "$ESC[38;5;212mPress Enter to start the updater now...$ESC[0m"
    $global:SILENT = $false
}

$INSTALLED_SCRIPT = "$TARGET_DIR\$SCRIPT_NAME"

if ($global:FORCE_SETUP) {
    Log-Event "INFO" "Setup requested with --setup."
    run_setup
} elseif ($SETUP_COMPLETE -and !$HAS_ARGS) {
    if ((Test-Path $INSTALLED_SCRIPT) -and (Test-Path $CONFIG_FILE)) {
        Clear-Host
        Write-Host "$ESC[0;32m[+] Configuration found! Using saved settings.$ESC[0m"
        Write-Host "$ESC[0;36m-> Press 'y' to re-run setup, or wait 5 seconds to continue automatically...`n$ESC[0m"
        
        $timeoutSeconds = 5
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $runSetup = $false
        
        while ($sw.Elapsed.TotalSeconds -lt $timeoutSeconds) {
            [ConsoleConfig]::CheckMinimizedAndHide() | Out-Null
            [System.Windows.Forms.Application]::DoEvents()
            
            if ([Console]::KeyAvailable) { 
                $key = [Console]::ReadKey($true)
                if ($key.KeyChar -match '^[Yy]$') {
                    $runSetup = $true
                }
                break 
            }
            Start-Sleep -Milliseconds 50
        }
        $sw.Stop()
        
        if ($runSetup) { run_setup } 
        else {
            if ($CURRENT_DIR -ne $TARGET_DIR) { Copy-Item -Path $FULL_SCRIPT_PATH -Destination "$TARGET_DIR\$SCRIPT_NAME" -Force }
        }
    } else { run_setup }
} elseif (!$SETUP_COMPLETE -and !$HAS_ARGS) { run_setup }

$global:k_dict = @{}
function Init-Kiosk-Dict {
    $raw = @{
        "0"="Belkarth|309.702%3B339.015"
        "1"="Belkarth Outlaws Refuge|397.782%3B384.003"
        "2"="The Hollow City|335.049%3B502.183"
        "3"="Haj Uxith|664.037%3B1686.503"
        "4"="Court of Contempt|1194.908%3B1257.149"
        "5"="Rawl'kha|479.207%3B636.837"
        "6"="Rawl'kha Outlaws Refuge|501.386%3B452.438"
        "7"="Vinedusk|397.082%3B865.97"
        "8"="Dune|398.415%3B310.5"
        "9"="Baandari Trading Post|834.059%3B700.203"
        "10"="Dra'bul|588.829%3B888.956"
        "11"="Valeguard|1173.63%3B785.94"
        "12"="Velyn Harbor Outlaws Refuge|494.732%3B274.696"
        "13"="Marbruk|772.277%3B700.203"
        "14"="Marbruk Outlaws Refuge|424.395%3B351.686"
        "15"="Verrant Morass|995.35%3B581.739"
        "16"="Greenheart|1110.89%3B1729.019"
        "17"="Elden Root|620.197%3B682.777"
        "18"="Elden Root Outlaws Refuge|177.267%3B314.617"
        "19"="Cormount|1107.491%3B528.163"
        "20"="Southpoint|884.46%3B1541.567"
        "21"="Skywatch|141.782%3B486.342"
        "22"="Firsthold|758.349%3B436.227"
        "23"="Vulkhel Guard|692.355%3B701.774"
        "24"="Vulkhel Guard Outlaws Refuge|360.712%3B403.013"
        "25"="Mistral|499.801%3B563.965"
        "26"="Evermore|753.425%3B448.638"
        "27"="Evermore Outlaws Refuge|483.326%3B521.825"
        "28"="Bangkorai Pass|931.328%3B1085.287"
        "29"="Hallin's Stand|948.118%3B736.639"
        "30"="Sentinel|474.455%3B887.134"
        "31"="Sentinel Outlaws Refuge|272.316%3B447.686"
        "32"="Morwha's Bounty|592.539%3B1337.948"
        "33"="Bergama|1141.733%3B1237.474"
        "34"="Shornhelm|555.722%3B825.034"
        "35"="Shornhelm Outlaws Refuge|340.752%3B381.151"
        "36"="Hoarfrost Downs|441.188%3B755.649"
        "37"="Oldgate|947.927%3B1525.045"
        "38"="Wayrest|412.673%3B609.906"
        "39"="Wayrest Outlaws Refuge|420.594%3B446.735"
        "40"="Firebrand Keep|605.813%3B736.682"
        "41"="Koeglin Village|693.069%3B470.5"
        "42"="Daggerfall|480.792%3B389.708"
        "43"="Daggerfall Outlaws Refuge|435.801%3B402.062"
        "44"="Lion Guard Redoubt|1275.731%3B538.132"
        "45"="Wyrd Tree|832.354%3B1161.648"
        "46"="Stonetooth|490.296%3B845.946"
        "47"="Port Hunding|181.386%3B872.876"
        "48"="Riften|417.584%3B947.964"
        "49"="Riften Outlaws Refuge|295.128%3B405.864"
        "50"="Nimalten|666.138%3B594.064"
        "51"="Fallowstone Hall|640.792%3B556.045"
        "52"="Windhelm|700.99%3B492.678"
        "53"="Windhelm Outlaws Refuge|166.811%3B380.201"
        "54"="Voljar Meadery|867.256%3B695.033"
        "55"="Fort Amol|265.346%3B96.639"
        "56"="Stormhold|628.118%3B535.451"
        "57"="Stormhold Outlaws Refuge|317.94%3B351.686"
        "58"="Venomous Fens|459.7%3B777.556"
        "59"="Hissmir|650.118%3B1092.45"
        "60"="Mournhold|845.148%3B860.203"
        "61"="Mournhold Outlaws Refuge|305.584%3B515.171"
        "62"="Tal'Deic Grounds|1711.712%3B946.019"
        "63"="Muth Gnaar Hills|502.25%3B1153.052"
        "64"="Ebonheart|497.425%3B647.608"
        "65"="Kragenmoor|596.435%3B643.173"
        "66"="Davon's Watch|886.336%3B834.856"
        "67"="Davon's Watch Outlaws Refuge|520.395%3B345.983"
        "68"="Dhalmora|514.059%3B814.262"
        "69"="Bleakrock|699.5%3B622.905"
        "70"="Orsinium|659.801%3B510.104"
        "71"="Orsinium Outlaws Refuge|402.534%3B339.33"
        "72"="Morkul Stronghold|472.871%3B359.609"
        "73"="Thieves Den|381.623%3B287.052"
        "74"="Abah's Landing|575.841%3B795.253"
        "75"="Anvil|525.148%3B590.896"
        "76"="Kvatch|631.287%3B551.292"
        "77"="Anvil Outlaws Refuge|489.029%3B453.389"
        "78"="Vivec City|290.692%3B475.253"
        "79"="Vivec City Outlaws Refuge|311.287%3B630.181"
        "80"="Sadrith Mora|401.584%3B806.342"
        "81"="Balmora|659.801%3B953.668"
        "82"="Brass Fortress|622.747%3B787.782"
        "83"="Brass Fortress Outlaws Refuge|677.227%3B486.656"
        "84"="Lillandril|605.94%3B787.332"
        "85"="Shimmerene|368.921%3B881.274"
        "86"="Alinor|735.841%3B682.777"
        "87"="Alinor Outlaws Refuge|398.732%3B280.399"
        "88"="Lilmoth|580.593%3B646.342"
        "89"="Lilmoth Outlaws Refuge|256.158%3B478.102"
        "90"="Rimmen|282.772%3B620.995"
        "91"="Rimmen Outlaws Refuge|448.158%3B273.745"
        "92"="Senchal|518.811%3B518.025"
        "93"="Senchal Outlaws Refuge|338.851%3B420.122"
        "94"="Solitude|441.197%3B426.611"
        "95"="Solitude Outlaws Refuge|286.574%3B319.369"
        "96"="Markarth|745.346%3B782.579"
        "97"="Markarth Outlaws Refuge|298.93%3B496.161"
        "98"="Leyawiin|539.405%3B864.955"
        "99"="Leyawiin Outlaws Refuge|389.227%3B463.844"
        "100"="Fargrave|881.584%3B312.084"
        "101"="Fargrave Outlaws Refuge|244.752%3B440.082"
        "102"="Gonfalon Bay|430.098%3B486.342"
        "103"="Gonfalon Bay Outlaws Refuge|599.287%3B235.726"
        "104"="Vastyr|905.346%3B723.965"
        "105"="Vastyr Outlaws Refuge|477.623%3B533.231"
        "106"="Necrom|700.99%3B667.543"
        "107"="Necrom Outlaws Refuge|520.395%3B410.617"
        "108"="Skingrad|419.009%3B733.47"
        "109"="Skingrad Outlaws Refuge|372.118%3B457.191"
        "110"="Sunport|640.792%3B796.837"
        "111"="Sunport Outlaws Refuge|551.762%3B402.062"

        "Lejesha"="Bergama Wayshrine - Alik'r Desert|30"
        "Manidah"="Morwha's Bounty Wayshrine - Alik'r Desert|30"
        "Laknar"="Sentinel - Alik'r Desert|83"
        "Saymimah"="Sentinel - Alik'r Desert|83"
        "Uurwaerion"="Sentinel - Alik'r Desert|83"
        "Vinder Hlaran"="Sentinel - Alik'r Desert|83"
        "Yat"="Sentinel - Alik'r Desert|83"
        "Panersewen"="Firsthold Wayshrine - Auridon|143"
        "Cerweriell"="Skywatch - Auridon|545"
        "Ferzhela"="Skywatch - Auridon|545"
        "Guzg"="Skywatch - Auridon|545"
        "Lanirsare"="Skywatch - Auridon|545"
        "Renzaiq"="Skywatch - Auridon|545"
        "Carillda"="Vulkhel Guard - Auridon|243"
        "Galam Seleth"="Dhalmora - Bal Foyen|56"
        "Malirzzaka"="Bangkorai Pass Wayshrine - Bangkorai|20"
        "Arver Falos"="Evermore - Bangkorai|84"
        "Tilinarie"="Evermore - Bangkorai|84"
        "Values-Many-Things"="Evermore - Bangkorai|84"
        "Kaale"="Evermore - Bangkorai|84"
        "Zunlog"="Evermore - Bangkorai|84"
        "Glorgzorgo"="Hallin's Stand - Bangkorai|360"
        "Ghatrugh"="Stonetooth Fortress - Betnikh|649"
        "Amirudda"="Leyawiin - Blackwood|1940"
        "Dandras Omayn"="Leyawiin - Blackwood|1940"
        "Lhotahir"="Leyawiin - Blackwood|1940"
        "Sihrimaya"="Leyawiin - Blackwood|1940"
        "Shuruthikh"="Leyawiin - Blackwood|1940"
        "Praxedes Vestalis"="Leyawiin - Blackwood|1940"
        "Inishez"="Bleakrock Wayshrine - Bleakrock Isle|74"
        "Commerce Delegate"="Brass Fortress - Clockwork City|1348"
        "Ravam Sedas"="Brass Fortress - Clockwork City|1348"
        "Orstag"="Brass Fortress - Clockwork City|1348"
        "Noveni Adrano"="Brass Fortress - Clockwork City|1348"
        "Valowende"="Brass Fortress - Clockwork City|1348"
        "Shogarz"="Brass Fortress - Clockwork City|1348"
        "Harzdak"="Court of Contempt Wayshrine - Coldharbour|255"
        "Shuliish"="Haj Uxith Wayshrine - Coldharbour|255"
        "Nistyniel"="The Hollow City - Coldharbour|422"
        "Ramzasa"="The Hollow City - Coldharbour|422"
        "Balver Sarvani"="The Hollow City - Coldharbour|422"
        "Virwillaure"="The Hollow City - Coldharbour|422"
        "Donnaelain"="Belkarth - Craglorn|1131"
        "Glegokh"="Belkarth - Craglorn|1131"
        "Shelzaka"="Belkarth - Craglorn|1131"
        "Keen-Eyes"="Belkarth - Craglorn|1131"
        "Shuhasa"="Belkarth - Craglorn|1131"
        "Nelvon Galen"="Belkarth - Craglorn|1131"
        "Mengilwaen"="Belkarth - Craglorn|1131"
        "Endoriell"="Mournhold - Deshaan|205"
        "Through-Gilded-Eyes"="Mournhold - Deshaan|205"
        "Zarum"="Mournhold - Deshaan|205"
        "Gals Fendyn"="Mournhold - Deshaan|205"
        "Razgugul"="Mournhold - Deshaan|205"
        "Hayaia"="Mournhold - Deshaan|205"
        "Erwurlde"="Mournhold - Deshaan|205"
        "Feran Relenim"="Muth Gnaar Hills Wayshrine - Deshaan|13"
        "Telvon Arobar"="Tal'Deic Grounds Wayshrine - Deshaan|13"
        "Muslabliz"="Fort Amol - Eastmarch|578"
        "Alareth"="Voljar Meadery Wayshrine - Eastmarch|61"
        "Alisewen"="Windhelm - Eastmarch|160"
        "Celorien"="Windhelm - Eastmarch|160"
        "Dosa"="Windhelm - Eastmarch|160"
        "Deras Golathyn"="Windhelm - Eastmarch|160"
        "Ghogurz"="Windhelm - Eastmarch|160"
        "Bodsa Manas"="The Bazaar - Fargrave|2136"
        "Furnvekh"="The Bazaar - Fargrave|2136"
        "Livia Tappo"="The Bazaar - Fargrave|2136"
        "Ven"="The Bazaar - Fargrave|2136"
        "Vesakta"="The Bazaar - Fargrave|2136"
        "Zenelaz"="The Bazaar - Fargrave|2136"
        "Arzalaya"="Vastyr - Galen|2227"
        "Sharflekh"="Vastyr - Galen|2227"
        "Gei"="Vastyr - Galen|2227"
        "Stephenn Surilie"="Vastyr - Galen|2227"
        "Tildinfanya"="Vastyr - Galen|2227"
        "Var the Vague"="Vastyr - Galen|2227"
        "Sintilfalion"="Daggerfall - Glenumbra|63"
        "Murgoz"="Daggerfall - Glenumbra|63"
        "Khalatah"="Daggerfall - Glenumbra|63"
        "Faedre"="Daggerfall - Glenumbra|63"
        "Brara Hlaalo"="Daggerfall - Glenumbra|63"
        "Nameel"="Lion Guard Redoubt Wayshrine - Glenumbra|63"
        "Mogazgur"="Wyrd Tree Wayshrine - Glenumbra|63"
        "Daynas Sadrano"="Anvil - Gold Coast|1074"
        "Majhasur"="Anvil - Gold Coast|1074"
        "Onurai-Maht"="Anvil - Gold Coast|1074"
        "Erluramar"="Kvatch - Gold Coast|1064"
        "Farul"="Kvatch - Gold Coast|1064"
        "Zagh gro-Stugh"="Kvatch - Gold Coast|1064"
        "Nirywy"="Cormount Wayshrine - Grahtwood|9"
        "Fintilorwe"="Elden Root - Grahtwood|445"
        "Walks-In-Leaves"="Elden Root - Grahtwood|445"
        "Mizul"="Elden Root - Grahtwood|445"
        "Iannianith"="Elden Root - Grahtwood|445"
        "Bols Thirandus"="Elden Root - Grahtwood|445"
        "Goh"="Elden Root - Grahtwood|445"
        "Naifineh"="Elden Root - Grahtwood|445"
        "Glothozug"="Southpoint Wayshrine - Grahtwood|9"
        "Halash"="Greenheart Wayshrine - Greenshade|300"
        "Camyaale"="Marbruk - Greenshade|387"
        "Fendros Faryon"="Marbruk - Greenshade|387"
        "Ghobargh"="Marbruk - Greenshade|387"
        "Goudadul"="Marbruk - Greenshade|387"
        "Hasiwen"="Marbruk - Greenshade|387"
        "Seeks-Better-Deals"="Verrant Morass Wayshrine - Greenshade|300"
        "Farvyn Rethan"="Abah's Landing - Hew's Bane|993"
        "Gathewen"="Abah's Landing - Hew's Bane|993"
        "Qanliz"="Abah's Landing - Hew's Bane|993"
        "Shiny-Trades"="Abah's Landing - Hew's Bane|993"
        "Snegbug"="Abah's Landing - Hew's Bane|993"
        "Dahnadreel"="Thieves Den - Hew's Bane|1013"
        "Innryk"="Gonfalon Bay - High Isle|2163"
        "Kemshelar"="Gonfalon Bay - High Isle|2163"
        "Marcelle Fanis"="Gonfalon Bay - High Isle|2163"
        "Pugereau Laffoon"="Gonfalon Bay - High Isle|2163"
        "Shakhrath"="Gonfalon Bay - High Isle|2163"
        "Zoe Frernile"="Gonfalon Bay - High Isle|2163"
        "Janne Jonnicent"="Gonfalon Bay Outlaws Refuge - High Isle|2169"
        "Dulia"="Mistral - Khenarthi's Roost|567"
        "Shamuniz"="Mistral - Khenarthi's Roost|567"
        "Mani"="Baandari Trading Post - Malabal Tor|282"
        "Murgrud"="Baandari Trading Post - Malabal Tor|282"
        "Jalaima"="Baandari Trading Post - Malabal Tor|282"
        "Nindenel"="Baandari Trading Post - Malabal Tor|282"
        "Teromawen"="Baandari Trading Post - Malabal Tor|282"
        "Ulyn Marys"="Dra'bul Wayshrine - Malabal Tor|22"
        "Kharg"="Valeguard Wayshrine - Malabal Tor|22"
        "Aki-Osheeja"="Lilmoth - Murkmire|1560"
        "Faelemar"="Lilmoth - Murkmire|1560"
        "Ordasha"="Lilmoth - Murkmire|1560"
        "Xokomar"="Lilmoth - Murkmire|1560"
        "Mahadal at-Bergama"="Lilmoth - Murkmire|1560"
        "Thaloril"="Lilmoth - Murkmire|1560"
        "Maelanrith"="Rimmen - Northern Elsweyr|1576"
        "Artura Pamarc"="Rimmen - Northern Elsweyr|1576"
        "Razzamin"="Rimmen - Northern Elsweyr|1576"
        "Nirshala"="Rimmen - Northern Elsweyr|1576"
        "Adiblargo"="Rimmen - Northern Elsweyr|1576"
        "Fortis Asina"="Rimmen - Northern Elsweyr|1576"
        "Uzarrur"="Dune - Reaper's March|533"
        "Muheh"="Rawl'kha - Reaper's March|312"
        "Shiniraer"="Rawl'kha - Reaper's March|312"
        "Heat-On-Scales"="Rawl'kha - Reaper's March|312"
        "Canda"="Rawl'kha - Reaper's March|312"
        "Ronuril"="Rawl'kha - Reaper's March|312"
        "Ambarys Teran"="Vinedusk Wayshrine - Reaper's March|256"
        "Aldam Urvyn"="Hoarfrost Downs - Rivenspire|528"
        "Fanwyearie"="Oldgate Wayshrine - Rivenspire|10"
        "Frenidela"="Shornhelm - Rivenspire|85"
        "Roudi"="Shornhelm - Rivenspire|85"
        "Shakh"="Shornhelm - Rivenspire|85"
        "Tendir Vlaren"="Shornhelm - Rivenspire|85"
        "Vorh"="Shornhelm - Rivenspire|85"
        "Talen-Dum"="Hissmir Wayshrine - Shadowfen|26"
        "Emuin"="Stormhold - Shadowfen|217"
        "Gasheg"="Stormhold - Shadowfen|217"
        "Tar-Shehs"="Stormhold - Shadowfen|217"
        "Vals Salvani"="Stormhold - Shadowfen|217"
        "Zino"="Stormhold - Shadowfen|217"
        "Junal-Nakal"="Venomous Fens Wayshrine - Shadowfen|26"
        "Florentina Verus"="Solitude - Western Skyrim|1773"
        "Gilur Vules"="Solitude - Western Skyrim|1773"
        "Grobert Agnan"="Solitude - Western Skyrim|1773"
        "Mandyl"="Solitude - Western Skyrim|1773"
        "Ohanath"="Solitude - Western Skyrim|1773"
        "Tuhdri"="Solitude - Western Skyrim|1773"
        "Fanyehna"="Solitude Outlaws Refuge - Western Skyrim|1778"
        "Glaetaldo"="Senchal - Southern Elsweyr|1675"
        "Golgakul"="Senchal - Southern Elsweyr|1675"
        "Jafinna"="Senchal - Southern Elsweyr|1675"
        "Maguzak"="Senchal - Southern Elsweyr|1675"
        "Saden Sarvani"="Senchal - Southern Elsweyr|1675"
        "Wusava"="Senchal - Southern Elsweyr|1675"
        "Tanur Llervu"="Davon's Watch - Stonefalls|24"
        "Silver-Scales"="Ebonheart - Stonefalls|511"
        "Gananith"="Ebonheart - Stonefalls|511"
        "Luz"="Ebonheart - Stonefalls|511"
        "J'zaraer"="Ebonheart - Stonefalls|511"
        "Urvel Hlaren"="Ebonheart - Stonefalls|511"
        "Ma'jidid"="Kragenmoor - Stonefalls|510"
        "Dromash"="Firebrand Keep Wayshrine - Stormhaven|12"
        "Aniama"="Koeglin Village - Stormhaven|532"
        "Azarati"="Wayrest - Stormhaven|33"
        "Morg"="Wayrest - Stormhaven|33"
        "Atin"="Wayrest - Stormhaven|33"
        "Tredyn Daram"="Wayrest - Stormhaven|33"
        "Estilldo"="Wayrest - Stormhaven|33"
        "Aerchith"="Wayrest - Stormhaven|33"
        "Ah-Zish"="Wayrest - Stormhaven|33"
        "Makmargo"="Port Hunding - Stros M'Kai|530"
        "Talwullaure"="Alinor - Summerset|1430"
        "Irna Dren"="Alinor - Summerset|1430"
        "Rubyn Denile"="Alinor - Summerset|1430"
        "Yggurz Strongbow"="Alinor - Summerset|1430"
        "Huzzin"="Alinor - Summerset|1430"
        "Rialilrin"="Alinor - Summerset|1430"
        "Ambalor"="Lillandril - Summerset|1455"
        "Nowajan"="Lillandril - Summerset|1455"
        "Quelilmor"="Shimmerene - Summerset|1455"
        "Shargalash"="Shimmerene - Summerset|1455"
        "Varandia"="Shimmerene - Summerset|1455"
        "Rinedel"="Lillandril - Summerset|1455"
        "Grudogg"="Necrom - Telvanni Peninsula|2343"
        "Tuls Madryon"="Necrom - Telvanni Peninsula|2343"
        "Alvura Thenim"="Necrom - Telvanni Peninsula|2343"
        "Falani"="Necrom - Telvanni Peninsula|2343"
        "Runethyne Brenur"="Necrom - Telvanni Peninsula|2343"
        "Wyn Serpe"="Necrom - Telvanni Peninsula|2343"
        "Thredis"="Necrom Outlaws Refuge - Telvanni Peninsula|2402"
        "Dion Hassildor"="Leyawiin Outlaws Refuge - Blackwood|1999"
        "Nardhil Barys"="Slag Town Outlaws Refuge - Clockwork City|1354"
        "Tuxutl"="Fargrave Outlaws Refuge - Fargrave|2099"
        "Virwen"="Abah's Landing - Hew's Bane|993"
        "Begok"="Rimmen Outlaws Refuge - Northern Elsweyr|1575"
        "Laytiva Sendris"="Senchal Outlaws Refuge - Southern Elsweyr|1679"
        "Bodfira"="Markarth - The Reach|1858"
        "Marilia Verethi"="Markarth - The Reach|1858"
        "Atazha"="Vivec City - Vvardenfell|1287"
        "Jena Calvus"="Vivec City - Vvardenfell|1287"
        "Lorthodaer"="Vivec City - Vvardenfell|1287"
        "Mauhoth"="Vivec City - Vvardenfell|1287"
        "Rinami"="Vivec City - Vvardenfell|1287"
        "Sebastian Brutya"="Vivec City - Vvardenfell|1287"
        "Relieves-Burdens"="Vivec City Outlaws Refuge - Vvardenfell|1287"
        "Narril"="Balmora - Vvardenfell|1290"
        "Ginette Malarelie"="Balmora - Vvardenfell|1287"
        "Mahrahdr"="Balmora - Vvardenfell|1290"
        "Ruxultav"="Sadrith Mora - Vvardenfell|1288"
        "Felayn Uvaram"="Sadrith Mora - Vvardenfell|1288"
        "Runik"="Sadrith Mora - Vvardenfell|1288"
        "Eralian"="Riften - The Rift|198"
        "Arnyeana"="Riften - The Rift|198"
        "Jeelus-Lei"="Riften - The Rift|198"
        "Llether Nilem"="Riften - The Rift|198"
        "Atheval"="Nimalten - The Rift|543"
        "Borgrara"="Morkul Stronghold - Wrothgar|954"
        "Henriette Panoit"="Morkul Stronghold - Wrothgar|954"
        "Nagrul gro-Stugbaz"="Morkul Stronghold - Wrothgar|954"
        "Oorgurn"="Morkul Stronghold - Wrothgar|954"
        "Jee-Ma"="Orsinium - Wrothgar|895"
        "Terorne"="Orsinium - Wrothgar|895"
        "Narkhukulg"="Orsinium Outlaws Refuge - Wrothgar|927"
        "Adzi-Dool"="Skingrad - West Weald|2514"
        "Catro Catius"="Skingrad - West Weald|2514"
        "Curinwe"="Skingrad - West Weald|2514"
        "Ildare Berel"="Skingrad - West Weald|2514"
        "Lucius Lento"="Skingrad - West Weald|2514"
        "Otho Tatius"="Skingrad - West Weald|2514"
        "Uraacil"="Vulkhel Guard Outlaws Refuge - Auridon|243"
        "Naerorien"="Elden Root Outlaws Refuge - Grahtwood|445"
        "Dugugikh"="Marbruk Outlaws Refuge - Greenshade|387"
        "Galis Andalen"="Velyn Harbor Outlaws Refuge - Malabal Tor|282"
        "Sharaddargo"="Rawl'kha Outlaws Refuge - Reaper's March|312"
        "Marbilah"="Sentinel Outlaws Refuge - Alik'r Desert|83"
        "Ornyenque"="Evermore Outlaws Refuge - Bangkorai|84"
        "Zulgozu"="Daggerfall Outlaws Refuge - Glenumbra|63"
        "Bixitleesh"="Shornhelm Outlaws Refuge - Rivenspire|85"
        "Essilion"="Wayrest Outlaws Refuge - Stormhaven|33"
        "Nakmargo"="Mournhold Outlaws Refuge - Deshaan|205"
        "Meden Berendus"="Windhelm Outlaws Refuge - Eastmarch|160"
        "Majdawa"="Riften Outlaws Refuge - The Rift|198"
        "Geeh-Sakka"="Stormhold Outlaws Refuge - Shadowfen|217"
        "Adagwen"="Davon's Watch Outlaws Refuge - Stonefalls|24"
        "Makkhzahr"="Belkarth Outlaws Refuge - Craglorn|1131"
        "Ushataga"="Skingrad Outlaws Refuge - West Weald|2514"
    }
    
    [string[]]$named = @($raw.Keys | Where-Object { $_ -notmatch '^[0-9]+$' })
    [array]::Sort($named, [System.StringComparer]::Ordinal)
    foreach ($t in $named) {
        $tp = $raw[$t].Split('|')
        if ($tp.Length -ge 2 -and $tp[1] -match '^[0-9]+$') { $global:k_dict[$t] = "$($tp[0])|$($tp[1])" }
    }
    foreach ($k in @($raw.Keys | Where-Object { $_ -match '^[0-9]+$' })) {
        $parts = $raw[$k].Split('|')
        $locName = $parts[0]; $coordStr = $parts[1]
        $global:k_dict[$k] = "$locName||$coordStr"
        $best = $null
        foreach ($t in $named) {
            if (!$global:k_dict.ContainsKey($t)) { continue }
            $tp = $global:k_dict[$t].Split('|')
            $tLoc = $tp[0]; $tMap = $tp[1]
            if ($tLoc.StartsWith("$locName - ") -or $tLoc.StartsWith("$locName Wayshrine") -or $tLoc -eq $locName) {
                $global:k_dict[$t] = "$tLoc|$tMap|$coordStr"
                if ($null -eq $best) { $best = "$tLoc|$tMap|$coordStr" }
            }
        }
        if ($null -ne $best) { $global:k_dict[$k] = $best }
    }
}
Init-Kiosk-Dict

function Get-HQ($q) {
    if($q -eq 6) { return "Mythic (Orange) 6" }; if($q -eq 5) { return "Legendary (Gold) 5" }; if($q -eq 4) { return "Epic (Purple) 4" }
    if($q -eq 3) { return "Superior (Blue) 3" }; if($q -eq 2) { return "Fine (Green) 2" }; if($q -eq 1) { return "Normal (White) 1" }
    return "Trash (Grey) 0"
}

function Get-Cat($n, $i, $s, $v) {
    $ln = $n.ToLower()
    if($ln -match 'motif') { return "Crafting Motif" }
    if($ln -match 'blueprint|praxis|design|pattern|formula|diagram|sketch') { return "Furniture Plan" }
    if($ln -match 'style page|runebox') { return "Style/Collectible" }
    if($ln -match 'tea blends of tamriel|tin of high isle taffy|assorted stolen shiny trinkets|lightly used fiddle|stuffed bear|grisly trophy|companion gift') { return "Companion Gift" }
    if($v -gt 1 -or $s -ge 20) { return "Equipment (Armor/Weapon)" }
    return "Materials/Misc"
}

function Calc-Quality($id, $name, $s, $v) {
    $ln = $name.ToLower()
    if ($id -match '^(165899|187648|171437|165910|175510|181971|181961|175402|184206|191067)$') { return 6 }
    if ($ln -match 'citation|truly superb glyph|tempering alloy|dreugh wax|rosin|kuta|perfect roe|aetherial dust|chromium plating|style page:|runebox:|research scroll|psijic ambrosia|indoril inks:') { return 5 }
    if ($ln -match 'master .* writ') { return 4 }
    if ($ln -match 'unknown .* writ|welkynar binding|rekuta|grain solvent|mastic|elegant lining|zircon plating|potent nirncrux|fortified nirncrux|culanda lacquer|harvested soul fragment') { return 4 }
    if ($ln -match 'tea blends of tamriel|twenty-year ruby port|assorted stolen shiny trinkets|lightly used fiddle|stuffed bear|grisly trophy|companion gift|tin of high isle taffy|angler''s knife set|dried fish biscuits|beginner''s bowfishing kit') { return 3 }
    if ($ln -match 'survey report|dwarven oil|turpen|embroidery|iridium plating|treasure map|bervez juice|frost mirriam') { return 3 }
    if ($ln -match 'hemming|honing stone|pitch|terne plating|soul gem') { return 2 }
    if ($ln -match '^(recipe|design|blueprint|pattern|praxis|formula|diagram|sketch):') {
        if($s -eq 6) { return 5 }; if($s -eq 5) { return 4 }; if($s -eq 4) { return 3 }; if($s -eq 3) { return 2 }; return 1
    }
    if ($s -ge 2 -and $s -le 6) { return $s - 1 }; if ($s -ge 20 -and $s -le 24) { return $s - 19 }
    if ($s -ge 25 -and $s -le 29) { return $s - 24 }; if ($s -ge 30 -and $s -le 34) { return $s - 29 }
    if ($s -ge 236 -and $s -le 240) { return $s - 235 }; if ($s -ge 241 -and $s -le 245) { return $s - 240 }
    if ($s -ge 254 -and $s -le 258) { return $s - 253 }; if ($s -ge 259 -and $s -le 263) { return $s - 258 }
    if ($s -ge 272 -and $s -le 276) { return $s - 271 }; if ($s -ge 277 -and $s -le 281) { return $s - 276 }
    if ($s -ge 290 -and $s -le 294) { return $s - 289 }; if ($s -ge 295 -and $s -le 299) { return $s - 294 }
    if ($s -ge 305 -and $s -le 309) { return $s - 304 }; if ($s -ge 308 -and $s -le 312) { return $s - 307 }
    if ($s -ge 313 -and $s -le 317) { return $s - 312 }; if ($s -ge 361 -and $s -le 365) { return $s - 360 }
    if ($s -ge 51 -and $s -le 60) { return 2 }; if ($s -ge 61 -and $s -le 70) { return 3 }
    if ($s -ge 71 -and $s -le 80) { return 4 }; if ($s -ge 81 -and $s -le 90) { return 3 }
    if ($s -ge 91 -and $s -le 100) { return 4 }; if ($s -ge 101 -and $s -le 110) { return 5 }
    if ($s -ge 111 -and $s -le 120) { return 1 }; if ($s -ge 125 -and $s -le 134) { return 1 }
    if ($s -ge 135 -and $s -le 144) { return 2 }; if ($s -ge 145 -and $s -le 154) { return 3 }
    if ($s -ge 155 -and $s -le 164) { return 4 }; if ($s -ge 165 -and $s -le 174) { return 5 }
    if ($s -ge 39 -and $s -le 49) { return 2 }; if ($s -ge 229 -and $s -le 231) { return $s - 227 }
    if ($s -ge 232 -and $s -le 234) { return $s - 229 }; if ($s -ge 250 -and $s -le 252) { return $s - 247 }
    if ($s -eq 7) { return 3 }; if ($s -eq 8) { return 4 }; if ($s -eq 9) { return 2 }
    if ($s -eq 235 -or $s -eq 253) { return 1 }; if ($s -eq 366) { return 6 }; if ($s -eq 358) { return 2 }; if ($s -eq 360) { return 3 }
    return 1
}

function Clean-Legacy-Tags {
    Log-Event "INFO" "clean_legacy_tags: sanitizing legacy DB files"
    $found = $false
    foreach ($db in @($DB_FILE, $HIST_FILE)) {
        if ((Test-Path $db) -and (Select-String -LiteralPath $db -SimpleMatch "<title>" -Quiet)) {
            $t = [System.IO.File]::ReadAllText($db).Replace("<title>UESP:ESO Item -- ", "").Replace("<title>ESO Item -- ", "").Replace("</title>", "")
            [System.IO.File]::WriteAllText($db, $t, (New-Object System.Text.UTF8Encoding $false))
            $found = $true
        }
    }
    if ($found) {
        Log-Event "INFO" "Sanitized legacy tags."
        if (!$global:SILENT) { Write-Host " $ESC[92m[+] Cleaned legacy tags.$ESC[0m" }
    }
}
Clean-Legacy-Tags

function Auto-Repair-Database {
    if (!(Test-Path $DB_FILE)) { return }
    Log-Event "INFO" "auto_repair_database: checking and repairing DB entries with missing item names."
    
    $missingCount = 0
    $dbLines = [System.IO.File]::ReadAllLines($DB_FILE)
    foreach ($line in $dbLines) {
        $parts = $line.Split('|')
        if ($parts[0] -match '^[0-9]+$') {
            $tempName = if ($parts.Length -ge 6) { $parts[5] } else { $parts[2] }
            if ($tempName -match '^Unknown Item \(') { $missingCount++ }
        }
    }
    
    if ($missingCount -gt 0) {
        if (!$SILENT) { Write-Host " $ESC[33m[!] Auto-Repair: Scanning local TTC data to resolve $missingCount items...$ESC[0m" }
        Log-Event "INFO" "Auto-Repair: Found $missingCount unknown items. Scanning local lua files for item links."
        $offlineDict = @{}
        if (Test-Path "$SAVED_VAR_DIR\TamrielTradeCentre.lua") {
            foreach ($line in [System.IO.File]::ReadLines("$SAVED_VAR_DIR\TamrielTradeCentre.lua")) {
                if ($line -match '\|H[^:]*:item:([0-9]+)[^|]*\|h([^|]+)\|h') {
                    $id = $matches[1]; $n = $matches[2] -replace '\^.*$', ''
                    if ($id -and $n) { $offlineDict[$id] = $n }
                }
            }
        }
        
        $newDb = New-Object System.Collections.ArrayList
        foreach ($line in $dbLines) {
            $parts = $line.Split('|')
            if ($parts[0] -match '^[0-9]+$' -and $parts.Length -ge 6) {
                if ($parts[5] -match '^Unknown Item \(' -and $offlineDict.ContainsKey($parts[0])) {
                    $parts[5] = $offlineDict[$parts[0]]
                    $real_qual = Calc-Quality $parts[0] $parts[5] ([int]$parts[2]) ([int]$parts[3])
                    $parts[1] = $real_qual; $parts[4] = Get-HQ $real_qual; $parts[6] = Get-Cat $parts[5] $parts[0] ([int]$parts[2]) ([int]$parts[3])
                    [void]$newDb.Add(($parts -join '|'))
                    continue
                }
            }
            [void]$newDb.Add($line)
        }
        [System.IO.File]::WriteAllLines($DB_FILE, $newDb.ToArray())
        if (!$SILENT) { Write-Host " $ESC[92m[+]$ESC[0m Offline Database repair complete!" }
        Log-Event "INFO" "Auto-Repair: Offline database repair completed successfully."
    }
}

function Prune-HistoryLines([string[]]$lines, [double]$cutoff, [hashtable]$dbName, [hashtable]$dbQual) {
    $kept = New-Object System.Collections.Generic.List[string]
    $pruned = New-Object System.Collections.Generic.List[string]
    foreach ($raw in $lines) {
        $line = $raw.TrimEnd("`r")
        $f = $line.Split('|')
        if ($f[0] -ne "HISTORY") { if ($line -ne "") { $kept.Add($line) }; continue }
        if ((To-Num $f[1]) -lt $cutoff) { $pruned.Add($line); continue }

        $nf = $f.Length
        if ($f[$nf - 1] -match '^[0-9]+$') { $scans = [long]$f[$nf - 1]; $src = $f[$nf - 2] } else { $scans = 1; $src = $f[$nf - 1] }
        if ($src -match '^(Unknown|\[Unknown\])$' -or $src -eq "") { $src = "TTC" }
        if ($nf -lt 14) { $f = $f + (,"" * (14 - $nf)) }

        if ($dbName.ContainsKey($f[5]) -and $dbName[$f[5]] -ne "" -and $dbName[$f[5]] -notmatch '^Unknown Item') { $f[6] = $dbName[$f[5]] }
        if ($dbQual.ContainsKey($f[5])) { $f[11] = Get-QualityColor $dbQual[$f[5]] }
        elseif (!$f[11].StartsWith("$ESC[")) { $f[11] = "$ESC[0m" }
        $f[12] = $src; $f[13] = "$scans"
        $kept.Add(($f[0..13] -join '|'))
    }
    return [PSCustomObject]@{ Kept = $kept.ToArray(); Pruned = $pruned.ToArray() }
}

function Prune-History {
    Log-Event "INFO" "prune_history: Initiating 30 days data prune and metadata sync."
    if (!(Test-Path $HIST_FILE)) { return }
    Start-Spinner "Pruning history data (30 days)..."
    $now = if ($CURRENT_TIME) { $CURRENT_TIME } else { [long][DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

    $dbName = New-Object System.Collections.Hashtable; $dbQual = New-Object System.Collections.Hashtable
    if (Test-Path $DB_FILE) {
        foreach ($line in [System.IO.File]::ReadLines($DB_FILE)) {
            $p = $line.Split('|')
            if ($p[0] -match '^[0-9]+$') {
                $dbName[$p[0]] = if ($p.Length -ge 6) { $p[5] } elseif ($p.Length -ge 3) { $p[2] } else { "" }
                $dbQual[$p[0]] = To-Num $p[1]
            }
        }
    }

    $orig = [System.IO.File]::ReadAllLines($HIST_FILE)
    $res = Prune-HistoryLines $orig ($now - 2592000) $dbName $dbQual
    [System.IO.File]::WriteAllText($HIST_FILE, $(if ($res.Kept.Count) { ($res.Kept -join "`n") + "`n" } else { "" }), (New-Object System.Text.UTF8Encoding $false))

    if ($global:LOG_MODE -eq "detailed") {
        foreach ($l in $res.Pruned) { Log-Event "ITEM" "Pruned History Item: $l" }
    }
    $count = [math]::Max(0, $orig.Count - $res.Kept.Count)
    Stop-Spinner 0 "History pruned ($count items removed)"
}
function Get-NameEnc([string]$s) { return $s.Replace(" ", "+").Replace("'", "%27") }
function Get-TtcUrl([string]$name) { return "https://us.tamrieltradecentre.com/pc/Trade/SearchResult?SearchType=Sell&ItemNamePattern=$(Get-NameEnc $name)" }

$UESP_STYLE_SUFFIXES = @(
    ' (Axes|Belts|Boots|Bows|Chests|Daggers|Gloves|Helmets)$',
    ' (Legs|Maces|Shields|Shoulders|Staves|Swords|Cuirass)$',
    ' (Greaves|Helm|Pauldrons|Sabatons|Gauntlets|Bracers)$',
    ' (Epaulets|Jack|Guards|Belt|Shoes|Jerkin|Breeches|Hat)$',
    ' (Robes|Sash|Girdle|Corselet|Arm Cops)$',
    ' Style$'
)

function Get-ItemLinks([string]$name, [string]$id) {
    $out = "$ESC[90m[$ESC]8;;$(Get-TtcUrl $name)$ESC\TTC$ESC]8;;$ESC\]$ESC[0m " +
           "$ESC[90m[$ESC]8;;https://eso-hub.com/en/trading/$id$ESC\ESO-Hub$ESC]8;;$ESC\]$ESC[0m"
    if ($name -cmatch '^(Blueprint|Praxis|Design|Pattern|Formula|Diagram|Sketch): ') {
        $u = ([regex]'^[^:]+: ').Replace($name, '', 1).Replace(" ", "_").Replace("'", "%27")
        $out += " $ESC[90m[$ESC]8;;https://en.uesp.net/wiki/File:ON-furnishing-$u.jpg$ESC\UESP$ESC]8;;$ESC\]$ESC[0m"
    } elseif ($name -cmatch 'Crafting Motif' -or $name -cmatch 'Style Page:') {
        $u = ([regex]'^.*Crafting Motif [^:]+: ').Replace($name, '', 1)
        $u = ([regex]'^.*Style Page: ').Replace($u, '', 1)
        foreach ($suf in $UESP_STYLE_SUFFIXES) { $u = ([regex]$suf).Replace($u, '', 1) }
        $u = $u.Replace(" ", "_").Replace("'", "%27")
        $out += " $ESC[90m[$ESC]8;;https://en.uesp.net/wiki/Online:${u}_Style$ESC\UESP$ESC]8;;$ESC\]$ESC[0m"
    }
    return $out
}

function Get-BandPrice([System.Collections.Generic.List[double]]$list) {
    $a = $list.ToArray(); [Array]::Sort($a); $n = $a.Length
    $trim = [math]::Floor($n * 0.10); if ($trim -eq 0) { $trim = 1 }
    $validN = $n - (2 * $trim); if ($validN -lt 1) { $validN = 1 }
    $ms = $trim + [math]::Floor($validN * 0.45); $me = $trim + [math]::Floor($validN * 0.55)
    if ($me -lt $ms) { $me = $ms }
    $sum = 0.0; $c = 0
    for ($i = $ms; $i -le $me; $i++) { $sum += $a[$i]; $c++ }
    return $sum / $c
}

function Test-RowPasses($p) {
    if ($script:bCutoff -gt 0 -and (To-Num $p[1]) -lt $script:bCutoff) { return $false }
    if ($script:bSrc -and (To-LowerAscii $p[12]).IndexOf($script:bSrc, [StringComparison]::Ordinal) -lt 0) { return $false }
    if ($script:bUser -and (To-LowerAscii $p[7]).IndexOf($script:bUser, [StringComparison]::Ordinal) -lt 0 -and (To-LowerAscii $p[8]).IndexOf($script:bUser, [StringComparison]::Ordinal) -lt 0) { return $false }
    if ("$($p[6])".StartsWith("Unknown Item (", [StringComparison]::Ordinal)) { return $false }
    return $true
}

function Get-RelTime([double]$ts, [long]$now) {
    if ($ts -eq 0) { return "Active" }
    $d = $now - $ts; if ($d -lt 0) { $d = 0 }
    if ($d -lt 60) { return "${d}s ago" }
    if ($d -lt 3600) { return "$([math]::Floor($d / 60))m ago" }
    if ($d -lt 86400) { return "$([math]::Floor($d / 3600))h ago" }
    return "$([math]::Floor($d / 86400))d ago"
}

function Get-BrowseSortKey([string]$sortOpt, [double]$ts, [double]$price, [string]$name, [int]$idx) {
    $k = switch ($sortOpt) {
        "2" { ([long]$ts).ToString().PadLeft(10, '0') }
        "3" { (Format-Fixed (100000000000000 - $price) 3).PadLeft(18, '0') }
        "4" { (Format-Fixed $price 3).PadLeft(18, '0') }
        "5" { To-LowerAscii $name }
        default { ([long](9999999999 - $ts)).ToString().PadLeft(10, '0') }
    }
    return "$k|$($idx.ToString().PadLeft(9, '0'))"
}

function Sort-ByKey($keys, $rows) {
    $k = [string[]]$keys.ToArray(); $r = [string[]]$rows.ToArray()
    [Array]::Sort($k, $r, [StringComparer]::Ordinal)
    return ,$r
}

function Read-BrowseFilters {
    $script:bSrcRaw = Read-Host "$ESC[33mSearch by Source [TTC or ESO-Hub] (leave empty for ALL)$ESC[0m"
    $script:bPersonal = Read-Host "$ESC[33mFilter to your @Username only? (y/N)$ESC[0m"
    Write-Host "`n$ESC[33mTime Filter:$ESC[0m"
    Write-Host " 1) Past 1 Week`n 2) Past 2 Weeks`n 3) Past 3 Weeks`n 4) All Data"
    $script:bTimeOpt = Read-Host "$ESC[33mChoice [1-4] (default 4)$ESC[0m"

    $script:bCutoff = 0; $now = [long][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    switch ($script:bTimeOpt) { "1" { $script:bCutoff = $now - 604800 } "2" { $script:bCutoff = $now - 1209600 } "3" { $script:bCutoff = $now - 1814400 } }

    $script:bUserRaw = ""
    if ($script:bPersonal -match '^[Yy]$') {
        if ([string]::IsNullOrEmpty($global:TARGET_USERNAME)) { Write-Host "$ESC[31m[!] @Username not set!$ESC[0m" }
        else { $script:bUserRaw = $global:TARGET_USERNAME }
    }
    $script:bSrc = To-LowerAscii $script:bSrcRaw
    $script:bUser = To-LowerAscii $script:bUserRaw
}

function Get-BrowseCacheFile([string]$key) {
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $hash = -join ($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("$key`n")) | ForEach-Object { $_.ToString("x2") })
    return "$script:bCacheDir\cache_$hash.txt"
}

function Test-CacheFresh($cacheFile) {
    return ((Test-Path -LiteralPath $cacheFile) -and (Get-Item -LiteralPath $cacheFile).LastWriteTimeUtc -gt (Get-Item -LiteralPath $HIST_FILE).LastWriteTimeUtc)
}

function Write-Lines($path, $lines) {
    [System.IO.File]::WriteAllText($path, $(if (@($lines).Count) { (@($lines) -join "`n") + "`n" } else { "" }), (New-Object System.Text.UTF8Encoding $false))
}

function Show-Pages($rows) {
    $total = $rows.Count; $pages = [math]::Ceiling($total / 50); $page = 1
    while ($true) {
        Clear-Host
        Write-Host "$ESC[36m--- Results Page $page of $pages ---$ESC[0m`n"
        $start = ($page - 1) * 50; $end = [math]::Min($start + 50, $total)
        for ($i = $start; $i -lt $end; $i++) { [Console]::WriteLine($rows[$i]) }
        Write-Host "`n$ESC[33mPress [SPACE] for next page, or 'q' to quit...$ESC[0m"
        $key = [Console]::ReadKey($true)
        if ($key.KeyChar -eq 'q' -or $key.KeyChar -eq 'Q') { break }
        if ($page * 50 -ge $total) { break }
        $page++
    }
}

function Get-HistoryRows([string]$file, [string]$term, [string]$sortOpt) {
    $now = [long][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $guildId = (New-Object System.Collections.Hashtable)
    if (Test-Path $DB_FILE) {
        foreach ($l in [System.IO.File]::ReadLines($DB_FILE)) { $q = $l.Split('|'); if ($q[0] -eq "GUILD") { $guildId[$q[1]] = $q[2] } }
    }
    $keys = New-Object System.Collections.Generic.List[string]; $rows = New-Object System.Collections.Generic.List[string]
    $nr = 0
    foreach ($raw in [System.IO.File]::ReadLines($file)) {
        $nr++
        $line = $raw.TrimEnd("`r"); $p = $line.Split('|')
        if ($p[0] -ne "HISTORY" -or !(Test-RowPasses $p)) { continue }
        if ($p[9] -eq "Unknown Guild" -or $p[9] -eq "Guilds") { continue }
        $kname = "$($p[10])"
        if ($kname -ne "" -and $kname -ne "0" -and $global:k_dict.ContainsKey($kname)) { $kname = $global:k_dict[$kname].Split('|')[0] }
        if ($term -and (To-LowerAscii "$line|$kname").IndexOf($term, [StringComparison]::Ordinal) -lt 0) { continue }

        $actCol = "$ESC[36m"
        if ($p[2] -eq "Sold") { $actCol = "$ESC[38;5;214m" }
        if ($p[2] -eq "Purchased") { $actCol = "$ESC[92m" }
        if ($p[2] -eq "Cancelled") { $actCol = "$ESC[31m" }

        $kStr = ""
        if ("$($p[10])" -ne "" -and $p[10] -ne "0") {
            $kStr = if ($global:k_dict.ContainsKey($p[10])) { Get-KioskLink $p[10] "" } else { " $ESC[90m(Kiosk ID: $($p[10]))$ESC[0m" }
        }
        $gStr = ""
        if ("$($p[9])" -ne "") {
            $gStr = if ($guildId.ContainsKey($p[9])) { " in $ESC[35m$ESC]8;;|H1:guild:$($guildId[$p[9]])|h$($p[9])|h$ESC\$($p[9])$ESC]8;;$ESC\$ESC[0m" } else { " in $ESC[35m$($p[9])$ESC[0m" }
        }
        $link = if ($p[12] -eq "TTC") { Get-TtcUrl $p[6] } else { "https://eso-hub.com/en/trading/$($p[5])" }
        $scans = To-Num $p[13]
        $scanStr = if ($scans -gt 1) { " $ESC[96m[${scans}x Scans]$ESC[0m" } else { "" }
        $trade = ""
        if ("$($p[8])" -ne "" -and "$($p[7])" -ne "") { $trade = " by $ESC[36m$($p[8])$ESC[0m to $ESC[36m$($p[7])$ESC[0m" }
        elseif ("$($p[8])" -ne "") { $trade = " by $ESC[36m$($p[8])$ESC[0m" }
        elseif ("$($p[7])" -ne "") { $trade = " to $ESC[36m$($p[7])$ESC[0m" }

        $ts = To-Num $p[1]
        $keys.Add((Get-BrowseSortKey $sortOpt $ts (To-Num $p[3]) $p[6] $nr))
        $rows.Add(" [$ESC[90m$(Get-RelTime $ts $now)$ESC[0m] $actCol$($p[2])$ESC[0m for $ESC[32m$($p[3])$ESC[33mgold$ESC[0m - $ESC[32m$($p[4])x$ESC[0m $ESC]8;;$link$ESC\$($p[11])$($p[6])$ESC[0m$ESC]8;;$ESC\$trade$gStr$kStr [$ESC[90m$($p[12])$ESC[0m]$scanStr")
    }
    return Sort-ByKey $keys $rows
}

function Get-ScanRows([string]$file, [string]$term, [string]$sortOpt) {
    $now = [long][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $keys = New-Object System.Collections.Generic.List[string]; $rows = New-Object System.Collections.Generic.List[string]
    $nr = 0
    foreach ($raw in [System.IO.File]::ReadLines($file)) {
        $nr++
        $line = $raw.TrimEnd("`r")
        if ($line -cnotmatch "\[TS:[0-9]+\]|\[$ESC\[90mListing$ESC\[0m\]") { continue }
        $plain = [regex]::Replace($line, "$ESC\]8;;[^$ESC]*$ESC\\", "")
        $plain = [regex]::Replace($plain, "$ESC\[[0-9;]*m", "")
        if ($term -and (To-LowerAscii $plain).IndexOf($term, [StringComparison]::Ordinal) -lt 0) { continue }
        $ts = if ($line -cmatch '\[TS:([0-9]+)\]') { To-Num $matches[1] } else { 0 }
        $price = if ($plain -cmatch ' for ([0-9]+)gold') { To-Num $matches[1] } else { 0 }
        $name = ([regex]'^[^-]* - [0-9]+x ').Replace($plain, '', 1)
        $row = if ($ts -gt 0) { ([regex]'\[TS:[0-9]+\]').Replace($line, "[$ESC[90m$(Get-RelTime $ts $now)$ESC[0m]", 1) } else { $line }
        $keys.Add((Get-BrowseSortKey $sortOpt $ts $price $name $nr))
        $rows.Add($row)
    }
    return Sort-ByKey $keys $rows
}

function Show-BrowseListing([string]$mode) {
    $term = To-LowerAscii (Read-Host "$ESC[33mEnter search term (leave empty for ALL data)$ESC[0m")
    Read-BrowseFilters
    Write-Host "`n$ESC[33mSort By:$ESC[0m"
    Write-Host " 1) Date (Newest First)`n 2) Date (Oldest First)`n 3) Price (Highest First)`n 4) Price (Lowest First)`n 5) Alphabetical (A-Z)"
    $sortOpt = Read-Host "$ESC[33mChoice [1-5]$ESC[0m"

    if ($mode -eq "scan") { Write-Host "`n$ESC[36m--- View Previous Extraction History ---$ESC[0m" } else { Write-Host "`n$ESC[36mProcessing data...$ESC[0m" }
    Start-Spinner "Filtering and sorting..."
    $rows = if ($mode -eq "scan") { Get-ScanRows $LAST_SCAN_FILE $term $sortOpt } else { Get-HistoryRows $HIST_FILE $term $sortOpt }
    Stop-Spinner 0 "$($rows.Count) results"

    if ($rows.Count -eq 0) {
        Write-Host " $ESC[31m[-] No results found.$ESC[0m"
        Read-Host "`n$ESC[33mPress Enter to return...$ESC[0m" | Out-Null
    } else {
        Show-Pages $rows
    }
}

function Get-TopLines([string]$kind, [string]$file = $HIST_FILE) {
    $prices = (New-Object System.Collections.Hashtable); $total = (New-Object System.Collections.Hashtable); $colors = (New-Object System.Collections.Hashtable); $ids = (New-Object System.Collections.Hashtable)
    foreach ($raw in [System.IO.File]::ReadLines($file)) {
        $p = $raw.TrimEnd("`r").Split('|')
        if ($p[0] -ne "HISTORY" -or ($p[2] -ne "Sold" -and $p[2] -ne "Purchased" -and $p[2] -ne "Listed") -or (To-Num $p[4]) -le 0) { continue }
        if (!(Test-RowPasses $p)) { continue }
        $qty = To-Num $p[4]; $unit = (To-Num $p[3]) / $qty; $name = $p[6]
        $scans = if ("$($p[13])" -ne "" -and (To-Num $p[13]) -gt 0) { To-Num $p[13] } else { 1 }
        $colors[$name] = if ("$($p[11])" -ne "") { $p[11] } else { "$ESC[0m" }
        $ids[$name] = $p[5]
        if (!$prices.ContainsKey($name)) { $prices[$name] = New-Object System.Collections.Generic.List[double] }
        $sold = ($p[2] -eq "Sold" -or $p[2] -eq "Purchased")
        for ($s = 0; $s -lt $scans; $s++) {
            $prices[$name].Add($unit)
            if ($sold) { $total[$name] = $total[$name] + $(if ($kind -eq "vol") { $qty } else { To-Num $p[3] }) }
        }
    }
    $keys = New-Object System.Collections.Generic.List[string]; $rows = New-Object System.Collections.Generic.List[string]
    foreach ($name in $total.Keys) {
        $n = $prices[$name].Count
        $sugg = if ($n -ge 5) { Get-BandPrice $prices[$name] } else { 0 }
        $pStr = if ($sugg -eq 0) { "Not enough data" } else { "$(Format-Fixed $sugg 2)g" }
        $lead = if ($kind -eq "vol") { " $ESC[36m$(Format-Fixed $total[$name] 0)x$ESC[0m sold - " } else { " $ESC[33m$(Format-Fixed $total[$name] 0)g$ESC[0m grossed - " }
        $inv = -join ((Format-Fixed $total[$name] 3).PadLeft(20, '0').ToCharArray() | ForEach-Object { if ($_ -ge '0' -and $_ -le '9') { [char](105 - [int]$_) } else { $_ } })
        $keys.Add("$inv`t$name")
        $rows.Add("$lead$($colors[$name])$name$ESC[0m (Avg: $ESC[33m$pStr$ESC[0m) $(Get-ItemLinks $name $ids[$name])")
    }
    $sorted = Sort-ByKey $keys $rows
    return ,@($sorted | Select-Object -First 10)
}

function Show-BrowseTop([string]$kind) {
    if ($kind -eq "vol") { Log-Event "INFO" "DB Browser: Generating Top 10 Selling Items list."; $tag = "O1v4"; $title = "Top 10 Selling Items (By Volume)" }
    else { Log-Event "INFO" "DB Browser: Generating Top 10 Highest Grossing Items list."; $tag = "O2v4"; $title = "Top 10 Highest Grossing Items" }
    Read-BrowseFilters
    if ($script:bUserRaw) { Write-Host "`n$ESC[36m--- $title [$($script:bUserRaw)] ---$ESC[0m" } else { Write-Host "`n$ESC[36m--- $title [Global] ---$ESC[0m" }

    $cacheFile = Get-BrowseCacheFile "$tag|$($script:bSrcRaw)|$($script:bPersonal)|$($script:bTimeOpt)"
    if (Test-CacheFresh $cacheFile) {
        Write-Host " $ESC[32m[+] Loading instantly from persistent cache...$ESC[0m`n"
        [Console]::Write([System.IO.File]::ReadAllText($cacheFile))
    } else {
        Write-Host ""
        if ($kind -eq "vol") { Start-Spinner "Calculating Top 10 by Volume (Building Cache)..." } else { Start-Spinner "Calculating Top 10 by Grossing (Building Cache)..." }
        $lines = Get-TopLines $kind
        Write-Lines $cacheFile $lines
        Stop-Spinner 0 "Calculation complete"
        Write-Host ""
        foreach ($l in $lines) { [Console]::WriteLine($l) }
    }
    Write-Host ""
}

function Get-PriceLines([string]$term, [string]$file = $HIST_FILE) {
    $prices = (New-Object System.Collections.Hashtable); $colors = (New-Object System.Collections.Hashtable); $ids = (New-Object System.Collections.Hashtable)
    foreach ($raw in [System.IO.File]::ReadLines($file)) {
        $p = $raw.TrimEnd("`r").Split('|')
        if ($p[0] -ne "HISTORY" -or (To-LowerAscii $p[6]).IndexOf($term, [StringComparison]::Ordinal) -lt 0) { continue }
        if (($p[2] -ne "Listed" -and $p[2] -ne "Sold" -and $p[2] -ne "Purchased") -or "$($p[3])" -notmatch '^[0-9]+(\.[0-9]+)?$' -or (To-Num $p[4]) -le 0) { continue }
        if (!(Test-RowPasses $p)) { continue }
        $qty = To-Num $p[4]; $unit = (To-Num $p[3]) / $qty; $name = $p[6]
        $scans = if ("$($p[13])" -ne "" -and (To-Num $p[13]) -gt 0) { To-Num $p[13] } else { 1 }
        $colors[$name] = if ("$($p[11])" -ne "") { $p[11] } else { "$ESC[0m" }
        $ids[$name] = $p[5]
        if (!$prices.ContainsKey($name)) { $prices[$name] = New-Object System.Collections.Generic.List[double] }
        for ($s = 0; $s -lt $scans; $s++) { $prices[$name].Add($unit) }
    }
    $keys = New-Object System.Collections.Generic.List[string]; $rows = New-Object System.Collections.Generic.List[string]
    foreach ($name in $prices.Keys) {
        $n = $prices[$name].Count
        if ($n -lt 5) { continue }
        $keys.Add($name)
        $rows.Add("$($colors[$name])$name$ESC[0m - Suggested Price: $ESC[33m$(Format-Fixed (Get-BandPrice $prices[$name]) 2)g$ESC[0m (Based on $n data points) $(Get-ItemLinks $name $ids[$name])")
    }
    return Sort-ByKey $keys $rows
}

function Show-BrowsePrice {
    $pTerm = Read-Host "$ESC[33mEnter exact or partial item name for price check$ESC[0m"
    Read-BrowseFilters
    Log-Event "INFO" "DB Browser: Executed Suggested Price Check for '$pTerm'"
    Write-Host "`n$ESC[36m--- Suggested Price Check ---$ESC[0m"

    $cacheFile = Get-BrowseCacheFile "O3v4|$pTerm|$($script:bSrcRaw)|$($script:bPersonal)|$($script:bTimeOpt)"
    if (Test-CacheFresh $cacheFile) {
        Write-Host " $ESC[32m[+] Loading instantly from persistent cache...$ESC[0m`n"
        [Console]::Write([System.IO.File]::ReadAllText($cacheFile))
    } else {
        Write-Host ""
        Start-Spinner "Calculating Outlier Eliminations (Building Cache)..."
        $lines = Get-PriceLines (To-LowerAscii $pTerm)
        if ($lines.Count -gt 0) {
            Write-Lines $cacheFile $lines
            Stop-Spinner 0 "Calculation complete"
            Write-Host ""
            foreach ($l in $lines) { [Console]::WriteLine($l) }
        } else {
            Stop-Spinner 1 "Not enough data to display anything"
        }
    }
    Write-Host ""
}

function Set-BrowseUser {
    Write-Host "`n$ESC[36m--- Settings: Edit My Target Username ---$ESC[0m"
    $u = Read-Host "$ESC[33mEnter your exact @Username (leave blank to clear)$ESC[0m"
    if ($u) { $u = "@" + $u.TrimStart('@') }
    $global:TARGET_USERNAME = $u
    $lines = if (Test-Path $CONFIG_FILE) { @([System.IO.File]::ReadAllLines($CONFIG_FILE)) } else { @() }
    $found = $false
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^TARGET_USERNAME=') { $lines[$i] = "TARGET_USERNAME=`"$u`""; $found = $true } }
    if (!$found) { $lines += "TARGET_USERNAME=`"$u`"" }
    [System.IO.File]::WriteAllLines($CONFIG_FILE, [string[]]$lines, (New-Object System.Text.UTF8Encoding $false))

    if (!$u) {
        Write-Host " $ESC[90m[-] Username cleared.$ESC[0m`n"
        Log-Event "INFO" "DB Browser: Target Username cleared."
    } else {
        Write-Host " $ESC[92m[+] Username saved as $u$ESC[0m`n"
        Log-Event "INFO" "DB Browser: Target Username updated to '$u'"
    }
    Read-Host "$ESC[33mPress Enter to return...$ESC[0m" | Out-Null
}

function Browse-Database {
    try { [ConsoleConfig]::DisableQuickEdit() } catch {}
    Log-Event "INFO" "browse_database: entering DB browser"
    Clear-Host
    Write-Host "`n$ESC[92m===========================================================================$ESC[0m"
    Write-Host "$ESC[1m$ESC[94m                         TTC & ESO-Hub Database Browser$ESC[0m"
    Write-Host "$ESC[97m                 (Data automatically retained for the last 30 days)$ESC[0m"
    Write-Host "$ESC[92m===========================================================================$ESC[0m`n"

    if (!(Test-Path $HIST_FILE) -or (Get-Item $HIST_FILE).Length -eq 0) {
        Write-Host "$ESC[31m[!] No history database found. Wait for extraction first.$ESC[0m`n"
        Write-Host "$ESC[31m[!] (or go visit a guild store in-game and press scan then /reloadui)$ESC[0m`n"
        Read-Host "$ESC[33mPress Enter to return...$ESC[0m" | Out-Null
        return
    }

    if (Test-Path $CONFIG_FILE) {
        $saved = Get-Content $CONFIG_FILE | Where-Object { $_ -match '^TARGET_USERNAME=' } | Select-Object -Last 1
        if ($saved -match '^TARGET_USERNAME="?([^"]*)"?$') { $global:TARGET_USERNAME = $matches[1] }
    }

    $script:bCacheDir = "$TARGET_DIR\Cache"
    if (!(Test-Path $script:bCacheDir)) { New-Item -ItemType Directory -Force -Path $script:bCacheDir | Out-Null }

    while ($true) {
        $cur = if ($global:TARGET_USERNAME) { $global:TARGET_USERNAME } else { "None" }
        Write-Host "`n$ESC[33mSelect a Database Function:$ESC[0m"
        Write-Host " 1) View / Search Database (Paginated & Sorted)"
        Write-Host " 2) Top 10 Most Selling Items (By Volume)"
        Write-Host " 3) Top 10 Highest Grossing Items (By Total Gold)"
        Write-Host " 4) Suggested Price Calculator (Outlier Elimination)"
        Write-Host " 5) View Previous Extraction History (Paginated & Sorted)"
        Write-Host " 6) Settings: Edit My Target Username $ESC[90m(Current: $cur)$ESC[0m"
        Write-Host " 7) Exit Browser & Resume Updater"
        $opt = Read-Host "$ESC[33mChoice [1-7]$ESC[0m"

        switch ($opt) {
            "1" { Show-BrowseListing "db" }
            "2" { Show-BrowseTop "vol" }
            "3" { Show-BrowseTop "gold" }
            "4" { Show-BrowsePrice }
            "5" { Show-BrowseListing "scan" }
            "6" { Set-BrowseUser }
            "7" { Log-Event "INFO" "browse_database: exiting DB browser" }
            default { Write-Host "$ESC[31mInvalid option.$ESC[0m" }
        }
        if ($opt -eq "7") { break }
    }
    Clear-Host
    if (!$global:SILENT -and (Test-Path $UI_STATE_FILE)) { Get-Content -LiteralPath $UI_STATE_FILE -Raw | Write-Host -NoNewline }
}
function Apply-DB-Updates($updates) {
    if (!$updates -or @($updates).Count -eq 0) { return }
    Log-Event "INFO" "apply_db_updates: applying database updates"

    $header = New-Object System.Collections.Generic.List[string]
    $dbLines = New-Object System.Collections.Hashtable
    if (Test-Path $DB_FILE) {
        foreach ($line in [System.IO.File]::ReadAllLines($DB_FILE)) {
            $p = $line.Split('|')
            if ($line.StartsWith("#DATABASE VERSION")) { $header.Add($line) }
            if ($p[0] -eq "GUILD") { $dbLines["GUILD_" + $p[1]] = $line }
            elseif ($p[0] -eq "KIOSK") { $dbLines["KIOSK_" + $p[1]] = $line }
            elseif ($p[0] -match '^[0-9]+$') { $dbLines["ITEM_" + $p[0]] = $line }
        }
    }

    foreach ($u in @($updates)) {
        $p = $u.Split('|')
        if ($p[0] -eq "DB_UPDATE") { $dbLines["ITEM_" + $p[1]] = ($p[1..($p.Length - 1)] -join '|') }
        elseif ($p[0] -eq "DB_GUILD") { $dbLines["GUILD_" + $p[1]] = "GUILD|$($p[1])|$($p[2])" }
        elseif ($p[0] -eq "DB_KIOSK") { $dbLines["KIOSK_" + $p[1]] = "KIOSK|$($p[1])|$($p[2])|$($p[3])|$($p[4])" }
    }

    $vals = [string[]]@($dbLines.Values)
    $keys = New-Object 'string[]' $vals.Length
    for ($i = 0; $i -lt $vals.Length; $i++) {
        $p = $vals[$i].Split('|')
        $keys[$i] = "$($p[0])`0$(if ($p.Length -ge 7) { $p[6] })`0$(if ($p.Length -ge 6) { $p[5] })`0$($vals[$i])"
    }
    [Array]::Sort($keys, $vals, [StringComparer]::Ordinal)

    $final = New-Object System.Collections.Generic.List[string]
    $final.AddRange($header); $final.AddRange($vals)
    [System.IO.File]::WriteAllText($DB_FILE, $(if ($final.Count) { ($final -join "`n") + "`n" } else { "" }), (New-Object System.Text.UTF8Encoding $false))
}
function Get-KioskLink($kiosk, $mapId) {
    if ($global:k_dict.ContainsKey($kiosk)) {
        $kp = $global:k_dict[$kiosk].Split('|')
        $kLoc = $kp[0]; $kMap = if ($kp.Length -ge 2) { $kp[1] } else { "" }; $kCoords = if ($kp.Length -ge 3) { $kp[2] } else { "" }
        if ($kMap -ne "" -and $kCoords -ne "") { return " $ESC[90m($ESC]8;;https://eso-hub.com/en/interactive-map?map=$kMap&ping=$kCoords$ESC\$kLoc$ESC]8;;$ESC\)$ESC[0m" }
        if ($kMap -ne "") { return " $ESC[90m($ESC]8;;https://eso-hub.com/en/interactive-map?map=$kMap$ESC\$kLoc$ESC]8;;$ESC\)$ESC[0m" }
        return " $ESC[90m($kLoc)$ESC[0m"
    }
    if ($mapId) { return " $ESC[90m($ESC]8;;https://eso-hub.com/en/interactive-map?map=$mapId$ESC\$kiosk$ESC]8;;$ESC\)$ESC[0m" }
    return " $ESC[90m($kiosk)$ESC[0m"
}

function Replace-First([string]$text, [string]$find, [string]$with) {
    $i = $text.IndexOf($find)
    if ($i -lt 0) { return $text }
    return $text.Substring(0, $i) + $with + $text.Substring($i + $find.Length)
}

function Invoke-EsoHubExtraction($svFile, $lastTime, $nowTime) {
    $dbGuildName = @{}; $dbCols = @{}; $dbQual = @{}; $dbName = @{}
    if (Test-Path $DB_FILE) {
        foreach ($l in [System.IO.File]::ReadLines($DB_FILE)) {
            $p = $l.Split('|')
            if ($p[0] -eq "GUILD") { if ($p.Length -ge 3) { $dbGuildName[$p[2]] = $p[1] } }
            elseif ($p[0] -match '^[0-9]+$') {
                $dbCols[$p[0]] = $p.Length; $dbQual[$p[0]] = if ($p.Length -ge 2) { $p[1] } else { "" }
                $dbName[$p[0]] = if ($p.Length -ge 6) { $p[5] } elseif ($p.Length -ge 3) { $p[2] } else { "" }
            }
        }
    }

    $lastTime = To-Num $lastTime; $maxTime = $lastTime
    $inTrader = $false; $inGuild = $false; $currentTrader = ""; $currentGid = ""; $buffered = ""; $scanType = ""
    $traderMaps = @{}; $guildKiosks = @{}; $guildMaps = @{}; $guildNames = @{}; $dbUpdated = @{}; $dbGuildUpdated = @{}
    $lines = New-Object System.Collections.Generic.List[string]
    $hist = New-Object System.Collections.Generic.List[string]
    $lineGid = New-Object System.Collections.Generic.List[string]

    foreach ($raw in [System.IO.File]::ReadLines($svFile)) {
        $line = if ($raw.EndsWith("`r")) { $raw.Substring(0, $raw.Length - 1) } else { $raw }
        if ($line.Contains('["traderData"]')) { $inTrader = $true; $inGuild = $false }
        if ($line.Contains('["guildData"]')) { $inGuild = $true; $inTrader = $false }

        if ($inTrader -and $line -match '^[ \t]*\["([^"]+)"\][ \t]*=[ \t]*$') {
            $val = $matches[1]
            if ($val -ne "NA Megaserver" -and $val -ne "EU Megaserver" -and $val -ne "PTS" -and $val -ne "guildHistory") { $currentTrader = $val }
        }
        if ($inTrader -and $line -match '\["mapId"\][ \t]*=[ \t]*[0-9]+') {
            if ($line -match '[0-9]+' -and $currentTrader -ne "") { $traderMaps[$currentTrader] = $matches[0] }
        }
        if ($inTrader -and $line -match '^[ \t]*\[[0-9]+\][ \t]*=[ \t]*[0-9]+') {
            if ($line -match '=[ \t]*([0-9]+)' -and $currentTrader -ne "") {
                $gid = $matches[1]; $guildKiosks[$gid] = $currentTrader
                if ($traderMaps[$currentTrader]) { $guildMaps[$gid] = $traderMaps[$currentTrader] }
            }
        }
        if ($inGuild -and $line -match '^[ \t]*\[[0-9]+\][ \t]*=[ \t]*$') {
            [void]($line -match '[0-9]+'); $currentGid = $matches[0]; $buffered = ""; $scanType = ""
        }
        if ($inGuild -and $line -match '\["guildId"\][ \t]*=[ \t]*[0-9]+') {
            [void]($line -match '[0-9]+'); $currentGid = $matches[0]
            if ($buffered -ne "") { $guildNames[$currentGid] = $buffered; $dbGuildUpdated[$buffered] = $currentGid; $buffered = "" }
        }
        if ($inGuild -and $line -match '\["(traderGuildName|guildName)"\][ \t]*=[ \t]*"([^"]+)"') {
            $val = $matches[2]
            if ($currentGid -ne "") { $guildNames[$currentGid] = $val; $dbGuildUpdated[$val] = $currentGid } else { $buffered = $val }
        }
        if ($line -match '\["(scannedSales|scannedItems|cancelledItems|purchasedItems|traderHistory)"\]') {
            switch ($matches[1]) {
                "scannedSales" { $scanType = "Sold" }; "scannedItems" { $scanType = "Listed" }; "cancelledItems" { $scanType = "Cancelled" }
                "purchasedItems" { $scanType = "Purchased" }; "traderHistory" { $scanType = "History" }
            }
        }

        if ($line.IndexOf(":item:") -lt 0 -or $scanType -eq "") { continue }
        $sIdx = $line.IndexOf('"|H')
        if ($sIdx -lt 0) { continue }
        $tStr = $line.Substring($sIdx + 1)
        $eIdx = $tStr.IndexOf('",'); if ($eIdx -lt 0) { $eIdx = $tStr.IndexOf('"') }
        if ($eIdx -lt 0) { continue }
        $fullVal = $tStr.Substring(0, $eIdx)
        $splitIdx = $fullVal.IndexOf('|h|h,'); $offset = 5
        if ($splitIdx -lt 0) { $splitIdx = $fullVal.IndexOf('|h,'); $offset = 3 }
        if ($splitIdx -lt 0) { continue }

        $itemLink = $fullVal.Substring(0, $splitIdx + 2)
        $dataCsv = $fullVal.Substring($splitIdx + $offset)
        $lp = $itemLink.Split(':')
        $itemid = if ($lp.Length -ge 3) { $lp[2] } else { "" }
        $s = if ($lp.Length -ge 4) { To-Num $lp[3] } else { 0 }
        $v = if ($lp.Length -ge 5) { To-Num $lp[4] } else { 0 }

        $arr = if ($dataCsv -eq "") { @() } else { $dataCsv.Split(',') }
        $len = $arr.Count
        $price = if ($len -ge 1) { $arr[0] } else { "" }
        $qty = if ($len -ge 2) { $arr[1] } else { "" }
        if ($qty -eq "") { $qty = "1" }
        $buyer = ""; $seller = ""
        if ($len -ge 5) { $buyer = $arr[2]; $seller = $arr[3]; $stime = To-Num $arr[4] }
        else { $seller = if ($len -ge 3) { $arr[2] } else { "" }; $stime = if ($len -ge 4) { To-Num $arr[3] } else { 0 } }
        if (!($stime -gt 1400000000)) {
            $stime = 0
            for ($idx = $len - 1; $idx -ge 2; $idx--) {
                if ($arr[$idx] -match '^[0-9]+$' -and [double]$arr[$idx] -gt 1400000000) { $stime = [double]$arr[$idx]; break }
            }
        }
        if ($buyer -ne "" -and $buyer -notmatch '^@') { $buyer = "@$buyer" }
        if ($seller -ne "" -and $seller -notmatch '^@') { $seller = "@$seller" }

        $realName = if ($dbName.ContainsKey($itemid) -and $dbName[$itemid] -notmatch '^Unknown Item') { $dbName[$itemid] } else { "Unknown Item ($itemid)" }
        $realQual = if ($dbQual.ContainsKey($itemid)) { [int](To-Num $dbQual[$itemid]) } else { Calc-Quality $itemid $realName $s $v }

        if ($realName.IndexOf("Unknown Item (") -lt 0) {
            $needs = ($dbName[$itemid] -ne $realName) -or !$dbQual.ContainsKey($itemid) -or ([int](To-Num $dbQual[$itemid]) -ne [int]$realQual) -or ((To-Num $dbCols[$itemid]) -lt 7)
            if ($needs) {
                $dbUpdated[$itemid] = "$itemid|$realQual|$s|$v|$(Get-HQ $realQual)|$realName|$(Get-Cat $realName $itemid $s $v)"
                $dbName[$itemid] = $realName; $dbQual[$itemid] = "$realQual"; $dbCols[$itemid] = 7
            }
        }

        if ($realName -ne "" -and $price -ne "") {
            if ($stime -gt $maxTime) { $maxTime = $stime }
            if ($stime -gt $lastTime -or $stime -eq 0 -or $scanType -eq "Listed") {
                $c = Get-QualityColor $realQual
                $itemDisplay = "$ESC]8;;https://eso-hub.com/en/trading/$itemid$ESC\$c$realName$ESC[0m$ESC]8;;$ESC\"
                $tradeStr = ""
                if ($seller -ne "" -and $buyer -ne "") { $tradeStr = " by $ESC[36m$seller$ESC[0m to $ESC[36m$buyer$ESC[0m" }
                elseif ($seller -ne "") { $tradeStr = " by $ESC[36m$seller$ESC[0m" }
                elseif ($buyer -ne "") { $tradeStr = " to $ESC[36m$buyer$ESC[0m" }
                $age = (To-Num $nowTime) - $stime; $statusTag = ""
                if ($scanType -eq "Sold") { $statusTag = " $ESC[38;5;214m[SOLD]$ESC[0m" }
                elseif ($scanType -eq "Purchased") { $statusTag = " $ESC[92m[PURCHASED]$ESC[0m" }
                elseif ($scanType -eq "Cancelled") { $statusTag = " $ESC[31m[CANCELLED]$ESC[0m" }
                elseif ($scanType -eq "Listed") { $statusTag = if ($stime -gt 0 -and $age -gt 2592000) { " $ESC[90m[EXPIRED]$ESC[0m" } else { " $ESC[34m[AVAILABLE]$ESC[0m" } }
                $ts = [long]$stime
                $lines.Add("$ts| $ESC[36m$scanType$ESC[0m for $ESC[32m$price$ESC[33mgold$ESC[0m - $ESC[32m${qty}x$ESC[0m $itemDisplay$tradeStr in GUILD_PLACEHOLDER_$currentGid$statusTag")
                $hist.Add($(if ($currentGid -ne "") { "HISTORY|$ts|$scanType|$price|$qty|$itemid|$realName|$buyer|$seller|$currentGid||$c|ESO-Hub" } else { "" }))
                $lineGid.Add($currentGid)
            }
        }
    }

    foreach ($gid in @($dbGuildName.Keys)) { if (!$guildNames.ContainsKey($gid)) { $guildNames[$gid] = $dbGuildName[$gid] } }
    $outLines = New-Object System.Collections.Generic.List[string]
    $outHist = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $gid = $lineGid[$i]
        $gname = if ($guildNames.ContainsKey($gid)) { $guildNames[$gid] } else { "" }
        if ($gname -eq "" -and $dbGuildName.ContainsKey($gid)) { $gname = $dbGuildName[$gid] }
        if ($gname -ne "" -and $gname -ne "Unknown Guild") { $gLink = "$ESC[35m$ESC]8;;|H1:guild:$gid|h$gname|h$ESC\$gname$ESC]8;;$ESC\$ESC[0m" }
        else { $gLink = "$ESC[35mUnknown Guild$ESC[0m"; $gname = "Unknown Guild" }
        $kiosk = if ($guildKiosks.ContainsKey($gid)) { $guildKiosks[$gid] } else { "" }
        $kStr = if ($kiosk -ne "") { Get-KioskLink $kiosk $guildMaps[$gid] } else { "" }
        $outLines.Add((Replace-First $lines[$i] "GUILD_PLACEHOLDER_$gid" "$gLink$kStr"))
        if ($hist[$i] -ne "") { $outHist.Add((Replace-First $hist[$i] "$gid||" "$gname|$kiosk|")) }
    }
    $updates = New-Object System.Collections.Generic.List[string]
    foreach ($k in $dbUpdated.Keys) { $updates.Add("DB_UPDATE|$($dbUpdated[$k])") }
    foreach ($g in $dbGuildUpdated.Keys) { $updates.Add("DB_GUILD|$g|$($dbGuildUpdated[$g])") }
    return [PSCustomObject]@{ Lines = $outLines.ToArray(); History = $outHist.ToArray(); MaxTime = [long]$maxTime; DbUpdates = $updates.ToArray() }
}
function Invoke-TtcExtraction($svFile, $lastTime, $nowTime) {
    $dbGuildId = @{}; $dbCols = @{}; $dbQual = @{}; $dbName = @{}
    if (Test-Path $DB_FILE) {
        foreach ($l in [System.IO.File]::ReadLines($DB_FILE)) {
            $p = $l.Split('|')
            if ($p[0] -eq "GUILD") { if ($p.Length -ge 3) { $dbGuildId[$p[1]] = $p[2] } }
            elseif ($p[0] -match '^[0-9]+$') {
                $dbCols[$p[0]] = $p.Length; $dbQual[$p[0]] = if ($p.Length -ge 2) { $p[1] } else { "" }
                $dbName[$p[0]] = if ($p.Length -ge 6) { $p[5] } elseif ($p.Length -ge 3) { $p[2] } else { "" }
            }
        }
    }

    $lastTime = To-Num $lastTime; $nowTime = To-Num $nowTime; $maxTime = $lastTime
    $path = @{}; $guildKiosks = @{}; $dbUpdated = @{}
    $inItem = $false; $itemLvl = 0
    $action = "Listed"; $guild = ""; $player = ""; $seller = ""; $buyer = ""
    $amt = ""; $stime = ""; $price = ""; $itemid = ""; $subtype = ""; $internalLevel = ""; $realName = ""; $kiosk = ""; $gameQual = ""
    $lines = New-Object System.Collections.Generic.List[string]
    $hist = New-Object System.Collections.Generic.List[string]

    foreach ($raw in [System.IO.File]::ReadLines($svFile)) {
        $line = if ($raw.EndsWith("`r")) { $raw.Substring(0, $raw.Length - 1) } else { $raw }

        if ($line -match '^[ \t]*\["?([^"]+)"?\][ \t]*=') {
            [void]($line -match '^[ \t]*'); $lvl = $matches[0].Length
            [void]($line -match '^[ \t]*\["?([^"]+)"?\]'); $key = $matches[1]
            foreach ($k in @($path.Keys)) { if ([int]$k -ge $lvl) { $path.Remove($k) } }
            $path[$lvl] = $key

            if ($key -eq "KioskLocationID" -or ($key -match '^[0-9]+$' -and !$inItem)) {
                $sorted = [int[]]@($path.Keys); [Array]::Sort($sorted)
            }
            if ($key -eq "KioskLocationID") {
                $gname = ""
                for ($i = 0; $i -lt $sorted.Count; $i++) { if ($path[$sorted[$i]] -eq "Guilds" -and ($i + 1) -lt $sorted.Count) { $gname = $path[$sorted[$i + 1]] } }
                if ($gname -ne "" -and $line -match '[0-9]+') { $guildKiosks[$gname] = $matches[0] }
            }
            if ($key -match '^[0-9]+$' -and !$inItem) {
                $inItem = $true; $itemLvl = $lvl
                $action = "Listed"; $guild = ""; $player = ""; $seller = ""; $buyer = ""
                $amt = ""; $stime = ""; $price = ""; $itemid = ""; $subtype = ""; $internalLevel = ""; $realName = ""; $gameQual = ""
                for ($i = 0; $i -lt $sorted.Count; $i++) {
                    $k = $path[$sorted[$i]]
                    if ($k -eq "SaleHistoryEntries") { $action = "Sold" }
                    if ($k -eq "AutoRecordEntries" -or $k -eq "Entries") { $action = "Listed" }
                    if ($k -eq "Guilds" -and ($i + 1) -lt $sorted.Count) { $guild = $path[$sorted[$i + 1]] }
                    if ($k -eq "PlayerListings" -and ($i + 1) -lt $sorted.Count) { $player = $path[$sorted[$i + 1]] }
                }
            }
        }
        if (!$inItem) { continue }

        if ($line -match '\["Amount"\][ \t]*=' -and $line -match '[0-9]+') { $amt = $matches[0] }
        if ($line -match '\["SaleTime"\][ \t]*=' -and $line -match '[0-9]+') { $stime = $matches[0] }
        if ($line -match '\["Timestamp"\][ \t]*=' -and $line -match '[0-9]+') { if ($stime -eq "") { $stime = $matches[0] } }
        if ($line -match '\["TimeStamp"\][ \t]*=' -and $line -match '[0-9]+') { if ($stime -eq "") { $stime = $matches[0] } }
        if ($line -match '\["QualityID"\][ \t]*=' -and $line -match '[0-9]+') { $gameQual = $matches[0] }
        if ($line -match '\["TotalPrice"\][ \t]*=' -and $line -match '[0-9]+') { $price = $matches[0] }
        if ($line -match '\["Price"\][ \t]*=' -and $line -notmatch 'TotalPrice' -and $line -match '[0-9]+') { if ($price -eq "") { $price = $matches[0] } }
        if ($line -match '\["Buyer"\][ \t]*=[ \t]*"([^"]+)"') { $buyer = $matches[1] }
        if ($line -match '\["Seller"\][ \t]*=[ \t]*"([^"]+)"') { $seller = $matches[1] }
        if ($line -match '\["ItemLink"\][ \t]*=') {
            if ($line -match '\|H[0-9a-fA-F]*:item:[0-9]+') { $itemid = $matches[0].Split(':')[2] }
            if ($line -match '"(\|H[^"]+)"') { $lp = $matches[1].Split(':'); $subtype = if ($lp.Length -ge 4) { $lp[3] } else { "" }; $internalLevel = if ($lp.Length -ge 5) { $lp[4] } else { "" } }
        }
        if ($line -match '\["Name"\][ \t]*=') {
            $val = $line -replace '.*Name"\][ \t]*=[ \t]*"', ''
            $val = $val -replace '",[ \t]*$', ''
            $realName = $val.Replace('\"', '"')
        }

        if ($line -match '^[ \t]*\},?[ \t]*$') {
            [void]($line -match '^[ \t]*')
            if ($matches[0].Length -gt $itemLvl) { continue }
            $inItem = $false
            $stimeNum = if ($stime -eq "") { 0 } else { To-Num $stime }
            if ($stimeNum -gt $maxTime) { $maxTime = $stimeNum }
            if (!($stimeNum -gt $lastTime -or $lastTime -eq 0 -or $action -eq "Listed")) { continue }
            if ($amt -eq "") { $amt = "1" }
            if ($realName -eq "" -or $realName -match '^\|[0-9]+\|$') {
                $realName = if ($dbName.ContainsKey($itemid) -and $dbName[$itemid] -notmatch '^Unknown Item') { $dbName[$itemid] } else { "Unknown Item ($itemid)" }
            }
            if ($price -eq "") { continue }

            $s = To-Num $subtype; $v = To-Num $internalLevel
            if ($dbName.ContainsKey($itemid)) {
                $needs = ($realName -ne $dbName[$itemid] -and $realName -notmatch '^Unknown Item') -or ((To-Num $dbCols[$itemid]) -lt 7)
            } else { $needs = $true }
            if ($gameQual -ne "") {
                $realQual = [int]$gameQual + 1
                if (-not $dbQual.ContainsKey($itemid) -or [int](To-Num $dbQual[$itemid]) -ne $realQual) { $needs = $true }
            } elseif ($dbQual.ContainsKey($itemid)) {
                $realQual = [int](To-Num $dbQual[$itemid])
            } else {
                $realQual = Calc-Quality $itemid $realName $s $v
            }
            if ($realName.StartsWith("Unknown Item (")) { $needs = $false }
            if ($needs) {
                $dbUpdated[$itemid] = "$itemid|$realQual|$s|$v|$(Get-HQ $realQual)|$realName|$(Get-Cat $realName $itemid $s $v)"
                $dbName[$itemid] = $realName; $dbQual[$itemid] = "$realQual"; $dbCols[$itemid] = 7
            }
            $c = Get-QualityColor $realQual

            $guildStr = ""; $kiosk = ""
            if ($guild -ne "" -and $guild -ne "Unknown Guild" -and $guild -ne "Guilds") {
                $gDisplay = if ($dbGuildId.ContainsKey($guild)) { "$ESC[35m$ESC]8;;|H1:guild:$($dbGuildId[$guild])|h$guild|h$ESC\$guild$ESC]8;;$ESC\$ESC[0m" } else { "$ESC[35m$guild$ESC[0m" }
                $kiosk = if ($guildKiosks.ContainsKey($guild)) { $guildKiosks[$guild] } else { "" }
                if ($kiosk -ne "" -and $kiosk -ne "0") {
                    $kStr = if ($global:k_dict.ContainsKey($kiosk)) { Get-KioskLink $kiosk "" } else { " $ESC[90m(Kiosk ID: $kiosk)$ESC[0m" }
                } else { $kStr = " $ESC[90m(Local Trader)$ESC[0m" }
                $guildStr = " in $gDisplay$kStr"
            }

            $playerClean = $player
            if ($playerClean -ne "" -and $playerClean -notmatch '^@') { $playerClean = "@$playerClean" }
            if ($buyer -ne "" -and $buyer -notmatch '^@') { $buyer = "@$buyer" }
            if ($seller -ne "" -and $seller -notmatch '^@') { $seller = "@$seller" }
            if ($seller -eq "" -and $playerClean -ne "") { $seller = $playerClean }
            $tradeStr = ""
            if ($seller -ne "" -and $buyer -ne "") { $tradeStr = " by $ESC[36m$seller$ESC[0m to $ESC[36m$buyer$ESC[0m" }
            elseif ($seller -ne "") { $tradeStr = " by $ESC[36m$seller$ESC[0m" }
            elseif ($buyer -ne "") { $tradeStr = " to $ESC[36m$buyer$ESC[0m" }
            elseif ($playerClean -ne "" -and $playerClean -ne $guild) { $tradeStr = " by $ESC[36m$playerClean$ESC[0m" }

            $nameEnc = $realName.Replace(" ", "+").Replace("'", "%27")
            $linkStart = "$ESC]8;;https://us.tamrieltradecentre.com/pc/Trade/SearchResult?SearchType=Sell&ItemNamePattern=$nameEnc$ESC\"
            $age = $nowTime - $stimeNum; $statusTag = ""
            if ($action -eq "Sold") { $statusTag = " $ESC[38;5;214m[SOLD]$ESC[0m" }
            elseif ($action -eq "Listed") { $statusTag = if ($stimeNum -gt 0 -and $age -gt 2592000) { " $ESC[90m[EXPIRED]$ESC[0m" } else { " $ESC[34m[AVAILABLE]$ESC[0m" } }
            $ts = if ($stimeNum -gt 0) { [long]$stimeNum } else { 0 }

            $lines.Add("$ts| $ESC[36m$action$ESC[0m for $ESC[32m$price$ESC[33mgold$ESC[0m - $ESC[32m${amt}x$ESC[0m $linkStart$c$realName$ESC[0m$ESC]8;;$ESC\$tradeStr$guildStr$statusTag")
            if ($guild -ne "Guilds" -and $guild -ne "Unknown Guild" -and $guild -ne "") {
                $hist.Add("HISTORY|$ts|$action|$price|$amt|$itemid|$realName|$buyer|$seller|$guild|$kiosk|$c|TTC")
            } elseif ($action -eq "Listed" -and $seller -ne "") {
                $hist.Add("HISTORY|$ts|$action|$price|$amt|$itemid|$realName|$buyer|$seller||$kiosk|$c|TTC")
            }
        }
    }

    $updates = New-Object System.Collections.Generic.List[string]
    foreach ($k in $dbUpdated.Keys) { $updates.Add("DB_UPDATE|$($dbUpdated[$k])") }
    foreach ($k in $global:k_dict.Keys) { $updates.Add("DB_KIOSK|$k|$($global:k_dict[$k])") }
    return [PSCustomObject]@{ Lines = $lines.ToArray(); History = $hist.ToArray(); MaxTime = [long]$maxTime; DbUpdates = $updates.ToArray() }
}
$TTC_WEB_CLIENT_VERSION = "3.1.0.0"
$TTC_BATCH_SIZE = 100

function Get-TTCClientId {
    if ([string]::IsNullOrEmpty($global:TTC_CLIENT_ID)) {
        $global:TTC_CLIENT_ID = [guid]::NewGuid().ToString()
        $global:CONFIG_CHANGED = $true
    }
    return $global:TTC_CLIENT_ID
}

function ConvertFrom-TTCKey([string]$s) {
    $s = $s.Trim().TrimStart('[').TrimEnd(']')
    if ($s.Length -ge 2 -and $s.StartsWith('"') -and $s.EndsWith('"')) { $s = $s.Substring(1, $s.Length - 2) }
    return $s
}

function Add-TTCJson([string]$json, [string]$name, $value) {
    if ([string]::IsNullOrEmpty($value) -or $value -eq "nil") { return $json }
    $sep = if ($json -eq "") { "" } else { "," }
    return "$json$sep`"$name`":$value"
}

function Get-TTCList($table) {
    $nums = @($table.Keys | Where-Object { $_ -like '#*' } | ForEach-Object { [double]$table[$_] } | Sort-Object)
    return "[" + (($nums | ForEach-Object { $_.ToString([Globalization.CultureInfo]::InvariantCulture) }) -join ",") + "]"
}

function Get-TTCItemJson($t) {
    $j = ""
    foreach ($pair in @(@("ID", "ID"), @("UID", "UID"), @("QualityID", "QualityID"), @("Category2IDOverWrite", "Category2IDOverWrite"),
                        @("TraitID", "TraitID"), @("LevelTotal", "Level"), @("PotionEffectIDs", "PotionEffects"))) {
        $j = Add-TTCJson $j $pair[0] $t[$pair[1]]
    }
    $mw = if ($t.ContainsKey("MasterWritInfo")) { $t["MasterWritInfo"] } else { "null" }
    return "{" + (Add-TTCJson $j "MasterWritInfo" $mw) + "}"
}

function Read-TTCUpload([string]$path, [string]$region, [long]$now, [string]$cache) {
    $sent = @{}
    if ($cache -and (Test-Path -LiteralPath $cache)) {
        foreach ($l in [IO.File]::ReadLines($cache)) { $p = $l.Split("`t"); if ($p.Count -ge 2) { $sent["$($p[0])|$($p[1])"] = $true } }
    }
    $stack = New-Object System.Collections.Generic.List[string]
    $tables = New-Object System.Collections.Generic.List[hashtable]
    $pending = ""
    $self = New-Object System.Collections.Generic.List[object]
    $auto = New-Object System.Collections.Generic.List[object]
    $guildInfo = @{}; $autoGuild = @{}; $settings = @{}; $accounts = @{}
    $dataKey = "${region}Data"

    foreach ($raw in [IO.File]::ReadLines($path)) {
        $t = $raw.Trim()
        if ($t -eq "{") { $stack.Add($pending); $tables.Add(@{}); $pending = ""; continue }
        if ($t -eq "}" -or $t -eq "},") {
            $d = $stack.Count
            $key = $stack[$d - 1]; $tbl = $tables[$d - 1]
            $s = { param($i) if ($stack.Count -gt $i) { $stack[$i] } else { "" } }
            if ($d -ge 2 -and ($key -eq "PotionEffects" -or $key -eq "RequiredPotionEffectIDs")) {
                $tables[$d - 2][$key] = Get-TTCList $tbl
            } elseif ($key -eq "MasterWritInfo") {
                $j = ""
                foreach ($k in @("RequiredItemID", "RequiredQualityID", "RequiredTraitID", "RequiredSetID", "RequiredStyleID", "RequiredPotionEffectIDs", "NumVoucher")) {
                    $j = Add-TTCJson $j $k $tbl[$k]
                }
                $tables[$d - 2]["MasterWritInfo"] = "{$j}"
            } elseif ($d -eq 9 -and (& $s 4) -eq $dataKey -and (& $s 5) -eq "Guilds" -and (& $s 7) -eq "Entries") {
                $self.Add(@{ Acct = $stack[2]; Guild = $stack[6]; Table = $tbl })
            } elseif ($d -eq 7 -and (& $s 4) -eq $dataKey -and (& $s 5) -eq "Guilds") {
                $guildInfo["$($stack[2])`t$($stack[6])"] = $tbl
            } elseif ($d -eq 11 -and (& $s 4) -eq $dataKey -and (& $s 5) -eq "AutoRecordEntries" -and (& $s 8) -eq "PlayerListings") {
                $auto.Add(@{ Acct = $stack[2]; Guild = $stack[7]; Player = $stack[9]; Table = $tbl })
            } elseif ($d -eq 8 -and (& $s 4) -eq $dataKey -and (& $s 5) -eq "AutoRecordEntries" -and (& $s 6) -eq "Guilds") {
                $autoGuild["$($stack[2])`t$($stack[7])"] = $tbl
            } elseif ($d -eq 5 -and $key -eq "Settings") {
                $settings[$stack[2]] = $tbl
            } elseif ($d -eq 4 -and $key -eq '$AccountWide') {
                $accounts[$stack[2]] = $tbl
            }
            $stack.RemoveAt($d - 1); $tables.RemoveAt($d - 1)
            continue
        }
        $eq = $t.IndexOf("=")
        if ($eq -lt 0) { continue }
        $k = ConvertFrom-TTCKey $t.Substring(0, $eq)
        $v = $t.Substring($eq + 1).Trim().TrimEnd(',').Trim()
        if ($v -eq "") { $pending = $k; continue }
        if ($k -match '^\d+$') { $k = "#$k" }
        if ($tables.Count -gt 0) { $tables[$tables.Count - 1][$k] = $v }
    }

    $best = @{}; $noId = New-Object System.Collections.Generic.List[string]; $kiosks = @{}; $culture = ""; $seen = @{ Newest = [long]0 }
    $keep = {
        param($guild, $player, $tbl, $discover, $expire, $kiosk)
        if ([string]::IsNullOrEmpty($discover) -or [string]::IsNullOrEmpty($expire)) { return }
        $dv = [long][double]$discover; $ev = [long][double]$expire
        if ($dv -le $now -and $dv -gt $seen.Newest) { $seen.Newest = $dv }
        $uid = "$($tbl['UID'])".Trim('"')
        if ($uid -eq "" -or $uid -eq "0") { return }
        if ($sent.ContainsKey("$uid|$dv") -or $now -gt $ev -or $dv -gt $now -or $now - $dv -gt 21600) { return }
        if (-not $tbl.ContainsKey("ID")) { if ($tbl["ItemLink"]) { $noId.Add("$($tbl['ItemLink'])".Trim('"')) }; return }
        $asset = Add-TTCJson (Add-TTCJson "" "Amount" $tbl["Amount"]) "TotalPrice" $tbl["TotalPrice"]
        $json = "{`"TradeAsset`":{$asset,`"Item`":$(Get-TTCItemJson $tbl)},`"PlayerID`":`"$player`",`"GuildID`":@@"
        if (-not [string]::IsNullOrEmpty($kiosk)) { $json += ",`"GuildKioskLocationID`":$kiosk" }
        $json += ",`"DiscoverUnixTime`":$dv,`"ExpireUnixTime`":$ev}"
        if ($best.ContainsKey($uid) -and $best[$uid].Discover -ge $dv) { return }
        $best[$uid] = @{ Discover = $dv; Guild = $guild; Json = $json; Uid = $uid }
    }

    foreach ($acct in $accounts.Keys) {
        $info = $accounts[$acct]
        if ([double]("0" + "$($info['ActualVersion'])") -lt 7) { continue }
        if ($culture -eq "") { $culture = "$($info['ClientCulture'])".Trim('"') }
        $set = $settings[$acct]
        if ($set -and $set["EnableAutoRecordStoreEntries"] -eq "true") {
            foreach ($e in $auto) {
                if ($e.Acct -ne $acct) { continue }
                $g = $autoGuild["$acct`t$($e.Guild)"]
                if (-not $g -or [string]::IsNullOrEmpty($g["KioskLocationID"])) { continue }
                & $keep $e.Guild $e.Player $e.Table $e.Table["DiscoverTime"] $e.Table["ExpireTime"] $g["KioskLocationID"]
                $kiosks[$e.Guild] = @($g["KioskLocationID"], $g["LastUpdate"])
            }
        }
        if ($set -and $set["EnableSelfEntriesUpload"] -eq "true") {
            foreach ($e in $self) {
                if ($e.Acct -ne $acct) { continue }
                $g = $guildInfo["$acct`t$($e.Guild)"]
                $scan = if ($g) { $g["LastFullScan"] } else { "" }
                $expire = if ($scan) { [string]([long][double]$scan + 604800) } else { "" }
                $kiosk = if ($g) { $g["KioskLocationID"] } else { "" }
                & $keep $e.Guild $acct $e.Table $scan $expire $kiosk
            }
        }
    }
    return @{ Entries = @($best.Values); NoId = $noId; Kiosks = $kiosks; Culture = $culture; Newest = $seen.Newest }
}

function Send-TTCJson([string]$domain, [string]$file, [string]$route) {
    & curl.exe -s -f -m 60 -X POST -A "$TTC_USER_AGENT" -H "Content-Type: application/json; charset=UTF-8" `
        -H "WebClientVersion: $TTC_WEB_CLIENT_VERSION" -H "ClientID: $(Get-TTCClientId)" `
        --data-binary "@$file" "https://$domain$route" 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Get-TTCUploadCache([string]$region) { return (Join-Path $DB_DIR "LTTC_TTC_Uploaded_$region.txt") }

function Invoke-TTCUpload([string]$domain, [string]$region, [string]$sv) {
    $global:TTC_UPLOAD_COUNT = 0; $global:TTC_UPLOAD_NEWEST = 0
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $cache = Get-TTCUploadCache $region
    try { $parsed = Read-TTCUpload $sv $region $now $cache } catch { return $false }
    $global:TTC_UPLOAD_NEWEST = $parsed.Newest
    $work = Join-Path $TEMP_DIR_ROOT ("lttc_upload_" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $ok = $true; $count = 0
    try {
        $ids = @{}
        foreach ($guild in @($parsed.Entries | ForEach-Object { $_.Guild } | Sort-Object -Unique)) {
            $resp = & curl.exe -s -f -m 30 -G -A "$TTC_USER_AGENT" -H "WebClientVersion: $TTC_WEB_CLIENT_VERSION" `
                -H "ClientID: $(Get-TTCClientId)" --data-urlencode "guildName=$guild" "https://$domain/api/PC/Trade/GetGuildID" 2>$null
            if ("$resp" -match '"GuildID":(\d+)') { $ids[$guild] = $Matches[1] }
        }
        $ready = New-Object System.Collections.Generic.List[object]
        foreach ($e in $parsed.Entries) {
            if ($ids.ContainsKey($e.Guild)) { $ready.Add($e) } else { $ok = $false }
        }
        for ($i = 0; $i -lt $ready.Count; $i += $TTC_BATCH_SIZE) {
            $batch = $ready.GetRange($i, [Math]::Min($TTC_BATCH_SIZE, $ready.Count - $i))
            $file = Join-Path $work "batch.json"
            [IO.File]::WriteAllText($file, "[" + (($batch | ForEach-Object { $_.Json.Replace("@@", $ids[$_.Guild]) }) -join ",") + "]", $utf8)
            if (Send-TTCJson $domain $file "/api/PC/Trade/PostAutoRecordedEntry") {
                $count += $batch.Count
                [IO.File]::AppendAllText($cache, (($batch | ForEach-Object { "$($_.Uid)`t$($_.Discover)`t$now`n" }) -join ""), $utf8)
            } else { $ok = $false }
        }
        if ($ready.Count -gt 0) {
            $links = @($parsed.NoId | Sort-Object -Unique)
            if ($parsed.Culture -eq "en" -and $links.Count -gt 0 -and $links.Count -lt ($ready.Count / 5)) {
                $file = Join-Path $work "links.json"
                [IO.File]::WriteAllText($file, "[" + (($links | ForEach-Object { "`"$_`"" }) -join ",") + "]", $utf8)
                Send-TTCJson $domain $file "/api/PC/Trade/RecordItemLinks" | Out-Null
            }
            foreach ($guild in $parsed.Kiosks.Keys) {
                if (-not $ids.ContainsKey($guild)) { continue }
                $k = $parsed.Kiosks[$guild]
                $stamp = if ($k[1]) { $k[1] } else { 0 }
                $file = Join-Path $work "kiosk.json"
                [IO.File]::WriteAllText($file, "{`"GuildID`":$($ids[$guild]),`"GuildKioskLocationID`":$($k[0]),`"Timestamp`":$stamp}", $utf8)
                Send-TTCJson $domain $file "/api/PC/Trade/VerifyKioskLocation" | Out-Null
            }
        }
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $cache) {
        $cut = $now - 172800
        $keepLines = @([IO.File]::ReadAllLines($cache) | Where-Object { $p = $_.Split("`t"); $p.Count -ge 2 -and [long]("0" + $p[1]) -ge $cut })
        [IO.File]::WriteAllText($cache, $(if ($keepLines.Count) { ($keepLines -join "`n") + "`n" } else { "" }), $utf8)
    }
    $global:TTC_UPLOAD_COUNT = $count
    return $ok
}

function Get-TTCNothingNewReason {
    $newest = [long]$global:TTC_UPLOAD_NEWEST
    if ($newest -le 0) { return "no listings in TamrielTradeCentre.lua yet" }
    $clock = [DateTimeOffset]::FromUnixTimeSeconds($newest).ToLocalTime().ToString("HH:mm")
    if ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $newest -gt 21600) {
        return "newest scan saved is $clock, TTC takes the last 6 hours; ESO saves new scans on /reloadui or logout"
    }
    return "every listing up to $clock was already uploaded; ESO saves new scans on /reloadui or logout"
}
$ADDON_UPDATE_EXCLUDE = @("HarvestMapData", "EsoTradingHub", "EsoHubScanner", "LibEsoHubPrices")
$ADDON_UPDATE_INTERVAL = 21600

function Get-AddonExcludes {
    $list = New-Object System.Collections.Generic.List[string]
    $list.AddRange([string[]]$ADDON_UPDATE_EXCLUDE)
    foreach ($s in ("$global:ADDON_UPDATE_SKIP" -split '\s+')) { if ($s) { $list.Add($s) } }
    return ,$list.ToArray()
}

function Test-LinkedFolder($path) {
    try { return [bool]((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) } catch { return $false }
}

function Get-ManifestField([string[]]$lines, [string]$field) {
    foreach ($l in $lines) {
        if ($l -match ('^##\s*' + $field + ':')) { return $l }
    }
    return $null
}

function Get-AddonLocalList($dir) {
    $out = New-Object System.Collections.Generic.List[string]
    $latin = [System.Text.Encoding]::GetEncoding(28591)
    foreach ($top in @(Get-ChildItem -LiteralPath $dir -Directory -Force -ErrorAction SilentlyContinue | Where-Object { !$_.Name.StartsWith(".") } | Sort-Object Name)) {
        if (Test-LinkedFolder $top.FullName) { continue }
        $dirs = @($top) + @(Get-ChildItem -LiteralPath $top.FullName -Directory -Recurse -Depth 2 -ErrorAction SilentlyContinue | Where-Object { !(Test-LinkedFolder $_.FullName) })
        foreach ($d in $dirs) {
            $mf = Join-Path $d.FullName "$($d.Name).addon"
            if (!(Test-Path -LiteralPath $mf)) { $mf = Join-Path $d.FullName "$($d.Name).txt" }
            if (!(Test-Path -LiteralPath $mf)) { continue }
            $lines = [System.IO.File]::ReadAllText($mf, $latin) -split "`n"
            $av = ""; $ver = ""
            $l = Get-ManifestField $lines "AddOnVersion"
            if ($null -ne $l) {
                $v = $l.Replace("`r", ""); $v = $v.Substring($v.IndexOf(':') + 1).TrimStart(" `t")
                $av = ($v.Replace("|", "").Trim(" `t") -split '\s+')[0]
            }
            $l = Get-ManifestField $lines "Version"
            if ($null -ne $l) {
                $v = $l.Replace("`r", "").Replace("|", ""); $ver = $v.Substring($v.IndexOf(':') + 1).Trim(" `t")
            }
            $rel = $d.FullName.Substring($dir.TrimEnd('\', '/').Length + 1).Replace('\', '/')
            $out.Add("$rel|$av|$ver")
        }
    }
    return ,$out.ToArray()
}

function Get-JStr([string]$s, [string]$key) {
    $p = $s.IndexOf('"' + $key + '":"', [StringComparison]::Ordinal)
    if ($p -lt 0) { return "" }
    $i = $p + $key.Length + 4
    $sb = New-Object System.Text.StringBuilder
    while ($i -lt $s.Length) {
        $c = $s[$i]
        if ($c -eq '\') {
            $c2 = if ($i + 1 -lt $s.Length) { $s[$i + 1] } else { "" }
            if ("$c2" -ceq "u") {
                $hex = if ($i + 6 -le $s.Length) { $s.Substring($i + 2, 4) } else { $s.Substring([math]::Min($i + 2, $s.Length)) }
                if ((To-LowerAscii $hex) -ne "feff") { [void]$sb.Append("?") }
                $i += 6; continue
            }
            [void]$sb.Append($c2); $i += 2; continue
        }
        if ($c -eq '"') { break }
        [void]$sb.Append($c); $i++
    }
    return $sb.ToString()
}

function Test-Dotted([string]$v) { return $v -cmatch '^[vV]?[0-9]+(\.[0-9]+)*$' }
function Get-VersionParts([string]$v) { return ($v -replace '^[vV]', '').Split('.').Length }

function Get-AddonUpdatePlan([string[]]$localLines, [string]$catalogText, [string]$recordsFile = "") {
    $recId = New-Object System.Collections.Hashtable; $recLu = New-Object System.Collections.Hashtable
    if ($recordsFile -and (Test-Path -LiteralPath $recordsFile)) {
        foreach ($l in [System.IO.File]::ReadAllLines($recordsFile)) { $r = $l.Split('|'); if ($r.Length -ge 3) { $recId[$r[0]] = $r[1]; $recLu[$r[0]] = $r[2] } }
    }
    $localAv = New-Object System.Collections.Hashtable; $localVer = New-Object System.Collections.Hashtable
    foreach ($l in $localLines) { $p = $l.Split('|'); $localAv[$p[0]] = $p[1]; $localVer[$p[0]] = if ($p.Length -gt 2) { $p[2] } else { "" } }
    $skipped = New-Object System.Collections.Hashtable
    foreach ($s in (Get-AddonExcludes)) { $skipped[$s] = $true }

    $bestId = New-Object System.Collections.Hashtable; $bestScore = @{}; $bestMine = @{}; $bestVer = @{}; $bestTav = @{}; $bestLu = @{}
    $pathsOf = New-Object System.Collections.Hashtable
    $order = New-Object System.Collections.Generic.List[string]

    $listings = ($catalogText -replace '\},\{"id":', "}`n{`"id`":") -split "`n"
    foreach ($s in $listings) {
        if ($s -cnotmatch '"id":([0-9]+)') { continue }
        $id = $matches[1]
        if ($s -cmatch '"categoryId":157[,}]') { continue }
        $title = To-LowerAscii (Get-JStr $s "title")
        $lver = Get-JStr $s "version"
        $lu = if ($s -cmatch '"lastUpdate":([0-9]+)') { $matches[1] } else { "" }
        $a = $s.IndexOf('"addons":[', [StringComparison]::Ordinal)
        if ($a -lt 0) { continue }
        $rest = $s.Substring($a); $npaths = 0
        $tops = New-Object System.Collections.Generic.List[object]
        $all = New-Object System.Collections.Generic.List[object]
        while (($p = $rest.IndexOf('"path":"', [StringComparison]::Ordinal)) -ge 0) {
            $rest = $rest.Substring($p)
            $path = Get-JStr $rest "path"
            $nxt = if ($rest.Length -gt 8) { $rest.IndexOf('"path":"', 8, [StringComparison]::Ordinal) } else { -1 }
            $obj = if ($nxt -ge 0) { $rest.Substring(0, $nxt) } else { $rest }
            $av = Get-JStr $obj "addOnVersion"
            $npaths++
            $all.Add(@($path, $av))
            if ($path.IndexOf('/') -lt 0) { $tops.Add(@($path, $av)) }
            $rest = if ($rest.Length -gt 8) { $rest.Substring(8) } else { "" }
        }
        $pathsOf[$id] = $all
        foreach ($t in $tops) {
            $f = $t[0]
            if (!$localAv.ContainsKey($f) -or $skipped.ContainsKey($f)) { continue }
            $score = $(if ($npaths -eq 1) { 2 } else { 0 }) + $(if ($title -ceq (To-LowerAscii $f)) { 1 } else { 0 })
            $mine = if (($t[1] -ne "" -and $t[1] -ceq "$($localAv[$f])") -or ($lver -ne "" -and ($lver -replace '^[vV]', '') -ceq ("$($localVer[$f])" -replace '^[vV]', ''))) { 1 } else { 0 }
            if (!$bestId.ContainsKey($f) -or $score -gt $bestScore[$f] -or ($score -eq $bestScore[$f] -and ($mine -gt $bestMine[$f] -or ($mine -eq $bestMine[$f] -and (To-Num $lu) -gt (To-Num $bestLu[$f]))))) {
                if (!$bestId.ContainsKey($f)) { $order.Add($f) }
                $bestId[$f] = $id; $bestScore[$f] = $score; $bestMine[$f] = $mine; $bestVer[$f] = $lver; $bestTav[$f] = $t[1]; $bestLu[$f] = $lu
            }
        }
    }

    $keys = New-Object System.Collections.Generic.List[string]; $rows = New-Object System.Collections.Generic.List[string]
    foreach ($f in $order) {
        $id = $bestId[$f]; $state = ""; $lshow = $localAv[$f]; $rshow = $bestTav[$f]
        foreach ($pa in $pathsOf[$id]) {
            $path = $pa[0]; $ra = $pa[1]
            if ($path -cne $f -and !$path.StartsWith("$f/", [StringComparison]::Ordinal)) { continue }
            if (!$localAv.ContainsKey($path)) { continue }
            $la = $localAv[$path]
            if ($la -cmatch '^[0-9]+$' -and $ra -cmatch '^[0-9]+$') {
                if ([double]$ra -gt [double]$la) { $state = "UPDATE"; $lshow = $la; $rshow = $ra; break }
                if ($state -eq "") { $state = "CURRENT"; if ($path -ceq $f) { $lshow = $la; $rshow = $ra } }
            } elseif ((Test-Dotted $la) -and (Test-Dotted $ra) -and (Get-VersionParts $la) -eq (Get-VersionParts $ra)) {
                if (Test-VersionNewer $ra $la) { $state = "UPDATE"; $lshow = $la; $rshow = $ra; break }
                if ($state -eq "") { $state = "CURRENT"; if ($path -ceq $f) { $lshow = $la; $rshow = $ra } }
            }
        }
        $lv = "$($localVer[$f])"; $rv = "$($bestVer[$f])"
        if ($state -eq "" -and $recId.ContainsKey($f) -and $recId[$f] -ceq $id -and "$($bestLu[$f])" -ne "") {
            $state = if ([double]$bestLu[$f] -gt (To-Num $recLu[$f])) { "UPDATE" } else { "CURRENT" }; $lshow = $lv; $rshow = $rv
        }
        if ($state -eq "" -and $rv -ne "" -and (($lv -replace '^[vV]', '') -ceq ($rv -replace '^[vV]', '') -or ("$($localAv[$f])" -replace '^[vV]', '') -ceq ($rv -replace '^[vV]', ''))) { $state = "CURRENT"; $lshow = $rv; $rshow = $rv }
        if ($state -eq "") {
            if ((Test-Dotted $lv) -and (Test-Dotted $rv) -and (Get-VersionParts $lv) -eq (Get-VersionParts $rv)) {
                $state = if (Test-VersionNewer $rv $lv) { "UPDATE" } else { "CURRENT" }; $lshow = $lv; $rshow = $rv
            } else {
                $state = "UNKNOWN"
                $lshow = if ("$($localAv[$f])" -ne "") { $localAv[$f] } else { $lv }
                $rshow = if ("$($bestTav[$f])" -ne "") { $bestTav[$f] } else { $rv }
            }
        }
        $keys.Add($f); $rows.Add("$state|$id|$f|$lshow|$rshow|$($bestLu[$f])")
    }
    return Sort-ByKey $keys $rows
}

function Install-AddonZip($zip) {
    $work = Join-Path $TEMP_DIR_ROOT "addon_update"
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    try { Expand-Archive -LiteralPath $zip -DestinationPath $work -Force } catch { return $false }
    $backup = Join-Path (Join-Path $TARGET_DIR "Backups") "AddOns"
    if (!(Test-Path $backup)) { New-Item -ItemType Directory -Force -Path $backup | Out-Null }
    $excludes = Get-AddonExcludes
    $installed = New-Object System.Collections.Generic.List[string]
    foreach ($d in @(Get-ChildItem -LiteralPath $work -Directory)) {
        $name = $d.Name
        if ($excludes -ccontains $name) { continue }
        $target = Join-Path $ADDON_DIR $name
        if (Test-LinkedFolder $target) { continue }
        Remove-Item -LiteralPath (Join-Path $backup $name) -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $target) {
            Move-Item -LiteralPath $target -Destination (Join-Path $backup $name) -Force
            (Get-Item -LiteralPath (Join-Path $backup $name)).LastWriteTime = Get-Date
        }
        try {
            Move-Item -LiteralPath $d.FullName -Destination $target -Force -ErrorAction Stop
            $installed.Add($name)
            Log-Event "INFO" "Add-on updated: $name"
        } catch {
            if (Test-Path -LiteralPath (Join-Path $backup $name)) { Move-Item -LiteralPath (Join-Path $backup $name) -Destination $target -Force }
        }
    }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    $script:ADDON_INSTALLED = $installed.ToArray()
    return ($installed.Count -gt 0)
}

$ADDON_RECORDS = Join-Path $DB_DIR "LTTC_AddonUpdates.db"

function Save-AddonInstallRecord($id, $lu) {
    if (!$lu) { return }
    $lines = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $ADDON_RECORDS) { foreach ($l in [System.IO.File]::ReadAllLines($ADDON_RECORDS)) { if ($script:ADDON_INSTALLED -cnotcontains $l.Split('|')[0]) { $lines.Add($l) } } }
    foreach ($name in $script:ADDON_INSTALLED) { $lines.Add("$name|$id|$lu") }
    [System.IO.File]::WriteAllText($ADDON_RECORDS, ($lines -join "`n") + "`n", (New-Object System.Text.UTF8Encoding $false))
}

$ADDON_BACKUP_DAYS = 30

function Remove-OldAddonBackups {
    $dir = Join-Path (Join-Path $TARGET_DIR "Backups") "AddOns"
    if (!(Test-Path -LiteralPath $dir)) { return }
    $limit = (Get-Date).AddDays(-$ADDON_BACKUP_DAYS)
    foreach ($old in @(Get-ChildItem -LiteralPath $dir -Directory | Where-Object { $_.LastWriteTime -lt $limit })) {
        Remove-Item -LiteralPath $old.FullName -Recurse -Force -ErrorAction SilentlyContinue
        Log-Event "INFO" "Add-on backup older than $ADDON_BACKUP_DAYS days removed: $($old.Name)"
    }
}

function Invoke-AddonUpdates {
    Remove-OldAddonBackups
    if ("$global:ENABLE_ADDON_UPDATES" -ne "true" -and $global:ENABLE_ADDON_UPDATES -ne $true) { return }
    if (!(Test-Path -LiteralPath $ADDON_DIR)) { return }
    UIEcho "$ESC[1m$ESC[97m [+] Updating Your Add-Ons & Libraries $ESC[0m"
    $now = [long][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $since = $now - (To-Num $global:ADDON_LAST_CHECK)
    if ($since -lt $ADDON_UPDATE_INTERVAL -and $since -ge 0) {
        UIEcho " $ESC[90mChecked $([math]::Floor($since / 60)) minutes ago. Next check in $([math]::Floor(($ADDON_UPDATE_INTERVAL - $since) / 60)) minutes.$ESC[0m`n"
        return
    }

    $catalog = Join-Path $TEMP_DIR_ROOT "esoui_filelist.json"
    Start-Spinner "Reading the ESOUI add-on list..."
    & curl.exe -s -f -m 120 -A $ESOUI_UA -o $catalog "$ESOUI_API/v4/game/ESO/filelist.json" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Stop-Spinner 1 "Could not reach ESOUI"
        $global:notifAddons = "Check Failed"
        Remove-Item -LiteralPath $catalog -Force -ErrorAction SilentlyContinue; UIEcho ""; return
    }
    $plan = Get-AddonUpdatePlan (Get-AddonLocalList $ADDON_DIR) ([System.IO.File]::ReadAllText($catalog)) $ADDON_RECORDS
    Remove-Item -LiteralPath $catalog -Force -ErrorAction SilentlyContinue
    Stop-Spinner 0 "Compared $($plan.Count) add-ons with ESOUI"
    $global:ADDON_LAST_CHECK = $now; $global:CONFIG_CHANGED = $true

    $updates = @($plan | Where-Object { $_.StartsWith("UPDATE|") })
    if ($updates.Count -eq 0) {
        UIEcho " $ESC[90mNo changes detected. $ESC[92mAll add-ons are up-to-date.$ESC[0m`n"
        $global:notifAddons = "Up-to-date"
        return
    }
    foreach ($u in $updates) { $p = $u.Split('|'); UIEcho " $ESC[33m$($p[2])$ESC[0m $ESC[90m$($p[3])$ESC[0m -> $ESC[92m$($p[4])$ESC[0m" }
    foreach ($u in @($plan | Where-Object { $_.StartsWith("UNKNOWN|") })) { $p = $u.Split('|'); Log-Event "INFO" "Add-on update skipped for $($p[2]): its version ($($p[3])) can't be compared with ESOUI's ($($p[4]))." }

    $count = 0; $failed = 0; $seen = @{}
    foreach ($u in $updates) {
        $p = $u.Split('|'); $id = $p[1]
        if ($seen.ContainsKey($id)) { continue }
        $seen[$id] = $true
        Start-Spinner "Downloading $($p[2]) from ESOUI..."
        $TEMP_DIR_USED = $true
        $zip = Join-Path $TEMP_DIR_ROOT "addon_$id.zip"
        if ((Invoke-EsouiDownload $id $zip) -eq 0 -and (Install-AddonZip $zip)) {
            Stop-Spinner 0 "Installed: $($script:ADDON_INSTALLED -join ' ')"
            $count++
            Save-AddonInstallRecord $id $p[5]
            if ($script:ADDON_INSTALLED -ccontains "TamrielTradeCentre") { $global:TTC_NA_VERSION = 0; $global:TTC_EU_VERSION = 0 }
        } else {
            Stop-Spinner 1 "Update failed for $($p[2])"
            Log-Event "WARN" "Add-on update failed for $($p[2]): ESOUI file $($p[1]) could not be downloaded or installed."
            $failed++
        }
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
    }
    $global:notifAddons = "Updated ($count)"
    if ($failed -gt 0) { $global:notifAddons += ", Failed ($failed)" }
    UIEcho ""
}
$SELF_UPDATE_INTERVAL = 21600
$SELF_RESTART_CODE = 3

function Install-SelfUpdate {
    $zip = Join-Path $TEMP_DIR_ROOT "self_update.zip"; $work = Join-Path $TEMP_DIR_ROOT "self_update"
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    $script:SELF_NEW_VERSION = ""
    $rc = Invoke-EsouiDownload $ESOUI_SELF_ID $zip
    if ($rc -ne 0) { return $rc }
    try { Expand-Archive -LiteralPath $zip -DestinationPath $work -Force } catch { Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue; return 2 }
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
    $new = Get-ChildItem -LiteralPath $work -Recurse -File -Filter $SCRIPT_NAME | Select-Object -First 1
    if (!$new) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue; return 2 }
    $text = [System.IO.File]::ReadAllText($new.FullName)
    $newVer = if ($text -cmatch '\$APP_VERSION = "([^"]+)"') { $matches[1] } else { "" }
    if ($text -notmatch '(?m)^==POWERSHELL_START==' -or !$newVer -or !(Test-VersionNewer $newVer $APP_VERSION)) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue; return 3
    }

    $installed = Join-Path $TARGET_DIR $SCRIPT_NAME
    $running = if ($FULL_SCRIPT_PATH) { [System.IO.Path]::GetFullPath($FULL_SCRIPT_PATH) } else { "" }
    if ($running -and $running -ieq [System.IO.Path]::GetFullPath($installed)) {
        Copy-Item -LiteralPath $new.FullName -Destination "$running.new" -Force
    } else {
        Copy-Item -LiteralPath $new.FullName -Destination $installed -Force
        if ($running) { Copy-Item -LiteralPath $new.FullName -Destination "$running.new" -Force }
    }
    Log-Event "INFO" "Self-update: staged v$newVer"
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    $script:SELF_NEW_VERSION = $newVer
    return 0
}

function Invoke-SelfUpdateCheck {
    if ("$global:AUTO_SELF_UPDATE" -eq "false" -or $global:AUTO_SELF_UPDATE -eq $false) { return }
    if ($global:ENABLE_LOCAL_MODE) { return }
    if ($env:LTTC_DEV) { return }
    $now = [long][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $since = $now - (To-Num $global:SELF_LAST_CHECK)
    if ($since -lt $SELF_UPDATE_INTERVAL -and $since -ge 0) { return }
    $global:SELF_LAST_CHECK = $now; save_config

    if (!(Get-EsouiDetails $ESOUI_SELF_ID)) { Log-Event "WARN" "Self-update: could not reach ESOUI."; return }
    if (!(Test-VersionNewer $script:ESOUI_VERSION $APP_VERSION)) { return }

    Start-Spinner "Updating the updater to $($script:ESOUI_VERSION)..."
    if ((Install-SelfUpdate) -eq 0) {
        Stop-Spinner 0 "Updated to v$($script:SELF_NEW_VERSION), restarting"
        [Environment]::Exit($SELF_RESTART_CODE)
    } else {
        Stop-Spinner 1 "Update to $($script:ESOUI_VERSION) failed, keeping v$APP_VERSION"
    }
}
$TTC_DOMAIN = if ($AUTO_SRV -eq "1") {"us.tamrieltradecentre.com"} else {"eu.tamrieltradecentre.com"}
$TTC_URL = "https://$TTC_DOMAIN/download/PriceTable"
$SAVED_VAR_DIR = (Get-Item $ADDON_DIR).Parent.FullName + "\SavedVariables"
Auto-Repair-Database
$TEMP_DIR = "$TEMP_DIR_ROOT\Downloads"
$OLD_TEMP_DIR = "$env:USERPROFILE\Downloads\Windows_Tamriel_Trade_Center_Temp"
if (Test-Path -LiteralPath $OLD_TEMP_DIR) { Remove-Item -LiteralPath $OLD_TEMP_DIR -Recurse -Force -ErrorAction SilentlyContinue }
$TTC_USER_AGENT = "TamrielTradeCentreClient/1.0.0"
$HM_USER_AGENT = "HarvestMapClient/1.0.0"

$LAUNCH_METHOD = "Terminal / .bat File"
if ($global:IS_STEAM_LAUNCH) { $LAUNCH_METHOD = "Steam Launch Options" }
elseif ($global:IS_DESKTOP) { $LAUNCH_METHOD = "Desktop Shortcut" }
elseif ($global:IS_TASK) { $LAUNCH_METHOD = "Background Task" }
Log-Event "INFO" "========================================================="
Log-Event "INFO" "Script Initiated via: $LAUNCH_METHOD"

while ($true) {
    Invoke-SelfUpdateCheck
    $global:CONFIG_CHANGED = $false
    $TEMP_DIR_USED = $false
    $CURRENT_TIME = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    
    $notifTTC = "Up-to-date"
    $notifEH = "Up-to-date"
    $notifHM = "Up-to-date"
    $global:notifAddons = ""
    $FOUND_NEW_DATA = $false
    $TEMP_SCAN_FILE = "$TEMP_DIR_ROOT\WTTC_TempScan.log"
    Out-File -FilePath $TEMP_SCAN_FILE -InputObject "" -Encoding UTF8
    Out-File -FilePath $UI_STATE_FILE -InputObject "" -Encoding UTF8

    Log-Event "INFO" "Main loop iteration started. Current time: $CURRENT_TIME"

    $shuffledUAs = @($USER_AGENTS | Get-Random -Count $USER_AGENTS.Count)
    $RAND_UA = $shuffledUAs[0]

    if (!$SILENT) {
        Clear-Host
        Write-Host "$ESC[0;92m===========================================================================$ESC[0m"
        Write-Host "$ESC[1m$ESC[0;94m                         $APP_TITLE$ESC[0m"
        Write-Host "$ESC[0;97m         Cross-Platform Auto-Updater for TTC, HarvestMap, ESO-Hub & ESOUI$ESC[0m"
        Write-Host "$ESC[0;90m                            Created by @APHONIC$ESC[0m"
        Write-Host "$ESC[0;92m===========================================================================`n$ESC[0m"
        Write-Host "Target AddOn Directory: $ESC[35m$ADDON_DIR$ESC[0m`n"
    }

    if (!(Test-Path $TEMP_DIR)) { New-Item -ItemType Directory -Force -Path $TEMP_DIR | Out-Null }
    Set-Location $TEMP_DIR

    $ADDON_SETTINGS_FILE = (Get-Item $ADDON_DIR).Parent.FullName + "\AddOnSettings.txt"
    $addonSettingsText = if (Test-Path $ADDON_SETTINGS_FILE) { Get-Content $ADDON_SETTINGS_FILE -Raw } else { "" }

    function Check-Addon-Enabled($addonName) {
        if (!(Test-Path "$ADDON_DIR\$addonName")) { return $false }
        if ($addonSettingsText) { return ($addonSettingsText -match "\b$([regex]::Escape($addonName))\b") }
        return $true
    }

    function Ensure-Missing-Addon($a_name, $a_id, $skip_var) {
        $skipVal = Get-Variable -Name $skip_var -ValueOnly -ErrorAction SilentlyContinue
        if ($skipVal -eq "True" -or $skipVal -eq $true) { return $false }
        
        $addonPath = Join-Path $global:ADDON_DIR $a_name
        if (!(Test-Path $addonPath)) {
            Write-Host " `n$ESC[33m[?] $a_name is missing. Do you want to download it? (y/N)$ESC[0m"
            $ans = Read-Host "Choice"
            if ([string]::IsNullOrWhiteSpace($ans)) { $ans = "n" }
            
            if ($ans -match '^[Yy]$') {
                Start-Spinner "Downloading $a_name from ESOUI..."
                Log-Event "INFO" "Attempting to download missing addon: $a_name"
                
                try {
                    $zipPath = "$TEMP_DIR_ROOT\${a_name}.zip"
                    if ((Invoke-EsouiDownload $a_id $zipPath) -eq 0) {
                        Expand-Archive -Path $zipPath -DestinationPath $global:ADDON_DIR -Force
                        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
                        
                        if ($a_name -eq "LibEsoHubPrices") {
                            $ehApi = (& curl.exe -s -X POST -H "User-Agent: ESOHubClient/1.0.9" -d "user_token=&client_system=$SYS_ID&client_version=1.0.9&lang=en" "https://data.eso-hub.com/v1/api/get-addon-versions" 2>$null) -join ""
                            $ehBlock = @($ehApi.Replace('{"folder_name"', "`n{`"folder_name`"") -split "`n" | Where-Object { $_ -match '"folder_name":"LibEsoHubPrices"' })
                            if ($ehBlock.Count -gt 0 -and $ehBlock[0] -match '"version":\{[^}]*"string":"([^"]+)"') {
                                $global:EH_LOC_7 = $matches[1]
                                $global:CONFIG_CHANGED = $true
                            }
                        }

                        if ($a_name -eq "TamrielTradeCentre") {
                            Remove-Item "$TEMP_DIR_ROOT\ttc_last_dl.txt" -Force -ErrorAction SilentlyContinue
                            $global:TTC_NA_VERSION = 0
                            $global:TTC_EU_VERSION = 0
                            $global:CONFIG_CHANGED = $true
                        }
                        
                        Stop-Spinner 0 "$a_name installed"
                        Log-Event "INFO" "Addon $a_name automatically downloaded and installed."
                        
                        $settings_file = (Get-Item $global:ADDON_DIR).Parent.FullName + "\AddOnSettings.txt"
                        if (Test-Path $settings_file) {
                            $sText = [System.IO.File]::ReadAllText($settings_file)
                            if ($a_name -eq "HarvestMap" -or $a_name -eq "HarvestMapData") {
                                $sText = [regex]::Replace($sText, '(?im)^HarvestMap 0', 'HarvestMap 1')
                                $sText = [regex]::Replace($sText, '(?im)^HarvestMapData 0', 'HarvestMapData 1')
                                if ($sText -notmatch '(?im)^HarvestMap ') { $sText += "`nHarvestMap 1" }
                                if ($sText -notmatch '(?im)^HarvestMapData ') { $sText += "`nHarvestMapData 1" }
                            } else {
                                $sText = [regex]::Replace($sText, "(?im)^$a_name 0", "$a_name 1")
                                if ($sText -notmatch "(?im)^$a_name ") { $sText += "`n$a_name 1" }
                            }
                            $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
                            [System.IO.File]::WriteAllText($settings_file, $sText, $Utf8NoBomEncoding)
                        }
                        return $true
                    } else {
                        Stop-Spinner 1 "$a_name download failed"
                        Log-Event "ERROR" "Download failed for missing addon: $a_name"
                        return $false
                    }
                } catch {
                    Stop-Spinner 1 "$a_name download failed"
                    return $false
                }
            } else {
                UIEcho " $ESC[90mUser Declined download of $a_name. Will not ask again.$ESC[0m"
                Log-Event "WARN" "User declined download for $a_name. Setting skip flag."
                Set-Variable -Name $skip_var -Value "True" -Scope Global
                save_config
                return $false
            }
        }
        return $true
    }

    Ensure-Missing-Addon "TamrielTradeCentre" "1245" "SKIP_DL_TTC" | Out-Null
    Ensure-Missing-Addon "HarvestMap" "57" "SKIP_DL_HM" | Out-Null
    Ensure-Missing-Addon "HarvestMapData" "3034" "SKIP_DL_HM" | Out-Null
    Ensure-Missing-Addon "LibEsoHubPrices" "4095" "SKIP_DL_EH" | Out-Null

    if ($global:SKIP_DL_EH -ne "True" -and $global:SKIP_DL_EH -ne $true) {
        if (!(Test-Path "$ADDON_DIR\EsoTradingHub") -or !(Test-Path "$ADDON_DIR\EsoHubScanner")) {
            Write-Host " `n$ESC[33m[?] ESO-Hub Addons are missing. Do you want to download them? (y/N)$ESC[0m"
            $ans = Read-Host "Choice"
            if ([string]::IsNullOrWhiteSpace($ans)) { $ans = "n" }
            if ($ans -match '^[Yy]$') {
                Start-Spinner "Downloading ESO-Hub Addons..."
                $api_resp = (& curl.exe -s -X POST -H "User-Agent: ESOHubClient/1.0.9" -d "user_token=&client_system=$SYS_ID&client_version=1.0.9&lang=en" "https://data.eso-hub.com/v1/api/get-addon-versions") -join ""
                
                $api_resp = $api_resp.Replace('{"folder_name"', "`n{`"folder_name`"")
                $lines = $api_resp -split "`n"
                foreach ($line in $lines) {
                    if ($line -match '"folder_name"\s*:\s*"([^"]+)"') {
                        $fname = $matches[1]
                        if ($fname -eq "LibEsoHubPrices") { continue } 
                        
                        $dl_url = if ($line -match '"file"\s*:\s*"([^"]+)"') { $matches[1].Replace('\/','/') } else { "" }
                        $srv_ver = if ($line -match '"version"\s*:\s*\{[^}]*"string"\s*:\s*"([^"]+)"') { $matches[1] } elseif ($line -match '"version"\s*:\s*"([^"]+)"') { $matches[1] } else { "" }
                        $id_num = if ($dl_url -match '(\d+)$') { $matches[1] } else { "0" }
                        
                        if ($fname -and $dl_url) {
                            Stop-Spinner 0 "Fetching $fname"
                            Start-Spinner "Downloading $fname..."
                            & curl.exe -s -f -m 30 -L -A "ESOHubClient/1.0.9" -o "$TEMP_DIR_ROOT\${fname}.zip" $dl_url
                            if ($LASTEXITCODE -eq 0) {
                                Expand-Archive -Path "$TEMP_DIR_ROOT\${fname}.zip" -DestinationPath $global:ADDON_DIR -Force
                                Remove-Item "$TEMP_DIR_ROOT\${fname}.zip" -Force
                                
                                Stop-Spinner 0 "$fname installed"
                                $var_name = "EH_LOC_$id_num"
                                Set-Variable -Name $var_name -Value $srv_ver -Scope Global
                                $global:CONFIG_CHANGED = $true
                                
                                $settings_file = (Get-Item $global:ADDON_DIR).Parent.FullName + "\AddOnSettings.txt"
                                if (Test-Path $settings_file) {
                                    $sText = [System.IO.File]::ReadAllText($settings_file)
                                    $sText = [regex]::Replace($sText, "(?im)^$fname 0", "$fname 1")
                                    if ($sText -notmatch "(?im)^$fname ") { $sText += "`n$fname 1" }
                                    $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
                                    [System.IO.File]::WriteAllText($settings_file, $sText, $Utf8NoBomEncoding)
                                }
                            } else {
                                Stop-Spinner 1 "Download failed for $fname"
                            }
                        }
                    }
                }
            } else {
                UIEcho " $ESC[90mUser Declined ESO-Hub downloads.$ESC[0m"
                $global:SKIP_DL_EH = "True"
                save_config
            }
        }
    }

    $HAS_TTC = Check-Addon-Enabled "TamrielTradeCentre"
    $HAS_HM = Check-Addon-Enabled "HarvestMap"

    if (!$global:ENABLE_LOCAL_MODE) {
        UIEcho "$ESC[1m$ESC[97m [0/4] Synchronizing Local Database $ESC[0m"
        UIEcho " $ESC[33mChecking ESOUI for database updates...$ESC[0m"
        
        $SRV_DB_VER = "0.0.0"
        if (Get-EsouiDetails $ESOUI_DB_ID) { $SRV_DB_VER = $script:ESOUI_VERSION }

        $LOC_DB_VER = "0.0.0"
        if (Test-Path $DB_FILE) {
            $firstLine = (Get-Content $DB_FILE -TotalCount 1)
            if ($firstLine -match '([0-9]+(\.[0-9]+)+)') { $LOC_DB_VER = $matches[1] }
        }

        $V_COL = if ($SRV_DB_VER -eq $LOC_DB_VER) {"$ESC[92m"} else {"$ESC[31m"}
        UIEcho "`t$ESC[90mServer_DB_Version= ${V_COL}$SRV_DB_VER$ESC[0m"
        UIEcho "`t$ESC[90mLocal_DB_Version=  ${V_COL}$LOC_DB_VER$ESC[0m"

        $histFirst = if (Test-Path -LiteralPath $HIST_FILE) { "$(Get-Content -LiteralPath $HIST_FILE -TotalCount 1)" } else { "" }
        $histSeeded = $histFirst -like "#HISTORY VERSION:*"
        if ($SRV_DB_VER -ne "0.0.0" -and ((Test-VersionNewer $SRV_DB_VER $LOC_DB_VER) -or !$histSeeded)) {
            UIEcho " $ESC[36mDownloading latest database template...$ESC[0m"
            Log-Event "INFO" "Downloading database update (v$SRV_DB_VER)"
            
            $dbZipPath = Join-Path $TEMP_DIR_ROOT "db.zip"
            try {
                $TEMP_DIR_USED = $true
                if ((Invoke-EsouiDownload $ESOUI_DB_ID $dbZipPath) -eq 0) {
                    $dbUpdateDir = Join-Path $TEMP_DIR_ROOT "DB_Update"
                    Expand-Archive -Path $dbZipPath -DestinationPath $dbUpdateDir -Force
                    
                    $NEW_DB = Get-ChildItem -Path $dbUpdateDir -Filter "LTTC_Database.db" -Recurse | Select-Object -First 1
                    $NEW_HIST = Get-ChildItem -Path $dbUpdateDir -Filter "LTTC_History.db" -Recurse | Select-Object -First 1
                    
                    if ($NEW_DB) {
                        if (!(Test-Path $DB_FILE) -or (Get-Item $DB_FILE).length -eq 0) {
                            $fresh = @("#DATABASE VERSION: $SRV_DB_VER") + @([System.IO.File]::ReadAllLines($NEW_DB.FullName) | Where-Object { !$_.StartsWith("#DATABASE VERSION:") })
                            [System.IO.File]::WriteAllText($DB_FILE, ($fresh -join "`n") + "`n", (New-Object System.Text.UTF8Encoding $false))
                            UIEcho " $ESC[92m[+] Database downloaded and installed!$ESC[0m`n"
                        } else {
                            UIEcho " $ESC[33mMerging new database entries (Preventing Duplicates)...$ESC[0m"
                            $seen = New-Object System.Collections.Hashtable
                            $mergedLines = New-Object System.Collections.ArrayList
                            [void]$mergedLines.Add("#DATABASE VERSION: $SRV_DB_VER")
                            
                            foreach ($file in @($DB_FILE, $NEW_DB.FullName)) {
                                foreach ($line in [System.IO.File]::ReadLines($file)) {
                                    if ($line.StartsWith("#DATABASE VERSION:")) { continue }
                                    $p = $line.Split('|')
                                    $key = if ($p[0] -eq "GUILD") {"GUILD_"+$p[1]} elseif ($p[0] -eq "KIOSK") {"KIOSK_"+$p[1]} elseif ($p[0] -match '^[0-9]+$') {"ITEM_"+$p[0]} else {$line}
                                    if (!$seen.ContainsKey($key)) {
                                        $seen[$key] = $true
                                        [void]$mergedLines.Add($line)
                                    }
                                }
                            }
                            [System.IO.File]::WriteAllText($DB_FILE, ($mergedLines.ToArray() -join "`n") + "`n", (New-Object System.Text.UTF8Encoding $false))
                            UIEcho " $ESC[92m[+] Database successfully merged to v$SRV_DB_VER!$ESC[0m`n"
                        }
                        if ($NEW_HIST) {
                            UIEcho " $ESC[33mMerging shared trade history...$ESC[0m"
                            Merge-TemplateHistory $HIST_FILE $NEW_HIST.FullName $SRV_DB_VER
                            UIEcho " $ESC[92m[+] Shared trade history merged.$ESC[0m`n"
                        } else {
                            $cur = if (Test-Path -LiteralPath $HIST_FILE) { @([System.IO.File]::ReadAllLines($HIST_FILE) | Where-Object { !$_.StartsWith("#HISTORY VERSION:") }) } else { @() }
                            [System.IO.File]::WriteAllText($HIST_FILE, ((@("#HISTORY VERSION: $SRV_DB_VER") + $cur) -join "`n") + "`n", (New-Object System.Text.UTF8Encoding $false))
                        }
                    }
                    Remove-Item -Path $dbUpdateDir -Recurse -Force
                    Remove-Item -LiteralPath $dbZipPath -Force -ErrorAction SilentlyContinue
                } else {
                    UIEcho " $ESC[31m[-] Database download failed (Timeout or Blocked).$ESC[0m`n"
                }
            } catch { UIEcho " $ESC[31m[-] Database download process failed.$ESC[0m`n" }
        } else {
            UIEcho " $ESC[90mNo changes detected. $ESC[92mLocal database is up-to-date. $ESC[35mSkipping download.$ESC[0m`n"
        }
    }

    if (!$global:ENABLE_LOCAL_MODE) { Invoke-AddonUpdates }
    if (!$HAS_TTC) {
        UIEcho "$ESC[1m$ESC[97m [1/4] & [2/4] Updating TTC Data (SKIPPED)$ESC[0m"
        UIEcho " $ESC[31m[-] TamrielTradeCentre not enabled.$ESC[0m`n"
        $notifTTC = "Skipped"
    } else {
        UIEcho "$ESC[1m$ESC[97m [1/4] Uploading your Local TTC Data $ESC[0m"
        $ttcSv = "$SAVED_VAR_DIR\TamrielTradeCentre.lua"
        $ttcSnap = "$SNAP_DIR\lttc_ttc_snapshot.lua"

        if (Test-Path $ttcSv) {
            if (!(Test-FileNewer $ttcSv $ttcSnap)) {
                UIEcho " $ESC[90mNo TTC local changes detected. $ESC[35mSkipping upload.$ESC[0m`n"
            } else {
                $ttcExtracted = $false; $ttcRawCount = 0
                if ($global:ENABLE_DISPLAY -and !$global:SILENT) {
                    Start-Spinner "Parsing TamrielTradeCentre.lua..."
                    [System.IO.File]::AppendAllText($TEMP_SCAN_FILE, "`n$ESC[0;35m--- TTC Extracted Data ---$ESC[0m`n", [System.Text.Encoding]::UTF8)
                    $res = Invoke-TtcExtraction $ttcSv $global:TTC_LAST_SALE $CURRENT_TIME
                    Stop-Spinner 0 "Extraction complete"
                    $ttcExtracted = $true; $ttcRawCount = $res.Lines.Count

                    if ($ttcRawCount -gt 0) {
                        $FOUND_NEW_DATA = $true
                        foreach ($l in $res.Lines) {
                            $cut = $l.IndexOf('|'); $ts = $l.Substring(0, $cut); $rest = $l.Substring($cut + 1)
                            $rawLine = if ($ts -eq "0") { " [$ESC[90mListing$ESC[0m]$rest" } else { " [TS:$ts]$rest" }
                            UIEcho $rawLine
                            [System.IO.File]::AppendAllText($TEMP_SCAN_FILE, "$rawLine`n", [System.Text.Encoding]::UTF8)
                        }
                    } else {
                        UIEcho " $ESC[90mNo new TTC items found. Upload skipped.$ESC[0m"
                    }

                    Merge-History $res.History
                    Apply-DB-Updates $res.DbUpdates
                    if ("$($res.MaxTime)" -ne "$global:TTC_LAST_SALE") { $global:TTC_LAST_SALE = $res.MaxTime; $global:CONFIG_CHANGED = $true }
                } else {
                    UIEcho " $ESC[90mExtraction disabled by user. Proceeding instantly...$ESC[0m"
                }

                if ($global:ENABLE_LOCAL_MODE) {
                    UIEcho "`n $ESC[90m[Local Mode] Skipping TTC Upload.$ESC[0m`n"
                    $notifTTC = "Extracted (No Upload)"
                    Copy-Item -LiteralPath $ttcSv -Destination $ttcSnap -Force -ErrorAction SilentlyContinue
                } elseif ($ttcExtracted -and $ttcRawCount -eq 0) {
                    $notifTTC = "No New Data"
                    Copy-Item -LiteralPath $ttcSv -Destination $ttcSnap -Force -ErrorAction SilentlyContinue
                } else {
                    $uploadDomains = if ($AUTO_SRV -eq "3") { @("us.tamrieltradecentre.com", "eu.tamrieltradecentre.com") } else { @($TTC_DOMAIN) }
                    $uploadOk = $true
                    foreach ($upDomain in $uploadDomains) {
                        $upRegion = if ($upDomain.StartsWith("eu.")) { "EU" } else { "NA" }
                        Start-Spinner "Uploading to https://$upDomain..."
                        if (Invoke-TTCUpload $upDomain $upRegion $ttcSv) {
                            if ($global:TTC_UPLOAD_COUNT -gt 0) { Stop-Spinner 0 "Upload finished ($upDomain, $($global:TTC_UPLOAD_COUNT) listings)" }
                            else { Stop-Spinner 0 "Nothing new for $upDomain ($(Get-TTCNothingNewReason))" }
                        } else { $uploadOk = $false; Stop-Spinner 1 "Upload failed ($upDomain)" }
                    }
                    if ($uploadOk) {
                        $notifTTC = "Data Uploaded"
                        Copy-Item -LiteralPath $ttcSv -Destination $ttcSnap -Force -ErrorAction SilentlyContinue
                    } else {
                        $notifTTC = "Upload Failed"
                    }
                }
            }
        } else {
            UIEcho " $ESC[33m[-] No TamrielTradeCentre.lua found. $ESC[35mSkipping.$ESC[0m`n"
        }

        UIEcho "$ESC[1m$ESC[97m [2/4] Updating your Local TTC Data $ESC[0m`n $ESC[33mChecking TTC APIs...$ESC[0m"
        $global:TTC_LAST_CHECK = $CURRENT_TIME; $global:CONFIG_CHANGED = $true

        $srv_list = @()
        if ($AUTO_SRV -eq "1" -or $AUTO_SRV -eq "3") { $srv_list += "NA" }
        if ($AUTO_SRV -eq "2" -or $AUTO_SRV -eq "3") { $srv_list += "EU" }

        $needs_dl = $false; $dl_na = $false; $dl_eu = $false
        $s_ver_na = "0"; $s_ver_eu = "0"

        foreach ($srv in $srv_list) {
            $api_domain = if ($srv -eq "EU") { "eu.tamrieltradecentre.com" } else { "us.tamrieltradecentre.com" }
            $apiResp = (& curl.exe -s -m 10 -A "$TTC_USER_AGENT" "https://$api_domain/api/GetTradeClientVersion" 2>$null) -join ""
            $s_ver = if ($apiResp -match '"PriceTableVersion"\s*:\s*"?([0-9]+)') { $matches[1] } else { "0" }
            if ($s_ver -eq "0") { UIEcho " $ESC[31m[-] Could not fetch TTC version for $srv.$ESC[0m" }

            if ($srv -eq "NA") { $s_ver_na = $s_ver; $loc_ver = "$global:TTC_NA_VERSION" } else { $s_ver_eu = $s_ver; $loc_ver = "$global:TTC_EU_VERSION" }
            if (!$loc_ver) { $loc_ver = "0" }

            $pt_file = "$ADDON_DIR\TamrielTradeCentre\PriceTable${srv}.lua"
            if ($loc_ver -eq "0" -and (Test-Path $pt_file)) {
                foreach ($l in (Get-Content $pt_file -TotalCount 5)) {
                    if ($l -match '(?i)^--Version[ \t]*=[ \t]*([0-9]+)') { $loc_ver = $matches[1]; break }
                }
            }

            $loc_disp = if ($loc_ver -eq "0") { "None" } else { $loc_ver }
            $s_ver_disp = if ($s_ver -eq "0") { "Error" } else { $s_ver }
            $v_col = if ($s_ver -eq $loc_ver) { "$ESC[92m" } else { "$ESC[31m" }
            UIEcho " `t$ESC[90mServer Version ($srv): ${v_col}$s_ver_disp$ESC[0m"
            UIEcho " `t$ESC[90mLocal Version ($srv):  ${v_col}$loc_disp$ESC[0m"

            if ($s_ver -ne "0" -and (To-Num $s_ver) -gt (To-Num $loc_ver)) {
                $needs_dl = $true
                if ($srv -eq "NA") { $dl_na = $true } else { $dl_eu = $true }
            }
        }

        if ($needs_dl) {
            UIEcho " $ESC[92mNew TTC Price Table available $ESC[0m"
            $ttc_diff = $CURRENT_TIME - (To-Num $global:TTC_LAST_DOWNLOAD)

            if ($global:ENABLE_LOCAL_MODE) {
                UIEcho " $ESC[90m[Local Mode] Download Skipped.$ESC[0m`n"
            } elseif ($ttc_diff -lt 3600 -and $ttc_diff -ge 0) {
                $wait_m = [math]::Floor((3600 - $ttc_diff) / 60)
                $notifTTC = if ($notifTTC -eq "Data Uploaded") { "Uploaded (DL Cooldown)" } else { "Download Cooldown" }
                UIEcho " $ESC[33mdownload is on cooldown ($wait_m min). $ESC[35mSkipping.$ESC[0m`n"
            } else {
                $success_all = $true; $TEMP_DIR_USED = $true; $rate_limit = $false

                foreach ($srv in $srv_list) {
                    if ($srv -eq "NA" -and !$dl_na) { continue }
                    if ($srv -eq "EU" -and !$dl_eu) { continue }
                    $dl_url = if ($srv -eq "NA") { "https://us.tamrieltradecentre.com/download/PriceTable" } else { "https://eu.tamrieltradecentre.com/download/PriceTable" }
                    $zipPath = "$TEMP_DIR\TTC-data-${srv}.zip"

                    Start-Spinner "Downloading TTC Price Table ($srv)..."
                    & curl.exe -s -f -A "$TTC_USER_AGENT" -L -o $zipPath "$dl_url" 2>$null
                    $success = $false
                    if ($LASTEXITCODE -eq 22) {
                        $rate_limit = $true
                        Stop-Spinner 1 "TTC Rate Limit reached ($srv)"
                        $success_all = $false; break
                    } elseif ($LASTEXITCODE -eq 0 -and (Test-ZipFile $zipPath)) {
                        $success = $true
                    }

                    if (!$success) {
                        Stop-Spinner 1 "Primary UA blocked ($srv)"
                        Start-Spinner "Retrying with fallback User-Agent ($srv)..."
                        foreach ($ua in $shuffledUAs) {
                            & curl.exe -s -f -H "User-Agent: $ua" -L -o $zipPath "$dl_url" 2>$null
                            if ($LASTEXITCODE -eq 22) { $rate_limit = $true; Stop-Spinner 1 "TTC Rate Limit reached ($srv)"; break }
                            if ($LASTEXITCODE -eq 0 -and (Test-ZipFile $zipPath)) { $success = $true; break }
                        }
                        if ($rate_limit) { $success_all = $false; break }
                    }

                    if ($success) {
                        Expand-Archive -Path $zipPath -DestinationPath "$TEMP_DIR\TTC_Extracted_${srv}" -Force
                        Stop-Spinner 0 "TTC Updated ($srv)"
                    } else {
                        Stop-Spinner 1 "TTC download failed ($srv)"
                        $success_all = $false
                    }
                }

                $has_na = Test-Path "$TEMP_DIR\TTC_Extracted_NA"
                $has_eu = Test-Path "$TEMP_DIR\TTC_Extracted_EU"

                if ($success_all -or $has_na -or $has_eu) {
                    $ttc_dir = "$ADDON_DIR\TamrielTradeCentre"
                    if (!(Test-Path $ttc_dir)) { New-Item -ItemType Directory -Force -Path $ttc_dir | Out-Null }
                    if ($has_na) { Copy-Item -Path "$TEMP_DIR\TTC_Extracted_NA\*" -Destination "$ttc_dir\" -Recurse -Force; $global:TTC_NA_VERSION = $s_ver_na }
                    if ($has_eu) { Copy-Item -Path "$TEMP_DIR\TTC_Extracted_EU\*" -Destination "$ttc_dir\" -Recurse -Force; $global:TTC_EU_VERSION = $s_ver_eu }
                    $global:TTC_LAST_DOWNLOAD = $CURRENT_TIME; $global:CONFIG_CHANGED = $true
                    $notifTTC = if ($notifTTC -eq "Data Uploaded") { "Uploaded & Updated" } else { "Updated" }
                    UIEcho ""
                } elseif (!$rate_limit) {
                    $notifTTC = if ($notifTTC -eq "Data Uploaded") { "Uploaded, DL Failed" } else { "Download Error" }
                }
            }
        } else {
            if ($s_ver_na -ne "0" -and (To-Num $s_ver_na) -ge (To-Num $global:TTC_NA_VERSION)) { $global:TTC_NA_VERSION = $s_ver_na; $global:CONFIG_CHANGED = $true }
            if ($s_ver_eu -ne "0" -and (To-Num $s_ver_eu) -ge (To-Num $global:TTC_EU_VERSION)) { $global:TTC_EU_VERSION = $s_ver_eu; $global:CONFIG_CHANGED = $true }
            UIEcho " $ESC[90mNo changes detected. $ESC[92mLocal PriceTable is up-to-date.$ESC[0m`n"
        }
    }
    UIEcho "$ESC[1m$ESC[97m [3/4] Updating ESO-Hub Prices & Uploading Scans $ESC[0m"
    UIEcho " $ESC[36mFetching latest ESO-Hub version data...$ESC[0m"

    $global:EH_LAST_CHECK = $CURRENT_TIME; $global:CONFIG_CHANGED = $true
    $ehUploadCount = 0; $ehUpdateCount = 0

    $apiResp = (& curl.exe -s -X POST -H "User-Agent: ESOHubClient/1.0.9" -d "user_token=&client_system=$SYS_ID&client_version=1.0.9&lang=en" "https://data.eso-hub.com/v1/api/get-addon-versions" 2>$null) -join ""
    $addonBlocks = @($apiResp.Replace('{"folder_name"', "`n{`"folder_name`"") -split "`n" | Where-Object { $_ -match '"folder_name"' })

    if ($addonBlocks.Count -eq 0) {
        $notifEH = "Download Error"
        UIEcho " $ESC[31m[-] Could not fetch ESO-Hub data.$ESC[0m`n"
    } else {
        $EH_TIME_DIFF = $CURRENT_TIME - (To-Num $global:EH_LAST_DOWNLOAD)
        $EH_DOWNLOAD_OCCURRED = $false

        foreach ($line in $addonBlocks) {
            $FNAME = if ($line -match '"folder_name":"([^"]+)"') { $matches[1] } else { "" }
            $SV_NAME = if ($line -match '"sv_file_name":"([^"]+)"') { $matches[1] } else { "" }
            $UP_EP = if ($line -match '"endpoint":"([^"]+)"') { $matches[1].Replace('\', '') } else { "" }
            $DL_URL = if ($line -match '"file":"([^"]+)"') { $matches[1].Replace('\', '') } else { "" }
            if (!$FNAME) { continue }

            if (!(Check-Addon-Enabled $FNAME)) {
                UIEcho " $ESC[31m[-] $FNAME missing. $ESC[35mSkipping.$ESC[0m"
                continue
            }

            $ID_NUM = if ($DL_URL -match '([0-9]+)$') { $matches[1] } else { "0" }
            $SRV_VER = if ($line -match '"version":\{[^}]*"string":"([^"]+)"') { $matches[1] } else { "" }
            $PREFIX = switch ($FNAME) { "EsoTradingHub" { "ETH5" } "LibEsoHubPrices" { "LEHP7" } "EsoHubScanner" { "EHS" } default { $FNAME } }

            $VAR_LOC_NAME = "EH_LOC_$ID_NUM"
            $LOC_VER = "$(Get-Variable -Name $VAR_LOC_NAME -Scope Global -ValueOnly -ErrorAction SilentlyContinue)"
            if (!$LOC_VER) { $LOC_VER = "0" }
            if ($LOC_VER -eq "0" -and (Test-Path "$ADDON_DIR\$FNAME")) {
                $LOC_VER = $SRV_VER
                Set-Variable -Name $VAR_LOC_NAME -Value $SRV_VER -Scope Global
                $global:CONFIG_CHANGED = $true
            }

            $V_COL = if ($SRV_VER -eq $LOC_VER) { "$ESC[92m" } else { "$ESC[31m" }
            UIEcho " $ESC[33mChecking server for $FNAME.zip...$ESC[0m"
            UIEcho "`t$ESC[90m${PREFIX}_Server_Version= ${V_COL}$SRV_VER$ESC[0m"
            UIEcho "`t$ESC[90m${PREFIX}_Local_Version= ${V_COL}$LOC_VER$ESC[0m"

            $svPath = "$SAVED_VAR_DIR\$SV_NAME"
            if ($SV_NAME -and $UP_EP -and (Test-Path -LiteralPath $svPath)) {
                $UP_SNAP = "$SNAP_DIR\lttc_eh_$($SV_NAME.ToLower().Replace('.lua', ''))_snapshot.lua"

                if (!(Test-FileNewer $svPath $UP_SNAP)) {
                    UIEcho " $ESC[90mNo changes detected in $SV_NAME. $ESC[35mSkipping upload.$ESC[0m"
                } else {
                    $ehExtracted = $false; $ehRawCount = 0
                    if ($SV_NAME -eq "EsoTradingHub.lua" -and $global:ENABLE_DISPLAY -and !$global:SILENT) {
                        Start-Spinner "Parsing $SV_NAME..."
                        [System.IO.File]::AppendAllText($TEMP_SCAN_FILE, "`n$ESC[0;35m--- ESO-Hub Extracted Data ---$ESC[0m`n", [System.Text.Encoding]::UTF8)
                        $res = Invoke-EsoHubExtraction $svPath $global:EH_LAST_SALE $CURRENT_TIME
                        Stop-Spinner 0 "Extraction complete"
                        $ehExtracted = $true; $ehRawCount = $res.Lines.Count

                        if ($ehRawCount -gt 0) {
                            $FOUND_NEW_DATA = $true
                            foreach ($l in $res.Lines) {
                                $cut = $l.IndexOf('|'); $ts = $l.Substring(0, $cut); $rest = $l.Substring($cut + 1)
                                $rawLine = if ($ts -eq "0") { " [$ESC[90mListing$ESC[0m]$rest" } else { " [TS:$ts]$rest" }
                                UIEcho $rawLine
                                [System.IO.File]::AppendAllText($TEMP_SCAN_FILE, "$rawLine`n", [System.Text.Encoding]::UTF8)
                            }
                        } else {
                            UIEcho " $ESC[90mNo new ESO-Hub items found. Upload skipped.$ESC[0m"
                        }

                        Merge-History $res.History
                        Apply-DB-Updates $res.DbUpdates
                        if ("$($res.MaxTime)" -ne "$global:EH_LAST_SALE") { $global:EH_LAST_SALE = $res.MaxTime; $global:CONFIG_CHANGED = $true }
                    } elseif ($SV_NAME -eq "EsoTradingHub.lua" -and !$global:ENABLE_DISPLAY -and !$global:SILENT) {
                        UIEcho " $ESC[90mExtraction disabled by user. Proceeding instantly to upload...$ESC[0m"
                    }

                    if ($global:ENABLE_LOCAL_MODE) {
                        UIEcho " $ESC[90m[Local Mode] Skipping ESO-Hub Upload ($SV_NAME).$ESC[0m"
                        Copy-Item -LiteralPath $svPath -Destination $UP_SNAP -Force -ErrorAction SilentlyContinue
                    } elseif ($SV_NAME -eq "EsoTradingHub.lua" -and $ehExtracted -and $ehRawCount -eq 0) {
                        Copy-Item -LiteralPath $svPath -Destination $UP_SNAP -Force -ErrorAction SilentlyContinue
                    } elseif ($SV_NAME -eq "EsoHubScanner.lua" -and !(Select-String -LiteralPath $svPath -Pattern '\|H[0-9a-fA-F]*:item:[0-9]+' -Quiet)) {
                        Copy-Item -LiteralPath $svPath -Destination $UP_SNAP -Force -ErrorAction SilentlyContinue
                    } else {
                        Start-Spinner "Uploading local scan data ($SV_NAME)..."
                        & curl.exe -s -f -m 60 -A "ESOHubClient/1.0.9" -F "file=@$svPath" "https://data.eso-hub.com$UP_EP`?user_token=$global:EH_USER_TOKEN" 2>$null | Out-Null
                        if ($LASTEXITCODE -eq 0) {
                            Copy-Item -LiteralPath $svPath -Destination $UP_SNAP -Force -ErrorAction SilentlyContinue
                            $ehUploadCount++
                            Stop-Spinner 0 "Upload finished ($SV_NAME)"
                        } else {
                            Stop-Spinner 1 "Upload failed ($SV_NAME)"
                        }
                    }
                }
            }

            if ($DL_URL) {
                if ($SRV_VER -eq $LOC_VER) {
                    UIEcho " $ESC[90mNo changes detected. $ESC[92m($FNAME.zip) is up-to-date. $ESC[35mSkipping download.$ESC[0m"
                } elseif ($global:ENABLE_LOCAL_MODE) {
                    UIEcho " $ESC[90m[Local Mode] Skipping Download for $FNAME.zip.$ESC[0m"
                } elseif ($EH_TIME_DIFF -lt 3600 -and $EH_TIME_DIFF -ge 0) {
                    $WAIT_MINS = [math]::Floor((3600 - $EH_TIME_DIFF) / 60)
                    UIEcho " $ESC[33mNew $FNAME.zip available, but download is on cooldown for $WAIT_MINS more minutes. $ESC[35mSkipping.$ESC[0m"
                } else {
                    Start-Spinner "Downloading $FNAME.zip..."
                    $TEMP_DIR_USED = $true
                    $zipPath = "$TEMP_DIR_ROOT\EH_$ID_NUM.zip"
                    & curl.exe -s -f -L -m 30 -A "ESOHubClient/1.0.9" -o $zipPath "$DL_URL" 2>$null
                    if ($LASTEXITCODE -ne 0) { & curl.exe -s -f -L -m 30 -A "$RAND_UA" -o $zipPath "$DL_URL" 2>$null }

                    if (Test-ZipFile $zipPath) {
                        Expand-Archive -Path $zipPath -DestinationPath "$TEMP_DIR_ROOT\ESOHub_Extracted" -Force
                        Copy-Item -Path "$TEMP_DIR_ROOT\ESOHub_Extracted\*" -Destination "$ADDON_DIR\" -Recurse -Force
                        Set-Variable -Name $VAR_LOC_NAME -Value $SRV_VER -Scope Global
                        $global:CONFIG_CHANGED = $true; $EH_DOWNLOAD_OCCURRED = $true; $ehUpdateCount++
                        Stop-Spinner 0 "$FNAME.zip updated successfully"
                    } else {
                        Stop-Spinner 1 "Error: $FNAME.zip download corrupted"
                    }
                }
            }
        }

        if ($EH_DOWNLOAD_OCCURRED) { $global:EH_LAST_DOWNLOAD = $CURRENT_TIME }
        if ($ehUpdateCount -gt 0 -or $ehUploadCount -gt 0) { $notifEH = "Updated ($ehUpdateCount), Uploaded ($ehUploadCount)" }
        UIEcho ""
    }
    if (!$HAS_HM -or $global:ENABLE_LOCAL_MODE) {
        $notifHM = "Skipped"
        UIEcho "$ESC[1m$ESC[97m [4/4] Updating HarvestMap Data (SKIPPED) $ESC[0m"
        if ($global:ENABLE_LOCAL_MODE) { UIEcho " $ESC[90m[Local Mode] Skipping HarvestMap updates.$ESC[0m`n" }
        else { UIEcho " $ESC[31m[-] HarvestMap not enabled in AddOnSettings.txt. $ESC[35mSkipping...$ESC[0m`n" }
    } else {
        $HM_DIR = "$ADDON_DIR\HarvestMapData"
        $EMPTY_FILE = "$HM_DIR\Main\emptyTable.lua"
        $MAIN_HM_FILE = "$SAVED_VAR_DIR\HarvestMap.lua"
        $HM_SNAP = "$SNAP_DIR\lttc_hm_main_snapshot.lua"

        if (Test-Path $HM_DIR) {
            $HM_CHANGED = $true
            $localHmStatus = "Out-of-Sync"
            if ((Test-Path $MAIN_HM_FILE) -and !(Test-FileNewer $MAIN_HM_FILE $HM_SNAP)) {
                $HM_CHANGED = $false
                $localHmStatus = "Synced"
            }

            $global:HM_LAST_CHECK = $CURRENT_TIME; $global:CONFIG_CHANGED = $true
            $V_COL = if (!$HM_CHANGED) { "$ESC[92m" } else { "$ESC[31m" }

            UIEcho "$ESC[1m$ESC[97m [4/4] Updating HarvestMap Data $ESC[0m"
            UIEcho " $ESC[33mVerifying HarvestMap local data state...$ESC[0m"
            if ((To-Num $global:HM_LAST_DOWNLOAD) -gt 0) { UIEcho "`t$ESC[90mLast_Download= $ESC[92m$(Convert-TimeStr ([long](To-Num $global:HM_LAST_DOWNLOAD)))$ESC[0m" }
            else { UIEcho "`t$ESC[90mLast_Download= $ESC[31mNever$ESC[0m" }
            UIEcho "`t$ESC[90mLocal_Data_Status= ${V_COL}$localHmStatus$ESC[0m"

            if (!$HM_CHANGED) {
                UIEcho " $ESC[90mNo changes detected. $ESC[92mHarvestMap.lua up-to-date.$ESC[0m`n"
            } else {
                $HM_TIME_DIFF = $CURRENT_TIME - (To-Num $global:HM_LAST_DOWNLOAD)
                if ($HM_TIME_DIFF -lt 3600 -and $HM_TIME_DIFF -ge 0) {
                    $WAIT_MINS = [math]::Floor((3600 - $HM_TIME_DIFF) / 60)
                    $notifHM = "Cooldown ($WAIT_MINS min)"
                    UIEcho " $ESC[33mLocal changes detected, but download is on cooldown for"
                    UIEcho " $WAIT_MINS more minutes. $ESC[35mSkipping.$ESC[0m`n"
                } else {
                    if (!(Test-Path $SAVED_VAR_DIR)) { New-Item -ItemType Directory -Force -Path $SAVED_VAR_DIR | Out-Null }
                    $hmFailed = $false
                    $zones = @("AD", "EP", "DC", "DLC", "NF")

                    UIEcho " $ESC[36mTargeting following database chunks for merge:$ESC[0m"
                    foreach ($zone in $zones) { UIEcho " $ESC[90m-> $HM_DIR\Modules\HarvestMap${zone}\HarvestMap${zone}.lua$ESC[0m" }

                    Start-Spinner "Preparing HarvestMap data..."
                    foreach ($zone in $zones) {
                        Update-Spinner "Merging local HarvestMap ${zone} data..."
                        $svfn1 = "$SAVED_VAR_DIR\HarvestMap${zone}.lua"
                        $svfn2 = "${svfn1}~"

                        if (Test-Path -LiteralPath $svfn1) {
                            Move-Item -LiteralPath $svfn1 -Destination $svfn2 -Force
                        } elseif (Test-Path $EMPTY_FILE) {
                            [System.IO.File]::WriteAllText($svfn2, "Harvest${zone}_SavedVars" + [System.IO.File]::ReadAllText($EMPTY_FILE))
                        } else {
                            [System.IO.File]::WriteAllText($svfn2, "Harvest${zone}_SavedVars={[`"data`"]={}}")
                        }

                        $modDir = "$HM_DIR\Modules\HarvestMap${zone}"
                        if (!(Test-Path $modDir)) { New-Item -ItemType Directory -Force -Path $modDir | Out-Null }

                        Update-Spinner "Downloading HarvestMap ${zone} chunk..."
                        & curl.exe -s -f -L -A "$HM_USER_AGENT" -d "@$svfn2" -o "$modDir\HarvestMap${zone}.lua" "http://harvestmap.binaryvector.net:8081" 2>$null
                        if ($LASTEXITCODE -ne 0) {
                            & curl.exe -s -f -L -H "User-Agent: $RAND_UA" -d "@$svfn2" -o "$modDir\HarvestMap${zone}.lua" "http://harvestmap.binaryvector.net:8081" 2>$null
                            if ($LASTEXITCODE -ne 0) { $hmFailed = $true }
                        }
                    }

                    if (!$hmFailed) {
                        if (Test-Path $MAIN_HM_FILE) { Copy-Item -LiteralPath $MAIN_HM_FILE -Destination $HM_SNAP -Force -ErrorAction SilentlyContinue }
                        $global:HM_LAST_DOWNLOAD = $CURRENT_TIME; $global:CONFIG_CHANGED = $true
                        $notifHM = "Updated successfully"
                        Stop-Spinner 0 "HarvestMap Data Successfully Updated"
                    } else {
                        $notifHM = "Error (Server Blocked)"
                        Stop-Spinner 1 "HarvestMap Update Failed"
                    }
                    UIEcho ""
                }
            }
        } else {
            $notifHM = "Not Found (Skipped)"
            UIEcho "$ESC[1m$ESC[97m [4/4] Updating HarvestMap Data (SKIPPED) $ESC[0m"
            UIEcho " $ESC[31m[!] HarvestMapData folder not found in: $ADDON_DIR. $ESC[35mSkipping...$ESC[0m`n"
        }
    }
    if ($FOUND_NEW_DATA) { Copy-Item -Path $TEMP_SCAN_FILE -Destination $LAST_SCAN_FILE -Force }

    Prune-History
    if ($global:CONFIG_CHANGED) { save_config }

    Set-Location $env:USERPROFILE
    Start-Spinner "Cleaning up temp files & old logs..."

    try {
        $logCutoff = (Get-Date).AddDays(-3).ToString("yyyy-MM-dd HH:mm:ss"); $keepLog = $false
        $keptLog = @(foreach ($l in [System.IO.File]::ReadAllLines($LOG_FILE)) {
            if ($l -match '^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]') { $keepLog = ([string]::CompareOrdinal($matches[1], $logCutoff) -ge 0) }
            if ($keepLog) { $l }
        })
        [System.IO.File]::WriteAllLines($LOG_FILE, [string[]]$keptLog)
    } catch {}

    $deleted = New-Object System.Collections.Generic.List[string]
    foreach ($t in @($TEMP_DIR, "$TEMP_DIR_ROOT\*.tmp", "$TEMP_DIR_ROOT\*.out", "$TEMP_DIR_ROOT\*.zip", "$TEMP_DIR_ROOT\ESOHub_Extracted", "$TEMP_DIR_ROOT\lttc_upload_*", "$TEMP_DIR_ROOT\DB_Update")) {
        foreach ($it in @(Get-Item -Path $t -ErrorAction SilentlyContinue)) {
            $deleted.Add($it.FullName)
            if ($it.PSIsContainer) { Get-ChildItem -LiteralPath $it.FullName -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object { $deleted.Add($_.FullName) } }
        }
        Remove-Item -Path $t -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($global:LOG_MODE -eq "detailed") { foreach ($f in $deleted) { Log-Event "ITEM" "Deleted Temporary File/Folder: $f" } }

    Stop-Spinner 0 "Cleanup complete ($($deleted.Count) items removed)"
    if ($deleted.Count -gt 0 -and !$global:SILENT) {
        foreach ($f in $deleted) { UIEcho " $ESC[90m-> Deleted: $f$ESC[0m" }
        UIEcho ""
    }

    if ($global:ENABLE_NOTIFS) {
        $msg = "TTC: $notifTTC`nESO-Hub: $notifEH`nHarvestMap: $notifHM"
        if ($global:notifAddons) { $msg += "`nAdd-ons: $($global:notifAddons)" }
        Send-Notification "Windows Tamriel Trade Center v$APP_VERSION" $msg
    }

    if ($AUTO_MODE -eq "1") { 
        try {
            $parent = Get-CimInstance Win32_Process -Filter "ProcessId = $PID"
            if ($parent.ParentProcessId) {
                $parentProc = Get-Process -Id $parent.ParentProcessId -ErrorAction SilentlyContinue
                if ($parentProc.Name -eq "cmd") { Stop-Process -Id $parentProc.Id -Force }
            }
        } catch {}
        [Environment]::Exit(0)
    }

    if ($CURRENT_TIME -ge $global:TARGET_RUN_TIME) { $global:TARGET_RUN_TIME = $CURRENT_TIME + 3600; save_config }
    $target_time = $global:TARGET_RUN_TIME

    if ($IS_STEAM_LAUNCH) {
        $gracePeriodEnd = $CURRENT_TIME + 15
        if ($SILENT) {
            while ([int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -lt $target_time) {
                Wait-WithEvents 10
                $now = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                if ($now -gt $gracePeriodEnd -and !(Get-Process "eso64", "zos", "eso", "Bethesda.net_Launcher" -ErrorAction SilentlyContinue)) { 
                    try {
                        $parent = Get-CimInstance Win32_Process -Filter "ProcessId = $PID"
                        if ($parent.ParentProcessId) {
                            $parentProc = Get-Process -Id $parent.ParentProcessId -ErrorAction SilentlyContinue
                            if ($parentProc.Name -eq "cmd") { Stop-Process -Id $parentProc.Id -Force }
                        }
                    } catch {}
                    [Environment]::Exit(0) 
                }
            }
        } else {
            Write-Host " $ESC[1;97;101m Restarting Sequence in 60 minutes... (Steam Mode) $ESC[0m`n"
            while ([int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -lt $target_time) {
                $now = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                $rem = $target_time - $now
                $min = [math]::Floor($rem / 60); $sec = $rem % 60
                Write-Host -NoNewline "`r $ESC[1;97;101m Countdown: ${min}:$($sec.ToString('D2')) $ESC[0m $ESC[0;90m(Press 'b' to browse data)$ESC[0m $ESC[0K"
                if ($now -gt $gracePeriodEnd -and $rem % 5 -eq 0 -and !(Get-Process "eso64", "zos", "eso", "Bethesda.net_Launcher" -ErrorAction SilentlyContinue)) { 
                    try {
                        $parent = Get-CimInstance Win32_Process -Filter "ProcessId = $PID"
                        if ($parent.ParentProcessId) {
                            $parentProc = Get-Process -Id $parent.ParentProcessId -ErrorAction SilentlyContinue
                            if ($parentProc.Name -eq "cmd") { Stop-Process -Id $parentProc.Id -Force }
                        }
                    } catch {}
                    [Environment]::Exit(0) 
                }
                Wait-WithEvents 1
            }
        }
    } else {
        if ($SILENT) { Wait-WithEvents 3600 } 
        else {
            Write-Host " $ESC[1;97;101m Restarting Sequence in 60 minutes... (Standalone Mode) $ESC[0m`n"
            while ([int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -lt $target_time) {
                $now = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                $rem = $target_time - $now
                $min = [math]::Floor($rem / 60); $sec = $rem % 60
                Write-Host -NoNewline "`r $ESC[1;97;101m Countdown: ${min}:$($sec.ToString('D2')) $ESC[0m $ESC[0;90m(Press 'b' to browse data)$ESC[0m $ESC[0K"
                Wait-WithEvents 1
            }
        }
    }
}