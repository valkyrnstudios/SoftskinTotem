Softskin = LibStub("AceAddon-3.0"):NewAddon("Softskin", "AceConsole-3.0",
                                            "AceEvent-3.0")

local playerGUID = UnitGUID("player")
local playerClass, _ = UnitClassBase("player")

-- TODO query for party talents
local stoneskinReduction = 43 * 1.2; -- Guardian Totems
local strengthOfEarthAP = 86 * 1.15; -- Enhancing Totems

local damageTaken = 0
local damageMitigated = 0

local DEBUG = true

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
    end
end

function Softskin:OnEnable() self:EvaluateShaman() end

function Softskin:GROUP_ROSTER_UPDATE() self:EvaluateShaman() end

function Softskin:EvaluateShaman()
    local classFilename;

    for i = 1, GetNumGroupMembers() do
        classFilename, _ = UnitClassBase("party" .. i)
        if classFilename == "SHAMAN" or DEBUG then
            self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
            self:SendMessage("Shaman detected")
            return
        end
    end

    self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
    self:SendMessage("No Shaman detected")
end

function Softskin:COMBAT_LOG_EVENT_UNFILTERED(...)
    return self:CombatLogHandler(CombatLogGetCurrentEventInfo())
end

function Softskin:CombatLogHandler(...)
    if AuraUtil.FindAuraByName("Stoneskin Totem", "player") or DEBUG then
        if AuraUtil.FindAuraByName("Strength of Earth Totem", "player") then
            return -- Multiple shaman
        end
    end

    local _, subevent, _, _, _, _, _, destGUID, _, _, _ = ...

    if destGUID ~= playerGUID then return end

    local amount

    if subevent == "SWING_DAMAGE" then
        amount, _, _, _, _, _, _, _, _, _ = select(12, ...)
    else
        return
    end

    damageTaken = damageTaken + amount

    local reduction = C_PaperDollInfo.GetArmorEffectivenessAgainstTarget(
                          UnitArmor("player"))

    local softskinSwingDamage = amount / reduction

    -- Stoneskin active, so add damage back for calculations
    local swingDamage = softskinSwingDamage + stoneskinReduction

    damageMitigated = damageMitigated + (swingDamage - softskinSwingDamage)
end

function Softskin:SendMessage(msg)
    if (DEFAULT_CHAT_FRAME) then
        DEFAULT_CHAT_FRAME:AddMessage("Softskin Totem: " .. msg, 0.0, 1.0, 0.0,
                                      1.0);
    end
end

function Softskin:BuildReport()
    return string.format(
               "Softskin Totem: Damage taken: %d; maximum mitigated: %d (%.2f%%); theoretical loss of %d AP",
               math.floor(damageTaken), math.floor(damageMitigated),
               damageMitigated / damageTaken * 100,
               math.floor(self:CalculateAP()))
end

function Softskin:Announce(report) SendChatMessage(report, "PARTY") end

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