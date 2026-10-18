$data modify storage spieler:ui row append value {text:"   $(r). ",color:"white"}
data modify storage spieler:ui row append value {text:"",color:"white",extra:[]}
data modify storage spieler:ui row[-1].extra append from storage spieler:tmp top.n
$data modify storage spieler:ui row append value {text:" $(v)$(unit)",color:"yellow"}
