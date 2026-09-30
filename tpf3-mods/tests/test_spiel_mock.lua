-- Lädt das Game-Script mit einer nachgebauten Spiel-API (TPF2-Stil) und spielt
-- einen kurzen Ablauf durch: Fenster öffnen, Linie aktivieren, Züge steuern.
-- Findet Tipp- und Laufzeitfehler; ob das echte TPF3 die API genauso hat,
-- lässt sich nur im Spiel prüfen.
--   luajit tests/test_spiel_mock.lua

package.path = "takt_helfer_1/res/scripts/?.lua;" .. package.path

local fehler = 0
local function pruefe(b, t) print((b and "  ok   " or "  FAIL ") .. t); if not b then fehler = fehler + 1 end end

-- ---------- Spielwelt ----------
local zeitMs = 0
local fahrzeuge = {
	[501] = { state = 1, stopIndex = 0, line = 42 },
	[502] = { state = 1, stopIndex = 0, line = 42 },
}
local befehle = {}
local events = {}

-- ---------- GUI-Attrappen ----------
local registry = {}
local function comp(typ)
	local o = { typ = typ, kinder = {}, sichtbar = true }
	return setmetatable(o, { __index = function(_, k)
		return function(self, ...)
			local a = { ... }
			if k == "onClick" or k == "onToggle" then self.handler = a[1]
			elseif k == "setText" then self.text = a[1]
			elseif k == "addItem" or k == "addRow" then self.kinder[#self.kinder + 1] = a[1]
			elseif k == "deleteAll" then self.kinder = {}
			elseif k == "setVisible" then self.sichtbar = a[1]
			elseif k == "isVisible" then return self.sichtbar
			elseif k == "getLayout" then rawset(self, "layout", rawget(self, "layout") or comp("layout")); return rawget(self, "layout")
			elseif k == "setLayout" then self.layout = a[1]
			end
		end
	end })
end
local function klasse(typ, extra)
	return { new = function(...) local c = comp(typ); if extra then extra(c, ...) end; return c end }
end

api = {
	type = {
		ComponentType = { GAME_TIME = 1, LINE = 2, TRANSPORT_VEHICLE = 3, NAME = 4 },
		enum = { TransportVehicleState = { IN_DEPOT = 0, EN_ROUTE = 1, GOING_TO_DEPOT = 2, AT_TERMINAL = 3 } },
	},
	engine = {
		util = { getWorld = function() return 0 end },
		getComponent = function(id, typ)
			if typ == 1 then return { gameTime = zeitMs } end
			if typ == 2 and id == 42 then return { stops = { { stationGroup = 900 }, { stationGroup = 901 } } } end
			if typ == 3 then return fahrzeuge[id] end
			if typ == 4 then return ({ [42] = { name = "RB 61" }, [900] = { name = "Waldenberg" }, [901] = { name = "Hyxel" } })[id] end
		end,
		system = {
			lineSystem = { getLines = function() return { 42 } end },
			transportVehicleSystem = { getLineVehicles = function(l) return l == 42 and { 501, 502 } or {} end },
		},
	},
	cmd = {
		make = {
			setVehicleManualDeparture = function(v, an) return { "manuell", v, an } end,
			setVehicleShouldDepart = function(v) return { "los", v } end,
		},
		sendCommand = function(c) befehle[#befehle + 1] = c end,
	},
	gui = {
		comp = {
			TextView = klasse("TextView", function(c, t) c.text = t end),
			Button = klasse("Button"), CheckBox = klasse("CheckBox"), Table = klasse("Table"),
			Component = klasse("Component"), ScrollArea = klasse("ScrollArea"), Window = klasse("Window"),
		},
		layout = { BoxLayout = klasse("BoxLayout") },
		util = {
			Size = { new = function(w, h) return { w, h } end },
			getById = function(id) registry[id] = registry[id] or comp(id); return registry[id] end,
		},
	},
}
game = { interface = { sendScriptEvent = function(id, name, param) events[#events + 1] = { "takt_helfer.lua", id, name, param } end } }

-- ---------- Script laden ----------
dofile("takt_helfer_1/mod.lua")
pruefe(data().info.name == "Takt-Helfer", "mod.lua liefert info")

dofile("takt_helfer_1/res/config/game_script/takt_helfer.lua")
local script = data()

script.guiInit()
local leiste = rawget(registry["gameInfo"], "layout")
pruefe(leiste and #leiste.kinder == 1, "Button \"Takt\" in der unteren Leiste")

-- Tabelle mitschneiden, um später in ihre Zeilen zu klicken
local tabelle
do
	local orig = api.gui.comp.Table.new
	api.gui.comp.Table.new = function(...) tabelle = orig(...); return tabelle end
end

-- Fenster öffnen
leiste.kinder[1].handler()
pruefe(tabelle and #tabelle.kinder == 1, "Fenster zeigt eine Zeile für Linie RB 61")
local zeile = tabelle.kinder[1]
pruefe(zeile[1].text == "RB 61", "Linienname in Spalte 1")
local knoten = zeile[4].layout.kinder[2]
pruefe(knoten.text == "Waldenberg", "Taktknoten zeigt ersten Halt")

-- Klicks: "An" anhaken, Takt fünfmal "+"
zeile[2].handler(true)
local plus = zeile[3].layout.kinder[3]
for i = 1, 5 do plus.handler() end
pruefe(zeile[3].layout.kinder[2].text == "5 min", "Takt-Anzeige steht auf 5 min")
pruefe(#events == 6, "6 Events an den Engine-Thread gesendet")
for _, e in ipairs(events) do script.handleEvent(e[1], e[2], e[3], e[4]) end
pruefe(script.save().linien["42"].aktiv == true, "Event aktiviert Linie im Engine-State")

-- Ablauf: beide Züge kommen am Knoten an
for i = 1, 5 do zeitMs = zeitMs + 1000; script.update() end
local manuell = 0
for _, b in ipairs(befehle) do if b[1] == "manuell" and b[3] == true then manuell = manuell + 1 end end
pruefe(manuell == 2, "beide Züge Richtung Knoten auf manuelle Abfahrt gesetzt")

fahrzeuge[501].state, fahrzeuge[502].state = 3, 3
befehle = {}
for i = 1, 60 do zeitMs = zeitMs + 1000; script.update() end
local los = {}
for _, b in ipairs(befehle) do if b[1] == "los" then los[#los + 1] = b[2] end end
pruefe(#los == 1, "nur ein Zug fährt sofort, der zweite wartet auf den Takt")

befehle = {}
for i = 1, 300 do zeitMs = zeitMs + 1000; script.update() end
los = {}
for _, b in ipairs(befehle) do if b[1] == "los" then los[#los + 1] = b[2] end end
pruefe(#los == 1, "zweiter Zug fährt nach 5 Minuten Takt")

-- GUI bekommt den State und aktualisiert die Statuszeile
script.load(script.save())
script.guiUpdate()
pruefe(true, "load/guiUpdate laufen ohne Fehler")

-- Abschalten
script.handleEvent("__takt_helfer__", "__takt_helfer__", "konfig", { linie = 42, felder = { aktiv = false } })
local frei = 0
for _, b in ipairs(befehle) do if b[1] == "manuell" and b[3] == false then frei = frei + 1 end end
pruefe(frei >= 1, "Abschalten setzt manuelle Abfahrt zurück")

print(fehler == 0 and "\nAlle Tests bestanden." or ("\n" .. fehler .. " Test(s) fehlgeschlagen."))
os.exit(fehler == 0 and 0 or 1)
