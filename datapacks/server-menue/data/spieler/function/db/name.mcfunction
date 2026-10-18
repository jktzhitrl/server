# Namen des Spielers als Text holen: Papier mit seinem Namen erzeugen, Namen abschreiben, Papier entfernen
loot spawn ~ ~ ~ loot spieler:name
data modify storage spieler:tmp e.n set from entity @e[type=item,distance=..2,limit=1,sort=nearest,nbt={Item:{components:{"minecraft:custom_data":{sp_name:1b}}}}] Item.components."minecraft:custom_name"
kill @e[type=item,distance=..2,nbt={Item:{components:{"minecraft:custom_data":{sp_name:1b}}}}]
