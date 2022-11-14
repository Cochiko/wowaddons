---------------
-- LIBRARIES --
---------------
local Locale = LibStub("AceLocale-3.0"):GetLocale("NameplateBoom")
local clh = CombatLogHelper
local NameplateBoom = LibStub("AceAddon-3.0"):NewAddon("NameplateBoom", "AceConsole-3.0", "AceEvent-3.0");

local debugHelper = GetDebugHelper(function() return NameplateBoom.db.global.logLevel end)
local info = debugHelper.Info
local debug = debugHelper.Debug
local trace = debugHelper.Trace

local animHelper = AnimationHelper

NameplateBoom.frame = CreateFrame("Frame", nil, UIParent);

---------------
-- CONSTANTS --
---------------
local ANIMATIONS = {
	["boom"] = "boom"
}

if not SCHOOL_MASK_PHYSICAL then -- XXX 9.1 PTR Support
	SCHOOL_MASK_PHYSICAL = Enum.Damageclass.MaskPhysical
	SCHOOL_MASK_HOLY = Enum.Damageclass.MaskHoly
	SCHOOL_MASK_FIRE = Enum.Damageclass.MaskFire
	SCHOOL_MASK_NATURE = Enum.Damageclass.MaskNature
	SCHOOL_MASK_FROST = Enum.Damageclass.MaskFrost
	SCHOOL_MASK_SHADOW = Enum.Damageclass.MaskShadow
	SCHOOL_MASK_ARCANE = Enum.Damageclass.MaskArcane
end

local DAMAGE_TYPE_COLORS = {
	[SCHOOL_MASK_PHYSICAL] = "FFFF00",
	[SCHOOL_MASK_HOLY] = "FFE680",
	[SCHOOL_MASK_FIRE] = "FF8000",
	[SCHOOL_MASK_NATURE] = "4DFF4D",
	[SCHOOL_MASK_FROST] = "80FFFF",
	[SCHOOL_MASK_SHADOW] = "8080FF",
	[SCHOOL_MASK_ARCANE] = "FF80FF",
	[SCHOOL_MASK_FIRE + SCHOOL_MASK_FROST + SCHOOL_MASK_ARCANE + SCHOOL_MASK_NATURE + SCHOOL_MASK_SHADOW] = "A330C9", -- Chromatic
	[SCHOOL_MASK_FIRE + SCHOOL_MASK_FROST + SCHOOL_MASK_ARCANE + SCHOOL_MASK_NATURE + SCHOOL_MASK_SHADOW + SCHOOL_MASK_HOLY] = "A330C9", -- Magic
	[SCHOOL_MASK_PHYSICAL + SCHOOL_MASK_FIRE + SCHOOL_MASK_FROST + SCHOOL_MASK_ARCANE + SCHOOL_MASK_NATURE + SCHOOL_MASK_SHADOW + SCHOOL_MASK_HOLY] = "A330C9", -- Chaos
	["melee"] = "FFFFFF",
	["pet"] = "CC8400"
};

--------
-- DB --
--------
local defaults = {
	global = {
		enabled = true, -- whether the addon should be enabled or not
		logLevel = debugHelper.LogLevels.INFO,
		animation = ANIMATIONS.boom,
	}
} ---@type Database

------------
-- LOCALS --
------------
local playerGuid;
local unitTokenToGuid = {}; ---@type table<string, string> table that maps unit ids (e.g. "nameplate1") to their GUID
local guidToUnitToken = {}; ---@type table<string, string> table that maps GUIDs to their unit id
local guidToNameplate = {}; ---@type table<string, NamePlateBase> table that maps GUIDs to their unit id
local animating = {} ---@type AnimatingNamePlate[] table of frames currently animating

------------
-- EVENTS --
------------
function NameplateBoom:OnInitialize()
	-- setup db
	self.db = LibStub("AceDB-3.0"):New("NameplateBoomDB", defaults, true); ---@type Database

	-- setup chat commands
	self:RegisterChatCommand("boom", "OpenMenu");

	-- setup menu
	self:RegisterMenu();

	-- if the addon is turned off in db, turn it off
	if (self.db.global.enabled == false) then
		self:Disable();
	end

	info("NameplateBoom Initialized")

