-- Thanks to Shibou for the API Wrapper code

-- Pulls back the Addon-Local Variables and store them locally.
local addonName, addonTable = ...;
local addon = _G[addonName];

-- Store local copies of Blizzard API and other addon global functions and variables
local GetBuildInfo = GetBuildInfo;
local select, setmetatable, table, type, unpack = select, setmetatable, table, type, unpack;

addonTable.CURRENT_WOW_VERSION = select(4, GetBuildInfo());

local Prototype = {


	-- API Version History
	-- 8.0 - Dropped second parameter (nameSubtext).
	--     - Also, no longer supports querying by spell name.
	UnitBuff = function(...)
		if addonTable.CURRENT_WOW_VERSION >= 30000 then
			local unitID, ID = ...;

			if type(ID) == "string" then
				for counter = 1, 40 do
					local auraName = UnitBuff(unitID, counter);

					if ID == auraName then
						return UnitBuff(unitID, counter);
					end
				end
			end
		else
			local parameters = { UnitBuff(...) };

			table.insert(parameters, 2, "dummyReturn");

			return unpack(parameters);
		end
	end,

	-- API Version History
	-- 8.0 - Dropped second parameter (nameSubtext).
	--     - Also, no longer supports querying by spell name.
	UnitDebuff = function(...)
		if addonTable.CURRENT_WOW_VERSION >= 30000 then
			local unitID, ID = ...;

			if type(ID) == "string" then
				for counter = 1, 40 do
					local auraName = UnitDebuff(unitID, counter);

					if ID == auraName then
						return UnitDebuff(unitID, counter);
					end
				end
			end
		else
			local parameters = { UnitDebuff(...) };

			table.insert(parameters, 2, "dummyReturn");

			return unpack(parameters);
		end
	end,


};

local MT = {
	__index = function(table, key)
		local classPrototype = Prototype[key];

		if classPrototype then
			if type(classPrototype) == "function" then
				return function(...)
					return classPrototype(...);
				end
			else
				return classPrototype;
			end
		else
			return function(...)
				return _G[key](...);
			end
		end
	end,
};

APIWrapper = setmetatable({}, MT);


-- don't load if class is wrong
local _, class = UnitClass("player")
if class ~= "PALADIN" then return end

local _, xmod = ...

xmod.retmodule = {}
xmod = xmod.retmodule

local qTaint = true -- will force queue check

-- thanks cremor
local GetTime, GetSpellCooldown, UnitBuff, UnitAura, UnitPower, UnitSpellHaste, UnitHealth, UnitHealthMax, GetTalentInfoByID, GetGlyphSocketInfo, IsUsableSpell, GetShapeshiftForm, max, min, SPELL_POWER_HOLY_POWER =
GetTime, GetSpellCooldown, UnitBuff, UnitAura, UnitPower, UnitSpellHaste, UnitHealth, UnitHealthMax, GetTalentInfoByID, GetGlyphSocketInfo, IsUsableSpell, GetShapeshiftForm, max, min, SPELL_POWER_HOLY_POWER
local db

-- debug if clcInfo detected
local debug
if clcInfo then debug = clcInfo.debug end

xmod.version = 3000001
xmod.defaults = {
	version = xmod.version,
	prio = "j right wis crus blood_d cmd cs how exo hw cons",
	rangePerSkill = false,
	howclash = 0, -- priority time for hammer of wrath
	csclash = 0, -- priority time for cs
	exoclash = 0, -- priority time for exorcism
	ssduration = 0, -- minimum duration on ss buff before suggesting refresh
}

-- @defines
--------------------------------------------------------------------------------
local idGCD = 20154 -- seal for gcd

-- spells
local idCrusaderStrike = 35395
local idJudgement = 20271
local idConsecration = 26573
local idHammerOfWrath = 24275
local idExorcism = 879 --27138
local idHolyWrath = 2812
local idDivineStorm = 53385
local idTemplarsVerdict = 85256

-- Cata Spells
local idZealotry = 85696
local idGuardian = 86150
local idInquisition = 84963

