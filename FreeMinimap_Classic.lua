local addonName, addonTab = ...
addonTab.version = C_AddOns.GetAddOnMetadata(addonName, "Version")

-- SavedVariables Setup
addonTab.defaults = {}

addonTab.loader = CreateFrame("Frame")
	addonTab.loader:RegisterEvent("ADDON_LOADED")
	addonTab.loader:SetScript("OnEvent", function(self, event, ...)
		addonTab.loader[event](self, ...) -- call event handlers
	end)

	function addonTab.loader:ADDON_LOADED(AddOn)
		if AddOn == addonName then
			if not (_G[addonName.."DBPC"]) then -- first time the addon is used
				_G[addonName.."DBPC"] = {} -- allocate a table to store your saved variables (the table will be saved to disk on logout)
				-- Now, load the table with defaults if needed.
				_G[addonName.."DBPC"] = addonTab.defaults
			end
			-- Initialise the addon with the Saved Variables information (new or loaded from disk)
			addonTab.db = _G[addonName.."DBPC"]
			self:UnregisterEvent("ADDON_LOADED")
		end
	end

addonTab.defaults.optpanelDefaults = {
	point = "RIGHT",
	relativeTo = "UIParent",
	relativePoint = "RIGHT",
	xOffset = 0,
	yOffset = 0,
}

addonTab.panel = CreateFrame( "Frame", addonName.."OptionsPanel", UIParent );
	AddOnOptionsPanel = _G[addonName.."OptionsPanel"]
	AddOnOptionsPanel:RegisterEvent("PLAYER_LOGIN")

	local t=AddOnOptionsPanel:CreateTexture(nil,"ARTWORK")
		t:SetAllPoints(AddOnOptionsPanel)

local AddOnOptionsPanelCloseButton = CreateFrame("Button", addonName.."OptionsPanelCloseButton", AddOnOptionsPanel, "UIPanelCloseButton")
	AddOnOptionsPanelCloseButton:RegisterEvent("PLAYER_LOGIN")
	AddOnOptionsPanelCloseButton:ClearAllPoints()
	AddOnOptionsPanelCloseButton:SetPoint("TOPRIGHT", AddOnOptionsPanel, 0, 0)
	AddOnOptionsPanelCloseButton:SetSize(34, 34)
	-- AddOnOptionsPanelCloseButton:Hide()

	AddOnOptionsPanelCloseButton:HookScript("OnClick", function (self, button, down)
		SettingsPanelTab1:Click()
		SettingsPanelCategoriesButton1:Click()
	end)

local function SetPoints_AddOnOptionsPanel()
	AddOnOptionsPanel:ClearAllPoints()
	AddOnOptionsPanel:SetParent(UIParent)
	AddOnOptionsPanel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	AddOnOptionsPanel:SetFrameStrata("HIGH")
	AddOnOptionsPanel:SetClampedToScreen(true)
	AddOnOptionsPanel:SetMovable(true)
	AddOnOptionsPanel:EnableMouse(true)
	AddOnOptionsPanel:RegisterForDrag("LeftButton")
	AddOnOptionsPanel:SetScale(1.0)
	AddOnOptionsPanel:SetWidth(480)
	AddOnOptionsPanel:SetHeight(270)
	AddOnOptionsPanel:Hide()
	t:SetColorTexture(0, 0, 0, 0.7)
	AddOnOptionsPanelCloseButton:Show()
end

AddOnOptionsPanel:SetScript("OnEvent", function(self, event, arg1)
	if event == "PLAYER_LOGIN" then
		SetPoints_AddOnOptionsPanel()
	end
end)

SettingsPanel:HookScript("OnShow", function(self)
		AddOnOptionsPanel:EnableMouse(false)
		t:SetColorTexture(0, 0, 0, 0)
		AddOnOptionsPanelCloseButton:Hide()
end)

-- SettingsPanel:HookScript("OnHide", function(self)
-- end)

