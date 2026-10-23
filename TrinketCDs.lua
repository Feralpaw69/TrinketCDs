local ADDON_NAME = "TrinketCDs"
local ADDON = CreateFrame("Frame")
_G[ADDON_NAME] = ADDON

local DB = _G.TrinketCDsDB
local SETTINGS = DB.DEFAULT_SETTINGS
local SWITCHES = SETTINGS.SWITCHES
ADDON.FRAMES = {}
ADDON.SETTINGS = SETTINGS
ADDON.ITEM_GROUP = DB.ITEM_GROUP
ADDON.SORTED_ITEMS = {13, 14, 11, 15, 16, 10, 8, 6}
ADDON.TRINKET_SWAP_ID = 10725

local ITEMS_CACHE = {}
local PRECISION_FORMAT = {[0] = "%d", [1] = "%.1f"}
local ADDON_PROFILE = format("%sProfile", ADDON_NAME)
local ADDON_NAME_COLOR = format("|cFFFFFF00[%s]|r: ", ADDON_NAME)
local ADDON_MEDIA = format("Interface\\Addons\\%s\\Media\\%%s", ADDON_NAME)
local BORDER_TEXTURE = ADDON_MEDIA:format("BigBorder.blp")
local DEFAULT_FONT_FILE = "Emblem.ttf"
local DEFAULT_FONT = ADDON_MEDIA:format(DEFAULT_FONT_FILE)
ADDON.DEFAULT_FONT = DEFAULT_FONT
SWITCHES.FONT_FILE = DEFAULT_FONT

local GetTime = GetTime
local UnitBuff = UnitBuff
local UnitGUID = UnitGUID
local InCombatLockdown = InCombatLockdown
local IsModifierKeyDown = IsModifierKeyDown
local UnitAffectingCombat = UnitAffectingCombat
local GetInventoryItemCooldown = GetInventoryItemCooldown
local GetContainerNumFreeSlots = GetContainerNumFreeSlots or (C_Container and C_Container.GetContainerNumFreeSlots)

ADDON.DRAG_UNLOCK = false

local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

local GLOW_STYLE_BUTTON = 1
local GLOW_STYLE_PIXEL = 2
local GLOW_STYLE_PROC = 3
local GLOW_FREQUENCY = 0.25
local GLOW_FRAMELEVEL = 8
local PIXEL_KEY = "TCD"
local PIXEL_LINES = 8
local PIXEL_LENGTH = 10
local PIXEL_THICKNESS = 1

local TEXT_OVERLAY_FRAMELEVEL = 30

local function ButtonGlow_Update(r)
    local f = r and r._ButtonGlow
    if not f then return end

    local width, height = r:GetSize()
    f:SetFrameLevel(r:GetFrameLevel() + GLOW_FRAMELEVEL)
    f:SetSize(width * 1.4, height * 1.4)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", r, "TOPLEFT", -width * 0.2, height * 0.2)
    f:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", width * 0.2, -height * 0.2)

    if f.ants then
        f.ants:SetSize(width * 1.4 * 0.85, height * 1.4 * 0.85)
    end

    f.throttle = (GLOW_FREQUENCY and GLOW_FREQUENCY > 0) and (0.25 / GLOW_FREQUENCY * 0.01) or 0.01
end

local function StopGlow(self)
    if not (LCG and self and self._tcd_glow_active) then return end

    local style = self._tcd_glow_style_active
    if style == GLOW_STYLE_PIXEL then
        if LCG.PixelGlow_Stop then
            LCG.PixelGlow_Stop(self, PIXEL_KEY)
        end
    elseif style == GLOW_STYLE_PROC then
        if LCG.ProcGlow_Stop then
            LCG.ProcGlow_Stop(self, PIXEL_KEY)
        end
    else
        if LCG.ButtonGlow_Stop then
            LCG.ButtonGlow_Stop(self)
        end
    end

    self._tcd_glow_active = false
    self._tcd_glow_style_active = nil
end

local function StartGlow(self)
    if not (LCG and self and self.item and self.item.applied
        and SWITCHES.SHOW_PROC_GLOW ~= 0
        and (self.settings.PROC_GLOW == nil or self.settings.PROC_GLOW ~= 0)) then
        return
    end

    local style = SWITCHES.PROC_GLOW_STYLE or GLOW_STYLE_BUTTON

    if style == GLOW_STYLE_PIXEL then
        if LCG.PixelGlow_Start then
            LCG.PixelGlow_Start(self, nil, PIXEL_LINES, GLOW_FREQUENCY, PIXEL_LENGTH, PIXEL_THICKNESS, 0, 0, nil, PIXEL_KEY, GLOW_FRAMELEVEL)
        end
    elseif style == GLOW_STYLE_PROC then
        if LCG.ProcGlow_Start then
            LCG.ProcGlow_Start(self, {
                color = nil,
                startAnim = true,
                duration = 1,
                key = PIXEL_KEY,
                frameLevel = GLOW_FRAMELEVEL,
                xOffset = 0,
                yOffset = 0,
            })
        end
    else
        if LCG.ButtonGlow_Start then
            LCG.ButtonGlow_Start(self, nil, GLOW_FREQUENCY, GLOW_FRAMELEVEL)
        end
    end

    self._tcd_glow_active = true
    self._tcd_glow_style_active = style
end

local function ShowProcVisuals(self, procSpellID)
    local wantGlow = (SWITCHES.SHOW_PROC_GLOW ~= 0)
        and (self.item and self.item.applied)
        and (self.settings.PROC_GLOW == nil or self.settings.PROC_GLOW ~= 0)
    local style = SWITCHES.PROC_GLOW_STYLE or GLOW_STYLE_BUTTON

    if LCG and wantGlow then
        if (not self._tcd_glow_active) or (self._tcd_glow_style_active ~= style) then
            StopGlow(self)
            StartGlow(self)
        else
            if style == GLOW_STYLE_BUTTON then
                ButtonGlow_Update(self)
            end
        end
    else
        StopGlow(self)
    end

    if SWITCHES.SHOW_PROC_ICON ~= 0 and procSpellID then
        local procIcon = select(3, GetSpellInfo(procSpellID))
        if procIcon then
            self.texture:SetTexture(procIcon)
            return
        end
    end

    if self.item and self.item.texture then
        self.texture:SetTexture(self.item.texture)
    end
end

local function HideProcVisuals(self)
    StopGlow(self)
    if self.item and self.item.texture then
        self.texture:SetTexture(self.item.texture)
    end
