-- Tactica.lua - Boss strategy helper addon for "vanilla"-compliant versions of Wow
-- Created by Doite

-------------------------------------------------
-- VERSION CHECK
-------------------------------------------------
local TACTICA_PREFIX = "TACTICA"

-- Provide gmatch/match if missing
do
  -- gmatch was gfind
  if not string.gmatch and string.gfind then
    string.gmatch = function(s, p) return string.gfind(s, p) end
  end
  -- Minimal match using find; returns the FIRST capture only
  if not string.match then
    string.match = function(s, p, init)
      local _, _, cap1 = string.find(s, p, init)
      return cap1
    end
  end
end

local function tlen(t)
  if table and table.getn then return table.getn(t) end
  local n=0; for _ in pairs(t) do n=n+1 end; return n
end

local function Tactica_GetVersion()
  local v
  if GetAddOnMetadata then
    v = GetAddOnMetadata("Tactica", "Version") or GetAddOnMetadata("Tactica", "X-Version")
  end
  v = v or (Tactica and Tactica.Version) or tostring(TacticaDB and TacticaDB.version or "0")
  return tostring(v or "0")
end

local function VersionIsNewer(a, b)
  if type(a) ~= "string" then a = tostring(a or "0") end
  if type(b) ~= "string" then b = tostring(b or "0") end
  local ai, bi = {}, {}
  for n in string.gmatch(a, "%d+") do table.insert(ai, tonumber(n) or 0) end
  for n in string.gmatch(b, "%d+") do table.insert(bi, tonumber(n) or 0) end
  local m = math.max(tlen(ai), tlen(bi))
  for i=1,m do
    local av = ai[i] or 0
    local bv = bi[i] or 0
    if bv > av then return true end
    if bv < av then return false end
  end
  return false
end

local _verGuildAnnounced, _verRaidAnnounced, _verNotifiedOnce = false, false, false
local _verLastEcho = 0
local _verWhoRid = nil

local _laterQueue = {}
local _laterFrame = CreateFrame("Frame")
_laterFrame:Hide()
_laterFrame:SetScript("OnUpdate", function()
  for i = tlen(_laterQueue), 1, -1 do
    local job = _laterQueue[i]
    local __dt = (arg1 and tonumber(arg1)) or 0.02; job.t = job.t - __dt
    if job.t <= 0 then
      table.remove(_laterQueue, i)
      local ok, err = pcall(job.f)
    end
  end
  if tlen(_laterQueue) == 0 then _laterFrame:Hide() end
end)
local function RunLaterTactica(delay, fn)
  table.insert(_laterQueue, { t = math.max(0.01, delay or 0.01), f = fn })
  _laterFrame:Show()
end

local function Tactica_NormalizeAddonChannel(channel)
  local ch = string.upper(tostring(channel or ""))
  if ch == "RAID" or ch == "PARTY" or ch == "GUILD" or ch == "OFFICER" or ch == "BATTLEGROUND" then
    return ch
  end
  if ch == "RAID_LEADER" or ch == "RAID_WARNING" then return "RAID" end
  if ch == "PARTY_LEADER" then return "PARTY" end
  return nil
end

local function Tactica_BroadcastVersion(channel)
  local msg = "VER:" .. Tactica_GetVersion()
  local ch = Tactica_NormalizeAddonChannel(channel)
  if SendAddonMessage and ch then SendAddonMessage(TACTICA_PREFIX, msg, ch) end
end

local function Tactica_BroadcastVersionAll()
  local sent = false
  -- RAID
  if UnitInRaid and UnitInRaid("player") then
    if SendAddonMessage then SendAddonMessage(TACTICA_PREFIX, "TACTICA_VER:"..Tactica_GetVersion(), "RAID") end
    sent = true
  end
  -- PARTY (only if not in raid)
  if (not (UnitInRaid and UnitInRaid("player"))) and (GetNumPartyMembers and GetNumPartyMembers() > 0) then
    if SendAddonMessage then SendAddonMessage(TACTICA_PREFIX, "TACTICA_VER:"..Tactica_GetVersion(), "PARTY") end
    sent = true
  end
  -- GUILD
  if (IsInGuild and IsInGuild()) then
    if SendAddonMessage then SendAddonMessage(TACTICA_PREFIX, "TACTICA_VER:"..Tactica_GetVersion(), "GUILD") end
    sent = true
  end
  return sent
end

local function Tactica_OnAddonMessageVersion(prefix, text, sender, channel)
  if prefix ~= TACTICA_PREFIX then return end
  if type(text) ~= "string" then return end
  local mine = Tactica_GetVersion()
  -- Handle legacy "VER:" and new "TACTICA_VER:"
  if string.sub(text,1,4) == "VER:" then
    local other = string.sub(text, 5)
    if not _verNotifiedOnce and VersionIsNewer(mine, other) then
      _verNotifiedOnce = true
      RunLaterTactica(8, function()
        Tactica:PrintMessage(string.format("A newer Tactica is available (yours: %s, latest seen: %s). Consider updating.", tostring(mine), tostring(other)))
      end)
    end
    -- Echo version back on same channel so older clients hear newer versions
    local me = UnitName and UnitName("player") or nil
    if sender ~= me and channel then Tactica_BroadcastVersion(channel) end
    return
  end
  if string.sub(text,1,12) == "TACTICA_VER:" then
    local other = string.sub(text, 13)
    if not _verNotifiedOnce and VersionIsNewer(mine, other) then
      _verNotifiedOnce = true
      RunLaterTactica(8, function()
        Tactica:PrintMessage(string.format("A newer Tactica is available (yours: %s, latest seen: %s). Consider updating.", tostring(mine), tostring(other)))
      end)
    end
    -- Echo version back on same channel so older/newer clients hear it (rate-limited)
    local me = UnitName and UnitName("player") or nil
    if sender ~= me and channel then
      local now = (GetTime and GetTime()) or 0
      local ch = Tactica_NormalizeAddonChannel(channel)
      if ch and now - _verLastEcho > 10 then _verLastEcho = now; SendAddonMessage("TACTICA", "TACTICA_VER:"..tostring(mine), ch) end
    end
    return
  end
  if string.sub(text, 1, 12) == "TACTICA_WHO:" then
    local payload = string.sub(text, 13) or ""
    local _, _, requester, rid = string.find(payload, "^([^:]+)%:(.+)$")
    if requester and requester ~= "" and rid and rid ~= "" and channel then
      local msg = "TACTICA_ME:" .. tostring(requester) .. ":" .. tostring(rid) .. ":" .. tostring(mine)
      local ch = Tactica_NormalizeAddonChannel(channel)
      if SendAddonMessage and ch then SendAddonMessage(TACTICA_PREFIX, msg, ch) end
    end
    return
  end
  if string.sub(text,1,11) == "TACTICA_ME:" then
    local payload = string.sub(text, 12) or ""
    local _, _, requester, rid, ver = string.find(payload, "^([^:]+)%:([^:]+)%:(.*)$")
    local me = (UnitName and UnitName("player")) or ""
    if requester and requester == me and rid and _verWhoRid and rid == _verWhoRid then
      local relation = VersionIsNewer(mine, ver) and "older" or (VersionIsNewer(ver, mine) and "newer" or "equal")
      local frame = (DEFAULT_CHAT_FRAME or ChatFrame1)
      if frame then frame:AddMessage(string.format("|cff33ff99Tactica:|r %s has %s (you: %s) [%s]", tostring(sender or "?"), tostring(ver or "?"), tostring(mine), relation)) end
    end
    return
  end

  if not _verNotifiedOnce and VersionIsNewer(mine, other) then
    _verNotifiedOnce = true
    RunLaterTactica(8, function()
      Tactica:PrintMessage(string.format(
        "A newer Tactica is available (yours: %s, latest seen: %s). Consider updating.",
        tostring(mine), tostring(other)))
    end)
  end
end

local function Tactica_MaybePingGuild()
  if _verGuildAnnounced then return end
  _verGuildAnnounced = true
  RunLaterTactica(10, function() Tactica_BroadcastVersion("GUILD") end)
end

local function Tactica_MaybePingRaid()
  if _verRaidAnnounced then return end
  if not UnitInRaid or not UnitInRaid("player") then return end
  _verRaidAnnounced = true
  RunLaterTactica(3, function() Tactica_BroadcastVersion("RAID") end)
end

Tactica = {
    SavedVariablesVersion = 1,
    Data = {},
    DefaultData = {},
    addFrame = nil,
    postFrame = nil,
    selectedRaid = nil,
    selectedBoss = nil,
	AutoPostHintShown = false,
	    RecentlyPosted = {}
};

local TACTICA_TITLE_COLOR = "|cff33ff99"
local function SetGreenTitle(fs, text)
  if not fs then return end
  fs:SetText(TACTICA_TITLE_COLOR .. tostring(text or "") .. "|r")
end

Tactica.Aliases = {
    -- Raids
    ["mc"] = "Molten Core",
    ["bwl"] = "Blackwing Lair",
    ["zg"] = "Zul'Gurub",
	["za"] = "Zul'Aman",
    ["aq20"] = "Ruins of Ahn'Qiraj",
    ["aq40"] = "Temple of Ahn'Qiraj",
    ["ony"] = "Onyxia's Lair",
	["os"] = "Obsidian Sanctum"
    ["naxx"] = "Naxxramas",
    ["kara"] = "Karazhan",
    ["world"] = "World Bosses",

    -- Bosses
    ["rag"] = "Ragnaros",
    ["mag"] = "Magmadar",
    ["geddon"] = "Baron Geddon",
    ["shaz"] = "Shazzrah",
    ["sulfuron"] = "Sulfuron Harbinger",
    ["golemagg"] = "Golemagg the Incinerator",
    ["majordomo"] = "Majordomo Executus",
    ["razorgore"] = "Razorgore the Untamed",
    ["broodlord"] = "Broodlord Lashlayer",
    ["ebon"] = "Ebonroc",
    ["fire"] = "Firemaw",
    ["flame"] = "Flamegor",
    ["chrom"] = "Chromaggus",
    ["vael"] = "Vaelastrasz the Corrupt",
    ["nef"] = "Nefarian",
    ["venoxis"] = "High Priest Venoxis",
    ["mandokir"] = "Bloodlord Mandokir",
    ["jindo"] = "Jin'do the Hexxer",
    ["kur"] = "Kurinnaxx",
    ["rajaxx"] = "General Rajaxx",
    ["skeram"] = "The Prophet Skeram",
    ["cthun"] = "C'Thun",
    ["patch"] = "Patchwerk",
    ["thadd"] = "Thaddius",
    ["azu"] = "Azuregos",
    ["kazzak"] = "Lord Kazzak",
	["volchan"] = "Volchan",
}

if not UIDropDownMenu_CreateInfo then
    UIDropDownMenu_CreateInfo = function()
        return {}
    end
end
-------------------------------------------------
-- BOSS NAME ALIASES (multi-NPC → one boss, with hostility mode)
-------------------------------------------------
Tactica.BossNameAliases = {} -- [lower(aliasName)] = array of { raid="...", boss="...", when="hostile|friendly|any" }

function Tactica:RegisterBossAliases(raidName, bossName, aliases, when)
  if not raidName or not bossName or not aliases then return end
  local mode = when or "any"
  for i = 1, table.getn(aliases) do
    local alias = aliases[i]
    if alias and alias ~= "" then
      local key = string.lower(alias)
      if not Tactica.BossNameAliases[key] then Tactica.BossNameAliases[key] = {} end
      table.insert(Tactica.BossNameAliases[key], { raid = raidName, boss = bossName, when = mode })
    end
  end
end

-- ZG: Vilebranch Speaker (attack to trigger boss) → Bloodlord Mandokir
Tactica:RegisterBossAliases("Zul'Gurub", "Bloodlord Mandokir", {
  "Vilebranch Speaker",
}, "hostile")

-- MC: Majordomo Executus (friendly talk-to-summon) → Ragnaros
Tactica:RegisterBossAliases("Molten Core", "Ragnaros", {
  "Majordomo Executus",
}, "friendly")

-- BWL: Vaelastrasz (friendly talk-to-start) → Vaelastrasz
Tactica:RegisterBossAliases("Blackwing Lair", "Vaelastrasz the Corrupt", {
  "Vaelastrasz the Corrupt",
}, "friendly")

-- BWL: Lord Victor Nefarius (friendly talk-to-start) → Nefarian
Tactica:RegisterBossAliases("Blackwing Lair", "Nefarian", {
  "Lord Victor Nefarius",
}, "friendly")

-- AQ40: Princess Yauj, Vem, and Lord Kri (attack any) → Bug Trio
Tactica:RegisterBossAliases("Temple of Ahn'Qiraj", "Silithid Royalty (Bug Trio)", {
  "Princess Yauj","Vem","Lord Kri",
}, "hostile")

-- AQ40: Emperor Vek'lor and Emperor Vek'nilash (attack any) → Twin Emperors
Tactica:RegisterBossAliases("Temple of Ahn'Qiraj", "Twin Emperors", {
  "Emperor Vek'lor","Emperor Vek'nilash",
}, "hostile")