AddOnOptionsPanel:SetScript("OnDragStart", AddOnOptionsPanel.StartMoving)

AddOnOptionsPanel:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	self:SetUserPlaced(false)
end)

-- ######################################################################## --
-- Register in the Interface Addon Options GUI

-- Set the name for the Category for the Options Panel
addonTab.panel.name = addonName;

-- Add the panel to the Interface Options
addonTab.category = Settings.RegisterCanvasLayoutCategory(addonTab.panel, addonName)
Settings.RegisterAddOnCategory( addonTab.category )

-- ######################################################################## --
-- -- Make a child panel
-- addonTab.childpanel = CreateFrame( "Frame", addonName.."ChildPanel", addonTab.panel);
-- addonTab.childpanel.name = addonName.."Child";
-- -- Specify childness of this panel (this puts it under the little red [+], instead of giving it a normal AddOn category)
-- addonTab.childpanel.parent = addonTab.panel.name;
-- -- Add the child to the Interface Options
-- InterfaceOptions_AddCategory(addonTab.childpanel);
-- ######################################################################## --
-- The following members and methods are used by the Interface Options frame to display and organize panels.
--
-- panel.name - string (required)
--	The name of the AddOn or group of configuration options.
--	This is the text that will display in the AddOn options list.
--
-- panel.parent - string (optional)
--	Name of the parent of the AddOn or group of configuration options.
--	This identifies "panel" as the child of another category.
--	If the parent category doesn't exist, "panel" will be displayed as a regular category.
--
-- panel.okay - function (optional)
--	This method will run when the player clicks "okay" in the Interface Options.
--
-- panel.cancel - function (optional)
--	This method will run when the player clicks "cancel" in the Interface Options.
--	Use this to revert their changes.
--
-- panel.default - function (optional)
--	This method will run when the player clicks "defaults".
--	Use this to revert their changes to your defaults.
-- ######################################################################## --
-- EXAMPLE -- Dynamically create a frame and use it as a subcategory for "My AddOn".
--
--	local panel = CreateFrame("FRAME", "ExampleSubCategory");
--	panel.name = "My SubCategory";
--	panel.parent = "My AddOn";
--
--	InterfaceOptions_AddCategory(panel);
--
-- EXAMPLE -- Create a frame with a control, an okay and a cancel method
--
--	--[[ Create a frame to use as the panel ]] --
--	local panel = CreateFrame("FRAME", "ExamplePanel");
--	panel.name = "My AddOn";
--
--	-- [[ When the player clicks okay, set the original value to the current setting ]] --
--	panel.okay =
--		function (self)
--			self.originalValue = MY_VARIABLE;
--		end
--
--	-- [[ When the player clicks cancel, set the current setting to the original value ]] --
--	panel.cancel =
--		function (self)
--			MY_VARIABLE = self.originalValue;
--		end
--
--	-- [[ Add the panel to the Interface Options ]] --
--	InterfaceOptions_AddCategory(panel);

-- ######################################################################## --

--Panel Title
local AddOnOptionsPanelTitleFS = AddOnOptionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	-- AddOnOptionsPanelTitleFS:SetText(addonName) -- Default color
	AddOnOptionsPanelTitleFS:SetText('|cff00c0ff'..addonName..'|r') --Custom color
	AddOnOptionsPanelTitleFS:SetPoint("TOPLEFT", 10, -10)
	AddOnOptionsPanelTitleFS:SetFont("Fonts\\FRIZQT__.TTF", 20)

-- Version Info, bottom right of Interface Options Panel
local AddOnOptionsPanelTitleVersionFS = AddOnOptionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	-- AddOnOptionsPanelTitleVersionFS:SetText(addonTab.version) -- Default color
	AddOnOptionsPanelTitleVersionFS:SetText('|cff00c0ff' .. addonTab.version .. '|r') --Custom color
	AddOnOptionsPanelTitleVersionFS:SetPoint("BOTTOMRIGHT", -10, 10)
	AddOnOptionsPanelTitleVersionFS:SetFont("Fonts\\FRIZQT__.TTF", 12)

