$execute unless data storage spieler:tmp e.nn run data modify storage spieler:tmp e.nn set from storage spieler:db p[{u:$(u)}].nn
$data remove storage spieler:db p[{u:$(u)}]
data modify storage spieler:db p append from storage spieler:tmp e