-- Naxx:  Thane Korth'azz, Lady Blaumeux, Sir Zeliek, and Highlord Mograine (attack any) → 4HM
Tactica:RegisterBossAliases("Naxxramas", "The Four Horsemen", {
  "Thane Korth'azz","Lady Blaumeux","Sir Zeliek","Highlord Mograine",
}, "hostile")

-------------------------------------------------
-- INITIALIZATION
-------------------------------------------------

-- Initialize the addon
local f = CreateFrame("Frame");
f:RegisterEvent("ADDON_LOADED");
f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("PLAYER_ENTERING_WORLD");
f:RegisterEvent("PLAYER_LOGOUT");
f:RegisterEvent("PLAYER_TARGET_CHANGED");
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("RAID_ROSTER_UPDATE")
local function InitializeSavedVariables()
    if not TacticaDB then
        TacticaDB = {
            version = Tactica.SavedVariablesVersion,
            CustomTactics = {},
            Healers = {},
            Settings = {
                UseRaidWarning = true,
                UseRaidChat = true,
                UsePartyChat = false,
                PopupScale = 1.0,
				AutoPostOnBoss = true,
				Loot = {
					AutoMasterLoot = true, 
					AutoGroupPopup = true, 
				},
                PostFrame = {
                    locked = false,
                    position = { point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = 0, y = 0 }
                }
            }
        }
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Tactica:|r Created new saved variables database.");
    else
        TacticaDB.version = TacticaDB.version or Tactica.SavedVariablesVersion
        TacticaDB.CustomTactics = TacticaDB.CustomTactics or {}
        TacticaDB.Healers = TacticaDB.Healers or {}
        TacticaDB.Settings = TacticaDB.Settings or {
            UseRaidWarning = true,
            UseRaidChat = true,
            UsePartyChat = false,
            PopupScale = 1.0,
            PostFrame = {
                locked = false,
                position = { point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = 0, y = 0 }
            }
        }
        TacticaDB.Settings.PostFrame = TacticaDB.Settings.PostFrame or {
            locked = false,
            position = { point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = 0, y = 0 }
        }
    end
	
		-- ensure Loot table and defaults exist
	TacticaDB.Settings.Loot = TacticaDB.Settings.Loot or {}
	if TacticaDB.Settings.Loot.AutoMasterLoot == nil then
		TacticaDB.Settings.Loot.AutoMasterLoot = true
	end
	if TacticaDB.Settings.Loot.AutoGroupPopup == nil then
		TacticaDB.Settings.Loot.AutoGroupPopup = true
	end

    -- Legacy migration block (kept as-is)
    if Tactica_SavedVariables then
		if Tactica_SavedVariables.CustomTactics then
			TacticaDB.CustomTactics = Tactica_SavedVariables.CustomTactics
		end
		if Tactica_SavedVariables.Settings then
			TacticaDB.Settings = Tactica_SavedVariables.Settings
		end
		Tactica_SavedVariables = nil
	end

	-- Ensure default exists for everyone (legacy or fresh)
	if TacticaDB and TacticaDB.Settings and TacticaDB.Settings.AutoPostOnBoss == nil then
		TacticaDB.Settings.AutoPostOnBoss = true
	end
	
	-- Ensure Settings table exists
	if not TacticaDB.Settings then TacticaDB.Settings = {} end

	-- Default: Auto-open Post UI on boss (ON)
	if TacticaDB.Settings.AutoPostOnBoss == nil then
	  TacticaDB.Settings.AutoPostOnBoss = true
	end


	-- Default: whisper confirmations on role change (ON)
	if TacticaDB.Settings.RoleWhisperEnabled == nil then
	  TacticaDB.Settings.RoleWhisperEnabled = true
	end

	-- Loot sub-table + defaults (both ON)
	if not TacticaDB.Settings.Loot then TacticaDB.Settings.Loot = {} end
	if TacticaDB.Settings.Loot.AutoMasterLoot == nil then
	  TacticaDB.Settings.Loot.AutoMasterLoot = true
	end
	if TacticaDB.Settings.Loot.AutoGroupPopup == nil then
	  TacticaDB.Settings.Loot.AutoGroupPopup = true
	end

		-- default: whisper a confirmation to the player whose role you change
	if not TacticaDB.Settings.RoleWhisperEnabled ~= false then
		-- keep it strictly boolean
	end
	if TacticaDB.Settings.RoleWhisperEnabled == nil then
		TacticaDB.Settings.RoleWhisperEnabled = true
	end
end

local TacticaExportFormatOptions = {
    { value = "name",             text = "Only Name",              header = "Player Name" },
    { value = "name_class",       text = "Name & Class",           header = "Player Name\tClass" },
    { value = "name_role",        text = "Name & Role",            header = "Player Name\tRole" },
    { value = "name_class_role",  text = "Name, Class & Role",     header = "Player Name\tClass\tRole" },
}

local function TacticaGetExportFormatOption(value)
    local _, opt
    for _, opt in ipairs(TacticaExportFormatOptions) do
        if opt.value == value then
            return opt
        end
    end
    return TacticaExportFormatOptions[4]
end

local function TacticaGetExportFormat()
    TacticaDB = TacticaDB or {}
    TacticaDB.Settings = TacticaDB.Settings or {}
    local opt = TacticaGetExportFormatOption(TacticaDB.Settings.ExportFormat)
    TacticaDB.Settings.ExportFormat = opt.value
    return opt
end

local TacticaExportLabelOptions = {
    { value = false, text = "No labels" },
    { value = true,  text = "Include labels" },
}

local function TacticaGetExportIncludeLabels()
    TacticaDB = TacticaDB or {}
    TacticaDB.Settings = TacticaDB.Settings or {}
    if TacticaDB.Settings.ExportIncludeLabels == nil then
        TacticaDB.Settings.ExportIncludeLabels = true
    end
    return (TacticaDB.Settings.ExportIncludeLabels == true)
end

local function TacticaGetExportLabelText(includeLabels)
    if includeLabels then
        return "Include labels"
    end
    return "No labels"
end

f:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "Tactica" then
        InitializeSavedVariables()
        RunLaterTactica(1, function()
		  local cf = DEFAULT_CHAT_FRAME or ChatFrame1
		  cf:AddMessage("|cff33ff99Tactica loaded.|r Use |cffffff00/tt|r or |cffffff00/tactica|r or |cffffff00minimap icon.|r")
		end)
    elseif event == "PLAYER_ENTERING_WORLD" then
    RunLaterTactica(10, function() Tactica_BroadcastVersionAll() end)

  elseif event == "RAID_ROSTER_UPDATE" then
    if not _verRaidAnnounced and UnitInRaid and UnitInRaid("player") then
      _verRaidAnnounced = true
      RunLaterTactica(3, function() Tactica_BroadcastVersionAll() end)
    end
  elseif event == "CHAT_MSG_ADDON" then
        -- Version traffic handling
        Tactica_OnAddonMessageVersion(arg1, arg2, arg4, arg3)

  elseif event == "PLAYER_LOGIN" then
        if not TacticaDB then
            InitializeSavedVariables()
        end
        Tactica:InitializeData();
        Tactica:CreateAddFrame();
        Tactica:CreatePostFrame();
    elseif event == "PLAYER_LOGOUT" then
        if TacticaDB then
            Tactica:SavePostFramePosition()
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        Tactica:HandleTargetChange()
    end
end);

-- Slash commands
SLASH_TACTICA1 = "/tactica";
SLASH_TACTICA2 = "/tt";
SlashCmdList["TACTICA"] = function(msg)
    Tactica:CommandHandler(msg);
end

SLASH_TTPUSH1 = "/ttpush"
SlashCmdList["TTPUSH"] = function()
    Tactica:CommandHandler("pushroles")
end

SLASH_TTCLEAR1 = "/ttclear"
SlashCmdList["TTCLEAR"] = function()
    Tactica:CommandHandler("clearroles")
end

function Tactica:HandleTargetChange()
    -- Clear recently posted if player died (wipe detection)
    if UnitIsDead("player") then
        if type(wipe)=="function" then wipe(self.RecentlyPosted) else for k in pairs(self.RecentlyPosted) do self.RecentlyPosted[k]=nil end end
        return
    end
    
    -- Check all conditions for auto-posting
    if not self:CanAutoPost() then
        return
    end
    
    local raidName, bossName = self:IsBossTarget()
    if not raidName or not bossName then
        return
    end
	
	-- If enabled, let the loot module flip Master Loot when boss is targeted
	if TacticaDB and TacticaDB.Settings and TacticaDB.Settings.Loot and TacticaDB.Settings.Loot.AutoMasterLoot then
		if TacticaLoot_OnBossTargeted then
			TacticaLoot_OnBossTargeted(raidName, bossName)
		end
	end

    
	    -- Respect user setting to disable auto-popup, but show a one-time hint
    if TacticaDB and TacticaDB.Settings and TacticaDB.Settings.AutoPostOnBoss == false then
        if not Tactica.AutoPostHintShown then
            Tactica.AutoPostHintShown = true
            self:PrintMessage("Auto-popup is off — use '/tt post' or '/tt autopost' to enable it again.")
        end
        return
    end

    -- Check if already posted for this boss recently
    local key = raidName..":"..bossName
    if self.RecentlyPosted[key] then
        return
    end
    
    -- Mark as posted
    self.RecentlyPosted[key] = true
    
    -- Set the selected raid and boss
    self.selectedRaid = raidName
    self.selectedBoss = bossName
    
    if not self.postFrame then
        self:CreatePostFrame()
    end
    
    -- Show the frame and force update both dropdowns
    self.postFrame:Show()
    UIDropDownMenu_SetText(TacticaPostRaidDropdown, raidName)
    UIDropDownMenu_SetText(TacticaPostBossDropdown, bossName)
    self:UpdatePostTacticDropdown(raidName, bossName)
end

function Tactica:IsBossTarget()
  if not UnitExists("target") or UnitIsDead("target") then
    return nil, nil
  end

  local targetName = UnitName("target")
  if not targetName or targetName == "" then
    return nil, nil
  end

  -- Determine friendliness/hostility
  local isHostile = UnitCanAttack and UnitCanAttack("player", "target")
  -- Treat "friendly" as "not hostile" for the purpose
  local isFriendly = not isHostile

  local lname = string.lower(targetName)

  -- Alias match with conditional "when"
  local entries = Tactica.BossNameAliases[lname]
  if entries then
    for i = 1, table.getn(entries) do
      local e = entries[i]
      local ok = (e.when == "any")
                or (e.when == "hostile"  and isHostile)
                or (e.when == "friendly" and isFriendly)
      if ok then
        local raidBlock = self.Data[e.raid]
        if raidBlock and raidBlock[e.boss] then
          return e.raid, e.boss
        end
      end
    end
  end

  -- Direct boss-name match requires hostile (avoid false positives on friendlies)
  if not isHostile then
    return nil, nil
  end

  for raidName, bosses in pairs(self.Data) do
    for bossName in pairs(bosses) do
      if string.lower(bossName) == lname then
        return raidName, bossName
      end
    end
  end

  return nil, nil
end

function Tactica:CanAutoPost()
    -- Check basic conditions
    if UnitIsDead("player") or UnitAffectingCombat("player") then
        return false
    end
    
    -- Check raid status
    if not UnitInRaid("player") then
        return false
    end
    
    -- Check raid leader/assist status
    local isLeader, isAssist = false, false
    
    -- Get player name for comparison
    local playerName = UnitName("player")
    
    -- Check raid status for all members
    for i = 1, 40 do
        local name, rank = GetRaidRosterInfo(i)
        if name and name == playerName then
            -- Rank 2 is leader, rank 1 is assist
            isLeader = (rank == 2)
            isAssist = (rank == 1)
            break
        end
    end
    
    if not (isLeader or isAssist) then
        return false
    end
    
    return true
end

function Tactica:InitializeData()
    -- Initialize empty data tables
    self.Data = {}
    TacticaDB.CustomTactics = TacticaDB.CustomTactics or {}
    
    -- First load all default data
    for raidName, bosses in pairs(self.DefaultData) do
        self.Data[raidName] = self.Data[raidName] or {}
        for bossName, tactics in pairs(bosses) do
            self.Data[raidName][bossName] = self.Data[raidName][bossName] or {}
            for tacticName, text in pairs(tactics) do
                self.Data[raidName][bossName][tacticName] = text
            end
        end
    end
    
    -- Then merge all custom tactics
    for raidName, bosses in pairs(TacticaDB.CustomTactics) do
        self.Data[raidName] = self.Data[raidName] or {}
        for bossName, tactics in pairs(bosses) do
            self.Data[raidName][bossName] = self.Data[raidName][bossName] or {}
            for tacticName, text in pairs(tactics) do
                if text and text ~= "" then
                    self.Data[raidName][bossName][tacticName] = text
                end
            end
        end
    end
end

