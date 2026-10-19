# Namen des Spielers als Text holen: kurz einen Spielerkopf mit seinem Profil erzeugen, Namen abschreiben, Kopf entfernen
loot spawn ~ ~ ~ loot spieler:name
data modify storage spieler:tmp e.nn set from entity @e[type=item,distance=..2,limit=1,sort=nearest,nbt={Item:{components:{"minecraft:custom_data":{sp_name:1b}}}}] Item.components."minecraft:profile".name
kill @e[type=item,distance=..2,nbt={Item:{components:{"minecraft:custom_data":{sp_name:1b}}}}]
