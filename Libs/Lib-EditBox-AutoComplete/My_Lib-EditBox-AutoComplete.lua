my_global_autocomplete_settings = {}
local old_ChatEdit_GetNextTellTarget = ChatEdit_GetNextTellTarget;
function MySetupAutoComplete(editbox, valueList, maxButtonCount, settings)

    editbox.old_OnEnterPressed = editbox.old_OnEnterPressed or
                                     editbox:GetScript("OnEnterPressed")
    editbox.old_OnEscPressed = editbox.old_OnEscPressed or
                                   editbox:GetScript("OnEscapePressed")
    editbox.old_OnTabPressed = editbox.old_OnTabPressed or
                                   editbox:GetScript("OnTabPressed")
    editbox.old_OnKeyDown = editbox.old_OnKeyDown or
                                editbox:GetScript("OnKeyDown")
    editbox.old_OnEditFocusLost = editbox.old_OnEditFocusLost or
                                      editbox:GetScript("OnEditFocusLost")

    local defaultsettings = {
        perWord = false,
        pattern = '',
        activationChar = '',
        closingChar = '',
        minChars = 0,
        fuzzyMatch = false,
        onSuggestionApplied = nil,
        renderSuggestionFN = nil,
        suggestionBiasFN = nil,
        interceptOnEnterPressed = false,
        addSpace = false,
        useTabToConfirm = false,
        useArrowButtons = false
    }

    my_global_autocomplete_settings = defaultsettings;

    if settings ~= nil then
        for k, v in pairs(settings) do my_global_autocomplete_settings[k] = v end
    end

    my_global_autocomplete_settings.valueList = valueList or {}
    my_global_autocomplete_settings.buttonCount = maxButtonCount or 10;
    my_global_autocomplete_settings.addHighlightedText = true

    My_EditBoxAutoCompleteBox:SetScript("OnHide", function(self)
		ChatEdit_GetNextTellTarget = old_ChatEdit_GetNextTellTarget;
    end);

    -- This should happen once globally, not for each autocomplete textbox
    My_EditBoxAutoCompleteBox.mouseInside = false;
    My_EditBoxAutoCompleteBox:SetScript("OnEnter", function(self)
        EditBoxAutoCompleteBox.mouseInside = true;
    end);
    My_EditBoxAutoCompleteBox:SetScript("OnLeave", function(self)
        My_EditBoxAutoCompleteBox.mouseInside = false;
    end);

    editbox:HookScript("OnTabPressed", function(editbox)
        if (my_global_autocomplete_settings.useTabToConfirm) then
            My_EditBoxAutoComplete_OnEnterPressed(editbox)
        else
            My_EditBoxAutoComplete_IncrementSelection(editbox, IsShiftKeyDown());
        end
    end);

    if (settings.useArrowButtons) then
        editbox:SetScript("OnKeyDown", function(editbox, key)

            if (My_EditBoxAutoCompleteBox:IsShown() and (My_EditBoxAutoCompleteBox.parent == editbox)) then
                if key == "TAB" then
                    ChatEdit_GetNextTellTarget = function()
                        return "", "";
                    end
                end
            end

            if key == "ENTER" then
                My_EditBoxAutoComplete_OnEnterPressed(editbox)
            end

            if My_EditBoxAutoComplete_OnArrowPressed(editbox, key) then
            else
                editbox.old_OnKeyDown(editbox, key)
            end

        end);
    end

    editbox:HookScript("OnTextChanged", function(editbox, changedByUser)
        My_EditBoxAutoComplete_OnTextChanged(editbox, changedByUser)
    end)

    editbox:HookScript("OnChar", function(editbox, char)

        if (char == my_global_autocomplete_settings.closingChar and
            editbox:GetUTF8CursorPosition() == #editbox:GetText() and
            editbox:GetUTF8CursorPosition() > 1) then

            My_EditBoxAutoComplete_OnEnterPressed(editbox)
        else
            My_EditBoxAutoComplete_OnChar(editbox);
        end

    end)

    editbox:SetScript("OnEditFocusLost", function(editbox)
        if not My_EditBoxAutoCompleteBox.mouseInside then
            My_EditBoxAutoComplete_HideIfAttachedTo(editbox)
            EditBox_ClearHighlight(editbox)
            editbox.old_OnEditFocusLost(editbox)
        end
    end)

    editbox:SetScript("OnEscapePressed", function(editbox)
        if not My_EditBoxAutoComplete_OnEscapePressed(editbox) then
            editbox.old_OnEscPressed(editbox)

            if AceGUI then
                AceGUI:ClearFocus(editbox.obj)
            else
                editbox:ClearFocus()
            end
        end
    end)
