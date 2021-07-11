Softskin = LibStub("AceAddon-3.0"):NewAddon("Softskin", "AceConsole-3.0",
                                            "AceEvent-3.0")

local playerGUID = UnitGUID("player")
local playerClass, _ = UnitClassBase("player")

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

function Softskin:OnEnable() self:EvaluateShaman() end

function Softskin:GROUP_ROSTER_UPDATE() self:EvaluateShaman() end

function Softskin:EvaluateShaman()
    local classFilename;

    for i = 1, GetNumGroupMembers() do
        classFilename, _ = UnitClassBase("party" .. i)
        if classFilename == "SHAMAN" then
            self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
            if DEBUG then self:SendMessage("Shaman detected") end
            return
        end
    end

    self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
    if DEBUG then self:SendMessage("No Shaman detected") end
end

function Softskin:COMBAT_LOG_EVENT_UNFILTERED(...)
    if AuraUtil.FindAuraByName("Stoneskin Totem", "player") ~= nil then
        if AuraUtil.FindAuraByName("Strength of Earth Totem", "player") ~= nil then
            return -- Multiple shaman
        end

        return self:CombatLogHandler(CombatLogGetCurrentEventInfo())
    else
        return
    end
end

function Softskin:CombatLogHandler(...)
    local _, subevent, _, _, _, _, _, destGUID, _, _, _ = ...

    if destGUID ~= playerGUID or subevent ~= "SWING_DAMAGE" then return end

    local amount, _, _, _, _, _, _, _, _, _ = select(12, ...)

    damageTaken = damageTaken + amount

    local reduction = C_PaperDollInfo.GetArmorEffectivenessAgainstTarget(
                          UnitArmor("player"))

    local softskinSwingDamage = amount / reduction

    -- Stoneskin active, so add damage back for calculations
    local swingDamage = softskinSwingDamage + stoneskinReduction

    damageMitigated = damageMitigated + (swingDamage - softskinSwingDamage)

    if DEBUG then
        self:SendMessage(
            "swingDamage: " .. swingDamage .. "; damageMitigated: " ..
                damageMitigated)
    end
end

function Softskin:SendMessage(msg)
    if (DEFAULT_CHAT_FRAME) then
        DEFAULT_CHAT_FRAME:AddMessage("Softskin Totem: " .. msg, 0.0, 1.0, 0.0,
                                      1.0);
    end
end

function Softskin:BuildReport()
    return string.format(
               "Damage taken: %d; maximum mitigated: %d (%.2f%%); theoretical loss of %d AP",
               math.floor(damageTaken), math.floor(damageMitigated),
               damageMitigated / damageTaken * 100,
               math.floor(self:CalculateAP()))
end

function Softskin:Announce(report)
    SendChatMessage("Softskin Totem: " .. report, "PARTY")
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

function Softskin:CalculateAP()
    local classFilename, hasKings;
    hasKings = AuraUtil.FindAuraByName("Blessing of Kings", "player") or
                   AuraUtil.FindAuraByName("Greater Blessing of Kings", "player")

    local effectiveAP = self:GetEffectiveAP(playerClass, hasKings)

    for i = 1, GetNumGroupMembers() do
        classFilename, _ = UnitClassBase("party" .. i)
        hasKings = AuraUtil.FindAuraByName("Blessing of Kings", "party" .. i) or
                       AuraUtil.FindAuraByName("Greater Blessing of Kings",
                                               "party" .. i)

        effectiveAP = effectiveAP + self:GetEffectiveAP(classFilename, hasKings)
    end

    return effectiveAP;
end
