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

