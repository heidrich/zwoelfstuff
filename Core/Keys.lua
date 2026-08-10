---------------------------------------------------------------------------
-- Keys - a mode, not a settings page.
--
-- Owner, 2026-08-10, having been given eight rows with a key control in each:
-- "du musst das anders machen mit den keys, du machst da einen keybind
-- button, dann grauen die buttons aus und du kannst auf den button klicken
-- und einen key belegen. dann steht der da drin."
--
-- He is describing what every action bar addon does, and the reason it won a
-- long time ago is that a key belongs to a PLACE ON THE SCREEN. A row called
-- "Slot 3" asks you to hold a picture of the panel in your head and count;
-- the panel itself is right there, and you can point at it.
--
-- SO THE PANELS COME OUT, everything on them dims, and each place wears its
-- own key. Click one, press a key, done - and what you just bound is written
-- where you are looking rather than in a list somewhere else.
--
-- WHY THE OVERLAY IS A SEPARATE FRAME and not a script on the slot: an answer
-- cell is a SecureActionButton. A click that reaches it CASTS, which is the
-- last thing anybody wants while assigning keys. A plain frame on top with
-- the mouse enabled swallows the click before it gets there - and being its
-- own frame, parented to UIParent, nothing here touches a protected frame at
-- all.
---------------------------------------------------------------------------
local _, ns = ...

local Keys = {}
ns.Keys = Keys

local UI = ns.UI
local C = UI.C

Keys.active = false

local overlays, banner = {}, nil
local capturing = nil

---------------------------------------------------------------------------
-- WHAT CAN CARRY A KEY
--
-- Built fresh every time the mode opens, because it is a list of frames that
-- are on the screen right now. Two panels, and both of them count their
-- places the way they are drawn.
---------------------------------------------------------------------------
function Keys.Targets()
    local out = {}

    local panel = ns.Externals and ns.Externals.Frame()
    if panel and panel.slots then
        for index = 1, ns.Externals.KEYS do
            local slot = panel.slots[index]
            if slot and slot:IsShown() then
                out[#out + 1] = {
                    frame = slot,
                    binding = ns.Externals.BindingName(index),
                    label = "Ask for cooldown " .. index,
                }
            end
        end
    end

    for index, cell in ipairs(ns.Answers and ns.Answers.Cells() or {}) do
        if index <= ns.Answers.KEYS and cell.who then
            out[#out + 1] = {
                frame = cell,
                binding = ns.Answers.BindingName(index),
                label = "Answer cell " .. index,
            }
        end
    end

    return out
end

---------------------------------------------------------------------------
-- Binding, which is the game's own and nothing of ours
---------------------------------------------------------------------------
local function Save()
    if SaveBindings and GetCurrentBindingSet then
        pcall(SaveBindings, GetCurrentBindingSet())
    end
end

function Keys.Current(binding)
    if not GetBindingKey then return nil end
    local ok, key = pcall(GetBindingKey, binding)
    if not ok then return nil end
    return key
end

function Keys.Clear(binding)
    local key = Keys.Current(binding)
    while key do
        if SetBinding then SetBinding(key, nil) end
        local next_ = Keys.Current(binding)
        if next_ == key then break end     -- SetBinding refused; do not spin
        key = next_
    end
    Save()
end

-- WHAT WAS ON THAT KEY BEFORE. Taking a key silently off something else is
-- the addon deciding for you; saying which one it was costs one line.
function Keys.Bind(binding, key)
    if not (key and binding) then return false end

    if InCombatLockdown and InCombatLockdown() then
        ns.Print("|cffff8040Not in combat|r - the game does not allow a key "
            .. "to be re-bound during a fight.")
        return false
    end

    local taken = GetBindingAction and GetBindingAction(key)
    if taken and taken ~= "" and taken ~= binding then
        local name = _G["BINDING_NAME_" .. taken] or taken
        ns.Print(string.format("|cffffd100%s|r taken from |cffffd100%s|r.",
            GetBindingText and GetBindingText(key) or key, name))
    end

    Keys.Clear(binding)
    if SetBinding then SetBinding(key, binding) end
    Save()
    return true
