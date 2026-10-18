# Eine Kategorie der Bestenliste: Symbol links, rechts Titel und Platz 1 bis 3 untereinander
data modify storage spieler:tmp rest set from storage spieler:db p
data modify storage spieler:ui row set value []
$data modify storage spieler:ui row append value {text:"$(titel)",color:"$(farbe)",bold:true}
scoreboard players set #r sp_tmp 1
function spieler:rang/platz
$data modify storage spieler:ui dlg.body append value {type:"minecraft:item",item:{id:"$(icon)"},show_decorations:false,show_tooltip:false,description:{width:250,contents:{text:""}}}
data modify storage spieler:ui dlg.body[-1].description.contents.extra set from storage spieler:ui row
