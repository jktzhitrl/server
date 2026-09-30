-- Takt-Helfer: reine Entscheidungslogik ohne Spiel-API.
--
-- Idee: An einem Halt der Linie ("Taktknoten") hält der Mod jedes Fahrzeug so
-- lange fest, bis seit der letzten Abfahrt dort ein voller Takt vergangen ist.
-- So lösen sich Pulks auf und die Fahrzeuge fahren gleichmäßig verteilt.
--
-- Die Spielwelt wird über ein "welt"-Objekt eingereicht (siehe spiel.lua),
-- dadurch lässt sich alles hier auch ohne Spiel testen (tests/test_logik.lua).
--
-- Alle Zeiten in Sekunden Spielzeit. 1 "Minute" in der Oberfläche = 60 s.

local logik = {}

logik.MIN_HALT = 20        -- mindestens so lange steht ein Fahrzeug am Knoten (Ein-/Aussteigen)
logik.MAX_HALT_FAKTOR = 1.5 -- nie länger als 1,5 Takte festhalten (verhindert Blockaden)
logik.GLAETTUNG = 0.3      -- Gewicht neuer Umlaufmessungen im gleitenden Mittel

function logik.neueLinie()
	return {
		aktiv = false,
		knoten = 0,          -- Halt-Index (0-basiert, wie im Spiel)
		taktMin = 0,         -- 0 = automatisch, sonst fester Takt in Minuten
		uhr = false,         -- Abfahrten auf volle Taktzeiten der Spieluhr legen
		letzteAbfahrt = nil, -- Zeitpunkt der letzten Abfahrt am Knoten
		letzterSlot = nil,   -- Uhr-Modus: Nummer des zuletzt belegten Takt-Slots
		umlauf = nil,        -- geschätzte Umlaufzeit ohne Festhaltezeit (s)
		anzeige = {},        -- Werte nur für die Oberfläche
	}
end

-- Takt in Sekunden; nil solange im Automatikmodus noch nichts gemessen wurde.
function logik.taktSekunden(linie, anzahl)
	if linie.taktMin and linie.taktMin > 0 then
		return linie.taktMin * 60
	end
	if linie.umlauf and anzahl > 0 then
		return linie.umlauf / anzahl
	end
	return nil
end

-- Soll das Fahrzeug jetzt am Knoten abfahren?
function logik.darfAbfahren(linie, fz, jetzt, takt)
	local stand = jetzt - (fz.ankunft or jetzt)
	if stand < logik.MIN_HALT then return false end
	if not takt then return true end -- Lernphase: normal fahren und Umlauf messen
	if stand >= takt * logik.MAX_HALT_FAKTOR then return true end

	if linie.uhr then
		local slot = math.floor(jetzt / takt)
		return linie.letzterSlot == nil or slot > linie.letzterSlot
	end
	return linie.letzteAbfahrt == nil or jetzt - linie.letzteAbfahrt >= takt
end

-- Buchführung nach einer Abfahrt am Knoten.
function logik.abgefahren(linie, fz, jetzt, takt)
	-- Umlaufzeit messen: Zeit seit der letzten Abfahrt desselben Fahrzeugs,
	-- abzüglich der Zeit, die wir es diesmal zusätzlich festgehalten haben.
	local gehalten = math.max(0, jetzt - ((fz.ankunft or jetzt) + logik.MIN_HALT))
	if fz.letzteAbfahrt then
		local rund = jetzt - fz.letzteAbfahrt - gehalten
		if rund > 0 then
			if linie.umlauf then
				linie.umlauf = linie.umlauf + logik.GLAETTUNG * (rund - linie.umlauf)
			else
				linie.umlauf = rund
			end
		end
	end
	fz.letzteAbfahrt = jetzt
	fz.ankunft = nil
	fz.abfahrtGesendet = true

	if linie.letzteAbfahrt then
		linie.anzeige.abstand = jetzt - linie.letzteAbfahrt
	end
	linie.letzteAbfahrt = jetzt
	if takt then linie.letzterSlot = math.floor(jetzt / takt) end
end

