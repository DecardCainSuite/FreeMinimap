--[[
	FreeMinimap — other addons' minimap icons on the region map

	Questie, RestedXP, TomTom, gatherers… put their minimap icons on the Minimap through the
	HereBeDragons-Pins-2.0 library. The library keeps every icon in one table
	(pins.minimapPins[icon] = { instanceID, x, y, floatOnEdge, … }: a world position in yards) and
	only draws those inside the real minimap's view radius (or on its edge). Its world map icons
	(pins.worldmapPins) are read too: RestedXP only puts the current step on the minimap.

	This module reads that table and draws a copy of each icon at its true place on the region map,
	where the real minimap does not reach. The copy repeats the icon's textures and texts (RestedXP's
	step number, Questie's glow…), its tooltip (the icon's own OnEnter) and its click.
	Icons that "float on the edge" float on the edge of the region map instead of the real minimap's.

	The table is the library's own data, not a published API: everything is read defensively.
	The original icons are never moved or re-parented; only their floatOnEdge flag is switched off
	while the region map shows them (put back when the region map or this option is turned off).
]]
local addonName, addonTab = ...
local R = FreeMinimapRegion
if not R then return end

local REFRESH = 0.5     --{ seconds between two copies of the icons' looks (addons change them without telling)
local MARGIN = 300      --{ yards around the window where icons are still kept as candidates
local MAX_PINS = 400    --{ most copies drawn at once
local RADIUS_K = 0.9    --{ HereBeDragons draws an icon while it is within 0.9 x the minimap's view radius
local MAX_DEPTH = 2     --{ nested child frames copied

local layer = CreateFrame("Frame", "FreeMinimapPins", R)
layer:SetAllPoints(R)
layer:SetFrameStrata("HIGH")
layer:SetFrameLevel(12)  --{ over the real minimap (10), under the buttons (30) }--
layer:EnableMouse(false)

local pool, used = {}, 0
local candidates = {}        --{ { src, data } built every REFRESH }--
local suppressed = {}        --{ [icon] = data whose floatOnEdge we switched off }--
local lastRefresh = -1
local lastKey

local function Lib()
	if not LibStub then return end
	local ok, lib = pcall(LibStub.GetLibrary, LibStub, "HereBeDragons-Pins-2.0", true)
	if ok and type(lib) == "table" and type(lib.minimapPins) == "table" then return lib end
end
local function Core()
	if not LibStub then return end
	local ok, lib = pcall(LibStub.GetLibrary, LibStub, "HereBeDragons-2.0", true)
	if ok and type(lib) == "table" then return lib end
end

local function IsNum(v) return type(v) == "number" and v == v and not (issecretvalue and issecretvalue(v)) end

--{ the player in the library's world space, from the region map's own map position }--
local function PlayerWorld(mapID, x, y)
	local hbd = Core()
	if not hbd then return end
	if hbd.GetWorldCoordinatesFromZone and mapID and IsNum(x) and IsNum(y) then
		local ok, wx, wy, inst = pcall(hbd.GetWorldCoordinatesFromZone, hbd, x, y, mapID)
		if ok and IsNum(wx) and IsNum(wy) and inst then return wx, wy, inst end
	end
	if hbd.GetPlayerWorldPosition then
		local ok, wx, wy, inst = pcall(hbd.GetPlayerWorldPosition, hbd)
		if ok and IsNum(wx) and IsNum(wy) and inst then return wx, wy, inst end
	end
end

local function Enabled()
	local pc = addonTab.pc
	return pc and pc.regionEnabled and pc.regionPins ~= false and R:IsShown()
end

--[[ ===================== redraw request to the library =====================
	HereBeDragons works out the minimap's size only when the player moves or the zoom changes: after
	FreeMinimap resizes the Minimap (region map scale, zone change, /reload…) the icons on the real
	minimap stayed misplaced until the next zoom. Adding an icon makes the library redraw everything on
	its next frame, so we keep one invisible icon of our own and add it again whenever needed. ]]
local nudgeIcon, nudgeQueued
local function Nudge()
	nudgeQueued = false
	local lib, hbd = Lib(), Core()
	if not (lib and hbd and lib.AddMinimapIconWorld and hbd.GetPlayerWorldPosition) then return end
	local ok, x, y, inst = pcall(hbd.GetPlayerWorldPosition, hbd)
	if not ok or not IsNum(x) or not IsNum(y) or not inst then return end
	if not nudgeIcon then
		nudgeIcon = CreateFrame("Frame", nil, UIParent)
		nudgeIcon:SetSize(1, 1)
		nudgeIcon:SetAlpha(0)
		nudgeIcon:EnableMouse(false)
	end
	pcall(lib.AddMinimapIconWorld, lib, addonName, nudgeIcon, inst, x, y, false)
end
local function QueueNudge()
	if nudgeQueued then return end
	nudgeQueued = true
	if C_Timer and C_Timer.After then C_Timer.After(0, Nudge) else Nudge() end
end
addonTab.PinsNudge = QueueNudge
Minimap:HookScript("OnSizeChanged", QueueNudge)

--{ ===================== floatOnEdge of the originals ===================== }--
local function Suppress(src, data)
	if data.floatOnEdge and not suppressed[src] then
		suppressed[src] = data
		data.floatOnEdge = false
		--{ the library only redraws when the player moves: hide now the copy it left on the minimap's edge }--
		if data.onEdge then
			data.onEdge = nil
			if type(src.Hide) == "function" then pcall(src.Hide, src) end
		end
		QueueNudge()
	end
end

local function RestoreAll()
	local lib = Lib()
	for src, data in pairs(suppressed) do
		--{ only if the library still holds the same record for this icon (records are recycled) }--
		if lib and lib.minimapPins[src] == data then data.floatOnEdge = true end
		suppressed[src] = nil
		QueueNudge()
	end
end

--{ ===================== copying an icon's looks ===================== }--
local function Call(obj, method, ...)
	local f = obj and obj[method]
	if type(f) ~= "function" then return end
	return pcall(f, obj, ...)
end
local function Get(obj, method, ...)
	local f = obj and obj[method]
	if type(f) ~= "function" then return end
	local r = { pcall(f, obj, ...) }
	if not r[1] then return end
	return unpack(r, 2)
end

local CopyFrame

local function CopyTexture(s, d)
	local atlas = Get(s, "GetAtlas")
	if type(atlas) == "string" and atlas ~= "" then
		Call(d, "SetAtlas", atlas)
	else
		Call(d, "SetTexture", Get(s, "GetTexture"))
	end
	local c = { Get(s, "GetTexCoord") }
	if #c == 8 then Call(d, "SetTexCoord", unpack(c)) elseif #c == 4 then Call(d, "SetTexCoord", unpack(c)) end
	local r, g, b, a = Get(s, "GetVertexColor")
	if r then Call(d, "SetVertexColor", r, g, b, a or 1) end
	Call(d, "SetBlendMode", Get(s, "GetBlendMode") or "BLEND")
	Call(d, "SetDesaturated", Get(s, "IsDesaturated") and true or false)
	local rot = Get(s, "GetRotation")
	if IsNum(rot) then Call(d, "SetRotation", rot) end
end

local function CopyFontString(s, d)
	local font, size, flags = Get(s, "GetFont")
	if font and IsNum(size) then
		Call(d, "SetFont", font, size, flags or "")
	else
		Call(d, "SetFontObject", Get(s, "GetFontObject") or GameFontNormalSmall)
	end
	Call(d, "SetText", Get(s, "GetText") or "")
	local r, g, b, a = Get(s, "GetTextColor")
	if r then Call(d, "SetTextColor", r, g, b, a or 1) end
	local sx, sy = Get(s, "GetShadowOffset")
	if IsNum(sx) then Call(d, "SetShadowOffset", sx, sy) end
	local sr, sg, sb, sa = Get(s, "GetShadowColor")
	if sr then Call(d, "SetShadowColor", sr, sg, sb, sa or 1) end
	local jh = Get(s, "GetJustifyH"); if jh then Call(d, "SetJustifyH", jh) end
	local jv = Get(s, "GetJustifyV"); if jv then Call(d, "SetJustifyV", jv) end
end

--{ the same anchors, with the original's parts replaced by the copy's }--
local function CopyPoints(s, d, map, root)
	Call(d, "ClearAllPoints")
	local n = Get(s, "GetNumPoints") or 0
	if n == 0 then Call(d, "SetPoint", "CENTER", root, "CENTER", 0, 0) return end
	for i = 1, n do
		local point, rel, relPoint, x, y = Get(s, "GetPoint", i)
		if point then
			local target = (rel and map[rel]) or root
			if rel and not map[rel] then relPoint = point; x, y = 0, 0 end
			Call(d, "SetPoint", point, target, relPoint or point, IsNum(x) and x or 0, IsNum(y) and y or 0)
		end
	end
end

local function Acquire(list, i, make)
	local o = list[i]
	if not o then o = make(); list[i] = o end
	return o
end

--{ copies src's regions (and child frames, a few levels deep) into d; returns true if anything is visible }--
CopyFrame = function(src, d, depth, root, map)
	map[src] = d
	d.__tex = d.__tex or {}; d.__fs = d.__fs or {}; d.__kids = d.__kids or {}
	local nt, nf, nk = 0, 0, 0
	local pairsTodo = {}
	local regions = { Get(src, "GetRegions") }
	for _, s in ipairs(regions) do
		local kind = Get(s, "GetObjectType")
		if kind == "Texture" then
			nt = nt + 1
			local t = Acquire(d.__tex, nt, function() return d:CreateTexture(nil, "OVERLAY") end)
			CopyTexture(s, t)
			map[s] = t
			pairsTodo[#pairsTodo + 1] = { s, t }
		elseif kind == "FontString" then
			nf = nf + 1
			local f = Acquire(d.__fs, nf, function() return d:CreateFontString(nil, "OVERLAY") end)
			CopyFontString(s, f)
			map[s] = f
			pairsTodo[#pairsTodo + 1] = { s, f }
		end
	end
	if depth < MAX_DEPTH then
		for _, c in ipairs({ Get(src, "GetChildren") }) do
			nk = nk + 1
			local k = Acquire(d.__kids, nk, function() local f = CreateFrame("Frame", nil, d); f:EnableMouse(false); return f end)
			k:SetFrameLevel(d:GetFrameLevel() + 1)
			k:SetScale(Get(c, "GetScale") or 1)
			k:SetAlpha(Get(c, "GetAlpha") or 1)
			k:SetShown(Get(c, "IsShown") and true or false)
			CopyFrame(c, k, depth + 1, d, map)
			pairsTodo[#pairsTodo + 1] = { c, k, true }
		end
	end
	--{ sizes, draw layers and anchors once every part exists (an anchor may point to a sibling) }--
	for _, p in ipairs(pairsTodo) do
		local s, o, isFrame = p[1], p[2], p[3]
		local w, h = Get(s, "GetSize")
		if IsNum(w) and IsNum(h) then Call(o, "SetSize", w, h) end
		if not isFrame then
			local layerName, sub = Get(s, "GetDrawLayer")
			if layerName then Call(o, "SetDrawLayer", layerName, sub or 0) end
			Call(o, "SetAlpha", Get(s, "GetAlpha") or 1)
			Call(o, "SetShown", Get(s, "IsShown") and true or false)
		end
		CopyPoints(s, o, map, d)
	end
	for i = nt + 1, #d.__tex do d.__tex[i]:Hide() end
	for i = nf + 1, #d.__fs do d.__fs[i]:Hide() end
	for i = nk + 1, #d.__kids do d.__kids[i]:Hide() end
	--{ visible = a shown part with some opacity }--
	for _, p in ipairs(pairsTodo) do
		local s = p[1]
		if Get(s, "IsShown") and (Get(s, "GetAlpha") or 1) > 0 then
			if p[3] or Get(s, "GetObjectType") == "FontString" then
				if p[3] or (Get(s, "GetText") or "") ~= "" then return true end
			else
				return true
			end
		end
	end
	return false
end

--{ ===================== the copies ===================== }--
local function OnEnter(self)
	local src = self.src
	if addonTab.ButtonHoverEnter then addonTab.ButtonHoverEnter() end
	local fn = src and Get(src, "GetScript", "OnEnter")
	if type(fn) == "function" then
		pcall(fn, src)
		--{ the icon's own script anchors the tooltip on the (hidden) original: move it onto the copy }--
		if GameTooltip and GameTooltip:IsShown() and Get(GameTooltip, "GetOwner") == src then
			GameTooltip:ClearAllPoints()
			GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPRIGHT", 0, 0)
		end
	end
end
local function OnLeave(self)
	local src = self.src
	local fn = src and Get(src, "GetScript", "OnLeave")
	if type(fn) == "function" then pcall(fn, src) end
end
local function OnClick(self, button)
	local src = self.src
	if not src then return end
	local fn = Get(src, "GetScript", "OnClick") or Get(src, "GetScript", "OnMouseUp")
	if type(fn) == "function" then pcall(fn, src, button or "LeftButton") end
end
local function OnWheel(_, delta)
	local fn = R:GetScript("OnMouseWheel")
	if fn then fn(R, delta) end
end

local function NewCopy()
	local b = CreateFrame("Button", nil, layer)
	b:SetFrameLevel(layer:GetFrameLevel() + 1)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnEnter", OnEnter)
	b:SetScript("OnLeave", OnLeave)
	b:SetScript("OnClick", OnClick)
	b:EnableMouseWheel(true)
	b:SetScript("OnMouseWheel", OnWheel)
	b:Hide()
	return b
end

local function HideFrom(i)
	for k = i, #pool do
		local b = pool[k]
		if b:IsShown() then b:Hide() end
		b.src = nil
	end
end

local function HideAll()
	HideFrom(1)
	used = 0
	RestoreAll()
	wipe(candidates)
	lastKey = nil
end
addonTab.PinsHide = HideAll

--{ the minimap's shape as HereBeDragons sees it (round unless an addon declares a square one) }--
local function SquareShape()
	if GetMinimapShape then
		local ok, s = pcall(GetMinimapShape)
		return ok and s == "SQUARE"
	end
	return false
end

--[[ Rebuild the candidates: icons on our continent near the window, their looks copied.
	px, py, inst: the player (library space); halfW/halfH: the window's half size in yards. ]]
local taken = {}
local SAME = 6   --{ yards: a world map icon this close to a minimap icon is the same thing (Questie puts both) }--
local function Key(inst, x, y) return tostring(inst) .. ":" .. math.floor(x / SAME) .. ":" .. math.floor(y / SAME) end
--{ a minimap icon in the same cell or a neighbouring one (no miss at a cell's border) }--
local function Taken(inst, x, y)
	local cx, cy = math.floor(x / SAME), math.floor(y / SAME)
	for i = -1, 1 do
		for j = -1, 1 do
			if taken[tostring(inst) .. ":" .. (cx + i) .. ":" .. (cy + j)] then return true end
		end
	end
	return false
end

local function Rebuild(lib, px, py, inst, halfW, halfH)
	wipe(candidates)
	local n = 0
	for src, data in pairs(lib.minimapPins) do
		if type(data) == "table" and data.instanceID == inst and IsNum(data.x) and IsNum(data.y)
		   and type(src) == "table" and not src.hidden and src ~= nudgeIcon then  --{ Questie's FakeHide: the icon is filtered out }--
			local dx, dy = px - data.x, data.y - py
			local float = data.floatOnEdge or suppressed[src] ~= nil
			--{ near the window, or anywhere on the continent for an icon that floats on the edge }--
			if float or (math.abs(dx) <= halfW + MARGIN and math.abs(dy) <= halfH + MARGIN) then
				n = n + 1
				if n > MAX_PINS then break end
				candidates[n] = { src = src, data = data, float = float, reg = lib.minimapPins }
				taken[Key(inst, data.x, data.y)] = true
			end
		end
	end
	--[[ world map icons: some addons put only part of theirs on the minimap (RestedXP: the current
		step; the next ones only on the world map). Those not already on the minimap (same place) are
		copied too, near the window only, never floating. ]]
	if type(lib.worldmapPins) == "table" and n <= MAX_PINS then
		for src, data in pairs(lib.worldmapPins) do
			if type(data) == "table" and data.instanceID == inst and IsNum(data.x) and IsNum(data.y)
			   and type(src) == "table" and not src.hidden and not lib.minimapPins[src] then
				local dx, dy = px - data.x, data.y - py
				if math.abs(dx) <= halfW + MARGIN and math.abs(dy) <= halfH + MARGIN and not Taken(inst, data.x, data.y) then
					n = n + 1
					if n > MAX_PINS then break end
					candidates[n] = { src = src, data = data, float = false, reg = lib.worldmapPins, world = true }
				end
			end
		end
	end
	if n > MAX_PINS then candidates[n] = nil end
	wipe(taken)
	--{ copy the looks }--
	for i, c in ipairs(candidates) do
		local b = pool[i] or NewCopy()
		pool[i] = b
		b.src = c.src
		local scale = 1
		--{ a minimap icon keeps its size on screen; a world map icon (whose map may be zoomed or closed) its size in UI units }--
		local se = c.world and UIParent:GetEffectiveScale() * (Get(c.src, "GetScale") or 1) or Get(c.src, "GetEffectiveScale")
		local le = layer:GetEffectiveScale()
		if IsNum(se) and IsNum(le) and le > 0 and se > 0 then scale = math.min(math.max(se / le, 0.05), 20) end
		b:SetScale(scale)
		local w, h = Get(c.src, "GetSize")
		b:SetSize(IsNum(w) and w > 0 and w or 16, IsNum(h) and h > 0 and h or 16)
		b:SetAlpha(Get(c.src, "GetAlpha") or 1)
		local okc, vis = pcall(CopyFrame, c.src, b, 0, b, {})
		c.visible = okc and vis
		b:EnableMouse(c.visible and true or false)
		c.button = b
		c.scale = scale
		c.halfSize = math.max(IsNum(w) and w or 16, IsNum(h) and h or 16) / 2
	end
	HideFrom(#candidates + 1)
	used = #candidates
end

--[[ /fmm pins: where the player and a few icons are according to each source, to compare our copies with
	what HereBeDragons draws on the real minimap. Printed and kept in FreeMinimapDB.pinsDebug (read after /reload). ]]
local last = {}
function addonTab.PinsDebug()
	local out = {}
	local function P(fmt, ...) local line = string.format(fmt, ...); out[#out + 1] = line; print("|cffff8a3dFMM|r " .. line) end
	local function C(f) local x, y = Get(f, "GetCenter"); local e = Get(f, "GetEffectiveScale") or 1; if x then return x * e, y * e end end
	P("map %s x %.4f y %.4f ppy %.4f window %dx%d", tostring(last.mapID), last.x or -1, last.y or -1, last.ppy or -1, last.cw or 0, last.ch or 0)
	local rx, ry = C(R); local mx, my = C(Minimap); local lx, ly = C(layer)
	P("centres (screen px): region %.1f,%.1f  minimap %.1f,%.1f  layer %.1f,%.1f", rx or -1, ry or -1, mx or -1, my or -1, lx or -1, ly or -1)
	local hbd = Core()
	if last.mapID then
		local ok, inst, vec = pcall(C_Map.GetWorldPosFromMapPos, last.mapID, CreateVector2D(last.x, last.y))
		if ok and vec then local a, b = vec:GetXY(); P("C_Map world (north, west) %.1f, %.1f inst %s", a, b, tostring(inst)) end
		if hbd then local a, b, i = hbd:GetWorldCoordinatesFromZone(last.x, last.y, last.mapID); P("HBD zone->world (x=west, y=north) %s, %s inst %s", tostring(a), tostring(b), tostring(i)) end
	end
	if hbd and hbd.GetPlayerWorldPosition then local a, b, i = hbd:GetPlayerWorldPosition(); P("HBD player (UnitPosition) %s, %s inst %s", tostring(a), tostring(b), tostring(i)) end
	local ok, uy, ux, _, ui = pcall(UnitPosition, "player"); if ok then P("UnitPosition %s, %s inst %s", tostring(uy), tostring(ux), tostring(ui)) end
	local lib = Lib()
	local n = 0
	if lib and last.px then
		for src, data in pairs(lib.minimapPins) do
			if n >= 5 then break end
			if src ~= nudgeIcon and Get(src, "IsVisible") and IsNum(data.x) then
				local sx, sy = C(src)
				local le = layer:GetEffectiveScale()
				if sx and mx then
					n = n + 1
					P("pin %d HBD on minimap %.1f,%.1f  ours %.1f,%.1f (dx %.1f yd, dy %.1f yd)", n,
						(sx - mx) / le, (sy - my) / le, (last.px - data.x) * last.ppy, (data.y - last.py) * last.ppy,
						last.px - data.x, data.y - last.py)
				end
			end
		end
	end
	if n == 0 then P("no icon drawn by HereBeDragons on the real minimap right now (walk next to one)") end
	if FreeMinimapDB then FreeMinimapDB.pinsDebug = out end
end

--[[ Called by the region map on every layout (FreeMinimap_Region.lua) with the map it centres on,
	the player's place on it, the screen pixels per yard and the window's size. ]]
function addonTab.PinsUpdate(mapID, x, y, ppy, cw, ch)
	if not ppy or not Enabled() then
		if used > 0 or next(suppressed) then HideAll() end
		return
	end
	local lib = Lib()
	if not lib then return end
	local px, py, inst = PlayerWorld(mapID, x, y)
	if not px then
		if used > 0 then HideAll() end
		return
	end
	last.mapID, last.x, last.y, last.ppy, last.cw, last.ch, last.px, last.py = mapID, x, y, ppy, cw, ch, px, py
	local pc = addonTab.pc
	local halfW, halfH = cw / 2, ch / 2
	local now = GetTime()
	local key = string.format("%s:%.4f:%d:%d", tostring(inst), ppy, math.floor(cw), math.floor(ch))
	if key ~= lastKey or now - lastRefresh >= REFRESH or now < lastRefresh then
		lastKey, lastRefresh = key, now
		Rebuild(lib, px, py, inst, halfW / ppy, halfH / ppy)
	end

	--{ what the real minimap (and HereBeDragons on it) already shows }--
	local overlay = pc.regionOverlay and (Minimap:GetAlpha() or 1) > 0
	local radius
	if overlay and C_Minimap and C_Minimap.GetViewRadius then
		local ok, r = pcall(C_Minimap.GetViewRadius)
		if ok and IsNum(r) and r > 0 then radius = r * RADIUS_K end
	end
	local square = SquareShape()

	for _, c in ipairs(candidates) do
		local b, data = c.button, c.data
		local placed = false
		if c.visible and c.reg[c.src] == data then
			local dx, dy = px - data.x, data.y - py   --{ yards: + = west of the icon / north of the player }--
			local inside = false
			if radius and not c.world then  --{ world map icons are never drawn by the real minimap }--
				if square then inside = math.max(math.abs(dx), math.abs(dy)) <= radius
				else inside = dx * dx + dy * dy <= radius * radius end
			end
			if inside then
				--{ the real minimap draws it: give its float flag back so it behaves as usual }--
				if suppressed[c.src] then data.floatOnEdge = true; suppressed[c.src] = nil; QueueNudge() end
			else
				local sx, sy = dx * ppy, dy * ppy
				local m = c.halfSize * c.scale
				local limX, limY = halfW - m, halfH - m
				local out = math.abs(sx) > halfW or math.abs(sy) > halfH
				if out and c.float and limX > 0 and limY > 0 then
					local f = math.min(limX / math.max(math.abs(sx), 1e-6), limY / math.max(math.abs(sy), 1e-6))
					sx, sy = sx * f, sy * f
					out = false
				end
				if not out then
					if c.float then Suppress(c.src, data) end
					b:ClearAllPoints()
					b:SetPoint("CENTER", layer, "CENTER", sx / c.scale, sy / c.scale)
					placed = true
				end
			end
		end
		if placed then
			if not b:IsShown() then b:Show() end
		elseif b:IsShown() then
			b:Hide()
		end
	end
end

--{ region map hidden (turned off, Alt+Z…): copies hidden and the originals' float flags given back }--
R:HookScript("OnHide", function() if used > 0 or next(suppressed) then HideAll() end end)
