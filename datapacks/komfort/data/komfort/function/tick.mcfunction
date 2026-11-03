execute as @a[scores={home=1..}] at @s run function komfort:home/los
execute as @a[scores={sethome=1..}] at @s run function komfort:home/setzen
execute as @a[scores={spawn=1..}] at @s run function komfort:spawn/los
execute as @a[scores={zurueck=1..}] at @s run function komfort:zurueck/los
execute as @a[scores={hilfe=1..}] run function komfort:hilfe
scoreboard players enable @a home
scoreboard players enable @a sethome
scoreboard players enable @a spawn
scoreboard players enable @a zurueck
scoreboard players enable @a hilfe
