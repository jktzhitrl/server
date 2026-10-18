$data modify storage spieler:ui row append value {text:"   $(r). ",color:"white"}
execute if data storage spieler:tmp top.n run data modify storage spieler:ui row append from storage spieler:tmp top.n
execute unless data storage spieler:tmp top.n run data modify storage spieler:ui row append value {text:"?",color:"white"}
$data modify storage spieler:ui row append value {text:" $(v)$(unit)",color:"yellow"}
