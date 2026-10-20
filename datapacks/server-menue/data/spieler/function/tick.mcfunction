# Menü-Knöpfe sofort beantworten
execute as @a[scores={menue=1..}] at @s run function spieler:menue/auswahl
execute as @a[scores={afk=1..}] run function spieler:afk/selbst
