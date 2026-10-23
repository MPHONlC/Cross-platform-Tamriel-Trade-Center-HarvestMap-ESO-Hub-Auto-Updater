function Get-VersionDiff($old, $new) {
    $old = "$old"; $new = "$new"
    $no = $old.Length; $nn = $new.Length; $min = [Math]::Min($no, $nn)
    $pre = 0; while ($pre -lt $min -and $old[$pre] -ceq $new[$pre]) { $pre++ }
    $suf = 0; while ($suf -lt ($min - $pre) -and $old[$no - 1 - $suf] -ceq $new[$nn - 1 - $suf]) { $suf++ }
    $opre = $old.Substring(0, $pre)
    $omid = $old.Substring($pre, $no - $pre - $suf)
    $osuf = $old.Substring($no - $suf)
    $nmid = $new.Substring($pre, $nn - $pre - $suf)
    return "$ESC[0m$opre$ESC[31m$omid$ESC[0m$osuf $ESC[90m->$ESC[0m $ESC[0m$opre$ESC[92m$nmid$ESC[0m$osuf"
}

function Get-AgeShort($s) {
    $s = [long]$s; if ($s -lt 0) { $s = 0 }
    if ($s -ge 86400) { return "$([long][math]::Floor($s / 86400))d $([long][math]::Floor(($s % 86400) / 3600))h" }
    elseif ($s -ge 3600) { return "$([long][math]::Floor($s / 3600))h $([long][math]::Floor(($s % 3600) / 60))m" }
    elseif ($s -ge 60) { return "$([long][math]::Floor($s / 60))m" }
    else { return "${s}s" }
}

function Get-SizeHuman($b) {
    $b = [long]$b
    if ($b -ge 1048576) { return "$([long][math]::Floor($b / 1048576)).$([long][math]::Floor(($b % 1048576) * 10 / 1048576)) MB" }
    elseif ($b -ge 1024) { return "$([long][math]::Floor($b / 1024)).$([long][math]::Floor(($b % 1024) * 10 / 1024)) KB" }
    else { return "$b B" }
}

function Get-HistoryUidCount($path) {
    if (!$path -or !(Test-Path -LiteralPath $path)) { return 0 }
    $seen = @{}; $c = 0
    foreach ($line in [System.IO.File]::ReadAllLines($path)) {
        $f = $line.Split('|')
        if ($f[0] -ne "HISTORY") { continue }
        $nf = $f.Length
        $src = if ($f[$nf - 1] -match '^[0-9]+$') { $f[$nf - 2] } else { $f[$nf - 1] }
        if ($src -match '^(Unknown|\[Unknown\])$' -or $src -eq "") { $src = "TTC" }
        $u = "$($f[5])|$($f[2])|$($f[3])|$($f[4])|$src"
        if (!$seen.ContainsKey($u)) { $seen[$u] = 1; $c++ }
    }
    return $c
}
