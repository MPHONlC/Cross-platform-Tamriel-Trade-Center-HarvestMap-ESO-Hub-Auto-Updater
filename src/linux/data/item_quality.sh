master_color_logic='
function get_hq(q) {
    if(q==6)return "Mythic (Orange) 6"
    if(q==5)return "Legendary (Gold) 5"
    if(q==4)return "Epic (Purple) 4"
    if(q==3)return "Superior (Blue) 3"
    if(q==2)return "Fine (Green) 2"
    if(q==1)return "Normal (White) 1"
    return "Trash (Grey) 0"
}
function get_cat(n,i,s,v) {
    ln = tolower(n)
    if(ln~/motif/)return "Crafting Motif"
    if(ln~/blueprint|praxis|design|pattern|formula|diagram|sketch/)return "Furniture Plan"
    if(ln~/style page|runebox/)return "Style/Collectible"
    if(ln~/tea blends of tamriel|tin of high isle taffy|assorted stolen shiny trinkets/)return "Companion Gift"
    if(ln~/lightly used fiddle|stuffed bear|grisly trophy|companion gift/)return "Companion Gift"
    if(v>1||s>=20)return "Equipment (Armor/Weapon)"
    return "Materials/Misc"
}
function calc_quality(id, name, s, v) {
    ln = tolower(name)
    if(id~/^(165899|187648|171437|165910|175510|181971|181961|175402|184206|191067)$/) return 6
    if(ln~/citation|truly superb glyph|tempering alloy|dreugh wax|rosin|kuta|perfect roe/) return 5
    if(ln~/aetherial dust|chromium plating|style page:|runebox:|research scroll|psijic ambrosia/) return 5
    if(ln~/indoril inks:/) return 5
    if(ln~/master .* writ/) return 4
    if(ln~/unknown .* writ|welkynar binding|rekuta|grain solvent|mastic|elegant lining/) return 4
    if(ln~/zircon plating|potent nirncrux|fortified nirncrux|culanda lacquer|harvested soul fragment/) return 4
    if(ln~/tea blends of tamriel|twenty-year ruby port|assorted stolen shiny trinkets/) return 3
    if(ln~/lightly used fiddle|stuffed bear|grisly trophy|companion gift|tin of high isle taffy/) return 3
    if(ln~/angler\047s knife set|dried fish biscuits|beginner\047s bowfishing kit/) return 3
    if(ln~/survey report|dwarven oil|turpen|embroidery|iridium plating|treasure map|bervez juice|frost mirriam/) return 3
    if(ln~/hemming|honing stone|pitch|terne plating|soul gem/) return 2
    if(ln~/^(recipe|design|blueprint|pattern|praxis|formula|diagram|sketch):/) { 
        if(s==6) return 5; if(s==5) return 4; if(s==4) return 3; if(s==3) return 2; return 1 
    }
    if(s >= 2 && s <= 6) return s - 1
    if(s >= 20 && s <= 24) return s - 19
    if(s >= 25 && s <= 29) return s - 24
    if(s >= 30 && s <= 34) return s - 29
    if(s >= 236 && s <= 240) return s - 235
    if(s >= 241 && s <= 245) return s - 240
    if(s >= 254 && s <= 258) return s - 253
    if(s >= 259 && s <= 263) return s - 258
    if(s >= 272 && s <= 276) return s - 271
    if(s >= 277 && s <= 281) return s - 276
    if(s >= 290 && s <= 294) return s - 289
    if(s >= 295 && s <= 299) return s - 294
    if(s >= 305 && s <= 309) return s - 304
    if(s >= 308 && s <= 312) return s - 307
    if(s >= 313 && s <= 317) return s - 312
    if(s >= 361 && s <= 365) return s - 360
    if(s >= 51 && s <= 60) return 2
    if(s >= 61 && s <= 70) return 3
    if(s >= 71 && s <= 80) return 4
    if(s >= 81 && s <= 90) return 3
    if(s >= 91 && s <= 100) return 4
    if(s >= 101 && s <= 110) return 5
    if(s >= 111 && s <= 120) return 1
    if(s >= 125 && s <= 134) return 1
    if(s >= 135 && s <= 144) return 2
    if(s >= 145 && s <= 154) return 3
    if(s >= 155 && s <= 164) return 4
    if(s >= 165 && s <= 174) return 5
    if(s >= 39 && s <= 49) return 2
    if(s >= 229 && s <= 231) return s - 227
    if(s >= 232 && s <= 234) return s - 229
    if(s >= 250 && s <= 252) return s - 247
    if(s == 7) return 3; if(s == 8) return 4; if(s == 9) return 2
    if(s == 235 || s == 253) return 1
    if(s == 366) return 6
    if(s == 358) return 2
    if(s == 360) return 3
    return 1
}
'

