Softskin = LibStub("AceAddon-3.0"):NewAddon("Softskin", "AceConsole-3.0", "AceEvent-3.0")

local playerGUID = UnitGUID("player")
local playerClass, _ = UnitClassBase("player")
local playerName = UnitName("player")

-- TODO query for party talents
local stoneskinReduction = 43 * 1.2; -- Guardian Totems
local strengthOfEarthAP = 86 * 1.15; -- Enhancing Totems

local damageTaken = 0
local damageMitigated = 0

local DEBUG = false

function Softskin:OnInitialize()
    self:RegisterChatCommand("softskin", "ChatCommand")
    self:RegisterChatCommand("sst", "ChatCommand")

    self:RegisterEvent("GROUP_ROSTER_UPDATE");

    self:EvaluateShaman()
end

function Softskin:ChatCommand(input)
    if not input or input:trim() == "" or input:trim() == "report" then
        if damageTaken == 0 or damageMitigated == 0 then
            self:SendMessage("No data to report")
            return
        end

        self:SendMessage(self:BuildReport())

    elseif input:trim() == "announce" then
        if damageTaken == 0 or damageMitigated == 0 then
            self:SendMessage("No data to report")
            return
        end

        self:Announce(self:BuildReport())

    elseif input:trim() == "reset" then
        self:SendMessage("Reset count")
        damageTaken = 0
        damageMitigated = 0
    elseif input:trim() == "evaluate" then
        self:EvaluateShaman()
    elseif input:trim() == "debug" then
        DEBUG = not DEBUG
    end
end

function Softskin:OnEnable()
    self:EvaluateShaman()
end

function Softskin:GROUP_ROSTER_UPDATE()
    self:EvaluateShaman()
end

function Softskin:EvaluateShaman()
    local classFilename

    for i = 1, GetNumGroupMembers() do
        classFilename, _ = UnitClassBase("party" .. i)
        if classFilename == "SHAMAN" then
            self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
            if DEBUG then
                self:SendMessage("Shaman detected")
            end
            return
        end
    end

    self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    if DEBUG then
        self:SendMessage("No Shaman detected")
    end
end

function Softskin:COMBAT_LOG_EVENT_UNFILTERED(...)
    return self:CombatLogHandler(CombatLogGetCurrentEventInfo())
end

function Softskin:CombatLogHandler(...)
    local _, subevent, _, _, _, _, _, destGUID, _, _, _ = ...

    if destGUID ~= playerGUID or subevent ~= "SWING_DAMAGE" then
        return
    end

    local _, _, _, _, _, _, _, _, buffID = AuraUtil.FindAuraByName("Stoneskin", "player")

    if buffID ~= nil then
        if AuraUtil.FindAuraByName("Strength of Earth", "player") ~= nil then
            return -- Multiple shaman
        end
    end

    local amount, _, _, _, _, _, _, _, _, _ = select(12, ...)

    damageTaken = damageTaken + amount

    local reduction = C_PaperDollInfo.GetArmorEffectivenessAgainstTarget(UnitArmor("player"))

    local softskinSwingDamage = amount / reduction

    -- Stoneskin active, so add damage back for calculations
    local swingDamage = softskinSwingDamage + stoneskinReduction

    damageMitigated = damageMitigated + (swingDamage - softskinSwingDamage)

    if DEBUG then
        self:SendMessage("swingDamage: " .. swingDamage .. "; damageMitigated: " .. damageMitigated)
    end
end

function Softskin:SendMessage(msg)
    if DEFAULT_CHAT_FRAME and msg ~= nil then
        DEFAULT_CHAT_FRAME:AddMessage("Softskin Totem: " .. msg, 0.0, 1.0, 0.0, 1.0)
    end
end

function Softskin:BuildReport()
    local classFilename, hasKings, entityName, unitAP

    local report = string.format("Analysis\nDamage taken: %d\nMaximum mitigated: %d (%.2f%%)\nTheoretical loss of:\n",
        math.floor(damageTaken), math.floor(damageMitigated), damageMitigated / damageTaken * 100)

    hasKings = AuraUtil.FindAuraByName("Blessing of Kings", "player") or
                   AuraUtil.FindAuraByName("Greater Blessing of Kings", "player")

    report = report ..
                 string.format('* %s: %d AP\n', playerName, math.floor(self:GetEffectiveAP(playerClass, hasKings)))

    for i = 1, GetNumGroupMembers() - 1 do
        classFilename, _ = UnitClassBase("party" .. i)
        entityName = UnitName("party" .. i)

        if entityName ~= nil then
            hasKings = AuraUtil.FindAuraByName("Blessing of Kings", "party" .. i) or
                           AuraUtil.FindAuraByName("Greater Blessing of Kings", "party" .. i)

            unitAP = math.floor(self:GetEffectiveAP(classFilename, hasKings))

            if unitAP > 0 then
                report = report .. string.format('* %s: %d AP\n', entityName, unitAP)
            end
        end

    end

    return report
end

function Softskin:Announce(report)
    local lines = {strsplit('\n', report)}

    SendChatMessage("Softskin Totem: " .. lines[1], "PARTY")

    for i = 2, #lines do
        SendChatMessage(lines[i], "PARTY")
    end
end

function Softskin:GetEffectiveAP(class, hasKings)
    local effectiveAP = 0;

    if class == "WARRIOR" then
        -- Prot (Vitality) / Fury (Imp Berserker): * 1.1
        effectiveAP = strengthOfEarthAP * 2 * 1.1
    elseif class == "HUNTER" then
        -- just pet, not hunter
        effectiveAP = strengthOfEarthAP * 2
    elseif class == "PALADIN" then
        -- Ret (Divine Strength): * 1.1
        effectiveAP = strengthOfEarthAP * 2 * 1.1
    elseif class == "DRUID" then
        -- Feral
        effectiveAP = strengthOfEarthAP * 2
    elseif class == "SHAMAN" then
        -- Enh
        effectiveAP = strengthOfEarthAP * 2
    elseif class == "ROGUE" then
        effectiveAP = strengthOfEarthAP
    end

    if hasKings then
        return effectiveAP * 1.1
    else
        return effectiveAP
    end
end