end

local function My_GetAutoCompleteButton(index)
    local buttonName = "My_EditBoxAutoCompleteButton" .. index;
    if not _G[buttonName] then
        local btn = CreateFrame("Button", buttonName, My_EditBoxAutoCompleteBox,
                                "My_EditBoxAutoCompleteButtonTemplate")
        btn:SetPoint("TOPLEFT", My_GetAutoCompleteButton(index - 1), "BOTTOMLEFT",
                     0, 0)
        btn:SetScript("OnEnter", function(self)
            My_EditBoxAutoCompleteBox.mouseInside = true;
        end)
        btn:SetScript("OnLeave", function(self)
            My_EditBoxAutoCompleteBox.mouseInside = false;
        end)
        _G[buttonName] = btn
        My_EditBoxAutoCompleteBox.existingButtonCount = max(index,
                                                         My_EditBoxAutoCompleteBox.existingButtonCount or
                                                             1)
                             
    end
    return _G[buttonName];
end

local function GetEditBoxAutoCompleteResults(text, valueList, fuzzyMatch)
    local results = {}
    local resultsCount = 1

    pcall(function()
        for i, value in ipairs(valueList) do
            pcall(function()

                local pattern = text:lower();
                if fuzzyMatch then
                    pattern = "^.*" .. text:lower() .. ".*";
                end

                if string.find(value:lower(), pattern) == 1 then
                    results[resultsCount] = value;
                    resultsCount = resultsCount + 1
                end
            end)
        end
    end)

    return results;
end

function My_EditBoxAutoComplete_OnLoad(self)
    -- self:SetBackdropBorderColor(0, 0, 0);
    -- self:SetBackdropColor(TOOLTIP_DEFAULT_BACKGROUND_COLOR.r, TOOLTIP_DEFAULT_BACKGROUND_COLOR.g, TOOLTIP_DEFAULT_BACKGROUND_COLOR.b);	
    self:SetBackdrop({
        bgFile = 'Interface\\DialogFrame\\UI-DialogBox-Background-Dark',
        edgeFile = 'Interface\\DialogFrame\\UI-DialogBox-Background-Dark',
        tile = true,
        tileSize = 32,
        edgeSize = 1,
        insets = {left = 0, right = 0, top = 0, bottom = 0}
    })
    AutoCompleteInstructions:SetText("|cffbbbbbb" .. PRESS_TAB .. "|r");
end

