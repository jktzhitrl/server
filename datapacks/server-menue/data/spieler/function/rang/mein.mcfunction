# Platz = 1 + Anzahl der Spieler mit mehr
$scoreboard players set #mein sp_tmp $(v)
data modify storage spieler:tmp rest set from storage spieler:db p
execute store result score #len sp_tmp run data get storage spieler:tmp rest
scoreboard players set #platz sp_tmp 1
scoreboard players set #i sp_tmp 0
execute if score #len sp_tmp matches 1.. run function spieler:rang/zaehlen_rufen
execute store result storage spieler:tmp arg.p int 1 run scoreboard players get #platz sp_tmp
function spieler:rang/mein_zeile with storage spieler:tmp arg
