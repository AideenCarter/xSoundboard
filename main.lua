local _, name_space = ...
local sound_dict = name_space.sound_dict
local player_cooldown = {}
local sound_cooldown = {}
local addon_message_prefix = "SOUNDBOARD"
local current_duration = 0
local current_start = 0
local own_cooldown = 0
local muted = false

----------------------------UTIL----------------------------

local debug = false
local function dbg_print(msg)
    if (debug) then
        print(msg)
    end
end

function is_retail()
    return floor((floor(select(4, GetBuildInfo())) / 10000)) >= 9
end

----------------------------DB----------------------------
local Soundboard = LibStub("AceAddon-3.0"):NewAddon("Soundboard")
local defaults   = {
    global = {
        auto_complete = false,
        coloring = false,
        muted = false,
        position = {
            point = "CENTER",
            relativeTo = "UIParent",
            relativePoint = "CENTER",
            xOffset = 0,
            yOffset = 0
        },
        size = {
            height = 100,
            width = 300
        },
        favourites = {}
    }
}

function Soundboard:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("SoundboardDB", defaults)
    self.db.RegisterCallback(self, "OnDatabaseShutdown", "SaveUIConfig")
    muted = self.db.global.muted
end

local function toggle_auto_complete()
    Soundboard.db.global.auto_complete = not Soundboard.db.global.auto_complete
end

local function toggle_coloring()
    Soundboard.db.global.coloring = not Soundboard.db.global.coloring
end
----------------------------SLASH----------------------------
local function get_cooldown(type)
    local cooldown = 15
    if type == "RAID" then
        cooldown = 60
    elseif type == "WHISPER" then
        cooldown = 0
    elseif debug then
        cooldown = 0
    end

    return cooldown
end

local groups = {}
for k, v in pairs(sound_dict) do
    groups[sound_dict[k].group] = 1
end
SLASH_SB1 = "/sb"
SlashCmdList["SB"] = function(sound)
    if sound:lower() == "show" then
        if _G["SOUNDBOARD_FRAME"]:IsShown() then
            _G["SOUNDBOARD_FRAME"]:Hide()
        else
            _G["SOUNDBOARD_FRAME"]:Show()
        end

        return
    end

    if sound:lower() == "reset" then
        _G["SOUNDBOARD_FRAME"]:SetSize(300, 200);
        _G["SOUNDBOARD_FRAME"]:ClearAllPoints()
        _G["SOUNDBOARD_FRAME"]:SetPoint("CENTER", UIParent, "CENTER", "0", "0")
    end

    if sound:lower() == "resetfav" then
        Soundboard.db.global.favourites = {}
    end

    if muted == true then
        dbg_print("not sending " .. sound .. " because muted")
        return
    end

    local chat_type = ""

    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then                        --Instance Group
        chat_type = "INSTANCE_CHAT"
    elseif IsInRaid() and not IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then --Raid Group
        chat_type = "RAID"
    elseif IsInGroup(LE_PARTY_CATEGORY_HOME) then                        --Party
        chat_type = "PARTY"
    elseif not is_retail() then
        chat_type = "YELL"
    else
        chat_type = "WHISPER"
    end


    own_cooldown = get_cooldown(chat_type)
    dbg_print("setting own cooldown minMaxValues to (0, " .. own_cooldown .. ")")
    statusBar:SetMinMaxValues(0, own_cooldown)

    dbg_print("sending " .. sound .. " in " .. chat_type)
    if chat_type == "WHISPER" then
        local name, _ = UnitName("player")
        C_ChatInfo.SendAddonMessage(addon_message_prefix, sound, chat_type, name)
    else
        C_ChatInfo.SendAddonMessage(addon_message_prefix, sound, chat_type);
    end
end

_G["soundboard_call"] = SlashCmdList["SB"]
----------------------------QUEUE----------------------------

List = {}
function List.new()
    return { first = 0, last = -1 }
end

function List.pushright(list, value)
    local last = list.last + 1
    list.last = last
    list[last] = value
end

