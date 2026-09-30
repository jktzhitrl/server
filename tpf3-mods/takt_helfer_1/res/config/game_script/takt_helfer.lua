-- Takt-Helfer: Game-Script. Das Spiel lädt jede Datei in res/config/game_script
-- aktiver Mods automatisch.
--   update/handleEvent/save  -> Engine-Thread (steuert die Fahrzeuge)
--   guiInit/guiUpdate/load   -> GUI-Thread (Fenster)

local logik = require "takt_helfer/logik"
local spiel = require "takt_helfer/spiel"
local fenster = require "takt_helfer/fenster"

local state = { linien = {}, fahrzeuge = {} }

function data()
	return {
		update = function()
			logik.schritt(state, spiel.welt, spiel.jetzt())
		end,

		handleEvent = function(src, id, name, param)
			if id ~= fenster.EVENT_ID or name ~= "konfig" or type(param) ~= "table" then return end
			logik.konfigurieren(state, spiel.welt, param.linie, param.felder or {})
		end,

		save = function()
			return state
		end,

		load = function(geladen)
			if geladen then
				state = geladen
				state.linien = state.linien or {}
				state.fahrzeuge = state.fahrzeuge or {}
			end
			fenster.load(state)
		end,

		guiInit = function()
			fenster.init()
		end,

		guiUpdate = function()
			fenster.update()
		end,
	}
end
