--[[
	FreeMinimap "Region map" mode  (EXPERIMENTAL)

	The native minimap can only ever show a fixed number of yards around you (set by the zoom level 0..5);
	making its frame bigger just magnifies the picture, it never reveals more terrain.
	To get "a lot more real estate" this module draws a bigger picture inside the same rectangle,
	centred on the player, with a free zoom (mouse wheel). Toggle with the options panel or "/fmm region".

	Two sources:
	  * "tiles" : the game's own minimap terrain tiles (world/minimaps/<map>/mapA_B.blp, FileDataIDs in
	              FreeMinimap_Tiles.lua). Same imagery and same scale as the real minimap => perfect overlay.
	  * "art"   : the zone's world-map illustration (fallback when no tile data exists for the continent).
]]
local addonName, addonTab = ...
local clip = addonTab.clip
if not clip then return end

local R = CreateFrame("Frame", "FreeMinimapRegion", clip)
R:SetAllPoints(clip)
R:SetFrameStrata("HIGH")
R:SetFrameLevel(2)
R:EnableMouse(true)
R:EnableMouseWheel(true)
R:HookScript("OnEnter", function() if addonTab.ButtonHoverEnter then addonTab.ButtonHoverEnter() end end) --{ buttons shown on mouseover }--
R:Hide()

local bg = R:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0.04, 0.04, 0.04, 1)

local canvas = CreateFrame("Frame", nil, R)
canvas:SetAllPoints(R)

local msg = R:CreateFontString(nil, "OVERLAY", "GameFontNormal")
msg:SetPoint("CENTER")
msg:SetText("")

--{ player marker: a dot that is always visible + a rotating arrow on top (if the texture exists) }--
local marker = CreateFrame("Frame", nil, R)
marker:SetAllPoints(R)
marker:SetFrameLevel(R:GetFrameLevel() + 3)
local dotBorder = marker:CreateTexture(nil, "ARTWORK", nil, 1)
dotBorder:SetSize(9, 9); dotBorder:SetPoint("CENTER"); dotBorder:SetColorTexture(0, 0, 0, 1)
local dot = marker:CreateTexture(nil, "ARTWORK", nil, 2)
dot:SetSize(5, 5); dot:SetPoint("CENTER"); dot:SetColorTexture(1, 0.9, 0.1, 1)
local arrow = marker:CreateTexture(nil, "OVERLAY")
arrow:SetSize(28, 28); arrow:SetPoint("CENTER")
arrow:SetTexture("Interface\\Minimap\\ROTATING-MINIMAPARROW")

local tiles = {}
local state = { mapID = nil, n = 0, cols = 1, lw = 1, lh = 1, tw = 256, th = 256 }

--{ climb from micro/dungeon maps up to the zone map so we see the whole region }--
local function ResolveMap(mapID)
	local id = mapID
	for _ = 1, 6 do
		local info = C_Map.GetMapInfo(id)
		if not info then break end
		if info.mapType and info.mapType > Enum.UIMapType.Zone and info.parentMapID and info.parentMapID > 0 then
			id = info.parentMapID
		else
			break
		end
	end
	return id
end

local function LoadMap(id)
	state.mapID = id
	state.n = 0
	local layers = C_Map.GetMapArtLayers(id)
	local layer = layers and layers[1]
	local texs = layer and C_Map.GetMapArtLayerTextures(id, 1)
	if not layer or not texs or #texs == 0 then
		for _, t in ipairs(tiles) do t:Hide() end
		return
	end
	state.lw, state.lh = layer.layerWidth, layer.layerHeight
	state.tw, state.th = layer.tileWidth, layer.tileHeight
	state.cols = math.max(math.ceil(state.lw / state.tw), 1)
	state.n = #texs
	for i = 1, state.n do
		local t = tiles[i]
		if not t then
			t = canvas:CreateTexture(nil, "BACKGROUND")
			tiles[i] = t
		end
		t:SetTexture(texs[i])
		t:Show()
	end
	for i = state.n + 1, #tiles do tiles[i]:Hide() end
end