function List.popleft(list)
    local first = list.first
    if first > list.last then error("list is empty") end
    local value = list[first]
    list[first] = nil
    list.first = first + 1
    return value
end

local sound_queue = List:new()

----------------------------EVENTS----------------------------
name = ""
realm = ""

local function is_on_cooldown(key, list, cooldown)
    if list[key] == nil then
        return false;
    end
    return GetTime() - list[key] < cooldown;
end

local function recvEventHandler(self, event, ...)
    if event ~= "CHAT_MSG_ADDON" then
        return
    end

    --scuffed fix
    if realm == "" then
        name, realm = UnitFullName("player")
        _G["SOUNDBOARD_full_player_name"] = name .. "-" .. realm
    end

    local prefix = select(1, ...);
    local message = select(2, ...);
    local type = select(3, ...);
    local sender = select(4, ...);
    if prefix ~= addon_message_prefix then
        return
    end

    dbg_print("received " .. message .. " from " .. sender .. " in " .. type .. " chat with " .. prefix .. " prefix")

    --if there is no such sound, skip
    local sound_file = sound_dict[message];
    if sound_file == nil then
        return
    end

    local cooldown = get_cooldown(type)

    --check for cds
    if is_on_cooldown(sender, player_cooldown, cooldown) then
        dbg_print("sender on cooldown")
        return
    end

    if is_on_cooldown(message, sound_cooldown, cooldown) then
        dbg_print("sound on cooldown")
        return;
    end

    --add cd
    message = message:lower()
    player_cooldown[sender] = GetTime();
    sound_cooldown[message] = GetTime();

    --add sound to q
    dbg_print("adding " .. message .. " to queue")
    List.pushright(sound_queue, message);
end

local recvFrame = CreateFrame("Frame");
recvFrame:RegisterEvent("CHAT_MSG_ADDON");
recvFrame:SetScript("OnEvent", recvEventHandler);

local function everyFrameHandler(self, event, ...)
    local player_full_mame = _G["SOUNDBOARD_full_player_name"]
    if player_cooldown[player_full_mame] ~= nil then
        if GetTime() > player_cooldown[player_full_mame] - own_cooldown then
            local status_value = GetTime() - player_cooldown[player_full_mame] - own_cooldown
            if status_value > 0 then
                statusBar:SetValue(own_cooldown)
            end
            statusBar:SetValue(status_value * -1)
        end
    end

    if sound_queue.first > sound_queue.last then
        return;
    end

    if GetTime() - current_start < current_duration then
        dbg_print("wait until current sound is finished")
        return;
    end

    local command = List.popleft(sound_queue);
    dbg_print("playing " .. command)
    local sound_file = sound_dict[command];
    if sound_file == nil then
        return
    end
    if muted == false then
        PlaySoundFile(sound_file.path, "Master");
    end
    current_duration = sound_file.duration;
    current_start = GetTime();
end

local everyFrame = CreateFrame("Frame");
everyFrame:SetScript("OnUpdate", everyFrameHandler);
C_ChatInfo.RegisterAddonMessagePrefix(addon_message_prefix);

