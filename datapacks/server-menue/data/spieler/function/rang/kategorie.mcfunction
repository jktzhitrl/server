# Eine Zeile der Bestenliste: Titel, dann Platz 1 bis 3
data modify storage spieler:tmp rest set from storage spieler:db p
data modify storage spieler:ui row set value []
$data modify storage spieler:ui row append value {text:"$(titel):",color:"gold"}
scoreboard players set #r sp_tmp 1
function spieler:rang/platz
data modify storage spieler:ui dlg.body append value {type:"minecraft:plain_message",width:400,contents:{text:""}}
data modify storage spieler:ui dlg.body[-1].contents.extra set from storage spieler:ui row
