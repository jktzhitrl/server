# Eigene Zahlen und Platz in jeder Kategorie
execute as @a at @s run function spieler:db/eintragen
data modify storage spieler:ui dlg set value {type:"minecraft:multi_action",title:{text:"Meine Werte"},body:[{type:"minecraft:plain_message",width:400,contents:{text:"Deine Zahlen auf dem Server",color:"gray"}}],columns:2,actions:[{label:"◀ Zurück",width:150,action:{type:"minecraft:run_command",command:"/trigger menue set 1"}}],exit_action:{label:"Schließen"}}
execute store result storage spieler:tmp arg.v int 1 run scoreboard players get @s bl_std
data modify storage spieler:tmp arg merge value {c:0,unit:" h",titel:"Spielzeit"}
function spieler:rang/mein with storage spieler:tmp arg
execute store result storage spieler:tmp arg.v int 1 run scoreboard players get @s bl_tode
data modify storage spieler:tmp arg merge value {c:1,unit:"",titel:"Tode"}
function spieler:rang/mein with storage spieler:tmp arg
execute store result storage spieler:tmp arg.v int 1 run scoreboard players get @s bl_abbau
data modify storage spieler:tmp arg merge value {c:2,unit:"",titel:"Abgebaute Blöcke"}
function spieler:rang/mein with storage spieler:tmp arg
execute store result storage spieler:tmp arg.v int 1 run scoreboard players get @s bl_mobs
data modify storage spieler:tmp arg merge value {c:3,unit:"",titel:"Besiegte Mobs"}
function spieler:rang/mein with storage spieler:tmp arg
function spieler:menue/zeigen with storage spieler:ui
