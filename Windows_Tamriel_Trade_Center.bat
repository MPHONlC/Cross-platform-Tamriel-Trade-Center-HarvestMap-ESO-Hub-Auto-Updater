@echo off
:: =======================================================================================
:: Windows Tamriel Trade Center: Cross-Platform Auto-Updater for TTC, HarvestMap & ESO-Hub
:: Created by @APHONIC
:: =======================================================================================
setlocal
set "SCRIPT_FULL_PATH=%~f0"
set "PS_ARGS=%*"

:: Safely reads the file using '%~f0' to prevent 'Invoke-Expression' crashes.
set "WIN_STYLE=-WindowStyle Normal"
echo.%* | findstr /C:"--silent" >nul && set "WIN_STYLE=-WindowStyle Hidden"
echo.%* | findstr /C:"--task" >nul && set "WIN_STYLE=-WindowStyle Hidden"
powershell -Sta %WIN_STYLE% -NoProfile -ExecutionPolicy Bypass -Command "$code = (Get-Content -LiteralPath '%~f0' -Raw) -replace '(?sm)^.*?\n==POWERSHELL_START==\r?\n',''; $sb = [ScriptBlock]::Create($code); & $sb"

if %errorlevel% neq 0 pause
exit /b %errorlevel%

==POWERSHELL_START==
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
$ErrorActionPreference = "SilentlyContinue"

# VERSION
$APP_VERSION = "4.0"
$APP_TITLE = "Windows Tamriel Trade Center v$APP_VERSION"
$TASK_NAME = "Windows Tamriel Trade Center v$APP_VERSION"

# ANSI Color Setup
$ESC = [char]27
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$host.UI.RawUI.WindowTitle = $APP_TITLE

# C# Interop for advanced Console Management (Hiding/Restoring the Window)
try {
    $csharp = @"
    using System;
    using System.Runtime.InteropServices;
    public class ConsoleConfig {
        const int SW_HIDE = 0;
        const int SW_RESTORE = 9;
        const int SW_SHOW = 5;
        
        [DllImport("kernel32.dll", ExactSpelling = true)]
        public static extern IntPtr GetConsoleWindow();
        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")]
        public static extern bool IsIconic(IntPtr hWnd);

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
} catch {}

# DIRECTORY & ICON SETUP
$TARGET_DIR = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "Windows_Tamriel_Trade_Center"
if (!(Test-Path $TARGET_DIR)) { New-Item -ItemType Directory -Force -Path $TARGET_DIR | Out-Null }
$CONFIG_FILE = "$TARGET_DIR\lttc_updater.conf"
$ICON_FILE = "$TARGET_DIR\ttc_icon.ico"
$LOG_FILE = "$TARGET_DIR\wttc.logs"

# Ensure the icon exists, download if it doesn't (Desktop Shortcut and Tray Icon)
if (!(Test-Path $ICON_FILE)) {
    try { Invoke-WebRequest -Uri "https://eu.tamrieltradecentre.com/favicon.ico" -OutFile $ICON_FILE -UseBasicParsing -TimeoutSec 10 -ErrorAction SilentlyContinue } catch {}
}

# Steam Logic and only allowing 1 instance of this script to be alive
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, "Global\WTTC_Updater_Mutex_$APP_VERSION", [ref]$createdNew)
if (!$createdNew) {
    try {
        $evt = [System.Threading.EventWaitHandle]::OpenExisting("Global\WTTC_RestoreEvent_$APP_VERSION")
        $evt.Set()
    } catch {}
    
    # Instantly hide this terminal and aggressively kill parent CMD so it doesn't linger behind
    [ConsoleConfig]::HideWindow()
    try {
        $parent = Get-CimInstance Win32_Process -Filter "ProcessId = $PID"
        if ($parent.ParentProcessId) {
            $parentProc = Get-Process -Id $parent.ParentProcessId -ErrorAction SilentlyContinue
            if ($parentProc.Name -eq "cmd") { Stop-Process -Id $parentProc.Id -Force }
        }
    } catch {}
    Stop-Process -Id $PID -Force
}

# pre parse arguments
$parsedArgs = @()
if ([string]::IsNullOrWhiteSpace($env:PS_ARGS) -eq $false) {
    $parsedArgs = [System.Text.RegularExpressions.Regex]::Matches($env:PS_ARGS, '[\"]([^\"]+)[\"]|([^ ]+)') | ForEach-Object {
        if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value }
    }
}
$global:HAS_ARGS = if ($parsedArgs.Count -gt 0) {$true} else {$false}
$global:IS_TASK = $false

for ($i = 0; $i -lt $parsedArgs.Count; $i++) {
    # Treat --silent the same as --task so tray icon activates and hide window
    if ($parsedArgs[$i] -eq "--task" -or $parsedArgs[$i] -eq "--silent") { 
        $global:IS_TASK = $true 
        [ConsoleConfig]::HideWindow()
    }
}

Write-Log "WTTC Updater Service Started." "Information"

$script:restoreEvent = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, "Global\WTTC_RestoreEvent_$APP_VERSION")

