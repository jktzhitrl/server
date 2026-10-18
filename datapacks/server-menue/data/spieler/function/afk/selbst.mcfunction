# /trigger afk: sich selbst sofort als AFK melden (bei der nächsten Bewegung ist man wieder da)
scoreboard players set @s afk 0
scoreboard players set @s afk_sek 600
execute unless entity @s[team=afk] run function spieler:afk/ist_afk