local function EditBoxAutoComplete_Update(parent, text, cursorPosition)
    local self = My_EditBoxAutoCompleteBox;
    local attachPoint;
    local origText = text

    if (not self:IsShown()) then
        self.currentResults = {}
        self.resultOffset = 0
    end

    if my_global_autocomplete_settings.perWord then
        local words = {}
        local newSentence = ""

        for word in string.gmatch(parent:GetText(), "([^%s]+)") do
            if word then table.insert(words, word) end
        end

        if (string.sub(origText, -1) ~= " ") then
            text = words[#words] -- Only use last word
        else
            text = ""
        end

    end

    text = origText

    if (not text or text == "") then
        --My_EditBoxAutoComplete_HideIfAttachedTo(parent);
        return;
    end

    if (text ~= nil and  my_global_autocomplete_settings.pattern ~= "") then
        local find = origText:find(my_global_autocomplete_settings.pattern)
        if (#text < 2 or not find) then
            My_EditBoxAutoComplete_HideIfAttachedTo(parent);
            return;
        else
            text = string.sub(text, 2) -- Remove the activation char
        end
    end

    if (#text < my_global_autocomplete_settings.minChars) then
        
        My_EditBoxAutoComplete_HideIfAttachedTo(parent);
        return;
    end

    if (cursorPosition <= strlen(origText)) then

        self:SetParent(parent);
        if (self.parent ~= parent) then
            My_EditBoxAutoComplete_SetSelectedIndex(self, 0);
            self.parentArrows = parent:GetAltArrowKeyMode();
        end
        parent:SetAltArrowKeyMode(false);
        local height = My_GetAutoCompleteButton(1):GetHeight() * 20
        if (parent:GetBottom() - height <= (AUTOCOMPLETE_DEFAULT_Y_OFFSET + 10)) then -- 10 is a magic number from the offset of AutoCompleteButton1.
            attachPoint = "ABOVE";
        else
            attachPoint = "BELOW";
        end
        if ((self.parent ~= parent) or (self.attachPoint ~= attachPoint)) then
            if (attachPoint == "ABOVE") then
                self:ClearAllPoints();
                self:SetPoint("BOTTOMLEFT", parent, "TOPLEFT",
                              parent.autoCompleteXOffset or 0,
                              parent.autoCompleteYOffset or
                                  -AUTOCOMPLETE_DEFAULT_Y_OFFSET);
            elseif (attachPoint == "BELOW") then
                self:ClearAllPoints();
                self:SetPoint("TOPLEFT", parent, "BOTTOMLEFT",
                              parent.autoCompleteXOffset or 0,
                              parent.autoCompleteYOffset or
                                  AUTOCOMPLETE_DEFAULT_Y_OFFSET);
            end
            self.attachPoint = attachPoint;
        end

        self.parent = parent;
        local possibilities = GetEditBoxAutoCompleteResults(text,
        my_global_autocomplete_settings.valueList,
                                                            my_global_autocomplete_settings
                                                                .fuzzyMatch);
        if (not possibilities) then possibilities = {}; end
        if (my_global_autocomplete_settings.fuzzyMatch) then
            -- We sort the possibilities here according to the following criteria

            -- 1. amount of characters in text vs the total in the possibility(match) (weight 100)
            -- 2. how early in we match (weight 50)
            -- 3. how many matching characters (case sensitive) (weight 25)
            local baseSortingFN = function(match, text)
                local matchingChars = 0;
                local cleanmatch = match --match:gsub(my_global_autocomplete_settings.pattern , "")
                local index, _, _ =
                    string.find(cleanmatch:lower(), text:lower())

                -- Check how many characters actually match (case sensitive)
                for i = index, index + #text do
                    if (string.sub(text, i - (index - 1), i - (index - 1)) ==
                        string.sub(cleanmatch, i, i)) then
                        matchingChars = matchingChars + 1;
                    end
                end

                return (25 * (1 - (matchingChars / #text))) + (50 * index) +
                           (25 * (1 - (#text / #cleanmatch)))
            end

            if my_global_autocomplete_settings.suggestionBiasFN ~= nil then
                table.sort(possibilities, function(left, right)
                    return baseSortingFN(left, text) -
                               my_global_autocomplete_settings.suggestionBiasFN(left, text) <
                               baseSortingFN(right, text) -
                               my_global_autocomplete_settings.suggestionBiasFN(right, text)
                end)
            else
                table.sort(possibilities, function(left, right)
                    return
                        baseSortingFN(left, text) < baseSortingFN(right, text)
                end)
            end
        end

        self.currentResults = possibilities
        My_EditBoxAutoComplete_UpdateResults(self, possibilities);
    else
        My_EditBoxAutoComplete_HideIfAttachedTo(parent);
    end
end

function My_EditBoxAutoComplete_HideIfAttachedTo(parent)
    local self = My_EditBoxAutoCompleteBox;
    if (self.parent == parent) then
        if (self.parentArrows) then
            parent:SetAltArrowKeyMode(self.parentArrows);
            self.parentArrows = nil;
        end
        self.parent = nil;

        self:Hide();
    end
end

function My_EditBoxAutoComplete_SetSelectedIndex(self, index)
    self.selectedIndex = index;
    for i = 1, 20 do
        My_GetAutoCompleteButton(i):UnlockHighlight();
    end
    if (index ~= 0) then My_GetAutoCompleteButton(index):LockHighlight(); end
end

function My_EditBoxAutoComplete_GetSelectedIndex(self) return self.selectedIndex; end

function My_EditBoxAutoComplete_GetNumResults(self) return self.numResults; end

function My_EditBoxAutoComplete_UpdateResults(self, results, indexOffset)
    local indexOffset = indexOffset or 0
    local totalReturns = #results - indexOffset;
    local numReturns = min(totalReturns, 20);
    local maxWidth = 150;

    for i = 1, numReturns do
        local button = My_GetAutoCompleteButton(i)
        button.name = Ambiguate(results[i + indexOffset], "none");

        if (my_global_autocomplete_settings.renderSuggestionFN ~= nil) then
            local text = my_global_autocomplete_settings.renderSuggestionFN(results[i +
                                                                     indexOffset])
            button:SetText(text);
        else
            button:SetText(results[i + indexOffset]);
        end

        maxWidth = max(maxWidth, button:GetFontString():GetWidth() + 30);
        button:Enable();
        button:Show();
    end

    for i = numReturns + 1, My_EditBoxAutoCompleteBox.existingButtonCount do
        My_GetAutoCompleteButton(i):Hide();
    end

    if (numReturns > 0) then
        maxWidth = max(maxWidth, AutoCompleteInstructions:GetStringWidth() + 30);
        self:SetHeight(numReturns * AutoCompleteButton1:GetHeight() + 35);
        self:SetWidth(maxWidth);
        self:Show();
        My_EditBoxAutoComplete_SetSelectedIndex(self, 1);
    else
        self:Hide();
    end

    if (totalReturns > 20) then
        local button = My_GetAutoCompleteButton(20);
        button:SetText(CONTINUED);
        button:Disable();
        self.numResults = numReturns - 1;
    else
        self.numResults = numReturns;
    end
end

function My_EditBoxAutoComplete_IncrementSelection(editBox, up)
    local autoComplete = My_EditBoxAutoCompleteBox;
    autoComplete.resultOffset = autoComplete.resultOffset or 0;

    --------------------TWITCH FIX--------------------

    if( not autoComplete:IsShown()) then 
        autoComplete = EditBoxAutoCompleteBox
        if(not autoComplete or not autoComplete:IsShown()) then
            return
        end

        local selectedIndex = EditBoxAutoComplete_GetSelectedIndex(autoComplete);
        local numReturns = EditBoxAutoComplete_GetNumResults(autoComplete);
        if (up) then
            local nextNum = selectedIndex;
            if selectedIndex == 1 then
                if autoComplete.resultOffset > 0 then
                    autoComplete.resultOffset = autoComplete.resultOffset - 1
                    EditBoxAutoComplete_UpdateResults(autoComplete,
                                                      autoComplete.currentResults,
                                                      autoComplete.resultOffset)
                else
                    autoComplete.resultOffset =
                        #autoComplete.currentResults - numReturns
                    nextNum = numReturns
                    EditBoxAutoComplete_UpdateResults(autoComplete,
                                                      autoComplete.currentResults,
                                                      autoComplete.resultOffset)
                end
            else
                nextNum = selectedIndex - 1;
            end
            EditBoxAutoComplete_SetSelectedIndex(autoComplete, nextNum);
        else
            local nextNum = selectedIndex;
            if selectedIndex == numReturns then
                if #autoComplete.currentResults - autoComplete.resultOffset >
                    numReturns then
                    autoComplete.resultOffset = autoComplete.resultOffset + 1
                    EditBoxAutoComplete_UpdateResults(autoComplete,
                                                      autoComplete.currentResults,
                                                      autoComplete.resultOffset)
                else
                    autoComplete.resultOffset = 0
                    nextNum = 1
                    EditBoxAutoComplete_UpdateResults(autoComplete,
                                                      autoComplete.currentResults,
                                                      autoComplete.resultOffset)
                end
            else
                nextNum = selectedIndex + 1;
            end

            EditBoxAutoComplete_SetSelectedIndex(autoComplete, nextNum)
        end
        return true
    end
    --------------------TWITCH FIX--------------------
    if (autoComplete.parent == editBox) then
        local selectedIndex = My_EditBoxAutoComplete_GetSelectedIndex(autoComplete);
        local numReturns = My_EditBoxAutoComplete_GetNumResults(autoComplete);
        if (up) then
            local nextNum = selectedIndex;
            if selectedIndex == 1 then
                if autoComplete.resultOffset > 0 then
                    autoComplete.resultOffset = autoComplete.resultOffset - 1
                    My_EditBoxAutoComplete_UpdateResults(autoComplete,
                                                      autoComplete.currentResults,
                                                      autoComplete.resultOffset)
                else
                    autoComplete.resultOffset =
                        #autoComplete.currentResults - numReturns
                    nextNum = numReturns
                    My_EditBoxAutoComplete_UpdateResults(autoComplete,
                                                      autoComplete.currentResults,
                                                      autoComplete.resultOffset)
                end
            else
                nextNum = selectedIndex - 1;
            end
            My_EditBoxAutoComplete_SetSelectedIndex(autoComplete, nextNum);
        else
            -- print("Down " .. selectedIndex .. " " .. #autoComplete.currentResults .. " " .. (autoComplete.resultOffset or "NIL"))
            local nextNum = selectedIndex;
            if selectedIndex == numReturns then
                if #autoComplete.currentResults - autoComplete.resultOffset >
                    numReturns then
                    autoComplete.resultOffset = autoComplete.resultOffset + 1
                    My_EditBoxAutoComplete_UpdateResults(autoComplete,
                                                      autoComplete.currentResults,
                                                      autoComplete.resultOffset)
                else
                    autoComplete.resultOffset = 0
                    nextNum = 1
                    My_EditBoxAutoComplete_UpdateResults(autoComplete,
                                                      autoComplete.currentResults,
                                                      autoComplete.resultOffset)
                end
            else
                nextNum = selectedIndex + 1;
            end

            My_EditBoxAutoComplete_SetSelectedIndex(autoComplete, nextNum)
        end
        return true;
    end
    return false;
end

function My_EditBoxAutoComplete_OnTabPressed(editBox)
    return My_EditBoxAutoComplete_IncrementSelection(editBox, IsShiftKeyDown())
end

function My_EditBoxAutoComplete_OnArrowPressed(self, key)
    if (key == "UP") then
        return My_EditBoxAutoComplete_IncrementSelection(self, true);
    elseif (key == "DOWN") then
        return My_EditBoxAutoComplete_IncrementSelection(self, false);
    end
end

local function GetAutoCompleteButton(index)
    local buttonName = "EditBoxAutoCompleteButton" .. index;
    if not _G[buttonName] then
        local btn = CreateFrame("Button", buttonName, EditBoxAutoCompleteBox,
                                "EditBoxAutoCompleteButtonTemplate")
        btn:SetPoint("TOPLEFT", GetAutoCompleteButton(index - 1), "BOTTOMLEFT",
                     0, 0)
        btn:SetScript("OnEnter", function(self)
            EditBoxAutoCompleteBox.mouseInside = true;
        end)
        btn:SetScript("OnLeave", function(self)
            EditBoxAutoCompleteBox.mouseInside = false;
        end)
        _G[buttonName] = btn
        EditBoxAutoCompleteBox.existingButtonCount = max(index,
                                                         EditBoxAutoCompleteBox.existingButtonCount or
                                                             1)
    end
    return _G[buttonName];
end


function My_EditBoxAutoComplete_OnEnterPressed(self)

    local autoComplete = My_EditBoxAutoCompleteBox;
    if (autoComplete:IsShown() and (autoComplete.parent == self) and
        (My_EditBoxAutoComplete_GetSelectedIndex(autoComplete) ~= 0)) then
        My_EditBoxAutoCompleteButton_OnClick(
            My_GetAutoCompleteButton(My_EditBoxAutoComplete_GetSelectedIndex(
                                      autoComplete)));
        return true;
    end
    -------------------TWITCH FIX--------------------------

    if (EditBoxAutoCompleteBox:IsShown() and (EditBoxAutoComplete_GetSelectedIndex(EditBoxAutoCompleteBox) ~= 0)) then
        EditBoxAutoCompleteButton_OnClick(GetAutoCompleteButton(EditBoxAutoComplete_GetSelectedIndex(EditBoxAutoCompleteBox)));
        return true;
    end
    return false;
end

function My_EditBoxAutoComplete_OnTextChanged(self, userInput)

    if (userInput) then
        EditBoxAutoComplete_Update(self, self:GetText(),
                                   self:GetUTF8CursorPosition());
    end
    if (self:GetText() == "") then
        My_EditBoxAutoComplete_HideIfAttachedTo(self);
    end
end

function My_EditBoxAutoComplete_AddHighlightedText(editBox, text)
    local editBoxText = editBox:GetText();
    local utf8Position = editBox:GetUTF8CursorPosition();
    local possibilities = GetEditBoxAutoCompleteResults(text);

    if (possibilities and possibilities[1]) then
        -- We're going to be setting the text programatically which will clear the userInput flag on the editBox. So we want to manually update the dropdown before we change the text.
        EditBoxAutoComplete_Update(editBox, editBoxText, utf8Position);
        local newText = string.gsub(editBoxText, AUTOCOMPLETE_SIMPLE_REGEX,
                                    string.format(
                                        AUTOCOMPLETE_SIMPLE_FORMAT_REGEX,
                                        possibilities[1], string.match(
                                            editBoxText,
                                            AUTOCOMPLETE_SIMPLE_REGEX)), 1)
        editBox:SetText(newText);
        editBox:HighlightText(strlen(editBoxText), strlen(newText)); -- This won't work if there is more after the name, but we aren't enabling this for normal chat (yet). Please fix me when we do.
        editBox:SetCursorPosition(strlen(editBoxText));
    end
end

function My_EditBoxAutoComplete_OnChar(self)
    local autoComplete = My_EditBoxAutoCompleteBox;
    if (autoComplete:IsShown() and autoComplete.parent == self) then
        if (self.addHighlightedText and self:GetUTF8CursorPosition() ==
            strlenutf8(self:GetText())) then
            My_EditBoxAutoComplete_AddHighlightedText(self, self:GetText());
            return true;
        end
    end

    return false;
end

function My_EditBoxAutoComplete_OnEditFocusLost(self)
    My_EditBoxAutoComplete_HideIfAttachedTo(self);
end

function My_EditBoxAutoComplete_OnEscapePressed(self)
    local autoComplete = My_EditBoxAutoCompleteBox;
    if (autoComplete:IsShown() and autoComplete.parent == self) then
        My_EditBoxAutoComplete_HideIfAttachedTo(self);
        return true;
    end
    return false;
end

function My_EditBoxAutoCompleteButton_OnClick(self)
    local autoComplete = self:GetParent();
    local editBox = autoComplete.parent;
    local editBoxText = editBox:GetText();
    local newText;
    newText = string.gsub(editBoxText, AUTOCOMPLETE_SIMPLE_REGEX,
                            string.format(AUTOCOMPLETE_SIMPLE_FORMAT_REGEX,
                                        self.name, string.match(editBoxText,
                                                                AUTOCOMPLETE_SIMPLE_REGEX)),
                            1);


    editBox:SetText(self.name);
    -- When we change the text, we move to the end, so we'll be consistent and move to the end if we don't change it as well.
    editBox:SetCursorPosition(strlen(self.name));

    autoComplete:Hide();

    if my_global_autocomplete_settings.onSuggestionApplied ~= nil then
        my_global_autocomplete_settings.onSuggestionApplied(self.name);
    end
end