-- ######################################################################## --

local function FMM_SetPoints() -- Function called by slash commands; skip to --Slash Setup if a reset function isn't needed.
	--Slider
	local slideValue = addonTab.db.mmsliderSetScale.minimapScale
	MMSlider:SetValue(slideValue)
	Minimap:SetScale(slideValue)
	fmMMminimapframe:SetScale(slideValue)
	getglobal(MMSlider:GetName() .. 'Text'):SetFormattedText("Minimap Scale = (%.2f)", (slideValue)); --Sets the "title" text (top-centre of slider).

	--Minimap Anchor Frame
	local point = addonTab.db.minimapSetPoints
		fmMMminimapframe:ClearAllPoints()
		fmMMminimapframe:SetPoint(
			point.point,
			point.relativeTo,
			point.relativePoint,
			point.xOffset,
			point.yOffset)

	--Minimap Frame
	Minimap:ClearAllPoints()
	Minimap:SetPoint("CENTER", fmMMminimapframe, "CENTER", 0, 0)
end

-- ######################################################################## --

--Slash Setup
function addonTab.ShowHelp()
	print(addonName.."("..addonTab.version..") Slash commands:")
	print("  /fmm (l)ock: Locks all "..addonName.." movable frames.")
	print("  /fmm (u)nlock: Unlocks all "..addonName.." movable frames.")
	print("  /fmm (c)onfig: Open the "..addonName.." addon configuration menu.")
	print("  /fmm reset:  Reset "..addonName.." to its defaults.")
	print('Examples: "/fmm c" or "/fmm config" opens the configuration menu.')
end

function addonTab.SetConfigToDefaults()
	print("Resetting config to defaults")
	FMM_SetPoints()
	ReloadUI();
end

function addonTab.GetConfigValue(key)
	return _G[addonName.."DBPC"][key]
end

function addonTab.PrintPerformanceData()
	UpdateAddOnMemoryUsage()
	local mem = GetAddOnMemoryUsage(addonName)
	print(addonName.." is currently using " .. mem .. " kbytes of memory")
	collectgarbage(collect)
	UpdateAddOnMemoryUsage()
	mem = GetAddOnMemoryUsage(addonName)
	print(addonName.." is currently using " .. mem .. " kbytes of memory after garbage collection")
end

function addonTab.SlashCmdHandler(msg, editbox)
	--print("command is " .. msg .. "\n")
	if (string.lower(msg) == "config") or (string.lower(msg) == "c") then
		C_Timer.After(0.1, function()
			Settings.OpenToCategory(addonTab.category:GetID());
		end)
		SetPoints_AddOnOptionsPanel()
		AddOnOptionsPanel:Show()
	elseif (string.lower(msg) == "dumpconfig") then
		print("With defaults")
		for k,v in pairs(fmMMDefaultConfig) do
			print(k,addonTab.GetConfigValue(k))
		end
		print("Direct table")
		for k,v in pairs(fmMMDefaultConfig) do
			print(k,v)
		end
	elseif (string.lower(msg) == "lock") or (string.lower(msg) == "l") then
		fmMMlockcheckframe:Hide()
		fmMMlockcheck:SetChecked(true)
	elseif (string.lower(msg) == "unlock") or (string.lower(msg) == "u") then
		fmMMlockcheckframe:Show()
		fmMMlockcheck:SetChecked(false)
	elseif (string.lower(msg) == "reset") then
		FMM_SetPoints()
		ReloadUI();
	elseif (string.lower(msg) == "perf") then
		addonTab.PrintPerformanceData()
	else
		addonTab.ShowHelp()
	end
end

