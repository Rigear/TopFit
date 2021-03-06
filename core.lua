local _, addon = ...

-- utility for rounding
local function round(input, places)
    if not places then
        places = 0
    end
    if type(input) == "number" and type(places) == "number" then
        local pow = 1
        for i = 1, ceil(places) do
            pow = pow * 10
        end
        return floor(input * pow + 0.5) / pow
    else
        return input
    end
end

-- create Addon object
TopFit = LibStub("AceAddon-3.0"):NewAddon("TopFit", "AceConsole-3.0")
TopFit.locale = addon.locale

-- debug function
function TopFit:Debug(text)
    if self.db.profile.debugMode then
        TopFit:Print("Debug: "..text)
    end
end

-- debug function
function TopFit:Warning(text)
    if not TopFit.warningsCache then
        TopFit.warningsCache = {}
    end
    
    if not TopFit.warningsCache[text] then
        TopFit.warningsCache[text] = true
        TopFit:Print("|cffff0000Warning: "..text)
    end
end

-- joins any number of tables together, one after the other. elements within the input-tables will get mixed, though
function TopFit:JoinTables(...)
    local result = {}
    local tab
    
    for i = 1, select("#", ...) do
        tab = select(i, ...)
        if tab then
            for index, value in pairs(tab) do
                tinsert(result, value)
            end
        end
    end
    
    return result
end

function TopFit.ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.tipText then
        GameTooltip:SetText(self.tipText, nil, nil, nil, nil, true)
    elseif self.itemLink then
        GameTooltip:SetHyperlink(self.itemLink)
    end
    GameTooltip:Show()
end

function TopFit.HideTooltip()
    GameTooltip:Hide()
end

