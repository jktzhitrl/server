function data()
	return {
		info = {
			minorVersion = 0,
			severityAdd = "NONE",
			severityRemove = "NONE",
			name = "Takt-Helfer",
			description = "Verteilt die Fahrzeuge einer Linie gleichmäßig: An einem wählbaren Halt (Taktknoten) " ..
				"wird jedes Fahrzeug festgehalten, bis seit der letzten Abfahrt ein voller Takt vergangen ist. " ..
				"Takt automatisch (Umlaufzeit / Fahrzeuge), fest in Minuten oder auf die Spieluhr ausgerichtet. " ..
				"Bedienung über den Button \"Takt\" in der unteren Leiste.",
			tags = { "Script Mod", "Misc" },
			visible = true,
			authors = {
				{ name = "Benedikt", role = "CREATOR" },
			},
		},
	}
end