SLASH_addonName1 = "/fmm"
local slashName = addonName
SlashCmdList["addonName"] = function(message, editbox) addonTab.SlashCmdHandler(message, editbox) end

-- ######################################################################## --

local FMM_isClassic
local _, _, _, tocversion = GetBuildInfo()
if (tocversion < 30000) then
	FMM_isClassic = true
end

local fmMMresetcheck = CreateFrame("Button", "fmMMresetcheck", AddOnOptionsPanel, "UIPanelButtonGrayTemplate")
	fmMMresetcheck:RegisterEvent("PLAYER_LOGIN")
	fmMMresetcheck:ClearAllPoints()
	fmMMresetcheck:SetPoint("BOTTOMLEFT", AddOnOptionsPanel, 5, 5)
	fmMMresetcheck:SetScale(1.25)
	fmMMresetcheck:SetWidth(125)
	fmMMresetcheck:SetHeight(30)
	fmMMresetcheck:Show()

local fmMMresetcheckButtonButtonFS = fmMMresetcheck:CreateFontString("FontString","OVERLAY","GameTooltipText")
	fmMMresetcheckButtonButtonFS:SetPoint("CENTER", fmMMresetcheck)
	fmMMresetcheckButtonButtonFS:SetFont("Fonts\\FRIZQT__.TTF", 12)
	fmMMresetcheckButtonButtonFS:SetShadowOffset(1, -1)
	fmMMresetcheckButtonButtonFS:SetTextColor(0, 0.75, 1, 1);
	fmMMresetcheckButtonButtonFS:SetText("Reset to Default")

local fmMMresetcheckButtonTexture=fmMMresetcheck:CreateTexture(nil,"ARTWORK")
	fmMMresetcheckButtonTexture:SetPoint("CENTER", fmMMresetcheck, "CENTER", -1, -1)
	fmMMresetcheckButtonTexture:SetColorTexture(0, 0.75, 1, 1)

	fmMMresetcheck:SetScript("OnClick", function (self, button, down)
		_G[addonName.."DBPC"] = addonTab.defaults;
		addonTab.db = _G[addonName.."DBPC"]
		FMM_SetPoints()
		ReloadUI();
	end)

	local function fmMMresetcheckTooltip()
		GameTooltip:SetOwner(fmMMresetcheck, "ANCHOR_RIGHT");
		GameTooltip:SetText(fmMMresetcheckButtontooltipText, 0, 0.75, 1, 1, true)
	end

	fmMMresetcheckButtontooltipText = ("Resetting to default\nwill reload your UI.") --Creates a tooltip on mouseover.

	fmMMresetcheck:SetScript("OnEnter", function(self)
		fmMMresetcheckTooltip()
		GameTooltip:Show()
	end)

	fmMMresetcheck:SetScript("OnLeave", function(self)
		GameTooltip_Hide()
	end)

 fmMMlockcheck = CreateFrame("CheckButton", "FreeMinimapLockAll", AddOnOptionsPanel, "InterfaceOptionsCheckButtonTemplate")
	fmMMlockcheck:ClearAllPoints()
	fmMMlockcheck:SetPoint("TOPLEFT", 25, -50)
	fmMMlockcheck:SetScale(1.25)
	_G[fmMMlockcheck:GetName() .. "Text"]:SetText("Lock all frames")
	fmMMlockcheck.tooltipText = 'Checked locks all FreeMinimap frames. Unchecked unlocks all FreeMinimap frames.' --Creates a tooltip on mouseover.
	fmMMlockcheck:SetChecked(true)

	fmMMlockcheckframe=CreateFrame("Frame", "fmMMlockcheckframe", UIParent)
	fmMMlockcheckframe:SetClampedToScreen(1)
	fmMMlockcheckframe:SetFrameStrata("BACKGROUND")
	fmMMlockcheckframe:SetFrameLevel("1")
	fmMMlockcheckframe:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT")
	fmMMlockcheckframe:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT")
	fmMMlockcheckframe:Hide()

	-- Lock/Unlock Frames
	fmMMlockcheck:SetScript("OnClick", function(self,button,down)
		if self:GetChecked(true) then
			fmMMlockcheckframe:Hide()
		else
			fmMMlockcheckframe:Show()
		end
	end)

