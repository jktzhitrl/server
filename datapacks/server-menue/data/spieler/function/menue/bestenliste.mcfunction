# Erst alle Anwesenden eintragen, dann für jede Kategorie die besten 3 heraussuchen
execute as @a at @s run function spieler:db/eintragen
data modify storage spieler:ui dlg set value {type:"minecraft:multi_action",title:{text:"★ Bestenliste ★",color:"gold",bold:true},body:[{type:"minecraft:plain_message",width:300,contents:{text:"Die besten Spieler auf dem Server",color:"gray",italic:true}}],columns:1,actions:[{label:{text:"◀ Zurück",color:"white"},width:200,action:{type:"minecraft:run_command",command:"/trigger menue set 1"}}],exit_action:{label:{text:"Schließen",color:"gray"},width:200}}
data modify storage spieler:tmp arg set value {c:0,unit:" Std.",titel:"Spielzeit",icon:"minecraft:clock",farbe:"gold"}
function spieler:rang/kategorie with storage spieler:tmp arg
data modify storage spieler:tmp arg set value {c:1,unit:"",titel:"Tode",icon:"minecraft:skeleton_skull",farbe:"red"}
function spieler:rang/kategorie with storage spieler:tmp arg
data modify storage spieler:tmp arg set value {c:2,unit:"",titel:"Abgebaute Blöcke",icon:"minecraft:iron_pickaxe",farbe:"aqua"}
function spieler:rang/kategorie with storage spieler:tmp arg
data modify storage spieler:tmp arg set value {c:3,unit:"",titel:"Besiegte Mobs",icon:"minecraft:iron_sword",farbe:"green"}
function spieler:rang/kategorie with storage spieler:tmp arg
data modify storage spieler:tmp arg set value {c:4,unit:" km",titel:"Gelaufene Strecke",icon:"minecraft:leather_boots",farbe:"#C88A50"}
function spieler:rang/kategorie with storage spieler:tmp arg
data modify storage spieler:tmp arg set value {c:5,unit:"",titel:"Gefangene Fische",icon:"minecraft:fishing_rod",farbe:"blue"}
function spieler:rang/kategorie with storage spieler:tmp arg
data modify storage spieler:tmp arg set value {c:6,unit:"",titel:"Gesetzte Erdblöcke",icon:"minecraft:dirt",farbe:"#B07A4A"}
function spieler:rang/kategorie with storage spieler:tmp arg
data modify storage spieler:tmp arg set value {c:7,unit:"",titel:"Abgebaute Diamanterze",icon:"minecraft:diamond",farbe:"aqua"}
function spieler:rang/kategorie with storage spieler:tmp arg
data modify storage spieler:tmp arg set value {c:8,unit:"",titel:"Gezüchtete Tiere",icon:"minecraft:wheat",farbe:"yellow"}
function spieler:rang/kategorie with storage spieler:tmp arg
data modify storage spieler:tmp arg set value {c:9,unit:"",titel:"Handel mit Dorfbewohnern",icon:"minecraft:emerald",farbe:"green"}
function spieler:rang/kategorie with storage spieler:tmp arg
data modify storage spieler:tmp arg set value {c:10,unit:"",titel:"Verzauberte Gegenstände",icon:"minecraft:enchanting_table",farbe:"light_purple"}
function spieler:rang/kategorie with storage spieler:tmp arg
data modify storage spieler:tmp arg set value {c:11,unit:"",titel:"Nächte geschlafen",icon:"minecraft:red_bed",farbe:"red"}
function spieler:rang/kategorie with storage spieler:tmp arg
function spieler:menue/zeigen with storage spieler:ui
