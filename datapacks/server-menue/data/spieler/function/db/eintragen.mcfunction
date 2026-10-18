# Eintrag des Spielers (@s) in der Liste spieler:db p erneuern: UUID, Name, Spielzeit, Tode, Blöcke, Mobs
data modify storage spieler:tmp e set value {}
data modify storage spieler:tmp e.u set from entity @s UUID
execute store result storage spieler:tmp e.s0 int 1 run scoreboard players get @s bl_std
execute store result storage spieler:tmp e.s1 int 1 run scoreboard players get @s bl_tode
execute store result storage spieler:tmp e.s2 int 1 run scoreboard players get @s bl_abbau
execute store result storage spieler:tmp e.s3 int 1 run scoreboard players get @s bl_mobs
# Name holen (ohne [AFK] davor: wer AFK ist, behält den gespeicherten Namen)
execute unless entity @s[team=afk] run function spieler:db/name
function spieler:db/ersetzen with storage spieler:tmp e