-- ######################################################################## --

-- Free Minimap
addonTab.defaults.minimapSetPoints = {
	point = "TOPRIGHT",
	relativeTo = "fmMMlockcheckframe",
	relativePoint = "TOPRIGHT",
	xOffset = 0,
	yOffset = 0,
}

-- fmMMMinimapFrame
local fmMMminimapframe=CreateFrame("Frame", "fmMMminimapframe", fmMMlockcheckframe)
	fmMMminimapframe:RegisterEvent("PLAYER_LOGIN")
	fmMMminimapframe:SetFrameStrata("HIGH")
	fmMMminimapframe:SetFrameStrata(5)
	fmMMminimapframe:SetClampedToScreen(true)
	fmMMminimapframe:SetMovable(true)
	fmMMminimapframe:EnableMouse(true)
	fmMMminimapframe:RegisterForDrag("LeftButton")
	fmMMminimapframe:SetWidth(120)
	fmMMminimapframe:SetHeight(120)
	fmMMminimapframe:Show()

	fmMMminimapframe:SetScript("OnEvent", function(self, event, arg1)
		if event == "PLAYER_LOGIN" then
			FMM_SetPoints()
		end
	end)

	fmMMminimapframe:SetScript("OnDragStart", fmMMminimapframe.StartMoving)

	fmMMminimapframe:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		self:SetUserPlaced(false)

		point, relativeTo, relativePoint, xOfs, yOfs = self:GetPoint(1)
			if ( relativeTo ) then
				relativeTo = relativeTo:GetName();
			else
				relativeTo = self:GetParent():GetName();
			end

		-- These are debugging messages for the frame points
		-- Un-comment them to help debug
		-- DEFAULT_CHAT_FRAME:AddMessage(point)
		-- DEFAULT_CHAT_FRAME:AddMessage(relativeTo)
		-- DEFAULT_CHAT_FRAME:AddMessage(relativePoint)
		-- DEFAULT_CHAT_FRAME:AddMessage(xOfs)
		-- DEFAULT_CHAT_FRAME:AddMessage(yOfs)

		addonTab.db.minimapSetPoints.point = point
		addonTab.db.minimapSetPoints.relativeTo = relativeTo
		addonTab.db.minimapSetPoints.relativePoint = relativePoint
		addonTab.db.minimapSetPoints.xOffset = xOfs
		addonTab.db.minimapSetPoints.yOffset = yOfs
	end)

local fmMMminimapframeFS = fmMMminimapframe:CreateFontString("FontString","OVERLAY","GameTooltipText")
local fmMMminimapFS = fmMMminimapframe:CreateFontString("FontString","OVERLAY","GameTooltipText")

	fmMMminimapFS:SetPoint("CENTER",fmMMminimapframe,"CENTER",0,0)
	fmMMminimapFS:SetFont("Fonts\\FRIZQT__.TTF", 10, "THINOUTLINE")
	fmMMminimapFS:SetText("MiniMap");
	fmMMminimapFS:SetTextColor(1, 1, 1);

local t=fmMMminimapframe:CreateTexture(nil,"ARTWORK")
	t:SetAllPoints(fmMMminimapframe)
	t:SetColorTexture(0, 192, 255, 0.7)

	addonTab.defaults.mmsliderSetScale = {
		minimapScale = 1.16,
	}

-- ######################################################################## --