end

---------------------------------------------------------------------------
-- One badge over one place
---------------------------------------------------------------------------
local function Paint(overlay)
    local key = Keys.Current(overlay.binding)
    if capturing == overlay then
        overlay.text:SetText("press")
        overlay.text:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
        overlay.bg:SetColorTexture(0, 0, 0, 0.82)
        overlay.edge:SetColor(C.accent[1], C.accent[2], C.accent[3], 1)
        return
    end

    overlay.text:SetText(key and (ns.ShortKey(key) or key) or "+")
    if key then
        overlay.text:SetTextColor(1, 1, 1)
    else
        overlay.text:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    end
    overlay.bg:SetColorTexture(0, 0, 0, 0.62)
    overlay.edge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)
end

-- SetPropagateKeyboardInput IS PROTECTED IN COMBAT and raises
-- ADDON_ACTION_BLOCKED if it is called there. The same guard Edit Mode uses,
-- for the same reason: a fight can start while you are standing in a mode
-- that was legal to open.
local function Propagate(frame, state)
    if InCombatLockdown and InCombatLockdown() then return false end
    if not frame.SetPropagateKeyboardInput then return false end
    frame:SetPropagateKeyboardInput(state)
    return true
end

local function Stop()
    if not capturing then return end
    local overlay = capturing
    capturing = nil
    overlay:EnableKeyboard(false)
    overlay:EnableMouseWheel(false)
    Propagate(overlay, true)
    Paint(overlay)
end

-- A mouse button as the binding system names it. The LEFT one is missing on
-- purpose: it is how you got here, so binding it would mean the click that
-- opened this closed it again.
local MOUSE_KEYS = {
    MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5",
}

local function Build(index)
    if overlays[index] then return overlays[index] end

    -- UIParent, never the slot: a child of a protected frame is a protected
    -- frame, and this one has to be created, shown and moved in peace.
    local overlay = CreateFrame("Button", nil, UIParent)
    overlay:SetFrameStrata("DIALOG")
    overlay:RegisterForClicks("AnyUp")

    overlay.bg = overlay:CreateTexture(nil, "BACKGROUND")
    overlay.bg:SetAllPoints(overlay)

    overlay.edge = ns.CreateBorder(overlay, 2, "OVERLAY")

    overlay.text = UI.Label(overlay, "", 12, C.text)
    overlay.text:SetPoint("CENTER", overlay, "CENTER", 0, 0)

    overlay:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" then
            if capturing == self then Stop() else
                Keys.Clear(self.binding)
                Paint(self)
            end
            return
        end

        if capturing == self then Stop() return end
        if capturing then Stop() end

        capturing = self
        self:EnableKeyboard(true)
        self:EnableMouseWheel(true)
        Propagate(self, false)
        Paint(self)
    end)

    overlay:SetScript("OnKeyDown", function(self, key)
        if capturing ~= self then return end
        -- ESCAPE LEAVES THE WHOLE MODE, not just this badge. It is the key
        -- everybody presses to get out of something, and having it mean
        -- "never mind about this one square" would strand you in a screen
        -- with no other way out.
        if key == "ESCAPE" then Keys:SetActive(false) return end
        local chord = UI.Chord(key)
        if not chord then return end
        Keys.Bind(self.binding, chord)
        Stop()
    end)

    overlay:SetScript("OnMouseWheel", function(self, delta)
        if capturing ~= self then return end
        Keys.Bind(self.binding, UI.Chord(delta > 0 and "MOUSEWHEELUP"
            or "MOUSEWHEELDOWN"))
        Stop()
    end)

    overlay:SetScript("OnMouseDown", function(self, mouse)
        if capturing ~= self then return end
        local key = MOUSE_KEYS[mouse]
        if key then
            Keys.Bind(self.binding, UI.Chord(key))
            Stop()
        end
    end)

    overlay:SetScript("OnEnter", function(self)
        if capturing == self then return end
        self.edge:SetColor(C.accent[1], C.accent[2], C.accent[3], 1)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.label or "")
        GameTooltip:AddLine("Click, then press a key.", 1, 1, 1)
        GameTooltip:AddLine("Right-click clears it.", 0.61, 0.64, 0.69)
        GameTooltip:Show()
    end)
    overlay:SetScript("OnLeave", function(self)
        if capturing ~= self then Paint(self) end
        if GameTooltip then GameTooltip:Hide() end
    end)

    overlays[index] = overlay
    return overlay
