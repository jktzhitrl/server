# Namen des Spielers (@s) holen: Kopf als Item hinlegen, mit /item modify (als der Spieler) sein Profil eintragen,
# Namen als Text in e.nn abschreiben, Kopf wieder entfernen. Im Test auf 26.3 mit Spieler geprüft.
summon item ~ ~ ~ {Item:{id:"minecraft:player_head",count:1},PickupDelay:32767s,Tags:["sp_name"]}
function spieler:db/kopf
data modify storage spieler:tmp e.nn set from entity @e[type=item,tag=sp_name,limit=1,sort=nearest] Item.components."minecraft:profile".name
kill @e[type=item,tag=sp_name]
