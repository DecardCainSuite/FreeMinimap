--[[
	FreeMinimap — the quests of your log on the region map

	The real minimap only shows the quests (and their hatched areas) within its own radius.
	Here, every quest of the log with a point on a zone the region map shows is drawn at its place
	(C_QuestLog.GetQuestsOnMap), in the look of the world map's quest icons, and the area of each quest
	still in progress is drawn as on the world map, with the game's own QuestPOIFrame.

	The quest areas sit under the real minimap (which draws its own inside its disc); the icons are
	only drawn where the real minimap does not reach.
	Positions: world yards from C_Map.GetWorldPosFromMapPos (vector = north, west), the player's from
	the same call on the map the region map is centred on.
]]
local addonName, addonTab = ...
local R = FreeMinimapRegion
if not R then return end

local REFRESH = 1        --{ seconds between two reads of the quest log (and at once after its events)
local REDRAW = 0.05      --{ seconds between two redraws of a quest area while the view keeps changing
local MARGIN = 400       --{ yards around the window where zones are still read
local ICON = 20          --{ icon size
local MARK = 0.6         --{ the state mark over the badge, part of the icon

local BADGE = { atlas = "UI-QuestPoi-QuestNumber", texture = "Interface\\GossipFrame\\ActiveQuestIcon" }
local IN_PROGRESS = { atlas = "Quest-In-Progress-Icon-yellow", texture = "Interface\\GossipFrame\\IncompleteQuestIcon" }
local TURN_IN = { atlas = "UI-QuestPoi-QuestBangTurnIn", texture = "Interface\\GossipFrame\\ActiveQuestIcon" }

local icons = CreateFrame("Frame", "FreeMinimapQuests", R)
icons:SetAllPoints(R)
icons:SetFrameStrata("HIGH")
icons:SetFrameLevel(11)  --{ over the real minimap (10), under other addons' icons (12) }--
icons:EnableMouse(false)

local areas = CreateFrame("Frame", "FreeMinimapQuestAreas", R)
areas:SetAllPoints(R)
areas:SetFrameStrata("HIGH")
areas:SetFrameLevel(8)   --{ over the terrain (its tile layer is at 4), under the real minimap (10) }--
areas:EnableMouse(false)

local quests = {}        --{ { id, mapID, wx (west), wy (north), complete, button } }
local blobs = {}         --{ [mapID] = QuestPOIFrame }
local blobRect = {}      --{ [mapID] = { west0, north0, west1, north1 } (map corners 0,0 and 1,1) }
local blobQuests = {}    --{ [mapID] = { questID, … } drawn }
local blobTracked = {}   --{ [mapID] = the tracked quest's ID when its area is in that zone }
local pool = {}
local dirty, lastRead, lastKey = true, -1, nil
local blobsWork          --{ nil = untested, false = QuestPOIFrame unavailable }

local function IsNum(v) return type(v) == "number" and v == v and not (issecretvalue and issecretvalue(v)) end

local function Enabled()
	local pc = addonTab.pc
	return pc and pc.regionEnabled and pc.regionQuests ~= false and R:IsShown()
end

--{ a map point in world yards: west, north, instance }--
local function World(mapID, x, y)
	if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
	local ok, inst, vec = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
	if not ok or not vec then return end
	local north, west
	if vec.GetXY then north, west = vec:GetXY() else north, west = vec.x, vec.y end
	if IsNum(north) and IsNum(west) then return west, north, inst end
end

local function Look(tex, look)
	if look.atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(look.atlas) then
		tex:SetAtlas(look.atlas)
	else
		tex:SetTexture(look.texture)
		tex:SetTexCoord(0, 1, 0, 1)
	end
end

--{ ===================== zones near the window ===================== }--
local zoneCache = {}     --{ [continent] = { mapID, … } }
local function Continent(mapID)
	local id = mapID
	for _ = 1, 8 do
		local info = C_Map.GetMapInfo(id)
		if not info then return end
		if info.mapType == (Enum.UIMapType.Continent or 2) then return id end
		if not info.parentMapID or info.parentMapID == 0 then return end
		id = info.parentMapID
	end
end

local function Rect(mapID)
	local r = blobRect[mapID]
	if r == nil then
		local w0, n0, i0 = World(mapID, 0, 0)
		local w1, n1 = World(mapID, 1, 1)
		r = (w0 and w1 and w0 ~= w1 and n0 ~= n1) and { w0, n0, w1, n1, i0 } or false
		blobRect[mapID] = r
	end
	return r or nil
end

local function ZonesNear(mapID, inst, pw, pn, halfW, halfH)
	local list = { mapID }
	local cont = Continent(mapID)
	if not cont or not C_Map.GetMapChildrenInfo then return list end
	local zones = zoneCache[cont]
	if not zones then
		zones = {}
		local ok, children = pcall(C_Map.GetMapChildrenInfo, cont, Enum.UIMapType.Zone, true)
		for _, info in ipairs(ok and children or {}) do zones[#zones + 1] = info.mapID end
		zoneCache[cont] = zones
	end
	local wMin, wMax = pw - halfW - MARGIN, pw + halfW + MARGIN
	local nMin, nMax = pn - halfH - MARGIN, pn + halfH + MARGIN
	for _, id in ipairs(zones) do
		if id ~= mapID then
			local r = Rect(id)
			if r and r[5] == inst then
				local a, b = math.min(r[1], r[3]), math.max(r[1], r[3])
				local c, d = math.min(r[2], r[4]), math.max(r[2], r[4])
				if b >= wMin and a <= wMax and d >= nMin and c <= nMax then list[#list + 1] = id end
			end
		end
	end
	return list
end

--{ ===================== icons ===================== }--
--[[ a quest's title and objectives in the tooltip (only = { [objective index] = true }: just those,
	as the game's own area tooltip shows the objectives of the area under the cursor) ]]
local function QuestLines(id, complete, only)
	local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
	GameTooltip:SetText(title or "?", 1, 0.82, 0)
	if complete then
		GameTooltip:AddLine(_G.QUEST_WATCH_QUEST_READY or "Ready for turn-in", 0.5, 0.95, 0.4)
		return
	end
	--{ the objectives: { text, finished } in order (the modern call first, the quest log's lines otherwise) }--
	local list = {}
	if C_QuestLog.GetQuestObjectives then
		local ok, objs = pcall(C_QuestLog.GetQuestObjectives, id)
		if ok and type(objs) == "table" then
			for i, o in ipairs(objs) do
				if type(o) == "table" and o.text then list[i] = { o.text, o.finished } end
			end
		end
	end
	if #list == 0 then
		local index = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id)
		local count, line = _G.GetNumQuestLeaderBoards, _G.GetQuestLogLeaderBoard
		if index and count and line then
			for i = 1, count(index) or 0 do
				local text, _, finished = line(i, index)
				if text then list[#list + 1] = { text, finished } end
			end
		end
	end
	local n = #list
	--[[ the area's objective numbers (GetTooltipIndex) may count from 0 on this client: with them the
		tooltip showed no objective at all (21/11). Taken as they are if they fall within the objectives,
		shifted by one if they start at 0; failing both, every unfinished objective. ]]
	if only then
		local fits, zero = false, false
		for k in pairs(only) do
			if k >= 1 and k <= n then fits = true end
			if k == 0 then zero = true end
		end
		if zero then
			local shifted = {}
			for k in pairs(only) do shifted[k + 1] = true end
			only = shifted
		elseif not fits then
			only = nil
		end
	end
	local shown = 0
	for pass = 1, 2 do
		for i = 1, n do
			local text, finished = list[i][1], list[i][2]
			if (pass == 1 and only and only[i]) or (pass == 2 and not finished) then
				GameTooltip:AddLine((_G.QUEST_DASH or "- ") .. text, 1, 1, 1, true)
				shown = shown + 1
			end
		end
		if shown > 0 then break end
	end
end

local function Enter(self)
	local q = self.quest
	if not q then return end
	if addonTab.ButtonHoverEnter then addonTab.ButtonHoverEnter() end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	QuestLines(q.id, q.complete)
	GameTooltip:AddLine("Click: track this quest", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

local function Click(self)
	local q = self.quest
	if not q then return end
	if C_QuestLog.AddQuestWatch and not (C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType(q.id)) then
		pcall(C_QuestLog.AddQuestWatch, q.id)
	end
	if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then pcall(C_SuperTrack.SetSuperTrackedQuestID, q.id) end
end

local function Wheel(_, delta)
	local fn = R:GetScript("OnMouseWheel")
	if fn then fn(R, delta) end
end

local function NewIcon()
	local b = CreateFrame("Button", nil, icons)
	b:SetSize(ICON, ICON)
	b:SetFrameLevel(icons:GetFrameLevel() + 1)
	b.badge = b:CreateTexture(nil, "ARTWORK")
	b.badge:SetAllPoints()
	Look(b.badge, BADGE)
	b.mark = b:CreateTexture(nil, "OVERLAY")
	b.mark:SetPoint("CENTER")
	b.mark:SetSize(ICON * MARK, ICON * MARK)
	b:RegisterForClicks("LeftButtonUp")
	b:SetScript("OnEnter", Enter)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:SetScript("OnClick", Click)
	b:EnableMouseWheel(true)
	b:SetScript("OnMouseWheel", Wheel)
	b:Hide()
	return b
end

--{ ===================== quest areas (QuestPOIFrame) ===================== }--
--[[ One QuestPOIFrame per zone (only the player's zone: see Read), covering the zone's whole map.
	It draws its shapes for its place on screen at the moment of drawing, so it is drawn again whenever
	its rectangle changes (QuestsUpdate). A new frame replaces it when the zone's quests change. ]]
--[[ The look of the areas' outline. The client has no colour setter for this frame (/fmm pins: DrawAll
	DrawBlob DrawNone SetBorderAlpha SetBorderScalar SetBorderTexture SetFillAlpha SetFillTexture SetMapID…):
	only textures, width and opacity. Tried in game on 15/11 (Thibault):
	  - world map edge (UI-QuestBlob-Outside), scalar 0.25, alpha 200: one blue line with a glow — VALIDATED;
	  - same at 0.6 / 255: glow far too strong;
	  - minimap ring (UI-QuestBlob-MinimapRing): a ring, so two lines across the edge (apart from 0.3),
	    one blue line at 0.12; with a fill: rejected; ring line over a faint glow (two frames): rejected.
	No fill: Thibault wants only the outline. ]]
local LINE = { texture = "Interface\\WorldMap\\UI-QuestBlob-Outside", scalar = 0.25, alpha = 200 }

--[[ Trial (21/11): our own edge textures, whose cross-section copies the real minimap's line as measured
	on Thibault's screenshot (pale blue core #9ECCFC with a sharp inner side, a blue-grey glow #708BC3 on
	the outer side only). How the frame lays a border texture along the edge is unknown, so there are four:
	the profile along the texture's width (u) or height (v), each way round. /fmm edge <0-4> [width]
	switches between them in game (0 = LINE above); pc.edgeStyle / pc.edgeScalar keep the choice. ]]
local MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"
local EDGES = { "fmm_edge1", "fmm_edge2", "fmm_edge3", "fmm_edge4", "fmm_edge5", "fmm_edge6", "fmm_edge7", "fmm_edge8", "fmm_edge9", "fmm_edge10", "fmm_edge11", "fmm_edge12", "fmm_edge13", "fmm_edge14", "fmm_edge15" }
--{ the tracked quest's texture for a style (saturation halved, see FocusLook) }--
local FOCUS = { fmm_edge7 = "fmm_edge12", fmm_edge13 = "fmm_edge13s", fmm_edge14 = "fmm_edge14s" }
--[[ 3 = the right way round (sharp inner side, glow outward), but the frame tints its border: our pale
	#9ECCFC core came out #3C9AFE (red x0.38, green x0.75). 5 = style 3 with the colours divided by that
	tint (red capped at 255: the native red can't be reached); 6 = style 3 in white.
	(21/11, later) 5 and 6 came out in their own colours, untinted: 7 = style 3 recoloured so its core is
	the native #A5D1FF; 8 = style 7 with a 30 % fainter glow. ]]
--[[ (21/11) A quest-area frame given an addon TGA it had not seen turned it into the "missing" green, for
	the whole session, even for ordinary textures; the same files shown first by ordinary textures (the
	/fmm textest grid) displayed fine. So the files are loaded here first, by hidden ordinary textures,
	before any quest-area frame asks for them. (The BLP copies written by Pillow were not read at all.) ]]
local preload = CreateFrame("Frame", nil, UIParent)
preload:SetSize(1, 1); preload:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10); preload:SetAlpha(0)
local toLoad = {}
for _, name in ipairs(EDGES) do toLoad[#toLoad + 1] = name end
for _, name in pairs(FOCUS) do toLoad[#toLoad + 1] = name end
for i, name in ipairs(toLoad) do
	local t = preload:CreateTexture(nil, "ARTWORK")
	t:SetSize(1, 1); t:SetPoint("TOPLEFT", i, 0)
	t:SetTexture("Interface\\AddOns\\" .. addonName .. "\\Media\\" .. name)
end
local function CurrentLook()
	local pc = addonTab.pc
	local style = pc and tonumber(pc.edgeStyle) or 7
	if EDGES[style] then
		return { texture = MEDIA .. EDGES[style], scalar = tonumber(pc and pc.edgeScalar) or 0.35, alpha = 255 }
	end
	return LINE
end
--[[ (21/11, Thibault's captures) On the real minimap only the tracked quest's area has the bright line:
	pale core #A5D1FF with its glow. The other areas get a
	faint line, about a third of the blue. So each zone has two frames: f (the other quests, faint) and
	f.__focus over it (the tracked quest, brighter texture). ]]
local FAINT = 80   --{ border alpha of the untracked areas }
--[[ (21/11, iterations 10-12) The frame shows a border texture in its own colours until it is asked
	UpdateMouseOverTooltip about a point outside its areas; from then on it tints it (red x0.42, green
	x0.77, blue x1): style 7's pale #A5D1FF becomes the blue #46A0FF. On the real minimap the other
	quests have that blue, faint, and the tracked one the pale line. So: the faint frame is asked about a
	point off its map after each drawing (tinted), the focus frame is never asked (pale), and the cursor
	is tested against a third, invisible frame (f.__probe) holding every area.
	Iteration 13: the tracked line was tinted all the same. The state is shared by every quest-area
	frame: the last point asked lights the quest under it and tints the others, everywhere. So after
	every question (drawing, cursor), a point inside the tracked area is asked last (Relight): the
	tracked quest stays lit (pale), the others tinted. The point is searched once on the focus frame
	(it holds only the tracked quest): the quest's own place first, rings around it, then a grid. ]]
local trackedPos = {}   --{ [mapID] = { x, y } the tracked quest's place on that map }
local GRID = 20
local function Ask(g, x, y)
	local ok, a = pcall(g.UpdateMouseOverTooltip, g, x, y)
	return ok and a and a ~= 0
end
local function FindPoint(g, mapID)
	local p = trackedPos[mapID]
	if p then
		if Ask(g, p[1], p[2]) then return p[1], p[2] end
		for r = 1, 8 do
			local d = r * 0.01
			for k = 0, 11 do
				local x, y = p[1] + d * math.cos(k * math.pi / 6), p[2] + d * math.sin(k * math.pi / 6)
				if Ask(g, x, y) then return x, y end
			end
		end
	end
	for i = 1, GRID - 1 do
		for j = 1, GRID - 1 do
			if Ask(g, i / GRID, j / GRID) then return i / GRID, j / GRID end
		end
	end
end
--[[ (21/11, /fmm qdiag + green style 11) Lighting changes nothing: the frame boosts the saturation of
	its border texture (about x2, hue and brightness kept): pale #A5D1FF -> #46A0FF, green (40,230,40) ->
	(0,211,0). The native tracked line is the pale one, so the tracked quest gets style 7 with its
	saturation halved (fmm_edge12), which the frame brings back to #A5D1FF. ]]
local function FocusLook()
	local l = CurrentLook()
	local name = l.texture:match("([^\\]+)$")
	if name and FOCUS[name] then return { texture = MEDIA .. FOCUS[name], scalar = l.scalar, alpha = l.alpha } end
	return l
end
local function FaintLook()
	local l = CurrentLook()
	return { texture = l.texture, scalar = l.scalar, alpha = math.min(l.alpha, FAINT) }
end

local function MakeBlobFrame(mapID, look, level)
	local ok, f = pcall(CreateFrame, "QuestPOIFrame", nil, areas)
	if not ok or not f or type(f.DrawBlob) ~= "function" then return end
	f:SetFrameLevel(level)
	f:EnableMouse(false)
	pcall(f.SetFillTexture, f, "Interface\\WorldMap\\UI-QuestBlob-Inside")
	pcall(f.SetFillAlpha, f, 0)
	pcall(f.SetBorderTexture, f, look.texture)
	pcall(f.SetBorderAlpha, f, look.alpha)
	pcall(f.SetBorderScalar, f, look.scalar)
	if f.SetMapID then pcall(f.SetMapID, f, mapID) end
	f:Hide()
	return f
end

--{ a zone's areas: f for the other quests, f.__focus over it for the tracked one, f.__probe for the cursor }--
local function NewBlob(mapID)
	if blobsWork == false then return end
	local f = MakeBlobFrame(mapID, FaintLook(), areas:GetFrameLevel())
	if not f then blobsWork = false return end
	blobsWork = true
	f.__focus = MakeBlobFrame(mapID, FocusLook(), areas:GetFrameLevel() + 1)
	f.__probe = MakeBlobFrame(mapID, CurrentLook(), areas:GetFrameLevel())
	if f.__probe then f.__probe:SetAlpha(0); pcall(f.__probe.SetBorderAlpha, f.__probe, 0) end
	return f
end

local function Retire(mapID)
	local f = blobs[mapID]
	if f then
		f:Hide()
		f:ClearAllPoints()
		if f.__focus then f.__focus:Hide(); f.__focus:ClearAllPoints() end
		if f.__probe then f.__probe:Hide(); f.__probe:ClearAllPoints() end
		blobs[mapID] = nil
	end
end

--{ a new look for the areas: their frames are made again (the look is set when a frame is made) }--
function addonTab.QuestsRestyle()
	for mapID in pairs(blobs) do Retire(mapID) end
	dirty = true
end

local function DrawBlobs(perMap)
	for mapID in pairs(blobs) do
		local want, had = perMap[mapID], blobQuests[mapID]
		local same = want and had and #want == #had and blobTracked[mapID] == perMap.__tracked[mapID]
		if same then for i = 1, #want do if want[i] ~= had[i] then same = false break end end end
		if not same then Retire(mapID) end
	end
	local tracked = perMap.__tracked
	perMap.__tracked = nil
	for mapID in pairs(blobQuests) do
		if not perMap[mapID] then blobQuests[mapID] = nil end
	end
	wipe(blobTracked)
	for mapID, want in pairs(perMap) do blobQuests[mapID] = want; blobTracked[mapID] = tracked[mapID] end
end

local function HideAll()
	for _, b in ipairs(pool) do b:Hide(); b.quest = nil end
	--{ the area frames are only hidden: their drawing stays valid for when the map shows again }--
	for _, f in pairs(blobs) do
		f:Hide()
		if f.__focus then f.__focus:Hide() end
		if f.__probe then f.__probe:Hide() end
	end
	wipe(quests)
	lastKey = nil
	dirty = true
end
addonTab.QuestsHide = HideAll

--{ ===================== reading the log ===================== }--
local function Read(maps, inst)
	wipe(quests)
	local seen, perMap = {}, {}
	wipe(trackedPos)
	local tracked = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
	for _, mapID in ipairs(maps) do
		local ok, list = pcall(C_QuestLog.GetQuestsOnMap, mapID)
		for _, q in ipairs(ok and list or {}) do
			local id = q.questID
			if id and IsNum(q.x) and IsNum(q.y) and not q.isMapIndicatorQuest
			   and (not _G.HaveQuestData or _G.HaveQuestData(id)) then
				local wx, wy, qi = World(mapID, q.x, q.y)
				local key = wx and (id .. ":" .. math.floor(wx / 4) .. ":" .. math.floor(wy / 4))
				if key and qi == inst and not seen[key] then
					seen[key] = true
					local complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) or false
					quests[#quests + 1] = { id = id, mapID = mapID, wx = wx, wy = wy, complete = complete, tracked = id == tracked }
					if id == tracked then trackedPos[mapID] = { q.x, q.y } end
					--[[ areas: only for the zone the player is in (maps[1]). On this client a QuestPOIFrame draws
						the player's own zone whatever map it is given: the frames of the neighbouring zones drew
						the same areas again, shrunk into their own rectangles (iteration 5, "ghosts"). ]]
					if not complete and mapID == maps[1] then
						perMap[mapID] = perMap[mapID] or {}
						local l = perMap[mapID]
						local dup = false
						for _, x in ipairs(l) do if x == id then dup = true break end end
						if not dup then l[#l + 1] = id end
					end
				end
			end
		end
	end
	for _, l in pairs(perMap) do table.sort(l) end
	local t = {}
	for mapID, l in pairs(perMap) do
		for _, id in ipairs(l) do if id == tracked then t[mapID] = id end end
	end
	perMap.__tracked = t
	for i, q in ipairs(quests) do
		local b = pool[i] or NewIcon()
		pool[i] = b
		b.quest = q
		Look(b.mark, q.complete and TURN_IN or IN_PROGRESS)
		b.badge:SetVertexColor(1, 1, 1, 1)
		if q.tracked then b:SetFrameLevel(icons:GetFrameLevel() + 2) else b:SetFrameLevel(icons:GetFrameLevel() + 1) end
	end
	for i = #quests + 1, #pool do pool[i]:Hide(); pool[i].quest = nil end
	DrawBlobs(perMap)
end

--[[ Called by the region map on every layout (FreeMinimap_Region.lua): the map it centres on,
	the player's place on it, the screen pixels per yard and the window's size. ]]
function addonTab.QuestsUpdate(mapID, x, y, ppy, cw, ch)
	if not ppy or not Enabled() or not (C_QuestLog and C_QuestLog.GetQuestsOnMap) then
		if #quests > 0 or next(blobQuests) then HideAll() end
		return
	end
	local pw, pn, inst = World(mapID, x, y)
	if not pw then
		if #quests > 0 then HideAll() end
		return
	end
	local halfW, halfH = cw / 2, ch / 2
	local now = GetTime()
	local key = string.format("%d:%s:%.4f:%d:%d", mapID, tostring(inst), ppy, math.floor(cw), math.floor(ch))
	if dirty or key ~= lastKey or now - lastRead >= REFRESH or now < lastRead then
		dirty, lastKey, lastRead = false, key, now
		Read(ZonesNear(mapID, inst, pw, pn, halfW / ppy, halfH / ppy), inst)
	end

	--{ what the real minimap already shows: its quest icons within its view radius }--
	local pc = addonTab.pc
	local radius
	if pc.regionOverlay and (Minimap:GetAlpha() or 1) > 0 and C_Minimap and C_Minimap.GetViewRadius then
		local ok, r = pcall(C_Minimap.GetViewRadius)
		if ok and IsNum(r) and r > 0 then radius = r end
	end

	for i, q in ipairs(quests) do
		local b = pool[i]
		local dx, dy = pw - q.wx, q.wy - pn
		local sx, sy = dx * ppy, dy * ppy
		local inside = radius and (dx * dx + dy * dy <= radius * radius)
		if not inside and math.abs(sx) <= halfW + ICON / 2 and math.abs(sy) <= halfH + ICON / 2 then
			b:ClearAllPoints()
			b:SetPoint("CENTER", icons, "CENTER", sx, sy)
			if not b:IsShown() then b:Show() end
		elseif b:IsShown() then
			b:Hide()
		end
	end

	--{ each zone's area frame covers that zone's whole map, placed like the terrain }--
	for mapID, ids in pairs(blobQuests) do
		local r = Rect(mapID)
		if r then
			local x0, y0 = (pw - r[1]) * ppy, (r[2] - pn) * ppy
			local x1, y1 = (pw - r[3]) * ppy, (r[4] - pn) * ppy
			local left, top = math.min(x0, x1), math.max(y0, y1)
			local w, h = math.abs(x1 - x0), math.abs(y1 - y0)
			local f = blobs[mapID]
			if not f and w > 1 and h > 1 then
				f = NewBlob(mapID)
				if f then blobs[mapID] = f end
			end
			if f then
				--[[ the shapes are drawn for the frame's place on screen at the moment of drawing and do not
					follow it afterwards (iteration 6: shapes left behind after a zoom). So, as Blizzard's map
					and OpenMap do: on every change of the rectangle, place the frame, make the game work its
					rectangle out now (GetRect), then wipe and draw again (at most every REDRAW seconds). ]]
				local c = f.__rect
				if not c or math.abs(c[1] - left) > 0.5 or math.abs(c[2] - top) > 0.5 or math.abs(c[3] - w) > 0.5 or math.abs(c[4] - h) > 0.5 then
					f.__rect = { left, top, w, h }
					f.__dirty = true
				end
				if not f:IsShown() then f.__dirty = true end
				if f.__dirty and now - (f.__drawn or -1) >= REDRAW then
					f.__dirty, f.__drawn = false, now
					local focusID = blobTracked[mapID]
					if f.__focus and not focusID then f.__focus:Hide() end
					for _, g in ipairs({ f, (focusID and f.__focus) or false, f.__probe or false }) do
						if g then
							g:SetScale(1)
							g:ClearAllPoints()
							g:SetPoint("TOPLEFT", areas, "CENTER", left, top)
							g:SetSize(w, h)
							if not g:IsShown() then g:Show() end
							pcall(g.GetRect, g)
							if g.DrawNone then pcall(g.DrawNone, g) end
							if g == f then
								for _, id in ipairs(ids) do if id ~= focusID then pcall(g.DrawBlob, g, id, true) end end
								if type(g.UpdateMouseOverTooltip) == "function" then pcall(g.UpdateMouseOverTooltip, g, -1, -1) end
							elseif g == f.__probe then
								for _, id in ipairs(ids) do pcall(g.DrawBlob, g, id, true) end
							else
								pcall(g.DrawBlob, g, focusID, true)
								g.__tries = 0
							end
						end
					end
					if addonTab.QuestsRelight then pcall(addonTab.QuestsRelight) end
				end
			end
		else
			Retire(mapID)
		end
	end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_POI_UPDATE", "QUEST_WATCH_LIST_CHANGED", "SUPER_TRACKING_CHANGED", "ZONE_CHANGED_NEW_AREA" }) do
	pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function() dirty = true end)

R:HookScript("OnHide", function() if #quests > 0 or next(blobQuests) then HideAll() end end)

--[[ ===================== tooltip over the areas =====================
	On the real minimap, hovering inside a quest's area shows its objectives; the areas drawn on the
	terrain tiles showed nothing (Thibault, 21/11). The area frame can tell which quest is under a point
	of its map, as the world map's quest areas do: UpdateMouseOverTooltip(x, y) with x, y the cursor on
	the frame (0..1 from its top left) returns the quest (log index on older clients, quest ID on newer
	ones) and how many of its objectives are there, read with GetTooltipIndex(i).
	Only while the cursor is over the region map itself (not over an icon, a button or the real minimap,
	which shows its own tooltip). ]]
local HOVER_EVERY = 0.05
local hover = CreateFrame("Frame", nil, R)
local hoverWait, hoverShown = 0, nil

local function QuestFromHit(a, ids)
	if not a then return end
	for _, id in ipairs(ids) do if id == a then return a end end                  --{ a quest ID }--
	if C_QuestLog.GetQuestIDForLogIndex then                                        --{ a log index }--
		local ok, id = pcall(C_QuestLog.GetQuestIDForLogIndex, a)
		if ok and id and id ~= 0 then return id end
	end
	if C_QuestLog.GetInfo then
		local ok, info = pcall(C_QuestLog.GetInfo, a)
		if ok and type(info) == "table" and info.questID then return info.questID end
	end
end

local function HideHover()
	if hoverShown and GameTooltip:IsOwned(R) then GameTooltip:Hide() end
	hoverShown = nil
end

local function OverMapOnly()
	if not R:IsMouseOver() then return false end
	if Minimap:IsShown() and (Minimap:GetAlpha() or 1) > 0 and Minimap:IsMouseOver() then return false end
	local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
	local f = foci and foci[1]
	return f == nil or f == R
end

local function Hover()
	if not next(blobQuests) or not OverMapOnly() then HideHover() return end
	local cx, cy = GetCursorPosition()
	local found, objectives
	for mapID, f0 in pairs(blobs) do
		local f = f0.__probe or f0
		local ids = blobQuests[mapID]
		if ids and f:IsShown() and type(f.UpdateMouseOverTooltip) == "function" then
			local s = f:GetEffectiveScale()
			local l, b, w, h = f:GetRect()
			local x, y = cx / s, cy / s
			if l and w > 0 and h > 0 and x >= l and x <= l + w and y >= b and y <= b + h then
				local ok, a, n = pcall(f.UpdateMouseOverTooltip, f, (x - l) / w, (b + h - y) / h)
				local id = ok and QuestFromHit(a, ids)
				if id then
					found = id
					if type(n) == "number" and n > 0 and type(f.GetTooltipIndex) == "function" then
						objectives = {}
						for i = 1, n do
							local okI, k = pcall(f.GetTooltipIndex, f, i)
							if okI and type(k) == "number" then objectives[k] = true end
						end
						if not next(objectives) then objectives = nil end
					end
					break
				end
			end
		end
	end
	if not found then HideHover() return end
	local key = found .. ":" .. (objectives and table.concat((function() local t = {} for k in pairs(objectives) do t[#t + 1] = k end table.sort(t) return t end)(), ",") or "*")
	if hoverShown == key and GameTooltip:IsOwned(R) then return end
	hoverShown = key
	GameTooltip:SetOwner(R, "ANCHOR_CURSOR_RIGHT", 5, 2)
	local complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(found) or false
	QuestLines(found, complete, objectives)
	GameTooltip:Show()
end

local function Relight()
	for mapID, f in pairs(blobs) do
		local g = f.__focus
		if g and g:IsShown() and blobTracked[mapID] and type(g.UpdateMouseOverTooltip) == "function" then
			if g.__lx and not Ask(g, g.__lx, g.__ly) then g.__lx = nil end
			if not g.__lx and (g.__tries or 0) < 20 then
				g.__tries = (g.__tries or 0) + 1
				g.__lx, g.__ly = FindPoint(g, mapID)
			end
		end
	end
end
addonTab.QuestsRelight = Relight

--{ TEMPORARY (21/11): /fmm qdiag, what the area frames hold and what the tracked-area search found }--
function addonTab.QuestsDiag()
	local P = function(...) print("|cffff8a3dFMM qdiag|r", ...) end
	local l = CurrentLook()
	P("style", tostring(addonTab.pc and addonTab.pc.edgeStyle), "texture", tostring(l.texture), "scalar", tostring(l.scalar))
	local any
	for mapID, f in pairs(blobs) do
		any = true
		local g, pr = f.__focus, f.__probe
		local ids = blobQuests[mapID] or {}
		P("map", mapID, "quests", table.concat(ids, ","), "tracked", tostring(blobTracked[mapID]),
			"tracked pos", trackedPos[mapID] and string.format("%.3f,%.3f", trackedPos[mapID][1], trackedPos[mapID][2]) or "none")
		P(" faint shown", tostring(f:IsShown()), "focus shown", tostring(g and g:IsShown()), "probe shown", tostring(pr and pr:IsShown()))
		if g then
			P(" focus point", g.__lx and string.format("%.3f,%.3f", g.__lx, g.__ly) or "NOT FOUND", "tries", tostring(g.__tries))
			if trackedPos[mapID] then
				local ok, a, n = pcall(g.UpdateMouseOverTooltip, g, trackedPos[mapID][1], trackedPos[mapID][2])
				P(" focus asked at quest pos ->", tostring(ok), tostring(a), tostring(n))
			end
			local hits = 0
			for i = 1, 19 do for j = 1, 19 do
				local ok, a = pcall(g.UpdateMouseOverTooltip, g, i / 20, j / 20)
				if ok and a and a ~= 0 then hits = hits + 1 end
			end end
			P(" focus grid hits (of 361)", hits)
		end
		if pr then
			local hits = 0
			for i = 1, 19 do for j = 1, 19 do
				local ok, a = pcall(pr.UpdateMouseOverTooltip, pr, i / 20, j / 20)
				if ok and a and a ~= 0 then hits = hits + 1 end
			end end
			P(" probe grid hits (of 361)", hits)
		end
		if g then pcall(Relight) end
	end
	if not any then P("no area frame") end
end

hover:SetScript("OnUpdate", function(_, elapsed)
	hoverWait = hoverWait - elapsed
	if hoverWait > 0 then return end
	hoverWait = HOVER_EVERY
	local ok = pcall(Hover)
	if not ok then HideHover() end
	pcall(Relight)
end)
R:HookScript("OnLeave", function() HideHover() end)
