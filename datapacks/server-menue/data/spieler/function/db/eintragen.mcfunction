# Eintrag des Spielers (@s) in der Liste spieler:db p erneuern: UUID, Name, Spielzeit, Tode, Blöcke, Mobs und weitere Kategorien s4-s11
data modify storage spieler:tmp e set value {}
data modify storage spieler:tmp e.u set from entity @s UUID
execute store result storage spieler:tmp e.s0 int 1 run scoreboard players get @s bl_std
execute store result storage spieler:tmp e.s1 int 1 run scoreboard players get @s bl_tode
execute store result storage spieler:tmp e.s2 int 1 run scoreboard players get @s bl_abbau
execute store result storage spieler:tmp e.s3 int 1 run scoreboard players get @s bl_mobs
execute store result storage spieler:tmp e.s4 int 1 run scoreboard players get @s bl_km
execute store result storage spieler:tmp e.s5 int 1 run scoreboard players get @s bl_fisch
execute store result storage spieler:tmp e.s6 int 1 run scoreboard players get @s bl_erde
execute store result storage spieler:tmp e.s7 int 1 run scoreboard players get @s bl_dia
execute store result storage spieler:tmp e.s8 int 1 run scoreboard players get @s bl_zucht
execute store result storage spieler:tmp e.s9 int 1 run scoreboard players get @s bl_handel
execute store result storage spieler:tmp e.s10 int 1 run scoreboard players get @s bl_zauber
execute store result storage spieler:tmp e.s11 int 1 run scoreboard players get @s bl_schlaf
# Name holen (über den Spielerkopf, daher ohne [AFK] davor)
function spieler:db/name
function spieler:db/ersetzen with storage spieler:tmp e
