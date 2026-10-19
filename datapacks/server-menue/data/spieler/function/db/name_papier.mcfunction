loot spawn ~ ~ ~ loot spieler:name_papier
data modify storage spieler:tmp e.nc set from entity @e[type=item,distance=..2,limit=1,sort=nearest,nbt={Item:{id:"minecraft:paper"}}] Item.components."minecraft:custom_name"
kill @e[type=item,distance=..2,nbt={Item:{id:"minecraft:paper"}}]
