# Die Seitenleiste wechselt alle 15 Sekunden: Spielzeit, Tode, Abgebaute Blöcke, Besiegte Mobs
scoreboard players add #seite bl_const 1
execute if score #seite bl_const matches 4.. run scoreboard players set #seite bl_const 0
execute if score #seite bl_const matches 0 run scoreboard objectives setdisplay sidebar bl_std
execute if score #seite bl_const matches 1 run scoreboard objectives setdisplay sidebar bl_tode
execute if score #seite bl_const matches 2 run scoreboard objectives setdisplay sidebar bl_abbau
execute if score #seite bl_const matches 3 run scoreboard objectives setdisplay sidebar bl_mobs
execute if score #an bl_const matches 1 run schedule function spieler:rotieren 15s replace
