# Namen des Spielers holen. Weg 1: Spielerkopf mit Profil (ergibt reinen Text in e.nn).
# Der Kopf entsteht genau an dieser Stelle, deshalb ist er das nächste Item (Abstand 0) und wird sofort wieder entfernt.
loot spawn ~ ~ ~ loot spieler:name
data modify storage spieler:tmp e.nn set from entity @e[type=item,distance=..0.5,limit=1,sort=nearest] Item.components."minecraft:profile".name
kill @e[type=item,distance=..0.5,limit=1,sort=nearest]
# Weg 3 (falls Weg 1 nichts liefert): Kopf mit /item modify füllen
execute unless data storage spieler:tmp e.nn run function spieler:db/name_modifier
# Weg 2 (falls beides nichts liefert): Papier, das nach dem Spieler benannt ist (ergibt Text-Baustein in e.nc)
execute unless data storage spieler:tmp e.nn run function spieler:db/name_papier
