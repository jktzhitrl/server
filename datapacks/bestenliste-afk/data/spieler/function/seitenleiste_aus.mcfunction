# Admin: Bestenliste in der Seitenleiste ausblenden
scoreboard players set #an bl_const 0
schedule clear spieler:rotieren
scoreboard objectives setdisplay sidebar
tellraw @s {"text":"Bestenliste in der Seitenleiste ist aus.","color":"gray"}
