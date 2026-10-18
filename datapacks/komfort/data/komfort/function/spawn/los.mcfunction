scoreboard players set @s spawn 0
execute unless data storage komfort:data spawn run tellraw @s {"text":"Der Spawn ist noch nicht festgelegt. Ein Admin muss sich hinstellen und /function komfort:admin/spawn_setzen eingeben.","color":"red"}
execute unless data storage komfort:data spawn run return 0
execute if data storage komfort:data spawn{d:0} in minecraft:overworld run function komfort:tp with storage komfort:data spawn
execute if data storage komfort:data spawn{d:1} in minecraft:the_nether run function komfort:tp with storage komfort:data spawn
execute if data storage komfort:data spawn{d:2} in minecraft:the_end run function komfort:tp with storage komfort:data spawn
tellraw @s {"text":"Du bist am Spawn.","color":"green"}
