summon item_display ~ ~ ~ {Tags:["sp_name"]}
loot replace entity @e[type=item_display,tag=sp_name,limit=1,sort=nearest] contents loot spieler:name
data modify storage spieler:tmp e.n set from entity @e[type=item_display,tag=sp_name,limit=1,sort=nearest] item.components."minecraft:custom_name"
kill @e[type=item_display,tag=sp_name]
