# Platz 1 gold, 2 silber, 3 bronze
execute if score #r sp_tmp matches 1 run data modify storage spieler:ui row append value {text:"\n 1. ",color:"#FFC83D",bold:true}
execute if score #r sp_tmp matches 2 run data modify storage spieler:ui row append value {text:"\n 2. ",color:"#C8C8C8",bold:true}
execute if score #r sp_tmp matches 3 run data modify storage spieler:ui row append value {text:"\n 3. ",color:"#D08A4E",bold:true}
execute if data storage spieler:tmp top.n run data modify storage spieler:ui row append from storage spieler:tmp top.n
execute unless data storage spieler:tmp top.n run data modify storage spieler:ui row append value {text:"?",color:"white"}
$data modify storage spieler:ui row append value {text:"  $(v)$(unit)",color:"yellow"}
