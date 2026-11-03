# menue = 1: Hauptmenü, 2: Bestenliste, 3: Meine Werte
execute store result score #wahl sp_tmp run scoreboard players get @s menue
scoreboard players set @s menue 0
scoreboard players enable @s menue
execute if score #wahl sp_tmp matches 1 run function spieler:menue/haupt
execute if score #wahl sp_tmp matches 2 run function spieler:menue/bestenliste
execute if score #wahl sp_tmp matches 3 run function spieler:menue/meine_werte
