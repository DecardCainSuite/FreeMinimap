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
areas:SetFrameLevel(3)   --{ over the terrain, under the real minimap }--
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
local function Enter(self)
	local q = self.quest
	if not q then return end
	if addonTab.ButtonHoverEnter then addonTab.ButtonHoverEnter() end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(q.id)
	GameTooltip:SetText(title or "?", 1, 0.82, 0)
	if q.complete then
		GameTooltip:AddLine(_G.QUEST_WATCH_QUEST_READY or "Ready for turn-in", 0.5, 0.95, 0.4)
	else
		local index = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(q.id)
		local count, line = _G.GetNumQuestLeaderBoards, _G.GetQuestLogLeaderBoard
		if index and count and line then
			for i = 1, count(index) or 0 do
				local text, _, finished = line(i, index)
				if text and not finished then GameTooltip:AddLine((_G.QUEST_DASH or "- ") .. text, 1, 1, 1, true) end
			end
		end
	end
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
local function Blob(mapID)
	if blobsWork == false then return end
	local f = blobs[mapID]
	if f then return f end
	local ok, frame = pcall(CreateFrame, "QuestPOIFrame", nil, areas)
	if not ok or not frame or type(frame.DrawBlob) ~= "function" then
		blobsWork = false
		return
	end
	blobsWork = true
	f = frame
	f:SetFrameLevel(areas:GetFrameLevel())
	f:EnableMouse(false)
	pcall(f.SetFillTexture, f, "Interface\\WorldMap\\UI-QuestBlob-Inside")
	pcall(f.SetBorderTexture, f, "Interface\\WorldMap\\UI-QuestBlob-Outside")
	pcall(f.SetFillAlpha, f, 128)
	pcall(f.SetBorderAlpha, f, 192)
	pcall(f.SetBorderScalar, f, 1.0)
	if f.SetMapID then pcall(f.SetMapID, f, mapID) end
	blobs[mapID] = f
	return f
end

local function DrawBlobs(perMap)
	for mapID, f in pairs(blobs) do
		local want = perMap[mapID]
		local had = blobQuests[mapID]
		local same = want and had and #want == #had
		if same then for i = 1, #want do if want[i] ~= had[i] then same = false break end end end
		if not same then
			if f.DrawNone then pcall(f.DrawNone, f) end
			for _, id in ipairs(want or {}) do pcall(f.DrawBlob, f, id, true) end
			blobQuests[mapID] = want
		end
		if not want then f:Hide() end
	end
	for mapID, want in pairs(perMap) do
		if not blobs[mapID] then
			local f = Blob(mapID)
			if f then
				if f.DrawNone then pcall(f.DrawNone, f) end
				for _, id in ipairs(want) do pcall(f.DrawBlob, f, id, true) end
				blobQuests[mapID] = want
			end
		end
	end
end

local function HideAll()
	for _, b in ipairs(pool) do b:Hide(); b.quest = nil end
	for mapID, f in pairs(blobs) do
		f:Hide()
		if f.DrawNone then pcall(f.DrawNone, f) end
		blobQuests[mapID] = nil
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
					if not complete then
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
	for mapID, f in pairs(blobs) do
		local r = blobQuests[mapID] and Rect(mapID)
		if r then
			local x0, y0 = (pw - r[1]) * ppy, (r[2] - pn) * ppy
			local x1, y1 = (pw - r[3]) * ppy, (r[4] - pn) * ppy
			local left, right = math.min(x0, x1), math.max(x0, x1)
			local bottom, top = math.min(y0, y1), math.max(y0, y1)
			local w, h = right - left, top - bottom
			if w > 1 and h > 1 then
				f:ClearAllPoints()
				f:SetPoint("TOPLEFT", areas, "CENTER", left, top)
				f:SetSize(w, h)
				if not f:IsShown() then f:Show() end
			else
				f:Hide()
			end
		elseif f:IsShown() then
			f:Hide()
		end
	end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_POI_UPDATE", "QUEST_WATCH_LIST_CHANGED", "SUPER_TRACKING_CHANGED", "ZONE_CHANGED_NEW_AREA" }) do
	pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function() dirty = true end)

R:HookScript("OnHide", function() if #quests > 0 or next(blobQuests) then HideAll() end end)
