# Erst alle Anwesenden eintragen, dann für jede Kategorie die besten 3 heraussuchen
execute as @a at @s run function spieler:db/eintragen
data modify storage spieler:ui dlg set value {type:"minecraft:multi_action",title:{text:"Bestenliste"},body:[{type:"minecraft:plain_message",width:400,contents:{text:"Die besten Spieler auf dem Server",color:"gray"}}],columns:2,actions:[{label:"◀ Zurück",width:150,action:{type:"minecraft:run_command",command:"/trigger menue set 1"}}],exit_action:{label:"Schließen"}}
data modify storage spieler:tmp arg set value {c:0,unit:" h",titel:"Spielzeit"}
function spieler:rang/kategorie with storage spieler:tmp arg
data modify storage spieler:tmp arg set value {c:1,unit:"",titel:"Tode"}
function spieler:rang/kategorie with storage spieler:tmp arg
data modify storage spieler:tmp arg set value {c:2,unit:"",titel:"Abgebaute Blöcke"}
function spieler:rang/kategorie with storage spieler:tmp arg
data modify storage spieler:tmp arg set value {c:3,unit:"",titel:"Besiegte Mobs"}
function spieler:rang/kategorie with storage spieler:tmp arg
function spieler:menue/zeigen with storage spieler:ui
