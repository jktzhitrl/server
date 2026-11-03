# Nur für Admins (OP): an der eigenen Position aufrufen
execute store result storage komfort:data spawn.x int 1 run data get entity @s Pos[0]
execute store result storage komfort:data spawn.y int 1 run data get entity @s Pos[1]
execute store result storage komfort:data spawn.z int 1 run data get entity @s Pos[2]
data modify storage komfort:data spawn.d set value 0
execute if dimension minecraft:the_nether run data modify storage komfort:data spawn.d set value 1
execute if dimension minecraft:the_end run data modify storage komfort:data spawn.d set value 2
tellraw @s {"text":"Spawn für /trigger spawn gespeichert.","color":"green"}