function Tactica:CommandHandler(msg)
    local args = self:GetArgs(msg)
    local command = string.lower(args[1] or "")

    if command == "" then
        self:PrintHelp()
        return
    elseif command == "help" then
        self:PrintHelp()
        return
    elseif command == "list" then
        self:ListAvailableTactics()

    elseif command == "add" then
        self:ShowAddPopup()

    elseif command == "remove" then
        self:ShowRemovePopup()

    elseif command == "post" then
        self:ShowPostPopup(true)

	elseif command == "build" then
	  if TacticaRaidBuilder and TacticaRaidBuilder.Open then
		TacticaRaidBuilder.Open()
	  else
		self:PrintError("Raid Builder module not loaded.")
	  end
	  return

	elseif command == "autoinvite" then
	  if TacticaInvite and TacticaInvite.Open then
		TacticaInvite.Open()
	  else
		self:PrintError("Auto-Invite module not loaded.")
	  end
	  return

	elseif command == "comp" or command == "composition" then
	  if TacticaComposition and TacticaComposition.Open then
		TacticaComposition:Open()
	  else
		self:PrintError("Composition module not loaded.")
	  end
	  return

	elseif command == "lfm" then
	  if TacticaRaidBuilder and TacticaRaidBuilder.AnnounceOnce then TacticaRaidBuilder.AnnounceOnce() end

    elseif command == "autopost" then
		-- toggle only
		TacticaDB.Settings.AutoPostOnBoss = not TacticaDB.Settings.AutoPostOnBoss
		if TacticaDB.Settings.AutoPostOnBoss then
			Tactica.AutoPostHintShown = false
			self:PrintMessage("Auto-popup is |cff00ff00ON|r. It will open on boss targets.")
		else
			self:PrintMessage("Auto-popup is |cffff5555OFF|r. Use '/tt post' or '/tt autopost' to enable.")
		end
	
	elseif command == "options" then
		self:ShowOptionsFrame()

	elseif command == "roles" or command == "role" then
        self:PostRoleSummary()

	elseif command == "export" or command == "exportroles" then
        self:ShowExportRolesFrame()

	elseif command == "rolewhisper" then
		if not TacticaDB or not TacticaDB.Settings then return end
		TacticaDB.Settings.RoleWhisperEnabled = not TacticaDB.Settings.RoleWhisperEnabled
		if TacticaDB.Settings.RoleWhisperEnabled then
			self:PrintMessage("Role-whisper is |cff00ff00ON|r. Players get a whisper when you set/clear their role.")
		else
			self:PrintMessage("Role-whisper is |cffff5555OFF|r.")
		end

    elseif command == "pushroles" then
        if TacticaRaidRoles_PushRoles then
            TacticaRaidRoles_PushRoles(false)
        else
            self:PrintError("Raid roles module not loaded.")
        end

    elseif command == "clearroles" then
        if TacticaRaidRoles_ClearAllRoles then
            TacticaRaidRoles_ClearAllRoles(false)
        else
            self:PrintError("Raid roles module not loaded.")
        end

    else
        -- Handle direct commands like "/tt mc,rag"
        if not self:CanAutoPost() then
            self:PrintError("You must be a raid leader or assist to post tactics.")
            return
        end

        local raidNameRaw = table.remove(args, 1)
        local bossNameRaw = table.remove(args, 1)
        local tacticName = table.concat(args, ",")

        local raidName = self:ResolveAlias(raidNameRaw)
        local bossName = self:ResolveAlias(bossNameRaw)

        if not (raidName and bossName) then
            self:PrintError("Invalid format. Use /tt help")
            return
        end

        self:PostTactic(raidName, bossName, tacticName)
    end
end

function Tactica:PostTactic(raidName, bossName, tacticName)
    local tacticText = self:FindTactic(raidName, bossName, tacticName);
    
    if type(tacticText) == "string" and string.find(tacticText, "%S") then
        if TacticaDB.Settings.UseRaidWarning then
            SendChatMessage("[TACTICA] "..string.upper(bossName or "DEFAULT").." STRATEGY (read chat):", "RAID_WARNING");
        end
        
		-- only post to raid
		local chatType = "RAID"

        for line in string.gmatch(tacticText, "([^\n]+)") do
            SendChatMessage(line, chatType);
        end
    elseif type(tacticText) == "string" then
        self:PrintMessage("Tactic is empty until released.")
    else
        self:PrintError("Tactic not found. Use /tt list to see available tactics.");
    end
end

function Tactica:PostTacticToSelf(raidName, bossName, tacticName)
    local tacticText = self:FindTactic(raidName, bossName, tacticName)
    if type(tacticText) == "string" and string.find(tacticText, "%S") then
        local f = DEFAULT_CHAT_FRAME or ChatFrame1
        f:AddMessage("|cff33ff99[Tactica] (Self):|r " .. string.upper(bossName or "DEFAULT") .. " STRATEGY:")
        for line in string.gmatch(tacticText, "([^\n]+)") do
            f:AddMessage(line)
        end
    elseif type(tacticText) == "string" then
        self:PrintMessage("Tactic is empty until released.")
    else
        self:PrintError("Tactic not found. Use /tt list to see available tactics.")
    end
end

function Tactica:FindTactic(raidName, bossName, tacticName)
    if not raidName or not bossName then return nil end
    
    raidName = self:StandardizeName(raidName)
    bossName = self:StandardizeName(bossName)
    tacticName = tacticName and self:StandardizeName(tacticName) or nil
    
    -- First check if specific tactic was requested
    if tacticName and tacticName ~= "" then
        -- Check both custom and default data regardless
        local sources = {TacticaDB.CustomTactics, self.DefaultData}
        for _, source in ipairs(sources) do
            if source[raidName] and 
               source[raidName][bossName] and
               source[raidName][bossName][tacticName] then
                return source[raidName][bossName][tacticName]
            end
        end
    else
        -- No specific tactic requested, return first available
        -- Check custom first, then default
        local sources = {TacticaDB.CustomTactics, self.DefaultData}
        for _, source in ipairs(sources) do
            if source[raidName] and source[raidName][bossName] then
                local sawEmpty = false
                for _, text in pairs(source[raidName][bossName]) do
                    if text and text ~= "" then
                        return text
                    elseif type(text) == "string" then
                        sawEmpty = true
                    end
                end
                if sawEmpty then return "" end
            end
        end
    end
    
    return nil
end

function Tactica:AddTactic(raidName, bossName, tacticName, tacticText)
    raidName = self:StandardizeName(raidName);
    bossName = self:StandardizeName(bossName);
    tacticName = self:StandardizeName(tacticName);
    
    if not tacticText or tacticText == "" then
        self:PrintError("Tactic text cannot be empty.");
        return false;
    end
    
    -- Initialize tables if they don't exist
    TacticaDB.CustomTactics[raidName] = TacticaDB.CustomTactics[raidName] or {};
    TacticaDB.CustomTactics[raidName][bossName] = TacticaDB.CustomTactics[raidName][bossName] or {};
    
    -- Save the tactic
    TacticaDB.CustomTactics[raidName][bossName][tacticName] = tacticText;
    
    -- Update the in-memory data
    self.Data[raidName] = self.Data[raidName] or {};
    self.Data[raidName][bossName] = self.Data[raidName][bossName] or {};
    self.Data[raidName][bossName][tacticName] = tacticText;
    
    return true;
end

function Tactica:RemoveTactic(raidName, bossName, tacticName)
    raidName = self:StandardizeName(raidName)
    bossName = self:StandardizeName(bossName)
    tacticName = self:StandardizeName(tacticName)
    
    if not (raidName and bossName and tacticName) then
        self:PrintError("Invalid raid, boss, or tactic name")
        return false
    end
    
    if not (TacticaDB.CustomTactics[raidName] and 
            TacticaDB.CustomTactics[raidName][bossName] and 
            TacticaDB.CustomTactics[raidName][bossName][tacticName]) then
        self:PrintError("Custom tactic not found")
        return false
    end
    
    -- Remove the tactic
    TacticaDB.CustomTactics[raidName][bossName][tacticName] = nil
    
    -- Clean up empty tables
    if next(TacticaDB.CustomTactics[raidName][bossName]) == nil then
        TacticaDB.CustomTactics[raidName][bossName] = nil
    end
    
    if next(TacticaDB.CustomTactics[raidName]) == nil then
        TacticaDB.CustomTactics[raidName] = nil
    end
    
    -- Update in-memory data
    if self.Data[raidName] and self.Data[raidName][bossName] then
        self.Data[raidName][bossName][tacticName] = nil
    end
    
    return true
end

-- Post Frame Lock/Position Handling
function Tactica:SavePostFramePosition()
  if not self.postFrame then return end
  if not TacticaDB then TacticaDB = {} end
  TacticaDB.Settings = TacticaDB.Settings or {}
  TacticaDB.Settings.PostFrame = TacticaDB.Settings.PostFrame or {}

  local point, _, relativePoint, x, y = self.postFrame:GetPoint(1)
  TacticaDB.Settings.PostFrame.position = {
    point = point or "CENTER",
    relativeTo = "UIParent",
    relativePoint = relativePoint or point or "CENTER",
    x = x or 0,
    y = y or 0,
  }
  TacticaDB.Settings.PostFrame.locked = (self.postFrame.locked == true)
end

function Tactica:RestorePostFramePosition()
  if not self.postFrame then return end
  if not (TacticaDB and TacticaDB.Settings and TacticaDB.Settings.PostFrame) then
    self.postFrame:ClearAllPoints()
    self.postFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    return
  end
  local pf = TacticaDB.Settings.PostFrame
  local p  = pf.position or {}
  self.postFrame:ClearAllPoints()
  if p.point then
    self.postFrame:SetPoint(p.point, UIParent, p.relativePoint or p.point, p.x or 0, p.y or 0)
  else
    self.postFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
  self.postFrame.locked = (pf.locked == true)
end

function Tactica:StringsEqual(a, b)
    return a and b and string.lower(tostring(a)) == string.lower(tostring(b));
end

local function IsReservedBossField(name)
    return name == "Loot table"
end

function Tactica:StandardizeName(name)
    if not name or name == "" then return "" end
    
    -- Special case for "default" tactic
    if string.lower(name) == "default" then
        return "Default"
    end
    
    -- First check if it matches any aliases exactly (case insensitive)
    local lowerName = string.lower(name)
    for alias, properName in pairs(self.Aliases) do
        if string.lower(alias) == lowerName then
            return properName
        end
    end
    
    -- For custom data, use simple capitalization (first letter only)
    if TacticaDB.CustomTactics then
        -- Check raid names
        for raidName in pairs(TacticaDB.CustomTactics) do
            if string.lower(raidName) == lowerName then
                return raidName
            end
            -- Check boss names
            if TacticaDB.CustomTactics[raidName] then
                for bossName in pairs(TacticaDB.CustomTactics[raidName]) do
                    if string.lower(bossName) == lowerName then
                        return bossName
                    end
                    -- Check tactic names
                    if TacticaDB.CustomTactics[raidName][bossName] then
                        for tacticName in pairs(TacticaDB.CustomTactics[raidName][bossName]) do
                            if string.lower(tacticName) == lowerName then
                                return tacticName
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- For default data, use proper capitalization from DefaultData
    for raidName, bosses in pairs(self.DefaultData) do
        if string.lower(raidName) == lowerName then
            return raidName
        end
        for bossName in pairs(bosses) do
            if string.lower(bossName) == lowerName then
                return bossName
            end
            for tacticName in pairs(bosses[bossName]) do
                if not IsReservedBossField(tacticName) and string.lower(tacticName) == lowerName then
                    return tacticName
                end
            end
        end
    end
    
    -- Fallback: simple capitalization if not found anywhere
    return string.gsub(string.lower(name), "^%l", string.upper)
end

function Tactica:GetArgs(str)
    local args = {};
    if not str or str == "" then return args end

    for arg in string.gmatch(str, "([^,]+)") do
        local trimmed = string.gsub(arg, "^%s*(.-)%s*$", "%1")
        table.insert(args, trimmed)
    end

    return args;
end

function Tactica:ResolveAlias(input)
    if not input then return nil end
    local key = string.lower(string.gsub(input, "^%s*(.-)%s*$", "%1"))
    return self.Aliases[key] or input
end

function Tactica:PrintHelp()
    self:PrintMessage("Tactica Commands:");
	self:PrintMessage("  |cffffff78/tt build|r (tool for auto creating raids)")
	self:PrintMessage("  |cffffff78/tt lfm|r (announce current /tt build msg)")
	self:PrintMessage("  |cffffff78/tt autoinvite|r or |cffffff78/ttai|r (standalone keyword auto-invite)")
    self:PrintMessage("  |cffffff00/tt post|r (popup to select and post a tactic)");
	self:PrintMessage("  |cffffff00/tt <Raid>,<Boss>,[Tactic]|r (post a tactic via command - for macros)");
    self:PrintMessage("  |cffffff00/tt add|r (add custom tactics)");
    self:PrintMessage("  |cffffff00/tt remove|r (remove a custom tactic)");
    self:PrintMessage("  |cffffff00/tt list|r (lists all available tactics)");
	self:PrintMessage("  |cffffff00/tt autopost|r (toggle the auto boss-popup");
	self:PrintMessage("  |cffffff00/ttpush|r or |cffffff00/tt pushroles|r (push role assignments manually)");
	self:PrintMessage("  |cffffff00/ttclear|r or |cffffff00/tt clearroles|r (clear role assignments manually)");
	self:PrintMessage("  |cffffff00/tt rolewhisper|r (toggle whisper role confirmation)")
	self:PrintMessage("  |cffffff00/tt roles|r (post Tanks/Healers/DPS to raid)")
	self:PrintMessage("  |cffffff00/tt export|r (export roster as copyable CSV)")
	self:PrintMessage("  |cffffff00/tt options|r (small options panel for toggles)")
	self:PrintMessage("  |cffffff78/tt comp|r or |cffffff78/tt composition|r (open composition tool)")
	self:PrintMessage("  |cffffff00/w Doite|r (addon and tactics by Doite)");
