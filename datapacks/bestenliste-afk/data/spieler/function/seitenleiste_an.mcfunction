# Admin: Bestenliste in der Seitenleiste wieder einblenden
scoreboard players set #an bl_const 1
function spieler:rotieren
tellraw @s {"text":"Bestenliste in der Seitenleiste ist an.","color":"gray"}
