@echo off

:: ====================================================================================
:: {Windows} Tamriel Trade Center Auto-Updater v6.0
:: Created by @APHONlC | Icon by @THAMER_AKATOSH
:: ------------------------------------------------------------------------------------
:: A utility for ESO to automate TTC, HarvestMap, and ESO-Hub updates.
:: I don't own these addons; this is just a tool to keep all their data updated.
::
:: NOTICE: This script is READ-ONLY for your SavedVariables. It won't touch your 
:: game data, but keep backups anyway just to be safe.
:: ====================================================================================
:: LICENSE & USAGE
:: Copyright (c) 2021-2026 @APHONlC. All rights reserved.
:: - Don't re-upload or mirror this on ESOUI/Nexus/etc without asking me first.
:: - Don't release modified versions of this code publicly.
:: - You're 100% free to tweak the code for your own private use on your machine.
:: ====================================================================================

:: Quick folder guide:
:: \Backups   -> Snapshots of Steam .vdf files before it mess with launch options.
:: \Database  -> LTTC_Database.db (Items Formatting) & LTTC_History.db (Your 30-day history).
:: \Logs      -> Simple or Detailed logs (WTTC.log).
:: \Snapshots -> Stores MD5 hashes of game files to check for changes before uploading.
:: \Temp      -> Active downloads and extraction staging area.

:: Cleanup note:
:: Everything in \Temp (zips, extracted folders, .tmp files) gets nuked 
:: automatically after every loop to keep things tidy.

setlocal
set "SCRIPT_FULL_PATH=%~f0"
set "PS_ARGS=%*"

set "WIN_STYLE=-WindowStyle Normal"
echo.%* | findstr /C:"--silent" >nul && set "WIN_STYLE=-WindowStyle Hidden"
echo.%* | findstr /C:"--task" >nul && set "WIN_STYLE=-WindowStyle Hidden"
powershell -Sta %WIN_STYLE% -NoProfile -ExecutionPolicy Bypass -Command "$code = (Get-Content -LiteralPath '%~f0' -Raw) -replace '(?sm)^.*?\n==POWERSHELL_START==\r?\n',''; $sb = [ScriptBlock]::Create($code); & $sb"

if %errorlevel% neq 0 pause
exit /b %errorlevel%

==POWERSHELL_START==
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
$ErrorActionPreference = "SilentlyContinue"

$APP_VERSION = "6.0"
$APP_TITLE = "Windows Tamriel Trade Center v$APP_VERSION"
$TASK_NAME = "Windows Tamriel Trade Center v$APP_VERSION"
$SYS_ID = "windows"

$ESC = [char]27
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$host.UI.RawUI.WindowTitle = $APP_TITLE

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

if (!(Test-Path $ICON_FILE)) {
    try { & curl.exe -s -m 15 -L -o $ICON_FILE "https://raw.githubusercontent.com/MPHONlC/Cross-platform-Tamriel-Trade-Center-HarvestMap-ESO-Hub-Auto-Updater/refs/heads/main/icon.ico" } catch {}
}

$currentPid = $PID
$existingProcess = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' AND ProcessId != $currentPid" | Where-Object { $_.CommandLine -match "Windows_Tamriel_Trade_Center" } | Select-Object -First 1

