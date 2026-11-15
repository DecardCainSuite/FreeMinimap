local addonName, addonTab = ... --[[ Free Minimap: moving the minimap without Edit Mode ]]
if addonTab.conflict then return end

--[[
pc.posMode = "editmode" (the game's Edit Mode places the minimap, as before) or "free" (Free Minimap places it).
Free: pc.posPoint (nearest corner / side of the screen) + pc.posX / pc.posY in UIParent pixels from that point.
Edit Mode puts its own position back when it applies a layout (login, layout change, leaving Edit Mode):
ours goes back on afterwards (FMM_Square is called on all those occasions, plus the hooks below).
The cluster is protected: never moved during a fight; the mover locks itself when a fight starts.
]]

if addonTab.character then
	addonTab.character.posMode = addonTab.character.posMode or "editmode"
end

local function ratio()
	local a = MinimapCluster:GetEffectiveScale() or 1
	local b = UIParent:GetEffectiveScale() or 1
	if a <= 0 or b <= 0 then return 1 end
	return a / b
end

--{ Point + offsets (UIParent pixels) for a rectangle given in UIParent pixels }--
local function pointFor(l, b, r, t)
	local W, H = UIParent:GetSize()
	local cx, cy = (l + r) / 2, (b + t) / 2
	local h = (cx < W / 3 and "LEFT") or (cx > W * 2 / 3 and "RIGHT") or ""
	local v = (cy > H * 2 / 3 and "TOP") or (cy < H / 3 and "BOTTOM") or ""
	local point = (v .. h ~= "") and (v .. h) or "CENTER"
	local x = (h == "LEFT" and l) or (h == "RIGHT" and (r - W)) or (cx - W / 2)
	local y = (v == "TOP" and (t - H)) or (v == "BOTTOM" and b) or (cy - H / 2)
	return point, math.floor(x + 0.5), math.floor(y + 0.5)
end

--{ Current rectangle of the minimap window in UIParent pixels }--
local function clusterRect()
	local l, b, w, h = MinimapCluster:GetRect()
	if not l then return end
	local k = ratio()
	return l * k, b * k, (l + w) * k, (b + h) * k
end

--{ Takes the minimap's current place as the free position (when switching to "free", or after a drag) }--
function addonTab.CapturePosition()
	local pc = addonTab.pc
	local l, b, r, t = clusterRect()
	if not (pc and l) then return false end
	pc.posPoint, pc.posX, pc.posY = pointFor(l, b, r, t)
	return true
end

local dragging = false

function addonTab.ApplyPosition()
	local pc = addonTab.pc
	if not pc or pc.posMode ~= "free" or dragging then return end
	if InCombatLockdown() then addonTab.layoutAfterCombat = true; return end
	if not pc.posPoint then
		if not addonTab.CapturePosition() then return end
	end
	local k = ratio()
	local x, y = (tonumber(pc.posX) or 0) / k, (tonumber(pc.posY) or 0) / k
	local p, rel, rp, ox, oy = MinimapCluster:GetPoint(1)
	if MinimapCluster:GetNumPoints() == 1 and p == pc.posPoint and rel == UIParent and rp == pc.posPoint
		and math.abs((ox or 0) - x) < 0.01 and math.abs((oy or 0) - y) < 0.01 then return end
	MinimapCluster:ClearAllPoints()
	MinimapCluster:SetPoint(pc.posPoint, UIParent, pc.posPoint, x, y)
end

--{ ------------------------------------------------------------ mover }--
local mover = CreateFrame("Frame", "FreeMinimapMover", UIParent)
mover:SetFrameStrata("DIALOG")
mover:SetClampedToScreen(true)
mover:EnableMouse(true)
mover:SetMovable(true)
mover:RegisterForDrag("LeftButton")
mover:Hide()
local bg = mover:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(1, 0.54, 0.24, 0.25)
local edges = {}
for i, pts in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
	local e = mover:CreateTexture(nil, "BORDER")
	e:SetColorTexture(1, 0.54, 0.24, 1)
	e:SetPoint(pts[1]); e:SetPoint(pts[2])
	if i <= 2 then e:SetHeight(2) else e:SetWidth(2) end
	edges[i] = e
end
local label = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
label:SetPoint("CENTER")
label:SetText("Free Minimap\ndrag to move")

local function stickToCluster()
	mover:ClearAllPoints()
	mover:SetAllPoints(MinimapCluster)
end

mover:SetScript("OnDragStart", function(self)
	if InCombatLockdown() then return end
	local l, b, r, t = clusterRect()
	if not l then return end
	dragging = true
	self:ClearAllPoints()
	self:SetSize(r - l, t - b)
	self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
	self:StartMoving()
	MinimapCluster:ClearAllPoints()
	MinimapCluster:SetPoint("CENTER", self, "CENTER", 0, 0)
end)

local function stopDrag()
	if not dragging then return end
	mover:StopMovingOrSizing()
	dragging = false
	local pc = addonTab.pc
	local l, b = mover:GetLeft(), mover:GetBottom()
	if pc and l then
		pc.posPoint, pc.posX, pc.posY = pointFor(l, b, l + mover:GetWidth(), b + mover:GetHeight())
		pc.posMode = "free"
	end
	if not InCombatLockdown() then
		MinimapCluster:ClearAllPoints()
		addonTab.ApplyPosition()
	end
	stickToCluster()
	if addonTab.RefreshOptions then addonTab.RefreshOptions() end
end
mover:SetScript("OnDragStop", stopDrag)

function addonTab.IsUnlocked() return mover:IsShown() end
function addonTab.SetUnlocked(on)
	if on and InCombatLockdown() then
		print("|cffff8a3dFree Minimap|r: the minimap can't be moved during a fight.")
		on = false
	end
	if on then
		local pc = addonTab.pc
		if pc and pc.posMode ~= "free" then
			addonTab.CapturePosition()
			pc.posMode = "free"
		end
		stickToCluster()
		mover:Show()
	else
		stopDrag()
		mover:Hide()
	end
	if addonTab.RefreshOptions then addonTab.RefreshOptions() end
end

function addonTab.SetPositionMode(mode)
	local pc = addonTab.pc
	if not pc then return end
	if mode == "free" and pc.posMode ~= "free" then addonTab.CapturePosition() end
	pc.posMode = (mode == "free") and "free" or "editmode"
	if pc.posMode ~= "free" then
		addonTab.SetUnlocked(false)
		--{ Edit Mode puts its own place back at its next layout (a /reload does it). Not called from here:
		--  running Edit Mode's code from an addon would taint it. }--
		print("|cffff8a3dFree Minimap|r: Edit Mode places the minimap again after a /reload.")
	end
	if addonTab.ApplyLayout then addonTab.ApplyLayout() end
	if addonTab.RefreshOptions then addonTab.RefreshOptions() end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:SetScript("OnEvent", function()
	if mover:IsShown() then
		stopDrag()
		mover:Hide()
		if addonTab.RefreshOptions then addonTab.RefreshOptions() end
	end
end)

--{ Edit Mode places its systems through ApplySystemAnchor: ours goes back right after (next frame, out of the game's code) }--
local queued = false
local function soon()
	if queued then return end
	queued = true
	C_Timer.After(0, function() queued = false; addonTab.ApplyPosition() end)
end
if MinimapCluster and type(MinimapCluster.ApplySystemAnchor) == "function" then
	pcall(hooksecurefunc, MinimapCluster, "ApplySystemAnchor", soon)
end
if EditModeManagerFrame and EditModeManagerFrame.HookScript then
	EditModeManagerFrame:HookScript("OnHide", soon)
end