end

local function new_item(item_ID)
    if not item_ID then return end
    local _, _, item_quality, item_level, _, _, _, _, _, item_texture = GetItemInfo(item_ID)
    if not item_quality then return end

    local item = {
        ID = item_ID,
        ilvl = item_level,
        quality = item_quality,
        texture = item_texture,
    }
    ITEMS_CACHE[item_ID] = item
    return item
end

local function get_buff_IDs(item_ID)
    local spell_IDs = DB.TRINKET_PROC_MULTIBUFF[item_ID]
    if not spell_IDs then return end

    local buff_IDs = {}
    for _, spell_ID in pairs(spell_IDs) do
        buff_IDs[spell_ID] = true
    end
    return buff_IDs
end

local function new_trinket(item_ID)
    local item = new_item(item_ID)
    if not item then return end

    local buff_ID = DB.TRINKET_PROC_ID[item_ID]
    local buff_IDs = get_buff_IDs(item_ID)
    item.spell_ID = buff_ID
    item.spell_IDs = buff_IDs
    item.stacks_ID = DB.TRINKET_PROC_STACKS[buff_ID]
    if buff_ID or buff_IDs then
        item.proc_in_DB = true
        item.CD = DB.TRINKET_PROC_CD[item_ID] or 45
    end
    return item
end

local function new_not_trinket(item_ID, buff_ID)
    local item = new_item(item_ID)
    if not item then return end

    item.spell_ID = buff_ID
    item.proc_in_DB = true
    item.CD = DB.ENCHANT_PROC_CD[buff_ID] or 60
    return item
end

local function check_other_ring(self)
    local slot_ID = self.slot_ID == 11 and 12 or 11
    local item_ID = GetInventoryItemID("player", slot_ID)
    local buff_ID = DB.ASHEN_RINGS[item_ID]
    if buff_ID then
        self.slot_ID = slot_ID
        return item_ID, buff_ID
    end
end

local function get_item(self)
    local item_ID = GetInventoryItemID("player", self.slot_ID)
    local item = ITEMS_CACHE[item_ID]

    if self.item_proc_type == "enchant" then
        local item_link = GetInventoryItemLink("player", self.slot_ID)
        if not item_link then return end

        local ench_ID = item_link:match("%d:(%d+)")
        local buff_ID = DB.ENCHANTS[ench_ID]
        if item and item.spell_ID == buff_ID then return item end

        if not buff_ID then
            local _, _, has_cd = GetInventoryItemCooldown("player", self.slot_ID)
            if has_cd == 0 then return end
        end

        return new_not_trinket(item_ID, buff_ID)

    elseif item then
        return item

    elseif self.item_proc_type == "trinket" then
        return new_trinket(item_ID)

    elseif self.item_proc_type == "ring" then
        local buff_ID = DB.ASHEN_RINGS[item_ID]
        if not buff_ID then
            item_ID, buff_ID = check_other_ring(self)
        end
        return buff_ID and new_not_trinket(item_ID, buff_ID)
    end
end

local function ResetFrame(self)
    HideProcVisuals(self)
    self.cooldown_current_end = nil
    self.stacks_text:SetText()
    self.texture:SetDesaturated(false)
    self.cooldown:SetReverse(false)
    self.cooldown:SetCooldown(0, 0)
    self:ToggleVisibility()
end

local function ApplyItemCD(self, dur)
    if self.item.applied then return end

    dur = dur or self.item.CD
    self.stacks_text:SetText()
    self.texture:SetDesaturated(true)
    self.cooldown:SetReverse(false)
    self.cooldown:SetCooldown(self.item.cd_start, dur)
    self.cooldown_current_end = self.item.cd_start + dur
    self:ToggleVisibility()
end

local function ItemUsedCheck(self)
    if not self.is_usable then return end

    local cdStart, cdDur = GetInventoryItemCooldown("player", self.slot_ID)
    if cdDur == 0 then return end

    if cdDur > 30 then
        self.item.CD = cdDur
        if self.item.ID == ADDON.TRINKET_SWAP_ID and self.item_ID_before_swap and GetTime() - cdStart < 5 then
            EquipItemByName(self.item_ID_before_swap, self.slot_ID)
        end
    end

    self.item.cd_start = cdStart
    self.item.cd_end = cdStart + cdDur
    self:ApplyItemCD(cdDur)
end

local GetPlayerBuff = (function()
    local function retail(buff_index)
        local _, _, stacks, _, duration, expirationTime, _, _, _, buffSpellID = UnitBuff("player", buff_index)
        return stacks, duration, expirationTime, buffSpellID
    end
    local function old(buff_index)
        local _, _, _, stacks, _, duration, expirationTime, _, _, _, buffSpellID = UnitBuff("player", buff_index)
        return stacks, duration, expirationTime, buffSpellID
    end
    local _, _, _, tocVersion = GetBuildInfo()
    local isRetail = tocVersion and tocVersion > 40000
    return isRetail and retail or old
end)()

local function player_buff(spell_ID)
    local buff_index = 1
    repeat
        local stacks, duration, expirationTime, buffSpellID = GetPlayerBuff(buff_index)
        if buffSpellID == spell_ID then
            return stacks, duration, expirationTime, buffSpellID
        end
        buff_index = buff_index + 1
    until not buffSpellID
end

local function player_buff_multi(spell_IDs)
    local buff_index = 1
    repeat
        local stacks, duration, expirationTime, buffSpellID = GetPlayerBuff(buff_index)
        if spell_IDs[buffSpellID] then
            return stacks, duration, expirationTime, buffSpellID
        end
        buff_index = buff_index + 1
    until not buffSpellID
end

local function player_buff_stacks(spell_ID, stacks_ID)
    local _stacks, _duration, _expiration, _main_stacks
    local buff_index = 1
    repeat
        local stacks, duration, expirationTime, buffSpellID = GetPlayerBuff(buff_index)
        if buffSpellID == spell_ID then
            _duration = duration
            _expiration = expirationTime
            _main_stacks = stacks
            if _stacks then
                return _stacks, _duration, _expiration
            end
        elseif buffSpellID == stacks_ID then
            _stacks = stacks
            if _duration then
                return _stacks, _duration, _expiration
            end
        end
        buff_index = buff_index + 1
    until not buffSpellID

    if _duration then
        return _main_stacks or 0, _duration, _expiration
    end
end

