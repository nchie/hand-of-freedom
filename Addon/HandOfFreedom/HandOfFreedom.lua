-- Hand of Freedom marker.
--
-- Draws three small squares at the top centre of the game: magenta, a state colour, yellow. The
-- Hand of Freedom app reads them to learn what is under the mouse, so a two-finger swipe can scroll a
-- window instead of turning. They are anchored to the world (WorldFrame), which the game draws to the
-- top edge, so on a MacBook with the game filling the screen they sit hidden behind the notch; the
-- interface (UIParent) stops below it.
--
--   green  the 3D world
--   blue   a window that takes the mouse wheel (chat, lists, the minimap)
--   red    any other window
--
-- The app matches these exact colours and this order, so change both sides together.

local CELL = 4                 -- physical pixels per square

local COLORS = {
    world = { 0, 1, 0 },
    scroll = { 0, 0, 1 },
    window = { 1, 0, 0 },
}

local marker = CreateFrame("Frame", "HandOfFreedomMarker", UIParent)
marker:SetFrameStrata("TOOLTIP")
marker:SetFrameLevel(100)
marker:EnableMouse(false)

local cells = {}
for i = 1, 3 do
    cells[i] = marker:CreateTexture(nil, "OVERLAY")
end
cells[1]:SetColorTexture(1, 0, 1)
cells[3]:SetColorTexture(1, 1, 0)

-- One physical pixel in the marker's own units.
local function physicalPixel()
    local height = GetPhysicalScreenSize and select(2, GetPhysicalScreenSize())
    if not height or height <= 0 then return 1 end
    return 768 / height / marker:GetEffectiveScale()
end

local function layout()
    local size = CELL * physicalPixel()
    local top = (WorldFrame and WorldFrame:GetTop()) and WorldFrame or UIParent
    marker:SetSize(size * 3, size)
    marker:ClearAllPoints()
    marker:SetPoint("TOP", top, "TOP", 0, 0)
    for i, t in ipairs(cells) do
        t:ClearAllPoints()
        t:SetSize(size, size)
        t:SetPoint("TOPLEFT", marker, "TOPLEFT", (i - 1) * size, 0)
    end
end

local function mouseFocus()
    if GetMouseFoci then return GetMouseFoci()[1] end
    if GetMouseFocus then return GetMouseFocus() end
    return nil
end

local function takesWheel(frame)
    while frame and frame ~= UIParent do
        if frame.IsForbidden and frame:IsForbidden() then return false end
        if frame.IsMouseWheelEnabled and frame:IsMouseWheelEnabled() then return true end
        frame = frame.GetParent and frame:GetParent() or nil
    end
    return false
end

local state
marker:SetScript("OnUpdate", function()
    local focus = mouseFocus()
    local now
    if focus == nil or focus == WorldFrame then
        now = "world"
    elseif takesWheel(focus) then
        now = "scroll"
    else
        now = "window"
    end
    if now ~= state then
        state = now
        cells[2]:SetColorTexture(unpack(COLORS[now]))
    end
end)

marker:RegisterEvent("PLAYER_LOGIN")
marker:RegisterEvent("UI_SCALE_CHANGED")
marker:RegisterEvent("DISPLAY_SIZE_CHANGED")
marker:SetScript("OnEvent", layout)
layout()
