# Läuft jede Sekunde
execute as @a run scoreboard players operation @s bl_std = @s bl_ticks
execute as @a run scoreboard players operation @s bl_std /= #72000 bl_const
execute as @a run function spieler:abbau_zaehlen
execute as @a at @s run function spieler:afk/pruefen
execute as @a[scores={afk=1..}] run function spieler:afk/selbst
scoreboard players enable @a afk
schedule function spieler:sekunde 1s replace