local function check_proc(item)
    if item.stacks_ID then
        return player_buff_stacks(item.spell_ID, item.stacks_ID)
    elseif item.spell_ID then
        return player_buff(item.spell_ID)
    elseif item.spell_IDs then
        return player_buff_multi(item.spell_IDs)
    end
end

local function ItemBuffApplied(self, duration, expirationTime, procSpellID)
    local cd_start = expirationTime - duration
    local item = self.item
    item.applied = true
    if not item.cd_start or cd_start > item.cd_start then
        item.cd_start = cd_start
        item.buff_end = expirationTime
        item.cd_end = self.no_swap_cd and expirationTime or cd_start + item.CD
    end
    self.texture:SetDesaturated(false)
    self.cooldown:SetReverse(true)
    self.cooldown:SetCooldown(cd_start, duration)
    self.cooldown_current_end = expirationTime
    self.last_proc_spell_id = procSpellID
    self:ToggleVisibility()
    ShowProcVisuals(self, procSpellID)
end

local function ItemBuffFaded(self)
    self.item.applied = false
    HideProcVisuals(self)
    if self.no_swap_cd then
        self:ResetFrame()
    elseif self.is_usable then
        self:ItemUsedCheck()
    else
        self:ApplyItemCD()
    end
end

local function AuraCheck(self, swapped)
    if not self.item then return end

    local stacks, duration, expiration, procSpellID = check_proc(self.item)
    if duration == 0 then
        self.item.applied = true
        self.stacks_text:SetText(stacks)
        self.last_proc_spell_id = procSpellID
        ShowProcVisuals(self, procSpellID)
    elseif duration then
        if stacks ~= 0 then
            self.stacks_text:SetText(stacks)
        end
        if swapped or expiration ~= self.item.buff_end then
            self:ItemBuffApplied(duration, expiration, procSpellID)
        else
            self.last_proc_spell_id = procSpellID
            ShowProcVisuals(self, procSpellID)
        end
    elseif self.item.applied then
        self:ItemBuffFaded()
    end
end

local function OnUpdate(self)
    if self.item.cd_end and GetTime() > self.item.cd_end then
        self.item.cd_end = nil
        self.cooldown_current_end = nil
        self.texture:SetDesaturated(false)
        if SWITCHES.HIDE_READY ~= 0 and not ADDON.DRAG_UNLOCK then
            self:Hide()
        end
    end
end

local function ToggleButton(self)
    if not self.button then return end
    if InCombatLockdown() then return end

    if ADDON.DRAG_UNLOCK then
        self.button:Hide()
    elseif (SWITCHES.USE_ON_CLICK ~= 0 and self.is_usable)
    or (self.item and self.item.ID == ADDON.TRINKET_SWAP_ID) then
        self.button:Show()
    else
        self.button:Hide()
    end
end

local function ItemUpdate(self)
    local old_ID = self.item and self.item.ID
    if old_ID and old_ID ~= ADDON.TRINKET_SWAP_ID then
        self.item_ID_before_swap = old_ID
    end

    local item = get_item(self)
    if item and item == self.item then return end
    self.item = item
    if not item then
        if ADDON.DRAG_UNLOCK then return self:ToggleVisibility() end
        return self:Hide()
    end

    self.texture:SetTexture(item.texture)
    self.ilvl_text:SetText(item.ilvl)
    local rgb = DB.ITEM_QUALITY[item.quality] or DB.ITEM_QUALITY[1]
    self.ilvl_text:SetTextColor(rgb())

    self.no_swap_cd = item.CD == 0
    self:SetScript("OnUpdate", item.CD ~= 0 and OnUpdate or nil)

    local _, _, is_usable = GetInventoryItemCooldown("player", self.slot_ID)
    self.is_usable = is_usable == 1

    self:ResetFrame()
    self:AuraCheck(true)
    self:ItemUsedCheck()
    self:ToggleButton()
end

local function ItemChanged(self)
    if not self.item or self.no_swap_cd or self.is_usable or not self.item.proc_in_DB then return end

    local now = GetTime()
    if SWITCHES.FORCE30 == 0 then
        self.item.cd_start = now
        self.item.cd_end = now + self.item.CD
        self:ApplyItemCD()
    elseif self.item.cd_end and self.item.cd_end - now > 30 then
        self:ApplyItemCD()
    else
        self.item.cd_start = now
        self.item.cd_end = now + 30
        self:ApplyItemCD(30)
    end
end

---------------------------------------------------------------------------
-- Move mode: mouse dragging, per-icon enable checkmark, overlap protection
---------------------------------------------------------------------------

local MOVE_STRATA = "FULLSCREEN_DIALOG"
local NORMAL_STRATA = "MEDIUM"
local PLACEHOLDER_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- tint colors for the move overlay
local TINT = {
    ok  = {0, 1, 0, 0.25},
    bad = {1, 0, 0, 0.55},
    off = {0, 0, 0, 0.65},
}

local function round(v)
    return floor(v + 0.5)
end

-- Current on-screen center of a frame, relative to UIParent center (same units as POS_X/POS_Y)
local function GetFramePos(self)
    local scale = self:GetEffectiveScale()
    local uiScale = UIParent:GetEffectiveScale()
    local cx, cy = self:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (cx and ux) then
        return self.settings.POS_X, self.settings.POS_Y
    end
    return (cx * scale - ux * uiScale) / uiScale, (cy * scale - uy * uiScale) / uiScale
end

-- Only enabled icons block space. Disabled ones never show, so they can't overlap anything.
local function IsObstacle(other, moving)
    return other ~= moving and other.settings.SHOW ~= 0
end

-- Returns the first enabled icon that a square of 'size' at (x, y) would overlap.
-- Icons that only touch edges do not count as overlapping.
local function FindOverlap(moving, x, y, size)
    for _, other in pairs(ADDON.FRAMES) do
        if IsObstacle(other, moving) then
            local s = other.settings
            local half = (size + s.ICON_SIZE) / 2
            if abs(x - s.POS_X) < half and abs(y - s.POS_Y) < half then
                return other
            end
        end
    end
end