-- Minimap Slider:
local MMSlider = CreateFrame("Slider", "MMSlider", AddOnOptionsPanel, "OptionsSliderTemplate")
	MMSlider:RegisterEvent("PLAYER_LOGIN")
	MMSlider:RegisterEvent("PLAYER_ENTERING_WORLD")
	MMSlider:RegisterEvent("ADDON_LOADED")
	MMSlider:SetPoint("CENTER", AddOnOptionsPanel, "CENTER", 0, 0)
	MMSlider:SetWidth(200)
	MMSlider:SetHeight(10)
	MMSlider:SetOrientation('HORIZONTAL')
	MMSlider:SetMinMaxValues(0.50, 3.0)
	MMSlider.minValue, MMSlider.maxValue = MMSlider:GetMinMaxValues()
	MMSlider:SetValueStep(0.05)
	MMSlider:SetObeyStepOnDrag(true)

	MMSlider.tooltipText = 'Scale the minimap in increments or decrements of 5' --Creates a tooltip on mouseover.

	getglobal(MMSlider:GetName() .. 'Low'):SetText(MMSlider.minValue); --Sets the left-side slider text (default is "Low").
	getglobal(MMSlider:GetName() .. 'High'):SetText(MMSlider.maxValue); --Sets the right-side slider text (default is "High").

	MMSlider:Show()

	MMSlider:SetScript("OnEvent", function(self, event, arg1)
		if event == "PLAYER_LOGIN" then
			FMM_SetPoints()
		end
	end)

	MMSlider:SetScript("OnValueChanged", function(self, value)
	local slideValue = MMSlider:GetValue()
		Minimap:SetScale(slideValue)
		fmMMminimapframe:SetScale(slideValue)

		getglobal(MMSlider:GetName() .. 'Text'):SetFormattedText("Minimap Scale = (%.2f)", (slideValue)); --Sets the "title" text (top-centre of slider).
		addonTab.db.mmsliderSetScale.minimapScale = slideValue
	end)

-- ######################################################################## --

-- Actual Minimap features and functions

--Hide Minimap Frames
if MinimapCluster.BorderTop then
	MinimapCluster.BorderTop:Hide()
end
if MinimapBorderTop then
	MinimapBorderTop:Hide()
end
MinimapBorder:Hide()
MinimapZoomIn:Hide()
MinimapZoomOut:Hide()
MinimapNorthTag:Hide()
if not FMM_isClassic then MiniMapTracking:SetAlpha(0) end

--Hide Minimap Clock
local mm = CreateFrame("Frame", "FreeMinimapFrame")

	mm:RegisterEvent("PLAYER_LOGIN")
	mm:RegisterEvent("PLAYER_ENTERING_WORLD")
	mm:RegisterEvent("ADDON_LOADED")
	if not FMM_isClassic then mm:RegisterEvent("PET_BATTLE_OVER") end
	mm:RegisterEvent("UPDATE_INSTANCE_INFO")

local function eventHandler(self, event, ...)
	for i = 1, 1 do
		if TimeManagerClockButton then
			TimeManagerClockButton:SetAlpha(0)
		end
	end
end

mm:SetScript("OnEvent",eventHandler)

-- Make Minimap Movable
Minimap:RegisterEvent("PLAYER_LOGIN")
Minimap:SetFrameStrata("MEDIUM")
Minimap:SetFrameLevel("5")
Minimap:SetClampedToScreen(true)
Minimap:SetMovable(true)
Minimap:EnableMouse(true)
Minimap:RegisterForDrag("LeftButton")
Minimap:SetMaskTexture('Interface\\ChatFrame\\ChatFrameBackground')
Minimap:EnableMouseWheel(true)

Minimap:SetScript("OnEvent", function(self, event, arg1)
	if event == "PLAYER_LOGIN" then
	local slideValue = addonTab.db.mmsliderSetScale
		self:SetScale(slideValue.minimapScale)
	end
end)

Minimap:SetScript("OnMouseWheel", function(mp, input)
local zoom = Minimap:GetZoom()
	if input > 0 and zoom < 5 then
		mp:SetZoom(zoom +1)
	elseif input < 0 and zoom > 0 then
		mp:SetZoom(zoom -1)
	end
end)

