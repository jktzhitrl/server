# Fenster anzeigen. Klappt das nicht, bekommt der Spieler eine Meldung statt gar nichts.
scoreboard players set #ok sp_tmp 0
$execute store success score #ok sp_tmp run dialog show @s $(dlg)
execute if score #ok sp_tmp matches 0 run tellraw @s [{"text":"Das Menü konnte nicht angezeigt werden. ","color":"red"},{"text":"Admin: /data get storage spieler:ui dlg","color":"gray"}]