-- seals
local idSealOfCorruption = 31801
local idSealOfRighteousness = 20154
local idSealOfWisdom = 20165


-- ------
-- buffs
-- ------
local ln_buff_SealOfCorruption = GetSpellInfo(31801)
local ln_buff_SealOfWisdom = GetSpellInfo(20165)
local ln_buff_SealOfRighteousness = GetSpellInfo(20154)
local ln_buff_aow = GetSpellInfo(53486)
local ln_buff_DivinePurpose = GetSpellInfo(90174)
local ln_buff_Zealotry = GetSpellInfo(85696)

-- debuffs

-- status vars
local s1, s2
local s_ctime, s_otime, s_gcd, s_hp, s_dp, s_aw, s_ss, s_dc, s_fv, s_bc, s_haste, s_in_execute_range
local s_buff_SealOfCorruption, s_buff_SealOfWisdom, s_buff_SealOfRighteousness, s_buff_aow, s_buff_DivinePurpose, s_buff_Zealotry

-- the queue
local qn = {} -- normal queue
local q -- working queue

local function GetCooldown(id)
	local start, duration = GetSpellCooldown(id)
	if start == nil then return 100 end
	local cd = start + duration - s_ctime - s_gcd
	if cd < 0 then return 0 end
	return cd
end

---------------------------------------------------------------------------------

creatureType = UnitCreatureType("Target")

-- actions ---------------------------------------------------------------------
local actions = {

	--Templar's Verdict 3hp
	tv = {
		id = idTemplarsVerdict,
		GetCD = function()
		
			if (s1 ~= idTemplarsVerdict) and ((s_hp > 2) or (s_buff_DivinePurpose > 1)) and (IsSpellKnown(idTemplarsVerdict)) then
					return 0
				end
				
				return 100
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5 / s_haste
			s_hp = min(3, s_hp - 3)

		end,
		info = "Templar's Verdict (3 Holy Power)",
	},
	
		--Zealotry 3hp
	zeal = {
		id = idZealotry,
		GetCD = function()
		
			if (s1 ~= idZealotry) and (s_hp > 2) and (IsSpellKnown(idZealotry)) then
					return GetCooldown(idZealotry)
				end
				
				return 100
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5 / s_haste
			s_hp = min(3, s_hp - 0)

		end,
		info = "Zealotry",
	},
	
		--Inquisition 3hp
	inq = {
		id = idInquisition,
		GetCD = function()
		
			if (s1 ~= idInquisition) and (s_hp > 2) and (IsSpellKnown(idInquisition)) then
					return 0
				end
				
				return 100
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5 / s_haste
			s_hp = min(3, s_hp - 3)

		end,
		info = "Inquisiton (3 Holy Power) **MAY BE BUGGY**",
	},
	
	--Paladin Seal
	seal = {
		id = idSealOfCorruption,
		GetCD = function()
			if (s1 ~= idSealOfCorruption) and (IsSpellKnown(idSealOfCorruption)) and not((s_buff_SealOfCorruption > 1) or (s_buff_SealOfWisdom > 1) or (s_buff_SealOfRighteousness > 1)) then
				return GetCooldown(idSealOfCorruption)
			end
			return 100
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5 / s_haste

		end,
		info = "Seal of Truth/Insight",
	},

	--Crusader Strike
	cs = {
		id = idCrusaderStrike,
		GetCD = function()
			if (s1 ~= idCrusaderStrike) and (IsSpellKnown(idCrusaderStrike)) then
				return GetCooldown(idCrusaderStrike)
			end
			return 100
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5 / s_haste

			s_hp = max(0, s_hp + 1)

		end,
		info = "Crusader Strike",
	},

	--Judgement
	j = {
		id = idJudgement,
		GetCD = function()
			if (s1 ~= idJudgement) and (IsSpellKnown(idJudgement)) and IsUsableSpell(idJudgement) then
				return GetCooldown(idJudgement)
			end
			return 100
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5 / s_haste

		end,
		info = "Judgement",
	},

	--Consecration
	cons = {
		id = idConsecration,
		GetCD = function()
			if (s1 ~= idConsecration) and (IsSpellKnown(idConsecration)) and (((s_mana/s_manaMax)*100) > 80) then
				return GetCooldown(idConsecration)
			end
			return 100
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5 / s_haste

		end,
		info = "Consecration",
	},

	--Hammer of Wrath
	how = {
		id = idHammerOfWrath,
		GetCD = function()
			if (s1 ~= idHammerOfWrath) and (IsSpellKnown(idHammerOfWrath)) and IsUsableSpell(idHammerOfWrath) then
				return GetCooldown(idHammerOfWrath)
			end
			return 100
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5 / s_haste

		end,
		info = "Hammer Of Wrath",
	},

	--Exorcism AOW
	exo_aow = {
		id = idExorcism,
		GetCD = function()
			if (s1 ~= idExorcism) and (s_buff_aow > 1) then
				return GetCooldown(idExorcism)
			end
			return 100
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5 / s_haste

		end,
		info = "Exorcism w/ Art of War proc",
	},

	--Exorcism
	exo = {
		id = idExorcism,
		GetCD = function()
			if (s1 ~= idExorcism) then
				return GetCooldown(idExorcism)
			end
			return 100
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5 / s_haste

		end,
		info = "Exorcism",
	},

	--Holy Wrath
	hw = {
		id = idHolyWrath,
		GetCD = function()
			if (s1 ~= idHolyWrath) and (IsSpellKnown(idHolyWrath)) then
				return GetCooldown(idHolyWrath)
			end
			return 100
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5 / s_haste

		end,
		info = "Holy Wrath",
	},

	--Divine Storm --Cata makes DS an aoe version of CS. Save for AOE mode testing.
	ds3 = {
		id = idDivineStorm,
		GetCD = function()
		
		-- code for in range
		inRange = 0
			for i = 1, 40 do
				if UnitExists('nameplate' .. i) and IsSpellInRange('Crusader Strike', 'nameplate' .. i) == 1 then 
				inRange = inRange + 1
			end
		end
		-- ------
		
			if (s1 ~= idDivineStorm) and (IsSpellKnown(idDivineStorm)) and (inRange > 2) then
				return GetCooldown(idDivineStorm)
			end
			return 100
		end,
		UpdateStatus = function()
			s_ctime = s_ctime + s_gcd + 1.5 / s_haste

		end,
		info = "Divine Storm w/ 3 or more targets",
	},


}

