@echo off
setlocal EnableDelayedExpansion

:: ==============================================================================
:: Windows Tamriel Trade Center
:: Created by @APHONIC (Updated)
:: ==============================================================================

:: Initialization
for /F "delims=#" %%E in ('"prompt #$E# & for %%E in (1) do rem"') do set "ESC=%%E"
title Windows Tamriel Trade Center

set "CURRENT_DIR=%~dp0"
if "%CURRENT_DIR:~-1%"=="\" set "CURRENT_DIR=%CURRENT_DIR:~0,-1%"
set "SCRIPT_NAME=%~nx0"

:: Save config globally and game directory
set "GLOBAL_CONFIG=%USERPROFILE%\lttc_updater.ini"
set "GAME_DIR="

if exist "%CURRENT_DIR%\eso64.exe" (
    set "GAME_DIR=%CURRENT_DIR%"
) else (
    for %%D in (C D E F G) do (
        if exist "%%D:\Program Files (x86)\Steam\steamapps\common\Zenimax Online\The Elder Scrolls Online\game\client\eso64.exe" set "GAME_DIR=%%D:\Program Files (x86)\Steam\steamapps\common\Zenimax Online\The Elder Scrolls Online\game\client"
        if exist "%%D:\SteamLibrary\steamapps\common\Zenimax Online\The Elder Scrolls Online\game\client\eso64.exe" set "GAME_DIR=%%D:\SteamLibrary\steamapps\common\Zenimax Online\The Elder Scrolls Online\game\client"
        if exist "%%D:\Zenimax Online\The Elder Scrolls Online\game\client\eso64.exe" set "GAME_DIR=%%D:\Zenimax Online\The Elder Scrolls Online\game\client"
    )
)

if not "!GAME_DIR!"=="" (
    set "CONFIG_FILE=!GAME_DIR!\lttc_updater.ini"
    set "LAST_TIME_FILE=!GAME_DIR!\lttc_last_sale.txt"
    set "LAST_DL_FILE=!GAME_DIR!\lttc_last_download.txt"
    set "ESO_HUB_TRACKER=!GAME_DIR!\lttc_esohub_tracker.txt"
) else (
    set "CONFIG_FILE=!GLOBAL_CONFIG!"
    set "LAST_TIME_FILE=%USERPROFILE%\lttc_last_sale.txt"
    set "LAST_DL_FILE=%USERPROFILE%\lttc_last_download.txt"
    set "ESO_HUB_TRACKER=%USERPROFILE%\lttc_esohub_tracker.txt"
)

:: config migration 
if not exist "!CONFIG_FILE!" (
    if exist "!GLOBAL_CONFIG!" (
        copy /y "!GLOBAL_CONFIG!" "!CONFIG_FILE!" >nul
    )
)

set SILENT=false
set AUTO_PATH=false
set AUTO_SRV=
set AUTO_MODE=
set "ADDON_DIR="
set SETUP_COMPLETE=false
set HAS_ARGS=false

if not "%~1"=="" set HAS_ARGS=true

:: Load Config 
if exist "!CONFIG_FILE!" (
    for /f "usebackq delims== tokens=1,2" %%A in ("!CONFIG_FILE!") do set "%%A=%%B"
) else if exist "!GLOBAL_CONFIG!" (
    for /f "usebackq delims== tokens=1,2" %%A in ("!GLOBAL_CONFIG!") do set "%%A=%%B"
)

:: Ensure GAME_DIR config fallback triggers if loaded from existing config
if not "!INSTALL_DIR!"=="" (
    set "GAME_DIR=!INSTALL_DIR!"
    set "CONFIG_FILE=!GAME_DIR!\lttc_updater.ini"
    set "LAST_TIME_FILE=!GAME_DIR!\lttc_last_sale.txt"
    set "LAST_DL_FILE=!GAME_DIR!\lttc_last_download.txt"
    set "ESO_HUB_TRACKER=!GAME_DIR!\lttc_esohub_tracker.txt"
)

:: user agents
set "UA[0]=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
set "UA[1]=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
set "UA[2]=Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:123.0) Gecko/20100101 Firefox/123.0"
set "UA[3]=Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:123.0) Gecko/20100101 Firefox/123.0"
set "UA[4]=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 Edg/122.0.0.0"
set "UA[5]=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3.1 Safari/605.1.15"
set "UA[6]=Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
set "UA[7]=Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:123.0) Gecko/20100101 Firefox/123.0"
set "UA[8]=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36 OPR/107.0.0.0"
set "UA[9]=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36 OPR/107.0.0.0"

