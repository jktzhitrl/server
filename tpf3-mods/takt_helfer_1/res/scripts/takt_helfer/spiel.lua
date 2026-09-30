-- Takt-Helfer: einzige Stelle, die die Spiel-API benutzt.
-- Aufgebaut nach der Transport-Fever-2-Script-API. Falls TPF3 hier etwas
-- umbenannt hat, muss nur diese Datei angepasst werden.

local spiel = {}

local function sicher(fn, ...)
	local ok, ergebnis = pcall(fn, ...)
	if ok then return ergebnis end
	return nil
end

-- Spielzeit in Sekunden
function spiel.jetzt()
	local t = sicher(function()
		return api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime / 1000
	end)
	if t then return t end
	return sicher(function() return game.interface.getGameTime().time end) or 0
end

local function zustandText(zustand)
	local e = api.type.enum.TransportVehicleState
	if zustand == e.AT_TERMINAL then return "HALT" end
	if zustand == e.IN_DEPOT then return "DEPOT" end
	return "FAHRT"
end

function spiel.linieExistiert(linie)
	return sicher(function()
		return api.engine.getComponent(linie, api.type.ComponentType.LINE) ~= nil
	end) == true
end

function spiel.fahrzeuge(linie)
	local liste = {}
	local ids = sicher(function() return api.engine.system.transportVehicleSystem.getLineVehicles(linie) end) or {}
	for _, id in ipairs(ids) do
		local tv = sicher(function() return api.engine.getComponent(id, api.type.ComponentType.TRANSPORT_VEHICLE) end)
		if tv then
			liste[#liste + 1] = { id = id, zustand = zustandText(tv.state), halt = tv.stopIndex }
		end
	end
	return liste
end

function spiel.setzeManuell(fahrzeug, an)
	sicher(function()
		api.cmd.sendCommand(api.cmd.make.setVehicleManualDeparture(fahrzeug, an))
	end)
end

function spiel.abfahren(fahrzeug)
	sicher(function()
		api.cmd.sendCommand(api.cmd.make.setVehicleShouldDepart(fahrzeug))
	end)
end

local function name(entity)
	return sicher(function()
		return api.engine.getComponent(entity, api.type.ComponentType.NAME).name
	end)
end

-- Alle Linien mit Name und Haltenamen, sortiert nach Name (für die Oberfläche)
function spiel.linien()
	local ergebnis = {}
	local ids = sicher(function() return api.engine.system.lineSystem.getLines() end) or {}
	for _, id in ipairs(ids) do
		local halte = {}
		local line = sicher(function() return api.engine.getComponent(id, api.type.ComponentType.LINE) end)
		if line then
			for i = 1, #line.stops do
				halte[i] = name(line.stops[i].stationGroup) or ("Halt " .. i)
			end
		end
		ergebnis[#ergebnis + 1] = { id = id, name = name(id) or ("Linie " .. id), halte = halte }
	end
	table.sort(ergebnis, function(a, b) return a.name < b.name end)
	return ergebnis
end

spiel.welt = {
	linieExistiert = spiel.linieExistiert,
	fahrzeuge = spiel.fahrzeuge,
	setzeManuell = spiel.setzeManuell,
	abfahren = spiel.abfahren,
}

return spiel