-- Move Minimap Icons
MiniMapMailBorder:SetAlpha(0)
MiniMapMailFrame:SetScale(1.25)
MiniMapMailFrame:ClearAllPoints()
MiniMapMailFrame:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", 7, 5)

GameTimeFrame:SetAlpha(0)
GameTimeFrame:ClearAllPoints()
GameTimeFrame:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", 0, 0)

if MiniMapWorldMapButton then
	MiniMapWorldMapButton:SetScale(1.5)
	MiniMapWorldMapButton:SetAlpha(0)
	MiniMapWorldMapButton:ClearAllPoints()
	MiniMapWorldMapButton:SetPoint("TOP", Minimap, "TOP", 0, 10)
end

MinimapBackdrop:ClearAllPoints()
MinimapBackdrop:SetParent(Minimap)
MinimapBackdrop:SetPoint("TOP", Minimap, "TOP", 0, 0)

--Zone Text
MinimapCompassTexture:SetParent(Minimap)
MinimapZoneTextButton:ClearAllPoints()
MinimapZoneTextButton:SetParent(Minimap)
MinimapZoneTextButton:SetPoint("TOP", Minimap, "TOP", 0, 0)

if (MiniMapRecordingBorder~=nil) then
	MiniMapRecordingBorder:SetAlpha(0)
	MiniMapRecordingButton:ClearAllPoints()
	MiniMapRecordingButton:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", 0, 0)
end

if FMM_isClassic then
	MinimapToggleButton:Hide()
end

if not FMM_isClassic then
	if QueueStatusMinimapButton then
		MiniMapTracking:ClearAllPoints()
		MiniMapTracking:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 0, 0)
	end

	if QueueStatusMinimapButton then
		QueueStatusMinimapButton:ClearAllPoints()
		QueueStatusMinimapButton:SetParent(Minimap)
		QueueStatusMinimapButton:SetPoint("CENTER", Minimap, "LEFT", 0, 0)
	end

	if QueueStatusMinimapButton then
		QueueStatusFrame:ClearAllPoints()
		QueueStatusFrame:SetFrameStrata("TOOLTIP")
		QueueStatusFrame:SetParent(Minimap)
		QueueStatusFrame:SetPoint("BOTTOMRIGHT", Minimap, "TOPRIGHT", -2, 2)
	end

	if QueueStatusMinimapButton then
		MiniMapInstanceDifficulty_AdjustPosition = function() end
		MiniMapInstanceDifficulty:SetParent(UIParent)
		MiniMapInstanceDifficulty:SetScale(0.5)
		MiniMapInstanceDifficulty:ClearAllPoints()
		MiniMapInstanceDifficulty:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 0, 0)
	end

	if QueueStatusMinimapButton then
		GuildInstanceDifficulty_AdjustPosition = function() end
		GuildInstanceDifficulty:SetParent(UIParent)
		GuildInstanceDifficulty:SetScale(0.5)
		GuildInstanceDifficulty:ClearAllPoints()
		GuildInstanceDifficulty:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 0, 0)
	end

	if QueueStatusMinimapButton then
		GarrisonLandingPageMinimapButton:SetParent(MinimapBackdrop)
		GarrisonLandingPageMinimapButton:SetScale(1.0)
		GarrisonLandingPageMinimapButton:ClearAllPoints()
		GarrisonLandingPageMinimapButton:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", -10, -10)
		GarrisonLandingPageMinimapButton:SetScale(0.75)
		GarrisonLandingPageMinimapButton:SetAlpha(0.5)
	end
end

-- Create New Minimap Clock
local use24hformat = false