end

---------------------------------------------------------------------------
-- The banner - what this mode is, while you are in it
---------------------------------------------------------------------------
-- THERE HAS TO BE A WAY OUT THAT YOU CAN SEE.
--
-- Owner, 2026-08-10: "man kommt nicht mehr aus dem modus. ein speichern
-- button oder done wäre cool" - and he was stuck for a reason worth writing
-- down: Escape was handled on the SQUARE, and a square only listens while it
-- is waiting for a key. Standing in the mode without having clicked one,
-- nothing on screen was listening at all.
--
-- So now there are three ways out and none of them needs to be discovered: a
-- button that says Done, Escape from anywhere in the mode, and Escape while a
-- square is capturing. A mode with one exit that is a keyboard shortcut is a
-- trap however well it works.
--
-- NOTHING IS "SAVED" HERE, and the button does not pretend otherwise. Each
-- key is written the moment it is pressed - SaveBindings, the game's own -
-- so Done means done, not committed. Calling it Save would promise that
-- leaving another way loses something, which would be a lie.
local function Banner()
    if banner then return banner end

    banner = CreateFrame("Frame", "ZwoelfStuffKeysBanner", UIParent)
    banner:SetFrameStrata("DIALOG")
    banner:SetSize(460, 74)
    banner:SetPoint("TOP", UIParent, "TOP", 0, -140)

    local bed = banner:CreateTexture(nil, "BACKGROUND")
    bed:SetAllPoints(banner)
    bed:SetColorTexture(C.canvasBg[1], C.canvasBg[2], C.canvasBg[3], 0.96)

    local edge = ns.CreateBorder(banner, 1, "OVERLAY")
    edge:SetColor(C.accent[1], C.accent[2], C.accent[3], 0.8)

    local title = UI.Label(banner, "Setting keys", 15, C.accent)
    title:SetPoint("TOPLEFT", banner, "TOPLEFT", 14, -12)

    local hint = UI.Label(banner,
        "Click a square, press the key. Right-click clears it. "
        .. "Every key is set the moment you press it.", 12, C.textDim)
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    hint:SetWidth(320)

    local done = UI.Button(banner, "Done", 96, function()
        Keys:SetActive(false)
    end, "primary")
    done:SetPoint("BOTTOMRIGHT", banner, "BOTTOMRIGHT", -14, 14)

    -- ESCAPE, FROM ANYWHERE IN THE MODE. The game's own list closes a shown
    -- frame on Escape; hiding this one is what leaving looks like, so the
    -- reflex works without a key handler of ours competing for the keyboard.
    if UISpecialFrames then
        table.insert(UISpecialFrames, "ZwoelfStuffKeysBanner")
    end
    -- Whatever hid it - the button, Escape, a reload - the mode ends with it.
    -- SetActive returns early when the state already matches, so the button
    -- hiding the banner and the banner ending the mode is one exit, not two.
    banner:SetScript("OnHide", function() Keys:SetActive(false) end)

    return banner
end

