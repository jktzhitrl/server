$data modify storage spieler:tmp top set from storage spieler:tmp rest[$(i)]
$data remove storage spieler:tmp rest[$(i)]
execute store result storage spieler:tmp arg.r int 1 run scoreboard players get #r sp_tmp
execute store result storage spieler:tmp arg.v int 1 run scoreboard players get #max sp_tmp
function spieler:rang/zeile with storage spieler:tmp arg