end

function Tactica:ListAvailableTactics()
    -- Combine default and custom data for listing
    local combinedData = {};
    
    -- Copy default data
    for raidName, bosses in pairs(self.DefaultData) do
        combinedData[raidName] = combinedData[raidName] or {};
        for bossName, tactics in pairs(bosses) do
            combinedData[raidName][bossName] = combinedData[raidName][bossName] or {};
            for tacticName, text in pairs(tactics) do
                combinedData[raidName][bossName][tacticName] = text;
            end
        end
    end
    
    -- Merge custom data
    for raidName, bosses in pairs(TacticaDB.CustomTactics or {}) do
        combinedData[raidName] = combinedData[raidName] or {};
        for bossName, tactics in pairs(bosses) do
            combinedData[raidName][bossName] = combinedData[raidName][bossName] or {};
            for tacticName, text in pairs(tactics) do
                combinedData[raidName][bossName][tacticName] = text;
            end
        end
    end
    
    -- Display the combined list
    self:PrintMessage("Available Tactics:");
    
    local count = 0;
    for raidName, bosses in pairs(combinedData) do
        if bosses and next(bosses) then
            self:PrintMessage("|cff00ff00"..raidName.."|r");
            for bossName, tactics in pairs(bosses) do
                if tactics and next(tactics) then
                    self:PrintMessage("  |cff00ffff"..bossName.."|r");
                    for tacticName in pairs(tactics) do
                        if tacticName ~= "Default" and not IsReservedBossField(tacticName) then
                            self:PrintMessage("    - "..tacticName);
                            count = count + 1;
                        end
                    end
                end
            end
        end
    end
    
    if count == 0 then
        self:PrintMessage("No custom tactics found (only default). Add some with /tt add");
    else
        self:PrintMessage(string.format("Total: %d custom tactics available.", count));
    end
end

function Tactica:PrintMessage(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Tactica:|r "..msg);
end

function Tactica:PrintError(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Tactica Error:|r "..msg);
end

-- Posts a role summary to RAID: Tanks / Healers / DPS (DPS = the rest of the raid)
function Tactica:PostRoleSummary()
    if not (UnitInRaid and UnitInRaid("player")) then
        self:PrintError("You must be in a raid.")
        return
    end

    local total = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    local tanks, healers = {}, {}

    local T = (TacticaDB and TacticaDB.Tanks)   or {}
    local H = (TacticaDB and TacticaDB.Healers) or {}

    -- collect current raid members with T/H marks
    for i = 1, total do
        local name = GetRaidRosterInfo(i)
        if name and name ~= "" then
            if T[name] then
                table.insert(tanks, name)
            elseif H[name] then
                table.insert(healers, name)
            end
        end
    end

    -- sort names (case-insensitive)
    table.sort(tanks,   function(a,b) return string.lower(a) < string.lower(b) end)
    table.sort(healers, function(a,b) return string.lower(a) < string.lower(b) end)

    -- print helper (wraps if too long)
    local function postNames(label, list)
        local cnt  = (table.getn and table.getn(list)) or 0
        local base = string.format("[Tactica]: %s - [%d]: ", label, cnt)
        local cur  = base
        local n    = (table.getn and table.getn(list)) or 0

        for idx = 1, n do
            local piece = (idx > 1 and ", " or "") .. list[idx]
            if string.len(cur) + string.len(piece) > 230 then
                SendChatMessage(cur, "RAID")
                cur = "    " .. list[idx]
            else
                cur = cur .. piece
            end
        end
        SendChatMessage(cur, "RAID")
    end

    postNames("Tanks",   tanks)
    postNames("Healers", healers)

    -- DPS = everyone not marked T/H (don’t list names; just the count)
    local nT       = (table.getn and table.getn(tanks))   or 0
    local nH       = (table.getn and table.getn(healers)) or 0
    local dpsTotal = total - nT - nH
    if dpsTotal < 0 then dpsTotal = 0 end

    local line = string.format("[Tactica]: DPS - [%d]: The rest of the raid.", dpsTotal)
    SendChatMessage(line, "RAID")
end

--- Shows a copyable CSV export of the raid roster with roles
function Tactica:ShowExportRolesFrame()
    if not (UnitInRaid and UnitInRaid("player")) then
        self:PrintError("You must be in a raid.")
        return
    end

    local function FillExportData()
        local formatOpt = TacticaGetExportFormat()

        -- Generate TSV data (tab-separated for Google Sheets)
        local includeLabels = TacticaGetExportIncludeLabels()
        local tsvLines = {}
        if includeLabels then
            table.insert(tsvLines, formatOpt.header)
        end
        local total = (GetNumRaidMembers and GetNumRaidMembers()) or 0
        local T = (TacticaDB and TacticaDB.Tanks) or {}
        local H = (TacticaDB and TacticaDB.Healers) or {}
        local D = (TacticaDB and TacticaDB.DPS) or {}

        -- Collect all raid members with their class and role
        local raidData = {}
        local i
        for i = 1, total do
            local name, _, _, _, class = GetRaidRosterInfo(i)
            if name and name ~= "" then
                local role = "DPS"
                if T[name] then
                    role = "Tank"
                elseif H[name] then
                    role = "Healer"
                elseif D[name] then
                    role = "DPS"
                end

                table.insert(raidData, {name = name, class = class or "Unknown", role = role})
            end
        end

        -- Sort by role (Tank > Healer > DPS), then by name
        table.sort(raidData, function(a, b)
            local roleOrder = {Tank = 1, Healer = 2, DPS = 3}
            local aOrder = roleOrder[a.role] or 4
            local bOrder = roleOrder[b.role] or 4
            if aOrder ~= bOrder then
                return aOrder < bOrder
            else
                return string.lower(a.name) < string.lower(b.name)
            end
        end)

        local _, entry
        for _, entry in ipairs(raidData) do
            local row
            if formatOpt.value == "name" then
                row = entry.name
            elseif formatOpt.value == "name_class" then
                row = string.format("%s\t%s", entry.name, entry.class)
            elseif formatOpt.value == "name_role" then
                row = string.format("%s\t%s", entry.name, entry.role)
            else
                row = string.format("%s\t%s\t%s", entry.name, entry.class, entry.role)
            end
            table.insert(tsvLines, row)
        end

        local tsvText = table.concat(tsvLines, "\n")
        self.exportEditBox:SetText(tsvText)
        self.exportEditBox:HighlightText()
        self.exportEditBox:SetFocus()
    end

    -- Create frame if it doesn't exist
    if not self.exportFrame then
        local f = CreateFrame("Frame", "TacticaExportFrame", UIParent)
        f:SetWidth(450)
        f:SetHeight(400)
        f:SetPoint("CENTER", UIParent, "CENTER")
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 }
        })
        f:SetBackdropColor(0, 0, 0, 1)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function() this:StartMoving() end)
        f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

        -- Title
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -20)
        title:SetJustifyH("LEFT")
        title:SetText("Tactica - Export Raid Roster")

        -- Instructions
        local instructions = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        instructions:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -45)
        instructions:SetJustifyH("LEFT")
        instructions:SetText("Select all (Ctrl+A) and copy (Ctrl+C) to clipboard:")

        -- Scroll frame for the EditBox
        local scrollFrame = CreateFrame("ScrollFrame", "TacticaExportScrollFrame", f, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -70)
        scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -35, 50)

        -- Background for scroll area
        local bg = CreateFrame("Frame", nil, f)
        bg:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", -5, 5)
        bg:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", 5, -5)
        bg:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        bg:SetBackdropColor(0, 0, 0, 0.5)

        -- The multiline EditBox
        local editBox = CreateFrame("EditBox", "TacticaExportEditBox", scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(false)
        editBox:SetFontObject("ChatFontNormal")
        editBox:SetWidth(380)
        editBox:SetHeight(1000)
        editBox:SetMaxLetters(0)
        editBox:SetScript("OnEscapePressed", function() f:Hide() end)
        scrollFrame:SetScrollChild(editBox)

        -- Top-right close button (X)
        local closeButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -10)

        -- Output format dropdown row
        local outputLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        outputLabel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 23)
        outputLabel:SetText("Output:")

        local outputDrop = CreateFrame("Frame", "TacticaExportOutputDropdown", f, "UIDropDownMenuTemplate")
        outputDrop:SetPoint("LEFT", outputLabel, "RIGHT", -10, 0)
        UIDropDownMenu_SetWidth(outputDrop, 145)

        UIDropDownMenu_Initialize(outputDrop, function()
            local _, opt
            for _, opt in ipairs(TacticaExportFormatOptions) do
                UIDropDownMenu_AddButton({
                    text = opt.text,
                    value = opt.value,
                    checked = (TacticaGetExportFormat().value == opt.value),
                    func = function()
                        local picked = this and this.value or opt.value
                        local selectedOpt = TacticaGetExportFormatOption(picked)
                        TacticaDB.Settings.ExportFormat = selectedOpt.value
                        UIDropDownMenu_SetText(outputDrop, selectedOpt.text)
                        FillExportData()
                        CloseDropDownMenus()
                    end
                })
            end
        end)

        local labelsLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        labelsLabel:SetPoint("LEFT", outputDrop, "RIGHT", -2, 0)
        labelsLabel:SetText("Label:")

        local labelsDrop = CreateFrame("Frame", "TacticaExportLabelsDropdown", f, "UIDropDownMenuTemplate")
        labelsDrop:SetPoint("LEFT", labelsLabel, "RIGHT", -10, 0)
        UIDropDownMenu_SetWidth(labelsDrop, 120)

        UIDropDownMenu_Initialize(labelsDrop, function()
            local _, opt
            for _, opt in ipairs(TacticaExportLabelOptions) do
                UIDropDownMenu_AddButton({
                    text = opt.text,
                    value = opt.value,
                    checked = (TacticaGetExportIncludeLabels() == opt.value),
                    func = function()
                        local picked = this and this.value
                        if picked == nil then picked = opt.value end
                        TacticaDB.Settings.ExportIncludeLabels = (picked == true)
                        UIDropDownMenu_SetText(labelsDrop, TacticaGetExportLabelText(TacticaDB.Settings.ExportIncludeLabels))
                        FillExportData()
                        CloseDropDownMenus()
                    end
                })
            end
        end)

        self.exportFrame = f
        self.exportEditBox = editBox
        self.exportOutputDropdown = outputDrop
        self.exportLabelsDropdown = labelsDrop
    end

    local currentOpt = TacticaGetExportFormat()
    UIDropDownMenu_SetText(self.exportOutputDropdown, currentOpt.text)
    UIDropDownMenu_SetText(self.exportLabelsDropdown, TacticaGetExportLabelText(TacticaGetExportIncludeLabels()))
    FillExportData()

    -- Show the frame
    self.exportFrame:Show()

    self:PrintMessage("Raid roster exported. Press Ctrl+A to select all, then Ctrl+C to copy.")
end

-------------------------------------------------
-- ADD OPTION UI
-------------------------------------------------

-- Helper: tint/untint the gear icon while Options is visible
local function Tactica_SetOptionsButtonActive(active)
  local btn = Tactica and Tactica.optionsButton
  if not btn then return end
  local nt = btn:GetNormalTexture()
  local pt = btn.GetPushedTexture and btn:GetPushedTexture() or nil

  if active then
    -- grey while options are open
    -- (tweak 0.6..0.8 for lighter/darker grey)
    if nt then nt:SetVertexColor(0.7, 0.7, 0.7) end
    if pt then pt:SetVertexColor(0.7, 0.7, 0.7) end
  else
    -- back to normal
    if nt then nt:SetVertexColor(1, 1, 1) end
    if pt then pt:SetVertexColor(1, 1, 1) end
  end
end

