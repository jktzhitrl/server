# Admin-Test: /function spieler:name_pruefen zeigt, welchen Namen das Paket für dich findet
data remove storage spieler:tmp e.nn
function spieler:db/name
execute if data storage spieler:tmp e.nn run tellraw @s [{"text":"Name gefunden: ","color":"green"},{"storage":"spieler:tmp","nbt":"e.nn","color":"yellow"}]
execute unless data storage spieler:tmp e.nn run tellraw @s {"text":"Kein Name gefunden. Bitte Foto an Claude schicken.","color":"red"}
