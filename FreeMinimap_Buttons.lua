local addonName, addonTab = ... --[[ Free Minimap: the game's buttons and texts around the minimap ]]
if addonTab.conflict then return end

--[[
Every element the game puts around its minimap (zone text, tracking, calendar, day/night, mail, difficulty,
addon compartment, expansion button, zoom buttons, clock) and our coordinates are placed by us, one by one,
inside the minimap window: a corner or side of the window + an X/Y offset in pixels + a size.
Each one is shown always, only while the mouse is over the minimap, or never.

The game's own header (the bar with the zone name, Edit Mode "Header Underneath", "Icon Scale") no longer decides
where they go: it lays them out from the round minimap's size, which is not ours, hence buttons all over the place.

Protected frames (the cluster and some of its children on this client) cannot be moved during a fight:
everything waits for the end of the fight (PLAYER_REGEN_ENABLED). Only their transparency changes in a fight.
Hidden = transparent and out of the mouse's way (never Hide(): the game shows them again and some are protected).
]]

local clip = addonTab.clip

--{ The window the elements are placed in: same rectangle as the minimap window, not clipped (buttons may stick out). }--
local holder = CreateFrame("Frame", "FreeMinimapButtons", MinimapCluster)
holder:SetAllPoints(clip)
holder:SetFrameStrata("HIGH")
holder:SetFrameLevel(30)
holder:EnableMouse(false)
addonTab.buttonHolder = holder

--{ Element list. get() returns the frame (or nil when this game has none). Order = order in the options. }--
local function cluster(key) return function() return MinimapCluster and MinimapCluster[key] end end
local ELEMENTS = {
	{ key = "zone",        label = "Zone name",         get = cluster("ZoneTextButton") },
	{ key = "coords",      label = "Coordinates",       get = function() return addonTab.coordsFrame end },
	{ key = "clock",       label = "Clock",             get = function() return TimeManagerClockButton end },
	{ key = "tracking",    label = "Tracking",          get = cluster("Tracking") },
	{ key = "calendar",    label = "Calendar",          get = function() return GameTimeFrame end },
	{ key = "diel",        label = "Day / night",       get = cluster("DielFrame") },
	{ key = "mail",        label = "Mail & orders",     get = cluster("IndicatorFrame") },
	{ key = "difficulty",  label = "Instance difficulty", get = cluster("InstanceDifficulty") },
	{ key = "compartment", label = "Addon compartment", get = function() return AddonCompartmentFrame end },
	{ key = "expansion",   label = "Expansion button",  get = function() return ExpansionLandingPageMinimapButton end },
	{ key = "zoom",        label = "Zoom buttons",      get = function() return Minimap and Minimap.ZoomIn end },
}
addonTab.BUTTON_ELEMENTS = ELEMENTS
local function frameOf(el)
	local ok, f = pcall(el.get)
	if ok and type(f) == "table" and f.SetPoint then return f end
end
addonTab.ButtonFrame = frameOf

--{ Defaults: a tidy layout inside the window (also used by "Reset"). show = "always" | "hover" | "hide". }--
addonTab.BUTTON_DEFAULTS = {
	zone        = { show = "hover",  point = "TOP",         x = 0,  y = -2,  scale = 1 },
	coords      = { show = "always", point = "TOP",         x = 0,  y = -18, scale = 1 },
	clock       = { show = "always", point = "BOTTOM",      x = 0,  y = 2,   scale = 1 },
	tracking    = { show = "hover",  point = "TOPLEFT",     x = 2,  y = -2,  scale = 1 },
	calendar    = { show = "hover",  point = "TOPRIGHT",    x = -2, y = -2,  scale = 1 },
	diel        = { show = "hover",  point = "TOPRIGHT",    x = -2, y = -36, scale = 1 },
	mail        = { show = "always", point = "TOPLEFT",     x = 2,  y = -32, scale = 1 },
	difficulty  = { show = "always", point = "BOTTOMRIGHT", x = -2, y = 2,   scale = 1 },
	compartment = { show = "hover",  point = "BOTTOMLEFT",  x = 2,  y = 2,   scale = 1 },
	expansion   = { show = "hover",  point = "LEFT",        x = 2,  y = 0,   scale = 1 },
	zoom        = { show = "hover",  point = "RIGHT",       x = -2, y = 0,   scale = 1 },
}
if addonTab.character then
	addonTab.character.buttons = addonTab.character.buttons or {}
	for k, v in pairs(addonTab.BUTTON_DEFAULTS) do
		addonTab.character.buttons[k] = addonTab.character.buttons[k] or { show = v.show, point = v.point, x = v.x, y = v.y, scale = v.scale }
	end
end

local POINTS = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }

--{ Settings of one element in the current profile (missing values filled from the defaults). }--
function addonTab.ButtonCfg(key)
	local pc = addonTab.pc
	local d = addonTab.BUTTON_DEFAULTS[key]
	if not (pc and d) then return d end
	if type(pc.buttons) ~= "table" then pc.buttons = {} end
	local c = pc.buttons[key]
	if type(c) ~= "table" then c = {}; pc.buttons[key] = c end
	if c.show ~= "always" and c.show ~= "hover" and c.show ~= "hide" then c.show = d.show end
	if not POINTS[c.point] then c.point = d.point end
	if type(c.x) ~= "number" then c.x = d.x end
	if type(c.y) ~= "number" then c.y = d.y end
	if type(c.scale) ~= "number" or c.scale <= 0 then c.scale = d.scale end
	return c
end

function addonTab.ResetButtons(key)
	local pc = addonTab.pc
	if not pc then return end
	if type(pc.buttons) ~= "table" then pc.buttons = {} end
	for k, d in pairs(addonTab.BUTTON_DEFAULTS) do
		if not key or key == k then pc.buttons[k] = { show = d.show, point = d.point, x = d.x, y = d.y, scale = d.scale } end
	end
	if addonTab.PlaceButtons then addonTab.PlaceButtons() end
end

--{ ------------------------------------------------------------ visibility }--
local hovered = false
local owned = {}     --{ frame -> true / "faded" (we keep its alpha) }--
local ownedKey = {}  --{ frame -> element key (for the SetAlpha hook) }--
local mouseOff = {}  --{ frames whose mouse we switched off (to give it back) }--
local settingAlpha = false

local function wantedAlpha(key)
	local c = addonTab.ButtonCfg(key)
	if not c or c.show == "always" then return nil end --{ nil = leave the game's own alpha }--
	if c.show == "hover" and hovered then return 1 end
	return 0
end

local function setAlpha(f, a)
	settingAlpha = true
	f:SetAlpha(a)
	settingAlpha = false
end

local function mouseFrames(key, f)
	local list = { f }
	if type(f.Button) == "table" and f.Button.EnableMouse then list[#list + 1] = f.Button end
	if key == "zoom" and type(Minimap.ZoomOut) == "table" then list[#list + 1] = Minimap.ZoomOut end
	if key == "mail" and type(f.MailFrame) == "table" then list[#list + 1] = f.MailFrame end
	return list
end

local function applyAlpha(el)
	local f = frameOf(el)
	if not f then return end
	local a = wantedAlpha(el.key)
	local frames = mouseFrames(el.key, f)
	for _, x in ipairs(frames) do
		if a then setAlpha(x, a) elseif owned[x] == "faded" then setAlpha(x, 1) end
		owned[x] = a and "faded" or true
		ownedKey[x] = el.key
	end
end

function addonTab.ApplyButtonAlpha()
	for _, el in ipairs(ELEMENTS) do applyAlpha(el) end
end

local function overAny()
	if holder:IsMouseOver(4, -4, -4, 4) then return true end
	for _, el in ipairs(ELEMENTS) do
		local f = frameOf(el)
		if f and f.IsMouseOver and f:IsVisible() and f:IsMouseOver() then return true end
	end
	return false
end

local ticker
local function stopHover()
	if ticker then ticker:Cancel(); ticker = nil end
	hovered = false
	addonTab.ApplyButtonAlpha()
end
local function onEnter()
	if not hovered then
		hovered = true
		addonTab.ApplyButtonAlpha()
	end
	if not ticker then
		ticker = C_Timer.NewTicker(0.5, function()
			if not overAny() then stopHover() end
		end)
	end
end

--{ ------------------------------------------------------------ placement }--
local pending = false
local hooked = {}
local soonQueued = false
local function soon()
	if soonQueued then return end
	soonQueued = true
	C_Timer.After(0, function()
		soonQueued = false
		addonTab.PlaceButtons()
	end)
end

local function hookFrame(f)
	if hooked[f] then return end
	hooked[f] = true
	if f.HookScript then
		pcall(f.HookScript, f, "OnEnter", onEnter)
		pcall(f.HookScript, f, "OnShow", soon) --{ the game re-anchors some of them when they show }--
	end
	if type(f.Button) == "table" and f.Button.HookScript then pcall(f.Button.HookScript, f.Button, "OnEnter", onEnter) end
	--{ the game fades / shows some of them itself: keep ours }--
	hooksecurefunc(f, "SetAlpha", function(self, a)
		if settingAlpha or owned[self] ~= "faded" then return end
		local key = ownedKey[self]
		local want = key and wantedAlpha(key)
		if want and a ~= want then setAlpha(self, want) end
	end)
end

local function protectedInCombat(f)
	return InCombatLockdown() and f.IsProtected and f:IsProtected()
end

local function mouse(frames, on)
	for _, x in ipairs(frames) do
		if x.EnableMouse then
			if not on and (not x.IsMouseEnabled or x:IsMouseEnabled()) then
				x:EnableMouse(false); mouseOff[x] = true
			elseif on and mouseOff[x] then
				x:EnableMouse(true); mouseOff[x] = nil
			end
		end
	end
end

local JUSTIFY = { TOPLEFT = "LEFT", LEFT = "LEFT", BOTTOMLEFT = "LEFT", TOPRIGHT = "RIGHT", RIGHT = "RIGHT", BOTTOMRIGHT = "RIGHT" }

local function placeOne(el)
	local f = frameOf(el)
	if not f then return end
	local c = addonTab.ButtonCfg(el.key)
	local s = math.max(0.05, (c.scale or 1) * ((addonTab.pc and addonTab.pc.buttonScale) or 1))
	hookFrame(f)
	if el.key == "zoom" and type(Minimap.ZoomOut) == "table" then hookFrame(Minimap.ZoomOut) end
	if f:GetParent() ~= holder then f:SetParent(holder) end
	f:SetScale(s)
	f:ClearAllPoints()
	--{ offsets are in the window's pixels whatever the element's own size }--
	f:SetPoint(c.point, holder, c.point, c.x / s, c.y / s)
	if f.SetFrameLevel then f:SetFrameLevel(holder:GetFrameLevel() + 2) end
	if el.key == "zoom" and type(Minimap.ZoomOut) == "table" then
		local o = Minimap.ZoomOut
		if o:GetParent() ~= holder then o:SetParent(holder) end
		o:SetScale(s)
		o:ClearAllPoints()
		o:SetPoint("TOP", f, "BOTTOM", 0, -2)
		if o.SetFrameLevel then o:SetFrameLevel(holder:GetFrameLevel() + 2) end
	elseif el.key == "coords" and addonTab.coordsText then
		local fs = addonTab.coordsText
		fs:ClearAllPoints()
		fs:SetPoint(JUSTIFY[c.point] or "CENTER", f, JUSTIFY[c.point] or "CENTER", 0, 0)
	end
	mouse(mouseFrames(el.key, f), c.show ~= "hide")
end

function addonTab.PlaceButtons()
	if not addonTab.pc then return end
	if InCombatLockdown() then
		pending = true
		addonTab.ApplyButtonAlpha()
		return
	end
	pending = false
	--{ the game's header bar: kept, but invisible (it only drew a background behind the zone name) }--
	if MinimapCluster.BorderTop then setAlpha(MinimapCluster.BorderTop, 0) end
	holder:ClearAllPoints()
	holder:SetAllPoints(clip)
	for _, el in ipairs(ELEMENTS) do
		local f = frameOf(el)
		if f and not protectedInCombat(f) then
			local ok, err = pcall(placeOne, el)
			if not ok and geterrorhandler then geterrorhandler()("Free Minimap, " .. el.key .. ": " .. tostring(err)) end
		end
	end
	addonTab.ApplyButtonAlpha()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("UPDATE_PENDING_MAIL")
pcall(ev.RegisterEvent, ev, "EDIT_MODE_LAYOUTS_UPDATED")
pcall(ev.RegisterEvent, ev, "ADDON_LOADED")
ev:SetScript("OnEvent", function(_, event, arg)
	if event == "PLAYER_REGEN_ENABLED" then
		if pending then addonTab.PlaceButtons() end
		if addonTab.layoutAfterCombat and addonTab.ApplyLayout then addonTab.ApplyLayout() end
	elseif event == "ADDON_LOADED" then
		if arg == "Blizzard_TimeManager" then soon() end --{ the clock button arrives with it }--
	else
		soon()
	end
end)

--{ The game moves its header elements again when the header setting changes or Edit Mode closes. }--
for _, m in ipairs({ "SetHeaderUnderneath", "Layout", "UpdateSystemSettingHeaderUnderneath" }) do
	if MinimapCluster and type(MinimapCluster[m]) == "function" then pcall(hooksecurefunc, MinimapCluster, m, soon) end
end
if EditModeManagerFrame and EditModeManagerFrame.HookScript then EditModeManagerFrame:HookScript("OnHide", soon) end
Minimap:HookScript("OnEnter", onEnter)
addonTab.ButtonHoverEnter = onEnter --{ the region map (FreeMinimap_Region.lua) reveals them too }--
