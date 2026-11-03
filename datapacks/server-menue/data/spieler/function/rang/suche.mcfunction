$execute store result score #v sp_tmp run data get storage spieler:tmp rest[$(i)].s$(c)
execute if score #v sp_tmp > #max sp_tmp run scoreboard players operation #maxi sp_tmp = #i sp_tmp
execute if score #v sp_tmp > #max sp_tmp run scoreboard players operation #max sp_tmp = #v sp_tmp
scoreboard players add #i sp_tmp 1
execute if score #i sp_tmp < #len sp_tmp run function spieler:rang/suche_rufen
