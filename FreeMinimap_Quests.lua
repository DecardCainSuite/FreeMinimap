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
	local index = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id)
	local count, line = _G.GetNumQuestLeaderBoards, _G.GetQuestLogLeaderBoard
	if index and count and line then
		for i = 1, count(index) or 0 do
			local text, _, finished = line(i, index)
			if text and (only and only[i] or (not only and not finished)) then
				GameTooltip:AddLine((_G.QUEST_DASH or "- ") .. text, 1, 1, 1, true)
			end
		end
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

--{ a zone's areas (f.__halo: a second frame under it, none for now) }--
local function NewBlob(mapID)
	if blobsWork == false then return end
	local f = MakeBlobFrame(mapID, LINE, areas:GetFrameLevel())
	if not f then blobsWork = false return end
	blobsWork = true
	return f
end

local function Retire(mapID)
	local f = blobs[mapID]
	if f then
		f:Hide()
		f:ClearAllPoints()
		if f.__halo then f.__halo:Hide(); f.__halo:ClearAllPoints() end
		blobs[mapID] = nil
	end
end

local function DrawBlobs(perMap)
	for mapID in pairs(blobs) do
		local want, had = perMap[mapID], blobQuests[mapID]
		local same = want and had and #want == #had
		if same then for i = 1, #want do if want[i] ~= had[i] then same = false break end end end
		if not same then Retire(mapID) end
	end
	for mapID in pairs(blobQuests) do
		if not perMap[mapID] then blobQuests[mapID] = nil end
	end
	for mapID, want in pairs(perMap) do blobQuests[mapID] = want end
end

local function HideAll()
	for _, b in ipairs(pool) do b:Hide(); b.quest = nil end
	--{ the area frames are only hidden: their drawing stays valid for when the map shows again }--
	for _, f in pairs(blobs) do f:Hide(); if f.__halo then f.__halo:Hide() end end
	wipe(quests)
	lastKey = nil
	dirty = true
end
addonTab.QuestsHide = HideAll

--{ ===================== reading the log ===================== }--
local function Read(maps, inst)
	wipe(quests)
	local seen, perMap = {}, {}
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
					for _, g in ipairs({ f.__halo or false, f }) do
						if g then
							g:SetScale(1)
							g:ClearAllPoints()
							g:SetPoint("TOPLEFT", areas, "CENTER", left, top)
							g:SetSize(w, h)
							if not g:IsShown() then g:Show() end
							pcall(g.GetRect, g)
							if g.DrawNone then pcall(g.DrawNone, g) end
							for _, id in ipairs(ids) do pcall(g.DrawBlob, g, id, true) end
						end
					end
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
	for mapID, f in pairs(blobs) do
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

hover:SetScript("OnUpdate", function(_, elapsed)
	hoverWait = hoverWait - elapsed
	if hoverWait > 0 then return end
	hoverWait = HOVER_EVERY
	local ok = pcall(Hover)
	if not ok then HideHover() end
end)
R:HookScript("OnLeave", function() HideHover() end)