-- Ein Durchlauf für eine Linie.
-- welt.fahrzeuge(linieId)  -> Liste { id=, zustand="HALT"|"FAHRT"|"DEPOT", halt=Index }
-- welt.setzeManuell(id, bool), welt.abfahren(id)
function logik.schrittLinie(linieId, linie, fahrzeugeState, welt, jetzt)
	local liste = welt.fahrzeuge(linieId)
	local imEinsatz = 0
	for _, v in ipairs(liste) do
		if v.zustand ~= "DEPOT" then imEinsatz = imEinsatz + 1 end
	end
	local takt = logik.taktSekunden(linie, imEinsatz)
	linie.anzeige.fahrzeuge = imEinsatz
	linie.anzeige.takt = takt

	for _, v in ipairs(liste) do
		local key = tostring(v.id)
		local fz = fahrzeugeState[key]
		if not fz then
			fz = { linie = linieId }
			fahrzeugeState[key] = fz
		end
		fz.linie = linieId
		fz.gesehen = jetzt

		-- Manuelle Abfahrt nur auf dem Weg zum / am Knoten, sonst fährt das
		-- Fahrzeug an allen anderen Halten ganz normal.
		local soll = v.zustand ~= "DEPOT" and v.halt == linie.knoten
		if fz.manuell ~= soll then
			welt.setzeManuell(v.id, soll)
			fz.manuell = soll
		end

		if v.zustand == "HALT" and v.halt == linie.knoten then
			if not fz.ankunft and not fz.abfahrtGesendet then
				fz.ankunft = jetzt
			end
			if fz.ankunft and logik.darfAbfahren(linie, fz, jetzt, takt) then
				welt.abfahren(v.id)
				logik.abgefahren(linie, fz, jetzt, takt)
			end
		else
			fz.abfahrtGesendet = nil
			if v.halt ~= linie.knoten then fz.ankunft = nil end
		end
	end
end

-- Linie abschalten: alle Fahrzeuge wieder normal fahren lassen.
function logik.freigeben(linieId, fahrzeugeState, welt)
	for key, fz in pairs(fahrzeugeState) do
		if fz.linie == linieId then
			if fz.manuell then welt.setzeManuell(tonumber(key), false) end
			fahrzeugeState[key] = nil
		end
	end
end

-- Kompletter Durchlauf über alle aktiven Linien.
function logik.schritt(state, welt, jetzt)
	state.linien = state.linien or {}
	state.fahrzeuge = state.fahrzeuge or {}
	for key, linie in pairs(state.linien) do
		local id = tonumber(key)
		if linie.aktiv then
			if welt.linieExistiert(id) then
				logik.schrittLinie(id, linie, state.fahrzeuge, welt, jetzt)
			else
				state.linien[key] = nil
			end
		end
	end
	-- Fahrzeuge vergessen, die lange nicht mehr gesehen wurden (verkauft, Linie gewechselt)
	for key, fz in pairs(state.fahrzeuge) do
		if fz.gesehen and jetzt - fz.gesehen > 600 then
			state.fahrzeuge[key] = nil
		end
	end
end

-- Einstellungen aus der Oberfläche übernehmen.
function logik.konfigurieren(state, welt, linieId, felder)
	state.linien = state.linien or {}
	state.fahrzeuge = state.fahrzeuge or {}
	local key = tostring(linieId)
	local linie = state.linien[key] or logik.neueLinie()
	state.linien[key] = linie

	local warAktiv = linie.aktiv
	for k, v in pairs(felder) do
		if k == "aktiv" or k == "knoten" or k == "taktMin" or k == "uhr" then
			linie[k] = v
		end
	end
	if felder.knoten ~= nil or felder.taktMin ~= nil or felder.uhr ~= nil then
		-- neuer Bezugspunkt: Messwerte zurücksetzen
		linie.letzteAbfahrt, linie.letzterSlot = nil, nil
		if felder.knoten ~= nil then linie.umlauf = nil end
	end
	if warAktiv and not linie.aktiv or felder.knoten ~= nil then
		logik.freigeben(linieId, state.fahrzeuge, welt)
	end
end

return logik
