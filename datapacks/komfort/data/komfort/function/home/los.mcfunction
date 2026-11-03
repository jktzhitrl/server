scoreboard players set @s home 0
execute unless score @s k_hset matches 1 run tellraw @s {"text":"Du hast noch kein Zuhause. Stell dich an die Stelle und tippe /trigger sethome","color":"red"}
execute unless score @s k_hset matches 1 run return 0
execute store result storage komfort:tmp x int 1 run scoreboard players get @s k_hx
execute store result storage komfort:tmp y int 1 run scoreboard players get @s k_hy
execute store result storage komfort:tmp z int 1 run scoreboard players get @s k_hz
execute if score @s k_hd matches 0 in minecraft:overworld run function komfort:tp with storage komfort:tmp
execute if score @s k_hd matches 1 in minecraft:the_nether run function komfort:tp with storage komfort:tmp
execute if score @s k_hd matches 2 in minecraft:the_end run function komfort:tp with storage komfort:tmp
tellraw @s {"text":"Willkommen zu Hause!","color":"green"}
