# Eigene Zahlen und Platz in jeder Kategorie
execute as @a at @s run function spieler:db/eintragen
function spieler:db/eintragen
data modify storage spieler:ui dlg set value {type:"minecraft:multi_action",title:{text:"✎ Meine Werte ✎",color:"aqua",bold:true},body:[],columns:1,actions:[{label:{text:"◀ Zurück",color:"white"},width:200,action:{type:"minecraft:run_command",command:"/trigger menue set 1"}}],exit_action:{label:{text:"Schließen",color:"gray"},width:200}}
data modify storage spieler:tmp kopf set value {type:"minecraft:item",item:{id:"minecraft:player_head",components:{"minecraft:profile":{id:[I;0,0,0,0]}}},show_decorations:false,show_tooltip:false,description:{width:250,contents:{text:"Die Werte von ",color:"gray",extra:[{text:"",color:"yellow",extra:[{text:"dir"}]}]}}}
function spieler:menue/kopf
data modify storage spieler:ui dlg.body append from storage spieler:tmp kopf
execute store result storage spieler:tmp arg.v int 1 run scoreboard players get @s bl_std
data modify storage spieler:tmp arg merge value {c:0,unit:" Std.",titel:"Spielzeit",icon:"minecraft:clock",farbe:"gold"}
function spieler:rang/mein with storage spieler:tmp arg
execute store result storage spieler:tmp arg.v int 1 run scoreboard players get @s bl_tode
data modify storage spieler:tmp arg merge value {c:1,unit:"",titel:"Tode",icon:"minecraft:skeleton_skull",farbe:"red"}
function spieler:rang/mein with storage spieler:tmp arg
execute store result storage spieler:tmp arg.v int 1 run scoreboard players get @s bl_abbau
data modify storage spieler:tmp arg merge value {c:2,unit:"",titel:"Abgebaute Blöcke",icon:"minecraft:iron_pickaxe",farbe:"aqua"}
function spieler:rang/mein with storage spieler:tmp arg
execute store result storage spieler:tmp arg.v int 1 run scoreboard players get @s bl_mobs
data modify storage spieler:tmp arg merge value {c:3,unit:"",titel:"Besiegte Mobs",icon:"minecraft:iron_sword",farbe:"green"}
function spieler:rang/mein with storage spieler:tmp arg
execute store result storage spieler:tmp arg.v int 1 run scoreboard players get @s bl_km
data modify storage spieler:tmp arg merge value {c:4,unit:" km",titel:"Gelaufene Strecke",icon:"minecraft:leather_boots",farbe:"#C88A50"}
function spieler:rang/mein with storage spieler:tmp arg
execute store result storage spieler:tmp arg.v int 1 run scoreboard players get @s bl_fisch
data modify storage spieler:tmp arg merge value {c:5,unit:"",titel:"Gefangene Fische",icon:"minecraft:fishing_rod",farbe:"blue"}
function spieler:rang/mein with storage spieler:tmp arg
execute store result storage spieler:tmp arg.v int 1 run scoreboard players get @s bl_erde
data modify storage spieler:tmp arg merge value {c:6,unit:"",titel:"Gesetzte Erdblöcke",icon:"minecraft:dirt",farbe:"#B07A4A"}
function spieler:rang/mein with storage spieler:tmp arg
execute store result storage spieler:tmp arg.v int 1 run scoreboard players get @s bl_dia
data modify storage spieler:tmp arg merge value {c:7,unit:"",titel:"Abgebaute Diamanterze",icon:"minecraft:diamond",farbe:"aqua"}
function spieler:rang/mein with storage spieler:tmp arg
execute store result storage spieler:tmp arg.v int 1 run scoreboard players get @s bl_zucht
data modify storage spieler:tmp arg merge value {c:8,unit:"",titel:"Gezüchtete Tiere",icon:"minecraft:wheat",farbe:"yellow"}
function spieler:rang/mein with storage spieler:tmp arg
execute store result storage spieler:tmp arg.v int 1 run scoreboard players get @s bl_handel
data modify storage spieler:tmp arg merge value {c:9,unit:"",titel:"Handel mit Dorfbewohnern",icon:"minecraft:emerald",farbe:"green"}
function spieler:rang/mein with storage spieler:tmp arg
execute store result storage spieler:tmp arg.v int 1 run scoreboard players get @s bl_zauber
data modify storage spieler:tmp arg merge value {c:10,unit:"",titel:"Verzauberte Gegenstände",icon:"minecraft:enchanting_table",farbe:"light_purple"}
function spieler:rang/mein with storage spieler:tmp arg
execute store result storage spieler:tmp arg.v int 1 run scoreboard players get @s bl_schlaf
data modify storage spieler:tmp arg merge value {c:11,unit:"",titel:"Nächte geschlafen",icon:"minecraft:red_bed",farbe:"red"}
function spieler:rang/mein with storage spieler:tmp arg
function spieler:menue/zeigen with storage spieler:ui
