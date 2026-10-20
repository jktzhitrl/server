# Weg 3: Kopf als Item hinlegen und mit /item modify (als der Spieler ausgeführt) mit seinem Profil füllen.
# Die Schreibweise ist in 26.x unsicher, deshalb zwei Varianten über einen Funktions-Tag (die ungültige wird einfach übersprungen).
summon item ~ ~ ~ {Item:{id:"minecraft:player_head",count:1},PickupDelay:32767s,Tags:["sp_name"]}
function #spieler:kopf_fuellen
data modify storage spieler:tmp e.nn set from entity @e[type=item,tag=sp_name,limit=1,sort=nearest] Item.components."minecraft:profile".name
kill @e[type=item,tag=sp_name]
