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
