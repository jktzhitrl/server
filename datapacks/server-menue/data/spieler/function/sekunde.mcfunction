# Läuft jede Sekunde
execute as @a run scoreboard players operation @s bl_std = @s bl_ticks
execute as @a run scoreboard players operation @s bl_std /= #72000 bl_const
execute as @a run function spieler:abbau_zaehlen
execute as @a at @s run function spieler:afk/pruefen
scoreboard players enable @a afk
scoreboard players enable @a menue
# Einmal pro Minute die Bestenliste mit allen Spielern auffrischen, die gerade da sind
scoreboard players add #sek bl_const 1
execute if score #sek bl_const matches 60.. as @a at @s run function spieler:db/eintragen
execute if score #sek bl_const matches 60.. run scoreboard players set #sek bl_const 0
schedule function spieler:sekunde 1s replace