---------------------------------------------------------------------------
-- The mode
---------------------------------------------------------------------------
-- WHY IT CANNOT OPEN, in one place and answerable BEFORE anything is taken
-- apart. SetBinding is protected in combat, so the mode that exists to call
-- it does not open there.
--
-- A caller that has to tidy up first needs to ask in advance: Edit Mode hands
-- over to this mode and has to close itself to do it, and closing itself for
-- a mode that then refuses would leave the player somewhere they did not ask
-- to be. A second copy of the rule in that caller is a rule that drifts.
function Keys:Blocked()
    if InCombatLockdown and InCombatLockdown() then
        return "|cffff8040Not in combat.|r Keys are set out of combat - the "
            .. "game does not allow one to be re-bound during a fight."
    end
    return nil
end

function Keys:SetActive(on)
    on = on and true or false
    if on == Keys.active then return Keys.active end

    if on then
        local why = Keys:Blocked()
        if why then
            ns.Print(why)
            return false
        end
    end

    Keys.active = on
    Stop()

    -- THE PANELS COME OUT, whole. A slot nobody present can fill is not drawn
    -- while you play, and "place three of the eight keys and guess the rest"
    -- is not an answer. Placing is the state that draws every one of them,
    -- and it is the same state Edit Mode uses for the same reason.
    if ns.Externals then ns.Externals:SetPlacing(on) end
    if ns.Answers then ns.Answers:SetPlacing(on) end

    if on then
        -- Same rule as Edit Mode: what it hides, it hands back.
        Keys.cameFromWindow = ns.Options and ns.Options.frame
            and ns.Options.frame:IsShown() and true or false
        if ns.Options and ns.Options.frame then ns.Options.frame:Hide() end
    end

    Keys:Refresh()

    if not on then
        for _, overlay in ipairs(overlays) do overlay:Hide() end
        if banner then banner:Hide() end
        if ns.Externals and ns.Externals.Frame() then
            ns.Externals.Frame():SetAlpha(ns.Externals.Config().alpha or 1)
        end
        if ns.Answers and ns.Answers.Frame() then
            ns.Answers.Frame():SetAlpha(1)
        end

        if Keys.cameFromWindow then
            Keys.cameFromWindow = false
            if ns.Options then ns.Options:Open() end
        end
    end

    return Keys.active
end

function Keys:Toggle() return self:SetActive(not Keys.active) end

-- A FIGHT ENDS IT. The mode exists to call SetBinding, which the game does
-- not allow in combat - so staying in it would mean a screen full of squares
-- that all refuse. Out, with a reason, rather than a mode that has quietly
-- stopped working.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
watcher:SetScript("OnEvent", function()
    if not Keys.active then return end
    ns.Print("|cffff8040Combat.|r Keys are set out of combat - back to it "
        .. "afterwards.")
    Keys:SetActive(false)
end)

-- Placed over whatever is on screen at this moment. Called again whenever
-- the panels rebuild, because a slot that moved would leave its badge behind.
function Keys:Refresh()
    if not Keys.active then return end

    Banner():Show()

    local targets = Keys.Targets()
    for index, target in ipairs(targets) do
        local overlay = Build(index)
        overlay.binding = target.binding
        overlay.label = target.label
        overlay:ClearAllPoints()
        overlay:SetAllPoints(target.frame)
        Paint(overlay)
        overlay:Show()
    end

    for spare = #targets + 1, #overlays do overlays[spare]:Hide() end

    -- EVERYTHING UNDER THEM GOES QUIET. Owner: "dann grauen die buttons aus".
    -- The badge is what you are working with; the icon under it is only there
    -- to say which place this is.
    if ns.Externals and ns.Externals.Frame() then
        ns.Externals.Frame():SetAlpha(0.45)
    end
    if ns.Answers and ns.Answers.Frame() then
        ns.Answers.Frame():SetAlpha(0.45)
    end

    if #targets == 0 then
        ns.Print("|cffffd100Nothing to bind.|r Neither panel has a place on "
            .. "screen right now - switch one on, or pick some spells for it.")
    end
end
