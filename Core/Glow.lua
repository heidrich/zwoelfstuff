---------------------------------------------------------------------------
-- Proc glow - a short expanding ring plus a flash, built from color
-- textures and animation groups only. No LibCustomGlow, no texture files,
-- nothing that can break when Blizzard reshuffles art paths.
---------------------------------------------------------------------------
local _, ns = ...

local Glow = {}
ns.Glow = Glow

local RING_PULSES = 2          -- how often the ring expands per proc
local PULSE_DURATION = 0.45

function Glow.Attach(parent)
    local glow = {}

    local container = CreateFrame("Frame", nil, parent)
    container:SetAllPoints(parent)
    container:SetFrameLevel(parent:GetFrameLevel() + 5)
    container:Hide()
    glow.container = container

    -- The expanding ring. Anchored by its centre so the Scale animation
    -- cannot fight against edge anchors.
    local ring = CreateFrame("Frame", nil, container)
    ring:SetPoint("CENTER", container, "CENTER", 0, 0)
    glow.ring = ring
    glow.ringBorder = ns.CreateBorder(ring, 2, "OVERLAY")

    -- Additive flash across the whole display.
    local flash = container:CreateTexture(nil, "OVERLAY", nil, 2)
    flash:SetAllPoints(container)
    flash:SetTexture(ns.WHITE)
    flash:SetBlendMode("ADD")
    flash:SetAlpha(0)
    glow.flash = flash

    ---------------------------------------------------------------------
    -- Animations
    ---------------------------------------------------------------------
    local ringAnim = ring:CreateAnimationGroup()

    local grow = ringAnim:CreateAnimation("Scale")
    grow:SetDuration(PULSE_DURATION)
    grow:SetOrder(1)
    grow:SetSmoothing("OUT")
    if grow.SetScaleFrom then
        grow:SetScaleFrom(0.94, 0.94)
        grow:SetScaleTo(1.45, 1.45)
    end

    local ringFade = ringAnim:CreateAnimation("Alpha")
    ringFade:SetDuration(PULSE_DURATION)
    ringFade:SetOrder(1)
    ringFade:SetFromAlpha(1)
    ringFade:SetToAlpha(0)

    glow.ringAnim = ringAnim

    ---------------------------------------------------------------------
    -- API
    ---------------------------------------------------------------------
    function glow:SetSize(width, height)
        self.ring:SetSize(width + 6, height + 6)
    end

    function glow:SetColor(r, g, b)
        self.ringBorder:SetColor(r, g, b, 1)
        self.flash:SetVertexColor(r, g, b, 1)
    end

    function glow:Play()
        self.pulsesLeft = RING_PULSES
        self.container:Show()
        self.ring:SetAlpha(1)
        self.ringAnim:Stop()
        self.ringAnim:Play()

        -- Flash is driven by the shared OnUpdate below so it stays a single
        -- animation-free fade; simpler than a second animation group.
        self.flashAlpha = 0.55
        self.container:SetScript("OnUpdate", function(frame, elapsed)
            local alpha = (self.flashAlpha or 0) - elapsed * 2.2
            if alpha <= 0 then
                self.flashAlpha = 0
                self.flash:SetAlpha(0)
                frame:SetScript("OnUpdate", nil)
            else
                self.flashAlpha = alpha
                self.flash:SetAlpha(alpha)
            end
        end)
    end

    function glow:Stop()
        self.ringAnim:Stop()
        self.container:SetScript("OnUpdate", nil)
        self.flash:SetAlpha(0)
        self.container:Hide()
    end

    ringAnim:SetScript("OnFinished", function()
        glow.pulsesLeft = (glow.pulsesLeft or 1) - 1
        if glow.pulsesLeft > 0 then
            glow.ring:SetAlpha(1)
            glow.ringAnim:Play()
        else
            glow.ring:SetAlpha(0)
            if not glow.container:GetScript("OnUpdate") then
                glow.container:Hide()
            end
        end
    end)

    glow:SetColor(1, 0.62, 0.20)
    return glow
end