if ($existingProcess) {
    $isBackground = ($env:PS_ARGS -match "--silent|--task|--steam")
    if ($isBackground) {
        try {
            $evt = [System.Threading.EventWaitHandle]::OpenExisting("Global\WTTC_RestoreEvent_$APP_VERSION")
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

$script:restoreEvent = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, "Global\WTTC_RestoreEvent_$APP_VERSION")

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
if (!$TARGET_RUN_TIME) { $global:TARGET_RUN_TIME = 0 }
if (!$TARGET_USERNAME) { $global:TARGET_USERNAME = "" }

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
TARGET_RUN_TIME="$TARGET_RUN_TIME"
TARGET_USERNAME="$TARGET_USERNAME"
SKIP_DL_TTC="$SKIP_DL_TTC"
SKIP_DL_HM="$SKIP_DL_HM"
SKIP_DL_EH="$SKIP_DL_EH"
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

for ($i = 0; $i -lt $parsedArgs.Count; $i++) {
    switch ($parsedArgs[$i]) {
        "--silent" { $global:SILENT = $true }
        "--auto" { $global:AUTO_PATH = $true }
        "--na" { $global:AUTO_SRV = "1" }
        "--eu" { $global:AUTO_SRV = "2" }
        "--both" { $global:AUTO_SRV = "3" }
        "--loop" { $global:AUTO_MODE = "2" }
        "--once" { $global:AUTO_MODE = "1" }
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

    $DesktopPath = [Environment]::GetFolderPath("Desktop")
    $startupPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    $startupShortcut = "$startupPath\Windows_TTC_Updater.lnk"
    $vbsLauncher = "$TARGET_DIR\wttc_launcher.vbs"
    
    if (Test-Path "$DesktopPath\Windows Tamriel Trade Center.lnk") { Remove-Item "$DesktopPath\Windows Tamriel Trade Center.lnk" -Force -ErrorAction SilentlyContinue }

    Write-Host "`n$ESC[0;33m9. Run automatically in the background when PC Starts?$ESC[0m"
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
Register-ScheduledTask -Action `$action -Trigger `$trigger -Settings `$settings -TaskName '$TASK_NAME' -Description 'Cross-Platform Auto-Updater for TTC, HarvestMap & ESO-Hub. Created by @APHONIC' -Force
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

    Write-Host "`n$ESC[0;33m10. Desktop Shortcut$ESC[0m"
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
            $Shortcut.Arguments = "$SHORTCUT_SRV_FLAG $LOOP_FLAG"
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
    
    Write-Host "$ESC[0;33m11. Steam Launch Options$ESC[0m"
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
                if ($text -match '("306130"\s*\{[\s\S]*?"LaunchOptions"\s*)"((?:\\"|[^"])*)"') {
                    $pre = $matches[1]
                    $cur = $matches[2]
                    
                    $cur = $cur -replace '\s*(?:nohup\s+)?cmd /c start.*?%command%', ' %command%'
                    $cur = $cur -replace '\s*(?:nohup\s+)?cmd /c start.*?(?:Tamriel_Trade_Center|--steam).*?$', ''
                    
                    if ($cur -match '%command%') {
                        $cur = $cur -replace '%command%', $escapedStr
                    } else {
                        $cur = $cur.Trim()
                        if ($cur -eq "") { $cur = $escapedStr } else { $cur = "$cur $escapedStr" }
                    }
                    $text = [regex]::Replace($text, '("306130"\s*\{[\s\S]*?)"LaunchOptions"\s*"((?:\\"|[^"])*)"', "${pre}`"$cur`"")
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

if ($SETUP_COMPLETE -and !$HAS_ARGS) {
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
    
    foreach ($k in $raw.Keys) {
        $parts = $raw[$k].Split('|')
        if ($k -match '^[0-9]+$') {
            $loc_name = $parts[0]
            $coord_str = $parts[1]
            $found_map = ""
            $found_full_loc = $loc_name
            foreach ($ek in $raw.Keys) {
                if ($ek -notmatch '^[0-9]+$') {
                    $eparts = $raw[$ek].Split('|')
                    $eloc = $eparts[0]
                    $emap = $eparts[1]
                    if ($eloc.StartsWith("$loc_name - ") -or $eloc.StartsWith("$loc_name Wayshrine") -or $eloc -eq $loc_name) {
                        $found_map = $emap
                        $found_full_loc = $eloc
                        break
                    }
                }
            }
            $global:k_dict[$k] = "$found_full_loc|$found_map|$coord_str"
        } else {
            if ($parts.Length -ge 2 -and $parts[1] -match '^[0-9]+$') {
                $global:k_dict[$k] = "$($parts[0])|$($parts[1])|"
            }
        }
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
    if ($ln -match 'citation|truly superb glyph|tempering alloy|dreugh wax|rosin|kuta|perfect roe|aetherial dust|chromium plating|style page:|runebox:|research scroll|psijic ambrosia|master .* writ|indoril inks:') { return 5 }
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
Auto-Repair-Database

function Prune-History {
    if (!(Test-Path $HIST_FILE)) { return }
    Log-Event "INFO" "prune_history: Initiating 30 days data prune and metadata sync."
    $cutoff = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 2592000
    
    $dbName = @{}; $dbQual = @{}
    if (Test-Path $DB_FILE) {
        foreach ($line in [System.IO.File]::ReadLines($DB_FILE)) {
            $p = $line.Split('|')
            if ($p[0] -match '^[0-9]+$') {
                $dbName[$p[0]] = if ($p.Length -ge 6) {$p[5]} else {$p[2]}
                $dbQual[$p[0]] = [int]$p[1]
            }
        }
    }
    
    $newHist = New-Object System.Collections.ArrayList
    $prunedItems = New-Object System.Collections.ArrayList
    
    foreach ($line in [System.IO.File]::ReadLines($HIST_FILE)) {
        $p = $line.Split('|')
        if ($p[0] -eq "HISTORY") {
            if ([int]$p[1] -ge $cutoff) {
                if ($dbName.ContainsKey($p[5]) -and $dbName[$p[5]] -notmatch '^Unknown Item') {
                    $p[6] = $dbName[$p[5]]
                }
                if ($dbQual.ContainsKey($p[5])) {
                    $q = $dbQual[$p[5]]; $c = "$ESC[0m"
                    if($q -eq 0) { $c = "$ESC[90m" } elseif($q -eq 1) { $c = "$ESC[97m" }
                    elseif($q -eq 2) { $c = "$ESC[32m" } elseif($q -eq 3) { $c = "$ESC[36m" }
                    elseif($q -eq 4) { $c = "$ESC[35m" } elseif($q -eq 5) { $c = "$ESC[33m" }
                    elseif($q -eq 6) { $c = "$ESC[38;5;214m" }
                    $p[11] = $c
                }
                if ($p[11] -notmatch '^\033\[') { $p[11] = "$ESC[0m" }
                
                $src = "TTC"; $scans = 1
                if ($p[$p.Length-1] -match '^[0-9]+$') {
                    $scans = [int]$p[$p.Length-1]; $src = $p[$p.Length-2]
                } else { $src = $p[$p.Length-1] }
                
                $p[12] = if ($src -match 'Unknown|^$') { "TTC" } else { $src }
                $p[13] = $scans
                [void]$newHist.Add(($p[0..13] -join '|'))
            } else {
                [void]$prunedItems.Add($line)
            }
        }
    }
    [System.IO.File]::WriteAllLines($HIST_FILE, $newHist.ToArray())
    
    if ($prunedItems.Count -gt 0) {
        UIEcho "`n $ESC[33mPruned $($prunedItems.Count) old items from history (30+ days):$ESC[0m"
        foreach ($pruned in $prunedItems) {
            $p = $pruned.Split('|')
            $itemName = if ($p.Length -ge 7) { $p[6] } else { "Unknown Item" }
            UIEcho " $ESC[90m-> Pruned: $itemName$ESC[0m"
            if ($global:LOG_MODE -eq "detailed") { Log-Event "ITEM" "Pruned: $pruned" }
        }
    }
}

function Browse-Database {
    try { [ConsoleConfig]::DisableQuickEdit() } catch {}
    Log-Event "INFO" "browse_database: entering DB browser"
    Clear-Host
    Write-Host "`n$ESC[92m===========================================================================$ESC[0m"
    Write-Host "$ESC[1m$ESC[94m                         TTC & ESO-Hub Database Browser$ESC[0m"
    Write-Host "$ESC[97m                 (Data automatically retained for the last 30 days)$ESC[0m"
    Write-Host "$ESC[92m===========================================================================$ESC[0m`n"
    
    if (!(Test-Path $HIST_FILE)) {
        Write-Host "$ESC[31m[!] No history database found. Wait for the script to extract data first.$ESC[0m`n"
        Write-Host "$ESC[31m[!] (or go visit a guild store in-game and press scan then /reloadui)$ESC[0m`n"
        Read-Host "$ESC[33mPress Enter to return...$ESC[0m"
        return
    }

    Load-Config $CONFIG_FILE

    while ($true) {
        Write-Host "`n$ESC[33mSelect a Database Function:$ESC[0m"
        Write-Host " 1) View / Search Database (Paginated & Sorted)"
        Write-Host " 2) Top 10 Most Selling Items (By Volume)"
        Write-Host " 3) Top 10 Highest Grossing Items (By Total Gold)"
        Write-Host " 4) Suggested Price Calculator (Outlier Elimination)"
        Write-Host " 5) View Previous Extraction History (Paginated & Sorted)"
        Write-Host " 6) Settings: Edit My Target Username $ESC[90m(Current: $($global:TARGET_USERNAME))$ESC[0m"
        Write-Host " 7) Exit Browser & Resume Updater"
        $opt = Read-Host "$ESC[33mChoice [1-7]$ESC[0m"
        
        if ($opt -eq "7") { 
            Log-Event "INFO" "browse_database: exiting DB browser"
            Clear-Host
            if (Test-Path $UI_STATE_FILE) {
                Get-Content -LiteralPath $UI_STATE_FILE -Raw | Write-Host -NoNewline
            }
            break 
        }
        
        if ($opt -eq "6") {
            Write-Host "`n$ESC[36m--- Settings: Edit My Target Username ---$ESC[0m"
            $tUser = Read-Host "$ESC[33mEnter your exact @Username (leave blank to clear)$ESC[0m"
            if ([string]::IsNullOrWhiteSpace($tUser)) {
                $global:TARGET_USERNAME = ""
                Write-Host " $ESC[90m[-] Username cleared.$ESC[0m`n"
                Log-Event "INFO" "DB Browser: Target Username cleared from settings."
            } else {
                if ($tUser -notmatch '^@') { $tUser = "@$tUser" }
                $global:TARGET_USERNAME = $tUser
                Write-Host " $ESC[92m[+] Username saved permanently to config as $TARGET_USERNAME$ESC[0m`n"
                Log-Event "INFO" "DB Browser: Target Username updated to '$TARGET_USERNAME'"
            }
            save_config
            Read-Host "$ESC[33mPress Enter to return...$ESC[0m"
            continue
        }
        
        if ($opt -match '^[12345]$') {
            $s_term = ""; $src_filter = ""; $personal = "N"
            if ($opt -eq "1" -or $opt -eq "4" -or $opt -eq "5") {
                if ($opt -eq "4") { $s_term = (Read-Host "$ESC[33mEnter exact or partial item name for price check:$ESC[0m").ToLower() }
                else { $s_term = (Read-Host "$ESC[33mEnter search term (leave empty for ALL data):$ESC[0m").ToLower() }
            }
            
            $src_filter = (Read-Host "$ESC[33mSearch by Source [TTC or ESO-Hub] (leave empty for ALL data):$ESC[0m").ToLower()
            $personal = Read-Host "$ESC[33mFilter to your @Username only? (y/N):$ESC[0m"
            
            Write-Host "`n$ESC[33mTime Filter:$ESC[0m"
            Write-Host " 1) Past 1 Week"
            Write-Host " 2) Past 2 Weeks"
            Write-Host " 3) Past 3 Weeks"
            Write-Host " 4) All Data"
            $time_opt = Read-Host "$ESC[33mChoice [1-4] (default 4)$ESC[0m"
            
            $cutoff = 0
            $now_ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            if ($time_opt -eq "1") { $cutoff = $now_ts - 604800 }
            elseif ($time_opt -eq "2") { $cutoff = $now_ts - 1209600 }
            elseif ($time_opt -eq "3") { $cutoff = $now_ts - 1814400 }

            $t_user = ""
            if ($personal -match '^[Yy]$') {
                if ([string]::IsNullOrWhiteSpace($global:TARGET_USERNAME)) {
                    Write-Host "$ESC[31m[!] @Username not set! Using global data. Set it in Option 6 first.$ESC[0m"
                } else { $t_user = $global:TARGET_USERNAME.ToLower() }
            }
            
            $sort_opt = "1"
            if ($opt -eq "1" -or $opt -eq "5") {
                Write-Host "`n$ESC[33mSort By:$ESC[0m"
                Write-Host " 1) Date (Newest First)"
                Write-Host " 2) Date (Oldest First)"
                Write-Host " 3) Price (Highest First)"
                Write-Host " 4) Price (Lowest First)"
                Write-Host " 5) Alphabetical (A-Z)"
                $sort_opt = Read-Host "$ESC[33mChoice [1-5]$ESC[0m"
            }
            
            if ($opt -eq "2") {
                if ($t_user) { Write-Host "`n$ESC[36m--- Top 10 Selling Items (By Volume) [$t_user] ---$ESC[0m" }
                else { Write-Host "`n$ESC[36m--- Top 10 Selling Items (By Volume) [Global] ---$ESC[0m" }
            } elseif ($opt -eq "3") {
                if ($t_user) { Write-Host "`n$ESC[36m--- Top 10 Highest Grossing Items [$t_user] ---$ESC[0m" }
                else { Write-Host "`n$ESC[36m--- Top 10 Highest Grossing Items [Global] ---$ESC[0m" }
            } elseif ($opt -eq "4") {
                Write-Host "`n$ESC[36m--- Suggested Price Check ---$ESC[0m"
            } elseif ($opt -eq "5") {
                Write-Host "`n$ESC[36m--- View Previous Extraction History ---$ESC[0m"
            } else { Write-Host "`n$ESC[36mProcessing data...$ESC[0m" }
            
            $results = New-Object System.Collections.ArrayList
            foreach ($line in [System.IO.File]::ReadLines($HIST_FILE)) {
                $p = $line.Split('|')
                if ($p[0] -eq "HISTORY") {
                    if ($cutoff -gt 0 -and [int]$p[1] -lt $cutoff) { continue }
                    if ($src_filter -and $p[12].ToLower().IndexOf($src_filter) -eq -1) { continue }
                    if ($t_user -and $p[7].ToLower() -ne $t_user -and $p[8].ToLower() -ne $t_user) { continue }
                    if ($p[6] -match '^Unknown Item') { continue }
                    if ($p[9] -eq "Unknown Guild" -or $p[9] -eq "Guilds") { continue }
                    
                    if ($s_term) {
                        $kiosk = $p[10]
                        if ($kiosk -ne "" -and $kiosk -ne "0" -and $global:k_dict.ContainsKey($kiosk)) {
                            $kp = $global:k_dict[$kiosk].Split('|')
                            $kiosk = $kp[0]
                        }
                        $search_str = "$($line)|$kiosk".ToLower()
                        if ($search_str.IndexOf($s_term) -eq -1) { continue }
                    }
                    
                    [void]$results.Add([PSCustomObject]@{
                        TS = [int]$p[1]; Action = $p[2]; Price = [double]$p[3]; Qty = [int]$p[4]
                        ID = $p[5]; Name = $p[6]; Buyer = $p[7]; Seller = $p[8]; Guild = $p[9]; Kiosk = $p[10]
                        Color = $p[11]; Src = $p[12]; Scans = [int]$p[13]
                    })
                }
            }
            
            if ($results.Count -eq 0) { Write-Host " $ESC[31m[-] No results found.$ESC[0m"; Read-Host "`n$ESC[33mPress Enter to return...$ESC[0m"; continue }
            
            if ($opt -eq "1" -or $opt -eq "5") {
                if ($sort_opt -eq "2") { $sorted = $results | Sort-Object TS }
                elseif ($sort_opt -eq "3") { $sorted = $results | Sort-Object Price -Descending }
                elseif ($sort_opt -eq "4") { $sorted = $results | Sort-Object Price }
                elseif ($sort_opt -eq "5") { $sorted = $results | Sort-Object Name }
                else { $sorted = $results | Sort-Object TS -Descending }
                
                $db_guild_id = @{}
                foreach ($line in [System.IO.File]::ReadLines($DB_FILE)) {
                    $p = $line.Split('|')
                    if ($p[0] -eq "GUILD") { $db_guild_id[$p[1]] = $p[2] }
                }

                $page = 1; $pageSize = 50; $total = $sorted.Count
                while ($true) {
                    Clear-Host
                    Write-Host "$ESC[36m--- Results Page $page of $([math]::Ceiling($total/$pageSize)) ---$ESC[0m`n"
                    $start = ($page - 1) * $pageSize
                    $end = [math]::Min($start + $pageSize, $total)
                    
                    for ($i = $start; $i -lt $end; $i++) {
                        $r = $sorted[$i]
                        $diff = $now_ts - $r.TS
                        $rel = if ($r.TS -eq 0) {"Active"} elseif ($diff -lt 60) {"$diff" + "s ago"} elseif ($diff -lt 3600) {"$([math]::Floor($diff/60))m ago"} elseif ($diff -lt 86400) {"$([math]::Floor($diff/3600))h ago"} else {"$([math]::Floor($diff/86400))d ago"}
                        
                        $actCol = "$ESC[36m"; if ($r.Action -eq "Sold") { $actCol = "$ESC[38;5;214m" }; if ($r.Action -eq "Purchased") { $actCol = "$ESC[92m" }; if ($r.Action -eq "Cancelled") { $actCol = "$ESC[31m" }
                        
                        $k_str = ""
                        if ($r.Kiosk -ne "" -and $r.Kiosk -ne "0") {
                            if ($global:k_dict.ContainsKey($r.Kiosk)) {
                                $kp = $global:k_dict[$r.Kiosk].Split('|')
                                $disp = $kp[0]; $mId = $kp[1]; $p = $kp[2]
                                if ($mId -and $p) { $k_str = " $ESC[90m($ESC]8;;https://eso-hub.com/en/interactive-map?map=$mId&ping=$p$ESC\$disp$ESC]8;;$ESC\)$ESC[0m" }
                                elseif ($mId) { $k_str = " $ESC[90m($ESC]8;;https://eso-hub.com/en/interactive-map?map=$mId$ESC\$disp$ESC]8;;$ESC\)$ESC[0m" }
                                elseif ($p) { $k_str = " $ESC[90m($ESC]8;;https://eso-hub.com/en/interactive-map?ping=$p$ESC\$disp$ESC]8;;$ESC\)$ESC[0m" }
                                else { $k_str = " $ESC[90m($disp)$ESC[0m" }
                            } else { $k_str = " $ESC[90m(Kiosk ID: $($r.Kiosk))$ESC[0m" }
                        }
                        
                        $g_str = ""
                        if ($r.Guild -ne "" -and $r.Guild -ne "Unknown Guild" -and $r.Guild -ne "Guilds") {
                            if ($db_guild_id.ContainsKey($r.Guild)) {
                                $gid = $db_guild_id[$r.Guild]
                                $fake_url = "|H1:guild:$gid|h$($r.Guild)|h"
                                $g_str = " in $ESC[35m$ESC]8;;$fake_url$ESC\$($r.Guild)$ESC]8;;$ESC\$ESC[0m"
                            } else { $g_str = " in $ESC[35m$($r.Guild)$ESC[0m" }
                        }
                        
                        $name_enc = [uri]::EscapeDataString($r.Name).Replace("%20", "+").Replace("'", "%27")
                        $link_start = "$ESC]8;;https://eso-hub.com/en/trading/$($r.ID)$ESC\"
                        if ($r.Src -eq "TTC") { $link_start = "$ESC]8;;https://us.tamrieltradecentre.com/pc/Trade/SearchResult?SearchType=Sell&ItemNamePattern=$name_enc$ESC\" }
                        $link_end = "$ESC]8;;$ESC\"
                        
                        $scan_str = if ($r.Scans -gt 1) {" $ESC[96m[$($r.Scans)x Scans]$ESC[0m"} else {""}
                        
                        $trade_str = ""
                        if ($r.Seller -and $r.Buyer) { $trade_str = " by $ESC[36m$($r.Seller)$ESC[0m to $ESC[36m$($r.Buyer)$ESC[0m" }
                        elseif ($r.Seller) { $trade_str = " by $ESC[36m$($r.Seller)$ESC[0m" }
                        elseif ($r.Buyer) { $trade_str = " to $ESC[36m$($r.Buyer)$ESC[0m" }

                        Write-Host " [$ESC[90m$rel$ESC[0m] ${actCol}$($r.Action)$ESC[0m for $ESC[32m$($r.Price)$ESC[33mgold$ESC[0m - $ESC[32m$($r.Qty)x$ESC[0m ${link_start}$($r.Color)$($r.Name)$ESC[0m${link_end}$trade_str$g_str$k_str [$ESC[90m$($r.Src)$ESC[0m]$scan_str"
                    }
                    
                    Write-Host "`n$ESC[33mPress [SPACE] for next page, or 'q' to quit...$ESC[0m"
                    $key = [System.Console]::ReadKey($true)
                    if ($key.KeyChar -eq 'q' -or $key.KeyChar -eq 'Q') { break }
                    if ($end -ge $total) { break }
                    $page++
                }
            } elseif ($opt -eq "2") {
                Log-Event "INFO" "DB Browser: Generating Top 10 Selling Items list."
                $grouped = $results | Where-Object { $_.Action -match 'Sold|Purchased|Listed' -and $_.Qty -gt 0 } | Group-Object Name
                $top = New-Object System.Collections.ArrayList
                foreach ($g in $grouped) {
                    $vol = ($g.Group | Measure-Object Qty -Sum).Sum
                    $prices = $g.Group | ForEach-Object { $_.Price / $_.Qty } | Sort-Object
                    $sugg = 0
                    if ($prices.Count -ge 5) {
                        $trim = [math]::Max(1, [math]::Floor($prices.Count * 0.10))
                        $valid = $prices[$trim..($prices.Count - $trim - 1)]
                        $sugg = ($valid | Measure-Object -Average).Average
                    }
                    [void]$top.Add([PSCustomObject]@{ Vol = $vol; Name = $g.Name; Sugg = $sugg; Color = $g.Group[0].Color; ID = $g.Group[0].ID; Src = $g.Group[0].Src; PtCount = $prices.Count })
                }
                $sortedTop = $top | Sort-Object Vol -Descending | Select-Object -First 10
                foreach ($t in $sortedTop) {
                    $p_str = if ($t.Sugg -eq 0) {"Low Data: Based on $($t.PtCount) pts"} else {"$([math]::Round($t.Sugg, 2))g"}
                    
                    $name_enc = [uri]::EscapeDataString($t.Name).Replace("%20", "+").Replace("'", "%27")
                    $link_start = "$ESC]8;;https://eso-hub.com/en/trading/$($t.ID)$ESC\"
                    if ($t.Src -eq "TTC") { $link_start = "$ESC]8;;https://us.tamrieltradecentre.com/pc/Trade/SearchResult?SearchType=Sell&ItemNamePattern=$name_enc$ESC\" }
                    $link_end = "$ESC]8;;$ESC\"
                    
                    Write-Host " $ESC[36m$($t.Vol)x$ESC[0m sold - ${link_start}$($t.Color)$($t.Name)$ESC[0m${link_end} (Avg: $ESC[33m$p_str$ESC[0m)"
                }
                Read-Host "`n$ESC[33mPress Enter to return...$ESC[0m"
            } elseif ($opt -eq "3") {
                Log-Event "INFO" "DB Browser: Generating Top 10 Highest Grossing Items list."
                $grouped = $results | Where-Object { $_.Action -match 'Sold|Purchased|Listed' -and $_.Qty -gt 0 } | Group-Object Name
                $top = New-Object System.Collections.ArrayList
                foreach ($g in $grouped) {
                    $gold = ($g.Group | Measure-Object Price -Sum).Sum
                    $prices = $g.Group | ForEach-Object { $_.Price / $_.Qty } | Sort-Object
                    $sugg = 0
                    if ($prices.Count -ge 5) {
                        $trim = [math]::Max(1, [math]::Floor($prices.Count * 0.10))
                        $valid = $prices[$trim..($prices.Count - $trim - 1)]
                        $sugg = ($valid | Measure-Object -Average).Average
                    }
                    [void]$top.Add([PSCustomObject]@{ Gold = $gold; Name = $g.Name; Sugg = $sugg; Color = $g.Group[0].Color; ID = $g.Group[0].ID; Src = $g.Group[0].Src; PtCount = $prices.Count })
                }
                $sortedTop = $top | Sort-Object Gold -Descending | Select-Object -First 10
                foreach ($t in $sortedTop) {
                    $p_str = if ($t.Sugg -eq 0) {"Low Data: Based on $($t.PtCount) pts"} else {"$([math]::Round($t.Sugg, 2))g"}
                    
                    $name_enc = [uri]::EscapeDataString($t.Name).Replace("%20", "+").Replace("'", "%27")
                    $link_start = "$ESC]8;;https://eso-hub.com/en/trading/$($t.ID)$ESC\"
                    if ($t.Src -eq "TTC") { $link_start = "$ESC]8;;https://us.tamrieltradecentre.com/pc/Trade/SearchResult?SearchType=Sell&ItemNamePattern=$name_enc$ESC\" }
                    $link_end = "$ESC]8;;$ESC\"
                    
                    Write-Host " $ESC[33m$($t.Gold)g$ESC[0m grossed - ${link_start}$($t.Color)$($t.Name)$ESC[0m${link_end} (Avg: $ESC[33m$p_str$ESC[0m)"
                }
                Read-Host "`n$ESC[33mPress Enter to return...$ESC[0m"
            } elseif ($opt -eq "4") {
                Log-Event "INFO" "DB Browser: Executed Suggested Price Check for '$s_term'"
                $grouped = $results | Where-Object { $_.Action -match 'Listed|Sold|Purchased' -and $_.Qty -gt 0 } | Group-Object Name
                foreach ($g in $grouped) {
                    if ($g.Count -lt 5) { continue }
                    
                    $prices = $g.Group | ForEach-Object { $_.Price / $_.Qty } | Sort-Object
                    $t = $g.Group[0]
                    $name_enc = [uri]::EscapeDataString($t.Name).Replace("%20", "+").Replace("'", "%27")
                    $link_start = "$ESC]8;;https://eso-hub.com/en/trading/$($t.ID)$ESC\"
                    if ($t.Src -eq "TTC") { $link_start = "$ESC]8;;https://us.tamrieltradecentre.com/pc/Trade/SearchResult?SearchType=Sell&ItemNamePattern=$name_enc$ESC\" }
                    $link_end = "$ESC]8;;$ESC\"
                    
                    $trim = [math]::Max(1, [math]::Floor($prices.Count * 0.10))
                    $valid = $prices[$trim..($prices.Count - $trim - 1)]
                    $avg = ($valid | Measure-Object -Average).Average
                    
                    Write-Host " ${link_start}$($t.Color)$($t.Name)$ESC[0m${link_end} - Suggested Price: $ESC[33m$([math]::Round($avg, 2))g$ESC[0m (Based on $($g.Count) data points)"
                }
                Read-Host "`n$ESC[33mPress Enter to return...$ESC[0m"
            }
        }
    }
}

function Apply-DB-Updates($updates) {
    if (!$updates -or $updates.Count -eq 0) { return }
    Log-Event "INFO" "apply_db_updates: applying database updates"
    
    $header = ""
    $dbLines = @{}
    if (Test-Path $DB_FILE) {
        $lines = [System.IO.File]::ReadAllLines($DB_FILE)
        foreach ($line in $lines) {
            if ($line.StartsWith("#DATABASE VERSION")) { $header = $line }
            elseif ($line.StartsWith("GUILD|")) { $p = $line.Split('|'); $dbLines["GUILD_" + $p[1]] = $line }
            elseif ($line.StartsWith("KIOSK|")) { $p = $line.Split('|'); $dbLines["KIOSK_" + $p[1]] = $line }
            else { $p = $line.Split('|'); if ($p[0] -match '^[0-9]+$') { $dbLines["ITEM_" + $p[0]] = $line } }
        }
    }
    
    foreach ($u in $updates) {
        $p = $u.Split('|')
        if ($p[0] -eq "DB_UPDATE") {
            $id = $p[1]; $val = ($p[1..($p.Length-1)] -join '|')
            $dbLines["ITEM_" + $id] = $val
        } elseif ($p[0] -eq "DB_GUILD") {
            $dbLines["GUILD_" + $p[1]] = "GUILD|$($p[1])|$($p[2])"
        } elseif ($p[0] -eq "DB_KIOSK") {
            $dbLines["KIOSK_" + $p[1]] = "KIOSK|$($p[1])|$($p[2])|$($p[3])|$($p[4])"
        }
    }
    
    $finalLines = New-Object System.Collections.ArrayList
    if ($header) { [void]$finalLines.Add($header) }
    
    $sortedValues = $dbLines.Values | Sort-Object { 
        $p = $_.Split('|')
        if ($p[0] -eq "GUILD" -or $p[0] -eq "KIOSK") { return "0_" + $p[1] }
        $sortName = if ($p.Length -ge 7) { $p[6] } else { "Z" }
        return "1_" + $sortName + "_" + $p[0]
    }
    
    foreach ($val in $sortedValues) { [void]$finalLines.Add($val) }
    [System.IO.File]::WriteAllLines($DB_FILE, $finalLines.ToArray())
}

$TTC_DOMAIN = if ($AUTO_SRV -eq "1") {"us.tamrieltradecentre.com"} else {"eu.tamrieltradecentre.com"}
$TTC_URL = "https://$TTC_DOMAIN/download/PriceTable"
$SAVED_VAR_DIR = (Get-Item $ADDON_DIR).Parent.FullName + "\SavedVariables"
$TEMP_DIR = "$env:USERPROFILE\Downloads\Windows_Tamriel_Trade_Center_Temp"
$TTC_USER_AGENT = "TamrielTradeCentreClient/1.0.0"
$HM_USER_AGENT = "HarvestMapClient/1.0.0"

while ($true) {
    $CONFIG_CHANGED = $false
    $TEMP_DIR_USED = $false
    $CURRENT_TIME = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    
    $notifTTC = "Up-to-date"
    $notifEH = "Up-to-date"
    $notifHM = "Up-to-date"
    $FOUND_NEW_DATA = $false
    $TEMP_SCAN_FILE = "$TEMP_DIR_ROOT\WTTC_TempScan.log"
    Out-File -FilePath $TEMP_SCAN_FILE -InputObject "" -Encoding UTF8
    Out-File -FilePath $UI_STATE_FILE -InputObject "" -Encoding UTF8

    Log-Event "INFO" "Main loop iteration started. Current time: $CURRENT_TIME"

    if (!$SILENT) {
        Clear-Host
        Write-Host "$ESC[0;92m===========================================================================$ESC[0m"
        Write-Host "$ESC[1m$ESC[0;94m                         $APP_TITLE$ESC[0m"
        Write-Host "$ESC[0;97m         Cross-Platform Auto-Updater for TTC, HarvestMap & ESO-Hub$ESC[0m"
        Write-Host "$ESC[0;90m                            Created by @APHONIC$ESC[0m"
        Write-Host "$ESC[0;92m===========================================================================`n$ESC[0m"
        Write-Host "Target AddOn Directory: $ESC[35m$ADDON_DIR$ESC[0m`n"
    }

    if (!(Test-Path $TEMP_DIR)) { New-Item -ItemType Directory -Force -Path $TEMP_DIR | Out-Null }
    Set-Location $TEMP_DIR

    $ADDON_SETTINGS_FILE = (Get-Item $ADDON_DIR).Parent.FullName + "\AddOnSettings.txt"
    $addonSettingsText = if (Test-Path $ADDON_SETTINGS_FILE) { Get-Content $ADDON_SETTINGS_FILE -Raw } else { "" }

    function Check-Addon-Enabled($addonName) {
        if ($addonSettingsText) { return ($addonSettingsText -match "\b$addonName\b") }
        return (Test-Path "$ADDON_DIR\$addonName")
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
                UIEcho " $ESC[36mDownloading $a_name from ESOUI...$ESC[0m"
                Log-Event "INFO" "Attempting to download missing addon: $a_name"
                
                try {
                    $apiRaw = (& curl.exe -s -m 30 -A "Mozilla/5.0" "https://api.mmoui.com/v3/game/ESO/filedetails/$a_id.json") -join ""
                    $dl_url = if ($apiRaw -match '"downloadurl"\s*:\s*"([^"]+)"') { $matches[1].Replace('\/','/') } else { "https://cdn.esoui.com/downloads/file${a_id}/" }
                    $addon_version = if ($apiRaw -match '"version"\s*:\s*"([^"]+)"') { $matches[1] } else { "" }
                    
                    $zipPath = "$TEMP_DIR_ROOT\${a_name}.zip"
                    & curl.exe -s -f -m 60 -L -A "Mozilla/5.0" -o $zipPath $dl_url
                    
                    if ($LASTEXITCODE -eq 0 -and (Test-Path $zipPath)) {
                        Expand-Archive -Path $zipPath -DestinationPath $global:ADDON_DIR -Force
                        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
                        
                        if ($a_name -eq "TamrielTradeCentre") {
                            Remove-Item "$TEMP_DIR_ROOT\ttc_last_dl.txt" -Force -ErrorAction SilentlyContinue
                            if ($addon_version) { 
                                $global:TTC_NA_VERSION = $addon_version
                                $global:TTC_EU_VERSION = $addon_version
                                $global:CONFIG_CHANGED = $true 
                            }
                        }
                        
                        UIEcho " $ESC[92m[+] $a_name installed successfully.$ESC[0m"
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
                        UIEcho " $ESC[31m[-] Download failed for $a_name.$ESC[0m"
                        Log-Event "ERROR" "Download failed for missing addon: $a_name"
                        return $false
                    }
                } catch {
                    UIEcho " $ESC[31m[-] Error processing $a_name download.$ESC[0m"
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

    if ($global:SKIP_DL_EH -ne "True" -and $global:SKIP_DL_EH -ne $true) {
        if (!(Test-Path "$ADDON_DIR\EsoTradingHub") -or !(Test-Path "$ADDON_DIR\EsoHubScanner")) {
            Write-Host " `n$ESC[33m[?] ESO-Hub Addons are missing. Do you want to download them? (y/N)$ESC[0m"
            $ans = Read-Host "Choice"
            if ([string]::IsNullOrWhiteSpace($ans)) { $ans = "n" }
            if ($ans -match '^[Yy]$') {
                UIEcho " $ESC[36mDownloading ESO-Hub Addons...$ESC[0m"
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
                            UIEcho " $ESC[36mDownloading $fname...$ESC[0m"
                            & curl.exe -s -f -m 30 -L -A "ESOHubClient/1.0.9" -o "$TEMP_DIR_ROOT\${fname}.zip" $dl_url
                            if ($LASTEXITCODE -eq 0) {
                                Expand-Archive -Path "$TEMP_DIR_ROOT\${fname}.zip" -DestinationPath $global:ADDON_DIR -Force
                                Remove-Item "$TEMP_DIR_ROOT\${fname}.zip" -Force
                                
                                UIEcho " $ESC[92m[+] $fname installed successfully.$ESC[0m"
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
                                UIEcho " $ESC[31m[-] Download failed for $fname.$ESC[0m"
                            }
                        }
                    }
                }
            } else {
                UIEcho " $ESC[90mUser Declined download of ESO-Hub Addons. Will not ask again.$ESC[0m"
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
        $DB_DL_URL = "https://cdn.esoui.com/downloads/file4428/"
        
        try {
            try {
                $apiReq = Invoke-WebRequest -Uri "https://api.mmoui.com/v3/game/ESO/filedetails/4428.json" -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
                $DB_API_RESP = $apiReq.Content
            } catch {
                $DB_API_RESP = (& curl.exe -s -m 30 -A "Mozilla/5.0" "https://api.mmoui.com/v3/game/ESO/filedetails/4428.json") -join ""
            }
            if ($DB_API_RESP -match '"(?i)(?:version|uiversion)"\s*:\s*"([^"]+)"') { $SRV_DB_VER = $matches[1] }
            if ($DB_API_RESP -match '"(?i)downloadurl"\s*:\s*"([^"]+)"') { $DB_DL_URL = $matches[1].Replace('\/','/') }
        } catch {}

        $LOC_DB_VER = "0.0.0"
        if (Test-Path $DB_FILE) {
            $firstLine = (Get-Content $DB_FILE -TotalCount 1)
            if ($firstLine -match '([0-9]+\.[0-9]+\.[0-9]+)') { $LOC_DB_VER = $matches[1] }
        }

        $V_COL = if ($SRV_DB_VER -eq $LOC_DB_VER) {"$ESC[92m"} else {"$ESC[31m"}
        UIEcho "`t$ESC[90mServer_DB_Version= ${V_COL}$SRV_DB_VER$ESC[0m"
        UIEcho "`t$ESC[90mLocal_DB_Version=  ${V_COL}$LOC_DB_VER$ESC[0m"

        if ($SRV_DB_VER -ne $LOC_DB_VER -and $SRV_DB_VER -ne "0.0.0") {
            UIEcho " $ESC[36mDownloading latest database template...$ESC[0m"
            Log-Event "INFO" "Downloading database update (v$SRV_DB_VER)"
            
            Start-Process -FilePath "curl.exe" -ArgumentList "-s -A `"Mozilla/5.0`" -o NUL `"https://www.esoui.com/downloads/download4428.zip`"" -WindowStyle Hidden
            
            $dbZipPath = "$TEMP_DIR_ROOT\db.zip"
            try {
                & curl.exe -s -f -m 60 -L -A "Mozilla/5.0" -o $dbZipPath $DB_DL_URL
                if ($LASTEXITCODE -eq 0 -and (Test-Path $dbZipPath)) {
                    Expand-Archive -Path $dbZipPath -DestinationPath "$TEMP_DIR_ROOT\DB_Update" -Force
                    
                    $NEW_DB = Get-ChildItem -Path "$TEMP_DIR_ROOT\DB_Update" -Filter "LTTC_Database.db" -Recurse | Select-Object -First 1
                    $NEW_HIST = Get-ChildItem -Path "$TEMP_DIR_ROOT\DB_Update" -Filter "LTTC_History.db" -Recurse | Select-Object -First 1
                    
                    if ($NEW_DB) {
                        if (!(Test-Path $DB_FILE) -or (Get-Item $DB_FILE).length -eq 0) {
                            Set-Content -Path $DB_FILE -Value "#DATABASE VERSION: $SRV_DB_VER"
                            Add-Content -Path $DB_FILE -Value (Get-Content $NEW_DB.FullName)
                            UIEcho " $ESC[92m[+] Database downloaded and installed!$ESC[0m`n"
                        } else {
                            UIEcho " $ESC[33mMerging new database entries (Preventing Duplicates)...$ESC[0m"
                            $seen = @{}
                            $mergedLines = New-Object System.Collections.ArrayList
                            [void]$mergedLines.Add("#DATABASE VERSION: $SRV_DB_VER")
                            
                            foreach ($file in @($DB_FILE, $NEW_DB.FullName)) {
                                foreach ($line in [System.IO.File]::ReadLines($file)) {
                                    if ($line.StartsWith("#DATABASE VERSION:")) { continue }
                                    $p = $line.Split('|')
                                    $key = if ($p[0] -eq "GUILD") {"GUILD_"+$p[1]} elseif ($p[0] -match '^[0-9]+$') {"ITEM_"+$p[0]} else {$line}
                                    if (!$seen.ContainsKey($key)) {
                                        $seen[$key] = $true
                                        [void]$mergedLines.Add($line)
                                    }
                                }
                            }
                            [System.IO.File]::WriteAllLines($DB_FILE, $mergedLines.ToArray())
                            UIEcho " $ESC[92m[+] Database successfully merged to v$SRV_DB_VER!$ESC[0m`n"
                        }
                        if ($NEW_HIST -and (Test-Path $HIST_FILE)) {
                            $histLines = [System.IO.File]::ReadAllLines($HIST_FILE)
                            if ($histLines.Count -gt 0 -and $histLines[0].StartsWith("#HISTORY VERSION:")) {
                                $histLines[0] = "#HISTORY VERSION: $SRV_DB_VER"
                                [System.IO.File]::WriteAllLines($HIST_FILE, $histLines)
                            }
                        }
                    }
                    Remove-Item -Path "$TEMP_DIR_ROOT\DB_Update" -Recurse -Force
                } else {
                    UIEcho " $ESC[31m[-] Database download failed (Timeout or Blocked).$ESC[0m`n"
                }
            } catch { UIEcho " $ESC[31m[-] Database download process failed.$ESC[0m`n" }
        } else {
            UIEcho " $ESC[90mNo changes detected. $ESC[92mLocal database is up-to-date. $ESC[35mSkipping download.$ESC[0m`n"
        }
    }

    if (!$HAS_TTC) {
        UIEcho "$ESC[1m$ESC[97m [1/4] & [2/4] Updating TTC Data (SKIPPED)$ESC[0m"
        UIEcho " $ESC[31m[-] TamrielTradeCentre is not installed. $ESC[35mSkipping.$ESC[0m`n"
        $notifTTC = "Not Installed"
    } else {
        UIEcho "$ESC[1m$ESC[97m [1/4] Uploading your Local TTC Data to TTC Server $ESC[0m"
        
        $TTC_CHANGED = $true
        if (Test-Path "$SAVED_VAR_DIR\TamrielTradeCentre.lua") {
            if (Test-Path "$SNAP_DIR\lttc_ttc_snapshot.lua") {
                $h1 = (Get-FileHash "$SAVED_VAR_DIR\TamrielTradeCentre.lua" -Algorithm MD5).Hash
                $h2 = (Get-FileHash "$SNAP_DIR\lttc_ttc_snapshot.lua" -Algorithm MD5).Hash
                if ($h1 -eq $h2) { $TTC_CHANGED = $false }
            }

            if (!$TTC_CHANGED) {
                UIEcho " $ESC[90mNo changes detected in TamrielTradeCentre.lua. $ESC[35mSkipping upload.$ESC[0m`n"
            } else {
                Log-Event "INFO" "Changes detected in TTC data. Beginning extraction."
                if ($global:ENABLE_DISPLAY -and !$SILENT) {
                    UIEcho " $ESC[36mExtracting new local listings & sales data from TTC...$ESC[0m"
                    "$ESC[0;35m--- TTC Extracted Data ---$ESC[0m" | Out-File -FilePath $TEMP_SCAN_FILE -Append -Encoding UTF8
                    
                    $max_time = [long]$TTC_LAST_SALE; $count = 0
                    
                    $dbName = @{}; $dbQual = @{}; $dbCols = @{}; $dbGuildId = @{}
                    if (Test-Path $DB_FILE) {
                        foreach ($line in [System.IO.File]::ReadLines($DB_FILE)) {
                            $p = $line.Split('|')
                            if ($p[0] -eq "GUILD") { $dbGuildId[$p[1]] = $p[2] }
                            elseif ($p[0] -match '^[0-9]+$') {
                                $dbCols[$p[0]] = $p.Length; $dbQual[$p[0]] = $p[1]
                                $dbName[$p[0]] = if ($p.Length -ge 6) {$p[5]} else {$p[2]}
                            }
                        }
                    }

                    $path = @{}; $guildKiosks = @{}
                    $inItem = $false; $itemLvl = 0; $action = "Listed"; $guild = ""; $player = ""; $seller = ""; $buyer = ""; $ttcId = ""
                    $amt = "1"; $stime = ""; $price = ""; $itemid = ""; $subtype = "1"; $internalLevel = "1"; $realName = ""
                    
                    $dbUpdates = New-Object System.Collections.ArrayList
                    $histLines = New-Object System.Collections.ArrayList
                    
                    foreach ($line in [System.IO.File]::ReadLines("$SAVED_VAR_DIR\TamrielTradeCentre.lua")) {
                        $lineTrim = $line.TrimStart()
                        if ($lineTrim -match '^\["?([^"]+)"?\]\s*=') {
                            $lvl = $line.Length - $lineTrim.Length
                            $key = $matches[1]
                            
                            $keysToRemove = @()
                            foreach ($k in $path.Keys) { if ([int]$k -ge $lvl) { $keysToRemove += $k } }
                            foreach ($k in $keysToRemove) { $path.Remove($k) }
                            $path[$lvl] = $key
                            
                            if ($key -eq "KioskLocationID") {
                                $sortedKeys = $path.Keys | Sort-Object { [int]$_ }
                                $gname = ""
                                for ($i = 0; $i -lt $sortedKeys.Count; $i++) {
                                    if ($path[$sortedKeys[$i]] -eq "Guilds" -and ($i + 1) -lt $sortedKeys.Count) { $gname = $path[$sortedKeys[$i+1]] }
                                }
                                if ($gname -and $line -match '([0-9]+)') { $guildKiosks[$gname] = $matches[1] }
                            }
                            
                            if ($key -match '^[0-9]+$' -and !$inItem) {
                                $inItem = $true; $itemLvl = $lvl
                                $sortedKeys = $path.Keys | Sort-Object { [int]$_ }
                                $action = "Listed"; $guild = ""; $player = ""; $seller = ""; $buyer = ""; $ttcId = ""
                                
                                for ($i = 0; $i -lt $sortedKeys.Count; $i++) {
                                    $k = $path[$sortedKeys[$i]]
                                    if ($k -eq "SaleHistoryEntries") { $action = "Sold" }
                                    if ($k -eq "AutoRecordEntries" -or $k -eq "Entries") { $action = "Listed" }
                                    if ($k -eq "Guilds" -and ($i + 1) -lt $sortedKeys.Count) { $guild = $path[$sortedKeys[$i+1]] }
                                    if ($k -eq "PlayerListings" -and ($i + 1) -lt $sortedKeys.Count) { $player = $path[$sortedKeys[$i+1]] }
                                }
                            }
                        }
                        
                        if ($inItem) {
                            if ($lineTrim -match '\["Amount"\]\s*=\s*([0-9]+)') { $amt = $matches[1] }
                            if ($lineTrim -match '\["SaleTime"\]\s*=\s*([0-9]+)') { $stime = $matches[1] }
                            if ($lineTrim -match '\["Timestamp"\]\s*=\s*([0-9]+)' -and !$stime) { $stime = $matches[1] }
                            if ($lineTrim -match '\["TimeStamp"\]\s*=\s*([0-9]+)' -and !$stime) { $stime = $matches[1] }
                            if ($lineTrim -match '\["TotalPrice"\]\s*=\s*([0-9]+)') { $price = $matches[1] }
                            if ($lineTrim -match '\["Price"\]\s*=\s*([0-9]+)' -and $lineTrim -notmatch 'TotalPrice' -and !$price) { $price = $matches[1] }
                            if ($lineTrim -match '\["Buyer"\]\s*=\s*"((?:\\"|[^"])*)"') { $buyer = $matches[1] -replace '\\"', '"' }
                            if ($lineTrim -match '\["Seller"\]\s*=\s*"((?:\\"|[^"])*)"') { $seller = $matches[1] -replace '\\"', '"' }
                            if ($lineTrim -match '\|H[0-9a-fA-F]*:item:([0-9]+):([0-9]+):([0-9]+)') {
                                $itemid = $matches[1]; $subtype = $matches[2]; $internalLevel = $matches[3]
                            }
                            if ($lineTrim -match '\["Name"\]\s*=\s*"((?:\\"|[^"])*)"') { $realName = $matches[1] -replace '\\"', '"' }
                            
                            if ($lineTrim -match '^\},?') {
                                if (($line.Length - $lineTrim.Length) -le $itemLvl) {
                                    $inItem = $false
                                    $stimeNum = if ($stime) { [long]$stime } else { 0 }
                                    if ($stimeNum -gt $max_time) { $max_time = $stimeNum }
                                    
                                    if ($stimeNum -gt [long]$TTC_LAST_SALE -or [long]$TTC_LAST_SALE -eq 0 -or $action -eq "Listed") {
                                        if (!$amt) { $amt = "1" }
                                        if (!$realName -or $realName -match '^\|[0-9]+\|$') {
                                            if ($dbName.ContainsKey($itemid) -and $dbName[$itemid] -notmatch '^Unknown Item') { $realName = $dbName[$itemid] }
                                            else { $realName = "Unknown Item ($itemid)" }
                                        }
                                        
                                        if ($price) {
                                            $s = [int]$subtype; $v = [int]$internalLevel; $needsUpdate = $false
                                            
                                            if ($dbName.ContainsKey($itemid)) {
                                                if ($realName -ne $dbName[$itemid] -and $realName -notmatch '^Unknown Item') { $needsUpdate = $true }
                                                if ($dbCols[$itemid] -lt 7) { $needsUpdate = $true }
                                            } else { $needsUpdate = $true }
                                            
                                            if ($dbQual.ContainsKey($itemid)) { $realQual = [int]$dbQual[$itemid] }
                                            else { $realQual = Calc-Quality $itemid $realName $s $v }
                                            
                                            if ($realName.StartsWith("Unknown Item (")) { $needsUpdate = $false }
                                            if ($needsUpdate) {
                                                $hq = Get-HQ $realQual; $cat = Get-Cat $realName $itemid $s $v
                                                [void]$dbUpdates.Add("DB_UPDATE|$itemid|$realQual|$s|$v|$hq|$realName|$cat")
                                                $dbName[$itemid] = $realName; $dbQual[$itemid] = $realQual; $dbCols[$itemid] = 7
                                            }
                                            
                                            $q_num = $realQual; $c = "$ESC[0m"
                                            if($q_num -eq 0) { $c = "$ESC[90m" } elseif($q_num -eq 1) { $c = "$ESC[97m" } elseif($q_num -eq 2) { $c = "$ESC[32m" }
                                            elseif($q_num -eq 3) { $c = "$ESC[36m" } elseif($q_num -eq 4) { $c = "$ESC[35m" } elseif($q_num -eq 5) { $c = "$ESC[33m" }
                                            elseif($q_num -eq 6) { $c = "$ESC[38;5;214m" }
                                            
                                            $guildStr = ""
                                            if ($guild -and $guild -ne "Unknown Guild" -and $guild -ne "Guilds") {
                                                $gDisplay = "$ESC[35m$guild$ESC[0m"
                                                if ($dbGuildId.ContainsKey($guild)) { $gDisplay = "$ESC[35m$ESC]8;;|H1:guild:$($dbGuildId[$guild])|h$guild|h$ESC\$guild$ESC]8;;$ESC\$ESC[0m" }
                                                
                                                $kiosk = $guildKiosks[$guild]
                                                $kStr = ""
                                                if ($kiosk -and $kiosk -ne "0") {
                                                    if ($global:k_dict.ContainsKey($kiosk)) {
                                                        $kp = $global:k_dict[$kiosk].Split('|')
                                                        $disp = $kp[0]; $mId = $kp[1]; $p = $kp[2]
                                                        if ($mId -and $p) { $kStr = " $ESC[90m($ESC]8;;https://eso-hub.com/en/interactive-map?map=$mId&ping=$p$ESC\$disp$ESC]8;;$ESC\)$ESC[0m" }
                                                        elseif ($mId) { $kStr = " $ESC[90m($ESC]8;;https://eso-hub.com/en/interactive-map?map=$mId$ESC\$disp$ESC]8;;$ESC\)$ESC[0m" }
                                                        elseif ($p) { $kStr = " $ESC[90m($ESC]8;;https://eso-hub.com/en/interactive-map?ping=$p$ESC\$disp$ESC]8;;$ESC\)$ESC[0m" }
                                                        else { $kStr = " $ESC[90m($disp)$ESC[0m" }
                                                    } else { $kStr = " $ESC[90m(Kiosk ID: $kiosk)$ESC[0m" }
                                                } else { $kStr = " $ESC[90m(Local Trader)$ESC[0m" }
                                                $guildStr = " in $gDisplay$kStr"
                                            }
                                            
                                            $playerStrClean = $player
                                            if ($playerStrClean -and $playerStrClean -notmatch '^@') { $playerStrClean = "@$playerStrClean" }
                                            if ($buyer -and $buyer -notmatch '^@') { $buyer = "@$buyer" }
                                            if ($seller -and $seller -notmatch '^@') { $seller = "@$seller" }
                                            if (!$seller -and $playerStrClean) { $seller = $playerStrClean }
                                            
                                            $tradeStr = ""
                                            if ($seller -and $buyer) { $tradeStr = " by $ESC[36m$seller$ESC[0m to $ESC[36m$buyer$ESC[0m" }
                                            elseif ($seller) { $tradeStr = " by $ESC[36m$seller$ESC[0m" }
                                            elseif ($buyer) { $tradeStr = " to $ESC[36m$buyer$ESC[0m" }
                                            elseif ($playerStrClean -and $playerStrClean -ne $guild) { $tradeStr = " by $ESC[36m$playerStrClean$ESC[0m" }
                                            
                                            $age = $CURRENT_TIME - $stimeNum
                                            $statusTag = ""
                                            if ($action -eq "Sold") { $statusTag = " $ESC[38;5;214m[SOLD]$ESC[0m" }
                                            elseif ($action -eq "Listed") {
                                                if ($stimeNum -gt 0 -and $age -gt 2592000) { $statusTag = " $ESC[90m[EXPIRED]$ESC[0m" }
                                                else { $statusTag = " $ESC[34m[AVAILABLE]$ESC[0m" }
                                            }
                                            
                                            $name_enc = [uri]::EscapeDataString($realName).Replace("%20", "+").Replace("'", "%27")
                                            $link_start = "$ESC]8;;https://us.tamrieltradecentre.com/pc/Trade/SearchResult?SearchType=Sell&ItemNamePattern=$name_enc$ESC\"
                                            $link_end = "$ESC]8;;$ESC\"
                                            
                                            $tsStr = if ($stimeNum -gt 0) {"[TS:$stimeNum]"} else {"[$ESC[90mListing$ESC[0m]"}
                                            $uiLine = " $tsStr $ESC[36m$action$ESC[0m for $ESC[32m$price$ESC[33mgold$ESC[0m - $ESC[32m${amt}x$ESC[0m ${link_start}$c$realName$ESC[0m${link_end}$tradeStr$guildStr$statusTag"
                                            UIEcho $uiLine
                                            $uiLine | Out-File -FilePath $TEMP_SCAN_FILE -Append -Encoding UTF8
                                            $FOUND_NEW_DATA = $true
                                            
                                            if ($guild -ne "Guilds" -and $guild -ne "Unknown Guild" -and $guild -ne "") {
                                                [void]$histLines.Add("HISTORY|$stimeNum|$action|$price|$amt|$itemid|$realName|$buyer|$seller|$guild|$kiosk|$c|TTC|1")
                                            } elseif ($action -eq "Listed" -and $seller -ne "") {
                                                [void]$histLines.Add("HISTORY|$stimeNum|$action|$price|$amt|$itemid|$realName|$buyer|$seller||$kiosk|$c|TTC|1")
                                            }
                                            $count++
                                        }
                                    }
                                    $amt = "1"; $stime = ""; $price = ""; $buyer = ""; $seller = ""; $itemid = ""; $subtype = "1"; $internalLevel = "1"; $realName = ""
                                }
                            }
                        }
                    }
                    
                    if ($count -eq 0) { UIEcho " $ESC[90mNo new TTC items found. Upload skipped.$ESC[0m" }
                    else { UIEcho " $ESC[92m[+]$ESC[0m Extraction complete!" }
                    
                    if ($histLines.Count -gt 0) { $histLines.ToArray() | Out-File -FilePath $HIST_FILE -Append -Encoding UTF8 }
                    Apply-DB-Updates $dbUpdates.ToArray()
                    
                    if ($max_time -gt [long]$TTC_LAST_SALE) { $global:TTC_LAST_SALE = $max_time; $CONFIG_CHANGED = $true }
                } else {
                    UIEcho " $ESC[90mExtraction disabled by user. Proceeding instantly to upload...$ESC[0m"
                }

                if ($global:ENABLE_LOCAL_MODE) {
                    UIEcho "`n $ESC[90m[Local Mode] Skipping TTC Upload. Data extracted to local DB only.$ESC[0m`n"
                    Copy-Item -Path "$SAVED_VAR_DIR\TamrielTradeCentre.lua" -Destination "$SNAP_DIR\lttc_ttc_snapshot.lua" -Force
                } elseif ($count -eq 0 -and $global:ENABLE_DISPLAY) {
                    Copy-Item -Path "$SAVED_VAR_DIR\TamrielTradeCentre.lua" -Destination "$SNAP_DIR\lttc_ttc_snapshot.lua" -Force
                } else {
                    UIEcho "`n $ESC[36mUploading to:$ESC[0m https://$TTC_DOMAIN/pc/Trade/WebClient/Upload"
                    curl.exe -s -A "$TTC_USER_AGENT" -H "Accept: text/html" -F "SavedVarFileInput=@$SAVED_VAR_DIR\TamrielTradeCentre.lua" "https://$TTC_DOMAIN/pc/Trade/WebClient/Upload" | Out-Null
                    $notifTTC = "Data Uploaded"
                    UIEcho " $ESC[92m[+] Upload finished.$ESC[0m`n"
                    Copy-Item -Path "$SAVED_VAR_DIR\TamrielTradeCentre.lua" -Destination "$SNAP_DIR\lttc_ttc_snapshot.lua" -Force
                }
            }
        } else {
            UIEcho " $ESC[33m[-] No TamrielTradeCentre.lua found. $ESC[35mSkipping upload.$ESC[0m`n"
        }

        UIEcho "$ESC[1m$ESC[97m [2/4] Updating your Local TTC Data $ESC[0m"
        UIEcho " $ESC[33mChecking TTC APIs for price table versions...$ESC[0m"
        
        $global:TTC_LAST_CHECK = $CURRENT_TIME; $CONFIG_CHANGED = $true
        
        $srv_list = @()
        if ($AUTO_SRV -eq "1" -or $AUTO_SRV -eq "3") { $srv_list += "NA" }
        if ($AUTO_SRV -eq "2" -or $AUTO_SRV -eq "3") { $srv_list += "EU" }

        $needs_dl = $false
        $dl_na = $false; $dl_eu = $false
        $s_ver_na = "0"; $s_ver_eu = "0"
        
        foreach ($srv in $srv_list) {
            $api_domain = if ($srv -eq "EU") {"eu.tamrieltradecentre.com"} else {"us.tamrieltradecentre.com"}
            
            try { 
                $API_RESP = Invoke-RestMethod -Uri "https://$api_domain/api/GetTradeClientVersion" `
                    -UserAgent $TTC_USER_AGENT
                $s_ver = $API_RESP.PriceTableVersion 
            } catch { $s_ver = "0" }

            if (!$s_ver) { $s_ver = "0" }
            
            if ($srv -eq "NA") { $s_ver_na = $s_ver; $loc_ver = $TTC_NA_VERSION } 
            else { $s_ver_eu = $s_ver; $loc_ver = $TTC_EU_VERSION }
            
            $pt_file = "$ADDON_DIR\TamrielTradeCentre\PriceTable${srv}.lua"
            if ($loc_ver -eq "0" -and (Test-Path $pt_file)) {
                $head = Get-Content $pt_file -TotalCount 5
                foreach ($l in $head) { 
                    if ($l -match '^--Version[ \t]*=[ \t]*([0-9]+)') { $loc_ver = $matches[1]; break } 
                }
            }

            $loc_disp = if ($loc_ver -eq "0") {"None"} else {$loc_ver}
            $s_ver_disp = if ($s_ver -eq "0") {"Error"} else {$s_ver}
            $v_col = if ([int]$s_ver -eq [int]$loc_ver) {"$ESC[92m"} else {"$ESC[31m"}

            UIEcho " `t$ESC[90mServer Version ($srv): ${v_col}$s_ver_disp$ESC[0m"
            UIEcho " `t$ESC[90mLocal Version ($srv):  ${v_col}$loc_disp$ESC[0m"

            if ([int]$s_ver -gt 0 -and [int]$s_ver -gt [int]$loc_ver) {
                $needs_dl = $true
                if ($srv -eq "NA") { $dl_na = $true }
                if ($srv -eq "EU") { $dl_eu = $true }
            }
        }

        if ($needs_dl) {
            UIEcho " $ESC[92mNew TTC Price Table available $ESC[0m"
            $ttc_diff = $CURRENT_TIME - [int]$TTC_LAST_DOWNLOAD
            
            if ($global:ENABLE_LOCAL_MODE) { 
                UIEcho " $ESC[90m[Local Mode] Download Skipped.$ESC[0m`n" 
            } elseif ($ttc_diff -lt 3600 -and $ttc_diff -ge 0) {
                $wait_mins = [math]::Floor((3600 - $ttc_diff) / 60)
                UIEcho " $ESC[33mbut download is on cooldown. Please wait $wait_mins mins. $ESC[35mSkipped.$ESC[0m`n"
            } else {
                $success_all = $true
                $TEMP_DIR_USED = $true
                $rate_limit = $false

                foreach ($srv in $srv_list) {
                    if ($srv -eq "NA" -and !$dl_na) { continue }
                    if ($srv -eq "EU" -and !$dl_eu) { continue }

                    $dl_prefix = if ($srv -eq "EU") {"eu"} else {"us"}
                    $dl_url = "https://${dl_prefix}.tamrieltradecentre.com/download/PriceTable"
                    
                    UIEcho " $ESC[36mDownloading TTC Price Table ($srv)...$ESC[0m"
                    $zipPath = "$TEMP_DIR\TTC-data-${srv}.zip"
                    & curl.exe -f -A "$TTC_USER_AGENT" -# -L -o $zipPath "$dl_url"
                    
                    if ($LASTEXITCODE -eq 22) {
                        $rate_limit = $true
                        UIEcho "`n $ESC[33m[!] TTC Rate Limit (429) reached for $srv. Waiting.$ESC[0m`n"
                        $success_all = $false
                        break
                    } elseif ($LASTEXITCODE -eq 0 -and (Test-Path $zipPath)) {
                        Expand-Archive -Path $zipPath -DestinationPath "$TEMP_DIR\TTC_Extracted_${srv}" -Force
                        UIEcho " $ESC[92m[+] TTC Updated ($srv)$ESC[0m"
                    } else {
                        UIEcho " $ESC[31m[!] Error: TTC Data download failed for $srv.$ESC[0m"
                        $success_all = $false
                    }
                }

                $has_na = Test-Path "$TEMP_DIR\TTC_Extracted_NA"
                $has_eu = Test-Path "$TEMP_DIR\TTC_Extracted_EU"

                if ($success_all -or $has_na -or $has_eu) {
                    $ttc_dir = "$ADDON_DIR\TamrielTradeCentre"
                    if (!(Test-Path $ttc_dir)) { New-Item -ItemType Directory -Force -Path $ttc_dir | Out-Null }
                    
                    if ($has_na) {
                        Copy-Item -Path "$TEMP_DIR\TTC_Extracted_NA\*" -Destination "$ttc_dir\" -Recurse -Force
                        $global:TTC_NA_VERSION = $s_ver_na
                    }
                    if ($has_eu) {
                        Copy-Item -Path "$TEMP_DIR\TTC_Extracted_EU\*" -Destination "$ttc_dir\" -Recurse -Force
                        $global:TTC_EU_VERSION = $s_ver_eu
                    }

                    $global:TTC_LAST_DOWNLOAD = $CURRENT_TIME
                    $global:CONFIG_CHANGED = $true
                    UIEcho "`n $ESC[92m[+] TTC Data Successfully Updated.$ESC[0m`n"
                }
            }
        } else {
            if ([int]$s_ver_na -gt 0 -and [int]$s_ver_na -ge [int]$TTC_NA_VERSION) { 
                $global:TTC_NA_VERSION = $s_ver_na; $CONFIG_CHANGED = $true 
            }
            if ([int]$s_ver_eu -gt 0 -and [int]$s_ver_eu -ge [int]$TTC_EU_VERSION) { 
                $global:TTC_EU_VERSION = $s_ver_eu; $CONFIG_CHANGED = $true 
            }
            UIEcho "`n $ESC[90mNo changes detected. $ESC[92mLocal PriceTables are up-to-date.$ESC[0m`n"
        }
    }

    UIEcho "`n$ESC[1m$ESC[97m [3/4] Updating ESO-Hub Prices & Uploading Scans $ESC[0m"
    UIEcho " $ESC[36mFetching latest ESO-Hub version data...$ESC[0m"
    
    $global:EH_LAST_CHECK = $CURRENT_TIME; $CONFIG_CHANGED = $true
    $ehUploadCount = 0; $ehUpdateCount = 0

    $EH_JSON_FILE = "$TEMP_DIR\esohub_temp.json"
    if (Test-Path $EH_JSON_FILE) { Remove-Item $EH_JSON_FILE -Force }
    cmd /c "curl.exe -s -X POST -H `"User-Agent: ESOHubClient/1.0.9`" -d `"user_token=&client_system=windows&client_version=1.0.9&lang=en`" `"https://data.eso-hub.com/v1/api/get-addon-versions`" -o `"$EH_JSON_FILE`""
    
    $addonBlocks = @()
    if (Test-Path $EH_JSON_FILE) {
        $jsonStr = Get-Content $EH_JSON_FILE -Raw
        $jsonStr = $jsonStr.Replace('{"folder_name"', "`n{`"folder_name`"")
        $lines = $jsonStr -split "`n"
        foreach ($line in $lines) { if ($line -match '"folder_name"') { $addonBlocks += $line } }
    }
    
    if ($addonBlocks.Count -eq 0) {
        UIEcho " $ESC[31m[-] Could not fetch ESO-Hub data.$ESC[0m`n"
    } else {
        $EH_TIME_DIFF = $CURRENT_TIME - [int]$EH_LAST_DOWNLOAD
        $EH_DOWNLOAD_OCCURRED = $false

        foreach ($line in $addonBlocks) {
            $FNAME = ""; $SV_NAME = ""; $UP_EP = ""; $DL_URL = ""; $SRV_VER = ""
            if ($line -match '"folder_name"\s*:\s*"([^"]+)"') { $FNAME = $matches[1] }
            if ($line -match '"sv_file_name"\s*:\s*"([^"]+)"') { $SV_NAME = $matches[1] }
            if ($line -match '"endpoint"\s*:\s*"([^"]+)"') { $UP_EP = $matches[1].Replace('\/','/') }
            if ($line -match '"file"\s*:\s*"([^"]+)"') { $DL_URL = $matches[1].Replace('\/','/') }
            if ($line -match '"version"\s*:\s*\{[^}]*"string"\s*:\s*"([^"]+)"') { $SRV_VER = $matches[1] } elseif ($line -match '"version"\s*:\s*"([^"]+)"') { $SRV_VER = $matches[1] }

            if (!$FNAME) { continue }

            $HAS_THIS_EH = Check-Addon-Enabled $FNAME
            if (!$HAS_THIS_EH) { UIEcho " $ESC[31m[-] $FNAME is not installed. $ESC[35mSkipping.$ESC[0m"; continue }
            
            $ID_NUM = if ($DL_URL -match '(\d+)$') { $matches[1] } else { "0" }
            if (!$SRV_VER) { $SRV_VER = "0" }
            
            $PREFIX = switch ($FNAME) { "EsoTradingHub" { "ETH5" }; "LibEsoHubPrices" { "LEHP7" }; "EsoHubScanner" { "EHS" }; default { $FNAME } }

            $VAR_LOC_NAME = "EH_LOC_$ID_NUM"
            $LOC_VER = Get-Variable -Name $VAR_LOC_NAME -ValueOnly -ErrorAction SilentlyContinue
            if (!$LOC_VER) { $LOC_VER = "0" }

            $V_COL = if ($SRV_VER -eq $LOC_VER) {"$ESC[92m"} else {"$ESC[31m"}

            if (!$SILENT) {
                Write-Host " $ESC[33mChecking server for $FNAME.zip...$ESC[0m"
                Write-Host "`t$ESC[90m${PREFIX}_Server_Version= ${V_COL}$SRV_VER$ESC[0m"
                Write-Host "`t$ESC[90m${PREFIX}_Local_Version= ${V_COL}$LOC_VER$ESC[0m"
            }

            if ($SV_NAME -and $UP_EP -and (Test-Path "$SAVED_VAR_DIR\$SV_NAME")) {
                $UP_SNAP = "$SNAP_DIR\lttc_eh_$($SV_NAME.ToLower().Replace('.lua',''))_snapshot.lua"
                $EH_LOCAL_CHANGED = $true
                if (Test-Path $UP_SNAP) {
                    $h1 = (Get-FileHash "$SAVED_VAR_DIR\$SV_NAME" -Algorithm MD5).Hash
                    $h2 = (Get-FileHash $UP_SNAP -Algorithm MD5).Hash
                    if ($h1 -eq $h2) { $EH_LOCAL_CHANGED = $false }
                }

                if (!$EH_LOCAL_CHANGED) {
                    UIEcho " $ESC[90mNo changes detected in $SV_NAME. $ESC[35mSkipping upload.$ESC[0m"
                } else {
                    if ($SV_NAME -eq "EsoTradingHub.lua" -and $global:ENABLE_DISPLAY -and !$SILENT) {
                        UIEcho " $ESC[36mExtracting new sales & scan data from EsoTradingHub...$ESC[0m"
                        "$ESC[0;35m--- ESO-Hub Extracted Data ---$ESC[0m" | Out-File -FilePath $TEMP_SCAN_FILE -Append -Encoding UTF8

                        $max_time = [long]$EH_LAST_SALE; $count = 0
                        $inTraderData = $false; $inGuildData = $false; $currentTrader = ""; $currentGuildId = ""; $bufferedGname = ""; $scanType = ""
                        $traderMaps = @{}; $guildKiosks = @{}; $guildMaps = @{}; $guildNames = @{}
                        $dbGuildName = @{}; $dbUpdates = New-Object System.Collections.ArrayList; $histLines = New-Object System.Collections.ArrayList
                        
                        if (Test-Path $DB_FILE) {
                            foreach ($line in [System.IO.File]::ReadLines($DB_FILE)) {
                                $p = $line.Split('|')
                                if ($p[0] -eq "GUILD") { $dbGuildName[$p[2]] = $p[1] }
                            }
                        }

                        foreach ($line in [System.IO.File]::ReadLines("$SAVED_VAR_DIR\$SV_NAME")) {
                            if ($line -match '\["traderData"\]') { $inTraderData = $true; $inGuildData = $false }
                            if ($line -match '\["guildData"\]') { $inGuildData = $true; $inTraderData = $false }
                            
                            if ($inTraderData -and $line -match '^\s*\["([^"]+)"\]\s*=\s*$') {
                                $val = $matches[1]
                                if ($val -notmatch 'Megaserver|PTS|guildHistory') { $currentTrader = $val }
                            }
                            if ($inTraderData -and $line -match '\["mapId"\]\s*=\s*([0-9]+)') {
                                if ($currentTrader) { $traderMaps[$currentTrader] = $matches[1] }
                            }
                            if ($inTraderData -and $line -match '^\s*\[([0-9]+)\]\s*=\s*[0-9]+') {
                                $gid = $matches[1]
                                if ($currentTrader) {
                                    $guildKiosks[$gid] = $currentTrader
                                    if ($traderMaps.ContainsKey($currentTrader)) { $guildMaps[$gid] = $traderMaps[$currentTrader] }
                                }
                            }
                            
                            if ($inGuildData -and $line -match '^\s*\[([0-9]+)\]\s*=\s*$') { $currentGuildId = $matches[1]; $bufferedGname = ""; $scanType = "" }
                            if ($inGuildData -and $line -match '\["guildId"\]\s*=\s*([0-9]+)') {
                                $currentGuildId = $matches[1]
                                if ($bufferedGname) { $guildNames[$currentGuildId] = $bufferedGname; [void]$dbUpdates.Add("DB_GUILD|$bufferedGname|$currentGuildId"); $bufferedGname = "" }
                            }
                            if ($inGuildData -and $line -match '\["(traderGuildName|guildName)"\]\s*=\s*"((?:\\"|[^"])*)"') {
                                $val = $matches[2] -replace '\\"', '"'
                                if ($currentGuildId) { $guildNames[$currentGuildId] = $val; [void]$dbUpdates.Add("DB_GUILD|$val|$currentGuildId") }
                                else { $bufferedGname = $val }
                            }
                            if ($line -match '\["(scannedSales|scannedItems|cancelledItems|purchasedItems|traderHistory)"\]') {
                                $stype = $matches[1]
                                if ($stype -eq "scannedSales") { $scanType = "Sold" }
                                elseif ($stype -eq "scannedItems") { $scanType = "Listed" }
                                elseif ($stype -eq "cancelledItems") { $scanType = "Cancelled" }
                                elseif ($stype -eq "purchasedItems") { $scanType = "Purchased" }
                            }
                            
                            if ($line.IndexOf(":item:") -gt 0 -and $scanType) {
                                $sIdx = $line.IndexOf('"|H')
                                if ($sIdx -gt 0) {
                                    $tStr = $line.Substring($sIdx + 1)
                                    $eIdx = $tStr.IndexOf('",')
                                    if ($eIdx -eq -1) { $eIdx = $tStr.IndexOf('"') }
                                    if ($eIdx -gt 0) {
                                        $fullVal = $tStr.Substring(0, $eIdx)
                                        $splitIdx = $fullVal.IndexOf('|h|h,')
                                        $offset = 5
                                        if ($splitIdx -eq -1) { $splitIdx = $fullVal.IndexOf('|h,'); $offset = 3 }
                                        
                                        if ($splitIdx -gt 0) {
                                            $itemLink = $fullVal.Substring(0, $splitIdx + 1)
                                            $dataCsv = $fullVal.Substring($splitIdx + $offset)
                                            
                                            $lp = $itemLink.Split(':')
                                            $itemid = $lp[2]; $subtype = $lp[3]; $internalLevel = $lp[4]
                                            $s = [int]$subtype; $v = [int]$internalLevel
                                            
                                            $arr = $dataCsv.Split(',')
                                            $price = $arr[0]; $qty = $arr[1]; $buyer = ""; $seller = ""; $stime = 0
                                            if (!$qty) { $qty = "1" }
                                            
                                            if ($arr.Length -ge 5) { $buyer = $arr[2]; $seller = $arr[3]; $stime = [long]$arr[4] }
                                            else { $seller = $arr[2]; $stime = [long]$arr[3] }
                                            
                                            if ($buyer -and $buyer -notmatch '^@') { $buyer = "@$buyer" }
                                            if ($seller -and $seller -notmatch '^@') { $seller = "@$seller" }
                                            
                                            if ($dbName.ContainsKey($itemid) -and $dbName[$itemid] -notmatch '^Unknown Item') { $realName = $dbName[$itemid] }
                                            else { $realName = "Unknown Item ($itemid)" }
                                            
                                            if ($dbQual.ContainsKey($itemid)) { $realQual = [int]$dbQual[$itemid] }
                                            else { $realQual = Calc-Quality $itemid $realName $s $v }
                                            
                                            if ($realName -notmatch '^Unknown Item \(' -and (!$dbName.ContainsKey($itemid) -or $dbName[$itemid] -ne $realName)) {
                                                $hq = Get-HQ $realQual; $cat = Get-Cat $realName $itemid $s $v
                                                [void]$dbUpdates.Add("DB_UPDATE|$itemid|$realQual|$s|$v|$hq|$realName|$cat")
                                                $dbName[$itemid] = $realName; $dbQual[$itemid] = $realQual
                                            }
                                            
                                            if ($realName -and $price) {
                                                if ($stime -gt $max_time) { $max_time = $stime }
                                                if ($stime -gt [long]$EH_LAST_SALE -or $stime -eq 0 -or $scanType -eq "Listed") {
                                                    $q_num = $realQual; $c = "$ESC[0m"
                                                    if($q_num -eq 0) { $c = "$ESC[90m" } elseif($q_num -eq 1) { $c = "$ESC[97m" } elseif($q_num -eq 2) { $c = "$ESC[32m" }
                                                    elseif($q_num -eq 3) { $c = "$ESC[36m" } elseif($q_num -eq 4) { $c = "$ESC[35m" } elseif($q_num -eq 5) { $c = "$ESC[33m" }
                                                    elseif($q_num -eq 6) { $c = "$ESC[38;5;214m" }
                                                    
                                                    $tradeStr = ""
                                                    if ($seller -and $buyer) { $tradeStr = " by $ESC[36m$seller$ESC[0m to $ESC[36m$buyer$ESC[0m" }
                                                    elseif ($seller) { $tradeStr = " by $ESC[36m$seller$ESC[0m" }
                                                    elseif ($buyer) { $tradeStr = " to $ESC[36m$buyer$ESC[0m" }
                                                    
                                                    $gname = if ($guildNames.ContainsKey($currentGuildId)) { $guildNames[$currentGuildId] } else { $dbGuildName[$currentGuildId] }
                                                    if (!$gname) { $gname = "Unknown Guild" }
                                                    
                                                    $gDisplay = "$ESC[35m$gname$ESC[0m"
                                                    if ($currentGuildId) { $gDisplay = "$ESC[35m$ESC]8;;|H1:guild:$currentGuildId|h$gname|h$ESC\$gname$ESC]8;;$ESC\$ESC[0m" }
                                                    
                                                    $kiosk = if ($guildKiosks.ContainsKey($currentGuildId)) { $guildKiosks[$currentGuildId] } else { "" }
                                                    $kStr = ""
                                                    if ($kiosk) {
                                                        if ($global:k_dict.ContainsKey($kiosk)) {
                                                            $kp = $global:k_dict[$kiosk].Split('|')
                                                            $disp = $kp[0]; $mId = $kp[1]; $p = $kp[2]
                                                            if ($mId -and $p) { $kStr = " $ESC[90m($ESC]8;;https://eso-hub.com/en/interactive-map?map=$mId&ping=$p$ESC\$disp$ESC]8;;$ESC\)$ESC[0m" }
                                                            elseif ($mId) { $kStr = " $ESC[90m($ESC]8;;https://eso-hub.com/en/interactive-map?map=$mId$ESC\$disp$ESC]8;;$ESC\)$ESC[0m" }
                                                            elseif ($p) { $kStr = " $ESC[90m($ESC]8;;https://eso-hub.com/en/interactive-map?ping=$p$ESC\$disp$ESC]8;;$ESC\)$ESC[0m" }
                                                            else { $kStr = " $ESC[90m($disp)$ESC[0m" }
                                                        } else { $kStr = " $ESC[90m($kiosk)$ESC[0m" }
                                                    }
                                                    
                                                    $age = $CURRENT_TIME - $stime; $statusTag = ""
                                                    if ($scanType -eq "Sold") { $statusTag = " $ESC[38;5;214m[SOLD]$ESC[0m" }
                                                    elseif ($scanType -eq "Purchased") { $statusTag = " $ESC[92m[PURCHASED]$ESC[0m" }
                                                    elseif ($scanType -eq "Cancelled") { $statusTag = " $ESC[31m[CANCELLED]$ESC[0m" }
                                                    elseif ($scanType -eq "Listed") {
                                                        if ($stime -gt 0 -and $age -gt 2592000) { $statusTag = " $ESC[90m[EXPIRED]$ESC[0m" }
                                                        else { $statusTag = " $ESC[34m[AVAILABLE]$ESC[0m" }
                                                    }
                                                    
                                                    $link_start = "$ESC]8;;https://eso-hub.com/en/trading/$itemid$ESC\"
                                                    $link_end = "$ESC]8;;$ESC\"
                                                    
                                                    $tsStr = if ($stime -gt 0) {"[TS:$stime]"} else {"[$ESC[90mListing$ESC[0m]"}
                                                    $uiLine = " $tsStr $ESC[36m$scanType$ESC[0m for $ESC[32m$price$ESC[33mgold$ESC[0m - $ESC[32m${qty}x$ESC[0m ${link_start}$c$realName$ESC[0m${link_end}$tradeStr in $gDisplay$kStr$statusTag"
                                                    UIEcho $uiLine
                                                    $uiLine | Out-File -FilePath $TEMP_SCAN_FILE -Append -Encoding UTF8
                                                    $FOUND_NEW_DATA = $true
                                                    
                                                    if ($currentGuildId) {
                                                        [void]$histLines.Add("HISTORY|$stime|$scanType|$price|$qty|$itemid|$realName|$buyer|$seller|$gname|$kiosk|$c|ESO-Hub|1")
                                                    }
                                                    $count++
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        if ($count -eq 0) { UIEcho " $ESC[90mNo new ESO-Hub items found. Upload skipped.$ESC[0m" }
                        else { UIEcho " $ESC[92m[+]$ESC[0m Extraction complete!" }
                        
                        if ($histLines.Count -gt 0) { $histLines.ToArray() | Out-File -FilePath $HIST_FILE -Append -Encoding UTF8 }
                        Apply-DB-Updates $dbUpdates.ToArray()
                        
                        if ($max_time -gt [long]$EH_LAST_SALE) { $global:EH_LAST_SALE = $max_time; $CONFIG_CHANGED = $true }
                    }
                    
                    if ($global:ENABLE_LOCAL_MODE) {
                        UIEcho " $ESC[90m[Local Mode] Skipping ESO-Hub Upload ($SV_NAME).$ESC[0m"
                        Copy-Item -Path "$SAVED_VAR_DIR\$SV_NAME" -Destination $UP_SNAP -Force
                    } elseif ($count -eq 0 -and $SV_NAME -eq "EsoTradingHub.lua") {
                        Copy-Item -Path "$SAVED_VAR_DIR\$SV_NAME" -Destination $UP_SNAP -Force
                    } else {
                        UIEcho " $ESC[36mUploading local scan data ($SV_NAME)...$ESC[0m"
                        curl.exe -s -m 60 -A "ESOHubClient/1.0.9" -F "file=@$SAVED_VAR_DIR\$SV_NAME" "https://data.eso-hub.com$UP_EP?user_token=$EH_USER_TOKEN" | Out-Null
                        Copy-Item -Path "$SAVED_VAR_DIR\$SV_NAME" -Destination $UP_SNAP -Force
                        $ehUploadCount++
                        UIEcho " $ESC[92m[+] Upload finished ($SV_NAME).$ESC[0m"
                    }
                }
            }

            if ($DL_URL) {
                if ($SRV_VER -eq $LOC_VER) {
                    UIEcho " $ESC[90mNo changes detected. $ESC[92m($FNAME.zip) is up-to-date. $ESC[35mSkipping download.$ESC[0m"
                } else {
                    if ($global:ENABLE_LOCAL_MODE) { UIEcho " $ESC[90m[Local Mode] Skipping Download for $FNAME.zip.$ESC[0m" }
                    elseif ($EH_TIME_DIFF -lt 3600 -and $EH_TIME_DIFF -ge 0) {
                        $WAIT_MINS = [math]::Floor((3600 - $EH_TIME_DIFF) / 60)
                        UIEcho " $ESC[33mNew $FNAME.zip available, but download is on cooldown for $WAIT_MINS more minutes. $ESC[35mSkipping.$ESC[0m"
                    } else {
                        UIEcho " $ESC[36mDownloading: $FNAME.zip$ESC[0m"
                        $TEMP_DIR_USED = $true
                        $zipPath = "$TEMP_DIR\EH_$ID_NUM.zip"
                        curl.exe -f -# -L -A "ESOHubClient/1.0.9" -o $zipPath "$DL_URL"
                        if (Test-Path $zipPath) {
                            Expand-Archive -Path $zipPath -DestinationPath "$TEMP_DIR\ESOHub_Extracted" -Force
                            Copy-Item -Path "$TEMP_DIR\ESOHub_Extracted\*" -Destination "$ADDON_DIR\" -Recurse -Force
                            Set-Variable -Name $VAR_LOC_NAME -Value $SRV_VER -Scope Global
                            $CONFIG_CHANGED = $true; $EH_DOWNLOAD_OCCURRED = $true; $ehUpdateCount++
                            UIEcho " $ESC[92m[+] $FNAME.zip updated successfully.$ESC[0m"
                        } else { UIEcho " $ESC[31m[!] Error: $FNAME.zip download corrupted.$ESC[0m" }
                    }
                }
            }
        }
        if ($EH_DOWNLOAD_OCCURRED) { $global:EH_LAST_DOWNLOAD = $CURRENT_TIME }
        if ($ehUpdateCount -gt 0 -or $ehUploadCount -gt 0) { $notifEH = "Updated ($ehUpdateCount), Uploaded ($ehUploadCount)" }
        if (!$SILENT) { Write-Host "" }
    }

    if (!$HAS_HM -or $global:ENABLE_LOCAL_MODE) {
        UIEcho "$ESC[1m$ESC[97m [4/4] Updating HarvestMap Data (SKIPPED) $ESC[0m"
        if ($global:ENABLE_LOCAL_MODE) { UIEcho " $ESC[90m[Local Mode] Skipping HarvestMap updates.$ESC[0m`n" }
        else { UIEcho " $ESC[31m[-] HarvestMap is not installed. $ESC[35mSkipping...$ESC[0m`n" }
        $notifHM = "Skipped"
    } else {
        UIEcho "$ESC[1m$ESC[97m [4/4] Updating HarvestMap Data $ESC[0m"
        $HM_DIR = "$ADDON_DIR\HarvestMapData"
        $EMPTY_FILE = "$HM_DIR\Main\emptyTable.lua"
        $MAIN_HM_FILE = "$SAVED_VAR_DIR\HarvestMap.lua"
        $HM_SNAP = "$SNAP_DIR\lttc_hm_main_snapshot.lua"
        
        if (Test-Path $HM_DIR) {
            $HM_CHANGED = $true
            if (Test-Path $MAIN_HM_FILE) {
                if (Test-Path $HM_SNAP) {
                    $h1 = (Get-FileHash $MAIN_HM_FILE -Algorithm MD5).Hash
                    $h2 = (Get-FileHash $HM_SNAP -Algorithm MD5).Hash
                    if ($h1 -eq $h2) { $HM_CHANGED = $false }
                }
            }
            
            $global:HM_LAST_CHECK = $CURRENT_TIME; $CONFIG_CHANGED = $true
            
            if (!$HM_CHANGED) {
                UIEcho " $ESC[90mNo changes detected. $ESC[92mHarvestMap.lua is up-to-date. $ESC[35mSkipping process.$ESC[0m`n"
            } else {
                $HM_TIME_DIFF = $CURRENT_TIME - [int]$HM_LAST_DOWNLOAD
                if ($HM_TIME_DIFF -lt 3600 -and $HM_TIME_DIFF -ge 0) {
                    $WAIT_MINS = [math]::Floor((3600 - $HM_TIME_DIFF) / 60)
                    UIEcho " $ESC[33mHarvestMap local changes detected, but download is on cooldown for $WAIT_MINS more minutes.$ESC[0m`n"
                    $notifHM = "Cooldown ($WAIT_MINS min)"
                } else {
                    if (Test-Path $MAIN_HM_FILE) { Copy-Item -Path $MAIN_HM_FILE -Destination $HM_SNAP -Force }
                    $hmFailed = $false
                    foreach ($zone in @("AD", "EP", "DC", "DLC", "NF")) {
                        $svfn1 = "$SAVED_VAR_DIR\HarvestMap${zone}.lua"
                        $svfn2 = "${svfn1}~"
                        
                        if (Test-Path $svfn1) { Move-Item -Path $svfn1 -Destination $svfn2 -Force } 
                        else { 
                            if (Test-Path $EMPTY_FILE) {
                                $cnt = Get-Content $EMPTY_FILE -Raw
                                Set-Content -Path $svfn2 -Value "Harvest${zone}_SavedVars$cnt" -NoNewline
                            } else {
                                Set-Content -Path $svfn2 -Value "Harvest${zone}_SavedVars={[`"data`"]={}}" -NoNewline 
                            }
                        }
                        
                        $modDir = "$HM_DIR\Modules\HarvestMap${zone}"
                        if (!(Test-Path $modDir)) { New-Item -ItemType Directory -Force -Path $modDir | Out-Null }
                        UIEcho " $ESC[36mDownloading database chunk to:$ESC[0m $modDir\HarvestMap${zone}.lua"
                        try { Invoke-WebRequest -Uri "http://harvestmap.binaryvector.net:8081" -Method Post -InFile $svfn2 -OutFile "$modDir\HarvestMap${zone}.lua" -UserAgent $HM_USER_AGENT -ErrorAction Stop } catch { $hmFailed = $true }
                    }
                    if (!$hmFailed) { $global:HM_LAST_DOWNLOAD = $CURRENT_TIME; $CONFIG_CHANGED = $true; UIEcho "`n $ESC[92m[+] HarvestMap Data Successfully Updated.$ESC[0m`n"; $notifHM = "Updated successfully" }
                }
            }
        } else {
            UIEcho " $ESC[31m[!] HarvestMapData folder not found in: $ADDON_DIR. $ESC[35mSkipping...$ESC[0m`n"
            $notifHM = "Not Found (Skipped)"
        }
    }

    if ($FOUND_NEW_DATA) { Copy-Item -Path $TEMP_SCAN_FILE -Destination $LAST_SCAN_FILE -Force }

    Prune-History
    if ($CONFIG_CHANGED) { save_config }

    if ($TEMP_DIR_USED) { UIEcho "`n $ESC[36mCleaning up temporary files...$ESC[0m" }
    Set-Location $env:USERPROFILE
    
    $delCount = 0
    $targets = @($TEMP_DIR, "$TEMP_DIR_ROOT\*.tmp", "$TEMP_DIR_ROOT\*.out",
                 "$TEMP_DIR_ROOT\*.zip", "$TEMP_DIR_ROOT\ESOHub_Extracted")
                 
    foreach ($t in $targets) {
        $items = Get-ChildItem -Path $t -Recurse -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName
        $rootItem = Get-Item -Path $t -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName
            
        $allToDel = @()
        if ($items) { $allToDel += $items }
        if ($rootItem) { $allToDel += $rootItem }
        
        $allToDel | Select-Object -Unique | ForEach-Object {
            UIEcho " $ESC[90m-> Deleted: $_$ESC[0m"
            if ($global:LOG_MODE -eq "detailed") { Log-Event "ITEM" "Deleted Temp File: $_" }
            $delCount++
        }
        Remove-Item -Path $t -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    if ($delCount -gt 0) {
        UIEcho " $ESC[92m[+] Cleanup complete ($delCount items removed).$ESC[0m`n"
    } elseif ($TEMP_DIR_USED) {
        UIEcho " $ESC[92m[+] Cleanup complete.$ESC[0m`n"
    }

    if ($global:ENABLE_NOTIFS) {
        $msg = "TTC: $notifTTC`nESO-Hub: $notifEH`nHarvestMap: $notifHM"
        try {
            [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
            [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime] | Out-Null
            $appId = "{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe"
            $template = "<toast><visual><binding template=`"ToastText02`"><text id=`"1`">Windows Tamriel Trade Center v$APP_VERSION</text><text id=`"2`">$msg</text></binding></visual></toast>"
            $xmlDocument = New-Object Windows.Data.Xml.Dom.XmlDocument
            $xmlDocument.LoadXml($template)
            $toast = [Windows.UI.Notifications.ToastNotification]::new($xmlDocument)
            [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
        } catch {}
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