end

function NameplateBoom:OnEnable()
	playerGuid = UnitGUID("player");

	self:RegisterEvent("NAME_PLATE_UNIT_ADDED");
	self:RegisterEvent("NAME_PLATE_UNIT_REMOVED");
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");

	self.db.global.enabled = true;
end

function NameplateBoom:OnDisable()
	self:UnregisterAllEvents();

	for fontString, _ in pairs(animating) do
		-- recycleFontString(fontString);
	end

	self.db.global.enabled = false;
end
function NameplateBoom:NAME_PLATE_UNIT_ADDED(event, unitToken)
	local guid = UnitGUID(unitToken);

	unitTokenToGuid[unitToken] = guid;
	guidToUnitToken[guid] = unitToken;

	local namePlate = C_NamePlate.GetNamePlateForUnit(unitToken)
	if namePlate then
		guidToNameplate[guid] = namePlate
		trace("found nameplate for: ".. unitToken)
	end
end

function NameplateBoom:NAME_PLATE_UNIT_REMOVED(event, unitToken)
	local guid = unitTokenToGuid[unitToken];

	unitTokenToGuid[unitToken] = nil;
	guidToUnitToken[guid] = nil;
	guidToNameplate[guid] = nil;

	trace("removing nameplate for: "..unitToken)
	-- recycle any fontStrings attached to this unit
	for fontString, _ in pairs(animating) do
		if fontString.unit == unitToken then
			-- recycleFontString(fontString);
		end
	end
end

function NameplateBoom:COMBAT_LOG_EVENT_UNFILTERED()
	-- Not sure the return does anything here
	return NameplateBoom:FilterCombatLogEvent(CombatLogGetCurrentEventInfo())
end

----------------
-- COMBAT LOG --
----------------
function NameplateBoom:FilterCombatLogEvent(_, clue, _, sourceGuid, _, sourceFlags, _, destGuid, _, _, _, ...)
	if playerGuid == destGuid then return end -- Filter out events targeted at the player for now
	if playerGuid == sourceGuid then
		local destUnit = guidToUnitToken[destGuid];
		if destUnit then
			-- Attack/spell successfully dealt damage
			if clh.IsDamageEvent(clue) then
				local spellName, amount, overkill, school, critical, spellId;
				if clh.IsMeleeEvent(clue) then
					spellName, amount, overkill, _, _, _, _, critical = "melee", ...;
				elseif clh.IsEnvironmentalEvent(clue) then
					spellName, amount, overkill, school, _, _, _, critical = ...;
				else
					spellId, spellName, _, amount, overkill, school, _, _, _, critical = ...;
				end
				self:AnimateDamageEvent(destGuid, spellName, amount, overkill, school, critical, spellId);
			-- Attack/Spell missed
			elseif clh.IsMissEvent(clue) then
				local spellName, missType, spellId;

				if clh.IsMeleeEvent(clue) then
					if destGuid == playerGuid then
						missType = ...;
					else
						missType = "melee";
					end
				else
					spellId, spellName, _, missType = ...;
				end
				self:MissEvent(destGuid, spellName, missType, spellId);
			end
		end
	elseif clh.IsPetOrGuardianEvent(sourceFlags) then
		local destUnit = guidToUnitToken[destGuid];
		if destUnit then
			-- Pet attack/spell successfully dealt damage
			if clh.IsDamageEvent(clue) then
				local spellName, amount, overkill, critical, spellId;
				if clh.IsMeleeEvent(clue) then
					spellName, amount, overkill, _, _, _, _, critical, _, _, _ = "pet", ...;
				elseif clh.IsEnvironmentalEvent(clue) then
					spellName, amount, overkill, _, _, _, _, critical= ...;
				else
					spellId, spellName, _, amount, overkill, _, _, _, _, critical = ...;
				end
				self:AnimateDamageEvent(destGuid, spellName, amount, overkill, "pet", critical, spellId);
			end
		-- If we wanted to show pet miss events, it would be here in a separate elseif block
		end
	end