local mmclock = CreateFrame("Frame", nil, Minimap)
	mmclock:RegisterEvent("PLAYER_LOGIN")
	mmclock:RegisterEvent("PLAYER_ENTERING_WORLD")
	mmclock:RegisterEvent("ADDON_LOADED")
	mmclock:RegisterEvent("PLAYER_REGEN_DISABLED")
	mmclock:RegisterEvent("PLAYER_REGEN_ENABLED")
	mmclock:RegisterEvent("UNIT_COMBAT")
	if not FMM_isClassic then
		mmclock:RegisterEvent("PET_BATTLE_OVER")
		mmclock:RegisterEvent("PET_BATTLE_OPENING_START")
	end
	mmclock:SetFrameStrata("MEDIUM")
	mmclock:SetFrameLevel("9")
	mmclock:SetWidth(100)
	mmclock:SetHeight(26)
	mmclock:Show()

	mmclock:SetScript("OnEvent", function()
		if C_AddOns.IsAddOnLoaded("NovaWorldBuffs") then
			if MinimapLayerFrame then
				MinimapLayerFrame:HookScript("OnShow", function(self)
					mmclock:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, 20)
				end)
				MinimapLayerFrame:HookScript("OnHide", function(self)
					mmclock:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, 0)
				end)
			end
		else
			mmclock:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, 0)
		end
		MinimapClockRefresh()
	end)

	local clockFS = mmclock:CreateFontString("FontString","OVERLAY","GameTooltipText")

	clockFS:SetTextColor(1, 1, 1);
	clockFS:SetPoint("BOTTOM",mmclock,"BOTTOM",0,0)

local elapsed = 0
	mmclock:SetScript("OnUpdate", function(self, e)
	   elapsed = elapsed + e
	   if elapsed >= 1 then
		   MinimapClockRefresh()
		   elapsed = 0
	   end
end)


function MinimapClockRefresh()
	if use24hformat then
		clockFS:SetFont("Fonts\\FRIZQT__.TTF", 12, "THINOUTLINE")
		clockFS:SetText(date("%H:%M"))
	else
		clockFS:SetFont("Fonts\\FRIZQT__.TTF", 12, "THINOUTLINE")
		clockFS:SetText(("%d:%s"):format(tonumber(date("%I")),((date("%M%p")))))
	end
end

-- -- Minimap Coordinates
local coordframe = CreateFrame("Frame", nil, Minimap)
	coordframe:SetFrameStrata("MEDIUM")
	coordframe:SetFrameLevel("9")
	coordframe:SetWidth(100)
	coordframe:SetHeight(26)
	coordframe:SetPoint("TOP", MinimapZoneTextButton, "BOTTOM", 0, 0)
	coordframe:Show()

local elapsed = 0
local coordframeFS = coordframe:CreateFontString("FontString","OVERLAY","GameTooltipText")
local coordFS = coordframe:CreateFontString("FontString","OVERLAY","GameTooltipText")

function coordRefresh()
	local mapID = C_Map.GetBestMapForUnit("player")
	if mapID then
		local pos = C_Map.GetPlayerMapPosition(mapID, "player")
		if (pos == nil) or (pos.x == nil) or (pos.y == nil) then
			coordFS:SetText("--, --")
			return
		end
		if pos and pos.x ~= 0 and pos.y ~= 0 then
			coordFS:SetFormattedText("%.1f, %.1f", pos.x*100, pos.y*100)
		end
	else
		coordFS:SetText("--, --")
	end
end

	coordFS:SetPoint("TOP",coordframe,"TOP",0,0)

	coordframe:SetScript("OnEvent", function()
		coordFS:SetTextColor(1, 1, 1);
		coordRefresh()
	end)

	coordframe:SetScript("OnUpdate", function(self, e)
		local inInstance, instanceType = IsInInstance()
		if not IsInInstance(player) then
		elapsed = elapsed + e
		if elapsed >= 1 then
			coordRefresh()
			elapsed = 0
		end
		else
			coordFS:SetFormattedText("")
		end
	end)
