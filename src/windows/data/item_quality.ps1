function Get-HQ($q) {
    if($q -eq 6) { return "Mythic (Orange) 6" }; if($q -eq 5) { return "Legendary (Gold) 5" }; if($q -eq 4) { return "Epic (Purple) 4" }
    if($q -eq 3) { return "Superior (Blue) 3" }; if($q -eq 2) { return "Fine (Green) 2" }; if($q -eq 1) { return "Normal (White) 1" }
    return "Trash (Grey) 0"
}

function Get-Cat($n, $i, $s, $v) {
    $ln = $n.ToLower()
    if($ln -match 'motif') { return "Crafting Motif" }
    if($ln -match 'blueprint|praxis|design|pattern|formula|diagram|sketch') { return "Furniture Plan" }
    if($ln -match 'style page|runebox') { return "Style/Collectible" }
    if($ln -match 'tea blends of tamriel|tin of high isle taffy|assorted stolen shiny trinkets|lightly used fiddle|stuffed bear|grisly trophy|companion gift') { return "Companion Gift" }
    if($v -gt 1 -or $s -ge 20) { return "Equipment (Armor/Weapon)" }
    return "Materials/Misc"
}

function Calc-Quality($id, $name, $s, $v) {
    $ln = $name.ToLower()
    if ($id -match '^(165899|187648|171437|165910|175510|181971|181961|175402|184206|191067)$') { return 6 }
    if ($ln -match 'citation|truly superb glyph|tempering alloy|dreugh wax|rosin|kuta|perfect roe|aetherial dust|chromium plating|style page:|runebox:|research scroll|psijic ambrosia|indoril inks:') { return 5 }
    if ($ln -match 'master .* writ') { return 4 }
    if ($ln -match 'unknown .* writ|welkynar binding|rekuta|grain solvent|mastic|elegant lining|zircon plating|potent nirncrux|fortified nirncrux|culanda lacquer|harvested soul fragment') { return 4 }
    if ($ln -match 'tea blends of tamriel|twenty-year ruby port|assorted stolen shiny trinkets|lightly used fiddle|stuffed bear|grisly trophy|companion gift|tin of high isle taffy|angler''s knife set|dried fish biscuits|beginner''s bowfishing kit') { return 3 }
    if ($ln -match 'survey report|dwarven oil|turpen|embroidery|iridium plating|treasure map|bervez juice|frost mirriam') { return 3 }
    if ($ln -match 'hemming|honing stone|pitch|terne plating|soul gem') { return 2 }
    if ($ln -match '^(recipe|design|blueprint|pattern|praxis|formula|diagram|sketch):') {
        if($s -eq 6) { return 5 }; if($s -eq 5) { return 4 }; if($s -eq 4) { return 3 }; if($s -eq 3) { return 2 }; return 1
    }
    if ($s -ge 2 -and $s -le 6) { return $s - 1 }; if ($s -ge 20 -and $s -le 24) { return $s - 19 }
    if ($s -ge 25 -and $s -le 29) { return $s - 24 }; if ($s -ge 30 -and $s -le 34) { return $s - 29 }
    if ($s -ge 236 -and $s -le 240) { return $s - 235 }; if ($s -ge 241 -and $s -le 245) { return $s - 240 }
    if ($s -ge 254 -and $s -le 258) { return $s - 253 }; if ($s -ge 259 -and $s -le 263) { return $s - 258 }
    if ($s -ge 272 -and $s -le 276) { return $s - 271 }; if ($s -ge 277 -and $s -le 281) { return $s - 276 }
    if ($s -ge 290 -and $s -le 294) { return $s - 289 }; if ($s -ge 295 -and $s -le 299) { return $s - 294 }
    if ($s -ge 305 -and $s -le 309) { return $s - 304 }; if ($s -ge 308 -and $s -le 312) { return $s - 307 }
    if ($s -ge 313 -and $s -le 317) { return $s - 312 }; if ($s -ge 361 -and $s -le 365) { return $s - 360 }
    if ($s -ge 51 -and $s -le 60) { return 2 }; if ($s -ge 61 -and $s -le 70) { return 3 }
    if ($s -ge 71 -and $s -le 80) { return 4 }; if ($s -ge 81 -and $s -le 90) { return 3 }
    if ($s -ge 91 -and $s -le 100) { return 4 }; if ($s -ge 101 -and $s -le 110) { return 5 }
    if ($s -ge 111 -and $s -le 120) { return 1 }; if ($s -ge 125 -and $s -le 134) { return 1 }
    if ($s -ge 135 -and $s -le 144) { return 2 }; if ($s -ge 145 -and $s -le 154) { return 3 }
    if ($s -ge 155 -and $s -le 164) { return 4 }; if ($s -ge 165 -and $s -le 174) { return 5 }
    if ($s -ge 39 -and $s -le 49) { return 2 }; if ($s -ge 229 -and $s -le 231) { return $s - 227 }
    if ($s -ge 232 -and $s -le 234) { return $s - 229 }; if ($s -ge 250 -and $s -le 252) { return $s - 247 }
    if ($s -eq 7) { return 3 }; if ($s -eq 8) { return 4 }; if ($s -eq 9) { return 2 }
    if ($s -eq 235 -or $s -eq 253) { return 1 }; if ($s -eq 366) { return 6 }; if ($s -eq 358) { return 2 }; if ($s -eq 360) { return 3 }
    return 1
}

