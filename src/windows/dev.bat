@echo off
setlocal
set "LTTC_SRC=%~dp0"
set "LTTC_DEV=1"
set "SCRIPT_FULL_PATH=%~dp0..\..\dist\Windows_Tamriel_Trade_Center.bat"
set "PS_ARGS=%*"
powershell -Sta -NoProfile -ExecutionPolicy Bypass -Command "$sb = [ScriptBlock]::Create((Get-Content -LiteralPath '%~dp0main.ps1' -Raw)); & $sb"
if %errorlevel% neq 0 pause
exit /b %errorlevel%
