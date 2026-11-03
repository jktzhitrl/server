# Admin: alles vom Paket entfernen (vor dem Löschen der ZIP-Datei aufrufen)
schedule clear spieler:sekunde
scoreboard objectives setdisplay sidebar
scoreboard objectives setdisplay list
team remove afk
function #spieler:regel_an
scoreboard objectives remove bl_std
scoreboard objectives remove bl_abbau
scoreboard objectives remove bl_const
scoreboard objectives remove bl_km
scoreboard objectives remove bl_dia
scoreboard objectives remove afk
scoreboard objectives remove menue
scoreboard objectives remove sp_tmp
scoreboard objectives remove afk_sek
scoreboard objectives remove afk_gleich
scoreboard objectives remove afk_x
scoreboard objectives remove afk_y
scoreboard objectives remove afk_z
scoreboard objectives remove afk_r
scoreboard objectives remove afk_p
scoreboard objectives remove afk_nx
scoreboard objectives remove afk_ny
scoreboard objectives remove afk_nz
scoreboard objectives remove afk_nr
scoreboard objectives remove afk_np
tellraw @s {"text":"Server-Menü entfernt. Die Zähler von Minecraft (Spielzeit, Tode, Mobs, Strecke, Fische usw.) bleiben erhalten, falls du das Paket wieder einsetzt.","color":"gray"}
