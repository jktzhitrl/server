loot spawn ~ ~ ~ loot spieler:name_papier
data modify storage spieler:tmp e.nc set from entity @e[type=item,distance=..0.5,limit=1,sort=nearest] Item.components."minecraft:custom_name"
kill @e[type=item,distance=..0.5,limit=1,sort=nearest]
