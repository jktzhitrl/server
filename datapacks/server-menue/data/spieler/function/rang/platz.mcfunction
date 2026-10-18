# Den Besten unter den Übrigen suchen, eintragen und aus der Liste nehmen
execute store result score #len sp_tmp run data get storage spieler:tmp rest
execute if score #len sp_tmp matches 0 run return 0
scoreboard players set #max sp_tmp -1
scoreboard players set #maxi sp_tmp 0
scoreboard players set #i sp_tmp 0
function spieler:rang/suche_rufen
execute store result storage spieler:tmp arg.i int 1 run scoreboard players get #maxi sp_tmp
function spieler:rang/nehmen with storage spieler:tmp arg
scoreboard players add #r sp_tmp 1
execute if score #r sp_tmp matches ..3 run function spieler:rang/platz
