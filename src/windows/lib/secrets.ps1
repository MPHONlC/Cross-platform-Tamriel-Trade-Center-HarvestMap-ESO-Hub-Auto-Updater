function Protect-Secret($v) {
    if (!$v) { return "" }
    if ("$v" -match '^ENC1:') { return $v }
    try {
        Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
        $bytes = [System.Text.Encoding]::UTF8.GetBytes("$v")
        $enc = [System.Security.Cryptography.ProtectedData]::Protect($bytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        return "ENC1:" + [Convert]::ToBase64String($enc)
    } catch { return "$v" }
}

function Unprotect-Secret($v) {
    if (!$v) { return "" }
    if ("$v" -notmatch '^ENC1:') { return "$v" }
    try {
        Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
        $enc = [Convert]::FromBase64String("$v".Substring(5))
        $bytes = [System.Security.Cryptography.ProtectedData]::Unprotect($enc, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        return [System.Text.Encoding]::UTF8.GetString($bytes)
    } catch { return "" }
}