end

---------------
-- ANIMATION --
---------------
function NameplateBoom:AnimateDamageEvent(destGuid, spellName, amount, overkill, school, isCrit, spellId)
	local text, animation, pow, size, alpha;

	local isAutoAttack = clh.IsAutoAttackSpell(spellName);

	local nameplate = guidToNameplate[destGuid]
	if not nameplate then return end

	-- select an animation
	if (isAutoAttack and isCrit) then
		animation = defaults.global.defaultAnimation
		pow = true;
	elseif (isAutoAttack) then
		animation = defaults.global.defaultAnimation
		pow = false;
	elseif (isCrit) then
		animation = defaults.global.defaultAnimation
		pow = true;
	elseif (not isAutoAttack and not isCrit) then
		animation = defaults.global.defaultAnimation
		pow = false;
	end


	nameplate.UnitFrame.healthBar.border:SetVertexColor()
	debug("damage! (isAutoAttack: "..tostring(isAutoAttack)..", pow: "..tostring(pow)..", spellName: "..spellName..")")

	return
end

function NameplateBoom:AnimateMissEvent(guid, spellName, amount, overkill, school, isCrit, spellId)
	debug("miss!")
end

------------------
-- OPTIONS MENU --
------------------
local menu = {
	name = "NameplateBoom",
	handler = NameplateBoom,
	type = 'group',
	args = {

		enable = {
			type = 'toggle',
			name = Locale["Enable NameplateBoom!!"],
			desc = Locale["Whether to enable the addon."],
			get = "IsEnabled",
			set = function(_, newValue) if (not newValue) then NameplateBoom:Disable(); else NameplateBoom:Enable(); end end,
			order = 4,
			width = "full",
		},

		disableBlizzardFCT = {
			type = 'toggle',
			name = Locale["Enable BlizzardSCT"],
			desc = Locale["Whether to enable Blizzard's SCT."],
			get = function(_, newValue) return GetCVar("floatingCombatTextCombatDamage") == "1" end,
			set = function(_, newValue)
				if (newValue) then
					SetCVar("floatingCombatTextCombatDamage", 1);
				else
					SetCVar("floatingCombatTextCombatDamage", 0);
				end
			end,
			order = 5,
			width = "full",
		},

		--enableDebug = {
		--	type = 'toggle',
		--	name = Locale["Enable Debug"],
		--	desc = Locale["Whether to enable debug logs."],
		--	get = function(_, newValue) return NameplateBoom.db.global.logLevel == debugHelper.LogLevels.DEBUG end,
		--	set = function(_, isEnabled)
		--		if isEnabled then
		--			NameplateBoom.db.global.logLevel = debugHelper.LogLevels.DEBUG
		--		else
		--			NameplateBoom.db.global.logLevel = defaults.global.logLevel
		--		end
		--	end,
		--	order = 6,
		--	width = "full",
		--},

		logLevel = {
			type = 'select',
			name = Locale["Log Level"],
			desc = Locale["Level of logs should be printed out in chat"],
			get = function() return NameplateBoom.db.global.logLevel end,
			set = function(_, newLevel) NameplateBoom.db.global.logLevel = newLevel end,
			values = {
				[debugHelper.LogLevels.INFO] = "Info",
				[debugHelper.LogLevels.DEBUG] = "Debug",
				[debugHelper.LogLevels.TRACE] = "Trace",
			},
			order = 6,
		},
	},
};

function NameplateBoom:OpenMenu()
	-- call twice as a temp fix for a blizz bug with slash commands
	InterfaceOptionsFrame_OpenToCategory(self.menu);
	InterfaceOptionsFrame_OpenToCategory(self.menu);
end

function NameplateBoom:RegisterMenu()
	LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable("NameplateBoom", menu);
	self.menu = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("NameplateBoom", "NameplateBoom");
end
