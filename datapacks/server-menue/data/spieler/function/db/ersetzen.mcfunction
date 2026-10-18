$execute unless data storage spieler:tmp e.n run data modify storage spieler:tmp e.n set from storage spieler:db p[{u:$(u)}].n
$data remove storage spieler:db p[{u:$(u)}]
data modify storage spieler:db p append from storage spieler:tmp e
