# Hauptmenü: Kopf und Name des Spielers, darunter die Knöpfe
function spieler:db/eintragen
data modify storage spieler:ui dlg set value {type:"minecraft:multi_action",title:{text:"⚑ Server-Menü ⚑",color:"gold",bold:true},body:[],columns:1,actions:[{label:{text:"★ Bestenliste",color:"gold"},tooltip:{text:"Die besten 3 Spieler in jeder Kategorie"},width:200,action:{type:"minecraft:run_command",command:"/trigger menue set 2"}},{label:{text:"✎ Meine Werte",color:"aqua"},tooltip:{text:"Deine eigenen Zahlen und dein Platz"},width:200,action:{type:"minecraft:run_command",command:"/trigger menue set 3"}},{label:{text:"☾ AFK melden",color:"gray"},tooltip:{text:"Graues [AFK] vor deinem Namen, bis du dich wieder bewegst"},width:200,action:{type:"minecraft:run_command",command:"/trigger afk"}}],exit_action:{label:{text:"Schließen",color:"gray"},width:200}}
data modify storage spieler:tmp kopf set value {type:"minecraft:item",item:{id:"minecraft:player_head",components:{"minecraft:profile":{id:[I;0,0,0,0]}}},show_decorations:false,show_tooltip:false,description:{width:200,contents:{text:"Hallo ",color:"gray",extra:[{text:"",color:"yellow",extra:[{text:"Spieler"}]},{text:"!\nWas möchtest du tun?",color:"gray"}]}}}
function spieler:menue/kopf
data modify storage spieler:ui dlg.body append from storage spieler:tmp kopf
function spieler:menue/zeigen with storage spieler:ui
