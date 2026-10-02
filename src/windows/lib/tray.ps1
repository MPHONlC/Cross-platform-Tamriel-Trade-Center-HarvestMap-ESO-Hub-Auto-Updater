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

