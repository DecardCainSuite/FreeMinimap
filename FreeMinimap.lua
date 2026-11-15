local addonName, addonTab = ... --[[ Using addonName, addonTab here in the init file for ubiquity ]]
--[[ Free Minimap: built from DejaMinimap by Dejablue, Bõb, Ertkal and Eurytus (with Thibault's changes). ]]

--{ The old addon would fight over the same minimap: run only one of them }--
if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("DejaMinimap") then
	addonTab.conflict = true
	local warn = CreateFrame("Frame")
	warn:RegisterEvent("PLAYER_LOGIN")
	warn:SetScript("OnEvent", function()
		print("|cffff8a3dFree Minimap|r is paused: the old DejaMinimap is still enabled. Disable DejaMinimap in the AddOns list, then reload.")
	end)
	return
end
local L = addonTab.L --{ Localization
addonTab.version = C_AddOns.GetAddOnMetadata(addonName, "Version")

--{ Default Character SavedVariables }--
if not addonTab.character then
	addonTab.character = {
		updateSize = false,
		size = 192, --{ legacy value (Edit Mode driven); only used once to migrate to width/height
		migrated = false,
		width = 192,       --{ minimap viewport width in pixels (no upper limit)
		height = 192,      --{ minimap viewport height in pixels (no upper limit)
		scale = 1,         --{ global scale of the whole minimap cluster
		buttonScale = 1,   --{ scale of the buttons/text around the minimap (independent from size)
		zoom = -1,         --{ native zoom 0..5, -1 = leave untouched
		regionEnabled = false, --{ "region map" mode (see FreeMinimap_Region.lua)
		regionZoom = 1,    --{ region map magnification (screen px per map-art px)
		regionSource = "tiles", --{ "tiles" (the game's minimap terrain) or "art" (world-map illustration)
		tileScale = 0.5,   --{ tiles mode: screen pixels per yard (1 yard = 1 px at 1.0)
		axisOverride = 0,  --{ 0 = auto-detect the world-axis convention, 1..8 = force one (/fmm axes)
		regionOverlay = true, --{ keep the REAL minimap on top of the region map, scaled to match it
		overlayRound = true,  --{ real minimap shown as a disc (true) or a square (false)
		overlayCal = 1,       --{ fine calibration of the overlay size if it does not line up with the map
		regionQuests = true,  --{ the quest log's quests and their areas drawn on the region map
		regionPins = true,    --{ other addons' minimap icons (Questie, RestedXP, TomTom…) also drawn on the region map
	}
end

--{ SavedVariables Loader }--
if not addonTab.loader then
	addonTab.loader = CreateFrame("Frame")
	addonTab.loader:RegisterEvent("ADDON_LOADED") --{ Payload: addOnName, containsBindings

	addonTab.loader:SetScript("OnEvent", function(self, event, ...)
		-- print(event)
		self[event](self, ...)
	end)
end

function addonTab.loader:ADDON_LOADED(loadedName)
	if loadedName ~= addonName then return end
	local function initDB(db, defaults)
		if type(db) ~= "table" then db = {} end
		if type(defaults) ~= "table" then return db end
		for k, v in pairs(defaults) do
			if type(v) == "table" then
				db[k] = initDB(db[k], v)
			elseif type(v) ~= type(db[k]) then
				db[k] = v
			end
		end
		return db
	end

	--{ Character SavedVariables (kept as the starting point of this character's profile) }--
	_G[addonName.."_PC"] = initDB(_G[addonName.."_PC"], addonTab.character)
	local legacy = _G[addonName.."_PC"]

	--{ Migrate the old single "size" value to width/height once }--
	if not legacy.migrated then
		legacy.width = legacy.size or 192
		legacy.height = legacy.size or 192
		legacy.migrated = true
	end

	--{ Profiles (account wide, each character picks one). A character without a profile gets one named after it,
	--  made from its own settings, so nothing changes until profiles are used. }--
	FreeMinimapDB = type(FreeMinimapDB) == "table" and FreeMinimapDB or {}
	local LFP = LibStub and LibStub("LibFreeProfiles-1.0", true)
	addonTab.pc = legacy
	if LFP then
		local function prepare(d)
			initDB(d, addonTab.character)
			d.migrated = true
		end
		--{ A new character starts from its FreeMinimap_PC values (shipped defaults / migrated DejaMinimap settings):
		--  seed its profile BEFORE the library runs, so that perCharacter finds it and leaves it alone. }--
		local ck = LFP.CharKey()
		local store = FreeMinimapDB
		store.profiles = type(store.profiles) == "table" and store.profiles or {}
		store.profileKeys = type(store.profileKeys) == "table" and store.profileKeys or {}
		if ck and (not store.profileKeys[ck] or not store.profiles[store.profileKeys[ck]]) then
			store.profiles[ck] = store.profiles[ck] or LFP.Copy(legacy)
			store.profileKeys[ck] = ck
		end
		addonTab.profiles = LFP:New("FreeMinimap", FreeMinimapDB, function(d)
			addonTab.pc = d
			if addonTab.ApplyLayout then addonTab.ApplyLayout() end
			if addonTab.ApplyRegionState then addonTab.ApplyRegionState() end
			if addonTab.RefreshOptions then addonTab.RefreshOptions() end
		end, prepare, nil, { perCharacter = true }) --{ LibFreeProfiles MINOR 2+; older versions ignore the option }--
		if ck then addonTab.pc = addonTab.profiles:Data() end
	end

	self:UnregisterEvent("ADDON_LOADED")
end

--[[
--{ SavedVariables Initialization Complete }--
--]]

--{ Viewport frames }--
--  clip    : rectangular window (width x height). The (square) Minimap lives inside it and is cropped by it.
--  overlay : always-on-top frame for texts that must stay visible in every mode.
addonTab.clip = CreateFrame("Frame", "FreeMinimapClip", MinimapCluster)
addonTab.clip:SetClipsChildren(true)
addonTab.clip:SetAllPoints(MinimapCluster)
addonTab.clip:SetFrameStrata("HIGH")
addonTab.overlay = CreateFrame("Frame", "FreeMinimapOverlay", addonTab.clip)
addonTab.overlay:SetAllPoints(addonTab.clip)
addonTab.overlay:SetFrameLevel(20)
addonTab.overlay:EnableMouse(false)
local clip = addonTab.clip

function addonTab.GetDims()
	local pc = addonTab.pc or addonTab.character
	local w = math.max(tonumber(pc.width) or 192, 16)
	local h = math.max(tonumber(pc.height) or 192, 16)
	return w, h
end

--{ Minimap Coordinates (a small frame of its own: placed like the game's buttons, see FreeMinimap_Buttons.lua) }--
addonTab.coordsFrame = CreateFrame("Frame", "FreeMinimapCoords", addonTab.overlay)
addonTab.coordsFrame:SetSize(110, 18)
addonTab.coordsFrame:EnableMouse(false)
local coordFS = addonTab.coordsFrame:CreateFontString(nil, "OVERLAY", "GameTooltipText")
	coordFS:SetTextColor(1, 1, 1)
	coordFS:SetPoint("CENTER")
addonTab.coordsText = coordFS

local function coordRefresh()
	local uiMapID = C_Map.GetBestMapForUnit("player")
	if not uiMapID then return end
	local mapInfo = C_Map.GetMapInfo(uiMapID)
	if not mapInfo.mapID then coordFS:SetText("--, --") return end
	local pos = C_Map.GetPlayerMapPosition(mapInfo.mapID, "player")
	if (pos == nil) or (pos.x == nil) or (pos.y == nil) then
		coordFS:SetText("--, --")
		return
	end
	if pos and pos.x ~= 0 and pos.y ~= 0 then
		coordFS:SetFormattedText("%.1f, %.1f", pos.x*100, pos.y*100)
	end
end

local timeElapsed = 0
addonTab.loader:SetScript("OnUpdate", function(self, elapsed)
	local inInstance, instanceType = IsInInstance()
	if not IsInInstance(player) then
		timeElapsed = timeElapsed + elapsed
		if timeElapsed >= 1 then
			coordRefresh()
			timeElapsed = 0
		end
	else
		coordFS:SetFormattedText("")
	end
end)

--{ Guard so that our own SetZoom calls are not saved as the user's choice }--
local zoomLock = false

--{ Applies width / height / scale / zoom / buttons layout. `force` skips the FarmHud modifier-key check. }--
local function FMM_Square(force)
	if not force and IsModifierKeyDown() then return end --{ FarmHud compatibility
	local pc = addonTab.pc
	if not pc then return end
	--{ UIParent hidden (Alt+Z / Alt+W): frame sizes and scales read now are unreliable. Wait for UIParent's OnShow. }--
	if not UIParent:IsVisible() then
		addonTab.layoutPending = true
		return
	end
	--{ The cluster is protected on this client: its size and scale can't change during a fight
	--  ("FreeMinimap tried to call the protected function MinimapCluster:SetSize()/SetScaleBase()"). After the fight. }--
	if InCombatLockdown() then
		addonTab.layoutAfterCombat = true
		return
	end
	addonTab.layoutAfterCombat = nil
	addonTab.layoutPending = nil

	local w, h = addonTab.GetDims()
	local side = math.min(w, h) --{ the real Minimap stays SQUARE (no stretching) and cannot be cropped: it never exceeds the window }--
	local scale = pc.buttonScale or 1
	local clusterScale = math.max(tonumber(pc.scale) or 1, 0.05)

	--{ only what differs (Edit Mode re-applies its own size / scale; setting the same values again is useless) }--
	local cw, ch = MinimapCluster:GetSize()
	if not cw or math.abs(cw - w) > 0.01 or math.abs(ch - h) > 0.01 then MinimapCluster:SetSize(w, h) end
	if math.abs((MinimapCluster:GetScale() or 1) - clusterScale) > 0.0001 then MinimapCluster:SetScale(clusterScale) end
	if addonTab.ApplyPosition then addonTab.ApplyPosition() end --{ free position (FreeMinimap_Position.lua) }--

	clip:ClearAllPoints()
	clip:SetAllPoints(MinimapCluster)

	Minimap:SetParent(clip)
	Minimap:SetFrameStrata("HIGH")
	Minimap:SetFrameLevel(10) --{ I suspect the Minimap.Selection frame is covering the Minimap after the MinimapCluster is hidden and then show, as with cinematics. This raises the minimap and its elements back to being interactable.
	Minimap:ClearAllPoints()
	Minimap:SetPoint("CENTER", clip, "CENTER", 0, 0)
	Minimap:SetSize(side, side)
	--{ only the visible rectangle should react to the mouse }--
	Minimap:SetHitRectInsets((side - w) / 2, (side - w) / 2, (side - h) / 2, (side - h) / 2)

	--{ Minimap Square Texture Mask }--
	Minimap:SetMaskTexture('Interface\\ChatFrame\\ChatFrameBackground')

	--{ Compass Texture }--
	MinimapCompassTexture:Hide()

	--{ Coordinates font }--
	coordFS:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")

	if TimeManagerClockTicker then
		TimeManagerClockTicker:SetFont("Fonts\\FRIZQT__.TTF", select(2, TimeManagerClockTicker:GetFont()), "OUTLINE")
	end

	if Minimap.ZoomHitArea then
		Minimap.ZoomHitArea:SetParent(Minimap)
		Minimap.ZoomHitArea:SetFrameLevel(100)
		Minimap.ZoomHitArea:SetScale(scale)
	end

	--{ Every button / text around the map: FreeMinimap_Buttons.lua }--
	if addonTab.PlaceButtons then addonTab.PlaceButtons() end

	--{ Hack to make the damned thing update with each size value change.
	zoomLock = true
	local zoom = Minimap:GetZoom() --{ Get current zoom
	Minimap:SetZoom(5) --{ Zoom out to cache the unzoomed minimap
	Minimap:SetZoom(0) --{ Zoom in to cache the zoomed minimap
	if pc.zoom and pc.zoom >= 0 then zoom = math.min(pc.zoom, 5) end --{ user-chosen native zoom wins
	Minimap:SetZoom(zoom) --{ Set the zoom back to what it was at
	zoomLock = false

	if addonTab.ApplyRegionState then addonTab.ApplyRegionState() end
	if addonTab.RegionResync then addonTab.RegionResync() end
end
addonTab.ApplyLayout = function() FMM_Square(true) end

--{ Remember the zoom level chosen with the mouse wheel / zoom buttons }--
hooksecurefunc(Minimap, "SetZoom", function(_, level)
	if zoomLock or not addonTab.pc then return end
	addonTab.pc.zoom = level
	if addonTab.RefreshOptions then addonTab.RefreshOptions() end
end)

--{ Resize and Make Minimap Square }--
addonTab.loader:RegisterEvent("PLAYER_ENTERING_WORLD")
-- addonTab.loader:RegisterEvent("PLAYER_TARGET_CHANGED")
addonTab.loader:RegisterEvent("ZONE_CHANGED")
addonTab.loader:RegisterEvent("ZONE_CHANGED_INDOORS")
addonTab.loader:RegisterEvent("ZONE_CHANGED_NEW_AREA")
--{ zoom / scale / size changes that must re-sync the region map (each has a handler below; registered safely) }--
for _, ev in ipairs({ "MINIMAP_UPDATE_ZOOM", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "LOADING_SCREEN_DISABLED", "CVAR_UPDATE" }) do
	pcall(addonTab.loader.RegisterEvent, addonTab.loader, ev)
end
-- addonTab.loader:RegisterEvent("MINIMAP_PING")
-- addonTab.loader:RegisterEvent("MINIMAP_UPDATE_ZOOM")

addonTab.loader:RegisterEvent("CLIENT_SCENE_CLOSED") --{ Quests, Flythroughs, Vistas, Examples: Artifact Weapon, Silithus World Speaker Scenes.
addonTab.loader:RegisterEvent("CINEMATIC_STOP") --{ Standard cinematics and cutscenes.
addonTab.loader:RegisterEvent("STOP_MOVIE") --{ "Movies"; however those are different...? Dunno
addonTab.loader:RegisterEvent("PERKS_PROGRAM_CLOSE") --{ Trading Post purchase scene

--{ Commented out events are not currently needed but may be in future; events below may only be available for Blizzard's use }
-- addonTab.loader:RegisterEvent("UPDATE_BINDINGS")
-- addonTab.loader:RegisterEvent("CRAFTINGORDERS_UPDATE_PERSONAL_ORDER_COUNTS")
-- addonTab.loader:RegisterEvent("SETTINGS_LOADED")
-- addonTab.loader:RegisterEvent("UPDATE_PENDING_MAIL")
-- addonTab.loader:RegisterEvent("VARIABLES_LOADED")
-- addonTab.loader:RegisterEvent("CVAR_UPDATE")

--{ Resize and Make Minimap Square }--
local function FMM_Square_Timer()
	C_Timer.After(0.07, FMM_Square)
end

local function PlayNice()
	if ( FarmHud ) and  ( FarmHud:IsShown() ) then
		return
	else
		FMM_Square_Timer()
	end
end

function addonTab.loader:CLIENT_SCENE_CLOSED(addonName)
	FMM_Square_Timer()
end

function addonTab.loader:CINEMATIC_STOP(addonName)
	FMM_Square_Timer()
end

function addonTab.loader:STOP_MOVIE(addonName)
	FMM_Square_Timer()
end

function addonTab.loader:PERKS_PROGRAM_CLOSE(addonName)
	FMM_Square_Timer()
end

local function FMM_Resync()
	if addonTab.RegionResync then addonTab.RegionResync() end
end

function addonTab.loader:MINIMAP_UPDATE_ZOOM() FMM_Resync() end --{ also fires when indoors/outdoors changes the view radius
function addonTab.loader:LOADING_SCREEN_DISABLED() FMM_Square_Timer(); FMM_Resync() end
function addonTab.loader:UI_SCALE_CHANGED() FMM_Square_Timer(); FMM_Resync() end
function addonTab.loader:DISPLAY_SIZE_CHANGED() FMM_Square_Timer(); FMM_Resync() end
function addonTab.loader:CVAR_UPDATE(name)
	if name == "uiScale" or name == "useUiScale" or name == "minimapZoom" or name == "rotateMinimap" or name == "minimapInsideZoom" or name == "minimapOutsideZoom" then FMM_Resync() end
end

function addonTab.loader:PLAYER_ENTERING_WORLD(addonName)
	FMM_Square_Timer()
	FMM_Resync()
end

-- function addonTab.loader:PLAYER_TARGET_CHANGED(addonName)
-- 	FMM_Square_Timer()
-- end

function addonTab.loader:ZONE_CHANGED(addonName)
	PlayNice(); FMM_Resync()
end

function addonTab.loader:ZONE_CHANGED_INDOORS(addonName)
	PlayNice(); FMM_Resync()
end

function addonTab.loader:ZONE_CHANGED_NEW_AREA(addonName)
	PlayNice(); FMM_Resync()
end

-- function addonTab.loader:MINIMAP_PING(addonName)
-- 	FMM_Square_Timer()
-- end

-- function addonTab.loader:MINIMAP_UPDATE_ZOOM(addonName)
-- 	FMM_Square_Timer()
-- end

-- function addonTab.loader:UPDATE_BINDINGS(addonName)
-- 	FMM_Square_Timer()
-- end

-- function addonTab.loader:CRAFTINGORDERS_UPDATE_PERSONAL_ORDER_COUNTS(addonName)
-- 	FMM_Square_Timer()
-- end

-- function addonTab.loader:SETTINGS_LOADED(addonName)
-- 	FMM_Square_Timer()
-- end

-- function addonTab.loader:UPDATE_PENDING_MAIL(addonName)
-- 	FMM_Square_Timer()
-- end

-- function addonTab.loader:VARIABLES_LOADED(addonName)
-- 	FMM_Square_Timer()
-- end

-- function addonTab.loader:CVAR_UPDATE(addonName)
-- 	FMM_Square_Timer()
-- end

MinimapCluster.Selection:HookScript("OnShow", function(self)
	FMM_Square()
end)

-- Force le cadre de sélection du mode édition au tout premier plan
if MinimapCluster and MinimapCluster.Selection then
    MinimapCluster.Selection:HookScript("OnShow", function(self)
        self:SetFrameStrata("TOOLTIP")
        self:SetFrameLevel(100)
    end)
end

MinimapCluster.Selection:HookScript("OnHide", function(self)
	FMM_Square()
end)

--{ Edit Mode may re-apply its own layout (size/anchors); re-assert ours afterwards }--
pcall(addonTab.loader.RegisterEvent, addonTab.loader, "EDIT_MODE_LAYOUTS_UPDATED")
function addonTab.loader:EDIT_MODE_LAYOUTS_UPDATED()
	FMM_Square_Timer()
end

hooksecurefunc(EditModeSystemSettingsDialog, "OnSettingValueChanged", function() FMM_Square() end)
hooksecurefunc("Minimap_Update", PlayNice)

--{ Alt+Z / Alt+W hides UIParent: nothing was laid out meanwhile (see FMM_Square). When it comes back, re-apply the layout
--  now, on the next frame and 0.1 s later (the game re-anchors its own frames during OnShow), then re-sync the region map. }--
local function FMM_AfterUIShow()
	FMM_Square(true)
	FMM_Resync()
end
UIParent:HookScript("OnShow", function()
	FMM_AfterUIShow()
	C_Timer.After(0, FMM_AfterUIShow)
	C_Timer.After(0.1, FMM_AfterUIShow)
end)
Minimap:HookScript("OnShow", function()
	if addonTab.layoutPending then FMM_Square(true) end
	FMM_Resync()
end)
