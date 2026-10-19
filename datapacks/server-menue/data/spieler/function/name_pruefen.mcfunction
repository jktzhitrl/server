# Admin-Test: /function spieler:name_pruefen zeigt jeden Schritt beim Auslesen des Namens im Chat
tellraw @s {"text":"--- Namens-Test ---","color":"gold"}
# Schritt 1: Spielerkopf
scoreboard players set #a sp_tmp 0
execute store success score #a sp_tmp run loot spawn ~ ~ ~ loot spieler:name
execute store result score #b sp_tmp if entity @e[type=item,distance=..2]
execute store result score #c sp_tmp if entity @e[type=item,distance=..2,nbt={Item:{id:"minecraft:player_head"}}]
tellraw @s [{"text":"1) Kopf erzeugt: ","color":"gray"},{"score":{"name":"#a","objective":"sp_tmp"},"color":"yellow"},{"text":"  Items da: ","color":"gray"},{"score":{"name":"#b","objective":"sp_tmp"},"color":"yellow"},{"text":"  davon erkannt: ","color":"gray"},{"score":{"name":"#c","objective":"sp_tmp"},"color":"yellow"}]
tellraw @s [{"text":"   Item: ","color":"gray"},{"entity":"@e[type=item,distance=..2,limit=1,sort=nearest]","nbt":"Item","color":"white"}]
kill @e[type=item,distance=..2,nbt={Item:{id:"minecraft:player_head"}}]
# Schritt 2: Papier mit Namen
scoreboard players set #a sp_tmp 0
execute store success score #a sp_tmp run loot spawn ~ ~ ~ loot spieler:name_papier
execute store result score #c sp_tmp if entity @e[type=item,distance=..2,nbt={Item:{id:"minecraft:paper"}}]
tellraw @s [{"text":"2) Papier erzeugt: ","color":"gray"},{"score":{"name":"#a","objective":"sp_tmp"},"color":"yellow"},{"text":"  erkannt: ","color":"gray"},{"score":{"name":"#c","objective":"sp_tmp"},"color":"yellow"}]
tellraw @s [{"text":"   Item: ","color":"gray"},{"entity":"@e[type=item,distance=..2,limit=1,sort=nearest]","nbt":"Item","color":"white"}]
kill @e[type=item,distance=..2,nbt={Item:{id:"minecraft:paper"}}]
# Ergebnis über den normalen Weg
data remove storage spieler:tmp e.nn
data remove storage spieler:tmp e.nc
function spieler:db/name
execute if data storage spieler:tmp e.nn run tellraw @s [{"text":"Ergebnis: Name gefunden (Weg 1): ","color":"green"},{"storage":"spieler:tmp","nbt":"e.nn","color":"yellow"}]
execute unless data storage spieler:tmp e.nn if data storage spieler:tmp e.nc run tellraw @s [{"text":"Ergebnis: Name gefunden (Weg 2): ","color":"green"},{"storage":"spieler:tmp","nbt":"e.nc","interpret":true,"color":"yellow"}]
execute unless data storage spieler:tmp e.nn unless data storage spieler:tmp e.nc run tellraw @s {"text":"Ergebnis: kein Name gefunden. Bitte Foto vom ganzen Chat an Claude schicken.","color":"red"}
