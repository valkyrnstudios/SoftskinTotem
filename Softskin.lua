Softskin = LibStub("AceAddon-3.0"):NewAddon("Softskin", "AceConsole-3.0", "AceEvent-3.0")

local playerGUID = UnitGUID("player")
local playerClass, _ = UnitClassBase("player")
local playerName = UnitName("player")

local findAura = AuraUtil.FindAuraByName
local getArmorEffectivenessAgainstTarget = C_PaperDollInfo.GetArmorEffectivenessAgainstTarget
local floor = math.floor
local fmt = string.format

local stoneSkinLookup = {
    [8072] = 4,
    [8156] = 7 * 1.2,
    [8157] = 11 * 1.2, -- Guardian Totems at 16+
    [10403] = 16 * 1.2,
    [10404] = 22 * 1.2,
    [10405] = 30 * 1.2,
    [25506] = 36 * 1.2,
    [25507] = 43 * 1.2
}

local strengthLookup = {
    [8076] = 10,
    [31634] = 20 * 1.15, -- Enhancing Totems at 21+
    [8162] = 20 * 1.15,
    [8163] = 36 * 1.15,
    [10441] = 61 * 1.15,
    [25362] = 77 * 1.15,
    [25527] = 86 * 1.15
}

local damageTaken = 0
local damageMitigated = 0
local strengthOfEarthAP = -1

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
        self:SendMessage(fmt("debug: %s", tostring(DEBUG)))
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

    local _, _, _, _, _, _, _, _, _, buffId = findAura("Stoneskin", "player")
    if buffId == nil or stoneSkinLookup[buffId] == nil then
        return
    end

    local _, _, _, _, _, _, _, _, _, strengthOfEarthId = findAura("Strength of Earth", "player")
    if strengthOfEarthId ~= nil then
        strengthOfEarthAP = strengthLookup[strengthOfEarthId]
    end

    local amount, _, _, _, _, _, _, _, _, _ = select(12, ...)

    damageTaken = damageTaken + amount

    local reduction = getArmorEffectivenessAgainstTarget(UnitArmor("player"))

    local softskinSwingDamage = amount / reduction

    -- Stoneskin active, so add damage back for calculations
    local swingDamage = softskinSwingDamage + stoneSkinLookup[buffId]

    damageMitigated = damageMitigated + (swingDamage - softskinSwingDamage)

    if DEBUG then
        self:SendMessage(fmt("swingDamage: %d; damageMitigated: %d", swingDamage, damageMitigated))
    end
end

function Softskin:SendMessage(msg)
    if DEFAULT_CHAT_FRAME and msg ~= nil then
        DEFAULT_CHAT_FRAME:AddMessage("Softskin Totem: " .. msg, 0.0, 1.0, 0.0, 1.0)
    end
end

function Softskin:BuildReport()
    local classFilename, hasKings, entityName, unitAP, playerLevel

    local report = fmt("Analysis\nDamage taken: %d\nMaximum mitigated: %d (%.2f%%)", floor(damageTaken),
        floor(damageMitigated), damageMitigated / damageTaken * 100)

    hasKings = findAura("Blessing of Kings", "player") or findAura("Greater Blessing of Kings", "player")

    report = report .. fmt('\nTheoretical loss of:\n* %s: %d AP\n', playerName,
        floor(self:GetEffectiveAP(playerClass, hasKings, UnitLevel("Player"))))

    for i = 1, GetNumGroupMembers() - 1 do
        classFilename, _ = UnitClassBase("party" .. i)
        entityName = UnitName("party" .. i)

        if entityName ~= nil then
            hasKings = findAura("Blessing of Kings", "party" .. i) or
                           findAura("Greater Blessing of Kings", "party" .. i)

            unitAP = floor(self:GetEffectiveAP(classFilename, hasKings, UnitLevel("party" .. i)))

            if unitAP > 0 then
                report = report .. fmt('* %s: %d AP\n', entityName, unitAP)
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

function Softskin:GetEffectiveAP(class, hasKings, playerLevel)
    local effectiveAP = 0

    if strengthOfEarthAP < 0 then
        if playerLevel >= 65 then
            strengthOfEarthAP = strengthLookup[25527]
        elseif playerLevel >= 60 then
            strengthOfEarthAP = strengthLookup[25362]
        elseif playerLevel >= 52 then
            strengthOfEarthAP = strengthLookup[10441]
        elseif playerLevel >= 38 then
            strengthOfEarthAP = strengthLookup[8163]
        elseif playerLevel >= 24 then
            strengthOfEarthAP = strengthLookup[8162]
        elseif playerLevel >= 10 then
            strengthOfEarthAP = strengthLookup[8076]
        else
            strengthOfEarthAP = -1
        end
    end

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