----------------------------AUTO-Complete----------------------------
function createAutoComplete()
    if Soundboard.db.global.auto_complete then
        for i = 1, NUM_CHAT_WINDOWS do
            local frame = _G["ChatFrame" .. i]
            local keyset = {}
            local n = 0

            for k, v in pairs(sound_dict) do
                n = n + 1
                keyset[n] = "/sb " .. k
            end

            local editbox = frame.editBox;
            local maxButtonCount = 20;

            local autocompletesettings = {
                perWord = true,
                pattern = "^/sb .*",
                activationChar = "^/sb .*",
                closingChar = ':',
                minChars = 2,
                fuzzyMatch = true,
                onSuggestionApplied = function(suggestion) return suggestion end,
                renderSuggestionFN = function(text)
                    return text:sub(5, #text) ..
                        " - " .. sound_dict[text:sub(5, #text)].group
                end,
                suggestionBiasFN = function(suggestion, text) return 0; end,
                interceptOnEnterPressed = true,
                addSpace = true,
                useTabToConfirm = true,
                useArrowButtons = true,
            }
            MySetupAutoComplete(editbox, keyset, maxButtonCount, autocompletesettings);
        end
    end
end

--------------------------UI-----------------------------------
local group_colors = {
    { red = 1,    green = 1,    blue = 1 },    -- White
    { red = 0.6,  green = 0.6,  blue = 1 },    -- Light Blue
    { red = 0.75, green = 0.75, blue = 0.75 }, -- Light Gray
    { red = 0.6,  green = 1,    blue = 0.6 },  -- Light Green
    { red = 1,    green = 0.8,  blue = 0.6 },  -- Light Orange
    { red = 0,    green = 1,    blue = 1 },    -- Cyan
    { red = 0.8,  green = 0.6,  blue = 1 },    -- Light Purple
    { red = 1,    green = 0.6,  blue = 0.8 }   -- Light Pink
}
local function compare(a, b)
    local sa = sound_dict[a]
    local sb = sound_dict[b]
    if sa.group ~= sb.group then
        return sa.group < sb.group
    else
        return sa.path < sb.path
    end
end
local function optionColoring(frame, db)
    if db then
        frame:GetFontString():SetTextColor(0, 255, 0)
    else
        frame:GetFontString():SetTextColor(255, 0, 0)
    end
end

local function createItems(sounds, child)
    local favourites = Soundboard.db.global.favourites
    local prevItem = nil
    local prevGroup = nil
    local colorText = Soundboard.db.global.coloring
    local i = 0
    for _, k in pairs(sounds) do
        local sound_group = sound_dict[k].group
        if prevGroup ~= sound_group then
            prevGroup = sound_group
            i = i + 1
            if i > table.getn(group_colors) then
                i = 1
            end
        end
        local item = CreateFrame("Button", nil, child, "UIPanelButtonTemplate")
        item:SetSize(265, 20)
        -- Anchor the item to the previous one or to the scroll frame if it's the first item
        if not prevItem then
            item:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -1)
        else
            item:SetPoint("TOPLEFT", prevItem, "BOTTOMLEFT", 0, -1)
        end

        item:SetText(k .. " - " .. sound_group)
        if colorText then
            item:GetFontString():SetTextColor(group_colors[i].red, group_colors[i].green, group_colors[i].blue)
        else
            item:GetFontString():SetTextColor(1, 1, 1)
        end
        item:RegisterForClicks("LeftButtonDown", "RightButtonDown")
        -- Add onclick handlers
        item:SetScript("OnClick", function(self, button, down)
            if button == "LeftButton" then
                SlashCmdList["SB"](k)
            else
                if favourites[k] == nil then
                    favourites[k] = k
                    item:GetFontString():SetTextColor(1, 1, 0)
                else
                    favourites[k] = nil
                    item:GetFontString():SetTextColor(1, 0, 0)
                end
            end
        end)
        prevItem = item
    end
    --save favourites to db
    Soundboard.db.global.favourites = favourites
end
-- Create a function to populate the list
local function createItemList(child, favChild)
    local sorted_sound_dict_keys = {}
    local sorted_favourties = {}
    for k, v in pairs(sound_dict) do table.insert(sorted_sound_dict_keys, k) end
    for k, v in pairs(Soundboard.db.global.favourites) do table.insert(sorted_favourties, k) end
    table.sort(sorted_sound_dict_keys, compare)
    table.sort(sorted_favourties, compare)
    createItems(sorted_sound_dict_keys, child)
    createItems(sorted_favourties, favChild)
end

local function createMenu()
    local db = Soundboard.db.global
    _G["SOUNDBOARD_FRAME"] = CreateFrame("Frame", "xSoundboardFrame", UIParent, "UIPanelDialogTemplate");
    frame = _G["SOUNDBOARD_FRAME"]
    frame:SetSize(db.size.width, db.size.height);
    frame:SetPoint(db.position.point, db.position.relativeTo, db.position.relativePoint, db.position.xOffset,
        db.position.yOffset);

    --makes frame moveable
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnSizeChanged", function(self, width, height)
        if width < 300 then
            width = 300
        end
        if height < 100 then
            height = 100
        end
        self:SetSize(width, height)
    end)

    --resizeable
    frame:SetResizable(true)
    local resizeButton = CreateFrame("Button", nil, frame)
    resizeButton:EnableMouse(true)
    resizeButton:SetPoint("BOTTOMRIGHT")
    resizeButton:SetSize(16, 16)
    resizeButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeButton:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeButton:SetScript("OnMouseDown", function(self)
        self:GetParent():StartSizing("bottom")
    end)
    resizeButton:SetScript("OnMouseUp", function(self)
        self:GetParent():StopMovingOrSizing("bottom")
    end)

    --adds title to frame
    frame.Title:SetFontObject("GameFontHighlight");
    frame.Title:SetPoint("CENTER", xSoundboardFrame, "CENTER");
    frame.Title:SetText("Soundboard");

    --adds scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate");
    scrollFrame:SetPoint("TOPLEFT", xSoundboardFrameDialogBG, "TOPLEFT", 4, -8);
    scrollFrame:SetPoint("BOTTOMRIGHT", xSoundboardFrameDialogBG, "BOTTOMRIGHT", -3, 4);

    scrollFrame.ScrollBar:ClearAllPoints();
    scrollFrame.ScrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", -3, -18);
    scrollFrame.ScrollBar:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", -7, 18);
    --adds favourites scroll frame
    local favScrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate");
    favScrollFrame:SetPoint("TOPLEFT", xSoundboardFrameDialogBG, "TOPLEFT", 4, -8);
    favScrollFrame:SetPoint("BOTTOMRIGHT", xSoundboardFrameDialogBG, "BOTTOMRIGHT", -3, 4);

    favScrollFrame.ScrollBar:ClearAllPoints();
    favScrollFrame.ScrollBar:SetPoint("TOPLEFT", favScrollFrame, "TOPRIGHT", -3, -18);
    favScrollFrame.ScrollBar:SetPoint("BOTTOMRIGHT", favScrollFrame, "BOTTOMRIGHT", -7, 18);
    favScrollFrame:Hide()

    --create child scroll frames
    local child = CreateFrame("Frame", nil, scrollFrame);
    child:SetSize(265, 1);

    local favChild = CreateFrame("Frame", nil, favScrollFrame);
    favChild:SetSize(265, 1);

    --add statusbar
    statusBar = CreateFrame("StatusBar", nil, frame)
    statusBar:SetSize(262, 15)
    statusBar:SetPoint("TOPLEFT", xSoundboardFrame, "TOPLEFT", 10, -7)
    statusBar:SetStatusBarTexture("Interface\\Addons\\Details\\images\\bar_flat" or
        "interface\\targetingframe\\ui-statusbar.blp")

    --add border to statusbar
    local statusBarBorder = CreateFrame("Frame", nil, statusBar, "BackdropTemplate")
    statusBarBorder:SetPoint("TOPLEFT", statusBar, "TOPLEFT", -2, 2)
    statusBarBorder:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMRIGHT", 2, -2)
    statusBarBorder:SetBackdrop(nil or {
        bgFile = "interface\\targetingframe\\ui-statusbar",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        tileSize = 0,
        edgeSize = 1,
        insets = { left = -1, right = -1, top = -1, bottom = -1 }
    })
    statusBarBorder:SetBackdropColor(0, 0, 0, 0)
    statusBarBorder:SetFrameLevel(statusBar:GetFrameLevel())

    scrollFrame:SetScrollChild(child);
    favScrollFrame:SetScrollChild(favChild)
    createItemList(child, favChild)

    --adds mute, unmute, auto_complete,coloring and reload button
    local muteButton = CreateFrame("Button", "xSoundboardFrameMute", frame, "UIPanelButtonTemplate");
    local unmuteButton = CreateFrame("Button", "xSoundboardFrameUnmute", muteButton, "UIPanelButtonTemplate");
    local favFrameButton = CreateFrame("Button", "xSoundboardReloadFrameButton", unmuteButton, "UIPanelButtonTemplate")
    local optButton = CreateFrame("Button", "xSoundboardFrameMute", favFrameButton, "UIPanelButtonTemplate");
    local autoCompleteButton = CreateFrame("Button", "xSoundboardFrameUnmute", optButton, "UIPanelButtonTemplate");
    local coloringButton = CreateFrame("Button", "xSoundboardFrameUnmute", autoCompleteButton, "UIPanelButtonTemplate");
    local reloadFrameButton = CreateFrame("Button", "xSoundboardReloadFrameButton", frame, "UIPanelButtonTemplate")
    local xbuttonSpacing = -2

    muteButton:SetSize(50, 20)
    muteButton:SetText("Mute")
    muteButton:SetPoint("TOPLEFT", 5, 15);
    if muted then muteButton:Disable() end
    muteButton:SetScript("OnClick", function(self, button, down)
        muteButton:Disable()
        unmuteButton:Enable()
        muted = true
    end)

    unmuteButton:SetSize(50, 20)
    unmuteButton:SetText("Unmute")
    unmuteButton:SetPoint("LEFT",muteButton, "RIGHT", xbuttonSpacing, 0);
    if not muted then unmuteButton:Disable() end
    unmuteButton:SetScript("OnClick", function(self, button, down)
        muteButton:Enable()
        unmuteButton:Disable()
        muted = false
    end)

    optButton:SetSize(20, 20)
    optButton:SetText(">")
    optButton:SetPoint("LEFT",favFrameButton, "RIGHT", xbuttonSpacing, 0);
    optButton:SetScript("OnClick", function(button, down)
        if autoCompleteButton:IsShown() then
            autoCompleteButton:Hide()
        else
            autoCompleteButton:Show()
        end
    end)

    autoCompleteButton:SetSize(100, 20)
    autoCompleteButton:SetText("Auto Complete")
    optionColoring(autoCompleteButton, Soundboard.db.global.auto_complete)
    autoCompleteButton:SetPoint("LEFT",optButton, "RIGHT", xbuttonSpacing, 0);
    autoCompleteButton:SetScript("OnClick", function(button, down)
        toggle_auto_complete()
        optionColoring(autoCompleteButton, Soundboard.db.global.auto_complete)
        reloadFrameButton:Show()
    end)
    autoCompleteButton:Hide()

    coloringButton:SetSize(60, 20)
    coloringButton:SetText("Coloring")
    optionColoring(coloringButton, Soundboard.db.global.coloring)
    coloringButton:SetPoint("LEFT",autoCompleteButton, "RIGHT", xbuttonSpacing, 0);
    coloringButton:SetScript("OnClick", function(button, down)
        toggle_coloring()
        optionColoring(coloringButton, Soundboard.db.global.coloring)
        reloadFrameButton:Show()
    end)

    reloadFrameButton:SetSize(50, 50)
    reloadFrameButton:SetText("Reload")
    reloadFrameButton:SetPoint("TOPRIGHT", 50, 0)
    reloadFrameButton:SetScript("OnClick", function(self)
        ReloadUI()
    end)
    reloadFrameButton:Hide()

    favFrameButton:SetSize(20, 20)
    favFrameButton:SetPoint("LEFT",unmuteButton, "RIGHT", xbuttonSpacing, 0)
    favFrameButton:SetNormalTexture("Interface\\Addons\\xSoundboard\\heart02.blp")
    favFrameButton:SetScript("OnClick", function(self)
        if favScrollFrame:IsShown() then
            favScrollFrame:Hide()
            scrollFrame:Show()
        else
            scrollFrame:Hide()
            favScrollFrame:Show()
        end
    end)
    frame:Hide()
end

function Soundboard:OnEnable()
    createAutoComplete()
    createMenu()
end

--Fires when logging out, just before the database is about to be cleaned of all AceDB metadata.
function Soundboard:SaveUIConfig()
    local db = Soundboard.db.global
    db.position.point, _, db.position.relativePoint, db.position.xOffset, db.position.yOffset = frame:GetPoint()
    db.size.width, db.size.height = frame:GetSize()
    db.muted = muted
end