function Tactica:ShowOptionsFrame()
  if self.optionsFrame then
    self.optionsFrame:Show()
    if self.RefreshOptionsFrame then self:RefreshOptionsFrame() end
    return
  end

  local f = CreateFrame("Frame", "TacticaOptionsFrame", UIParent)
  f:SetWidth(235); f:SetHeight(145)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 32,
    insets = { left=11, right=12, top=12, bottom=11 }
  })
	f:SetBackdropColor(0, 0, 0, 1)
	f:SetBackdropBorderColor(1, 1, 1, 1)
	f:SetFrameStrata("DIALOG")

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", f, "TOP", 0, -12)
  SetGreenTitle(title, "Tactica Options")

  -- helper to build one checkbox + label, and return the checkbox
  local function mkcb(name, y, text)
    local cb = CreateFrame("CheckButton", name, f, "UICheckButtonTemplate")
    cb:SetWidth(24); cb:SetHeight(24)
    cb:SetPoint("TOPLEFT", f, "TOPLEFT", 12, y)
    local label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    label:SetText(text)
    return cb
  end

  -- create all checkboxes and keep references - can refresh them
  f.cbAutoPost    = mkcb("TacticaOptAutoPost",    -28, "Auto-open Post UI on boss")
  f.cbAutoML      = mkcb("TacticaOptAutoML",      -48, "Auto Master Loot on boss (RL)")
  f.cbAutoGroup   = mkcb("TacticaOptAutoGroup",   -68, "Loot popup after boss (RL)")
  f.cbRoleWhisper = mkcb("TacticaOptRoleWhisper", -88, "Whisper role confirmations")

  -- wire click handlers
  f.cbAutoPost:SetScript("OnClick", function()
    if not (TacticaDB and TacticaDB.Settings) then return end
    TacticaDB.Settings.AutoPostOnBoss = this:GetChecked() and true or false
    if TacticaDB.Settings.AutoPostOnBoss then
      Tactica.AutoPostHintShown = false
      Tactica:PrintMessage("Auto-popup is |cff00ff00ON|r. It will open on boss targets.")
    else
      Tactica:PrintMessage("Auto-popup is |cffff5555OFF|r. Use '/tt post' or '/tt autopost' to enable.")
    end
  end)

  f.cbAutoML:SetScript("OnClick", function()
    if not (TacticaDB and TacticaDB.Settings) then return end
    TacticaDB.Settings.Loot = TacticaDB.Settings.Loot or {}
    TacticaDB.Settings.Loot.AutoMasterLoot = this:GetChecked() and true or false
    if TacticaDB.Settings.Loot.AutoMasterLoot then
      Tactica:PrintMessage("Auto Master Loot is |cff00ff00ON|r.")
    else
      Tactica:PrintMessage("Auto Master Loot is |cffff5555OFF|r.")
    end
  end)

  f.cbAutoGroup:SetScript("OnClick", function()
    if not (TacticaDB and TacticaDB.Settings) then return end
    TacticaDB.Settings.Loot = TacticaDB.Settings.Loot or {}
    TacticaDB.Settings.Loot.AutoGroupPopup = this:GetChecked() and true or false
    if TacticaDB.Settings.Loot.AutoGroupPopup then
      Tactica:PrintMessage("Group Loot popup is |cff00ff00ON|r.")
    else
      Tactica:PrintMessage("Group Loot popup is |cffff5555OFF|r.")
    end
  end)

  f.cbRoleWhisper:SetScript("OnClick", function()
    if not (TacticaDB and TacticaDB.Settings) then return end
    TacticaDB.Settings.RoleWhisperEnabled = this:GetChecked() and true or false
    if TacticaDB.Settings.RoleWhisperEnabled then
      Tactica:PrintMessage("Role-whisper is |cff00ff00ON|r.")
    else
      Tactica:PrintMessage("Role-whisper is |cffff5555OFF|r.")
    end
  end)

  -- initial sync on first open
  if not TacticaDB then TacticaDB = {} end
  if not TacticaDB.Settings then TacticaDB.Settings = {} end
  if not TacticaDB.Settings.Loot then TacticaDB.Settings.Loot = {} end
  local S = TacticaDB.Settings
  local L = S.Loot
  if f.cbAutoPost    then f.cbAutoPost:SetChecked(S.AutoPostOnBoss ~= false) end
  if f.cbAutoML      then f.cbAutoML:SetChecked(L.AutoMasterLoot and true or false) end
  if f.cbAutoGroup   then f.cbAutoGroup:SetChecked(L.AutoGroupPopup and true or false) end
  if f.cbRoleWhisper then f.cbRoleWhisper:SetChecked(S.RoleWhisperEnabled and true or false) end

  local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  close:SetWidth(70); close:SetHeight(20)
  close:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)
  close:SetText("Close")
  close:SetScript("OnClick", function() f:Hide() end)

  f:SetScript("OnShow", function()
	  if Tactica.RefreshOptionsFrame then Tactica:RefreshOptionsFrame() end
	  Tactica_SetOptionsButtonActive(true)
	end)

	f:SetScript("OnHide", function()
	  Tactica_SetOptionsButtonActive(false)
	end)

	self.optionsFrame = f

	-- ensure first-ever open tints immediately (not just via OnShow)
	Tactica_SetOptionsButtonActive(true)

	f:Show()
end

function Tactica:RefreshOptionsFrame()
  local f = self.optionsFrame
  if not f then return end

  -- db guards
  local S = TacticaDB and TacticaDB.Settings or nil
  local L = S and S.Loot or nil

  if f.cbAutoPost then
    f.cbAutoPost:SetChecked(S and (S.AutoPostOnBoss ~= false))
  end
  if f.cbAutoML then
    f.cbAutoML:SetChecked(L and L.AutoMasterLoot and true or false)
  end
  if f.cbAutoGroup then
    f.cbAutoGroup:SetChecked(L and L.AutoGroupPopup and true or false)
  end
  if f.cbRoleWhisper then
    f.cbRoleWhisper:SetChecked(S and S.RoleWhisperEnabled and true or false)
  end
end

-------------------------------------------------
-- ADD TACTIC UI
-------------------------------------------------

function Tactica:UpdateBossDropdown(raidName)
    local bossDropdown = getglobal("TacticaBossDropdown")
    
    -- Reset selections
    Tactica.selectedBoss = nil
    UIDropDownMenu_SetText(TacticaBossDropdown, "Select Boss")
    
    -- Get all bosses for this raid from both default and custom data
    local bosses = {}
    
    -- Add bosses from default data
    if self.DefaultData[raidName] then
        for bossName in pairs(self.DefaultData[raidName]) do
            bosses[bossName] = true
        end
    end
    
    -- Add bosses from custom data
    if TacticaDB.CustomTactics[raidName] then
        for bossName in pairs(TacticaDB.CustomTactics[raidName]) do
            bosses[bossName] = true
        end
    end
    
    -- Initialize boss dropdown
    UIDropDownMenu_Initialize(bossDropdown, function()
        for bossName in pairs(bosses) do
            local bossName = bossName
            local info = {
                text = bossName,
                func = function()
                    Tactica.selectedBoss = bossName
                    UIDropDownMenu_SetText(TacticaBossDropdown, bossName)
                end
            }
            UIDropDownMenu_AddButton(info)
        end
    end)
end

function Tactica:CreateAddFrame()
    if self.addFrame then return end
    
    -- Main frame
    local f = CreateFrame("Frame", "TacticaAddFrame", UIParent)
    f:SetWidth(400)
    f:SetHeight(300)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 32,
    insets = { left=11, right=12, top=12, bottom=11 }
  })
	f:SetBackdropColor(0, 0, 0, 1)
	f:SetBackdropBorderColor(1, 1, 1, 1)
	f:SetFrameStrata("DIALOG")
    f:Hide()
    
    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -15)
    SetGreenTitle(title, "Add New Tactic")
	title:SetFontObject(GameFontNormalLarge)

    -- RAID DROPDOWN
    local raidLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    raidLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -45)
    raidLabel:SetText("Raid:")

    local raidDropdown = CreateFrame("Frame", "TacticaRaidDropdown", f, "UIDropDownMenuTemplate")
    raidDropdown:SetPoint("TOPLEFT", f, "TOPLEFT", 75, -40)
    raidDropdown:SetWidth(150)

    -- BOSS DROPDOWN
    local bossLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bossLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -75)
    bossLabel:SetText("Boss:")

    local bossDropdown = CreateFrame("Frame", "TacticaBossDropdown", f, "UIDropDownMenuTemplate")
    bossDropdown:SetPoint("TOPLEFT", f, "TOPLEFT", 75, -70)
    bossDropdown:SetWidth(150)

    -- Initialize dropdowns
    f:SetScript("OnShow", function()
        -- Initialize raid dropdown
        UIDropDownMenu_Initialize(raidDropdown, function()
            local raids = {
                "Molten Core", "Blackwing Lair", "Zul'Gurub",
                "Ruins of Ahn'Qiraj", "Temple of Ahn'Qiraj",
                "Onyxia's Lair", "Naxxramas", "Karazhan", 
				"World Bosses"
            }
            for _, raidName in ipairs(raids) do
                local raidName = raidName
                local info = {
                    text = raidName,
                    func = function()
                        Tactica.selectedRaid = raidName
                        UIDropDownMenu_SetText(TacticaRaidDropdown, raidName)
                        Tactica:UpdateBossDropdown(raidName)
                    end
                }
                UIDropDownMenu_AddButton(info)
            end
        end)
        
        -- Set initial raid text (respecting any selection that might have been set before showing)
        if Tactica.selectedRaid then
            UIDropDownMenu_SetText(TacticaRaidDropdown, Tactica.selectedRaid)
            Tactica:UpdateBossDropdown(Tactica.selectedRaid)
        else
            UIDropDownMenu_SetText(TacticaRaidDropdown, "Select Raid")
        end
        
        -- Set initial boss text
        if Tactica.selectedBoss then
            UIDropDownMenu_SetText(TacticaBossDropdown, Tactica.selectedBoss)
        else
            UIDropDownMenu_SetText(TacticaBossDropdown, "Select Boss")
        end
    end)

    -- Tactic name
    local nameLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -115)
    nameLabel:SetText("Tactic Name:")
    
    local nameEdit = CreateFrame("EditBox", "TacticaNameEdit", f, "InputBoxTemplate")
    nameEdit:SetWidth(250)
    nameEdit:SetHeight(20)
    nameEdit:SetPoint("TOPLEFT", f, "TOPLEFT", 100, -110)
    nameEdit:SetAutoFocus(false)

    -- Tactic description
    local descLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    descLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -140)
    descLabel:SetText("Tactic (each line divided by enter adds a /raid message):")

    -- ScrollFrame container
    local scrollFrame = CreateFrame("ScrollFrame", "TacticaDescScroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -160)
    scrollFrame:SetWidth(350)
    scrollFrame:SetHeight(100)

    -- Background behind the scroll frame
    local bg = CreateFrame("Frame", nil, f)
    bg:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", -5, 5)
    bg:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", 5, -5)
    bg:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    bg:SetBackdropColor(0, 0, 0, 0.5)

    -- The multiline EditBox
    local descEdit = CreateFrame("EditBox", "TacticaDescEdit", scrollFrame)
    descEdit:SetMultiLine(true)
    descEdit:SetAutoFocus(false)
    descEdit:SetFontObject("ChatFontNormal")
    descEdit:SetWidth(330)
    descEdit:SetHeight(400)
    descEdit:SetMaxLetters(2000)
    descEdit:SetScript("OnEscapePressed", function() f:Hide() end)
    descEdit:SetScript("OnCursorChanged", function(self, x, y, w, h)
        if not y or not h then return end
        local offset = scrollFrame:GetVerticalScroll()
        local height = scrollFrame:GetHeight()
        if y + h > offset + height then
            scrollFrame:SetVerticalScroll(y + h - height)
        elseif y < offset then
            scrollFrame:SetVerticalScroll(y)
        end
    end)

    scrollFrame:SetScrollChild(descEdit)

   -- Add Submit Button
    local cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancel:SetWidth(100)
    cancel:SetHeight(25)
    cancel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 12)
    cancel:SetText("Cancel")
    cancel:SetScript("OnClick", function() f:Hide() end)
    
    local submit = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    submit:SetWidth(100)
    submit:SetHeight(25)
    submit:SetPoint("RIGHT", cancel, "LEFT", -10, 0)
    submit:SetText("Submit")
    submit:SetScript("OnClick", function()
        local raid = Tactica.selectedRaid
        local boss = Tactica.selectedBoss
        local name = nameEdit:GetText()
        local desc = descEdit:GetText()
        
        if not raid then
            self:PrintError("Please select a raid")
            return
        end
        
        if not boss then
            self:PrintError("Please select a boss")
            return
        end
        
        if name == "" then
            self:PrintError("Please enter a tactic name")
            return
        end
        
        if desc == "" then
            self:PrintError("Please enter tactic description")
            return
        end
        
        if self:AddTactic(raid, boss, name, desc) then
            self:PrintMessage("Tactic added successfully!")
            f:Hide()
        end
    end)

    self.addFrame = f
end

function Tactica:ShowAddPopup()
    if not self.addFrame then
        self:CreateAddFrame()
    end
    
    -- Reset selections
    Tactica.selectedRaid = nil
    Tactica.selectedBoss = nil
    UIDropDownMenu_SetText(TacticaRaidDropdown, "Select Raid")
    UIDropDownMenu_SetText(TacticaBossDropdown, "Select Boss")
    
    -- Reset fields
    getglobal("TacticaNameEdit"):SetText("")
    getglobal("TacticaDescEdit"):SetText("")
    
    self.addFrame:Show()
end

-------------------------------------------------
-- POST TACTIC UI
-------------------------------------------------

