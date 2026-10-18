# ---------- Bestenliste ----------
scoreboard objectives add bl_ticks minecraft.custom:minecraft.play_time
scoreboard objectives add bl_std dummy {"text":"Spielzeit (Stunden)","color":"gold"}
scoreboard objectives add bl_tode deathCount {"text":"Tode","color":"red"}
scoreboard objectives add bl_mobs totalKillCount {"text":"Besiegte Mobs","color":"dark_green"}
scoreboard objectives add bl_abbau dummy {"text":"Abgebaute Blöcke","color":"aqua"}
scoreboard objectives add bl_const dummy
scoreboard players set #72000 bl_const 72000
scoreboard objectives add bl_u_wooden_pickaxe minecraft.used:minecraft.wooden_pickaxe
scoreboard objectives add bl_u_wooden_shovel minecraft.used:minecraft.wooden_shovel
scoreboard objectives add bl_u_wooden_axe minecraft.used:minecraft.wooden_axe
scoreboard objectives add bl_u_wooden_hoe minecraft.used:minecraft.wooden_hoe
scoreboard objectives add bl_u_stone_pickaxe minecraft.used:minecraft.stone_pickaxe
scoreboard objectives add bl_u_stone_shovel minecraft.used:minecraft.stone_shovel
scoreboard objectives add bl_u_stone_axe minecraft.used:minecraft.stone_axe
scoreboard objectives add bl_u_stone_hoe minecraft.used:minecraft.stone_hoe
scoreboard objectives add bl_u_iron_pickaxe minecraft.used:minecraft.iron_pickaxe
scoreboard objectives add bl_u_iron_shovel minecraft.used:minecraft.iron_shovel
scoreboard objectives add bl_u_iron_axe minecraft.used:minecraft.iron_axe
scoreboard objectives add bl_u_iron_hoe minecraft.used:minecraft.iron_hoe
scoreboard objectives add bl_u_golden_pickaxe minecraft.used:minecraft.golden_pickaxe
scoreboard objectives add bl_u_golden_shovel minecraft.used:minecraft.golden_shovel
scoreboard objectives add bl_u_golden_axe minecraft.used:minecraft.golden_axe
scoreboard objectives add bl_u_golden_hoe minecraft.used:minecraft.golden_hoe
scoreboard objectives add bl_u_diamond_pickaxe minecraft.used:minecraft.diamond_pickaxe
scoreboard objectives add bl_u_diamond_shovel minecraft.used:minecraft.diamond_shovel
scoreboard objectives add bl_u_diamond_axe minecraft.used:minecraft.diamond_axe
scoreboard objectives add bl_u_diamond_hoe minecraft.used:minecraft.diamond_hoe
scoreboard objectives add bl_u_netherite_pickaxe minecraft.used:minecraft.netherite_pickaxe
scoreboard objectives add bl_u_netherite_shovel minecraft.used:minecraft.netherite_shovel
scoreboard objectives add bl_u_netherite_axe minecraft.used:minecraft.netherite_axe
scoreboard objectives add bl_u_netherite_hoe minecraft.used:minecraft.netherite_hoe
# ---------- AFK ----------
scoreboard objectives add afk trigger
scoreboard objectives add afk_sek dummy
scoreboard objectives add afk_gleich dummy
scoreboard objectives add afk_x dummy
scoreboard objectives add afk_y dummy
scoreboard objectives add afk_z dummy
scoreboard objectives add afk_r dummy
scoreboard objectives add afk_p dummy
scoreboard objectives add afk_nx dummy
scoreboard objectives add afk_ny dummy
scoreboard objectives add afk_nz dummy
scoreboard objectives add afk_nr dummy
scoreboard objectives add afk_np dummy
team add afk {"text":"AFK"}
team modify afk prefix {"text":"[AFK] ","color":"gray"}
team modify afk color gray
# ---------- Menü ----------
scoreboard objectives add menue trigger
scoreboard objectives add sp_tmp dummy
# alte Anzeigen der ersten Version wegräumen
schedule clear spieler:rotieren
scoreboard objectives setdisplay sidebar
scoreboard objectives setdisplay list
execute unless data storage spieler:db p run data modify storage spieler:db p set value []
schedule function spieler:sekunde 1s replace
