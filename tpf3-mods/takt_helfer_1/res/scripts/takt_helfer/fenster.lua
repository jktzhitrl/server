-- Takt-Helfer: Fenster im Spiel (GUI-Thread).

local logik = require "takt_helfer/logik"
local spiel = require "takt_helfer/spiel"

local fenster = {}

local EVENT_ID = "__takt_helfer__"

local ui = { window = nil, tabelle = nil, statusTexte = {}, linien = {} }
local stateGui = { linien = {} }

local function zeit(sek)
	if not sek then return "–" end
	sek = math.floor(sek + 0.5)
	return string.format("%d:%02d", math.floor(sek / 60), sek % 60)
end

local function konfig(linieId)
	return stateGui.linien[tostring(linieId)] or logik.neueLinie()
end

local function senden(linieId, felder)
	-- sofort lokal übernehmen, damit die Anzeige nicht springt
	local key = tostring(linieId)
	local l = stateGui.linien[key] or logik.neueLinie()
	for k, v in pairs(felder) do l[k] = v end
	stateGui.linien[key] = l
	game.interface.sendScriptEvent(EVENT_ID, "konfig", { linie = linieId, felder = felder })
end

local function text(t) return api.gui.comp.TextView.new(t) end

local function knopf(beschriftung, aktion)
	local b = api.gui.comp.Button.new(text(beschriftung), true)
	b:onClick(aktion)
	return b
end

local function zeile(...)
	local layout = api.gui.layout.BoxLayout.new("HORIZONTAL")
	for _, c in ipairs({ ... }) do layout:addItem(c) end
	local comp = api.gui.comp.Component.new("")
	comp:setLayout(layout)
	return comp
end

local function taktText(l)
	return (l.taktMin or 0) == 0 and "Auto" or (l.taktMin .. " min")
end

local function statusText(l)
	if not l.aktiv then return "aus" end
	local a = l.anzeige or {}
	return string.format("%s Fz · Takt %s · zuletzt %s", tostring(a.fahrzeuge or "?"), zeit(a.takt), zeit(a.abstand))
end

local function zeileFuer(info)
	local id = info.id
	local l = konfig(id)

	local an = api.gui.comp.CheckBox.new("")
	an:setSelected(l.aktiv == true, false)
	an:onToggle(function(sel) senden(id, { aktiv = sel }) end)

	local taktAnzeige = text(taktText(l))
	local function aendereTakt(d)
		local neu = math.max(0, math.min(120, (konfig(id).taktMin or 0) + d))
		senden(id, { taktMin = neu })
		taktAnzeige:setText(taktText(konfig(id)))
	end

	local anzahl = math.max(1, #info.halte)
	local knotenAnzeige = text(info.halte[(l.knoten or 0) + 1] or "–")
	local function aendereKnoten(d)
		local neu = ((konfig(id).knoten or 0) + d) % anzahl
		senden(id, { knoten = neu })
		knotenAnzeige:setText(info.halte[neu + 1] or "–")
	end

	local uhr = api.gui.comp.CheckBox.new("")
	uhr:setSelected(l.uhr == true, false)
	uhr:onToggle(function(sel) senden(id, { uhr = sel }) end)

	local status = text(statusText(l))
	ui.statusTexte[tostring(id)] = status

	return {
		text(info.name),
		an,
		zeile(knopf("-", function() aendereTakt(-1) end), taktAnzeige, knopf("+", function() aendereTakt(1) end)),
		zeile(knopf("<", function() aendereKnoten(-1) end), knotenAnzeige, knopf(">", function() aendereKnoten(1) end)),
		uhr,
		status,
	}
end

function fenster.neuAufbauen()
	if not ui.tabelle then return end
	ui.tabelle:deleteAll()
	ui.statusTexte = {}
	ui.linien = spiel.linien()
	for _, info in ipairs(ui.linien) do
		ui.tabelle:addRow(zeileFuer(info))
	end
end

local function erstelleFenster()
	local layout = api.gui.layout.BoxLayout.new("VERTICAL")

	layout:addItem(text(
		"Aktive Linien werden am Taktknoten so lange festgehalten, bis ein voller Takt seit der letzten Abfahrt vergangen ist.\n" ..
		"Takt \"Auto\" = Umlaufzeit / Anzahl Fahrzeuge (wird nach einer Runde gelernt). Uhr = Abfahrt nur zu vollen Taktzeiten."))

	ui.tabelle = api.gui.comp.Table.new(6, "NONE")
	ui.tabelle:setHeader({ text("Linie"), text("An"), text("Takt"), text("Taktknoten"), text("Uhr"), text("Status") })
	local inhalt = api.gui.comp.Component.new("takt_helfer_inhalt")
	local innen = api.gui.layout.BoxLayout.new("VERTICAL")
	innen:addItem(ui.tabelle)
	inhalt:setLayout(innen)
	layout:addItem(api.gui.comp.ScrollArea.new(inhalt, "takt_helfer_scroll"))

	layout:addItem(knopf("Linienliste aktualisieren", fenster.neuAufbauen))

	local wrapper = api.gui.comp.Component.new("takt_helfer_fenster_inhalt")
	wrapper:setLayout(layout)

	ui.window = api.gui.comp.Window.new("Takt-Helfer", wrapper)
	ui.window:addHideOnCloseHandler()
	ui.window:setSize(api.gui.util.Size.new(900, 500))
	ui.window:setPosition(200, 120)
	ui.window:setVisible(false, false)
end

local function umschalten()
	if not ui.window then erstelleFenster() end
	local sichtbar = ui.window:isVisible()
	if not sichtbar then fenster.neuAufbauen() end
	ui.window:setVisible(not sichtbar, false)
end

function fenster.init()
	local ok, err = pcall(function()
		local b = api.gui.comp.Button.new(text("Takt"), true)
		b:onClick(umschalten)
		api.gui.util.getById("gameInfo"):getLayout():addItem(b)
	end)
	if not ok then print("[Takt-Helfer] Button konnte nicht angelegt werden: " .. tostring(err)) end
end

-- Zustand vom Engine-Thread übernehmen
function fenster.load(state)
	if state and state.linien then stateGui = state end
end

local letzteAktualisierung = 0
function fenster.update()
	if not ui.window or not ui.window:isVisible() then return end
	local t = os.clock()
	if t - letzteAktualisierung < 0.5 then return end
	letzteAktualisierung = t
	for key, tv in pairs(ui.statusTexte) do
		tv:setText(statusText(stateGui.linien[key] or logik.neueLinie()))
	end
end

fenster.EVENT_ID = EVENT_ID

return fenster
