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