-- Nearest position to (x, y) where the icon does not overlap any enabled icon.
-- Candidates are the drop point plus every "pushed against a neighbour's edge" coordinate.
-- Returns nil if nothing fits on screen.
local function FindFreeSpot(moving, x, y, size)
    x, y = round(x), round(y)
    if not FindOverlap(moving, x, y, size) then
        return x, y
    end

    local xs, ys = {x}, {y}
    for _, other in pairs(ADDON.FRAMES) do
        if IsObstacle(other, moving) then
            local s = other.settings
            local half = ceil((size + s.ICON_SIZE) / 2)
            xs[#xs + 1] = s.POS_X - half
            xs[#xs + 1] = s.POS_X + half
            ys[#ys + 1] = s.POS_Y - half
            ys[#ys + 1] = s.POS_Y + half
        end
    end

    local maxX = UIParent:GetWidth() / 2 - size / 2
    local maxY = UIParent:GetHeight() / 2 - size / 2
    local bestDist, bestX, bestY
    for _, cx in ipairs(xs) do
        for _, cy in ipairs(ys) do
            if abs(cx) <= maxX and abs(cy) <= maxY then
                local dx, dy = cx - x, cy - y
                local dist = dx * dx + dy * dy
                if (not bestDist or dist < bestDist) and not FindOverlap(moving, cx, cy, size) then
                    bestDist, bestX, bestY = dist, cx, cy
                end
            end
        end
    end
    return bestX, bestY
end
ADDON.FindFreeSpot = FindFreeSpot


-- Snapping ("auto-lock"): when an icon is dropped close to another icon's row or column
-- it is lined up exactly with it, or docked flush against its side.
local SNAP_DISTANCE = 10

local function SnapEnabled()
    return SWITCHES.SNAP_ICONS ~= 0 and not IsShiftKeyDown()
end

local function SnapPosition(moving, x, y, size)
    local h = size / 2
    local bestDX, snapX, bestDY, snapY

    local function tryX(tx)
        local d = abs(tx - x)
        if d <= SNAP_DISTANCE and (not bestDX or d < bestDX) then bestDX, snapX = d, tx end
    end
    local function tryY(ty)
        local d = abs(ty - y)
        if d <= SNAP_DISTANCE and (not bestDY or d < bestDY) then bestDY, snapY = d, ty end
    end

    for _, other in pairs(ADDON.FRAMES) do
        if IsObstacle(other, moving) then
            local s = other.settings
            local oh = s.ICON_SIZE / 2
            local flush = ceil(oh + h)

            -- same row: centers, top edges or bottom edges in line
            tryY(s.POS_Y)
            tryY(round(s.POS_Y + oh - h))
            tryY(round(s.POS_Y - oh + h))
            -- same column: centers, left edges or right edges in line
            tryX(s.POS_X)
            tryX(round(s.POS_X - oh + h))
            tryX(round(s.POS_X + oh - h))

            -- dock flush beside / above / below a neighbour that is close by
            if abs(y - s.POS_Y) < oh + h then
                tryX(s.POS_X - flush)
                tryX(s.POS_X + flush)
            end
            if abs(x - s.POS_X) < oh + h then
                tryY(s.POS_Y - flush)
                tryY(s.POS_Y + flush)
            end
        end
    end

    return snapX or x, snapY or y, snapX ~= nil, snapY ~= nil
end

local snap_guides
local function ShowSnapGuides(x, y, showX, showY)
    if not snap_guides then
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetAllPoints(UIParent)
        f.h = f:CreateTexture(nil, "OVERLAY")
        f.h:SetTexture(0.2, 0.8, 1, 0.8)
        f.h:SetHeight(1)
        f.v = f:CreateTexture(nil, "OVERLAY")
        f.v:SetTexture(0.2, 0.8, 1, 0.8)
        f.v:SetWidth(1)
        snap_guides = f
    end
    local g = snap_guides
    if showY then
        g.h:ClearAllPoints()
        g.h:SetPoint("LEFT", UIParent, "CENTER", -UIParent:GetWidth() / 2, y)
        g.h:SetPoint("RIGHT", UIParent, "CENTER", UIParent:GetWidth() / 2, y)
        g.h:Show()
    else
        g.h:Hide()
    end
    if showX then
        g.v:ClearAllPoints()
        g.v:SetPoint("TOP", UIParent, "CENTER", x, UIParent:GetHeight() / 2)
        g.v:SetPoint("BOTTOM", UIParent, "CENTER", x, -UIParent:GetHeight() / 2)
        g.v:Show()
    else
        g.v:Hide()
    end
    g:Show()
end

local function HideSnapGuides()
    if snap_guides then snap_guides:Hide() end
end

local function AnchorToSettings(self)
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "CENTER", self.settings.POS_X, self.settings.POS_Y)
end

local function NotifyPositionChanged(self)
    if ADDON.OPTIONS and ADDON.OPTIONS.UpdateSliders then
        ADDON.OPTIONS:UpdateSliders(self.slot_ID)
    end
end

local function SetOverlayTint(overlay, state)
    if overlay.tint_state == state then return end
    overlay.tint_state = state
    overlay.tint:SetTexture(unpack(TINT[state]))
end

local function MoveOverlay_OnUpdate(overlay)
    local self = overlay.icon
    if not self.isMoving then return end
    local size = self.settings.ICON_SIZE
    local x, y = GetFramePos(self)
    if SnapEnabled() then
        local sx, sy, snappedX, snappedY = SnapPosition(self, x, y, size)
        ShowSnapGuides(sx, sy, snappedX, snappedY)
        x, y = sx, sy
    else
        HideSnapGuides()
    end
    SetOverlayTint(overlay, FindOverlap(self, x, y, size) and "bad" or "ok")
end

local UpdateMoveOverlay -- forward declaration

local function MoveCheck_OnClick(check)
    local self = check.icon
    local enable = check:GetChecked() and true or false
    self.settings.SHOW = enable and 1 or 0

    if enable then
        -- enabling by mouse is also protected: nudge it to the nearest free spot if needed
        local s = self.settings
        local x, y = FindFreeSpot(self, s.POS_X, s.POS_Y, s.ICON_SIZE)
        if not x then
            print(ADDON_NAME_COLOR .. format("%s overlaps another icon and there is no free spot nearby.", self.item_group))
        elseif x ~= s.POS_X or y ~= s.POS_Y then
            s.POS_X, s.POS_Y = x, y
            AnchorToSettings(self)
            NotifyPositionChanged(self)
            print(ADDON_NAME_COLOR .. format("%s was moved slightly so it doesn't overlap another icon.", self.item_group))
        end
    end

    UpdateMoveOverlay(self)
    if ADDON.OPTIONS and ADDON.OPTIONS.RefreshShowCheckboxes then
        ADDON.OPTIONS:RefreshShowCheckboxes()
    end
end

local function MoveCheck_OnEnter(check)
    GameTooltip:SetOwner(check, "ANCHOR_RIGHT")
    GameTooltip:SetText(check.icon.item_group)
    GameTooltip:AddLine("Checked: icon is active.", 1, 1, 1)
    GameTooltip:AddLine("Unchecked: icon is completely disabled.", 1, 1, 1)
    GameTooltip:AddLine("Drag the icon to move it.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function CreateMoveOverlay(self)
    local overlay = CreateFrame("Frame", nil, self)
    overlay.icon = self
    overlay:SetAllPoints()
    overlay:SetFrameLevel(self:GetFrameLevel() + TEXT_OVERLAY_FRAMELEVEL + 5)

    overlay.tint = overlay:CreateTexture(nil, "OVERLAY")
    overlay.tint:SetAllPoints()

    overlay.label = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    overlay.label:SetPoint("BOTTOM", overlay, "TOP", 0, 3)

    local check_name = ADDON_NAME .. self.slot_ID .. "MoveCheck"
    local check = CreateFrame("CheckButton", check_name, overlay, "UICheckButtonTemplate")
    check.icon = self
    check:SetWidth(20)
    check:SetHeight(20)
    check:SetPoint("CENTER", overlay, "TOPRIGHT", -2, -2)
    check:SetFrameLevel(overlay:GetFrameLevel() + 2)
    check:SetScript("OnClick", MoveCheck_OnClick)
    check:SetScript("OnEnter", MoveCheck_OnEnter)
    check:SetScript("OnLeave", GameTooltip_Hide)
    overlay.check = check

    overlay:SetScript("OnUpdate", MoveOverlay_OnUpdate)
    self.move_overlay = overlay
    return overlay
end

UpdateMoveOverlay = function(self)
    local overlay = self.move_overlay or CreateMoveOverlay(self)
    local enabled = self.settings.SHOW ~= 0

    overlay:SetFrameLevel(self:GetFrameLevel() + TEXT_OVERLAY_FRAMELEVEL + 5)
    overlay.check:SetFrameLevel(overlay:GetFrameLevel() + 2)
    overlay.check:SetChecked(enabled)

    local label = self.item_group
    if not self.item then
        label = label .. " |cFF888888(empty)|r"
        self.texture:SetTexture(PLACEHOLDER_ICON)
    end
    overlay.label:SetText(label)
    if enabled then
        overlay.label:SetTextColor(1, 0.82, 0)
    else
        overlay.label:SetTextColor(0.5, 0.5, 0.5)
    end

    overlay.tint_state = nil
    SetOverlayTint(overlay, enabled and "ok" or "off")
    overlay:Show()
end
ADDON.UpdateMoveOverlay = UpdateMoveOverlay

local function OnDragStart(self)
    if InCombatLockdown() then return end
    if not ADDON.DRAG_UNLOCK then return end
    self.drag_start_x = self.settings.POS_X
    self.drag_start_y = self.settings.POS_Y
    self:StartMoving()
    self.isMoving = true
end

local function OnDragStop(self)
    if not self.isMoving then return end
    self:StopMovingOrSizing()
    if self.SetUserPlaced then self:SetUserPlaced(false) end
    self.isMoving = false

    local s = self.settings
    HideSnapGuides()
    local posX, posY = GetFramePos(self)
    if SnapEnabled() then
        posX, posY = SnapPosition(self, posX, posY, s.ICON_SIZE)
    end
    local x, y = FindFreeSpot(self, posX, posY, s.ICON_SIZE)

    if x then
        s.POS_X, s.POS_Y = x, y
    else
        s.POS_X, s.POS_Y = self.drag_start_x or s.POS_X, self.drag_start_y or s.POS_Y
        print(ADDON_NAME_COLOR .. "No free spot there - icon moved back. Use the X/Y sliders to overlap icons on purpose.")
    end

    AnchorToSettings(self)
    if self.move_overlay and ADDON.DRAG_UNLOCK then
        UpdateMoveOverlay(self)
    end
    NotifyPositionChanged(self)
end
ADDON.StopDragging = OnDragStop

local function SetupDragForFrame(self)
    self:SetMovable(true)
    self:SetClampedToScreen(true)
    self:RegisterForDrag("LeftButton")
    self:SetScript("OnDragStart", OnDragStart)
    self:SetScript("OnDragStop", OnDragStop)
end

local function OnMouseDown(self, button)
    self = self.parent or self
    if ADDON.DRAG_UNLOCK then return end
    if InCombatLockdown() then
        if not IsModifierKeyDown() then return end
        print(ADDON_NAME_COLOR .. "Leave combat to swap items")
    elseif button == "LeftButton" then
        if IsControlKeyDown() then
            self.swap_back_item_id = self.item.ID
            for i=0,4 do
                local free_slots, bag_type = GetContainerNumFreeSlots(i)
                if bag_type == 0 and free_slots > 0 then
                    PickupInventoryItem(self.slot_ID)
                    return i == 0 and PutItemInBackpack() or PutItemInBag(i+CONTAINER_BAG_OFFSET)
                end
            end
        elseif IsShiftKeyDown() then
            if self.slot_ID == 13 then
                EquipItemByName(self.item.ID, 14)
            elseif self.slot_ID == 14 then
                EquipItemByName(self.item.ID, 13)
            end
        elseif IsAltKeyDown() then
            local item_name = GetItemInfo(self.item.ID)
            EquipItemByName(item_name, self.slot_ID)
        end
    elseif button == "RightButton" then
        if IsControlKeyDown() then
            if self.item.ID == ADDON.TRINKET_SWAP_ID then
                if not self.item_ID_before_swap then return end
                EquipItemByName(self.item_ID_before_swap, self.slot_ID)
            else
                EquipItemByName(ADDON.TRINKET_SWAP_ID, self.slot_ID)
            end
        end
    end
end

local function PlayerInCombat()
    return UnitAffectingCombat("player") or UnitGUID("boss1")
end

local function ToggleVisibility(self)
    if self.button and InCombatLockdown() then return end

    if ADDON.DRAG_UNLOCK then
        -- move mode: show every icon (disabled/empty ones dimmed) so it can be placed or re-enabled
        self:Show()
        UpdateMoveOverlay(self)
        return
    end

    if not self.item then return self:Hide() end

    if self.settings.SHOW == 0
    or (SWITCHES.COMBAT_ONLY ~= 0 and not PlayerInCombat())
    or (SWITCHES.HIDE_READY ~= 0 and not self.cooldown_current_end) then
        self:Hide()
    else
        self:Show()
    end
end

local function OnEvent(self, event, arg1, arg2)
    if event == "UNIT_AURA" then
        if arg1 ~= "player" then return end
        self:AuraCheck()
    elseif event == "ARENA_TEAM_ROSTER_UPDATE" then
        self:ResetFrame()
    elseif event == "BAG_UPDATE_COOLDOWN" then
        self:ItemUsedCheck()
    elseif event == "MODIFIER_STATE_CHANGED" then
        if InCombatLockdown() then return end
        if ADDON.DRAG_UNLOCK then return end
        self:EnableMouse(arg2 == 1)
    elseif event == "PLAYER_REGEN_DISABLED" then
        self:ToggleVisibility()
        self:UnregisterEvent("MODIFIER_STATE_CHANGED")
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:ToggleVisibility()
        self:RegisterEvent("MODIFIER_STATE_CHANGED")
    elseif event == "ITEM_UNLOCKED" then
        if not self.swap_back_item_id then return end
        EquipItemByName(self.swap_back_item_id, self.slot_ID)
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        if DB.ITEM_GROUP[arg1] ~= self.item_group then return end
        if self.swap_back_item_id == GetInventoryItemID("player", self.slot_ID) then
            self.swap_back_item_id = false
        end
        local item = self.item
        local slot = self.slot_ID
        self:ItemUpdate()
        if item == self.item and slot == self.slot_ID then return end
        self:ItemChanged()
    elseif event == "PLAYER_ENTERING_WORLD" then
        if self.item then return end
        self:ItemUpdate()
    elseif event == "UNIT_NAME_UPDATE" then
        if arg1 ~= "player" then return end
        if not self.item then
            self:ItemUpdate()
        end
        self:ItemChanged()
    end
end

local function new_font_overlay(parent)
    local font = parent:CreateFontString(nil, "OVERLAY")
    font:SetShadowColor(0, 0, 0, 1)
    font:SetShadowOffset(1, -1)
    return font
end

local function add_cooldown_text(self)
    if OmniCC then return end

    self.cooldown.text = new_font_overlay(self.cooldown)
    self.cooldown.text:SetPoint("CENTER")
    self.cooldown:SetScript("OnUpdate", function()
        if not self.cooldown_current_end then return end
        local diff = self.cooldown_current_end - GetTime()
        if diff > 100 then
            self.cooldown.text:SetFormattedText("%dm", diff/60)
        elseif diff < 0.1 then
            self.cooldown_current_end = nil
            self.cooldown.text:SetText()
        else
            self.cooldown.text:SetFormattedText(PRECISION_FORMAT[SWITCHES.SHOW_DECIMALS], diff)
        end
    end)
end

local function add_text_layer(self)
    self.text_overlay = CreateFrame("Frame", nil, self)
    self.text_overlay:SetAllPoints()
    self.text_overlay:SetFrameLevel(self:GetFrameLevel() + TEXT_OVERLAY_FRAMELEVEL)

    self.stacks_text = new_font_overlay(self.text_overlay)
    self.stacks_text:SetWidth(self.settings.ICON_SIZE)

    self.ilvl_text = new_font_overlay(self.text_overlay)
    self.ilvl_text:SetPoint("BOTTOMRIGHT", 0, 2)
end

local function set_new_font(text, icon_size, text_size)
    if not text then return end

    local fontsize = icon_size / 100 * text_size + 1
    local success = text:SetFont(SWITCHES.FONT_FILE, floor(fontsize), "OUTLINE")

    if success == 1 or success == true then return success end

    SWITCHES.FONT_FILE = DEFAULT_FONT
    text:SetFont(DEFAULT_FONT, floor(fontsize), "OUTLINE")
end

local function RedrawFrame(self)
    local zoom = self.settings.ZOOM / 100
    local mooz = 1 - zoom
    self.texture:SetTexCoord(zoom, zoom, zoom, mooz, mooz, zoom, mooz, mooz)

    local border_margin = self.settings.BORDER_MARGIN
    self.border:SetPoint("TOPLEFT", self, -border_margin, border_margin)
    self.border:SetPoint("BOTTOMRIGHT", self, border_margin, -border_margin)
    self.border:SetBackdrop({edgeFile=BORDER_TEXTURE, edgeSize=self.settings.EDGE_SIZE})
    self.border:SetBackdropBorderColor(0, 0, 0, 1)

    if self.settings.SHOW_ILVL ~= 0 then
        self.ilvl_text:Show()
    else
        self.ilvl_text:Hide()
    end

    local _icon_size = self.settings.ICON_SIZE
    local stacks_pos = SWITCHES.STACKS_BOTTOM == 0 and 1 or -1
    self.stacks_text:SetPoint("CENTER", 0, _icon_size/2 * stacks_pos)

    set_new_font(self.stacks_text, _icon_size, self.settings.STACKS_SIZE)
    set_new_font(self.ilvl_text, _icon_size, self.settings.ILVL_SIZE)
    set_new_font(self.cooldown.text, _icon_size, self.settings.CD_SIZE)

    if InCombatLockdown() then return end

    self:SetSize(_icon_size, _icon_size)
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "CENTER", self.settings.POS_X, self.settings.POS_Y)

    if self.text_overlay then
        self.text_overlay:SetFrameLevel(self:GetFrameLevel() + TEXT_OVERLAY_FRAMELEVEL)
    end

    if self._tcd_glow_active and self._tcd_glow_style_active == GLOW_STYLE_BUTTON then
        ButtonGlow_Update(self)
    end

    self:ToggleButton()
    self:ToggleVisibility()
end

local function add_functions(self)
    self.ApplyItemCD = ApplyItemCD
    self.AuraCheck = AuraCheck
    self.ItemBuffApplied = ItemBuffApplied
    self.ItemBuffFaded = ItemBuffFaded
    self.ItemChanged = ItemChanged
    self.ItemUsedCheck = ItemUsedCheck
    self.ItemUpdate = ItemUpdate
    self.RedrawFrame = RedrawFrame
    self.ResetFrame = ResetFrame
    self.ToggleButton = ToggleButton
    self.ToggleVisibility = ToggleVisibility

    self:RegisterEvent("BAG_UPDATE_COOLDOWN")
    self:RegisterEvent("ITEM_UNLOCKED")
    self:RegisterEvent("MODIFIER_STATE_CHANGED")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:RegisterEvent("UNIT_AURA")
    self:RegisterEvent("UNIT_NAME_UPDATE")
    self:RegisterEvent("ARENA_TEAM_ROSTER_UPDATE")

    self:SetScript("OnEvent", OnEvent)
    self:SetScript("OnMouseDown", OnMouseDown)
end

local function add_button(self)
    if SWITCHES.HIDE_READY ~= 0 then return end

    local frame_name = ADDON_NAME .. self.slot_ID
    self.button = CreateFrame("Button", frame_name.."Button", self, "SecureActionButtonTemplate")
    self.button:SetAttribute("type1", "item")
    self.button:SetAttribute("item", self.slot_ID)
    self.button:SetAllPoints()
    self.button:SetScript("OnMouseDown", OnMouseDown)
    self.button.parent = self
end

local function CreateNewItemFrame(slot_ID)
    local frame_name = ADDON_NAME..slot_ID
    local self = CreateFrame("Frame", frame_name, UIParent)

    self.slot_ID = slot_ID
    self.item_group = DB.ITEM_GROUP[slot_ID]
    self.item_proc_type = DB.ITEM_PROC_TYPES[slot_ID]
    self.settings = SETTINGS.ITEMS[slot_ID]

    self.texture = self:CreateTexture(frame_name.."Background", "OVERLAY")
    self.texture:SetAllPoints()
    self.texture:SetTexture("Interface/Icons/Trade_Engineering")

    self.border = CreateFrame("Frame", frame_name.."Border", self, BackdropTemplateMixin and "BackdropTemplate")
    self.border:SetFrameStrata("MEDIUM")

    self.cooldown = CreateFrame("Cooldown", frame_name.."Cooldown", self, "CooldownFrameTemplate")
    self.cooldown:SetAllPoints()
    if self.cooldown.SetEdgeScale then self.cooldown:SetEdgeScale(0) end

    add_button(self)
    add_cooldown_text(self)
    add_text_layer(self)
    add_functions(self)

    SetupDragForFrame(self)

    self:RedrawFrame()

    return self
end

local function update_settings(svars_table, settings_table)
    if not svars_table then return end
    for old_table_key in pairs(settings_table) do
        local new_table_value = svars_table[old_table_key]
        if new_table_value ~= nil then
            settings_table[old_table_key] = new_table_value
        end
    end
end

local function update_nested_settings(svars, key)
    local _svars = svars[key]
    if not _svars then return end
    for item_slot_id, settings_item in pairs(SETTINGS[key]) do
        update_settings(_svars[item_slot_id], settings_item)
    end
end

local function is_trinket(item_id)
    return item_id and select(9, GetItemInfo(item_id)) == "INVTYPE_TRINKET"
end

local function set_trinket_swap_id()
    local char_profile = _G["TrinketCDsProfileChar"]
    if not char_profile then return end

    local trinket_swap_link = char_profile["trinket_swap_link"]
    if not trinket_swap_link then return end

    local item_id = trinket_swap_link:match("item:(%d+):")
    if not is_trinket(item_id) then return end

    ADDON.TRINKET_SWAP_ID = tonumber(item_id)
end

function ADDON:SaveCurrentProfile(profileName)
    if not profileName then return end
    if not _G.TrinketCDsProfiles then
        _G.TrinketCDsProfiles = {}
    end
    local profiles = _G.TrinketCDsProfiles

    local saved = { ITEMS = {}, SWITCHES = {} }
    for slot_ID, settings in pairs(SETTINGS.ITEMS) do
        saved.ITEMS[slot_ID] = {}
        for k, v in pairs(settings) do
            saved.ITEMS[slot_ID][k] = v
        end
    end
    for k, v in pairs(SWITCHES) do
        saved.SWITCHES[k] = v
    end

    profiles[profileName] = saved
    print(ADDON_NAME_COLOR .. format("Profile '%s' saved.", profileName))
end

function ADDON:LoadProfile(profileName)
    if not profileName then return end
    local profiles = _G.TrinketCDsProfiles
    if not profiles or not profiles[profileName] then
        print(ADDON_NAME_COLOR .. format("Profile '%s' not found.", profileName))
        return
    end

    local saved = profiles[profileName]
    if saved.ITEMS then
        for slot_ID, saved_settings in pairs(saved.ITEMS) do
            if SETTINGS.ITEMS[slot_ID] then
                for k, v in pairs(saved_settings) do
                    SETTINGS.ITEMS[slot_ID][k] = v
                end
            end
        end
    end
    if saved.SWITCHES then
        for k, v in pairs(saved.SWITCHES) do
            SWITCHES[k] = v
        end
    end

    for _, frame in pairs(self.FRAMES) do
        frame:RedrawFrame()
        frame:AuraCheck(true)
    end

    print(ADDON_NAME_COLOR .. format("Profile '%s' loaded.", profileName))
end

function ADDON:DeleteProfile(profileName)
    if not profileName then return end
    local profiles = _G.TrinketCDsProfiles
    if not profiles or not profiles[profileName] then
        print(ADDON_NAME_COLOR .. format("Profile '%s' not found.", profileName))
        return
    end
    profiles[profileName] = nil
    print(ADDON_NAME_COLOR .. format("Profile '%s' deleted.", profileName))
end

function ADDON:GetProfileList()
    local profiles = _G.TrinketCDsProfiles
    if not profiles then return {} end
    local list = {}
    for name in pairs(profiles) do
        list[#list+1] = name
    end
    sort(list)
    return list
end

local function RestoreIconTexture(frame)
    if not frame.item then return end
    if frame.item.applied then
        ShowProcVisuals(frame, frame.last_proc_spell_id)
    else
        frame.texture:SetTexture(frame.item.texture)
    end
end

function ADDON:SetDragUnlock(state, silent)
    state = state and true or false
    if state == self.DRAG_UNLOCK then return true end

    if InCombatLockdown() then
        print(ADDON_NAME_COLOR .. "Cannot move icons in combat.")
        return false
    end

    self.DRAG_UNLOCK = state

    for _, frame in pairs(self.FRAMES) do
        if state then
            frame:SetFrameStrata(MOVE_STRATA)
            frame.border:SetFrameStrata(MOVE_STRATA)
            frame:EnableMouse(true)
        else
            if frame.isMoving then OnDragStop(frame) end
            frame:SetFrameStrata(NORMAL_STRATA)
            frame.border:SetFrameStrata(NORMAL_STRATA)
            frame:EnableMouse(false)
            if frame.move_overlay then frame.move_overlay:Hide() end
            RestoreIconTexture(frame)
        end
        if frame.text_overlay then
            frame.text_overlay:SetFrameLevel(frame:GetFrameLevel() + TEXT_OVERLAY_FRAMELEVEL)
        end
        frame:ToggleButton()
        frame:ToggleVisibility()
    end

    if self.OPTIONS and self.OPTIONS.RefreshDragCheckbox then
        self.OPTIONS:RefreshDragCheckbox()
    end

    if not silent then
        if state then
            print(ADDON_NAME_COLOR .. "|cFF00FF00Icons unlocked|r - drag them with the mouse. "
                .. "Use the checkmark on an icon to enable/disable it. "
                .. "Dragged icons can't overlap (use the X/Y sliders for that). |cFFFFFF00/tcd lock|r when done.")
        else
            print(ADDON_NAME_COLOR .. "|cFFFF0000Icons locked|r - positions saved.")
        end
    end
    return true
end

function ADDON:ToggleDragUnlock()
    return self:SetDragUnlock(not self.DRAG_UNLOCK)
end

function ADDON:OnEvent(event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end

        if not _G.TrinketCDsProfiles then
            _G.TrinketCDsProfiles = {}
        end

        if not _G.TrinketCDsProfileChar then
            _G.TrinketCDsProfileChar = {}
        end

        local char_settings = _G.TrinketCDsProfileChar.SETTINGS
        local svars = char_settings or _G[ADDON_PROFILE]

        if svars then
            update_nested_settings(svars, "ITEMS")
            update_settings(svars.SWITCHES, SWITCHES)
            if svars.SWITCHES and svars.SWITCHES.SHOW_GLOW ~= nil and svars.SWITCHES.SHOW_PROC_GLOW == nil then
                SWITCHES.SHOW_PROC_GLOW = svars.SWITCHES.SHOW_GLOW
            end
        end

        _G[ADDON_PROFILE] = SETTINGS

        for _, slot_ID in ipairs(self.SORTED_ITEMS) do
            self.FRAMES[slot_ID] = CreateNewItemFrame(slot_ID)
        end

        set_trinket_swap_id()

    elseif event == "PLAYER_REGEN_DISABLED" then
        -- still allowed to touch secure frames during this event: lock before lockdown starts
        if self.DRAG_UNLOCK then
            self:SetDragUnlock(false, true)
            print(ADDON_NAME_COLOR .. "Entered combat - icons locked.")
        end

    elseif event == "PLAYER_LOGOUT" then
        if not _G.TrinketCDsProfileChar then
            _G.TrinketCDsProfileChar = {}
        end
        local saved = { ITEMS = {}, SWITCHES = {} }
        for slot_ID, settings in pairs(SETTINGS.ITEMS) do
            saved.ITEMS[slot_ID] = {}
            for k, v in pairs(settings) do
                saved.ITEMS[slot_ID][k] = v
            end
        end
        for k, v in pairs(SWITCHES) do
            saved.SWITCHES[k] = v
        end
        _G.TrinketCDsProfileChar.SETTINGS = saved
    end
end

ADDON:RegisterEvent("ADDON_LOADED")
ADDON:RegisterEvent("PLAYER_LOGOUT")
ADDON:RegisterEvent("PLAYER_REGEN_DISABLED")
ADDON:SetScript("OnEvent", ADDON.OnEvent)

SLASH_RIDEPAD_TRINKETS1 = "/tcd"
function SlashCmdList.RIDEPAD_TRINKETS(arg)
    if arg == "p" or arg == "cpu" then
        if GetCVarInfo('scriptProfile') == "0" then
            print(ADDON_NAME_COLOR .. "To check cpu usage, type in chat and reload\n|cFFFFFF00/console scriptProfile 1|r")
            return
        end
        UpdateAddOnCPUUsage()
        local msg = ADDON_NAME_COLOR .. "Total seconds in addon:"
        msg = format("%s\n%.3fs", msg, GetAddOnCPUUsage(ADDON_NAME) / 1000)
        for _, frame in pairs(ADDON.FRAMES) do
            local t, c = GetFrameCPUUsage(frame)
            msg = format("%s\n%.3fs | %d function calls", msg, t / 1000, c)
        end
        print(msg)
    elseif arg == "o" or arg == "opt" or arg == "options" or arg == "config" then
        InterfaceOptionsFrame_OpenToCategory(ADDON_NAME)
    elseif arg == "unlock" then
        ADDON:SetDragUnlock(true)
    elseif arg == "lock" then
        ADDON:SetDragUnlock(false)
    elseif arg == "drag" or arg == "move" then
        ADDON:ToggleDragUnlock()
    elseif arg:match("^save ") then
        local profileName = arg:match("^save (.+)$")
        ADDON:SaveCurrentProfile(strtrim(profileName))
    elseif arg:match("^load ") then
        local profileName = arg:match("^load (.+)$")
        ADDON:LoadProfile(strtrim(profileName))
    elseif arg:match("^delete ") then
        local profileName = arg:match("^delete (.+)$")
        ADDON:DeleteProfile(strtrim(profileName))
    elseif arg == "profiles" or arg == "list" then
        local list = ADDON:GetProfileList()
        if #list == 0 then
            print(ADDON_NAME_COLOR .. "No saved profiles.")
        else
            print(ADDON_NAME_COLOR .. "Saved profiles:")
            for _, name in ipairs(list) do
                print("  |cFF00FF00" .. name .. "|r")
            end
        end
    else
        print(ADDON_NAME_COLOR .. "Available commands:")
        print("|cFFFFFF00o|r || |cFFFFFF00opt|r || |cFFFFFF00options|r || |cFFFFFF00config|r - opens options window")
        print("|cFFFFFF00p|r || |cFFFFFF00cpu|r - prints cpu usage")
        print("|cFFFFFF00drag|r || |cFFFFFF00move|r - toggle moving icons with the mouse")
        print("|cFFFFFF00unlock|r / |cFFFFFF00lock|r - unlock / lock icons")
        print("|cFFFFFF00save <name>|r - save current layout as profile")
        print("|cFFFFFF00load <name>|r - load profile")
        print("|cFFFFFF00delete <name>|r - delete profile")
        print("|cFFFFFF00profiles|r || |cFFFFFF00list|r - list saved profiles")
    end
end