function Tactica:CreatePostFrame()
    if self.postFrame then return end
    
    -- Main frame
    local f = CreateFrame("Frame", "TacticaPostFrame", UIParent)
    f:SetWidth(220)
    f:SetHeight(185)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 32,
    insets = { left=11, right=12, top=12, bottom=11 }
  })
	f:SetBackdropColor(0, 0, 0, 1)
	f:SetBackdropBorderColor(1, 1, 1, 1)
	f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
	f:SetClampedToScreen(true)
	if f.SetUserPlaced then f:SetUserPlaced(true) end
    f.locked = false
    
    f:SetScript("OnDragStart", function()
        if not f.locked then 
            f:StartMoving() 
        end
    end)
    f:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        Tactica:SavePostFramePosition()
    end)
    f:Hide()
    
    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -15)
    SetGreenTitle(title, "Post Tactic")
	title:SetFontObject(GameFontNormalLarge)

    -- Close button (X)
    local closeButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
    closeButton:SetScript("OnClick", function() f:Hide() end)

	f:SetScript("OnHide", function()
	  Tactica:SavePostFramePosition()
	end)
	
	 -- Lock button (icon)
	local lockButton = CreateFrame("Button", "TacticaLockButton", f)
	lockButton:SetWidth(18); lockButton:SetHeight(18)
	lockButton:SetPoint("TOPRIGHT", closeButton, "TOPLEFT", 0, -7)

	local function UpdateLockIcon()
	  if f.locked then
		lockButton:SetNormalTexture("Interface\\AddOns\\Tactica\\Media\\tactica-lock")
	  else
		lockButton:SetNormalTexture("Interface\\AddOns\\Tactica\\Media\\tactica-unlock")
	  end
	end

	local function UpdateLockTooltip()
	  if not GameTooltip then return end
	  if GetMouseFocus and GetMouseFocus() == lockButton then
		GameTooltip:ClearLines()
		GameTooltip:SetOwner(lockButton, "ANCHOR_RIGHT")
		GameTooltip:AddLine(f.locked and "Locked" or "Unlocked", 1, 1, 1)
		GameTooltip:AddLine("Click to toggle", 0.9, 0.9, 0.9)
		GameTooltip:Show()
	  end
	end

	UpdateLockIcon()

	lockButton:SetScript("OnClick", function()
	  f.locked = not f.locked
	  UpdateLockIcon()
	  Tactica:SavePostFramePosition()
	  -- refresh tooltip immediately if the cursor is still on the button
	  UpdateLockTooltip()
	end)

	lockButton:SetScript("OnEnter", function()
	  UpdateLockTooltip()
	end)

	lockButton:SetScript("OnLeave", function()
	  if GameTooltip then GameTooltip:Hide() end
	end)

	-- Settings (Options) icon button next to the lock button
	local optionsButton = CreateFrame("Button", nil, f)
	optionsButton:SetWidth(20); optionsButton:SetHeight(20)
	optionsButton:SetPoint("TOPRIGHT", lockButton, "TOPLEFT", -3, 1)

	-- custom texture
	optionsButton:SetNormalTexture("Interface\\AddOns\\Tactica\\Media\\tactica-gear")

	optionsButton:SetScript("OnClick", function()
	  if Tactica and Tactica.ShowOptionsFrame then
		Tactica:ShowOptionsFrame()
	  end
	end)

	-- tooltip
	optionsButton:SetScript("OnEnter", function()
	  if GameTooltip then
		GameTooltip:SetOwner(optionsButton, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Tactica Options", 1, 1, 1)
		GameTooltip:Show()
	  end
	end)
	optionsButton:SetScript("OnLeave", function()
	  if GameTooltip then GameTooltip:Hide() end
	end)

	-- store a reference - tint while options is open
	Tactica.optionsButton = optionsButton

	
    -- RAID DROPDOWN
    local raidLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    raidLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -40)
    raidLabel:SetText("Raid:")

    local raidDropdown = CreateFrame("Frame", "TacticaPostRaidDropdown", f, "UIDropDownMenuTemplate")
    raidDropdown:SetPoint("TOPLEFT", f, "TOPLEFT", 50, -36)
    raidDropdown:SetWidth(150)

    -- BOSS DROPDOWN
    local bossLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bossLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -70)
    bossLabel:SetText("Boss:")

    local bossDropdown = CreateFrame("Frame", "TacticaPostBossDropdown", f, "UIDropDownMenuTemplate")
    bossDropdown:SetPoint("TOPLEFT", f, "TOPLEFT", 50, -65)
    bossDropdown:SetWidth(150)

    -- TACTIC DROPDOWN
    local tacticLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tacticLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -100)
    tacticLabel:SetText("Tactic:")

    local tacticDropdown = CreateFrame("Frame", "TacticaPostTacticDropdown", f, "UIDropDownMenuTemplate")
    tacticDropdown:SetPoint("TOPLEFT", f, "TOPLEFT", 50, -95)
    tacticDropdown:SetWidth(250)

    -- Initialize dropdowns
    f:SetScript("OnShow", function()
	if not f._restoredOnce then
	  Tactica:RestorePostFramePosition()
	  f._restoredOnce = true
	end
        -- Initialize raid dropdown
        UIDropDownMenu_Initialize(raidDropdown, function()
            local raids = {
                "Molten Core", "Blackwing Lair", "Zul'Gurub",
                "Ruins of Ahn'Qiraj", "Temple of Ahn'Qiraj",
                "Onyxia's Lair", "Naxxramas", "Karazhan",
				"World Bosses"
            }
            for _, raidName in ipairs(raids) do
                local r = raidName
                local info = {
                    text = r,
                    func = function()
                        Tactica.selectedRaid = r
                        UIDropDownMenu_SetText(TacticaPostRaidDropdown, r)
                        Tactica:UpdatePostBossDropdown(r)
                    end
                }
                UIDropDownMenu_AddButton(info)
            end
        end)
        
        -- Set initial texts
        UIDropDownMenu_SetText(TacticaPostRaidDropdown, Tactica.selectedRaid or "Select Raid")
        UIDropDownMenu_SetText(TacticaPostBossDropdown, Tactica.selectedBoss or "Select Boss")
        UIDropDownMenu_SetText(TacticaPostTacticDropdown, "Select Tactic (opt.)")
		
		if TacticaAutoPostCheckbox then
			TacticaAutoPostCheckbox:SetChecked(
				not (TacticaDB and TacticaDB.Settings and TacticaDB.Settings.AutoPostOnBoss == false)
			)
		end
		
		if UpdateLockIcon then UpdateLockIcon() end
		
				-- keep loot checkboxes in sync with DB whenever the frame opens
		if TacticaAutoMasterLootCB then
		  TacticaAutoMasterLootCB:SetChecked(
			TacticaDB and TacticaDB.Settings and TacticaDB.Settings.Loot and TacticaDB.Settings.Loot.AutoMasterLoot
		  )
		end
		if TacticaAutoGroupPopupCB then
		  TacticaAutoGroupPopupCB:SetChecked(
			TacticaDB and TacticaDB.Settings and TacticaDB.Settings.Loot and TacticaDB.Settings.Loot.AutoGroupPopup
		  )
		end

    end)

    -- Post to Raid (bottom-right, leader/assist only)
    local submit = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    submit:SetWidth(100)
    submit:SetHeight(25)
    submit:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 15)
    submit:SetText("Post to Raid")
    submit:SetScript("OnClick", function()
        if not self:CanAutoPost() then
            self:PrintError("You must be a raid leader or assist to post tactics.")
            return
        end
        local raid = Tactica.selectedRaid
        local boss = Tactica.selectedBoss
        local tactic = UIDropDownMenu_GetText(TacticaPostTacticDropdown)
        if not raid then self:PrintError("Please select a raid"); return end
        if not boss then self:PrintError("Please select a boss"); return end
        if tactic == "Select Tactic (opt.)" then tactic = nil end
        self:PostTactic(raid, boss, tactic)
        f:Hide()
    end)

    -- Post to Self (bottom-left, green, no leader requirement)
    local selfBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    selfBtn:SetWidth(100)
    selfBtn:SetHeight(25)
    selfBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 15)
    selfBtn:SetText("Post to Self")
	
    -- Green styling
	local fs = selfBtn:GetFontString()
	if fs and fs.SetTextColor then
	  fs:SetTextColor(0.2, 1.0, 0.2) -- green text
	end

	selfBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
	local nt = selfBtn:GetNormalTexture()
	if nt then nt:SetVertexColor(0.2, 0.8, 0.2) end

	selfBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
	local pt = selfBtn:GetPushedTexture()
	if pt then pt:SetVertexColor(0.2, 0.8, 0.2) end

	selfBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
	local ht = selfBtn:GetHighlightTexture()
	if ht then
	  ht:SetBlendMode("ADD")
	  ht:SetVertexColor(0.2, 1.0, 0.2)
	end

    selfBtn:SetScript("OnClick", function()
        local raid = Tactica.selectedRaid
        local boss = Tactica.selectedBoss
        local tactic = UIDropDownMenu_GetText(TacticaPostTacticDropdown)
        if not raid then self:PrintError("Please select a raid"); return end
        if not boss then self:PrintError("Please select a boss"); return end
        if tactic == "Select Tactic (opt.)" then tactic = nil end
        self:PostTacticToSelf(raid, boss, tactic)
        f:Hide()
    end)
	  
	  -- Auto-open on boss (checkbox)
    local autoCB = CreateFrame("CheckButton", "TacticaAutoPostCheckbox", f, "UICheckButtonTemplate")
    autoCB:SetWidth(24); autoCB:SetHeight(24)
    autoCB:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 40)

    local label = getglobal("TacticaAutoPostCheckboxText")
    if label then
        label:SetText("Auto-open Tactica on boss")
    end

    autoCB:SetChecked(not (TacticaDB and TacticaDB.Settings and TacticaDB.Settings.AutoPostOnBoss == false))

    autoCB:SetScript("OnClick", function()
        local on = autoCB:GetChecked() and true or false
        if not TacticaDB or not TacticaDB.Settings then return end
        TacticaDB.Settings.AutoPostOnBoss = on
        if on then
            Tactica.AutoPostHintShown = false
            Tactica:PrintMessage("Auto-popup is |cff00ff00ON|r. It will open on boss targets.")
        else
            Tactica:PrintMessage("Auto-popup is |cffff5555OFF|r. Use '/tt post' or '/tt autopost' to enable.")
        end
    end)
	self.postFrame = f
	Tactica:RestorePostFramePosition()
	f._restoredOnce = true
	if TacticaDB and TacticaDB.Settings and TacticaDB.Settings.PostFrame then
	  f.locked = (TacticaDB.Settings.PostFrame.locked == true)
	else
	  f.locked = false
	end
	if UpdateLockIcon then UpdateLockIcon() end
end

-------------------------------------------------
-- REMOVE TACTIC UI
-------------------------------------------------

