-- Free Minimap - options window (/fmm)
-- Same look as the other Free addons (graphite + ember). Opens inside Free Hub when it is installed.

local ADDON, ns = ...

local MEDIA  = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local WHITE  = "Interface\\Buttons\\WHITE8x8"
local CIRCLE = MEDIA .. "circle"
local FONT   = "Fonts\\ARIALN.TTF"

local C = {
    bg       = { 0.070, 0.074, 0.085, 0.97 },
    panel    = { 0.098, 0.104, 0.118, 1 },
    control  = { 0.145, 0.151, 0.170, 1 },
    hover    = { 0.190, 0.197, 0.222, 1 },
    text     = { 0.930, 0.937, 0.955, 1 },
    dim      = { 0.700, 0.712, 0.750, 1 },
    muted    = { 0.500, 0.515, 0.560, 1 },
    accent   = { 1.000, 0.540, 0.240, 1 },
    accentHi = { 1.000, 0.640, 0.380, 1 },
    onAccent = { 0.100, 0.050, 0.020, 1 },
}

local W, H = 720, 560
local PAD = 18
local frame
local refreshers = {}
local function OnRefresh(fn) refreshers[#refreshers + 1] = fn end

-- Elements that follow the two-column layout when the window is resized (inside Free Hub).
-- Each one remembers its place for the natural width W; the right column moves and both columns widen.
local GAP = 40
local COLW0 = (W - 2 * PAD - GAP) / 2
local RX0 = PAD + COLW0 + GAP
local flow, onResize = {}, {}
-- point: anchor of the element, placed at (x, y) from the parent's top-left corner.
-- right: x is a right edge (moves with the column width). width: stretched with the column.
local function Flow(obj, point, x, y, width, right)
    flow[#flow + 1] = { o = obj, p = point, x = x, y = y, w = width, right = right }
end
local function Reflow(width)
    width = math.max(W, width or W)
    local colW = (width - 2 * PAD - GAP) / 2
    local dC = colW - COLW0
    local rx = PAD + colW + GAP
    for _, e in ipairs(flow) do
        if e.p then
            local x = e.x
            if x >= RX0 - 1 then x = x - RX0 + rx end
            if e.right then x = x + dC end
            e.o:SetPoint(e.p, e.o:GetParent(), "TOPLEFT", x, e.y)
        end
        if e.w and e.w >= 100 then e.o:SetWidth(e.w + dC) end
    end
    for _, fn in ipairs(onResize) do fn(width) end
end

-- settings of this character; the native zoom is read from the minimap when it was never chosen
local function Cfg() return ns.pc end
local function Val(field)
    local pc = ns.pc
    if field == "zoom" then
        local z = pc.zoom
        if not z or z < 0 then z = Minimap:GetZoom() end
        return z
    end
    return pc[field]
end
local function Set(field, value)
    ns.pc[field] = value
    if ns.ApplyLayout then ns.ApplyLayout() end
    if frame then frame:Refresh() end
end

-- ------------------------------------------------------------ primitives
local function SetFont(obj, size, flags)
    obj:SetFont(FONT, size, flags or "")
    if not obj:GetFont() then obj:SetFont(STANDARD_TEXT_FONT, size, flags or "") end
end

local function Text(parent, size, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    SetFont(fs, size)
    fs:SetTextColor(unpack(color))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    return fs
end

local function Fill(parent, color, layer, sub)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
    t:SetTexture(WHITE)
    t:SetVertexColor(unpack(color))
    return t
end

local function Border(f, alpha, layer)
    f.edges = {}
    for i, p in ipairs({ { "TOPLEFT", "TOPRIGHT", "h" }, { "BOTTOMLEFT", "BOTTOMRIGHT", "h" },
                         { "TOPLEFT", "BOTTOMLEFT", "v" }, { "TOPRIGHT", "BOTTOMRIGHT", "v" } }) do
        local e = f:CreateTexture(nil, layer or "BORDER")
        e:SetTexture(WHITE)
        e:SetVertexColor(1, 1, 1, alpha or 0.07)
        e:SetPoint(p[1]); e:SetPoint(p[2])
        if p[3] == "h" then e:SetHeight(1) else e:SetWidth(1) end
        f.edges[i] = e
    end
end
local function BorderColor(f, r, g, b, a) for _, e in ipairs(f.edges) do e:SetVertexColor(r, g, b, a) end end

local function Label(parent, text, x, y)
    local fs = Text(parent, 13, C.text)
    fs:SetPoint("TOPLEFT", x, y)
    Flow(fs, "TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function Hint(parent, text, x, y, width)
    local fs = Text(parent, 11, C.muted)
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetWidth(width)
    Flow(fs, "TOPLEFT", x, y, width)
    fs:SetText(text or "")
    return fs
end

local function Caption(parent, text, x, y)
    local fs = Text(parent, 11, C.accent)
    fs:SetPoint("TOPLEFT", x, y)
    Flow(fs, "TOPLEFT", x, y)
    fs:SetText(text:upper())
    return fs
end

-- ------------------------------------------------------------ controls
local function Button(parent, label, width, primary, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 28)
    b.bg = Fill(b, primary and C.accent or C.control)
    b.bg:SetAllPoints()
    if not primary then Border(b, 0.08) end
    b.label = Text(b, 13, primary and C.onAccent or C.text)
    b.label:SetPoint("CENTER")
    b.label:SetText(label)
    b:SetScript("OnEnter", function(self) self.bg:SetVertexColor(unpack(primary and C.accentHi or C.hover)) end)
    b:SetScript("OnLeave", function(self) self.bg:SetVertexColor(unpack(primary and C.accent or C.control)) end)
    b:SetScript("OnClick", onClick)
    return b
end

-- Switch: track and knob are regions of the same button (knob on a higher layer).
local function Switch(parent, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(34, 18)
    local function cap(left)
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetTexture(CIRCLE)
        t:SetTexCoord(left and 0 or 0.5, left and 0.5 or 1, 0, 1)
        t:SetSize(9, 18)
        t:SetPoint(left and "LEFT" or "RIGHT")
        return t
    end
    local l, r = cap(true), cap(false)
    local m = b:CreateTexture(nil, "ARTWORK"); m:SetTexture(WHITE)
    m:SetPoint("TOPLEFT", l, "TOPRIGHT"); m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
    local knob = b:CreateTexture(nil, "OVERLAY"); knob:SetTexture(CIRCLE); knob:SetSize(14, 14)
    local function paint(on)
        local col = on and C.accent or C.control
        l:SetVertexColor(unpack(col)); r:SetVertexColor(unpack(col)); m:SetVertexColor(unpack(col))
        knob:ClearAllPoints()
        if on then
            knob:SetPoint("RIGHT", -2, 0); knob:SetVertexColor(unpack(C.onAccent))
        else
            knob:SetPoint("LEFT", 2, 0); knob:SetVertexColor(unpack(C.dim))
        end
    end
    b:SetScript("OnClick", function() set(not get()); paint(get()) end)
    OnRefresh(function() paint(get() and true or false) end)
    return b
end

local function SwitchRow(parent, text, x, y, width, get, set)
    Label(parent, text, x, y - 2)
    local s = Switch(parent, get, set)
    s:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width, y)
    Flow(s, "TOPRIGHT", x + width, y, nil, true)
    return s
end

local function Segmented(parent, items, x, y, width, get, set, height)
    height = height or 26
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, height)
    f:SetPoint("TOPLEFT", x, y)
    Flow(f, "TOPLEFT", x, y, width)
    local bg = Fill(f, C.control); bg:SetAllPoints()
    local buttons = {}
    local function layout()
        local w = (f:GetWidth() or width) / #items
        if not w or w <= 0 then w = width / #items end
        for i, b in ipairs(buttons) do
            b:SetSize(w - 2, height - 4)
            b:SetPoint("LEFT", 1 + (i - 1) * w, 0)
        end
    end
    f:SetScript("OnSizeChanged", layout)
    for i, it in ipairs(items) do
        local b = CreateFrame("Button", nil, f)
        b.sel = Fill(b, C.accent, "ARTWORK"); b.sel:SetAllPoints()
        b.hl = Fill(b, { 1, 1, 1, 0.05 }, "ARTWORK", 1); b.hl:SetAllPoints(); b.hl:Hide()
        b.label = Text(b, 12, C.dim); b.label:SetPoint("CENTER"); b.label:SetText(it[2])
        b:SetScript("OnEnter", function(self) self.hl:Show() end)
        b:SetScript("OnLeave", function(self) self.hl:Hide() end)
        b:SetScript("OnClick", function() set(it[1]) end)
        b.value = it[1]
        buttons[i] = b
    end
    layout()
    OnRefresh(function()
        local v = get()
        for _, b in ipairs(buttons) do
            local on = (b.value == v)
            b.sel:SetShown(on)
            b.label:SetTextColor(unpack(on and C.onAccent or C.dim))
        end
    end)
    return f
end

local function InputBox(parent, width, height)
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetSize(width, height or 24)
    eb:SetAutoFocus(false)
    eb:SetTextInsets(6, 6, 0, 0)
    SetFont(eb, 13)
    eb:SetTextColor(unpack(C.text))
    local bg = Fill(eb, C.control); bg:SetAllPoints()
    Border(eb, 0.08)
    eb:SetScript("OnEditFocusGained", function(self) BorderColor(self, C.accent[1], C.accent[2], C.accent[3], 0.9); self:HighlightText() end)
    eb:SetScript("OnEditFocusLost", function(self) BorderColor(self, 1, 1, 1, 0.08); self:HighlightText(0, 0) end)
    return eb
end

local function num(text)
    local t = (text or ""):gsub(",", ".")
    t = t:gsub("[^%d%.%-]", "")
    return tonumber(t)
end
local function fmtNum(v)
    if math.floor(v) == v then return tostring(v) end
    local s = string.format("%.2f", v):gsub("0+$", "")
    s = s:gsub("%.$", "")
    return s
end

-- Slider row: slim slider with an indicative range + free value box (no limit).
local function SliderRow(parent, text, x, y, width, field, o)
    Label(parent, text, x, y - 5)
    local box = InputBox(parent, 64)
    box:SetJustifyH("CENTER")
    box:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width, y)
    Flow(box, "TOPRIGHT", x + width, y, nil, true)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(width - 110 - 64 - 12, 18)
    Flow(s, nil, 0, 0, width - 110 - 64 - 12)
    s:SetPoint("RIGHT", box, "LEFT", -12, 0)
    s:SetMinMaxValues(o.lo, o.hi)
    s:SetValueStep(o.step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouseWheel(true)
    local track = Fill(s, { 1, 1, 1, 0.10 }); track:SetHeight(4); track:SetPoint("LEFT"); track:SetPoint("RIGHT")
    local fill = Fill(s, C.accent, "ARTWORK"); fill:SetHeight(4); fill:SetPoint("LEFT")
    s:SetThumbTexture(WHITE)
    local thumb = s:GetThumbTexture()
    thumb:SetSize(6, 16)
    thumb:SetVertexColor(unpack(C.text))

    local getV = o.get or function() return Val(field) end
    local setV = o.set or function(v) Set(field, v) end
    local toS = o.toSlider or function(v) return v end
    local fromS = o.fromSlider or function(v) return v end
    local updating = false
    local function paint(v)
        local frac = (math.max(o.lo, math.min(o.hi, v)) - o.lo) / (o.hi - o.lo)
        fill:SetWidth(math.max(0.01, frac * s:GetWidth()))
    end
    s:SetScript("OnSizeChanged", function() paint(toS(getV())) end)
    s:SetScript("OnValueChanged", function(_, v)
        paint(v)
        if updating then return end
        v = math.floor(v / o.step + 0.5) * o.step
        setV(fromS(v))
    end)
    s:SetScript("OnMouseWheel", function(_, d)
        local v = toS(getV()) + d * o.step * (IsShiftKeyDown() and 10 or 1)
        local parsed = o.parse(fmtNum(v))
        if parsed ~= nil then setV(parsed) end
    end)
    s:SetScript("OnEnter", function() thumb:SetVertexColor(unpack(C.accent)) end)
    s:SetScript("OnLeave", function() thumb:SetVertexColor(unpack(C.text)) end)
    box:SetScript("OnEnterPressed", function(self)
        local v = o.parse(self:GetText())
        self:ClearFocus()
        if v ~= nil then setV(v) else frame:Refresh() end
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); frame:Refresh() end)
    OnRefresh(function()
        local v = toS(getV())
        updating = true
        s:SetValue(math.max(o.lo, math.min(o.hi, v)))
        updating = false
        paint(v)
        if not box:HasFocus() then box:SetText(o.fmt(getV())) end
    end)
end
-- Dropdown with optional texture preview (items: { key=, label=, path= })
local openList
local function Dropdown(parent, text, x, y, width, getItems, get, set, showTextures)
    Label(parent, text, x, y - 5)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width - 120, 26)
    b:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width, y)
    Flow(b, "TOPRIGHT", x + width, y, width - 120, true)
    local bg = Fill(b, C.control); bg:SetAllPoints()
    Border(b, 0.08)
    local prev = b:CreateTexture(nil, "ARTWORK"); prev:SetPoint("TOPLEFT", 1, -1); prev:SetPoint("BOTTOMRIGHT", -22, 1); prev:SetAlpha(0.35)
    local val = Text(b, 13, C.text); val:SetPoint("LEFT", 8, 0); val:SetPoint("RIGHT", -24, 0); val:SetWordWrap(false)
    local arrow = Text(b, 12, C.dim); arrow:SetPoint("RIGHT", -8, 0); arrow:SetText("v")
    b:SetScript("OnEnter", function() bg:SetVertexColor(unpack(C.hover)) end)
    b:SetScript("OnLeave", function() bg:SetVertexColor(unpack(C.control)) end)

    local list = CreateFrame("Frame", nil, frame)
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetWidth(width - 120)
    list:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
    list:EnableMouse(true)
    list:EnableMouseWheel(true)
    list:Hide()
    local lbg = Fill(list, { 0.11, 0.115, 0.13, 1 }); lbg:SetAllPoints()
    Border(list, 0.12)
    local ROWS, RH = 10, 22
    local rows, offset = {}, 0
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, list)
        r:SetHeight(RH)
        r:SetPoint("TOPLEFT", 1, -1 - (i - 1) * RH); r:SetPoint("TOPRIGHT", -1, -1 - (i - 1) * RH)
        r.tex = r:CreateTexture(nil, "ARTWORK"); r.tex:SetPoint("TOPLEFT", 2, -2); r.tex:SetPoint("BOTTOMRIGHT", -2, 2); r.tex:SetAlpha(0.55)
        r.hl = Fill(r, { 1, 1, 1, 0.08 }, "ARTWORK", 2); r.hl:SetAllPoints(); r.hl:Hide()
        r.text = Text(r, 12, C.text); r.text:SetPoint("LEFT", 8, 0); r.text:SetPoint("RIGHT", -8, 0); r.text:SetWordWrap(false)
        r:SetScript("OnEnter", function(self) self.hl:Show() end)
        r:SetScript("OnLeave", function(self) self.hl:Hide() end)
        r:SetScript("OnClick", function(self) set(self.key); list:Hide(); openList = nil end)
        rows[i] = r
    end
    local function render()
        local items = getItems()
        offset = math.max(0, math.min(offset, #items - ROWS))
        local shown = math.min(ROWS, #items)
        list:SetHeight(shown * RH + 2)
        for i = 1, ROWS do
            local it = items[i + offset]
            local r = rows[i]
            if it then
                r.key = it.key
                r.text:SetText(it.label)
                r.text:SetTextColor(unpack(it.key == get() and C.accent or C.text))
                if showTextures and it.path then r.tex:SetTexture(it.path); r.tex:SetVertexColor(0.8, 0.8, 0.85); r.tex:Show()
                elseif showTextures and it.key == "blizzard" then r.tex:SetAtlas("ui-swingtimerbar-filling-mainhand"); r.tex:SetVertexColor(1, 1, 1); r.tex:Show()
                else r.tex:Hide() end
                r:Show()
            else
                r:Hide()
            end
        end
    end
    list:SetScript("OnMouseWheel", function(_, d) offset = offset - d * 3; render() end)
    b:SetScript("OnClick", function()
        if list:IsShown() then list:Hide(); openList = nil; return end
        if openList then openList:Hide() end
        local items = getItems()
        offset = 0
        for i, it in ipairs(items) do if it.key == get() then offset = math.max(0, i - 5) end end
        -- the window's strata is copied to its children (Free Hub), so put the list back on top each time
        list:SetWidth(b:GetWidth() or (width - 120))
        list:SetFrameStrata("FULLSCREEN_DIALOG")
        list:SetFrameLevel((frame:GetFrameLevel() or 1) + 100)
        render(); list:Show(); openList = list
    end)
    OnRefresh(function()
        local cur = get()
        local label, path = cur, nil
        for _, it in ipairs(getItems()) do if it.key == cur then label, path = it.label, it.path end end
        val:SetText(label)
        if showTextures and path then prev:SetTexture(path); prev:SetVertexColor(1, 1, 1); prev:Show()
        elseif showTextures and cur == "blizzard" then prev:SetAtlas("ui-swingtimerbar-filling-mainhand"); prev:SetVertexColor(1, 1, 1); prev:Show()
        else prev:Hide() end
    end)
end

-- ------------------------------------------------------------ defaults (reset)
local RESET_KEYS = { "posMode", "width", "height", "scale", "buttonScale", "zoom", "regionEnabled", "regionZoom", "regionOverlay",
                     "overlayRound", "overlayCal", "regionSource", "tileScale", "axisOverride", "regionPins", "regionQuests" }
function ns.ResetDefaults()
    local d, pc = ns.character, ns.pc
    if not (d and pc) then return end
    for _, k in ipairs(RESET_KEYS) do pc[k] = d[k] end
    if ns.ResetButtons then ns.ResetButtons() end
    if ns.ApplyLayout then ns.ApplyLayout() end
    if ns.RefreshOptions then ns.RefreshOptions() end
end

-- ------------------------------------------------------------ window
local function Build()
    frame = CreateFrame("Frame", "FreeMinimapOptions", UIParent)
    frame:SetSize(W, H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
    tinsert(UISpecialFrames, "FreeMinimapOptions")
    local shadow = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    frame.fhShadow = shadow
    shadow:SetTexture(MEDIA .. "shadow"); shadow:SetVertexColor(0, 0, 0, 0.8)
    shadow:SetPoint("TOPLEFT", -36, 36); shadow:SetPoint("BOTTOMRIGHT", 36, -36)
    local bg = Fill(frame, C.bg, "BACKGROUND", -6); bg:SetAllPoints()
    Border(frame, 0.09)
    local topLine = Fill(frame, C.accent, "BORDER", 2); topLine:SetHeight(2); topLine:SetPoint("TOPLEFT"); topLine:SetPoint("TOPRIGHT")

    -- header
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT"); header:SetPoint("TOPRIGHT"); header:SetHeight(54)
    header:EnableMouse(true); header:RegisterForDrag("LeftButton")
    -- inside Free Hub, dragging the header moves the hub window instead
    header:SetScript("OnDragStart", function() (frame.fhMover or frame):StartMoving() end)
    header:SetScript("OnDragStop", function() (frame.fhMover or frame):StopMovingOrSizing() end)
    local icon = header:CreateTexture(nil, "ARTWORK"); icon:SetTexture(MEDIA .. "icon"); icon:SetSize(32, 32); icon:SetPoint("LEFT", PAD, -1)
    local title = Text(header, 17, C.text); title:SetPoint("LEFT", icon, "RIGHT", 10, 7); title:SetText("Free Minimap")
    local ver = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or ""
    local sub = Text(header, 11, C.muted); sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3); sub:SetText("Minimap  ·  v" .. ver)
    local close = CreateFrame("Button", nil, header); close:SetSize(26, 26); close:SetPoint("RIGHT", -12, 0)
    local x1 = Fill(close, C.dim, "ARTWORK"); x1:SetSize(14, 2); x1:SetPoint("CENTER"); x1:SetRotation(math.rad(45))
    local x2 = Fill(close, C.dim, "ARTWORK"); x2:SetSize(14, 2); x2:SetPoint("CENTER"); x2:SetRotation(math.rad(-45))
    close:SetScript("OnEnter", function() x1:SetVertexColor(unpack(C.accent)); x2:SetVertexColor(unpack(C.accent)) end)
    close:SetScript("OnLeave", function() x1:SetVertexColor(unpack(C.dim)); x2:SetVertexColor(unpack(C.dim)) end)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame.fhClose = close

    -- status cards: what the minimap shows right now
    local CARDS = {
        { title = "Minimap", state = function() local w, h = ns.GetDims(); return string.format("%d x %d  ·  scale %s", w, h, fmtNum(math.floor((ns.pc.scale or 1) * 100 + 0.5) / 100)) end,
          on = function() return true end },
        { title = "Region map", state = function()
              if not ns.pc.regionEnabled then return "Off" end
              return (ns.pc.regionSource == "art" and "Map art" or "Terrain tiles") .. (ns.pc.regionOverlay and "  ·  real minimap on top" or "")
          end, on = function() return ns.pc.regionEnabled end },
        { title = "Native zoom", state = function() return "Level " .. tostring(Val("zoom")) .. " of 5" end, on = function() return true end },
    }
    local NB = #CARDS
    local cardW = (W - 2 * PAD - (NB - 1) * 8) / NB
    local cards = {}
    onResize[#onResize + 1] = function(width)
        local cw = (width - 2 * PAD - (NB - 1) * 8) / NB
        for i, card in ipairs(cards) do
            card:SetWidth(cw)
            card:SetPoint("TOPLEFT", PAD + (i - 1) * (cw + 8), -62)
        end
    end
    for i, info in ipairs(CARDS) do
        local card = CreateFrame("Frame", nil, frame)
        card:SetSize(cardW, 46)
        card:SetPoint("TOPLEFT", PAD + (i - 1) * (cardW + 8), -62)
        cards[i] = card
        card.bg = Fill(card, C.panel); card.bg:SetAllPoints()
        Border(card, 0.06)
        card.dot = card:CreateTexture(nil, "ARTWORK"); card.dot:SetTexture(CIRCLE); card.dot:SetSize(10, 10); card.dot:SetPoint("TOPLEFT", 12, -12)
        card.name = Text(card, 14, C.text); card.name:SetPoint("LEFT", card.dot, "RIGHT", 8, 0); card.name:SetPoint("RIGHT", -8, 0); card.name:SetWordWrap(false)
        card.name:SetText(info.title)
        card.state = Text(card, 11, C.muted); card.state:SetPoint("TOPLEFT", 30, -27); card.state:SetPoint("RIGHT", -8, 0); card.state:SetWordWrap(false)
        OnRefresh(function()
            local on = info.on()
            card.dot:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], on and 1 or 0.3)
            card.name:SetTextColor(unpack(on and C.text or C.muted))
            card.state:SetText(info.state())
        end)
    end

    -- tabs
    local TABS = { { "minimap", "Minimap" }, { "buttons", "Buttons" }, { "region", "Region map" }, { "general", "General" } }
    local pages, tabButtons, activeTab = {}, {}, "minimap"
    local tabY = -124
    local line = Fill(frame, { 1, 1, 1, 0.07 }, "BORDER"); line:SetHeight(1)
    line:SetPoint("TOPLEFT", PAD, tabY - 30); line:SetPoint("TOPRIGHT", -PAD, tabY - 30)
    local tx = PAD
    for _, t in ipairs(TABS) do
        local b = CreateFrame("Button", nil, frame)
        b.label = Text(b, 14, C.dim); b.label:SetPoint("LEFT"); b.label:SetText(t[2])
        b:SetSize(b.label:GetStringWidth() + 4, 30)
        b:SetPoint("TOPLEFT", tx, tabY)
        b.under = Fill(b, C.accent, "ARTWORK"); b.under:SetHeight(2); b.under:SetPoint("BOTTOMLEFT", 0, -1); b.under:SetPoint("BOTTOMRIGHT", 0, -1)
        b:SetScript("OnClick", function() activeTab = t[1]; if openList then openList:Hide() end; frame:Refresh() end)
        b:SetScript("OnEnter", function(self) if activeTab ~= t[1] then self.label:SetTextColor(unpack(C.text)) end end)
        b:SetScript("OnLeave", function(self) if activeTab ~= t[1] then self.label:SetTextColor(unpack(C.dim)) end end)
        tabButtons[t[1]] = b
        tx = tx + b:GetWidth() + 26
        local page = CreateFrame("Frame", nil, frame)
        page:SetPoint("TOPLEFT", 0, tabY - 44); page:SetPoint("BOTTOMRIGHT", 0, 60)
        pages[t[1]] = page
    end
    OnRefresh(function()
        for k, b in pairs(tabButtons) do
            local on = (k == activeTab)
            b.under:SetShown(on)
            b.label:SetTextColor(unpack(on and C.text or C.dim))
            pages[k]:SetShown(on)
        end
    end)

    local COLW = COLW0
    local LX, RX = PAD, RX0
    local ROW = 38
    local function y(i) return -22 - (i - 1) * ROW end
    -- typed values have no upper limit; the minimum keeps the minimap usable
    local function atLeast(min) return function(t) local v = num(t); return (v and v >= min) and v or nil end end
    local function bool(field) return function() return Cfg()[field] and true or false end, function(v) Set(field, v) end end

    -- Minimap
    local p = pages.minimap
    Caption(p, "Size", LX, 0)
    SliderRow(p, "Width", LX, y(1), COLW, "width", { lo = 50, hi = 2000, step = 1, fmt = fmtNum, parse = atLeast(20) })
    SliderRow(p, "Height", LX, y(2), COLW, "height", { lo = 50, hi = 1500, step = 1, fmt = fmtNum, parse = atLeast(20) })
    SliderRow(p, "Scale", LX, y(3), COLW, "scale", { lo = 0.2, hi = 5, step = 0.05, fmt = fmtNum, parse = atLeast(0.05) })
    Hint(p, "Sliders cover the usual range: type any value in the box and press Enter, there is no upper limit. Mouse wheel steps, Shift x10.", LX, y(4) + 6, COLW)
    Caption(p, "Display", RX, 0)
    SliderRow(p, "Buttons & text", RX, y(1), COLW, "buttonScale", { lo = 0.2, hi = 4, step = 0.05, fmt = fmtNum, parse = atLeast(0.05) })
    Label(p, "Native zoom", RX, y(2) - 3)
    Segmented(p, { { 0, "0" }, { 1, "1" }, { 2, "2" }, { 3, "3" }, { 4, "4" }, { 5, "5" } }, RX + 120, y(2), COLW - 120,
        function() return Val("zoom") end, function(v) Set("zoom", v) end)
    Caption(p, "Position", RX, y(3) + 4)
    Label(p, "Placed by", RX, y(4) + 10 - 3)
    Segmented(p, { { "free", "Free Minimap" }, { "editmode", "Edit Mode" } }, RX + 120, y(4) + 10, COLW - 120,
        function() return Cfg().posMode == "free" and "free" or "editmode" end,
        function(v) if ns.SetPositionMode then ns.SetPositionMode(v) end end)
    local function posSet(field) return function(v)
        local pc = Cfg()
        if pc.posMode ~= "free" and ns.SetPositionMode then ns.SetPositionMode("free") end
        pc[field] = v
        if ns.ApplyPosition then ns.ApplyPosition() end
        if frame then frame:Refresh() end
    end end
    local function anyNumber(t) return num(t) end
    SliderRow(p, "X", RX, y(5) + 10, COLW, nil, { lo = -2000, hi = 2000, step = 1, fmt = fmtNum, parse = anyNumber,
        get = function() return tonumber(Cfg().posX) or 0 end, set = posSet("posX") })
    SliderRow(p, "Y", RX, y(6) + 10, COLW, nil, { lo = -1200, hi = 1200, step = 1, fmt = fmtNum, parse = anyNumber,
        get = function() return tonumber(Cfg().posY) or 0 end, set = posSet("posY") })
    local unlock = Button(p, "Unlock", 110, true, function() if ns.SetUnlocked then ns.SetUnlocked(not ns.IsUnlocked()) end end)
    unlock:SetPoint("TOPLEFT", RX, y(7) + 10)
    Flow(unlock, "TOPLEFT", RX, y(7) + 10)
    local move = Button(p, "Edit Mode", 110, false, function()
        if EditModeManagerFrame then
            if ShowUIPanel then ShowUIPanel(EditModeManagerFrame) else EditModeManagerFrame:Show() end
        end
    end)
    move:SetPoint("LEFT", unlock, "RIGHT", 6, 0)
    local posHint = Hint(p, "", RX, y(8) + 2, COLW)
    OnRefresh(function()
        local free = Cfg().posMode == "free"
        unlock.label:SetText(ns.IsUnlocked and ns.IsUnlocked() and "Lock" or "Unlock")
        local pt = Cfg().posPoint
        posHint:SetText(free and ("Drag the orange frame, or type X / Y (pixels from the screen's " .. (pt and pt:lower() or "nearest corner") .. "). Not during a fight.")
            or "Edit Mode places the minimap. \"Unlock\" switches to Free Minimap's own position.")
    end)

    -- Buttons: every element around the map, placed one by one in the window
    p = pages.buttons
    local selKey = "zone"
    local function sel() return ns.ButtonCfg(selKey) end
    local function setSel(k, v)
        local c = sel(); if not c then return end
        c[k] = v
        if ns.PlaceButtons then ns.PlaceButtons() end
        if frame then frame:Refresh() end
    end
    local SHOW = { always = "Always", hover = "Mouseover", hide = "Hidden" }
    local POINTS = {
        { key = "TOPLEFT", label = "Top left" }, { key = "TOP", label = "Top" }, { key = "TOPRIGHT", label = "Top right" },
        { key = "LEFT", label = "Left" }, { key = "CENTER", label = "Centre" }, { key = "RIGHT", label = "Right" },
        { key = "BOTTOMLEFT", label = "Bottom left" }, { key = "BOTTOM", label = "Bottom" }, { key = "BOTTOMRIGHT", label = "Bottom right" },
    }
    local pointLabel = {}
    for _, it in ipairs(POINTS) do pointLabel[it.key] = it.label end
    Caption(p, "Elements", LX, 0)
    local RH = 24
    for i, el in ipairs(ns.BUTTON_ELEMENTS or {}) do
        local r = CreateFrame("Button", nil, p)
        local ry = -18 - (i - 1) * RH
        r:SetSize(COLW, RH - 2)
        r:SetPoint("TOPLEFT", LX, ry)
        Flow(r, "TOPLEFT", LX, ry, COLW)
        r.bg = Fill(r, C.panel); r.bg:SetAllPoints()
        r.sel = Fill(r, C.accent, "ARTWORK"); r.sel:SetWidth(3); r.sel:SetPoint("TOPLEFT"); r.sel:SetPoint("BOTTOMLEFT")
        r.name = Text(r, 13, C.text); r.name:SetPoint("LEFT", 10, 0); r.name:SetText(el.label)
        r.state = Text(r, 11, C.muted); r.state:SetPoint("RIGHT", -8, 0); r.state:SetJustifyH("RIGHT"); r.state:SetWordWrap(false)
        r:SetScript("OnEnter", function(self) self.bg:SetVertexColor(unpack(C.hover)) end)
        r:SetScript("OnLeave", function(self) self.bg:SetVertexColor(unpack(selKey == el.key and C.control or C.panel)) end)
        r:SetScript("OnClick", function() selKey = el.key; if openList then openList:Hide() end; frame:Refresh() end)
        OnRefresh(function()
            local on = (selKey == el.key)
            r.sel:SetShown(on)
            r.bg:SetVertexColor(unpack(on and C.control or C.panel))
            local present = ns.ButtonFrame(el) ~= nil
            local c = ns.ButtonCfg(el.key)
            r.name:SetTextColor(unpack(present and C.text or C.muted))
            if not present then
                r.state:SetText("not in this game")
            elseif c then
                r.state:SetText(SHOW[c.show] .. (c.show ~= "hide" and ("  ·  " .. (pointLabel[c.point] or c.point)) or ""))
            end
        end)
    end
    local selTitle = Caption(p, "", RX, 0)
    OnRefresh(function()
        for _, el in ipairs(ns.BUTTON_ELEMENTS or {}) do if el.key == selKey then selTitle:SetText(el.label:upper()) end end
    end)
    Label(p, "Show", RX, y(1) - 3)
    Segmented(p, { { "always", "Always" }, { "hover", "Mouseover" }, { "hide", "Hidden" } }, RX + 120, y(1), COLW - 120,
        function() return sel() and sel().show end, function(v) setSel("show", v) end)
    Dropdown(p, "Position", RX, y(2), COLW, function() return POINTS end,
        function() return sel() and sel().point end, function(v) setSel("point", v) end)
    local function anyNum(t) return num(t) end
    SliderRow(p, "X offset", RX, y(3), COLW, nil, { lo = -200, hi = 200, step = 1, fmt = fmtNum, parse = anyNum,
        get = function() return sel() and sel().x or 0 end, set = function(v) setSel("x", v) end })
    SliderRow(p, "Y offset", RX, y(4), COLW, nil, { lo = -200, hi = 200, step = 1, fmt = fmtNum, parse = anyNum,
        get = function() return sel() and sel().y or 0 end, set = function(v) setSel("y", v) end })
    SliderRow(p, "Size", RX, y(5), COLW, nil, { lo = 0.3, hi = 3, step = 0.05, fmt = fmtNum, parse = atLeast(0.05),
        get = function() return sel() and sel().scale or 1 end, set = function(v) setSel("scale", v) end })
    Hint(p, "Offsets in pixels from the chosen point of the minimap window (Y up = positive). Mouseover: shown while the mouse is on the minimap. \"Buttons & text\" (Minimap tab) multiplies every size.", RX, y(6) + 8, COLW)
    local bResetOne = Button(p, "Reset this one", 120, false, function() if ns.ResetButtons then ns.ResetButtons(selKey) end; frame:Refresh() end)
    bResetOne:SetPoint("TOPLEFT", RX, y(7) - 6)
    Flow(bResetOne, "TOPLEFT", RX, y(7) - 6)
    local bResetAll = Button(p, "Reset all", 96, false, function() if ns.ResetButtons then ns.ResetButtons() end; frame:Refresh() end)
    bResetAll:SetPoint("LEFT", bResetOne, "RIGHT", 6, 0)

    -- Region map
    p = pages.region
    local regionOn = function() return Cfg().regionEnabled and true or false end
    Caption(p, "Region map", LX, 0)
    SwitchRow(p, "Show the region map", LX, y(1), COLW,
        function() return Cfg().regionEnabled and true or false end,
        function(v) if ns.SetRegion then ns.SetRegion(v) end; if frame then frame:Refresh() end end)
    Label(p, "Background", LX, y(2) - 3)
    Segmented(p, { { "tiles", "Terrain tiles" }, { "art", "Map art" } }, LX + 120, y(2), COLW - 120,
        function() return Cfg().regionSource == "art" and "art" or "tiles" end, function(v) Set("regionSource", v) end)
    SliderRow(p, "Tile scale", LX, y(3), COLW, "tileScale", { lo = 0.1, hi = 4, step = 0.05, fmt = fmtNum, parse = atLeast(0.02) })
    SliderRow(p, "Map art zoom", LX, y(4), COLW, "regionZoom", { lo = 0.1, hi = 6, step = 0.05, fmt = fmtNum, parse = atLeast(0.02) })
    Hint(p, "Draws the terrain around you in the whole rectangle, centred on you and north-up (minimap rotation is switched off while it is on). Terrain tiles are the game's own minimap pictures; map art is the world-map illustration, used where no tile exists. Tile scale = screen pixels per yard. Mouse wheel on the map zooms it.", LX, y(5) + 6, COLW)
    SwitchRow(p, "Icons of other addons", LX, y(8), COLW,
        function() return Cfg().regionPins ~= false end, function(v) Set("regionPins", v and true or false) end)
    Hint(p, "Questie, RestedXP, TomTom, gatherers… also show their icons on the region map, beyond the real minimap, with their tooltips (RestedXP: the next steps too). Icons that point the way float on the edge of the region map.", LX, y(9) + 6, COLW)
    Caption(p, "Real minimap on top", RX, 0)
    SwitchRow(p, "Overlay the real minimap", RX, y(1), COLW, bool("regionOverlay"))
    SwitchRow(p, "Round (disc)", RX, y(2), COLW, bool("overlayRound"))
    SliderRow(p, "Calibration", RX, y(3), COLW, "overlayCal", { lo = 0.3, hi = 3, step = 0.01, fmt = fmtNum, parse = atLeast(0.05) })
    local AXES = { { key = 0, label = "Automatic" } }
    for i = 1, 8 do AXES[#AXES + 1] = { key = i, label = "Convention " .. i } end
    Dropdown(p, "Tile axes", RX, y(4), COLW, function() return AXES end,
        function() return tonumber(Cfg().axisOverride) or 0 end, function(v) Set("axisOverride", v) end)
    Hint(p, "With the overlay, the real minimap (icons, arrow, pings) sits on the region map at the same scale. Calibration 1 = exact; tweak it if the two do not line up. Change the tile axes only if the terrain looks misplaced.", RX, y(5) + 6, COLW)
    SwitchRow(p, "Quests of the log", RX, y(8), COLW,
        function() return Cfg().regionQuests ~= false end, function(v) Set("regionQuests", v and true or false) end)
    Hint(p, "Your quests and their areas on the whole region map, as on the world map (the real minimap shows only those within its own radius). Click a quest to track it.", RX, y(9) + 6, COLW)
    OnRefresh(function() end)

    -- General
    p = pages.general
    Caption(p, "General", LX, 0)
    SwitchRow(p, "Minimap button", LX, y(1), COLW,
        function() return ns.IsMinimapShown == nil or ns.IsMinimapShown() end,
        function(v) if ns.SetMinimapShown then ns.SetMinimapShown(v) end end)
    Hint(p, "With Free Hub installed, one button opens all the Free addons and this one stays hidden.", LX, y(2) + 6, COLW)
    Caption(p, "Commands", LX, y(3))
    Hint(p, "/fmm  options\n/fmm region  region map on / off\n/fmm axes 0-8  tile axes (0 = automatic)\n/fmm reset  back to defaults", LX, y(4), COLW)
    Hint(p, "Based on DejaMinimap, with permission.", LX, y(8), COLW)

    -- Profiles (like ElvUI: each character picks one; export / import as text)
    local PM = function() return ns.profiles end
    local function profileItems(exceptCurrent)
        local out = {}
        local m = PM()
        if not m then return out end
        for _, name in ipairs(m:List()) do
            if not (exceptCurrent and name == m:Current()) then
                local n = m:Users(name)
                out[#out + 1] = { key = name, label = name .. (n > 0 and ("  (" .. n .. " char.)") or "") }
            end
        end
        return out
    end
    Caption(p, "Profile", RX, 0)
    Dropdown(p, "This character", RX, y(1), COLW, function() return profileItems(false) end,
        function() return PM() and PM():Current() end, function(v) if PM() then PM():Set(v); frame:Refresh() end end)
    Label(p, "New profile", RX, y(2) - 5)
    local newBox = InputBox(p, COLW - 120 - 2 * 76)
    newBox:SetPoint("TOPLEFT", RX + 120, y(2))
    Flow(newBox, "TOPLEFT", RX + 120, y(2), COLW - 120 - 2 * 76)
    local function newName() local t = (newBox:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", ""); return t ~= "" and t or nil end
    local bNew = Button(p, "Empty", 72, false, function()
        local n = newName(); if not n or not PM() then return end
        newBox:SetText(""); newBox:ClearFocus(); PM():Set(n); frame:Refresh()
    end)
    bNew:SetPoint("LEFT", newBox, "RIGHT", 4, 0)
    local bDup = Button(p, "Copy", 72, true, function()
        local n = newName(); if not n or not PM() then return end
        newBox:SetText(""); newBox:ClearFocus(); PM():Set(n, PM():Current()); frame:Refresh()
    end)
    bDup:SetPoint("LEFT", bNew, "RIGHT", 4, 0)
    newBox:SetScript("OnEnterPressed", function() bDup:Click() end)
    newBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    Dropdown(p, "Copy settings", RX, y(3), COLW, function() return profileItems(true) end,
        function() return "from another profile..." end, function(v) if PM() then PM():CopyFrom(v); frame:Refresh() end end)
    Dropdown(p, "Delete", RX, y(4), COLW, function() return profileItems(true) end,
        function() return "choose a profile..." end, function(v) if PM() then PM():Delete(v); frame:Refresh() end end)
    local LFP = LibStub and LibStub("LibFreeProfiles-1.0", true)
    Label(p, "Share", RX, y(5) - 5)
    local bExp = Button(p, "Export", 96, false, function()
        if LFP and PM() then LFP:ShowExport("Export Free Minimap profile: " .. PM():Current(), PM():Export()) end
    end)
    bExp:SetPoint("TOPLEFT", RX + 120, y(5))
    Flow(bExp, "TOPLEFT", RX + 120, y(5))
    local bImp = Button(p, "Import", 96, false, function()
        if LFP and PM() then
            LFP:ShowImport("Import a Free Minimap profile", "Imported", function(text, name)
                local ok, res = PM():Import(text, name)
                if ok then frame:Refresh() end
                return ok, res
            end)
        end
    end)
    bImp:SetPoint("LEFT", bExp, "RIGHT", 6, 0)
    Hint(p, "Each character remembers its profile (at first, one named after the character). \"Copy\" starts the new profile from the current one. Export gives a text to paste on another character or account.", RX, y(6) + 4, COLW)

    -- footer
    local footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT"); footer:SetPoint("BOTTOMRIGHT"); footer:SetHeight(56)
    local fbg = Fill(footer, C.panel, "BACKGROUND", -5); fbg:SetAllPoints()
    local fl = Fill(footer, { 1, 1, 1, 0.06 }, "BORDER"); fl:SetHeight(1); fl:SetPoint("TOPLEFT"); fl:SetPoint("TOPRIGHT")
    local reset
    reset = Button(footer, "Reset to defaults", 150, false, function()
        -- a second click within 4 seconds confirms
        local now = GetTime and GetTime() or 0
        if reset.armed and now - reset.armed < 4 then
            reset.armed = nil; reset.label:SetText("Reset to defaults")
            ns.ResetDefaults()
        else
            reset.armed = now; reset.label:SetText("Click again")
        end
    end)
    reset:SetPoint("LEFT", PAD, 0)
    local region = Button(footer, "Region map", 120, true, function() if ns.SetRegion then ns.SetRegion(not Cfg().regionEnabled) end end)
    region:SetPoint("RIGHT", -PAD, 0)
    OnRefresh(function()
        region.label:SetText(Cfg().regionEnabled and "Region map: on" or "Region map: off")
        reset.armed = nil; reset.label:SetText("Reset to defaults")
    end)

    function frame:Refresh()
        if not ns.pc then return end
        for _, fn in ipairs(refreshers) do fn() end
    end
    frame:SetScript("OnShow", function(self) self:Refresh() end)
    frame:SetScript("OnSizeChanged", function(_, w) Reflow(w) end)
    frame:SetScript("OnHide", function()
        if openList then openList:Hide(); openList = nil end
        ns.lastOptionsHide = GetTime and GetTime() or 0
        if C_Timer then C_Timer.After(0, ns.ReopenForEditMode) end
    end)
    frame:Hide()
end

-- ------------------------------------------------------------ Free Hub integration
-- When Free Hub is installed, these options open inside its window (sidebar on the left).
local function Embed(parent)
    if not ns.pc then return end
    if not frame then Build() end
    frame.fhEmbedded = true
    frame:SetParent(parent)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)   -- fills the hub; the layout follows its size
    frame:SetFrameStrata(parent:GetFrameStrata())
    frame:SetFrameLevel(parent:GetFrameLevel() + 1)
    frame.fhShadow:Hide()
    frame.fhClose:Hide()
    frame.fhMover = FreeHub:GetFrame()
    frame.fhNaturalW, frame.fhNaturalH = W, H
    frame:Show()
    return frame
end
local function Unembed()
    if not frame or not frame.fhEmbedded then return end
    frame.fhEmbedded = nil
    frame:Hide()
    frame:SetParent(UIParent)
    frame:ClearAllPoints()
    frame:SetSize(W, H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame.fhShadow:Show()
    frame.fhClose:Show()
    frame.fhMover = nil
end
if FreeHub and FreeHub.Register and not ns.conflict then
    FreeHub:Register("FreeMinimap", {
        embed = Embed,
        unembed = Unembed,
        minW = W, minH = H,   -- natural size of these options; the hub never gets smaller than this
        minimap = function(show) if ns.ApplyMinimapVisibility then ns.ApplyMinimapVisibility(show) end end,
    })
end

-- Edit Mode closes the windows Escape closes (ours and Free Hub) as it opens: when it does, open them again,
-- so the size, buttons and position can be set while placing the minimap.
local editShownAt = -10
function ns.ReopenForEditMode()
    if not (frame and EditModeManagerFrame and EditModeManagerFrame:IsShown()) then return end
    if frame:IsShown() or not ns.lastOptionsHide then return end
    if math.abs(ns.lastOptionsHide - editShownAt) > 0.5 then return end
    ns.lastOptionsHide = nil
    if FreeHub and FreeHub.Open and FreeHub:IsRegistered("FreeMinimap") then FreeHub:Open("FreeMinimap") else frame:Show() end
end
if EditModeManagerFrame and EditModeManagerFrame.HookScript then
    EditModeManagerFrame:HookScript("OnShow", function()
        editShownAt = GetTime and GetTime() or 0
        if C_Timer then C_Timer.After(0, ns.ReopenForEditMode) end
    end)
end

function ns.ToggleOptions()
    if ns.conflict then
        print("|cffff8a3dFree Minimap|r is paused: disable the old DejaMinimap in the AddOns list, then reload.")
        return
    end
    if not ns.pc then return end
    if FreeHub and FreeHub.Toggle and FreeHub:IsRegistered("FreeMinimap") then FreeHub:Toggle("FreeMinimap"); return end
    if not frame then Build() end
    frame:SetShown(not frame:IsShown())
end
ns.ToggleConfig = ns.ToggleOptions

function ns.RefreshOptions()
    if frame and frame:IsShown() then frame:Refresh() end
end
ns.OnChanged = ns.RefreshOptions

-- ------------------------------------------------------------ slash commands
SLASH_FREEMINIMAP1 = "/fmm"
SLASH_FREEMINIMAP2 = "/freeminimap"
SlashCmdList["FREEMINIMAP"] = function(msg)
    msg = strlower(strtrim(msg or ""))
    if ns.conflict then ns.ToggleOptions(); return end
    local pc = ns.pc
    if not pc then return end
    if msg == "textest" then
        if ns.TextureTest then ns.TextureTest() end
        return
    end
    if msg == "pins" then
        if ns.PinsDebug then ns.PinsDebug() end
        return
    end
    --{ /fmm edge <0-4> [width]: trial looks for the quest areas' outline (0 = the world map's edge) }--
    local style, width = msg:match("^edge%s*(%d*)%s*([%d%.]*)")
    if style then
        if style ~= "" then pc.edgeStyle = tonumber(style) end
        if width ~= "" then pc.edgeScalar = tonumber(width) end
        if ns.QuestsRestyle then ns.QuestsRestyle() end
        print(string.format("|cffff8a3dFree Minimap|r quest outline: style %d, width %.2f", tonumber(pc.edgeStyle) or 7, tonumber(pc.edgeScalar) or 0.35))
        return
    end
    if msg == "region" or msg == "r" then
        ns.SetRegion(not pc.regionEnabled)
    elseif msg:sub(1, 4) == "axes" then
        -- force one of the 8 world-axis conventions if the tiles look misplaced (0 = auto)
        local n = tonumber(msg:match("%d+")) or (((tonumber(pc.axisOverride) or 0) + 1) % 9)
        pc.axisOverride = n
        print("|cffff8a3dFree Minimap|r tile axes: " .. (n == 0 and "automatic" or n))
        ns.RefreshOptions()
    elseif msg == "reset" then
        ns.ResetDefaults()
    elseif msg == "help" or msg == "?" then
        print("|cffff8a3dFree Minimap|r: /fmm = options, /fmm region = region map on/off, /fmm axes [0-8] = tile axes, /fmm reset = defaults")
    else
        ns.ToggleOptions()
    end
end
