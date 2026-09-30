-- Tests für die Taktlogik (ohne Spiel). Ausführen aus dem Ordner tpf3-mods:
--   luajit tests/test_logik.lua

package.path = "takt_helfer_1/res/scripts/?.lua;" .. package.path
local logik = require "takt_helfer/logik"

local fehler = 0
local function pruefe(bedingung, text)
	if bedingung then
		print("  ok   " .. text)
	else
		print("  FAIL " .. text)
		fehler = fehler + 1
	end
end

-- Mini-Simulation einer Ringlinie mit zwei Halten:
-- Halt 0 = Taktknoten, Halt 1 = normaler Zwischenhalt.
local function simuliere(opt)
	local fahrzeiten = opt.fahrzeiten -- { zu Halt 1, zu Halt 0 }
	local fz = {}
	for i, start in ipairs(opt.starts) do
		fz[i] = { id = 100 + i, zustand = "FAHRT", halt = 0, rest = start, manuell = false, bereit = nil }
	end
	local manuellAnHalt1 = false
	local abfahrten = {}

	local welt = {
		linieExistiert = function() return true end,
		fahrzeuge = function()
			local l = {}
			for _, v in ipairs(fz) do l[#l + 1] = { id = v.id, zustand = v.zustand, halt = v.halt } end
			return l
		end,
		setzeManuell = function(id, an)
			for _, v in ipairs(fz) do if v.id == id then v.manuell = an end end
		end,
		abfahren = function(id)
			for _, v in ipairs(fz) do if v.id == id then v.losbefehl = true end end
		end,
	}

	local state = { linien = {}, fahrzeuge = {} }
	logik.konfigurieren(state, welt, 7, { aktiv = true, knoten = 0, taktMin = opt.taktMin or 0, uhr = opt.uhr or false })

	local dt = 1
	local rnd = 12345
	local function zufall() rnd = (rnd * 1103515245 + 12345) % 2147483648; return rnd / 2147483648 end

	for t = 0, opt.dauer, dt do
		for _, v in ipairs(fz) do
			if v.zustand == "FAHRT" then
				v.rest = v.rest - dt
				if v.rest <= 0 then
					v.zustand, v.bereit, v.losbefehl = "HALT", t + 15, false
				end
			elseif v.zustand == "HALT" then
				local fertig = t >= v.bereit
				local los = (v.manuell and v.losbefehl) or (not v.manuell and fertig)
				if v.halt == 1 and v.manuell then manuellAnHalt1 = true end
				if los then
					if v.halt == 0 then abfahrten[#abfahrten + 1] = t end
					v.halt = (v.halt + 1) % 2
					v.rest = fahrzeiten[v.halt + 1] + math.floor(zufall() * (opt.streuung or 0))
					v.zustand = "FAHRT"
				end
			end
		end
		logik.schritt(state, welt, t)
	end
	return abfahrten, state.linien["7"], manuellAnHalt1
end

local function abstaende(abf, letzte)
	local a = {}
	for i = math.max(2, #abf - letzte + 1), #abf do a[#a + 1] = abf[i] - abf[i - 1] end
	return a
end

print("Automatischer Takt: Pulk aus 4 Zügen löst sich auf")
do
	local abf, linie, manuellAnHalt1 = simuliere {
		starts = { 5, 25, 45, 65 }, fahrzeiten = { 500, 600 }, streuung = 20, dauer = 40000,
	}
	local a = abstaende(abf, 12)
	local min, max, sum = math.huge, 0, 0
	for _, x in ipairs(a) do min = math.min(min, x); max = math.max(max, x); sum = sum + x end
	local mittel = sum / #a
	print(string.format("    Abstände zuletzt: %s", table.concat(a, ", ")))
	print(string.format("    gelernter Umlauf %.0f s, Takt %.0f s", linie.umlauf or -1, linie.anzeige.takt or -1))
	-- Umlauf ohne Festhalten: 500 + 600 Fahrt + 15 Halt an Halt 1 + 20 Mindesthalt + ~10 Streuung
	pruefe(linie.umlauf and math.abs(linie.umlauf - 1145) < 40, "Umlaufzeit wird realistisch gelernt")
	pruefe(max - min <= 0.2 * mittel, "Abstände gleichmäßig (Spreizung <= 20 %)")
	pruefe(math.abs(mittel - linie.umlauf / 4) < 0.1 * mittel, "Abstand ~ Umlauf / Anzahl Züge")
	pruefe(not manuellAnHalt1, "an normalen Halten nie manuell festgehalten")
end

print("Fester Takt 6 Minuten")
do
	local abf = simuliere {
		starts = { 5, 15, 25 }, fahrzeiten = { 400, 500 }, streuung = 10, dauer = 30000, taktMin = 6,
	}
	local a = abstaende(abf, 10)
	local ok = true
	for _, x in ipairs(a) do if x < 360 then ok = false end end
	print(string.format("    Abstände zuletzt: %s", table.concat(a, ", ")))
	pruefe(ok, "kein Abstand kürzer als 360 s")
end

print("Uhr-Takt 10 Minuten: Abfahrten auf vollen Taktzeiten")
do
	local abf = simuliere {
		starts = { 5, 15 }, fahrzeiten = { 400, 500 }, streuung = 10, dauer = 30000, taktMin = 10, uhr = true,
	}
	local ok = true
	for i = #abf - 8, #abf do
		local rest = abf[i] % 600
		if rest > 2 and rest < 598 then ok = false; print("    daneben: " .. abf[i]) end
	end
	pruefe(ok, "Abfahrten liegen auf Vielfachen von 600 s")
end

print("Abschalten gibt alle Fahrzeuge frei")
do
	local manuell = {}
	local welt = {
		linieExistiert = function() return true end,
		fahrzeuge = function() return { { id = 1, zustand = "FAHRT", halt = 0 }, { id = 2, zustand = "FAHRT", halt = 1 } } end,
		setzeManuell = function(id, an) manuell[id] = an end,
		abfahren = function() end,
	}
	local state = {}
	logik.konfigurieren(state, welt, 3, { aktiv = true })
	logik.schritt(state, welt, 0)
	pruefe(manuell[1] == true and not manuell[2], "nur Fahrzeug Richtung Knoten ist manuell")
	logik.konfigurieren(state, welt, 3, { aktiv = false })
	pruefe(manuell[1] == false, "nach Abschalten wieder automatisch")
end

print(fehler == 0 and "\nAlle Tests bestanden." or ("\n" .. fehler .. " Test(s) fehlgeschlagen."))
os.exit(fehler == 0 and 0 or 1)