:: Argument Parsing
:parse_args
if "%~1"=="" goto end_args
if /I "%~1"=="--silent" set SILENT=true
if /I "%~1"=="--auto" set AUTO_PATH=true
if /I "%~1"=="--na" set AUTO_SRV=1
if /I "%~1"=="--eu" set AUTO_SRV=2
if /I "%~1"=="--loop" set AUTO_MODE=2
if /I "%~1"=="--once" set AUTO_MODE=1
if /I "%~1"=="--addon-dir" (
    set "ADDON_DIR=%~2"
    shift
)
shift
goto parse_args
:end_args

:: Launch Check
if "!INSTALL_DIR!"=="" set "INSTALL_DIR=!GAME_DIR!"

if "%SETUP_COMPLETE%"=="true" if "%HAS_ARGS%"=="false" (
    if exist "!INSTALL_DIR!\%SCRIPT_NAME%" if exist "!INSTALL_DIR!\lttc_updater.ini" goto AskRerun
)
if "%SETUP_COMPLETE%"=="false" if "%HAS_ARGS%"=="false" goto RunSetup
goto StartLoop

:AskRerun
cls
echo %ESC%[0;32m[+] Configuration found! Using saved settings.%ESC%[0m
echo -^> Press 'Y' to re-run setup, or wait 5 seconds to continue automatically...
choice /C YN /N /T 5 /D N /M "Setup done, do you want to re-run setup? (y/N): "
if errorlevel 2 goto StartLoop
if errorlevel 1 goto RunSetup
goto StartLoop

:RunSetup
cls
echo.
echo %ESC%[0;33m--- Initial Setup ^& Configuration ---%ESC%[0m
echo Scanning for Game Directory across drives...
set "INSTALL_DIR="

for %%D in (C D E F G) do (
    if exist "%%D:\Program Files (x86)\Steam\steamapps\common\Zenimax Online\The Elder Scrolls Online\game\client\eso64.exe" (
        set "INSTALL_DIR=%%D:\Program Files (x86)\Steam\steamapps\common\Zenimax Online\The Elder Scrolls Online\game\client"
        goto FoundInstallDir
    )
    if exist "%%D:\SteamLibrary\steamapps\common\Zenimax Online\The Elder Scrolls Online\game\client\eso64.exe" (
        set "INSTALL_DIR=%%D:\SteamLibrary\steamapps\common\Zenimax Online\The Elder Scrolls Online\game\client"
        goto FoundInstallDir
    )
    if exist "%%D:\Zenimax Online\The Elder Scrolls Online\game\client\eso64.exe" (
        set "INSTALL_DIR=%%D:\Zenimax Online\The Elder Scrolls Online\game\client"
        goto FoundInstallDir
    )
)

echo %ESC%[0;31m[-] Could not locate eso64.exe automatically.%ESC%[0m
set /p manual_dir="Enter the full path to your game client folder: "
set "manual_dir=!manual_dir:"=!"
if exist "!manual_dir!\eso64.exe" (
    set "INSTALL_DIR=!manual_dir!"
) else (
    echo %ESC%[0;31m[!] Error: eso64.exe not found. Setup aborted.%ESC%[0m
    pause
    exit /b 1
)

:FoundInstallDir
echo %ESC%[0;32m[+] Found Game Directory at:%ESC%[0m !INSTALL_DIR!
set /p use_install="Is this the correct location? (y/n): "
if /I not "!use_install!"=="y" (
    set /p INSTALL_DIR="Please manually enter the full path to your game client folder: "
    set "INSTALL_DIR=!INSTALL_DIR:"=!"
)

if not "!CONFIG_FILE!"=="!INSTALL_DIR!\lttc_updater.ini" (
    copy /y "!CONFIG_FILE!" "!INSTALL_DIR!\lttc_updater.ini" >nul 2>nul
    set "CONFIG_FILE=!INSTALL_DIR!\lttc_updater.ini"
    set "LAST_TIME_FILE=!INSTALL_DIR!\lttc_last_sale.txt"
    set "LAST_DL_FILE=!INSTALL_DIR!\lttc_last_download.txt"
    set "ESO_HUB_TRACKER=!INSTALL_DIR!\lttc_esohub_tracker.txt"
)

if /I "%CURRENT_DIR%"=="!INSTALL_DIR!" (
    echo %ESC%[0;36m-^> Script is already running from the game directory. Skipping copy step.%ESC%[0m
) else if exist "!INSTALL_DIR!\%SCRIPT_NAME%" (
    echo %ESC%[0;36m-^> Script already exists in the game directory. Skipping copy step.%ESC%[0m
) else (
    set /p copy_script="Do you want to copy this script to your game directory (!INSTALL_DIR!) for Steam Launch Options? (y/n): "
    if /I "!copy_script!"=="y" (
        copy /y "%~f0" "!INSTALL_DIR!\%SCRIPT_NAME%" >nul
        echo %ESC%[0;32m[+] Script copied to:%ESC%[0m !INSTALL_DIR!
    )
)

echo.
echo %ESC%[0;33m1. Which server do you play on? (For TTC Pricing)%ESC%[0m
echo 1^) North America ^(NA^)
echo 2^) Europe ^(EU^)
set /p AUTO_SRV="Choice [1-2]: "

echo.
echo %ESC%[0;33m2. Do you want the terminal to be visible when launching via Steam?%ESC%[0m
echo 1^) Show Terminal ^(Verbose output^)
echo 2^) Hide Terminal ^(Silent background mode^)
set /p term_choice="Choice [1-2]: "
if "!term_choice!"=="2" (set SILENT=true) else (set SILENT=false)

echo.
echo %ESC%[0;33m3. How should the script run during gameplay?%ESC%[0m
echo 1^) Run once and close immediately
echo 2^) Loop continuously ^(Every 60 mins to avoid rate-limit^)
set /p AUTO_MODE="Choice [1-2]: "

echo.
echo %ESC%[0;33m4. Addon Folder Location%ESC%[0m
echo Scanning for Addons folder...
set "FOUND_ADDONS="

if exist "%USERPROFILE%\Documents\Elder Scrolls Online\live\AddOns" (
    set "FOUND_ADDONS=%USERPROFILE%\Documents\Elder Scrolls Online\live\AddOns"
) else if exist "%USERPROFILE%\OneDrive\Documents\Elder Scrolls Online\live\AddOns" (
    set "FOUND_ADDONS=%USERPROFILE%\OneDrive\Documents\Elder Scrolls Online\live\AddOns"
) else if exist "%PUBLIC%\Documents\Elder Scrolls Online\live\AddOns" (
    set "FOUND_ADDONS=%PUBLIC%\Documents\Elder Scrolls Online\live\AddOns"
) else (
    for %%D in (C D E F G) do (
        if exist "%%D:\Elder Scrolls Online\live\AddOns" set "FOUND_ADDONS=%%D:\Elder Scrolls Online\live\AddOns"
    )
)

if not "!FOUND_ADDONS!"=="" (
    echo %ESC%[0;32m[+] Found Addons at:%ESC%[0m !FOUND_ADDONS!
    set /p use_found="Is this the correct location? (y/n): "
    if /I "!use_found!"=="y" (
        set "ADDON_DIR=!FOUND_ADDONS!"
    ) else (
        set /p ADDON_DIR="Enter full custom path to AddOns: "
    )
) else (
    echo %ESC%[0;31m[-] Could not automatically find AddOns.%ESC%[0m
    set /p ADDON_DIR="Enter full custom path: "
)
set "ADDON_DIR=!ADDON_DIR:"=!"

:: Save Config Globally
echo INSTALL_DIR=!INSTALL_DIR!> "!CONFIG_FILE!"
echo AUTO_SRV=!AUTO_SRV!>> "!CONFIG_FILE!"
echo SILENT=!SILENT!>> "!CONFIG_FILE!"
echo AUTO_MODE=!AUTO_MODE!>> "!CONFIG_FILE!"
echo ADDON_DIR=!ADDON_DIR!>> "!CONFIG_FILE!"
echo SETUP_COMPLETE=true>> "!CONFIG_FILE!"

copy /y "!CONFIG_FILE!" "!GLOBAL_CONFIG!" >nul 2>nul

echo.
echo %ESC%[0;33m5. Desktop Shortcut%ESC%[0m
set /p make_shortcut="Create a desktop shortcut? (y/n): "

set "SHORTCUT_SRV_FLAG=--na"
if "!AUTO_SRV!"=="2" set "SHORTCUT_SRV_FLAG=--eu"
set "SILENT_FLAG="
if "!SILENT!"=="true" set "SILENT_FLAG=--silent"
set "LOOP_FLAG=--once"
if "!AUTO_MODE!"=="2" set "LOOP_FLAG=--loop"

if /I "!make_shortcut!"=="y" (
    set "ICON_PATH=!INSTALL_DIR!\ttc_icon.ico"
    echo  -^> Downloading TTC favicon from https://us.tamrieltradecentre.com/favicon.ico
    curl -s -L -o "!ICON_PATH!" "https://us.tamrieltradecentre.com/favicon.ico"

    set "SHORTCUT_PATH=%USERPROFILE%\Desktop\Windows Tamriel Trade Center.lnk"
    powershell -Command "$wshell = New-Object -ComObject WScript.Shell; $s = $wshell.CreateShortcut('!SHORTCUT_PATH!'); $s.TargetPath = '!INSTALL_DIR!\%SCRIPT_NAME%'; $s.Arguments = '!SILENT_FLAG! !SHORTCUT_SRV_FLAG! !LOOP_FLAG! --addon-dir ""!ADDON_DIR!""'; $s.IconLocation = '!ICON_PATH!'; $s.Save()"
    if "!SILENT!"=="true" powershell -Command "$wshell = New-Object -ComObject WScript.Shell; $s = $wshell.CreateShortcut('!SHORTCUT_PATH!'); $s.WindowStyle = 7; $s.Save()"
    echo %ESC%[0;32m[+] Windows shortcut installed to Desktop.%ESC%[0m
)

echo.
echo %ESC%[0;92m================ SETUP COMPLETE ================%ESC%[0m
echo To run this automatically alongside your game, copy this string into your %ESC%[1mSteam Launch Options%ESC%[0m:
echo.
if "!SILENT!"=="true" (
    set "LAUNCH_CMD=cmd /c start /min """" ""!INSTALL_DIR!\%SCRIPT_NAME%"" !SILENT_FLAG! !SHORTCUT_SRV_FLAG! !LOOP_FLAG! --addon-dir ""!ADDON_DIR!"" ^& %%command%%"
    echo %ESC%[0;104m !LAUNCH_CMD! %ESC%[0m
) else (
    set "LAUNCH_CMD=cmd /c start """" ""!INSTALL_DIR!\%SCRIPT_NAME%"" !SHORTCUT_SRV_FLAG! !LOOP_FLAG! --addon-dir ""!ADDON_DIR!"" ^& %%command%%"
    echo %ESC%[0;104m !LAUNCH_CMD! %ESC%[0m
)
echo.

echo %ESC%[0;33m6. Steam Launch Options%ESC%[0m
echo Would you like this script to automatically inject the Launch Command into your Steam configuration?
echo (WARNING: Steam MUST be closed to do this. We can close it for you.)
set /p auto_steam="Apply automatically? (y/n): "
if /I "!auto_steam!"=="y" (
    tasklist /FI "IMAGENAME eq steam.exe" 2>NUL | find /I /N "steam.exe">NUL
    if !ERRORLEVEL! EQU 0 (
        echo %ESC%[0;33m[!] Steam is running. Closing Steam to safely inject options...%ESC%[0m
        taskkill /F /IM steam.exe >nul
        timeout /t 5 >nul
    )
    
    set "LAUNCH_STR=!LAUNCH_CMD!"
    powershell -NoProfile -Command "$steamPath = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath; if (-not $steamPath) { $steamPath = 'C:\Program Files (x86)\Steam' }; $configPaths = Get-ChildItem -Path \"$steamPath\userdata\*\config\localconfig.vdf\" -ErrorAction SilentlyContinue; foreach ($config in $configPaths) { Copy-Item $config.FullName \"$($config.FullName).bak\"; $content = Get-Content $config.FullName -Raw; $ls = $env:LAUNCH_STR.Replace('\x22', '\x5C\x22'); if ($content -match '(\x22306130\x22\s*\{)') { if ($content -match '(\x22306130\x22\s*\{[^\}]*)\x22LaunchOptions\x22\s*\x22[^\x22]*\x22') { $content = $content -replace '(\x22306130\x22\s*\{[^\}]*)\x22LaunchOptions\x22\s*\x22[^\x22]*\x22', \"`$1`\x22LaunchOptions`\x22`t`t`\x22$ls`\x22\" } else { $content = $content -replace '(\x22306130\x22\s*\{)', \"`$1`n`t`t`t`t`\x22LaunchOptions`\x22`t`t`\x22$ls`\x22\" } } else { $content = $content -replace '(\x22apps\x22\s*\{)', \"`$1`n`t`t`t`\x22306130`\x22`n`t`t`t{`n`t`t`t`t`\x22LaunchOptions`\x22`t`t`\x22$ls`\x22`n`t`t`t}\" }; Set-Content -Path $config.FullName -Value $content -NoNewline; Write-Host \"`e[0;32m[+] Successfully injected Launch Options into Steam!`e[0m\" }"
    
    echo %ESC%[0;33m[!] Restarting Steam...%ESC%[0m
    start "" "steam://open/main"
)
echo.
pause
goto StartLoop

:: Execution
:StartLoop
set "SAVED_VAR_DIR=!ADDON_DIR!\..\SavedVariables"
set "TEMP_DIR=%USERPROFILE%\Downloads\Windows_Tamriel_Trade_Center_Temp"
set "ESO_HUB_TRACKER=!INSTALL_DIR!\lttc_esohub_tracker.txt"

if "%AUTO_SRV%"=="1" (set "TTC_DOMAIN=us.tamrieltradecentre.com") else (set "TTC_DOMAIN=eu.tamrieltradecentre.com")
set "TTC_URL=https://!TTC_DOMAIN!/download/PriceTable"

:main_loop
if "%SILENT%"=="false" (
    cls
    echo %ESC%[0;92m==================================================%ESC%[0m
    echo %ESC%[1m%ESC%[0;94m           Windows Tamriel Trade Center%ESC%[0m
    echo %ESC%[0;92m==================================================%ESC%[0m
    echo %ESC%[0;35mTarget AddOn Directory: !ADDON_DIR!%ESC%[0m
    echo.
)

if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%"
cd /d "%TEMP_DIR%" || exit /b 1

set /a RAND_IDX=%RANDOM% %% 10
for %%j in (!RAND_IDX!) do set "RAND_UA=!UA[%%j]!"

:: UPLOAD TTC DATA
if "%SILENT%"=="false" echo %ESC%[0;104m%ESC%[1m%ESC%[0;97m [1/4] Uploading your Local TTC Data to TTC Server %ESC%[0m
if exist "!SAVED_VAR_DIR!\TamrielTradeCentre.lua" (
    if "%SILENT%"=="false" (
        echo %ESC%[0;36mExtracting recent sales data from Lua (Showing up to 30 recent entries)...%ESC%[0m
        powershell -NoProfile -Command "$path='!SAVED_VAR_DIR!\TamrielTradeCentre.lua'; $timeFile='!LAST_TIME_FILE!'; $lastTime=0; if(Test-Path $timeFile){ [int]::TryParse((Get-Content $timeFile | Select-Object -First 1), [ref]$lastTime) | Out-Null }; $maxTime=$lastTime; if(Test-Path $path){ $lines=Get-Content $path; $out=@(); $a=''; $n=''; $p=''; $q=''; $t=''; foreach($l in $lines){ if($l -match '\[\x22Amount\x22\]\s*=\s*(\d+)'){ $a=$matches[1] } elseif($l -match '\[\x22QualityID\x22\]\s*=\s*(\d+)'){ $q=$matches[1] } elseif($l -match '\[\x22SaleTime\x22\]\s*=\s*(\d+)'){ $t=$matches[1] } elseif($l -match '\[\x22TotalPrice\x22\]\s*=\s*(\d+)'){ $p=$matches[1] } elseif($l -match '\[\x22Name\x22\]\s*=\s*\x22([^\x22]+)'){ $n=$matches[1] } elseif($l -match '\}'){ if($n -and $p){ if([long]$t -gt $maxTime){ $maxTime=[long]$t }; if([long]$t -gt $lastTime){ $c='\e[0m'; if($q -eq '0'){ $c='\e[90m' } elseif($q -eq '1'){ $c='\e[97m' } elseif($q -eq '2'){ $c='\e[32m' } elseif($q -eq '3'){ $c='\e[36m' } elseif($q -eq '4'){ $c='\e[35m' } elseif($q -eq '5'){ $c='\e[33m' } elseif($q -eq '6'){ $c='\e[38;5;214m' }; $c=$c -replace '\\e',[char]27; $esc=[char]27; $out += \" for $esc[32m$p$esc[33mgold$esc[0m - $esc[32m${a}x$esc[0m $c$n$esc[0m\" }; $a=''; $n=''; $p=''; $q=''; $t='' } } }; $c=$out.Count; if($c -gt 0){ $start=0; if($c -gt 30){$start=$c-30}; for($i=$start; $i -lt $c; $i++){ Write-Host $out[$i] } } else { $esc=[char]27; Write-Host \" $esc[90mNo new sales found since last upload.$esc[0m\" }; if($maxTime -gt $lastTime){ Set-Content -Path $timeFile -Value $maxTime } }"
        echo.
        echo %ESC%[0;36mUploading to:%ESC%[0m https://!TTC_DOMAIN!/pc/Trade/WebClient/Upload
    )
    
    curl -s -A "!RAND_UA!" -H "Accept: text/html,application/xhtml+xml,application/xml" -F "SavedVarFileInput=@!SAVED_VAR_DIR!\TamrielTradeCentre.lua" "https://!TTC_DOMAIN!/pc/Trade/WebClient/Upload" >nul
    
    if "%SILENT%"=="false" echo %ESC%[0;92m[+] Upload finished.%ESC%[0m
    if "%SILENT%"=="false" echo.
) else (
    if "%SILENT%"=="false" echo %ESC%[0;33m[-] No TamrielTradeCentre.lua found. Skipping upload.%ESC%[0m
    if "%SILENT%"=="false" echo.
)

:: DOWNLOAD TTC DATA
set "LAST_DL_TIME=0"
if exist "!LAST_DL_FILE!" (
    set /p LAST_DL_TIME=<"!LAST_DL_FILE!"
)

for /f "usebackq tokens=1,2" %%A in (`powershell -NoProfile -Command "$current=[int][double]::Parse((Get-Date (Get-Date).ToUniversalTime() -UFormat '%%s')); $last=0; if(Test-Path '!LAST_DL_FILE!'){ [int]::TryParse((Get-Content '!LAST_DL_FILE!' | Select-Object -First 1), [ref]$last) | Out-Null }; $diff=$current - $last; if ($diff -lt 3600 -and $diff -ge 0) { Write-Output ('SKIP ' + [math]::Floor((3600-$diff)/60)) } else { Write-Output ('RUN ' + $current) }"`) do (
    set "DL_ACTION=%%A"
    set "DL_VAL=%%B"
)

if "!DL_ACTION!"=="SKIP" (
    if "%SILENT%"=="false" echo %ESC%[0;104m%ESC%[1m%ESC%[0;97m [2/4] Updating your Local TTC Data (SKIPPED) %ESC%[0m
    if "%SILENT%"=="false" echo %ESC%[0;33mAlready downloaded within the last hour. Please wait !DL_VAL! more minutes to avoid spam.%ESC%[0m
    if "%SILENT%"=="false" echo.
) else (
    if "%SILENT%"=="false" echo %ESC%[0;104m%ESC%[1m%ESC%[0;97m [2/4] Updating your Local TTC Data %ESC%[0m
    if "%SILENT%"=="false" echo %ESC%[0;36mDownloading from:%ESC%[0m %TTC_URL%
    if "%SILENT%"=="false" echo %ESC%[0;36mDropping zip temporarily to:%ESC%[0m %TEMP_DIR%\Windows_Tamriel_Trade_Center-TTC-data.zip

    set SUCCESS=false
    set /a START_IDX=%RANDOM% %% 10
    
    for /L %%i in (0,1,9) do (
        if "!SUCCESS!"=="false" (
            set /a "CUR_IDX=(START_IDX + %%i) %% 10"
            for %%j in (!CUR_IDX!) do set "CURRENT_UA=!UA[%%j]!"
            if "%SILENT%"=="false" echo %ESC%[0;36mAttempting download with random User-Agent...%ESC%[0m
            
            :: Headers
            curl -H "User-Agent: !CURRENT_UA!" -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8" -H "Accept-Language: en-US,en;q=0.5" -H "Connection: keep-alive" -H "Upgrade-Insecure-Requests: 1" -H "Sec-Fetch-Dest: document" -H "Sec-Fetch-Mode: navigate" -H "Sec-Fetch-Site: none" -H "Sec-Fetch-User: ?1" -# -L -o Windows_Tamriel_Trade_Center-TTC-data.zip "%TTC_URL%"

            tar -tf Windows_Tamriel_Trade_Center-TTC-data.zip >nul 2>&1
            if !ERRORLEVEL! EQU 0 (
                set SUCCESS=true
            ) else (
                if "%SILENT%"=="false" echo %ESC%[0;33m[-] Download failed or blocked. Trying another User-Agent...%ESC%[0m
            )
        )
    )

    echo !DL_VAL!> "!LAST_DL_FILE!"

    if "!SUCCESS!"=="true" (
        if "%SILENT%"=="false" echo %ESC%[0;36mExtracting archive and copying files to:%ESC%[0m !ADDON_DIR!\TamrielTradeCentre
        if not exist "!ADDON_DIR!\TamrielTradeCentre" mkdir "!ADDON_DIR!\TamrielTradeCentre"
        tar -xf Windows_Tamriel_Trade_Center-TTC-data.zip -C "!ADDON_DIR!\TamrielTradeCentre"
        if "%SILENT%"=="false" echo %ESC%[0;92m[+] TTC Data Successfully Updated.%ESC%[0m
        if "%SILENT%"=="false" echo.
    ) else (
        if "%SILENT%"=="false" echo %ESC%[0;31m[!] Error: All User-Agents failed. TTC Data download was blocked by the server, Please try again later.%ESC%[0m
        if "%SILENT%"=="false" echo.
    )
)

:: ESO HUB
for /f "usebackq delims=" %%I in (`powershell -Command "$d=Get-Date; if ($d.DayOfWeek -eq 'Monday' -and $d.Hour -lt 12) { $d=$d.AddDays(-1) }; $w= [cultureinfo]::InvariantCulture.Calendar.GetWeekOfYear($d, [reflection.cultureinfo]::InvariantCulture.DateTimeFormat.CalendarWeekRule, [dayofweek]::Monday); '{0}-W{1:D2}' -f $d.Year, $w"`) do set "CURRENT_ESO_HUB_WEEK=%%I"

set "LAST_ESO_HUB_WEEK="
if exist "!ESO_HUB_TRACKER!" set /p LAST_ESO_HUB_WEEK=<"!ESO_HUB_TRACKER!"

if not "!CURRENT_ESO_HUB_WEEK!"=="!LAST_ESO_HUB_WEEK!" (
    if "%SILENT%"=="false" echo %ESC%[0;104m%ESC%[1m%ESC%[0;97m [3/4] Updating ESO-Hub Prices %ESC%[0m
    if "%SILENT%"=="false" echo %ESC%[0;36mDownloading from:%ESC%[0m https://www.esoui.com/downloads/dl4095/
    if "%SILENT%"=="false" echo %ESC%[0;36mDropping zip temporarily to:%ESC%[0m %TEMP_DIR%\Windows_Tamriel_Trade_Center-ESOHUb-data.zip
    
    set HUB_SUCCESS=false
    set /a START_IDX=%RANDOM% %% 10
    
    for /L %%i in (0,1,9) do (
        if "!HUB_SUCCESS!"=="false" (
            set /a "CUR_IDX=(START_IDX + %%i) %% 10"
            for %%j in (!CUR_IDX!) do set "CURRENT_UA=!UA[%%j]!"
            
            curl -# -L -A "!CURRENT_UA!" -o Windows_Tamriel_Trade_Center-ESOHUb-data.zip "https://www.esoui.com/downloads/dl4095/"
            
            tar -tf Windows_Tamriel_Trade_Center-ESOHUb-data.zip >nul 2>&1
            if !ERRORLEVEL! EQU 0 (
                set HUB_SUCCESS=true
            ) else (
                if "%SILENT%"=="false" echo %ESC%[0;33m[-] Download failed or corrupted. Trying another User-Agent...%ESC%[0m
            )
        )
    )

    if "!HUB_SUCCESS!"=="true" (
        if "%SILENT%"=="false" echo %ESC%[0;36mExtracting archive and copying files to:%ESC%[0m !ADDON_DIR!
        tar -xf Windows_Tamriel_Trade_Center-ESOHUb-data.zip -C "!ADDON_DIR!"
        echo !CURRENT_ESO_HUB_WEEK!> "!ESO_HUB_TRACKER!"
        if "%SILENT%"=="false" echo %ESC%[0;92m[+] ESO-Hub Prices Successfully Updated.%ESC%[0m
        if "%SILENT%"=="false" echo.
    ) else (
        if "%SILENT%"=="false" echo %ESC%[0;31m[!] Error: All User-Agents failed. ESO-Hub Prices download failed or was corrupted.%ESC%[0m
        if "%SILENT%"=="false" echo.
    )
) else (
    if "%SILENT%"=="false" echo %ESC%[0;104m%ESC%[1m%ESC%[0;97m [3/4] Updating ESO-Hub Prices (SKIPPED) %ESC%[0m
    if "%SILENT%"=="false" echo %ESC%[0;33mAlready matches ESOUI schedule. Next check after Monday 12:00 PM.%ESC%[0m
    if "%SILENT%"=="false" echo.
)

:: HARVESTMAP
set "HM_DIR=!ADDON_DIR!\HarvestMapData"
set "EMPTY_FILE=!HM_DIR!\Main\emptyTable.lua"

if exist "!HM_DIR!" (
    if "%SILENT%"=="false" echo %ESC%[0;104m%ESC%[1m%ESC%[0;97m [4/4] Updating HarvestMap Data %ESC%[0m
    if not exist "!SAVED_VAR_DIR!" mkdir "!SAVED_VAR_DIR!"
    
    for %%z in (AD EP DC DLC NF) do (
        set "svfn1=!SAVED_VAR_DIR!\HarvestMap%%z.lua"
        set "svfn2=!SAVED_VAR_DIR!\HarvestMap%%z.lua~"
        
        if exist "!svfn1!" (
            move /y "!svfn1!" "!svfn2!" >nul
        ) else (
            if exist "!EMPTY_FILE!" (
                echo Harvest%%z_SavedVars> "!svfn2!"
                type "!EMPTY_FILE!" >> "!svfn2!"
            ) else (
                echo Harvest%%z_SavedVars={["data"]={}} > "!svfn2!"
            )
        )
        
        if not exist "!HM_DIR!\Modules\HarvestMap%%z" mkdir "!HM_DIR!\Modules\HarvestMap%%z"
        if "%SILENT%"=="false" echo %ESC%[0;36mDownloading database chunk to:%ESC%[0m !HM_DIR!\Modules\HarvestMap%%z\HarvestMap%%z.lua
        curl -f -s -L -A "!RAND_UA!" -d @"!svfn2!" -o "!HM_DIR!\Modules\HarvestMap%%z\HarvestMap%%z.lua" "http://harvestmap.binaryvector.net:8081"
    )
    if "%SILENT%"=="false" echo. & echo %ESC%[0;92m[+] HarvestMap Data Successfully Updated.%ESC%[0m
    if "%SILENT%"=="false" echo.
) else (
    if "%SILENT%"=="false" echo %ESC%[0;104m%ESC%[1m%ESC%[0;97m [4/4] Updating HarvestMap Data (SKIPPED) %ESC%[0m
    if "%SILENT%"=="false" echo %ESC%[0;31m[!] HarvestMapData folder not found in: !ADDON_DIR!. Skipping...%ESC%[0m
    if "%SILENT%"=="false" echo.
)

:: Cleanup
if "%SILENT%"=="false" echo %ESC%[0;33mCleaning up temporary files...%ESC%[0m
cd /d "%USERPROFILE%"
if "%SILENT%"=="false" echo %ESC%[0;36mDeleting Temp Directory and all downloaded zips at:%ESC%[0m %TEMP_DIR%
rmdir /s /q "%TEMP_DIR%"
if "%SILENT%"=="false" echo %ESC%[0;92m[+] Cleanup Complete.%ESC%[0m
if "%SILENT%"=="false" echo.

if "%AUTO_MODE%"=="1" exit /b 0

if "%SILENT%"=="true" (
    for /L %%i in (1,1,360) do (
        timeout /t 10 /nobreak >nul
        tasklist /FI "IMAGENAME eq eso64.exe" 2>NUL | find /I /N "eso64.exe">NUL
        if errorlevel 1 exit /b 0
    )
) else (
    echo %ESC%[0;101m Restarting Sequence in 60 minutes... %ESC%[0m
    echo.
    for /L %%i in (3600,-1,1) do (
        set /a "min=%%i/60", "sec=%%i%%60"
        if !sec! LSS 10 set "sec=0!sec!"
        <nul set /p "=%ESC%[0G%ESC%[0;101m%ESC%[1m%ESC%[0;94m Countdown: !min!:!sec!%ESC%[0K"
        
        set /a "check=%%i%%5"
        if !check!==0 (
            tasklist /FI "IMAGENAME eq eso64.exe" 2>NUL | find /I /N "eso64.exe">NUL
            if errorlevel 1 (
                echo.
                echo %ESC%[0;33mGame closed. Terminating updater...%ESC%[0m
                timeout /t 2 /nobreak >nul
                exit /b 0
            )
        )
        timeout /t 1 /nobreak >nul
    )
    echo.
)

goto main_loop