--------------------------------------------------------------------------------



local function UpdateQueue()
	-- normal queue
	qn = {}
	for v in string.gmatch(db.prio, "[^ ]+") do
		if actions[v] then
			table.insert(qn, v)
		else
			print("clcretmodule - invalid action:", v)
		end
	end
	db.prio = table.concat(qn, " ")

	-- force reconstruction for q
	qTaint = true
end

local function GetBuff(buff)

	local left = 0
	local _, expires
	_, _, _, _, _, expires = APIWrapper.UnitBuff("player", buff, nil, "PLAYER")
	if expires then
		left = max(0, expires - s_ctime - s_gcd)
	end
	return left
end

local function GetDebuff(debuff)
	local left = 0
	local _, expires
	_, _, _, _, _, expires = APIWrapper.UnitDebuff("target", debuff, nil, "PLAYER")
	if expires then
		left = max(0, expires - s_ctime - s_gcd)
	end
	return left
end

-- reads all the interesting data // List of Buffs
local function GetStatus()
	-- current time
	s_ctime = GetTime()

	-- gcd value
	local start, duration = GetSpellCooldown(idGCD)
	s_gcd = start + duration - s_ctime
	if s_gcd < 0 then s_gcd = 0 end


	-- the buffs

	s_buff_SealOfCorruption = GetBuff(ln_buff_SealOfCorruption)
	s_buff_SealOfWisdom = GetBuff(ln_buff_SealOfWisdom)
	s_buff_SealOfRighteousness = GetBuff(ln_buff_SealOfRighteousness)
	s_buff_aow = GetBuff(ln_buff_aow)
	s_buff_DivinePurpose = GetBuff(ln_buff_DivinePurpose)
	s_buff_Zealotry = GetBuff(ln_buff_Zealotry)

	-- the debuffs


	-- client hp and haste
	s_haste = 1 -- + UnitSpellHaste("player") / 100
	s_mana = UnitPower("player", 0)
	s_manaMax = UnitPowerMax("player", 0)
	s_hp = UnitPower("player", 9)
	