# LOAD FORMS ASSEMBLY FOR BOTH NOTIFICATIONS AND TRAY ICON
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ONLY CREATE THE TRAY ICON IF RUNNING AS THE BACKGROUND STARTUP TASK
if ($global:IS_TASK) {
    $script:trayIcon = New-Object System.Windows.Forms.NotifyIcon
    $script:trayIcon.Text = $APP_TITLE
    if (Test-Path $ICON_FILE) { $script:trayIcon.Icon = New-Object System.Drawing.Icon($ICON_FILE) } 
    else { $script:trayIcon.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon((Get-Process -id $PID).Path) }

    $menu = New-Object System.Windows.Forms.ContextMenu
    $exitItem = New-Object System.Windows.Forms.MenuItem "Exit Updater"
    $exitItem.add_Click({
        Write-Log "WTTC Updater Service Terminated by User via Tray." "Information"
        $script:trayIcon.Visible = $false
        try {
            $parent = Get-CimInstance Win32_Process -Filter "ProcessId = $PID"
            if ($parent.ParentProcessId) {
                $parentProc = Get-Process -Id $parent.ParentProcessId -ErrorAction SilentlyContinue
                if ($parentProc.Name -eq "cmd") { Stop-Process -Id $parentProc.Id -Force }
            }
        } catch {}
        Stop-Process -Id $PID -Force
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
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 200
    }
}

# Grab the file path handed down from the Batch layer
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

# Force standalone and normal modes to be Verbose by default.
# The --silent launch argument will re-enable hidden mode automatically.
$global:SILENT = $false
$global:AUTO_PATH = if ($AUTO_PATH -eq 'true') {$true} else {$false}
$global:SETUP_COMPLETE = if ($SETUP_COMPLETE -eq 'true') {$true} else {$false}
$global:ENABLE_NOTIFS = if ($ENABLE_NOTIFS -eq 'true') {$true} else {$false}
if (!$STARTUP_MODE) { $global:STARTUP_MODE = "0" }
$global:IS_STEAM_LAUNCH = $false

if (!$TTC_LAST_SALE) { $global:TTC_LAST_SALE = 0 }
if (!$TTC_LAST_DOWNLOAD) { $global:TTC_LAST_DOWNLOAD = 0 }
if (!$TTC_LAST_CHECK) { $global:TTC_LAST_CHECK = 0 }
if (!$TTC_LOC_VERSION) { $global:TTC_LOC_VERSION = 0 }
if (!$EH_LAST_DOWNLOAD) { $global:EH_LAST_DOWNLOAD = 0 }
if (!$EH_LAST_CHECK) { $global:EH_LAST_CHECK = 0 }
if (!$EH_LOC_5) { $global:EH_LOC_5 = 0 }
if (!$EH_LOC_7) { $global:EH_LOC_7 = 0 }
if (!$EH_LOC_9) { $global:EH_LOC_9 = 0 }
if (!$HM_LAST_DOWNLOAD) { $global:HM_LAST_DOWNLOAD = 0 }
if (!$HM_LAST_CHECK) { $global:HM_LAST_CHECK = 0 }

function save_config {
    $c = @"
AUTO_SRV="$AUTO_SRV"
SILENT=$($SILENT.ToString().ToLower())
AUTO_MODE="$AUTO_MODE"
ADDON_DIR="$ADDON_DIR"
SETUP_COMPLETE=$($SETUP_COMPLETE.ToString().ToLower())
ENABLE_NOTIFS=$($ENABLE_NOTIFS.ToString().ToLower())
STARTUP_MODE="$STARTUP_MODE"
TTC_LAST_SALE="$TTC_LAST_SALE"
TTC_LAST_DOWNLOAD="$TTC_LAST_DOWNLOAD"
TTC_LAST_CHECK="$TTC_LAST_CHECK"
TTC_LOC_VERSION="$TTC_LOC_VERSION"
EH_LAST_DOWNLOAD="$EH_LAST_DOWNLOAD"
EH_LAST_CHECK="$EH_LAST_CHECK"
EH_LOC_5="$EH_LOC_5"
EH_LOC_7="$EH_LOC_7"
EH_LOC_9="$EH_LOC_9"
HM_LAST_DOWNLOAD="$HM_LAST_DOWNLOAD"
HM_LAST_CHECK="$HM_LAST_CHECK"
"@
    $c | Out-File -FilePath $CONFIG_FILE -Encoding UTF8 -Force
}

for ($i = 0; $i -lt $parsedArgs.Count; $i++) {
    switch ($parsedArgs[$i]) {
        "--silent" { $global:SILENT = $true }
        "--auto" { $global:AUTO_PATH = $true }
        "--na" { $global:AUTO_SRV = "1" }
        "--eu" { $global:AUTO_SRV = "2" }
        "--loop" { $global:AUTO_MODE = "2" }
        "--once" { $global:AUTO_MODE = "1" }
        "--steam" { $global:IS_STEAM_LAUNCH = $true }
    }
}

function auto_scan_addons {
    Write-Host " Scanning standard Documents & OneDrive folders..." -ForegroundColor Cyan
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

    Write-Host " Performing scans for AddOns folder across all drives (this may take a moment)..." -ForegroundColor Yellow
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

    if ($CURRENT_DIR -ne $TARGET_DIR) {
        Copy-Item -Path $FULL_SCRIPT_PATH -Destination "$TARGET_DIR\$SCRIPT_NAME" -Force
        Write-Host "$ESC[0;32m[+] Script successfully copied/updated in Documents folder:$ESC[0m $TARGET_DIR"
    } else {
        Write-Host "$ESC[0;36m-> Script is already running from the Documents folder.\n$ESC[0m"
    }

    Write-Host "`n$ESC[0;33m1. Which server do you play on? (For TTC Pricing)$ESC[0m"
    Write-Host "1) North America (NA)`n2) Europe (EU)"
    $global:AUTO_SRV = Read-Host "Choice [1-2]"

    Write-Host "`n$ESC[0;33m2. Do you want the terminal to be visible when launching via Steam?$ESC[0m"
    Write-Host "1) Show Terminal (Verbose visible output)`n2) Hide Terminal (Invisible background hidden)"
    $ans = Read-Host "Choice [1-2]"
    if ($ans -eq "2") { $global:SILENT = $true } else { $global:SILENT = $false }

    Write-Host "`n$ESC[0;33m3. How should the script run during gameplay?$ESC[0m"
    Write-Host "1) Run once and close immediately`n2) Loop continuously (Checks local file & server status every 60 minutes to avoid server rate-limit)"
    $global:AUTO_MODE = Read-Host "Choice [1-2]"

    Write-Host "`n$ESC[0;33m4. Addon Folder Location$ESC[0m"
    if ($ADDON_DIR -and (Test-Path $ADDON_DIR)) {
        Write-Host "$ESC[0;32m[+] Found Saved Addons Directory at:$ESC[0m $ADDON_DIR"
        $FOUND_ADDONS = $ADDON_DIR
    } else {
        $FOUND_ADDONS = auto_scan_addons
        if ($FOUND_ADDONS) {
            Write-Host "$ESC[0;32m[+] Found Addons folder at:$ESC[0m $FOUND_ADDONS"
            $ans = Read-Host "Is this the correct location? (y/n)"
            if ($ans -notmatch '^[Yy]$') { $FOUND_ADDONS = Read-Host "Enter full custom path to AddOns folder" }
        } else {
            Write-Host "$ESC[0;31m[-] Could not find AddOns folder automatically.$ESC[0m"
            $FOUND_ADDONS = Read-Host "Enter full custom path to AddOns folder"
        }
    }
    $global:ADDON_DIR = $FOUND_ADDONS

    Write-Host "`n$ESC[0;33m5. Enable Native Windows Notifications?$ESC[0m"
    Write-Host "1) Yes (Uses native Action Center, summarizes updates, respects Do Not Disturb)`n2) No"
    $ans = Read-Host "Choice [1-2]"
    $global:ENABLE_NOTIFS = if ($ans -eq "1") {$true} else {$false}

    # Cleanup any old shortcuts and tasks
    $DesktopPath = [Environment]::GetFolderPath("Desktop")
    $startupPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    $startupShortcut = "$startupPath\Windows_TTC_Updater.lnk"
    $vbsLauncher = "$TARGET_DIR\wttc_launcher.vbs"
    
    if (Test-Path "$DesktopPath\Windows Tamriel Trade Center.lnk") { Remove-Item "$DesktopPath\Windows Tamriel Trade Center.lnk" -Force -ErrorAction SilentlyContinue }

    Write-Host "`n$ESC[0;33m6. Run automatically in the background when PC Starts?$ESC[0m"
    Write-Host "`n$ESC[0;33mOptions that require to delete Scheduled Task will always ask for UAC (Admin Access)$ESC[0m"
    Write-Host "1) Yes - Advanced Mode (Requires Admin, completely invisible Scheduled Task)"
    Write-Host "2) Yes - Standard Mode (No Admin, places hidden shortcut in Startup folder)"
    Write-Host "3) No  - (Do not run at startup, cleans up previous startup choices)"
    $ans = Read-Host "Choice [1-3]"
    
    # Mutually Exclusive Cleanup Logic with Admin Elevation for Task Deletion
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
        Write-Host "`n -> Registering Scheduled Task & Event Log (Please click 'Yes' on the Admin prompt)..."
        
        # Create VBS launcher for startup
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
            Write-Log "Background Startup Task registered." "Information"
        } else {
            Write-Host "$ESC[0;31m[-] Failed to get proper admin privileges or action was canceled.$ESC[0m"
            Write-Host "$ESC[0;33m -> Falling back to Windows Startup Folder method.$ESC[0m"
            Write-Log "Failed to elevate. Used Fallback Startup Shortcut." "Warning"
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
            Write-Log "Startup Shortcut registered." "Information"
        } catch { Write-Host "$ESC[0;31m[-] Failed to create startup shortcut.$ESC[0m" }
    } else {
        Write-Host "`n -> Skipping startup registration & ensuring clean state.$ESC[0m"
    }

    $global:SETUP_COMPLETE = $true
    save_config

    Write-Host "`n$ESC[0;33m7. Desktop Shortcut$ESC[0m"
    Write-Host "1) Yes - Run normally (Show terminal output)"
    Write-Host "2) Yes - Run hidden (Background, uses tray icon)"
    Write-Host "3) No"
    $ans = Read-Host "Choice [1-3]"
    
    $SHORTCUT_SRV_FLAG = if ($AUTO_SRV -eq "2") {"--eu"} else {"--na"}
    $SILENT_FLAG = if ($SILENT) {"--silent"} else {""}
    $LOOP_FLAG = if ($AUTO_MODE -eq "2") {"--loop"} else {"--once"}

    if ($ans -eq "1" -or $ans -eq "2") {
        Write-Host " -> Creating desktop icon..."
        try {
            $WshShell = New-Object -comObject WScript.Shell
            $Shortcut = $WshShell.CreateShortcut("$DesktopPath\Windows Tamriel Trade Center.lnk")
            
            if ($ans -eq "2") {
                # Setup Shortcut to run entirely hidden and spawn the Tray Icon
                $Shortcut.TargetPath = "powershell.exe"
                $Shortcut.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -Command `"Start-Process -FilePath '$TARGET_DIR\$SCRIPT_NAME' -ArgumentList '--silent $SHORTCUT_SRV_FLAG $LOOP_FLAG --task' -WindowStyle Hidden`""
                $Shortcut.WindowStyle = 7
            } else {
                # Setup Shortcut to run normally
                $Shortcut.TargetPath = "$TARGET_DIR\$SCRIPT_NAME"
                $Shortcut.Arguments = "$SHORTCUT_SRV_FLAG $LOOP_FLAG"
                $Shortcut.WindowStyle = 1
            }
            
            if (Test-Path $ICON_FILE) { $Shortcut.IconLocation = $ICON_FILE }
            $Shortcut.Save()
            Write-Host "$ESC[0;32m[+] Windows desktop shortcut installed.$ESC[0m"
        } catch { Write-Host "$ESC[0;31m[-] Failed to create shortcut.$ESC[0m" }
    }

    Write-Host "`n$ESC[0;92m================ SETUP COMPLETE ================$ESC[0m"
    Write-Host "To run this automatically alongside your game, copy this string into your Steam Launch Options:`n"
    
    $ARGS_STR = "$SILENT_FLAG $SHORTCUT_SRV_FLAG $LOOP_FLAG --steam"
    
    if ($SILENT) {
        $LAUNCH_CMD = "cmd /c start `"`" /MIN `"$TARGET_DIR\$SCRIPT_NAME`" $ARGS_STR & %command%"
    } else {
        $LAUNCH_CMD = "cmd /c start `"`" `"$TARGET_DIR\$SCRIPT_NAME`" $ARGS_STR & %command%"
    }
    
    Write-Host "$ESC[0;104m $LAUNCH_CMD $ESC[0m`n"
    
    Write-Host "$ESC[0;33m8. Steam Launch Options$ESC[0m"
    Write-Host "Would you like this script to automatically inject the Launch Command into your Steam configuration?"
    Write-Host "(WARNING: Steam MUST be closed to do this. We can close it for you.)"
    $ans = Read-Host "Apply automatically? (y/n)"
    
    if ($ans -match '^[Yy]$') {
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

            Write-Host "$ESC[0;36m-> Injecting into $($conf.FullName)...$ESC[0m"
            $text = [System.IO.File]::ReadAllText($conf.FullName)
            
            $escapedStr = $LAUNCH_CMD.Replace('\', '\\').Replace('"', '\"').Replace('$', '$$')
            
            if ($text -match '"306130"\s*\{') {
                if ($text -match '"306130"\s*\{[\s\S]*?"LaunchOptions"\s*"[^"]*"') {
                    $text = [regex]::Replace($text, '("306130"\s*\{[\s\S]*?)"LaunchOptions"\s*"[^"]*"', "`${1}`"LaunchOptions`"`t`t`"$escapedStr`"")
                } else {
                    $text = [regex]::Replace($text, '("306130"\s*\{)', "`${1}`n`t`t`t`t`"LaunchOptions`"`t`t`"$escapedStr`"")
                }
            } else {
                $text = [regex]::Replace($text, '("apps"\s*\{)', "`${1}`n`t`t`t`"306130`"`n`t`t`t{`n`t`t`t`t`"LaunchOptions`"`t`t`"$escapedStr`"`n`t`t`t}")
            }
            
            $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
            [System.IO.File]::WriteAllText($conf.FullName, $text, $Utf8NoBomEncoding)
            Write-Host "$ESC[0;32m[+] Successfully injected Launch Options into Steam!$ESC[0m"
        }
        Write-Host "$ESC[0;33m[!] Restarting Steam...$ESC[0m"
        Start-Process "steam://open/main" -ErrorAction SilentlyContinue
    }
    Read-Host "Press Enter to start the updater now..."
    
    # Reset silent flag
    $global:SILENT = $false
}

$INSTALLED_SCRIPT = "$TARGET_DIR\$SCRIPT_NAME"

if ($SETUP_COMPLETE -and !$HAS_ARGS) {
    if ((Test-Path $INSTALLED_SCRIPT) -and (Test-Path $CONFIG_FILE)) {
        Clear-Host
        Write-Host "$ESC[0;32m[+] Configuration found! Using saved settings.$ESC[0m"
        Write-Host "$ESC[0;36m-> Press 'y' to re-run setup, or wait 5 seconds to continue automatically...`n$ESC[0m"
        
        $timeout = new-timespan -Seconds 5
        $sw = [diagnostics.stopwatch]::StartNew()
        $key = $null
        while ($sw.elapsed -lt $timeout) {
            [ConsoleConfig]::CheckMinimizedAndHide() | Out-Null
            [System.Windows.Forms.Application]::DoEvents()
            if ($host.UI.RawUI.KeyAvailable) { $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown"); break }
            Start-Sleep -Milliseconds 50
        }
        
        if ($key -and $key.Character -match '^[Yy]$') { 
            run_setup 
        } else {
            if ($CURRENT_DIR -ne $TARGET_DIR) {
                Copy-Item -Path $FULL_SCRIPT_PATH -Destination "$TARGET_DIR\$SCRIPT_NAME" -Force
            }
        }
    } else { run_setup }
} elseif (!$SETUP_COMPLETE -and !$HAS_ARGS) { run_setup }

$TTC_DOMAIN = if ($AUTO_SRV -eq "1") {"us.tamrieltradecentre.com"} else {"eu.tamrieltradecentre.com"}
$TTC_URL = "https://$TTC_DOMAIN/download/PriceTable"
$SAVED_VAR_DIR = (Get-Item $ADDON_DIR).Parent.FullName + "\SavedVariables"
$TEMP_DIR = "$env:USERPROFILE\Downloads\Windows_Tamriel_Trade_Center_Temp"

$TTC_USER_AGENT = "TamrielTradeCentreClient/1.0.0"
$HM_USER_AGENT = "HarvestMapClient/1.0.0"

$USER_AGENTS = @(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:123.0) Gecko/20100101 Firefox/123.0"
)

while ($true) {
    $CONFIG_CHANGED = $false
    $TEMP_DIR_USED = $false
    $CURRENT_TIME = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    
    $notifTTC = "Up-to-date"
    $notifEH = "Up-to-date"
    $notifHM = "Up-to-date"
    
    $RAND_UA = $USER_AGENTS | Get-Random

    if (!$SILENT) {
        Clear-Host
        Write-Host "$ESC[0;92m===========================================================================$ESC[0m"
        Write-Host "$ESC[1m$ESC[0;94m                         $APP_TITLE$ESC[0m"
        Write-Host "$ESC[0;97m         Cross-Platform Auto-Updater for TTC, HarvestMap & ESO-Hub$ESC[0m"
        Write-Host "$ESC[0;90m                            Created by @APHONIC$ESC[0m"
        Write-Host "$ESC[0;92m===========================================================================`n$ESC[0m"
        Write-Host "$ESC[0;36m       [!] To properly close and terminate the updater, press CTRL+C.$ESC[0m"
        Write-Host "$ESC[0;92m===========================================================================`n$ESC[0m"
        Write-Host "Target AddOn Directory: $ESC[35m$ADDON_DIR$ESC[0m`n"
    }

    if (!(Test-Path $TEMP_DIR)) { New-Item -ItemType Directory -Force -Path $TEMP_DIR | Out-Null }
    Set-Location $TEMP_DIR

    # PARSE ADDON SETTINGS
    $ADDON_SETTINGS_FILE = (Get-Item $ADDON_DIR).Parent.FullName + "\AddOnSettings.txt"
    $addonSettingsText = if (Test-Path $ADDON_SETTINGS_FILE) { Get-Content $ADDON_SETTINGS_FILE -Raw } else { "" }

    function Check-Addon-Enabled($addonName) {
        if ($addonSettingsText) { return ($addonSettingsText -match "\b$addonName\b") }
        return (Test-Path "$ADDON_DIR\$addonName")
    }

    $HAS_TTC = Check-Addon-Enabled "TamrielTradeCentre"
    $HAS_HM = Check-Addon-Enabled "HarvestMap"

    # TTC Proccess
    if (!$HAS_TTC) {
        if (!$SILENT) { Write-Host "$ESC[1m$ESC[97m [1/4] & [2/4] Updating TTC Data (SKIPPED)$ESC[0m" }
        if (!$SILENT) { Write-Host " $ESC[31m[-] TamrielTradeCentre is not installed/enabled in AddOnSettings.txt. $ESC[35mSkipping TTC updates.$ESC[0m`n" }
        $notifTTC = "Not Installed (Skipped)"
    } else {
        # UPLOAD TTC DATA
        if (!$SILENT) { Write-Host "$ESC[1m$ESC[97m [1/4] Uploading your Local TTC Data to TTC Server $ESC[0m" }
        
        $TTC_CHANGED = $true
        if (Test-Path "$SAVED_VAR_DIR\TamrielTradeCentre.lua") {
            if (Test-Path "$TARGET_DIR\lttc_ttc_snapshot.lua") {
                $h1 = (Get-FileHash "$SAVED_VAR_DIR\TamrielTradeCentre.lua" -Algorithm MD5).Hash
                $h2 = (Get-FileHash "$TARGET_DIR\lttc_ttc_snapshot.lua" -Algorithm MD5).Hash
                if ($h1 -eq $h2) { $TTC_CHANGED = $false }
            }

            if (!$TTC_CHANGED) {
                if (!$SILENT) { Write-Host " $ESC[90mNo changes detected in TamrielTradeCentre.lua. $ESC[35mSkipping upload.$ESC[0m`n" }
            } else {
                Copy-Item -Path "$SAVED_VAR_DIR\TamrielTradeCentre.lua" -Destination "$TARGET_DIR\lttc_ttc_snapshot.lua" -Force -ErrorAction SilentlyContinue
                if (!$SILENT) {
                    Write-Host " $ESC[36mExtracting recent sales data from Lua (Showing up to 30 recent entries)...$ESC[0m"
                    $max_time = [long]$TTC_LAST_SALE; $lines = New-Object System.Collections.ArrayList
                    $name = ""; $price = ""; $amt = ""; $qual = ""; $stime = ""
                    
                    try {
                        foreach ($line in [System.IO.File]::ReadLines("$SAVED_VAR_DIR\TamrielTradeCentre.lua")) {
                            if ($line -match '\["Amount"\]\s*=\s*(\d+)') { $amt = $matches[1] }
                            if ($line -match '\["QualityID"\]\s*=\s*(\d+)') { $qual = $matches[1] }
                            if ($line -match '\["SaleTime"\]\s*=\s*(\d+)') { $stime = $matches[1] }
                            if ($line -match '\["TotalPrice"\]\s*=\s*(\d+)') { $price = $matches[1] }
                            if ($line -match '\["Name"\]\s*=\s*"([^"]+)"') { $name = $matches[1] }
                            if ($line -match '\}') {
                                if ($name -ne "" -and $price -ne "") {
                                    $stimeNum = $stime -as [long]
                                    if ($stimeNum -gt $max_time) { $max_time = $stimeNum }
                                    if ($stimeNum -gt [long]$TTC_LAST_SALE) {
                                        $c = switch ($qual) { 0 {"$ESC[90m"}; 1 {"$ESC[97m"}; 2 {"$ESC[32m"}; 3 {"$ESC[36m"}; 4 {"$ESC[35m"}; 5 {"$ESC[33m"}; 6 {"$ESC[38;5;214m"}; default {"$ESC[0m"} }
                                        [void]$lines.Add(" for $ESC[32m$price$ESC[33mgold$ESC[0m - $ESC[32m${amt}x$ESC[0m $c$name$ESC[0m")
                                    }
                                }
                                $name = ""; $price = ""; $amt = ""; $qual = ""; $stime = ""
                            }
                        }
                    } catch {}

                    $start = if ($lines.Count -gt 30) { $lines.Count - 30 } else { 0 }
                    if ($lines.Count -gt 0) { for ($i = $start; $i -lt $lines.Count; $i++) { Write-Host $lines[$i] } }
                    else { Write-Host " $ESC[90mNo new sales found since last upload.$ESC[0m" }

                    if ($max_time -gt [long]$TTC_LAST_SALE) {
                        $global:TTC_LAST_SALE = $max_time
                        $CONFIG_CHANGED = $true
                    }
                    Write-Host "`n $ESC[36mUploading to:$ESC[0m https://$TTC_DOMAIN/pc/Trade/WebClient/Upload"
                }
                curl.exe -s -A "$TTC_USER_AGENT" -H "Accept: text/html,application/xhtml+xml,application/xml" -F "SavedVarFileInput=@$SAVED_VAR_DIR\TamrielTradeCentre.lua" "https://$TTC_DOMAIN/pc/Trade/WebClient/Upload" | Out-Null
                $notifTTC = "Data Uploaded"
                Write-Log "TTC local sales data uploaded to server." "Information"
                if (!$SILENT) { Write-Host " $ESC[92m[+] Upload finished.$ESC[0m`n" }
            }
        } else {
            if (!$SILENT) { Write-Host " $ESC[33m[-] No TamrielTradeCentre.lua found. $ESC[35mSkipping upload.$ESC[0m`n" }
        }

        # DOWNLOAD TTC DATA
        if (!$SILENT) { Write-Host "$ESC[1m$ESC[97m [2/4] Updating your Local TTC Data $ESC[0m" }
        if (!$SILENT) { Write-Host " $ESC[33mChecking TTC API for price table version...$ESC[0m" }
        
        $global:TTC_LAST_CHECK = $CURRENT_TIME
        $CONFIG_CHANGED = $true

        try {
            $API_RESP = Invoke-RestMethod -Uri "https://$TTC_DOMAIN/api/GetTradeClientVersion" -UserAgent $TTC_USER_AGENT
            $SRV_VERSION = $API_RESP.PriceTableVersion
        } catch { $SRV_VERSION = $null }

        if (!$SRV_VERSION) {
            $notifTTC = "Download Error (API Blocked)"
            Write-Log "Could not fetch version from TTC API. Update skipped." "Warning"
            if (!$SILENT) { Write-Host " $ESC[31m[-] Could not fetch version from TTC API. $ESC[35mSkipping download.$ESC[0m`n" }
        } else {
            $LOCAL_VERSION = "0"
            $PT_FILE = if ($AUTO_SRV -eq "2") {"$ADDON_DIR\TamrielTradeCentre\PriceTableEU.lua"} else {"$ADDON_DIR\TamrielTradeCentre\PriceTableNA.lua"}
            
            if (Test-Path $PT_FILE) {
                $head = Get-Content $PT_FILE -TotalCount 5
                foreach ($l in $head) {
                    if ($l -match '^--Version[ \t]*=[ \t]*([0-9]+)') { $LOCAL_VERSION = $matches[1]; break }
                }
            }

            $LOCAL_DISPLAY = if ($LOCAL_VERSION -eq "0") {"None / Not Found"} else {$LOCAL_VERSION}
            $V_COL = if ([int]$SRV_VERSION -eq [int]$LOCAL_VERSION) {"$ESC[92m"} else {"$ESC[31m"}

            if ([int]$SRV_VERSION -gt [int]$LOCAL_VERSION) {
                if (!$SILENT) { Write-Host -NoNewline " $ESC[92mNew TTC Price Table available $ESC[0m" }
                $TTC_TIME_DIFF = $CURRENT_TIME - [int]$TTC_LAST_DOWNLOAD
                if ($TTC_TIME_DIFF -lt 3600 -and $TTC_TIME_DIFF -ge 0) {
                    $WAIT_MINS = [math]::Floor((3600 - $TTC_TIME_DIFF) / 60)
                    if ($notifTTC -eq "Data Uploaded") { $notifTTC = "Uploaded (DL Cooldown)" } else { $notifTTC = "Download Cooldown" }
                    if (!$SILENT) {
                        Write-Host "`n `t$ESC[90mServer Version: ${V_COL}$SRV_VERSION$ESC[0m"
                        Write-Host " `t$ESC[90mLocal Version: ${V_COL}$LOCAL_DISPLAY$ESC[0m"
                        Write-Host " $ESC[33mbut download is on cooldown. Please wait $WAIT_MINS minutes. $ESC[35mSkipping.$ESC[0m`n"
                    }
                } else {
                    if (!$SILENT) {
                        Write-Host "`n `t$ESC[90mServer Version: ${V_COL}$SRV_VERSION$ESC[0m"
                        Write-Host " `t$ESC[90mLocal Version: ${V_COL}$LOCAL_DISPLAY$ESC[0m"
                        Write-Host " $ESC[36mDownloading from:$ESC[0m $TTC_URL"
                    }
                    
                    $TEMP_DIR_USED = $true
                    $zipPath = "$TEMP_DIR\TTC-data.zip"
                    curl.exe -f -A "$TTC_USER_AGENT" -# -L -o $zipPath "$TTC_URL"
                    
                    if (Test-Path $zipPath) {
                        Expand-Archive -Path $zipPath -DestinationPath "$TEMP_DIR\TTC_Extracted" -Force
                        if (!(Test-Path "$ADDON_DIR\TamrielTradeCentre")) { New-Item -ItemType Directory -Force -Path "$ADDON_DIR\TamrielTradeCentre" | Out-Null }
                        Copy-Item -Path "$TEMP_DIR\TTC_Extracted\*" -Destination "$ADDON_DIR\TamrielTradeCentre\" -Recurse -Force
                        Send-Live-Update "TTC: Downloading and extracting latest price data..."
                        $global:TTC_LAST_DOWNLOAD = $CURRENT_TIME
                        $global:TTC_LOC_VERSION = $SRV_VERSION
                        $CONFIG_CHANGED = $true
                        if ($notifTTC -eq "Data Uploaded") { $notifTTC = "Uploaded & Updated" } else { $notifTTC = "Updated" }
                        Write-Log "TTC PriceTable updated to version $SRV_VERSION." "Information"
                        if (!$SILENT) { Write-Host " $ESC[92m[+] TTC Data Successfully Updated.$ESC[0m`n" }
                    } else {
                        if ($notifTTC -eq "Data Uploaded") { $notifTTC = "Uploaded, but DL Failed" } else { $notifTTC = "Download Error" }
                        Write-Log "TTC Data download blocked by the server." "Error"
                        if (!$SILENT) { Write-Host " $ESC[31m[!] Error: TTC Data download blocked by the server.$ESC[0m`n" }
                    }
                }
            } else {
                $global:TTC_LOC_VERSION = $LOCAL_VERSION
                $CONFIG_CHANGED = $true
                if (!$SILENT) {
                    Write-Host " `t$ESC[90mServer Version: ${V_COL}$SRV_VERSION$ESC[0m"
                    Write-Host " `t$ESC[90mLocal Version: ${V_COL}$LOCAL_DISPLAY$ESC[0m`n"
                    Write-Host " $ESC[90mNo changes detected. $ESC[92mLocal PriceTable is up-to-date. $ESC[35mSkipping download.$ESC[0m"
                }
                Send-Live-Update "TTC: Prices are already up to date. Skipping."
            }
        }
    }

    # ESO-HUB Proccess
    if (!$SILENT) { Write-Host "`n$ESC[1m$ESC[97m [3/4] Updating ESO-Hub Prices & Uploading Scans $ESC[0m" }
    if (!$SILENT) { Write-Host " $ESC[36mFetching latest ESO-Hub version data...$ESC[0m" }
    
    $global:EH_LAST_CHECK = $CURRENT_TIME
    $CONFIG_CHANGED = $true
    $ehUploadCount = 0
    $ehUpdateCount = 0

    $EH_JSON_FILE = "$TEMP_DIR\esohub_temp.json"
    if (Test-Path $EH_JSON_FILE) { Remove-Item $EH_JSON_FILE -Force }
    
    $curlCmd = "curl.exe -s -X POST -H `"User-Agent: ESOHubClient/1.0.9`" -d `"user_token=&client_system=windows&client_version=1.0.9&lang=en`" `"https://data.eso-hub.com/v1/api/get-addon-versions`" -o `"$EH_JSON_FILE`""
    cmd /c $curlCmd
    
    $addonBlocks = @()
    if (Test-Path $EH_JSON_FILE) {
        $jsonStr = Get-Content $EH_JSON_FILE -Raw
        $jsonStr = $jsonStr.Replace('{"folder_name"', "`n{`"folder_name`"")
        $lines = $jsonStr -split "`n"
        foreach ($line in $lines) {
            if ($line -match '"folder_name"') {
                $addonBlocks += $line
            }
        }
    }
    
    if ($addonBlocks.Count -eq 0) {
        $notifEH = "Download Error"
        Write-Log "Could not fetch ESO-Hub data." "Warning"
        if (!$SILENT) { Write-Host " $ESC[31m[-] Could not fetch ESO-Hub data.$ESC[0m`n" }
    } else {
        $EH_TIME_DIFF = $CURRENT_TIME - [int]$EH_LAST_DOWNLOAD
        $EH_DOWNLOAD_OCCURRED = $false

        foreach ($line in $addonBlocks) {
            $FNAME = ""; $SV_NAME = ""; $UP_EP = ""; $DL_URL = ""; $SRV_VER = ""
            
            if ($line -match '"folder_name"\s*:\s*"([^"]+)"') { $FNAME = $matches[1] }
            if ($line -match '"sv_file_name"\s*:\s*"([^"]+)"') { $SV_NAME = $matches[1] }
            if ($line -match '"endpoint"\s*:\s*"([^"]+)"') { $UP_EP = $matches[1].Replace('\/','/') }
            if ($line -match '"file"\s*:\s*"([^"]+)"') { $DL_URL = $matches[1].Replace('\/','/') }
            
            if ($line -match '"version"\s*:\s*\{[^}]*"string"\s*:\s*"([^"]+)"') { 
                $SRV_VER = $matches[1] 
            } elseif ($line -match '"version"\s*:\s*"([^"]+)"') {
                $SRV_VER = $matches[1]
            }

            if (!$FNAME) { continue }

            $HAS_THIS_EH = Check-Addon-Enabled $FNAME
            if (!$HAS_THIS_EH) {
                if (!$SILENT) { Write-Host " $ESC[31m[-] $FNAME is not installed/enabled in AddOnSettings.txt. $ESC[35mSkipping.$ESC[0m" }
                continue
            }
            
            $ID_NUM = if ($DL_URL -match '(\d+)$') { $matches[1] } else { "0" }
            if (!$SRV_VER) { $SRV_VER = "0" }
            
            $PREFIX = switch ($FNAME) {
                "EsoTradingHub" { "ETH5" }
                "LibEsoHubPrices" { "LEHP7" }
                "EsoHubScanner" { "EHS" }
                default { $FNAME }
            }

            $VAR_LOC_NAME = "EH_LOC_$ID_NUM"
            $LOC_VER = Get-Variable -Name $VAR_LOC_NAME -ValueOnly -ErrorAction SilentlyContinue
            if (!$LOC_VER) { $LOC_VER = "0" }

            $V_COL = if ($SRV_VER -eq $LOC_VER) {"$ESC[92m"} else {"$ESC[31m"}

            if (!$SILENT) {
                Write-Host " $ESC[33mChecking server for $FNAME.zip...$ESC[0m"
                Write-Host "`t$ESC[90m${PREFIX}_Server_Version= ${V_COL}$SRV_VER$ESC[0m"
                Write-Host "`t$ESC[90m${PREFIX}_Local_Version= ${V_COL}$LOC_VER$ESC[0m"
            }

            # Upload
            if ($SV_NAME -and $UP_EP) {
                if (Test-Path "$SAVED_VAR_DIR\$SV_NAME") {
                    $UP_SNAP = "$TARGET_DIR\lttc_eh_$($SV_NAME.ToLower().Replace('.lua',''))_snapshot.lua"
                    $EH_LOCAL_CHANGED = $true
                    if (Test-Path $UP_SNAP) {
                        $h1 = (Get-FileHash "$SAVED_VAR_DIR\$SV_NAME" -Algorithm MD5).Hash
                        $h2 = (Get-FileHash $UP_SNAP -Algorithm MD5).Hash
                        if ($h1 -eq $h2) { $EH_LOCAL_CHANGED = $false }
                    }

                    if (!$EH_LOCAL_CHANGED) {
                        if (!$SILENT) { Write-Host " $ESC[90mNo changes detected in $SV_NAME. $ESC[35mSkipping upload.$ESC[0m" }
                    } else {
                        if (!$SILENT) { Write-Host " $ESC[36mUploading local scan data ($SV_NAME)...$ESC[0m" }
                        curl.exe -s -A "ESOHubClient/1.0.9" -F "file=@$SAVED_VAR_DIR\$SV_NAME" "https://data.eso-hub.com$UP_EP?user_token=" | Out-Null
                        Copy-Item -Path "$SAVED_VAR_DIR\$SV_NAME" -Destination $UP_SNAP -Force
                        $ehUploadCount++
                        Write-Log "ESO-Hub local data ($SV_NAME) uploaded to server." "Information"
                        if (!$SILENT) { Write-Host " $ESC[92m[+] Upload finished ($SV_NAME).$ESC[0m" }
                    }
                } else {
                    if (!$SILENT) { Write-Host " $ESC[33m[-] No $SV_NAME found. $ESC[35mSkipping upload.$ESC[0m" }
                }
            }

            # Download
            if ($DL_URL) {
                if ($SRV_VER -eq $LOC_VER) {
                    if (!$SILENT) { Write-Host " $ESC[90mNo changes detected. $ESC[92m($FNAME.zip) is up-to-date. $ESC[35mSkipping download.$ESC[0m" }
                } else {
                    if ($EH_TIME_DIFF -lt 3600 -and $EH_TIME_DIFF -ge 0) {
                        $WAIT_MINS = [math]::Floor((3600 - $EH_TIME_DIFF) / 60)
                        if (!$SILENT) { Write-Host " $ESC[33mNew $FNAME.zip available, but download is on cooldown for $WAIT_MINS more minutes. $ESC[35mSkipping.$ESC[0m" }
                    } else {
                        if (!$SILENT) { Write-Host " $ESC[36mDownloading: $FNAME.zip$ESC[0m" }
                        $TEMP_DIR_USED = $true
                        $zipPath = "$TEMP_DIR\EH_$ID_NUM.zip"
                        curl.exe -f -# -L -A "ESOHubClient/1.0.9" -o $zipPath "$DL_URL"
                        
                        if (Test-Path $zipPath) {
                            Expand-Archive -Path $zipPath -DestinationPath "$TEMP_DIR\ESOHub_Extracted" -Force
                            Copy-Item -Path "$TEMP_DIR\ESOHub_Extracted\*" -Destination "$ADDON_DIR\" -Recurse -Force
                            
                            Set-Variable -Name $VAR_LOC_NAME -Value $SRV_VER -Scope Global
                            $CONFIG_CHANGED = $true
                            $EH_DOWNLOAD_OCCURRED = $true
                            $ehUpdateCount++
                            Write-Log "ESO-Hub Addon ($FNAME) updated to version $SRV_VER." "Information"
                            if (!$SILENT) { Write-Host " $ESC[92m[+] $FNAME.zip updated successfully.$ESC[0m" }
                        } else {
                            Write-Log "ESO-Hub Addon ($FNAME) download corrupted." "Error"
                            if (!$SILENT) { Write-Host " $ESC[31m[!] Error: $FNAME.zip download corrupted.$ESC[0m" }
                        }
                    }
                }
            }
        }
        if ($EH_DOWNLOAD_OCCURRED) { $global:EH_LAST_DOWNLOAD = $CURRENT_TIME }
        if ($ehUpdateCount -gt 0 -or $ehUploadCount -gt 0) {
            $notifEH = "Updated ($ehUpdateCount), Uploaded ($ehUploadCount)"
        }
        if (!$SILENT) { Write-Host "" }
    }

    # HARVESTMAP Proccess
    if (!$HAS_HM) {
        $notifHM = "Not Installed (Skipped)"
        if (!$SILENT) {
            Write-Host "$ESC[1m$ESC[97m [4/4] Updating HarvestMap Data (SKIPPED) $ESC[0m"
            Write-Host " $ESC[31m[-] HarvestMap is not installed/enabled in AddOnSettings.txt. $ESC[35mSkipping...$ESC[0m`n"
        }
    } else {
        $HM_DIR = "$ADDON_DIR\HarvestMapData"
        $EMPTY_FILE = "$HM_DIR\Main\emptyTable.lua"
        $MAIN_HM_FILE = "$SAVED_VAR_DIR\HarvestMap.lua"
        $HM_SNAP = "$TARGET_DIR\lttc_hm_main_snapshot.lua"
        
        if (Test-Path $HM_DIR) {
            $HM_CHANGED = $true
            $LOCAL_HM_STATUS = "Out-of-Sync"
            $SRV_HM_STATUS = "Latest"
            
            if (Test-Path $MAIN_HM_FILE) {
                if (Test-Path $HM_SNAP) {
                    $h1 = (Get-FileHash $MAIN_HM_FILE -Algorithm MD5).Hash
                    $h2 = (Get-FileHash $HM_SNAP -Algorithm MD5).Hash
                    if ($h1 -eq $h2) { 
                        $HM_CHANGED = $false 
                        $LOCAL_HM_STATUS = "Synced"
                    }
                }
            }

            $global:HM_LAST_CHECK = $CURRENT_TIME
            $CONFIG_CHANGED = $true

            $V_COL = if (!$HM_CHANGED) {"$ESC[92m"} else {"$ESC[31m"}

            if (!$SILENT) {
                Write-Host "$ESC[1m$ESC[97m [4/4] Updating HarvestMap Data $ESC[0m"
                Write-Host " $ESC[33mVerifying HarvestMap local data state...$ESC[0m"
                Write-Host "`t$ESC[90mServer_Data_Status= $ESC[92m$SRV_HM_STATUS$ESC[0m"
                Write-Host "`t$ESC[90mLocal_Data_Status= ${V_COL}$LOCAL_HM_STATUS$ESC[0m"
            }

            if (!$HM_CHANGED) {
                if (!$SILENT) {
                    Write-Host " $ESC[90mNo changes detected. $ESC[92mHarvestMap.lua is up-to-date. $ESC[35mSkipping process.$ESC[0m`n"
                }
                Send-Live-Update "HarvestMap: Data is up to date. Skipping."
            } else {
                $HM_TIME_DIFF = $CURRENT_TIME - [int]$HM_LAST_DOWNLOAD
                
                if ($HM_TIME_DIFF -lt 3600 -and $HM_TIME_DIFF -ge 0) {
                    $WAIT_MINS = [math]::Floor((3600 - $HM_TIME_DIFF) / 60)
                    $notifHM = "Cooldown ($WAIT_MINS min)"
                    if (!$SILENT) {
                        Write-Host " $ESC[33mHarvestMap local changes detected, but download is on cooldown for $WAIT_MINS more minutes. $ESC[35mSkipping.$ESC[0m`n"
                    }
                } else {
                    Send-Live-Update "HarvestMap: Downloading new zone data..."
                    if (Test-Path $MAIN_HM_FILE) { Copy-Item -Path $MAIN_HM_FILE -Destination $HM_SNAP -Force }
                    if (!(Test-Path $SAVED_VAR_DIR)) { New-Item -ItemType Directory -Force -Path $SAVED_VAR_DIR | Out-Null }
                    
                    $hmFailed = $false
                    foreach ($zone in @("AD", "EP", "DC", "DLC", "NF")) {
                        $svfn1 = "$SAVED_VAR_DIR\HarvestMap${zone}.lua"
                        $svfn2 = "${svfn1}~"
                        
                        if (Test-Path $svfn1) { Move-Item -Path $svfn1 -Destination $svfn2 -Force }
                        else {
                            $name = "Harvest${zone}_SavedVars"
                            if (Test-Path $EMPTY_FILE) {
                                $cnt = Get-Content $EMPTY_FILE -Raw
                                Set-Content -Path $svfn2 -Value "$name$cnt" -NoNewline
                            } else {
                                Set-Content -Path $svfn2 -Value "$name={[`"data`"]={}}" -NoNewline
                            }
                        }
                        
                        $modDir = "$HM_DIR\Modules\HarvestMap${zone}"
                        if (!(Test-Path $modDir)) { New-Item -ItemType Directory -Force -Path $modDir | Out-Null }
                        if (!$SILENT) { Write-Host " $ESC[36mDownloading database chunk to:$ESC[0m $modDir\HarvestMap${zone}.lua" }
                        
                        try {
                            Invoke-WebRequest -Uri "http://harvestmap.binaryvector.net:8081" -Method Post -InFile $svfn2 -OutFile "$modDir\HarvestMap${zone}.lua" -UserAgent $HM_USER_AGENT -ErrorAction Stop
                        } catch {
                            if (!$SILENT) { Write-Host "  $ESC[33m[-] Primary UA blocked. Retrying with fallback UA...$ESC[0m" }
                            try {
                                Invoke-WebRequest -Uri "http://harvestmap.binaryvector.net:8081" -Method Post -InFile $svfn2 -OutFile "$modDir\HarvestMap${zone}.lua" -UserAgent $RAND_UA -ErrorAction Stop
                            } catch {
                                $hmFailed = $true
                            }
                        }
                    }
                    
                    if (!$hmFailed) {
                        $global:HM_LAST_DOWNLOAD = $CURRENT_TIME
                        $CONFIG_CHANGED = $true
                        $notifHM = "Updated successfully"
                        Write-Log "HarvestMap data chunks downloaded successfully." "Information"
                        if (!$SILENT) { Write-Host "`n $ESC[92m[+] HarvestMap Data Successfully Updated.$ESC[0m`n" }
                    } else {
                        $notifHM = "Error (Server Blocked)"
                        Write-Log "HarvestMap Data download blocked by server." "Error"
                    }
                }
            }
        } else {
            $notifHM = "Not Found (Skipped)"
            if (!$SILENT) {
                Write-Host "$ESC[1m$ESC[97m [4/4] Updating HarvestMap Data (SKIPPED) $ESC[0m"
                Write-Host " $ESC[31m[!] HarvestMapData folder not found in: $ADDON_DIR. $ESC[35mSkipping...$ESC[0m`n"
            }
        }
    }

    if ($CONFIG_CHANGED) { save_config }

    if ($TEMP_DIR_USED) {
        if (!$SILENT) {
            Write-Host "$ESC[31mCleaning up temporary files...$ESC[0m"
            Write-Host "$ESC[31mDeleting Temp Directory at: $TEMP_DIR$ESC[0m"
        }
    }
    Set-Location $env:USERPROFILE
    Remove-Item -Path $TEMP_DIR -Recurse -Force -ErrorAction SilentlyContinue
    if ($TEMP_DIR_USED -and !$SILENT) { Write-Host "$ESC[92m[+] Cleanup Complete.$ESC[0m`n" }

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
        Stop-Process -Id $PID -Force 
    }

    if ($IS_STEAM_LAUNCH) {
        if ($SILENT) {
            for ($i=0; $i -lt 360; $i++) {
                Wait-WithEvents 10
                if (!(Get-Process "eso64", "zos", "eso", "Bethesda.net_Launcher" -ErrorAction SilentlyContinue)) {
                    Write-Log "WTTC Updater Terminated (Game Process closed)." "Information"
                    if ($global:IS_TASK -and $script:trayIcon) { $script:trayIcon.Visible = $false }
                    try {
                        $parent = Get-CimInstance Win32_Process -Filter "ProcessId = $PID"
                        if ($parent.ParentProcessId) {
                            $parentProc = Get-Process -Id $parent.ParentProcessId -ErrorAction SilentlyContinue
                            if ($parentProc.Name -eq "cmd") { Stop-Process -Id $parentProc.Id -Force }
                        }
                    } catch {}
                    Stop-Process -Id $PID -Force
                }
            }
        } else {
            Write-Host " $ESC[1;97;101m Restarting Sequence in 60 minutes... (Steam Mode: Auto-Exit on game close) $ESC[0m`n"
            for ($i=3600; $i -gt 0; $i--) {
                $min = [math]::Floor($i / 60); $sec = $i % 60
                Write-Host -NoNewline "`r $ESC[1;97;101m Countdown: ${min}:$($sec.ToString('D2')) $ESC[0m$ESC[0K"
                if ($i % 5 -eq 0) {
                    if (!(Get-Process "eso64", "zos", "eso", "Bethesda.net_Launcher" -ErrorAction SilentlyContinue)) {
                        Write-Host "`n`n $ESC[33mGame closed. Terminating updater...$ESC[0m"
                        Write-Log "WTTC Updater Terminated (Game Process closed)." "Information"
                        Start-Sleep -Seconds 2
                        if ($global:IS_TASK -and $script:trayIcon) { $script:trayIcon.Visible = $false }
                        try {
                            $parent = Get-CimInstance Win32_Process -Filter "ProcessId = $PID"
                            if ($parent.ParentProcessId) {
                                $parentProc = Get-Process -Id $parent.ParentProcessId -ErrorAction SilentlyContinue
                                if ($parentProc.Name -eq "cmd") { Stop-Process -Id $parentProc.Id -Force }
                            }
                        } catch {}
                        Stop-Process -Id $PID -Force
                    }
                }
                Wait-WithEvents 1
            }
        }
    } else {
        if ($SILENT) {
            Wait-WithEvents 3600
        } else {
            Write-Host " $ESC[1;97;101m Restarting Sequence in 60 minutes... (Standalone Mode) $ESC[0m`n"
            for ($i=3600; $i -gt 0; $i--) {
                $min = [math]::Floor($i / 60); $sec = $i % 60
                Write-Host -NoNewline "`r $ESC[1;97;101m Countdown: ${min}:$($sec.ToString('D2')) $ESC[0m$ESC[0K"
                Wait-WithEvents 1
            }
        }
    }
}