function Tactica:CreateRemoveFrame()
    if self.removeFrame then return end
    
    -- Main frame
    local f = CreateFrame("Frame", "TacticaRemoveFrame", UIParent)
    f:SetWidth(220)
    f:SetHeight(165)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 32,
    insets = { left=11, right=12, top=12, bottom=11 }
  })
	f:SetBackdropColor(0, 0, 0, 1)
	f:SetBackdropBorderColor(1, 1, 1, 1)
	f:SetFrameStrata("DIALOG")
    f:Hide()
    
    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -15)
    SetGreenTitle(title, "Remove Custom Tactic")

    -- Close button (X)
    local closeButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
    closeButton:SetScript("OnClick", function() f:Hide() end)
	
    -- RAID DROPDOWN
    local raidLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    raidLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -40)
    raidLabel:SetText("Raid:")

    local raidDropdown = CreateFrame("Frame", "TacticaRemoveRaidDropdown", f, "UIDropDownMenuTemplate")
    raidDropdown:SetPoint("TOPLEFT", f, "TOPLEFT", 50, -36)
    raidDropdown:SetWidth(150)

    -- BOSS DROPDOWN
    local bossLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bossLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -70)
    bossLabel:SetText("Boss:")

    local bossDropdown = CreateFrame("Frame", "TacticaRemoveBossDropdown", f, "UIDropDownMenuTemplate")
    bossDropdown:SetPoint("TOPLEFT", f, "TOPLEFT", 50, -65)
    bossDropdown:SetWidth(150)

    -- TACTIC DROPDOWN
    local tacticLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tacticLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -100)
    tacticLabel:SetText("Tactic:")

    local tacticDropdown = CreateFrame("Frame", "TacticaRemoveTacticDropdown", f, "UIDropDownMenuTemplate")
    tacticDropdown:SetPoint("TOPLEFT", f, "TOPLEFT", 50, -95)
    tacticDropdown:SetWidth(250)

    -- Initialize dropdowns
    f:SetScript("OnShow", function()
        -- Initialize raid dropdown with only raids that have custom tactics
        UIDropDownMenu_Initialize(raidDropdown, function()
            local hasCustomTactics = false
            
            for raidName, bosses in pairs(TacticaDB.CustomTactics or {}) do
                if bosses and next(bosses) then
                    hasCustomTactics = true
                    local raidName = raidName
                    local info = {
                        text = raidName,
                        func = function()
                            Tactica.selectedRaid = raidName
                            UIDropDownMenu_SetText(TacticaRemoveRaidDropdown, raidName)
                            Tactica:UpdateRemoveBossDropdown(raidName)
                        end
                    }
                    UIDropDownMenu_AddButton(info)
                end
            end
            
            if not hasCustomTactics then
                local info = {
                    text = "No custom tactics",
                    func = function() end,
                    disabled = true
                }
                UIDropDownMenu_AddButton(info)
            end
        end)
        
        -- Set initial raid text
        if Tactica.selectedRaid and TacticaDB.CustomTactics[Tactica.selectedRaid] then
            UIDropDownMenu_SetText(TacticaRemoveRaidDropdown, Tactica.selectedRaid)
            Tactica:UpdateRemoveBossDropdown(Tactica.selectedRaid)
        else
            UIDropDownMenu_SetText(TacticaRemoveRaidDropdown, "Select Raid")
        end
        
        -- Set initial boss text
        if Tactica.selectedBoss and Tactica.selectedRaid and 
           TacticaDB.CustomTactics[Tactica.selectedRaid] and 
           TacticaDB.CustomTactics[Tactica.selectedRaid][Tactica.selectedBoss] then
            UIDropDownMenu_SetText(TacticaRemoveBossDropdown, Tactica.selectedBoss)
            Tactica:UpdateRemoveTacticDropdown(Tactica.selectedRaid, Tactica.selectedBoss)
        else
            UIDropDownMenu_SetText(TacticaRemoveBossDropdown, "Select Boss")
        end
        
        -- Set initial tactic text
        UIDropDownMenu_SetText(TacticaRemoveTacticDropdown, "Select Tactic")
    end)

    -- Remove button
    local removeButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    removeButton:SetWidth(100)
    removeButton:SetHeight(25)
    removeButton:SetPoint("BOTTOM", f, "BOTTOM", 0, 15)
    removeButton:SetText("Remove")
    removeButton:SetScript("OnClick", function()
        local raid = Tactica.selectedRaid
        local boss = Tactica.selectedBoss
        local tactic = UIDropDownMenu_GetText(TacticaRemoveTacticDropdown)
        
        if not raid then
            self:PrintError("Please select a raid")
            return
        end
        
        if not boss then
            self:PrintError("Please select a boss")
            return
        end
        
        if tactic == "Select Tactic" then
            self:PrintError("Please select a tactic to remove")
            return
        end
        
        if self:RemoveTactic(raid, boss, tactic) then
            self:PrintMessage(string.format("Tactic '%s' for %s in %s removed successfully!", tactic, boss, raid))
            f:Hide()
        end
    end)

    self.removeFrame = f
end

function Tactica:UpdatePostBossDropdown(raidName)
    local bossDropdown = getglobal("TacticaPostBossDropdown")
    local tacticDropdown = getglobal("TacticaPostTacticDropdown")
    
    -- Reset selections
    Tactica.selectedBoss = nil
    UIDropDownMenu_SetText(TacticaPostBossDropdown, "Select Boss")
    UIDropDownMenu_SetText(TacticaPostTacticDropdown, "Select Tactic (opt.)")
    
    -- Get all bosses for this raid from both default and custom data
    local bosses = {}
    
    -- Add bosses from default data
    if self.DefaultData[raidName] then
        for bossName in pairs(self.DefaultData[raidName]) do
            bosses[bossName] = true
        end
    end
    
    -- Add bosses from custom data
    if TacticaDB.CustomTactics[raidName] then
        for bossName in pairs(TacticaDB.CustomTactics[raidName]) do
            bosses[bossName] = true
        end
    end
    
    -- Initialize boss dropdown
    UIDropDownMenu_Initialize(bossDropdown, function()
        for bossName in pairs(bosses) do
            local bossName = bossName
            local info = {
                text = bossName,
                func = function()
                    Tactica.selectedBoss = bossName
                    UIDropDownMenu_SetText(TacticaPostBossDropdown, bossName)
                    Tactica:UpdatePostTacticDropdown(raidName, bossName)
                end
            }
            UIDropDownMenu_AddButton(info)
        end
    end)
end

function Tactica:UpdatePostTacticDropdown(raidName, bossName)
    local tacticDropdown = getglobal("TacticaPostTacticDropdown")
    
    -- Reset selection
    UIDropDownMenu_SetText(TacticaPostTacticDropdown, "Select Tactic (opt.)")
    
    -- Initialize tactic dropdown with all available tactics for this boss
    UIDropDownMenu_Initialize(tacticDropdown, function()
        -- Add default tactic option
        local info = {
            text = "Default",
            func = function()
                UIDropDownMenu_SetText(TacticaPostTacticDropdown, "Default")
            end
        }
        UIDropDownMenu_AddButton(info)
        
        -- Add tactics from default data
        if self.DefaultData[raidName] and self.DefaultData[raidName][bossName] then
            for tacticName in pairs(self.DefaultData[raidName][bossName]) do
                if tacticName ~= "Default" and not IsReservedBossField(tacticName) then
                    local tacticName = tacticName
                    local info = {
                        text = tacticName,
                        func = function()
                            UIDropDownMenu_SetText(TacticaPostTacticDropdown, tacticName)
                        end
                    }
                    UIDropDownMenu_AddButton(info)
                end
            end
        end
        
        -- Add tactics from custom data
        if TacticaDB.CustomTactics[raidName] and 
           TacticaDB.CustomTactics[raidName][bossName] then
            for tacticName in pairs(TacticaDB.CustomTactics[raidName][bossName]) do
                if tacticName ~= "Default" then
                    local tacticName = tacticName
                    local info = {
                        text = tacticName,
                        func = function()
                            UIDropDownMenu_SetText(TacticaPostTacticDropdown, tacticName)
                        end
                    }
                    UIDropDownMenu_AddButton(info)
                end
            end
        end
    end)
end

function Tactica:ShowPostPopup(isManual)
    if not self.postFrame then
        self:CreatePostFrame()
    end
    
    if isManual then
        -- For manual calls, reset selections
        self.selectedRaid = nil
        self.selectedBoss = nil
        UIDropDownMenu_SetText(TacticaPostRaidDropdown, "Select Raid")
        UIDropDownMenu_SetText(TacticaPostBossDropdown, "Select Boss")
    else
        -- For automatic calls, use the preselected values
        if self.selectedRaid then
            UIDropDownMenu_SetText(TacticaPostRaidDropdown, self.selectedRaid)
            self:UpdatePostBossDropdown(self.selectedRaid)
            
            if self.selectedBoss then
                UIDropDownMenu_SetText(TacticaPostBossDropdown, self.selectedBoss)
                self:UpdatePostTacticDropdown(self.selectedRaid, self.selectedBoss)
            end
        end
    end
    
    self.postFrame:Show()
end

-------------------------------------------------
-- REMOVE TACTIC UI HELPER FUNCTIONS
-------------------------------------------------

function Tactica:UpdateRemoveBossDropdown(raidName)
    local bossDropdown = getglobal("TacticaRemoveBossDropdown")
    local tacticDropdown = getglobal("TacticaRemoveTacticDropdown")
    
    -- Reset selections
    Tactica.selectedBoss = nil
    UIDropDownMenu_SetText(TacticaRemoveBossDropdown, "Select Boss")
    UIDropDownMenu_SetText(TacticaRemoveTacticDropdown, "Select Tactic")
    
    -- Get all bosses for this raid that have custom tactics
    local bosses = {}
    
    if TacticaDB.CustomTactics[raidName] then
        for bossName in pairs(TacticaDB.CustomTactics[raidName]) do
            bosses[bossName] = true
        end
    end
    
    -- Initialize boss dropdown
    UIDropDownMenu_Initialize(bossDropdown, function()
        for bossName in pairs(bosses) do
            local bossName = bossName
            local info = {
                text = bossName,
                func = function()
                    Tactica.selectedBoss = bossName
                    UIDropDownMenu_SetText(TacticaRemoveBossDropdown, bossName)
                    Tactica:UpdateRemoveTacticDropdown(raidName, bossName)
                end
            }
            UIDropDownMenu_AddButton(info)
        end
    end)
end

function Tactica:UpdateRemoveTacticDropdown(raidName, bossName)
    local tacticDropdown = getglobal("TacticaRemoveTacticDropdown")
    
    -- Reset selection
    UIDropDownMenu_SetText(TacticaRemoveTacticDropdown, "Select Tactic")
    
    -- Initialize tactic dropdown with custom tactics for this boss
    UIDropDownMenu_Initialize(tacticDropdown, function()
        if TacticaDB.CustomTactics[raidName] and TacticaDB.CustomTactics[raidName][bossName] then
            for tacticName in pairs(TacticaDB.CustomTactics[raidName][bossName]) do
                local tacticName = tacticName
                local info = {
                    text = tacticName,
                    func = function()
                        UIDropDownMenu_SetText(TacticaRemoveTacticDropdown, tacticName)
                    end
                }
                UIDropDownMenu_AddButton(info)
            end
        end
    end)
end

function Tactica:ShowRemovePopup()
    if not self.removeFrame then
        self:CreateRemoveFrame()
    end
    
    -- Reset selections but keep any previously selected raid/boss
    UIDropDownMenu_SetText(TacticaRemoveRaidDropdown, Tactica.selectedRaid or "Select Raid")
    UIDropDownMenu_SetText(TacticaRemoveBossDropdown, Tactica.selectedBoss or "Select Boss")
    UIDropDownMenu_SetText(TacticaRemoveTacticDropdown, "Select Tactic")
    
    -- If selected raid with custom tactics, update boss dropdown
    if Tactica.selectedRaid and TacticaDB.CustomTactics[Tactica.selectedRaid] then
        self:UpdateRemoveBossDropdown(Tactica.selectedRaid)
        
        -- If selected boss with custom tactics, update tactic dropdown
        if Tactica.selectedBoss and TacticaDB.CustomTactics[Tactica.selectedRaid][Tactica.selectedBoss] then
            self:UpdateRemoveTacticDropdown(Tactica.selectedRaid, Tactica.selectedBoss)
        end
    end
    
    self.removeFrame:Show()
end

