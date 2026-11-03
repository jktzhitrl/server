# Hat sich der Spieler seit der letzten Sekunde bewegt oder umgesehen?
execute store result score @s afk_nx run data get entity @s Pos[0] 10
execute store result score @s afk_ny run data get entity @s Pos[1] 10
execute store result score @s afk_nz run data get entity @s Pos[2] 10
execute store result score @s afk_nr run data get entity @s Rotation[0] 10
execute store result score @s afk_np run data get entity @s Rotation[1] 10
scoreboard players set @s afk_gleich 0
execute if score @s afk_nx = @s afk_x if score @s afk_ny = @s afk_y if score @s afk_nz = @s afk_z if score @s afk_nr = @s afk_r if score @s afk_np = @s afk_p run scoreboard players set @s afk_gleich 1
scoreboard players operation @s afk_x = @s afk_nx
scoreboard players operation @s afk_y = @s afk_ny
scoreboard players operation @s afk_z = @s afk_nz
scoreboard players operation @s afk_r = @s afk_nr
scoreboard players operation @s afk_p = @s afk_np
execute if score @s afk_gleich matches 1 run scoreboard players add @s afk_sek 1
execute if score @s afk_gleich matches 0 run function spieler:afk/bewegt
# 10 Minuten (600 Sekunden) still: AFK
execute if score @s afk_sek matches 600 unless entity @s[team=afk] run function spieler:afk/ist_afk
