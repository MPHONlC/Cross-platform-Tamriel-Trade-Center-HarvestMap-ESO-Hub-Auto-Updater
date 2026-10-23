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