-------------------------------------------------
-- MINIMAP ICON & MENU (self-contained section)
-------------------------------------------------
do
  -- small SV pocket; create defaults on first load
  local function _MiniSV()
    TacticaDB                = TacticaDB or {}
    TacticaDB.Settings       = TacticaDB.Settings or {}
    TacticaDB.Settings.Minimap = TacticaDB.Settings.Minimap or {
      angle = 215,
      offset = 0,
      locked = false,
      hide = false,
    }
    return TacticaDB.Settings.Minimap
  end

  -- compute minimap button position
  local function _PlaceMini(btn)
    local sv = _MiniSV()
    local rad = math.rad(sv.angle or 215)
    local r   = (80 + (sv.offset or 0))
    local x   = 53 - (r * math.cos(rad))
    local y   = (r * math.sin(rad)) - 55
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", Minimap, "TOPLEFT", x, y)
  end

  -- help lines for tooltip (keep in sync with /tt help)
  local function _HelpLines()
    return {
      "|cffffff00/tt help|r – show commands",
	  "|cffffff78/tt build|r – open Raid Builder",  
	  "|cffffff78/tt lfm|r – announce Raid Builder msg",
	  "|cffffff78/tt autoinvite|r – open Auto Invite",
	  "|cffffff78/tt export|r – export raid roster",
      "|cffffff00/tt post|r – open post UI",
      "|cffffff00/tt add|r – add custom tactic",
      "|cffffff00/tt remove|r – remove custom tactic",
      "|cffffff00/tt list|r – list all tactics",
      "|cffffff00/tt autopost|r – toggle auto-open on boss",
      "|cffffff00/tt roles|r – post tank/healer summary",
      "|cffffff00/tt rolewhisper|r – toggle role whisper",
      "|cffffff00/tt options|r – options panel",
      "|cffffff78/tt comp|r – open composition tool",
    }
  end

  -------------------------------------------------
  -- The drop-down minimap menu
  -------------------------------------------------
  local menu = CreateFrame("Frame", "TacticaMinimapMenu", UIParent, "UIDropDownMenuTemplate")
  local function _MenuInit()
    local info

    info = { isTitle = 1, text = TACTICA_TITLE_COLOR .. "Tactica|r", notCheckable = 1, justifyH = "CENTER" }
    UIDropDownMenu_AddButton(info, 1)

    local add = function(text, fn, disabled)
      info = { notCheckable = 1, text = text, disabled = disabled and true or nil, func = fn }
      UIDropDownMenu_AddButton(info, 1)
    end

    add("Open Post Tactics", function() if Tactica and Tactica.ShowPostPopup then Tactica:ShowPostPopup(true) end end)
    add("Open Add Tactics",  function() if Tactica and Tactica.ShowAddPopup  then Tactica:ShowAddPopup()  end end)
    add("Open Remove Tactics", function() if Tactica and Tactica.ShowRemovePopup then Tactica:ShowRemovePopup() end end)
    add("Open Raid Builder", function()
      if TacticaRaidBuilder and TacticaRaidBuilder.Open then
        TacticaRaidBuilder.Open()
      else
        if Tactica and Tactica.PrintError then Tactica:PrintError("Raid Builder module not loaded.") end
      end
    end)
	add("Open Auto Invite", function()
      if TacticaInvite and TacticaInvite.Open then
        TacticaInvite.Open()
      else
        if Tactica and Tactica.PrintError then Tactica:PrintError("Auto-Invite module not loaded.") end
      end
    end)
	add("Open Composition Tool", function()
      if TacticaComposition and TacticaComposition.Open then
        TacticaComposition:Open()
      else
        if Tactica and Tactica.PrintError then Tactica:PrintError("Composition module not loaded.") end
      end
    end)
	add("Open Export", function() if Tactica and Tactica.ShowExportRolesFrame then Tactica:ShowExportRolesFrame() end end)
    add("Open Options", function() if Tactica and Tactica.ShowOptionsFrame then Tactica:ShowOptionsFrame() end end)
    add("Tactica Help",  function() if Tactica and Tactica.PrintHelp then Tactica:PrintHelp() end end)
  end
  menu.initialize = _MenuInit
  menu.displayMode = "MENU"

  -------------------------------------------------
  -- The minimap button
  -------------------------------------------------
  local btn = CreateFrame("Button", "TacticaMinimapButton", Minimap)
  btn:SetFrameStrata("MEDIUM")
  btn:SetWidth(31); btn:SetHeight(31)

  -- art
  local overlay = btn:CreateTexture(nil, "OVERLAY")
  overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  overlay:SetWidth(54); overlay:SetHeight(54)
  overlay:SetPoint("TOPLEFT", 0, 0)

  local icon = btn:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture("Interface\\AddOns\\Tactica\\Media\\tactica-icon")
  icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
  icon:SetWidth(20); icon:SetHeight(20)
  icon:SetPoint("TOPLEFT", 6, -6)

  local hlt = btn:CreateTexture(nil, "HIGHLIGHT")
  hlt:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  hlt:SetBlendMode("ADD")
  hlt:SetAllPoints(btn)

  btn:RegisterForDrag("LeftButton", "RightButton")
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  -- drag to move (unless locked)
  btn:SetScript("OnDragStart", function()
    local sv = _MiniSV()
    if sv.locked then return end
    btn:SetScript("OnUpdate", function()
      local x, y = GetCursorPosition()
      local mx, my = Minimap:GetCenter()
      local scale = Minimap:GetEffectiveScale()
      local ang = math.deg(math.atan2(y/scale - my, x/scale - mx))
      _MiniSV().angle = ang
      _PlaceMini(btn)
    end)
  end)
  btn:SetScript("OnDragStop", function() btn:SetScript("OnUpdate", nil) end)

  -- click: open drop-down (left or right)
  btn:SetScript("OnClick", function()
    ToggleDropDownMenu(1, nil, menu, "TacticaMinimapButton", 0, 0)
  end)

  -- tooltip: first line + the help list
  btn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
	GameTooltip:AddLine("TACTICA", 0.2, 1.0, 0.6)
    GameTooltip:AddLine("Click minimap icon to open menu", 1, 1, 1)
	GameTooltip:AddLine("Version: " .. tostring(Tactica_GetVersion()), 1, 1, 1)
    GameTooltip:AddLine(" ")
    for _, line in ipairs(_HelpLines()) do
      GameTooltip:AddLine(line, 0.9, 0.9, 0.9, 1)
    end
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() if GameTooltip:IsOwned(btn) then GameTooltip:Hide() end end)

  -- show/hide + initial placement on addon load
  local ev = CreateFrame("Frame")
  ev:RegisterEvent("ADDON_LOADED")
  ev:SetScript("OnEvent", function()
    if event ~= "ADDON_LOADED" or arg1 ~= "Tactica" then return end
    local sv = _MiniSV()
    if sv.hide then btn:Hide() else btn:Show() end
    _PlaceMini(btn)
  end)
end

-------------------------------------------------
-- VERSION DEBUG
-------------------------------------------------

-- /ttversion: show current Tactica version
SLASH_TTVERSION1 = "/ttversion"
SlashCmdList["TTVERSION"] = function()
  local v = Tactica_GetVersion and Tactica_GetVersion() or (Tactica and Tactica.Version) or (TacticaDB and TacticaDB.version) or "unknown"
  (DEFAULT_CHAT_FRAME or ChatFrame1):AddMessage("|cff33ff99Tactica:|r Version " .. tostring(v))
end


-- /ttversionwho: debug WHO for versions
SLASH_TTVERSIONWHO1 = "/ttversionwho"
SlashCmdList["TTVERSIONWHO"] = function()
  (DEFAULT_CHAT_FRAME or ChatFrame1):AddMessage("|cff33ff99Tactica:|r version WHO sent. Listening for replies...")
  local sent = false
  local me = (UnitName and UnitName("player")) or nil
  if me and me ~= "" then
    _verWhoRid = tostring(((GetTime and GetTime()) or 0))
    local msg = "TACTICA_WHO:" .. tostring(me) .. ":" .. tostring(_verWhoRid)
    if UnitInRaid and UnitInRaid("player") then
      SendAddonMessage("TACTICA", msg, "RAID"); sent = true
    elseif (GetNumPartyMembers and GetNumPartyMembers() > 0) then
      SendAddonMessage("TACTICA", msg, "PARTY"); sent = true
    elseif IsInGuild and IsInGuild() then
      SendAddonMessage("TACTICA", msg, "GUILD"); sent = true
    end
  end
  if not sent then (DEFAULT_CHAT_FRAME or ChatFrame1):AddMessage("|cff33ff99Tactica:|r No channels available (raid/party/guild).") end
end

-- /tt_loot: Shows loot frame
SLASH_TTACTICALOOT1 = "/tt_loot"
SLASH_TTACTICALOOT2 = "/tactica_loot"
SlashCmdList["TTACTICALOOT"] = function()
  if TacticaLoot_ShowPopup then
    TacticaLoot_ShowPopup()
  else
    (DEFAULT_CHAT_FRAME or ChatFrame1):AddMessage("|cffff5555Tactica:|r Loot module not loaded.")
  end
end

-------------------------------------------------
-- DEFAULT DATA
-------------------------------------------------

Tactica.DefaultData = {
    ["Molten Core"] = {
		["Lucifron"] = {
			["Default"] = ""
		},
		["Magmadar"] = {
			["Default"] = ""
		},
		["Garr"] = {
			["Default"] = ""
		},
		["Baron Geddon"] = {
			["Default"] = ""
		},
		["Shazzrah"] = {
			["Default"] = ""
		},
		["Sulfuron Harbinger"] = {
			["Default"] = ""
		},
		["Golemagg the Incinerator"] = {
			["Default"] = ""
		},
		["Majordomo Executus"] = {
			["Default"] = ""
		},
		["Ragnaros"] = {
			["Default"] = ""
		}
    },
    ["Blackwing Lair"] = {
        ["Razorgore the Untamed"] = {
            ["Default"] = ""
        },
        ["Vaelastrasz the Corrupt"] = {
            ["Default"] = ""
        },
        ["Broodlord Lashlayer"] = {
            ["Default"] = ""
        },
        ["Firemaw"] = {
            ["Default"] = ""
        },
        ["Ebonroc"] = {
            ["Default"] = ""
        },
        ["Flamegor"] = {
            ["Default"] = ""
        },
        ["Chromaggus"] = {
            ["Default"] = ""
        },
        ["Nefarian"] = {
            ["Default"] = ""
        },
        ["Ezzel Darkbrewer"] = {
            ["Default"] = ""
        }
    },
    ["Zul'Gurub"] = {
        ["High Priestess Jeklik"] = {
            ["Default"] = ""
        },
        ["High Priest Venoxis"] = {
            ["Default"] = ""
        },
        ["High Priestess Mar'li"] = {
            ["Default"] = ""
        },
        ["High Priest Thekal"] = {
            ["Default"] = ""
        },
        ["High Priestess Arlokk"] = {
            ["Default"] = ""
        },
        ["Hakkar"] = {
            ["Default"] = ""
        },
        ["Bloodlord Mandokir"] = {
            ["Default"] = ""
        },
        ["Jin'do the Hexxer"] = {
            ["Default"] = ""
        },
        ["Gahz'ranka"] = {
            ["Default"] = ""
        }
    },
    ["Ruins of Ahn'Qiraj"] = {
        ["Kurinnaxx"] = {
            ["Default"] = ""
        },
        ["General Rajaxx"] = {
            ["Default"] = ""
        },
        ["Moam"] = {
            ["Default"] = ""
        },
        ["Buru the Gorger"] = {
            ["Default"] = ""
        },
        ["Ayamiss the Hunter"] = {
            ["Default"] = ""
        },
        ["Ossirian the Unscarred"] = {
            ["Default"] = ""
        }
    },
    ["Temple of Ahn'Qiraj"] = {
        ["The Prophet Skeram"] = {
            ["Default"] = ""
        },
        ["Silithid Royalty (Bug Trio)"] = {
            ["Default"] = ""
        },
        ["Battleguard Sartura"] = {
            ["Default"] = ""
        },
        ["Fankriss the Unyielding"] = {
            ["Default"] = ""
        },
        ["Viscidus"] = {
            ["Default"] = ""
        },
        ["Princess Huhuran"] = {
            ["Default"] = ""
        },
        ["Twin Emperors"] = {
            ["Loot table"] = { "Emperor Vek'lor", "Emperor Vek'nilash" },
            ["Default"] = ""
        },
        ["Ouro"] = {
            ["Default"] = ""
        },
        ["C'Thun"] = {
            ["Default"] = ""
        }
    },
    ["Naxxramas"] = {
        ["Anub'Rekhan"] = {
            ["Default"] = ""
        },
        ["Grand Widow Faerlina"] = {
            ["Default"] = ""
        },
        ["Maexxna"] = {
            ["Default"] = ""
        },
        ["Noth the Plaguebringer"] = {
            ["Default"] = ""
        },
        ["Heigan the Unclean"] = {
            ["Default"] = ""
        },
        ["Loatheb"] = {
            ["Default"] = ""
        },
        ["Instructor Razuvious"] = {
            ["Default"] = ""
        },
        ["Gothik the Harvester"] = {
            ["Default"] = ""
        },
        ["The Four Horsemen"] = {
            ["Default"] = ""
        },
        ["Patchwerk"] = {
            ["Default"] = ""
        },
        ["Grobbulus"] = {
            ["Default"] = ""
        },
        ["Gluth"] = {
            ["Default"] = ""
        },
        ["Thaddius"] = {
            ["Default"] = ""
        },
        ["Sapphiron"] = {
            ["Default"] = ""
        },
        ["Kel'Thuzad"] = {
            ["Default"] = ""
        }
    },
    ["World Bosses"] = {
        ["Lord Kazzak"] = {
            ["Default"] = "Tanks: One tank is sufficient. Face Kazzak away from the raid to avoid Cleave. Manage threat carefully—player deaths heal Kazzak via Capture Soul. Maintain cooldowns to survive during enrage.\nDPS: Manage threat tightly; avoid stacking. Dying causes Kazzak to heal. Dispel Twisted Reflection to stop boss healing and Mark of Kazzak to prevent explosive deaths.\nHealers: Dispel Twisted Reflection fast (Priests/Paladins). Cleanse Mark of Kazzak or have target run away before mana burnout explosion. Watch for Capture Soul, heal quick to avoid healing Kazzak.\nClass Specific: Priests/Paladins must dispel Twisted Reflection. Druids/Mages should cleanse Mark of Kazzak if possible or the target should disengage raid safely. Other classes support with LoS for Shadowbolt Volley.\nBoss Ability: Heals when players die (Capture Soul), casts Twisted Reflection to steal life—must be dispelled, Mark of Kazzak drains mana then explodes, Shadowbolt Volley hits raid, Enrages after 3 mins—burn fast or wipe."
        },
        ["Volchan"] = {
            ["Default"] = ""
        },
        ["Azuregos"] = {
            ["Default"] = ""
        },
        ["Lethon"] = {
            ["Default"] = ""
        },
        ["Emeriss"] = {
            ["Default"] = ""
        },
        ["Taerar"] = {
            ["Default"] = ""
        },
        ["Ysondre"] = {
            ["Default"] = ""
        }
    },
    ["Karazhan"] = {
        ["EMPTY"] = {
            ["Default"] = ""
        }
    },

    ["Onyxia's Lair"] = {
        ["Onyxia"] = {
            ["Default"] = "Tanks: Tank near back wall during inital phase (P1) and when Onyxia lands again (P3). Turn away from raid (side of boss towards raid). During airphase (P2), grab all adds.\nDPS: Never stand behind or infront of Onyxia. Focus adds when up. CARE THREAT! Stable DPS and let tank get agro when Onyxia lands (P3).\nHealers: Focus on tank, and during airphase (P2) and landing phase (P3) on damage on raid.\nClass Specific: Fear Ward (Priests) and Tremor Totem (Shaman) prio for MT during landing phase (P3).\nBoss Ability: During airphase (P2) Onyxia will occasionally Fire Breath, with will likely kill anyone in it's path. To avoid it ALL must NEVER stand beneath or diagonally (in straight line) from where Onyxia currently is facing. Note the boss will move."
        }
    }
}
