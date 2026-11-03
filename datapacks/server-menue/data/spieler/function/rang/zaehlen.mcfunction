$execute store result score #v sp_tmp run data get storage spieler:tmp rest[$(i)].s$(c)
execute if score #v sp_tmp > #mein sp_tmp run scoreboard players add #platz sp_tmp 1
scoreboard players add #i sp_tmp 1
execute if score #i sp_tmp < #len sp_tmp run function spieler:rang/zaehlen_rufen
