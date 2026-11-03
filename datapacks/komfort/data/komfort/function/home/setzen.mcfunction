scoreboard players set @s sethome 0
execute store result score @s k_hx run data get entity @s Pos[0]
execute store result score @s k_hy run data get entity @s Pos[1]
execute store result score @s k_hz run data get entity @s Pos[2]
scoreboard players set @s k_hd 0
execute if dimension minecraft:the_nether run scoreboard players set @s k_hd 1
execute if dimension minecraft:the_end run scoreboard players set @s k_hd 2
scoreboard players set @s k_hset 1
tellraw @s {"text":"Dein Zuhause ist gespeichert. Mit /trigger home kommst du hierher zurück.","color":"green"}
