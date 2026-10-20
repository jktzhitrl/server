# Namen nur holen, wenn er für diesen Spieler noch nicht gespeichert ist
$execute unless data storage spieler:db p[{u:$(u)}].nn unless data storage spieler:db p[{u:$(u)}].nc run function spieler:db/name
