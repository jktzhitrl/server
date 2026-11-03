# Werte, die aus mehreren Zählern zusammengesetzt sind
# Strecke in km = alle Fußwege (Laufen, Sprinten, Schleichen, Schwimmen) in cm / 100000
scoreboard players operation @s bl_km = @s bl_w1
scoreboard players operation @s bl_km += @s bl_w2
scoreboard players operation @s bl_km += @s bl_w3
scoreboard players operation @s bl_km += @s bl_w4
scoreboard players operation @s bl_km += @s bl_w5
scoreboard players operation @s bl_km += @s bl_w6
scoreboard players operation @s bl_km /= #100000 bl_const
# Diamanterze normal und Tiefenschiefer
scoreboard players operation @s bl_dia = @s bl_dia1
scoreboard players operation @s bl_dia += @s bl_dia2
