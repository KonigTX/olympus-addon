-- 1.5.5: the shared map-name labels on Forever's world map (Map.LayoutNames), against a model of the
-- map's canvas that follows Forever 1.60.1's own code: its pins' frame levels (Blizzard_MapCanvas/
-- MapCanvas_PinFrameLevelsManager.lua, the order Blizzard_WorldMap.lua:259-303 adds them in), the
-- explored areas' art as one pin the canvas's size (MapExplorationDataProvider.lua:61-67), its zoom
-- (MapCanvas_ScrollContainerMixin.lua: zoom levels from the fit, :485-516, GetScaleForMinZoom :742,
-- the canvas scaled by Child:SetScale :364) and the way it places a pin (Blizzard_MapCanvas.lua:723-749).
-- The dev's screen on 11-10 (Elwynn Forest, UI scale about 0.71): a label over Goldshire, p1429:426:660,
-- drawn as a dark box left of the town that faded out, no text; /run gave left 209, top 314, width 209,
-- scale 1.4376, the canvas at about 0.6956.
local ns, test, eq, extra = ...
local ADDON_DIR = assert(extra and extra.ADDON_DIR, "tests/run.lua hands ADDON_DIR to this file")

-- A frame with the geometry the labels use: points on its parent, scale, level, regions.
local function Frame(kind, parent)
	local f = { kind = kind, parent = parent, shown = true, level = parent and (parent.level or 0) + 1 or 0, scale = 1,
		w = 0, h = 0, scripts = {}, regions = {} }
	function f:SetParent(p) self.parent = p end
	function f:GetParent() return self.parent end
	function f:Show() self.shown = true end
	function f:Hide() self.shown = false end
	function f:SetShown(on) self.shown = on and true or false end
	function f:IsShown() return self.shown end
	function f:IsVisible()
		local x = self
		while x do if not x.shown then return false end x = x.parent end
		return true
	end
	function f:SetSize(w, h) self.w, self.h = w, h end
	function f:SetWidth(w) self.w = w end
	function f:SetHeight(h) self.h = h end
	function f:GetWidth() return self.w end
	function f:GetHeight() return self.h end
	function f:SetScale(s) self.scale = s end
	function f:GetScale() return self.scale end
	function f:GetEffectiveScale() return self.scale * (self.parent and self.parent:GetEffectiveScale() or 1) end
	function f:SetFrameLevel(l) self.level = l end
	function f:GetFrameLevel() return self.level end
	function f:EnableMouse(on) self.mouse = on end
	function f:SetScript(k, fn) self.scripts[k] = fn end
	function f:GetScript(k) return self.scripts[k] end
	function f:HookScript() end
	function f:ClearAllPoints() self.point = nil end
	function f:SetAllPoints(rel) self.point = { "ALL", rel } end
	function f:SetPoint(p, rel, rp, x, y)
		if type(rel) == "number" then rel, rp, x, y = self.parent, p, rel, rp end
		self.point = { p, rel, rp, x or 0, y or 0 }
	end
	function f:SetText(t) self.text = t end
	function f:GetText() return self.text end
	function f:SetColorTexture(...) self.color = { ... } end
	-- GameFontNormal: about 6.5 units a character at its 12 (enough to size the box by).
	function f:GetUnboundedStringWidth() return #(self.text or "") * 6.5 end
	function f:GetStringWidth() return self:GetUnboundedStringWidth() end
	function f:CreateTexture() local r = Frame("Texture", self); self.regions[#self.regions + 1] = r; return r end
	function f:CreateFontString() local r = Frame("FontString", self); self.regions[#self.regions + 1] = r; return r end
	-- (Any other method, as on the game's objects: nothing this test reads.)
	return setmetatable(f, { __index = function(_, key)
		if type(key) == "string" and key:match("^%u") then return function() end end
	end })
end

-- MapCanvas_PinFrameLevelsManager.lua: levels from 2000 (:3), each type added on top of the last
-- (AddFrameLevel, :62-71), read with GetFrameLevelStart / GetFrameLevelRange (:130-144) and
-- GetValidFrameLevel (:146-157); an unknown type reads as PIN_FRAME_LEVEL_DEFAULT's.
local function Levels()
	local m = { definitions = { PIN_FRAME_LEVEL_DEFAULT = { startLevel = 2000, range = 1 } }, maxLevel = 2000 }
	function m:AddFrameLevel(kind, range)
		range = range or 1
		self.definitions[kind] = { startLevel = self.maxLevel + 1, range = range }
		self.maxLevel = self.maxLevel + range
	end
	function m:GetFrameLevelStart(kind) return (self.definitions[kind] or self.definitions.PIN_FRAME_LEVEL_DEFAULT).startLevel end
	function m:GetFrameLevelRange(kind) return (self.definitions[kind] or self.definitions.PIN_FRAME_LEVEL_DEFAULT).range end
	function m:GetValidFrameLevel(kind, index)
		local d = self.definitions[kind] or self.definitions.PIN_FRAME_LEVEL_DEFAULT
		return d.startLevel + math.max(0, math.min((index or 1), d.range) - 1)
	end
	-- Blizzard_WorldMap.lua:259-279, as Forever 1.60.1 adds them (to the area POIs).
	for _, t in ipairs({ { "PIN_FRAME_LEVEL_WOW_LABS_AREA" }, { "PIN_FRAME_LEVEL_MAP_EXPLORATION" }, { "PIN_FRAME_LEVEL_PLUNDERSTORM_CIRCLE" },
		{ "PIN_FRAME_LEVEL_EVENT_OVERLAY" }, { "PIN_FRAME_LEVEL_GARRISON_PLOT" }, { "PIN_FRAME_LEVEL_FOG_OF_WAR" }, { "PIN_FRAME_LEVEL_QUEST_BLOB" },
		{ "PIN_FRAME_LEVEL_SCENARIO_BLOB" }, { "PIN_FRAME_LEVEL_MAP_HIGHLIGHT" }, { "PIN_FRAME_LEVEL_DEBUG", 4 }, { "PIN_FRAME_LEVEL_DIG_SITE" },
		{ "PIN_FRAME_LEVEL_DUNGEON_ENTRANCE" }, { "PIN_FRAME_LEVEL_DELVE_ENTRANCE" }, { "PIN_FRAME_LEVEL_FLIGHT_POINT" },
		{ "PIN_FRAME_LEVEL_NEIGHBORHOOD_MAP_OBJECTS" }, { "PIN_FRAME_LEVEL_INVASION" }, { "PIN_FRAME_LEVEL_PET_TAMER" },
		{ "PIN_FRAME_LEVEL_SELECTABLE_GRAVEYARD" }, { "PIN_FRAME_LEVEL_DRAGONRIDING_RACE" }, { "PIN_FRAME_LEVEL_AREA_POI" } }) do
		m:AddFrameLevel(t[1], t[2])
	end
	return m
end

-- Forever's world map: Elwynn Forest (1429), its art 1002 x 668 on the canvas, in a container
-- 697 x 465 at the effective scale `ui` (the fit, about 0.6956, is its first zoom level).
local function MapModel(ui)
	local root = Frame("Frame", nil)
	root.scale = ui
	local map = Frame("Frame", root)
	map.mapID, map.levelsManager = 1429, Levels()
	local sc = Frame("ScrollFrame", map)
	sc:SetSize(697, 465)
	local canvas = Frame("Frame", sc)
	canvas:SetSize(1002, 668)
	map.ScrollContainer, sc.Child = sc, canvas
	-- (MapCanvas_ScrollContainerMixin.lua:485-516: the fit, then two more steps to twice it.)
	function sc:Fit()
		local fit = math.min(self.w / canvas.w, self.h / canvas.h)
		self.zoomLevels = { { scale = fit }, { scale = fit * 1.5 }, { scale = fit * 2 } }
		self:Zoom(fit)
	end
	function sc:Zoom(scale) self.currentScale = scale; canvas:SetScale(scale) end -- (:364, Child:SetScale)
	function sc:GetCanvasScale() return self.currentScale end
	function map:GetCanvas() return canvas end
	function map:GetMapID() return self.mapID end
	function map:GetPinFrameLevelsManager() return self.levelsManager end -- (Blizzard_MapCanvas.lua:1029)
	function map:GetCanvasScale() return sc:GetCanvasScale() end
	function map:HasZoomLevels() return sc.zoomLevels ~= nil end
	function map:GetScaleForMinZoom() return sc.zoomLevels[1].scale end
	function map:OnMapChanged() end
	sc:Fit()
	-- The explored areas' art (MapExplorationDataProvider.lua): one pin the canvas's size, at its type's level.
	local explored = Frame("Frame", canvas)
	explored:SetAllPoints(canvas)
	explored:SetFrameLevel(map.levelsManager:GetValidFrameLevel("PIN_FRAME_LEVEL_MAP_EXPLORATION"))
	return { root = root, map = map, sc = sc, canvas = canvas, explored = explored }
end

-- A label's rect on the canvas, in canvas units: its centre and size (its anchor as the label laid it).
local function OnCanvas(f, canvas)
	local p = f.point
	assert(p and p[1] == "CENTER" and p[2] == canvas and p[3] == "TOPLEFT", "centred on the canvas's top left")
	local s = f:GetScale()
	return { x = p[4] * s, y = -p[5] * s, w = f:GetWidth() * s, h = f:GetHeight() * s }
end

-- Map.lua loaded into a namespace of its own, with the shared names `entries`, on the model's map.
local function WithLabels(entries, fn)
	local saved = { CreateFrame = CreateFrame, WorldMapFrame = WorldMapFrame, UIParent = UIParent, C_Map = C_Map }
	local ok, err = pcall(function()
		local m = MapModel(0.71 / 0.71) -- (the container's effective scale: 1, as the dev's /run read it)
		UIParent = m.root
		WorldMapFrame = m.map
		local created = {}
		m.created = created
		CreateFrame = function(kind, _, parent) local f = Frame(kind, parent); created[#created + 1] = f; return f end
		C_Map = setmetatable({ GetMapRectOnMap = function() return nil end, GetMapChildrenInfo = function() return {} end,
			GetMapInfo = function(id) return { mapID = id, parentMapID = 1415 } end }, { __index = saved.C_Map })
		local gns = setmetatable({}, { __index = ns })
		gns.On, gns.RegisterEvent = function() end, function() end
		gns.Gate = { Allowed = function() return true end, Hooks = function() end, Install = function() end }
		gns.IsMember = function() return true end
		gns.db = setmetatable({ showMap = true }, { __index = ns.db })
		gns.MapNames = {
			MAX_PLACES = 128,
			CanEdit = function() return false end,
			Original = function() return "Elwynn Forest" end,
			Name = function(_, original) return original end,
			Entries = function() return entries end,
			Place = function(key)
				local map, x, y = tostring(key):match("^p(%d+):(%d+):(%d+)$")
				if map then return tonumber(map), tonumber(x) / 1000, tonumber(y) / 1000 end
				return tonumber(key)
			end,
		}
		assert(loadfile(ADDON_DIR .. "Map.lua"))("Olympus", gns)
		m.Map = gns.Map
		fn(m)
	end)
	CreateFrame, WorldMapFrame, UIParent, C_Map = saved.CreateFrame, saved.WorldMapFrame, saved.UIParent, saved.C_Map
	if not ok then error(err, 0) end
end

local VILLAGE = { { key = "p1429:426:660", text = "Olympus Village" } }

test("1.5.5 map names: a point label is drawn above the map's explored art (its text in sight), under its icons", function()
	WithLabels(VILLAGE, function(m)
		m.Map.LayoutNames()
		local f = m.Map.nameLabels[1]
		assert(f and f:IsVisible(), "the label is laid out")
		eq(f.text:GetText(), "Olympus Village")
		assert(f.text:IsVisible(), "its text shows")
		local L = m.map.levelsManager
		local kinds = 0
		for _ in pairs(L.definitions) do kinds = kinds + 1 end
		local level = f:GetFrameLevel()
		-- The dev's screen: the label at the canvas's level + 90, under the explored art's pin (2002).
		assert(level > m.explored:GetFrameLevel(), ("over the explored art: %d > %d"):format(level, m.explored:GetFrameLevel()))
		for _, kind in ipairs({ "PIN_FRAME_LEVEL_FOG_OF_WAR", "PIN_FRAME_LEVEL_QUEST_BLOB", "PIN_FRAME_LEVEL_SCENARIO_BLOB", "PIN_FRAME_LEVEL_MAP_HIGHLIGHT" }) do
			assert(level > L:GetValidFrameLevel(kind), "over " .. kind)
		end
		for _, kind in ipairs({ "PIN_FRAME_LEVEL_DIG_SITE", "PIN_FRAME_LEVEL_DUNGEON_ENTRANCE", "PIN_FRAME_LEVEL_FLIGHT_POINT", "PIN_FRAME_LEVEL_AREA_POI" }) do
			assert(level < L:GetValidFrameLevel(kind), "under the icons: " .. kind)
		end
		-- The game's pin frame-level table is read, never written.
		local after = 0
		for _ in pairs(L.definitions) do after = after + 1 end
		eq(after, kinds, "no level type added to the game's table")
		eq(L.maxLevel, L:GetValidFrameLevel("PIN_FRAME_LEVEL_AREA_POI"), "none moved")
		-- A map without that table (another client): above the canvas, as before.
		m.map.GetPinFrameLevelsManager = nil
		m.Map.LayoutNames()
		eq(f:GetFrameLevel(), m.canvas:GetFrameLevel() + m.Map.LEVEL_ABOVE_CANVAS)
	end)
end)

test("1.5.5 map names: the label is centred on its point and covers the printed name at every zoom, its text never smaller than the map's own", function()
	WithLabels(VILLAGE, function(m)
		local Map, sc, canvas = m.Map, m.sc, m.canvas
		local fit = sc.zoomLevels[1].scale
		assert(math.abs(fit - 0.6956) < 0.001, "the dev's canvas scale at the map's widest view: " .. fit)
		-- The printed names under a label, on the canvas (the art's own units): GOLDSHIRE under this
		-- point, and Elwynn's widest one, STORMWIND, as long as a label must cover.
		local printed = { w = 220, h = 26 }
		for _, zoom in ipairs({ fit, fit * 1.5, fit * 2 }) do
			sc:Zoom(zoom)
			Map.LayoutOverlay() -- (as the map's hooks lay it out: its change, a mouse wheel turn, its size)
			local f = Map.nameLabels[1]
			local r = OnCanvas(f, canvas)
			-- Centred on its point (MapCanvasMixin:ApplyPinPosition's arithmetic).
			assert(math.abs(r.x - 1002 * 0.426) < 1e-6 and math.abs(r.y - 668 * 0.660) < 1e-6, ("centred at %.2f, %.2f"):format(r.x, r.y))
			-- Over the printed name, whole.
			assert(r.w >= printed.w and r.h >= printed.h, ("at zoom %.3f the label is %.1f x %.1f on the canvas"):format(zoom, r.w, r.h))
			-- Readable: never smaller on screen than the map window's own text (scale 1 under the container).
			local onScreen = f:GetEffectiveScale() / sc:GetEffectiveScale()
			assert(onScreen >= 1 - 1e-9, ("its text at %.3f of the map's own size"):format(onScreen))
			eq(f.scale, 1 / fit, "sized on the canvas: one size at every zoom")
		end
		-- At the widest view, what the dev's /run read: width 209-210, scale 1.4376, left 209 on the canvas's
		-- frame: the box from 0.426 of the art across, 210 wide, at the container's own scale.
		sc:Zoom(fit)
		Map.LayoutOverlay()
		local f = Map.nameLabels[1]
		eq(f:GetWidth(), Map.NAME_WIDTH)
		assert(math.abs(f:GetScale() - 1.4376) < 0.001, "scale " .. f:GetScale())
		-- A long name widens the box (up to its most); a short one keeps the box that covers the art.
		WithLabels({ { key = "p1429:426:660", text = string.rep("W", 80) } }, function(n)
			n.Map.LayoutNames()
			eq(n.Map.nameLabels[1]:GetWidth(), n.Map.NAME_WIDTH_MAX)
		end)
		eq(Map.NameWidth(nil), Map.NAME_WIDTH)
		eq(Map.NameWidth(300), 320)
	end)
end)

test("1.5.5 map names: maximized or made small again, the labels follow the map's new widest view", function()
	WithLabels(VILLAGE, function(m)
		local Map, sc = m.Map, m.sc
		Map.LayoutNames()
		local watch = assert(Map.nameWatch, "a watch while labels show")
		eq(watch:IsShown(), true)
		local before = Map.nameLabels[1]:GetScale()
		-- Maximized: the container doubles, the map makes its zoom levels again (Blizzard_MapCanvas.lua:73-75).
		sc:SetSize(1394, 930)
		sc:Fit()
		watch.scripts.OnUpdate(watch, 1)
		local after = Map.nameLabels[1]:GetScale()
		assert(math.abs(after - 1 / sc.zoomLevels[1].scale) < 1e-9 and after < before, ("laid out again: %.4f -> %.4f"):format(before, after))
		-- Nothing changed: not laid out again (the watch only reads).
		local laid = 0
		local layout = Map.LayoutNames
		Map.LayoutNames = function(...) laid = laid + 1 return layout(...) end
		watch.scripts.OnUpdate(watch, 1)
		eq(laid, 0)
		Map.LayoutNames = layout
		-- No label: no watch.
		WithLabels({}, function(n)
			n.Map.LayoutNames()
			assert(not n.Map.nameWatch or not n.Map.nameWatch:IsShown(), "no watch without a label")
		end)
	end)
end)

test("1.5.5 map: the continent totals sit over the map's painted layers too, one over the name labels", function()
	WithLabels(VILLAGE, function(m)
		local Map = m.Map
		m.map.mapID = 947
		Map.overlayData[1] = { cont = 1415, count = 10, guilds = {}, on = 947, x = 0.5, y = 0.5 }
		Map.LayoutOverlay()
		local total
		for _, f in ipairs(m.created) do
			if f.count == 10 and f.parent == m.canvas then total = f end
		end
		assert(total and total:IsVisible(), "the continent's total drawn on the canvas")
		local art = Map.ArtLevel(m.canvas)
		assert(art > m.explored:GetFrameLevel(), "the painted layers' top is over the explored art")
		eq(total:GetFrameLevel(), art + 1, "over the painted layers and the name labels")
		assert(total:GetFrameLevel() < m.map.levelsManager:GetValidFrameLevel("PIN_FRAME_LEVEL_DIG_SITE"), "under the icons")
	end)
end)
