scoreboard players set @s zurueck 0
execute unless data entity @s LastDeathLocation run tellraw @s {"text":"Du bist noch nicht gestorben, es gibt keinen Todespunkt.","color":"red"}
execute unless data entity @s LastDeathLocation run return 0
execute store result storage komfort:tmp x int 1 run data get entity @s LastDeathLocation.pos[0]
execute store result storage komfort:tmp y int 1 run data get entity @s LastDeathLocation.pos[1]
execute store result storage komfort:tmp z int 1 run data get entity @s LastDeathLocation.pos[2]
execute if data entity @s LastDeathLocation{dimension:"minecraft:overworld"} in minecraft:overworld run function komfort:tp with storage komfort:tmp
execute if data entity @s LastDeathLocation{dimension:"minecraft:the_nether"} in minecraft:the_nether run function komfort:tp with storage komfort:tmp
execute if data entity @s LastDeathLocation{dimension:"minecraft:the_end"} in minecraft:the_end run function komfort:tp with storage komfort:tmp
tellraw @s {"text":"Du bist an deinem letzten Todespunkt. Vorsicht!","color":"gold"}
