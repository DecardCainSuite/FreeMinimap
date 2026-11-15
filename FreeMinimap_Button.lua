-- Free Minimap - minimap button (LibDataBroker + LibDBIcon).
-- Hidden when Free Hub is installed: the hub shows one button for all the Free addons.

local ADDON, ns = ...
if ns.conflict then return end
local ICON_NAME = "FreeMinimap"
local Icon

local function DB()
    FreeMinimapDB = type(FreeMinimapDB) == "table" and FreeMinimapDB or {}
    FreeMinimapDB.minimap = FreeMinimapDB.minimap or { hide = false }
    return FreeMinimapDB
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    Icon = LibStub and LibStub("LibDBIcon-1.0", true)
    if not (LDB and Icon) then return end
    local db = DB()
    local obj = LDB:NewDataObject(ICON_NAME, {
        type = "launcher",
        text = "Free Minimap",
        icon = "Interface\\AddOns\\" .. ADDON .. "\\Media\\icon",
        OnClick = function(_, button)
            if button == "RightButton" then
                if ns.SetRegion and ns.pc then ns.SetRegion(not ns.pc.regionEnabled) end
            else
                ns.ToggleOptions()
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("Free Minimap")
            tt:AddLine("|cffffffffLeft-click|r  options", 0.8, 0.8, 0.8)
            tt:AddLine("|cffffffffRight-click|r  region map on / off", 0.8, 0.8, 0.8)
        end,
    })
    if obj then Icon:Register(ICON_NAME, obj, db.minimap) end
    if FreeHub and FreeHub.ManagesMinimap and FreeHub:ManagesMinimap() then Icon:Hide(ICON_NAME) end
end)

ns.IsMinimapShown = function() return not DB().minimap.hide end
ns.SetMinimapShown = function(show)
    local db = DB()
    db.minimap.hide = not show
    if Icon then if show then Icon:Show(ICON_NAME) else Icon:Hide(ICON_NAME) end end
    if ns.OnChanged then ns.OnChanged() end
end
-- called by Free Hub: show/hide our button without changing the saved choice
ns.ApplyMinimapVisibility = function(show)
    if not Icon then return end
    if show and not DB().minimap.hide then Icon:Show(ICON_NAME) else Icon:Hide(ICON_NAME) end
end
