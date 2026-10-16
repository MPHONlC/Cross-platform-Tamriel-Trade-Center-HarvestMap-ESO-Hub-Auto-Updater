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
