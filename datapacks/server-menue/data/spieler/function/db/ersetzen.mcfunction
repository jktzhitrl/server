$execute unless data storage spieler:tmp e.nn unless data storage spieler:tmp e.nc run data modify storage spieler:tmp e.nn set from storage spieler:db p[{u:$(u)}].nn
$execute unless data storage spieler:tmp e.nn unless data storage spieler:tmp e.nc run data modify storage spieler:tmp e.nc set from storage spieler:db p[{u:$(u)}].nc
$data remove storage spieler:db p[{u:$(u)}]
data modify storage spieler:db p append from storage spieler:tmp e
