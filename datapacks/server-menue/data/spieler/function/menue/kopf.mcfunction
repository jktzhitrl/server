# Eigenen Kopf (über die UUID) und Namen in spieler:tmp kopf eintragen
data modify storage spieler:tmp kopf.item.components."minecraft:profile".id set from entity @s UUID
execute if data storage spieler:tmp e.n run data modify storage spieler:tmp kopf.description.contents.extra[0].extra[0] set from storage spieler:tmp e.n