--{ ===================== real minimap tiles ===================== }--
local TILE_YARDS = 533.33333333
local TILE_LIMIT = 1500  --{ most tile textures kept on screen (memory / speed guard)

local function GetTileTable(inst)
	return addonTab.TileData and addonTab.TileData[inst] or nil   --{ [A*64+B] = fileID  (A runs east, B runs south)
end

local function XY(vec)
	if type(vec) ~= "table" then return end
	if vec.GetXY then return vec:GetXY() end
	return vec.x, vec.y
end

--{ Each convention turns the API's world vector (u, v) into (west, north) in yards.
--  The usual one (OpenMap, HereBeDragons): vector = (world X = north, world Y = west). }--
local CONVS = {
	function(u, v) return  v,  u end, --{ usual
	function(u, v) return -v,  u end,
	function(u, v) return  v, -u end,
	function(u, v) return -v, -u end,
	function(u, v) return  u,  v end,
	function(u, v) return -u,  v end,
	function(u, v) return  u, -v end,
	function(u, v) return -u, -v end,
}

--{ Settle the convention ONCE from a point whose real position is known (like OpenMap does):
--  Stormwind's flight master, world X (north) -8840.6, Y (west) 489.7, must lie inside the Elwynn / Stormwind maps. }--
local ANCHOR_NORTH, ANCHOR_WEST = -8840.6, 489.7
local ANCHOR_MAPS = { 1429, 1453, 37, 84 } --{ Elwynn / Stormwind: Classic-era and retail ids
local detected
local function DetectConv()
	if detected then return detected end
	for _, m in ipairs(ANCHOR_MAPS) do
		local ok0, i0, p0 = pcall(C_Map.GetWorldPosFromMapPos, m, CreateVector2D(0, 0))
		local ok1, i1, p1 = pcall(C_Map.GetWorldPosFromMapPos, m, CreateVector2D(1, 1))
		if ok0 and ok1 and p0 and p1 then
			local x0, y0 = XY(p0)
			local x1, y1 = XY(p1)
			if type(x0) == "number" and type(x1) == "number" and not (issecretvalue and (issecretvalue(x0) or issecretvalue(x1))) then
				for ci, f in ipairs(CONVS) do
					local w0, n0 = f(x0, y0)
					local w1, n1 = f(x1, y1)
					local margin = 300
					if ANCHOR_NORTH >= math.min(n0, n1) - margin and ANCHOR_NORTH <= math.max(n0, n1) + margin
					   and ANCHOR_WEST >= math.min(w0, w1) - margin and ANCHOR_WEST <= math.max(w0, w1) + margin then
						detected = ci
						return ci
					end
				end
			end
		end
	end
	return 1 --{ no anchor map found: the usual convention
end

local function TileIndex(west, north)
	return 32 - west / TILE_YARDS, 32 - north / TILE_YARDS
end

--{ the tiles live in one container frame that is only moved while walking; they are re-laid
--  out only when the visible tile window, the scale or the continent changes }--
local container = CreateFrame("Frame", nil, canvas)
container:SetSize(1, 1)
local tilePool = {}
local tileKey

--{ Size of the drawing window, never larger than the configured width/height (the clip frame can read a huge
--  or zero size while UIParent is hidden / being shown again: Alt+Z, Alt+W). }--
local function ClipSize()
	local mw, mh = addonTab.GetDims()
	local cw, ch = clip:GetWidth(), clip:GetHeight()
	if type(cw) ~= "number" or cw ~= cw or cw < 1 then cw = mw end
	if type(ch) ~= "number" or ch ~= ch or ch < 1 then ch = mh end
	return math.min(cw, mw), math.min(ch, mh)
end

--{ true when sizes / scales can be trusted (a hidden UIParent makes GetEffectiveScale & co. unreliable) }--
local function CanLayout()
	return UIParent:IsVisible() and clip:IsVisible()
end

--{ returns used (tiles drawn / handled), ppy (px per yard; nil when nothing could be drawn) }--
local function LayoutTiles(pc, id, x, y)
	local inst, w = C_Map.GetWorldPosFromMapPos(id, CreateVector2D(x, y))
	if not inst or not w then return false end
	local tt = GetTileTable(inst)
	if not tt then return false end

	local ci = tonumber(pc.axisOverride) or 0
	if ci < 1 or ci > #CONVS then ci = DetectConv() end
	local u, v = XY(w)
	local west, north = CONVS[ci](u, v)
	local fa, fb = TileIndex(west, north)

	local ppy = math.max(tonumber(pc.tileScale) or 0.5, 0.005) --{ screen px per yard }
	local size = TILE_YARDS * ppy
	local cw, ch = ClipSize()
	local na, nb = math.ceil(cw / 2 / size) + 1, math.ceil(ch / 2 / size) + 1
	if (2 * na + 1) * (2 * nb + 1) > TILE_LIMIT then
		msg:SetText("Too zoomed out for tiles:\nraise the tile scale (or shrink the frame)")
		container:Hide()
		return true
	end
	container:Show()

	--{ move the whole tile layer: one call while walking }--
	container:ClearAllPoints()
	container:SetPoint("TOPLEFT", canvas, "CENTER", -fa * size, fb * size)

	local a0, b0 = math.floor(fa), math.floor(fb)
	local key = string.format("%d:%d:%d:%.5f:%d:%d", inst, a0, b0, size, na, nb)
	if key ~= tileKey then
		tileKey = key
		local n = 0
		for da = -na, na do
			for db = -nb, nb do
				local A, B = a0 + da, b0 + db
				local fid = tt[A * 64 + B]
				if fid then
					n = n + 1
					local t = tilePool[n]
					if not t then
						t = container:CreateTexture(nil, "BACKGROUND")
						tilePool[n] = t
					end
					if t.fid ~= fid then t:SetTexture(fid); t.fid = fid end
					t:ClearAllPoints()
					t:SetSize(size, size)
					t:SetPoint("TOPLEFT", container, "TOPLEFT", A * size, -B * size)
					t:Show()
				end
			end
		end
		for i = n + 1, #tilePool do tilePool[i]:Hide() end
	end
	return true, ppy
end

local warn = R:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
warn:SetPoint("BOTTOM", R, "BOTTOM", 0, 6)
warn:SetText("")

--{ Minimap zoom / view radius / scale ratio as the game reports them right now }--
local function ReadMinimapState()
	local zoom, radius
	if Minimap.GetZoom then local ok, z = pcall(Minimap.GetZoom, Minimap); if ok then zoom = z end end
	if C_Minimap and C_Minimap.GetViewRadius then local ok, r = pcall(C_Minimap.GetViewRadius); if ok then radius = r end end
	local ratio = 1
	local ok, a, b = pcall(function() return Minimap:GetEffectiveScale(), clip:GetEffectiveScale() end)
	if ok and type(a) == "number" and type(b) == "number" and a > 0 and b > 0 then
		ratio = math.min(math.max(a / b, 0.1), 10)
	end
	return zoom, radius, ratio
end

local function SizeOverlay(pc, ppy)
	--{ Scale the real minimap so that its visible disc covers exactly the same yards as the picture under it.
	--  The native minimap cannot be cropped, so it may never be larger than the window. }--
	local zoom, radius, ratio = ReadMinimapState()
	if type(radius) == "number" and ppy and radius > 0 then
		--{ the Minimap may carry a scale of its own: size it in its own units so it covers the same screen area }--
		local S = 2 * radius * ppy * (tonumber(pc.overlayCal) or 1) / ratio
		local cw, ch = ClipSize()
		local limit = math.max(math.min(cw, ch) / ratio, 16)
		if S > limit then
			S = limit
			warn:SetText("Real minimap shrunk to fit the frame (no longer aligned): lower the tile scale")
		else
			warn:SetText("")
		end
		S = math.max(S, 16)
		if math.abs(Minimap:GetWidth() - S) > 0.5 or math.abs(Minimap:GetHeight() - S) > 0.5 then
			Minimap:SetSize(S, S)
			Minimap:SetHitRectInsets(0, 0, 0, 0)
		end
		--{ remember what this layout was built from (see the consistency check below) }--
		R.used = { zoom = zoom, radius = radius, ratio = ratio, S = S, cal = tonumber(pc.overlayCal) or 1, ppy = ppy }
	end
end

--{ icons on the region map: the quest log's (FreeMinimap_Quests.lua) and other addons' (FreeMinimap_Pins.lua); ppy nil = none }--
local function Pins(id, x, y, ppy)
	local cw, ch = ClipSize()
	if addonTab.QuestsUpdate then
		local ok = pcall(addonTab.QuestsUpdate, id, x, y, ppy, cw, ch)
		if not ok and addonTab.QuestsHide then pcall(addonTab.QuestsHide) end
	end
	if addonTab.PinsUpdate then
		local ok = pcall(addonTab.PinsUpdate, id, x, y, ppy, cw, ch)
		if not ok and addonTab.PinsHide then pcall(addonTab.PinsHide) end
	end
end

local function Layout()
	local pc = addonTab.pc
	if not pc then return end
	if not CanLayout() then return end --{ UIParent / clip hidden: sizes are not reliable, wait for OnShow }--
	local z = math.max(tonumber(pc.regionZoom) or 1, 0.01)

	local best = C_Map.GetBestMapForUnit("player")
	if not best then
		msg:SetText("No map")
		marker:Hide()
		Pins()
		return
	end
	local id = ResolveMap(best)

	local pos = C_Map.GetPlayerMapPosition(id, "player")
	local x, y
	if pos then x, y = pos:GetXY() end
	if not x or not y then
		msg:SetText("Position unavailable")
		marker:Hide()
		Pins()
		return
	end

	--{ 1) the game's own minimap tiles }--
	R.usingTiles = false
	if pc.regionSource ~= "art" then
		local used, ppy = LayoutTiles(pc, id, x, y)
		if used then
			R.usingTiles = true
			for _, t in ipairs(tiles) do t:Hide() end
			if not ppy then marker:Hide(); Pins() return end --{ "too zoomed out" message already set }--
			msg:SetText("")
			marker:SetShown(not pc.regionOverlay)
			if pc.regionOverlay then SizeOverlay(pc, ppy) end
			Pins(id, x, y, ppy)
			return
		end
	end
	container:Hide()
	warn:SetText("")

	--{ 2) fallback: the zone's world-map illustration }--
	if id ~= state.mapID then LoadMap(id) end
	if state.n == 0 then
		msg:SetText("No tiles or map art here")
		marker:Hide()
		Pins()
		return
	end
	msg:SetText("")
	marker:SetShown(not pc.regionOverlay) --{ with the overlay, the real minimap draws the player arrow }--

	local ww = C_Map.GetMapWorldSize and C_Map.GetMapWorldSize(id)
	local artPpy = (ww and ww > 0) and z * state.lw / ww or nil
	if pc.regionOverlay and artPpy then SizeOverlay(pc, artPpy) end

	local px, py = x * state.lw * z, y * state.lh * z
	local tw, th = state.tw * z, state.th * z
	for i = 1, state.n do
		local col = (i - 1) % state.cols
		local row = math.floor((i - 1) / state.cols)
		local t = tiles[i]
		t:ClearAllPoints()
		t:SetSize(tw, th)
		t:SetPoint("TOPLEFT", canvas, "CENTER", col * tw - px, py - row * th)
	end

	local facing = GetPlayerFacing and GetPlayerFacing()
	if facing then arrow:SetRotation(facing) end
	Pins(id, x, y, artPpy)
end

local acc, acc2 = 0, 0
local failed = false
local inLayout = false
local function RunLayout()
	if inLayout or not R:IsShown() then return end
	inLayout = true --{ SizeOverlay resizes the Minimap, whose OnSizeChanged hook calls back into us }--
	local ok, err = pcall(Layout)
	inLayout = false
	if not ok and not failed then
		failed = true
		msg:SetText("Region map error:\n" .. tostring(err))
	elseif ok then
		failed = false
	end
	return ok
end

--[[ Re-sync the region map with the minimap (zoom, scale, size, position).
	Root cause of the "out of sync until I scroll in and out" bug: the game applies a minimap zoom / indoor-outdoor
	view-radius change a moment AFTER SetZoom / the event, and the old code only re-read it on a 50 ms poll that
	was cached by tile key and never looked at the Minimap's own scale; FMM_Square (zone change, Edit Mode, cinematics)
	resized the Minimap back to a square without telling the region map. Now every such change calls this, which
	drops the tile cache, lays out immediately, and again on the next frame and 0.1 s later. ]]
local pendA, pendB
function addonTab.RegionResync()
	tileKey = nil
	R.used = nil
	RunLayout()
	if not C_Timer or not C_Timer.After then return end
	if not pendA then
		pendA = true
		C_Timer.After(0, function() pendA = false; tileKey = nil; RunLayout() end)
	end
	if not pendB then
		pendB = true
		C_Timer.After(0.1, function() pendB = false; tileKey = nil; RunLayout() end)
	end
end
R.resyncs = 0

--{ cheap periodic consistency check: does the Minimap still look like what the last layout produced? }--
local function Inconsistent()
	local pc = addonTab.pc
	if not pc or not pc.regionEnabled or not pc.regionOverlay or not CanLayout() then return false end
	local u = R.used
	if not u then return R.usingTiles or false end --{ nothing laid out yet while it should have been }--
	local zoom, radius, ratio = ReadMinimapState()
	if zoom ~= u.zoom or radius ~= u.radius or math.abs(ratio - u.ratio) > 0.001 then return true end
	if math.abs(Minimap:GetWidth() - u.S) > 0.5 or math.abs(Minimap:GetHeight() - u.S) > 0.5 then return true end
	if (tonumber(pc.overlayCal) or 1) ~= u.cal then return true end
	return false
end

R:SetScript("OnUpdate", function(_, e)
	acc = acc + e
	acc2 = acc2 + e
	if acc2 >= 0.75 then
		acc2 = 0
		if Inconsistent() then
			R.resyncs = R.resyncs + 1
			addonTab.RegionResync()
		end
	end
	if acc < 0.05 then return end
	acc = 0
	RunLayout()
end)
R:SetScript("OnShow", function() addonTab.RegionResync() end)

-- Fonction unique de zoom pour la Region Map
local function ZoomRegion(delta)
    local pc = addonTab.pc
    if not pc then return end
    local k = delta > 0 and 1.15 or (1 / 1.15)
    if R.usingTiles then
        pc.tileScale = math.min(math.max((tonumber(pc.tileScale) or 0.5) * k, 0.02), 20)
    else
        pc.regionZoom = math.min(math.max((tonumber(pc.regionZoom) or 1) * k, 0.02), 50)
    end
    if addonTab.RefreshOptions then addonTab.RefreshOptions() end
    addonTab.RegionResync()
end

-- Appliquer le zoom au cadre de la Region Map
R:SetScript("OnMouseWheel", function(_, delta)
    ZoomRegion(delta)
end)

-- Intercepter la molette sur la vraie Minimap pour zoomer aussi la Region Map
Minimap:HookScript("OnMouseWheel", function(_, delta)
    if addonTab.pc and addonTab.pc.regionEnabled then
        ZoomRegion(delta)
    end
end)
--{ the game applies a zoom / size change asynchronously: re-sync on those too }--
Minimap:HookScript("OnSizeChanged", function() addonTab.RegionResync() end)
Minimap:HookScript("OnShow", function() addonTab.RegionResync() end)
hooksecurefunc(Minimap, "SetZoom", function() addonTab.RegionResync() end)

local savedRotate
function addonTab.ApplyRegionState()
	local pc = addonTab.pc
	if not pc then return end
	local on = pc.regionEnabled and true or false
	R:SetShown(on)

	if on and pc.regionOverlay then
		--{ real minimap on top of the region map }--
		Minimap:SetAlpha(1)
		Minimap:EnableMouse(true)
		Minimap:EnableMouseWheel(true)
		Minimap:SetMaskTexture(pc.overlayRound and "Interface\\CharacterFrame\\TempPortraitAlphaMask" or "Interface\\ChatFrame\\ChatFrameBackground")
		--{ the map art is drawn north-up, so the minimap must not rotate }--
		if GetCVar("rotateMinimap") == "1" then
			savedRotate = "1"
			SetCVar("rotateMinimap", "0")
		end
	elseif on then
		--{ region map only, real minimap hidden }--
		Minimap:SetAlpha(0)
		Minimap:EnableMouse(false)
		Minimap:EnableMouseWheel(false)
	else
		Minimap:SetAlpha(1)
		Minimap:EnableMouse(true)
		Minimap:EnableMouseWheel(true)
		Minimap:SetMaskTexture("Interface\\ChatFrame\\ChatFrameBackground")
		if savedRotate then
			SetCVar("rotateMinimap", savedRotate)
			savedRotate = nil
		end
	end
	if on then addonTab.RegionResync() end
end

function addonTab.SetRegion(on)
	if not addonTab.pc then return end
	addonTab.pc.regionEnabled = on and true or false
	addonTab.ApplyRegionState()
	if addonTab.RefreshOptions then addonTab.RefreshOptions() end
end

--{ apply saved state once the SavedVariables are loaded and the layout has been built }--
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function()
	C_Timer.After(0.5, addonTab.ApplyRegionState)
end)
