# Namen des Spielers holen. Weg 1: Spielerkopf mit Profil (ergibt reinen Text in e.nn)
loot spawn ~ ~ ~ loot spieler:name
data modify storage spieler:tmp e.nn set from entity @e[type=item,distance=..2,limit=1,sort=nearest,nbt={Item:{id:"minecraft:player_head"}}] Item.components."minecraft:profile".name
kill @e[type=item,distance=..2,nbt={Item:{id:"minecraft:player_head"}}]
# Weg 2 (falls Weg 1 nichts liefert): Papier, das nach dem Spieler benannt ist (ergibt Text-Baustein in e.nc)
execute unless data storage spieler:tmp e.nn run function spieler:db/name_papier