function TopFit:EquipRecommendedItems()
    -- skip equipping if virtual items were included
    if (not TopFit.db.profile.sets[TopFit.setCode].skipVirtualItems) and TopFit.db.profile.sets[TopFit.setCode].virtualItems and #(TopFit.db.profile.sets[TopFit.setCode].virtualItems) > 0 then
        TopFit:Print(TopFit.locale.NoticeVirtualItemsUsed)
        
        -- reenable options and quit
        TopFit:StoppedCalculation()
        TopFit.isBlocked = false
        
        -- reset relevant score field
        TopFit.ignoreCapsForCalculation = nil
        
        -- initiate next calculation if necessary
        if (#TopFit.workSetList > 0) then
            TopFit:CalculateSets()
        end
        return
    end
    
    -- equip them
    TopFit.updateEquipmentCounter = 10000
    TopFit.equipRetries = 0
    TopFit.updateFrame:SetScript("OnUpdate", TopFit.onUpdateForEquipment)
end

function TopFit:onUpdateForEquipment(elapsed)
    -- don't try equipping in combat or while dead
    if UnitAffectingCombat("player") or UnitIsDeadOrGhost("player") then
        return
    end

    -- see if all items already fit
    allDone = true
    for slotID, recTable in pairs(TopFit.itemRecommendations) do
        if (TopFit:GetItemScore(recTable.locationTable.itemLink, TopFit.setCode, TopFit.ignoreCapsForCalculation) > 0) then
            slotItemLink = GetInventoryItemLink("player", slotID)
            if (slotItemLink ~= recTable.locationTable.itemLink) then
                allDone = false
            end
        end
    end
    
    TopFit.updateEquipmentCounter = TopFit.updateEquipmentCounter + elapsed
    
    -- try equipping the items every 100 frames (some weird ring positions might stop us from correctly equipping items on the first try, for example)
    if (TopFit.updateEquipmentCounter > 1) then
        for slotID, recTable in pairs(TopFit.itemRecommendations) do
            slotItemLink = GetInventoryItemLink("player", slotID)
            if (slotItemLink ~= recTable.locationTable.itemLink) then
                -- find itemLink in bags
                local itemTable = nil
                local found = false
                local foundBag, foundSlot
                for bag = 0, 4 do
                    for slot = 1, GetContainerNumSlots(bag) do
                        local itemLink = GetContainerItemLink(bag,slot)
                        
                        if itemLink == recTable.locationTable.itemLink then
                            foundBag = bag
                            foundSlot = slot
                            found = true
                            break
                        end
                    end
                end
                
                if not found then
                    -- try to find item in equipped items
                    for _, invSlot in pairs(TopFit.slots) do
                        local itemLink = GetInventoryItemLink("player", invSlot)
                        
                        if itemLink == recTable.locationTable.itemLink then
                            foundBag = nil
                            foundSlot = invSlot
                            found = true
                            break
                        end
                    end
                end
                
                if not found then
                    TopFit:Print(string.format(TopFit.locale.ErrorItemNotFound, recTable.locationTable.itemLink))
                    TopFit.itemRecommendations[slotID] = nil
                else
                    -- try equipping the item again
                    --TODO: if we try to equip offhand, and mainhand is two-handed, and no titan's grip, unequip mainhand first
                    ClearCursor()
                    if foundBag then
                        PickupContainerItem(foundBag, foundSlot)
                    else
                        PickupInventoryItem(foundSlot)
                    end
                    EquipCursorItem(slotID)
                end
            end
        end
        
        TopFit.updateEquipmentCounter = 0
        TopFit.equipRetries = TopFit.equipRetries + 1
    end
    
    -- if all items have been equipped, save equipment set and unregister script
    -- also abort if it takes to long, just save the items that _have_ been equipped
    if ((allDone) or (TopFit.equipRetries > 5)) then
        if (not allDone) then
            TopFit:Print(TopFit.locale.NoticeEquipFailure)
            
            for slotID, recTable in pairs(TopFit.itemRecommendations) do
                slotItemLink = GetInventoryItemLink("player", slotID)
                if (slotItemLink ~= recTable.locationTable.itemLink) then
                    TopFit:Print(string.format(TopFit.locale.ErrorEquipFailure, recTable.locationTable.itemLink, slotID, TopFit.slotNames[slotID]))
                    TopFit.itemRecommendations[slotID] = nil
                end
            end
        end
        
        TopFit:Debug("All Done!")
        TopFit.updateFrame:SetScript("OnUpdate", nil)
        TopFit:StoppedCalculation()
        
        EquipmentManagerClearIgnoredSlotsForSave()
        for _, slotID in pairs(TopFit.slots) do
            if (not TopFit.itemRecommendations[slotID]) then
                TopFit:Debug("Ignoring slot "..slotID)
                EquipmentManagerIgnoreSlotForSave(slotID)
            end
        end
        
        -- save equipment set
        if (CanUseEquipmentSets()) then
            local texture
            setName = TopFit:GenerateSetName(TopFit.currentSetName)
            -- check if a set with this name exists
            if (GetEquipmentSetInfoByName(setName)) then
                texture = GetEquipmentSetInfoByName(setName)
            else
                texture = "Spell_Holy_EmpowerChampion"
            end
            
            TopFit:Debug("Trying to save set: "..setName..", "..(texture or "nil"))
            SaveEquipmentSet(setName, texture)
        end
    
        -- we are done with this set
        TopFit.isBlocked = false
        
        -- reset relevant score field
        TopFit.ignoreCapsForCalculation = nil
        
        -- initiate next calculation if necessary
        if (#TopFit.workSetList > 0) then
            TopFit:CalculateSets()
        end
    end
end

function TopFit:GenerateSetName(name)
    -- using substr because blizzard interface only allows 16 characters
    -- although technically SaveEquipmentSet & co allow more ;)
    return (((name ~= nil) and string.sub(name.." ", 1, 12).."(TF)") or "TopFit")
end

function TopFit:ChatCommand(input)
    if not input or input:trim() == "" then
        InterfaceOptionsFrame_OpenToCategory("TopFit")
    else
        if input:trim():lower() == "show" then
            TopFit:CreateProgressFrame()
        elseif input:trim():lower() == "options" then
            InterfaceOptionsFrame_OpenToCategory("TopFit")
        else
            TopFit:Print(TopFit.locale.SlashHelp)
        end
    end
end

function TopFit:OnInitialize()
    -- load saved variables
    self.db = LibStub("AceDB-3.0"):New("TopFitDB")
    
    -- set callback handler
    TopFit.eventHandler = TopFit.eventHandler or LibStub("CallbackHandler-1.0"):New(TopFit)
    
    -- create gametooltip for scanning
    TopFit.scanTooltip = CreateFrame('GameTooltip', 'TFScanTooltip', UIParent, 'GameTooltipTemplate')
    
    -- check if any set is saved already, if not, create default
    if (not self.db.profile.sets) then
        self.db.profile.sets = {
            set_1 = {
                name = "Default Set",
                weights = {},
                caps = {},
                forced = {},
            },
        }
    end
    
    -- for savedvariable updates: check if each set has a forced table
    for set, table in pairs(self.db.profile.sets) do
        if table.forced == nil then
            table.forced = {}
        end
        
        -- also set if all stat and cap values are numbers
        for stat, value in pairs(table.weights) do
            table.weights[stat] = tonumber(value) or nil
        end
        for _, capTable in pairs(table.caps) do
            capTable.value = tonumber(capTable.value)
        end
    end
    
    -- list of weight categories and stats
    TopFit.statList = {
        [TopFit.locale.StatsCategoryBasic] = {
            [1] = "ITEM_MOD_AGILITY_SHORT",
            [2] = "ITEM_MOD_INTELLECT_SHORT",
            [3] = "ITEM_MOD_SPIRIT_SHORT",
            [4] = "ITEM_MOD_STAMINA_SHORT",
            [5] = "ITEM_MOD_STRENGTH_SHORT",
        },
        [TopFit.locale.StatsCategoryMelee] = {
            [1] = "ITEM_MOD_EXPERTISE_RATING_SHORT",
            [2] = "ITEM_MOD_FERAL_ATTACK_POWER_SHORT",
            -- [3] = "ITEM_MOD_ATTACK_POWER_SHORT",
            [3] = "ITEM_MOD_MELEE_ATTACK_POWER_SHORT",
            [4] = "ITEM_MOD_RANGED_ATTACK_POWER_SHORT",
            [5] = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT",
            [6] = "TOPFIT_MELEE_DPS",
            [7] = "TOPFIT_RANGED_DPS",
            [8] = "TOPFIT_MELEE_WEAPON_SPEED",
            [9] = "TOPFIT_RANGED_WEAPON_SPEED",
        },
        [TopFit.locale.StatsCategoryCaster] = {
            [1] = "ITEM_MOD_SPELL_PENETRATION_SHORT",
            [2] = "ITEM_MOD_SPELL_POWER_SHORT",
        },
        [TopFit.locale.StatsCategoryDefensive] = {
            [1] = "ITEM_MOD_BLOCK_RATING_SHORT",
            [2] = "ITEM_MOD_DODGE_RATING_SHORT",
            [3] = "ITEM_MOD_PARRY_RATING_SHORT",
            [4] = "ITEM_MOD_RESILIENCE_RATING_SHORT",
            [5] = "RESISTANCE0_NAME",                   -- armor
        },
        [TopFit.locale.StatsCategoryHybrid] = {
            [1] = "ITEM_MOD_CRIT_RATING_SHORT",
            [2] = "ITEM_MOD_HASTE_RATING_SHORT",
            [3] = "ITEM_MOD_HIT_RATING_SHORT",
            [4] = "ITEM_MOD_MASTERY_RATING_SHORT",
        },
        [TopFit.locale.StatsCategoryResistances] = {
            [1] = "RESISTANCE1_NAME",                   -- holy
            [2] = "RESISTANCE2_NAME",                   -- fire
            [3] = "RESISTANCE3_NAME",                   -- nature
            [4] = "RESISTANCE4_NAME",                   -- frost
            [5] = "RESISTANCE5_NAME",                   -- shadow
            [6] = "RESISTANCE6_NAME",                   -- arcane
        },
        --[[ [TopFit.locale.StatsCategoryArmorTypes] = {
            [1] = "TOPFIT_ARMORTYPE_CLOTH",
            [2] = "TOPFIT_ARMORTYPE_LEATHER",
            [3] = "TOPFIT_ARMORTYPE_MAIL",
            [4] = "TOPFIT_ARMORTYPE_PLATE",
        }]]
    }

    TOPFIT_ARMORTYPE_CLOTH = select(2, GetAuctionItemSubClasses(2));
    TOPFIT_ARMORTYPE_LEATHER = select(3, GetAuctionItemSubClasses(2));
    TOPFIT_ARMORTYPE_MAIL = select(4, GetAuctionItemSubClasses(2));
    TOPFIT_ARMORTYPE_PLATE = select(5, GetAuctionItemSubClasses(2));

    -- list of inventory slot names
    TopFit.slotList = {
        --"AmmoSlot",
        "BackSlot",
        "ChestSlot",
        "FeetSlot",
        "Finger0Slot",
        "Finger1Slot",
        "HandsSlot",
        "HeadSlot",
        "LegsSlot",
        "MainHandSlot",
        "NeckSlot",
        -- "RangedSlot",
        "SecondaryHandSlot",
        "ShirtSlot",
        "ShoulderSlot",
        "TabardSlot",
        "Trinket0Slot",
        "Trinket1Slot",
        "WaistSlot",
        "WristSlot",
    }
        
    TopFit.armoredSlots = {
        [1] = true,
        [3] = true,
        [5] = true,
        [6] = true,
        [7] = true,
        [8] = true,
        [9] = true,
        [10] = true,
    }

    -- create list of slot names with corresponding slot IDs
    TopFit.slots = {}
    TopFit.slotNames = {}
    for _, slotName in pairs(TopFit.slotList) do
        local slotID, _, _ = GetInventorySlotInfo(slotName)
        TopFit.slots[slotName] = slotID;
        TopFit.slotNames[slotID] = slotName;
    end
    
    -- create frame for OnUpdate
    TopFit.updateFrame = CreateFrame("Frame")
    
    -- create options
    TopFit:createOptions()

    -- register Slash command
    self:RegisterChatCommand("topfit", "ChatCommand")
    self:RegisterChatCommand("tf", "ChatCommand")
    
    -- cache tables
    TopFit.itemsCache = {}
    TopFit.scoresCache = {}
    
    -- table for equippable item list
    TopFit.equippableItems = {}
    TopFit:collectEquippableItems()
    TopFit.loginDelay = 150
    
    -- frame for eventhandling
    TopFit.eventFrame = CreateFrame("Frame")
    TopFit.eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    TopFit.eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
    TopFit.eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
    TopFit.eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    TopFit.eventFrame:SetScript("OnEvent", TopFit.FrameOnEvent)
    TopFit.eventFrame:SetScript("OnUpdate", TopFit.delayCalculationOnLogin)
    
    -- frame for calculation function
    TopFit.calculationsFrame = CreateFrame("Frame");
    
    -- heirloom info
    local isPlateWearer, isMailWearer = false, false
    if (select(2, UnitClass("player")) == "WARRIOR") or (select(2, UnitClass("player")) == "PALADIN") or (select(2, UnitClass("player")) == "DEATHKNIGHT") then
        isPlateWearer = true
    end
    if (select(2, UnitClass("player")) == "SHAMAN") or (select(2, UnitClass("player")) == "HUNTER") then
        isMailWearer = true
    end
    
    -- tables of itemIDs for heirlooms which change armor type
    -- 1: head, 3: shoulder, 5: chest
    TopFit.heirloomInfo = {
        plateHeirlooms = {
            [1] = {
                [1] = 69887,
                [2] = 61931,
             },
            [3] = {
                [1] = 42949,
                [2] = 44100,
                [3] = 44099,
                [4] = 69890,
            },
            [5] = {
                [1] = 48685,
                [2] = 69889,
            },
        },
        mailHeirlooms = {
            [1] = {
                [1] = 61936,
                [2] = 61935,
            },
            [3] = {
                [1] = 44102,
                [2] = 42950,
                [3] = 42951,
                [4] = 44101,
            },
            [5] = {
                [1] = 48677,
                [2] = 48683,
            },
        },
        isPlateWearer = isPlateWearer,
        isMailWearer = isMailWearer
    }
    
    -- container for plugin information and frames
    TopFit.plugins = {}
    
    -- button to open frame
    hooksecurefunc("ToggleCharacter", function (...)
        TopFit:initializeCharacterFrameUI()
    end)
    
    TopFit:collectItems()
end

function TopFit:collectEquippableItems()
    local newItem = {}
    
    -- check bags
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local item = GetContainerItemLink(bag, slot)
            
            if IsEquippableItem(item) then
                local found = false
                for _, link in pairs(TopFit.equippableItems) do
                    if link == item then
                        found = true
                        break
                    end
                end
                
                if not found then
                    tinsert(TopFit.equippableItems, item)
                    tinsert(newItem, {
                        itemLink = item,
                        bag = bag,
                        slot = slot
                    })
                end
            end
        end
    end
    
    -- check equipment (mostly so your set doesn't get recalculated just because you unequip an item)
    for _, invSlot in pairs(TopFit.slots) do
        local item = GetInventoryItemLink("player", invSlot)
        if IsEquippableItem(item) then
            local found = false
            for _, link in pairs(TopFit.equippableItems) do
                if link == item then
                    found = true
                    break
                end
            end
            
            if not found then
                tinsert(TopFit.equippableItems, item)
                tinsert(newItem, {
                    itemLink = item,
                    slot = invSlot
                })
            end
        end
    end
    
    if (#newItem == 0) then return false end
    return newItem
end

function TopFit:delayCalculationOnLogin()
    if TopFit.loginDelay then
        TopFit.loginDelay = TopFit.loginDelay - 1
        if TopFit.loginDelay <= 0 then
            TopFit.loginDelay = nil
            TopFit.eventFrame:SetScript("OnUpdate", nil)
            TopFit:collectEquippableItems()
        end
    end
end

function TopFit:FrameOnEvent(event, ...)
    if (event == "BAG_UPDATE_DELAYED") then
        -- update item list
        if TopFit.loginDelay then return end
        --TODO: only update affected bag
        TopFit:collectItems()
        
        -- check inventory for new equippable items
        local newEquip = TopFit:collectEquippableItems()
        if newEquip and not TopFit.loginDelay and
            ((TopFit.db.profile.defaultUpdateSet and GetActiveSpecGroup() == 1) or
            (TopFit.db.profile.defaultUpdateSet2 and GetActiveSpecGroup() == 2))
        then
            -- new equippable item in inventory, check if it is actually better than anything currently available
            for _, newItem in pairs(newEquip) do
                -- skip BoE items
                if not newItem.bag or not TopFit:IsItemBoE(newItem.bag, newItem.slot) then
                    TopFit:Debug("New Item: "..newItem.itemLink)
                    local itemTable = TopFit:GetCachedItem(newItem.itemLink)
                    local setCode = GetActiveSpecGroup() == 1 and TopFit.db.profile.defaultUpdateSet or TopFit.db.profile.defaultUpdateSet2

                    for _, slotID in pairs(itemTable.equipLocationsByType) do
                        -- try to get the currently used item from the player's equipment set
                        local setItem = TopFit:GetSetItemFromSlot(slotID, setCode)
                        local setItemTable = TopFit:GetCachedItem(setItem)
                        if setItem and setItemTable then
                            -- if either score or any cap is higher than currently equipped, calculate
                            if TopFit:GetItemScore(newItem.itemLink, setCode) > TopFit:GetItemScore(setItem, setCode) then
                                TopFit:Debug('Higher Score!')
                                TopFit:RunAutoUpdate(true)
                                return
                            else
                                -- check caps
                                for stat, cap in pairs(TopFit.db.profile.sets[setCode].caps) do
                                    if cap.active and (itemTable.totalBonus[stat] or 0) > (setItemTable.totalBonus[stat] or 0) then
                                        TopFit:Debug('Higher Cap!')
                                        TopFit:RunAutoUpdate(true)
                                        return
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    elseif (event == "PLAYER_LEVEL_UP") then
        --[[ remove cache info for heirlooms so they are rescanned
        for itemLink, itemTable in pairs(TopFit.itemsCache) do
            if itemTable.itemQuality == 7 then
                TopFit.itemsCache[itemLink] = nil
                TopFit.scoresCache[itemLink] = nil
            end
        end--]]
        
        -- if an auto-update-set is set, update that as well
        TopFit:ClearCache()
        TopFit:RunAutoUpdate()
    elseif (event == "ACTIVE_TALENT_GROUP_CHANGED") then
        TopFit:ClearCache()
        if not TopFit.db.profile.preventAutoUpdateOnRespec then
            TopFit:RunAutoUpdate()
        end
    end
end

function TopFit:RunAutoUpdate(skipDelay)
    if not TopFit.workSetList then
        TopFit.workSetList = {}
    end
    local runUpdate = false;
    if (TopFit.db.profile.defaultUpdateSet and GetActiveSpecGroup() == 1) then
        tinsert(TopFit.workSetList, TopFit.db.profile.defaultUpdateSet)
        runUpdate = true;
    end
    if (TopFit.db.profile.defaultUpdateSet2 and GetActiveSpecGroup() == 2) then
        tinsert(TopFit.workSetList, TopFit.db.profile.defaultUpdateSet2)
        runUpdate = true;
    end
    if runUpdate then
        if not TopFit.autoUpdateTimerFrame then
            TopFit.autoUpdateTimerFrame = CreateFrame("Frame")
        end
        -- because right on level up there seem to be problems finding the items for equipping, delay the actual update
        if not skipDelay then
            TopFit.delayCalculation = 0.5 -- delay in seconds until update
        else
            TopFit.delayCalculation = 0
        end
        TopFit.autoUpdateTimerFrame:SetScript("OnUpdate", function(self, delay)
            if (TopFit.delayCalculation > 0) then
                TopFit.delayCalculation = TopFit.delayCalculation - delay
            else
                TopFit.autoUpdateTimerFrame:SetScript("OnUpdate", nil)
                TopFit:CalculateSets(true) -- calculate silently
            end
        end)
    end
end

function TopFit:OnEnable()
    -- Called when the addon is enabled
end

function TopFit:OnDisable()
    -- Called when the addon is disabled
end

function TopFit:CreateEquipmentSet(set)
    if (CanUseEquipmentSets()) then
        setName = TopFit:GenerateSetName(set)
        -- check if a set with this name exists
        if (GetEquipmentSetInfoByName(setName)) then
            texture = GetEquipmentSetInfoByName(setName)
        else
            texture = "Spell_Holy_EmpowerChampion"
        end
        
        TopFit:Debug("Trying to create set: "..setName..", "..(texture or "nil"))
        SaveEquipmentSet(setName, texture)
    end
end