end

-- remove all talents not available and present in rotation
-- adjust for modified skills present in rotation
local function GetWorkingQueue()
	q = {}
	local name, selected, available
	for k, v in pairs(qn) do
		-- see if it has a talent requirement
		-- if actions[v].reqTalent then
			-- see if the talent is activated
			-- _, name, _, selected, available = GetTalentInfoByID(actions[v].reqTalent, GetActiveSpecGroup())
			-- if name and selected and available then
				-- table.insert(q, v)
			-- end
		-- else
			table.insert(q, v)
		-- end
	end
end

local function GetNextAction()
	-- check if working queue needs updated due to glyph talent changes
	if qTaint then
		GetWorkingQueue()
		qTaint = false
	end

	local n = #q

	-- parse once, get cooldowns, return first 0
	for i = 1, n do
		local action = actions[q[i]]
		local cd = action.GetCD()
		if debug and debug.enabled then
			debug:AddBoth(q[i], cd)
		end
		if cd == 0 then
			return action.id, q[i]
		end
		action.cd = cd
	end

	-- parse again, return min cooldown
	local minQ = 1
	local minCd = actions[q[1]].cd
	for i = 2, n do
		local action = actions[q[i]]
		if minCd > action.cd then
			minCd = action.cd
			minQ = i
		end
	end
	return actions[q[minQ]].id, q[minQ]
end

-- exposed functions

-- this function should be called from addons
function xmod.Init()
	db = xmod.db
	UpdateQueue()
end

function xmod.GetActions()
	return actions
end

function xmod.Update()
	UpdateQueue()
end

function xmod.Rotation()
	s1 = nil
	GetStatus()
	if debug and debug.enabled then
		debug:Clear()
		debug:AddBoth("ctime", s_ctime)
		debug:AddBoth("gcd", s_gcd)
		debug:AddBoth("haste", s_haste)

	end
	local action
	s1, action = GetNextAction()
	if debug and debug.enabled then
		debug:AddBoth("s1", action)
		debug:AddBoth("s1Id", s1)
	end
	-- 
	s_otime = s_ctime -- save it so we adjust buffs for next
	actions[action].UpdateStatus()

	s_otime = s_ctime - s_otime

	-- adjust buffs
	s_buff_SealOfCorruption = max(0, s_buff_SealOfCorruption - s_otime)
	s_buff_SealOfWisdom = max(0, s_buff_SealOfWisdom - s_otime)
	s_buff_SealOfRighteousness = max(0, s_buff_SealOfRighteousness - s_otime)

	s_buff_aow = max(0, s_buff_aow - s_otime)
	s_buff_DivinePurpose = max(0, s_buff_DivinePurpose - s_otime)
	s_buff_Zealotry = max(0, s_buff_Zealotry - s_otime)

	
	if debug and debug.enabled then
		debug:AddBoth("csc", s_CrusaderStrikeCharges)
	end

	if debug and debug.enabled then
		debug:AddBoth("ctime", s_ctime)
		debug:AddBoth("otime", s_otime)
		debug:AddBoth("gcd", s_gcd)
		debug:AddBoth("haste", s_haste)
		debug:AddBoth("dJudgement", s_debuff_Judgement)
		
	end
	s2, action = GetNextAction()
	if debug and debug.enabled then
		debug:AddBoth("s2", action)
	end

	return s1, s2
end

-- event frame
local ef = CreateFrame("Frame", "clcRetModuleEventFrame") -- event frame
ef:Hide()
local function OnEvent()
	qTaint = true

end
ef:SetScript("OnEvent", OnEvent)
ef:RegisterEvent("PLAYER_ENTERING_WORLD")
ef:RegisterEvent("PLAYER_LEVEL_UP")