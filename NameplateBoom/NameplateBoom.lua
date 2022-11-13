---------------
-- LIBRARIES --
---------------
local Locale = LibStub("AceLocale-3.0"):GetLocale("NameplateBoom")
local clh = CombatLogHelper
local NameplateBoom = LibStub("AceAddon-3.0"):NewAddon("NameplateBoom", "AceConsole-3.0", "AceEvent-3.0");

local debugHelper = GetDebugHelper(function() return NameplateBoom.db.global.logLevel end)
local info = debugHelper.Info
local debug = debugHelper.Debug

NameplateBoom.frame = CreateFrame("Frame", nil, UIParent);

---------------
-- CONSTANTS --
---------------
local ANIMATIONS = {}
ANIMATIONS["boom"] = "boom"

--------
-- DB --
--------
local defaults = {
	global = {
		enabled = true, -- whether the addon should be enabled or not
		logLevel = debugHelper.LogLevels.INFO,
		animation = ANIMATIONS.boom -- the default animation
	}
}

------------
-- LOCALS --
------------
local playerGuid;
local unitTokenToGuid = {}; -- table that maps unit ids (e.g. "nameplate1") to their GUID
local guidToUnitToken = {}; -- table that maps GUIDs to their unit id
local animating = {} ---@type AnimatingNamePlate[] table of frames currently animating

------------
-- EVENTS --
------------
function NameplateBoom:OnInitialize()
	-- setup db
	self.db = LibStub("AceDB-3.0"):New("NameplateBoomDB", defaults, true);

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
		debug("found nameplate for: ".. unitToken)
	end
end

function NameplateBoom:NAME_PLATE_UNIT_REMOVED(event, unitToken)
	local guid = unitTokenToGuid[unitToken];

	unitTokenToGuid[unitToken] = nil;
	guidToUnitToken[guid] = nil;

	debug("removing nameplate for: "..unitToken)
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

function NameplateBoom:FilterCombatLogEvent(_, clue, _, sourceGUID, _, sourceFlags, _, destGUID, _, _, _, ...)
	if playerGuid == destGUID then return end -- Filter out events targeted at the player for now
	if playerGuid == sourceGUID then
		local destUnit = guidToUnitToken[destGUID];
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
				self:DamageEvent(destGUID, spellName, amount, overkill, school, critical, spellId);
			-- Attack/Spell missed
			elseif clh.IsMissEvent(clue) then
				local spellName, missType, spellId;

				if clh.IsMeleeEvent(clue) then
					if destGUID == playerGuid then
						missType = ...;
					else
						missType = "melee";
					end
				else
					spellId, spellName, _, missType = ...;
				end
				self:MissEvent(destGUID, spellName, missType, spellId);
			end
		end
	elseif isPetOrGuardianEvent(sourceFlags) then
		local destUnit = guidToUnitToken[destGUID];
		if destUnit then
			-- Pet attack/spell successfully dealt damage
			if isDamageEvent(clue) then
				local spellName, amount, overkill, critical, spellId;
				if isMeleeEvent(clue) then
					spellName, amount, overkill, _, _, _, _, critical, _, _, _ = "pet", ...;
				elseif isEnvironmentalEvent(clue) then
					spellName, amount, overkill, _, _, _, _, critical= ...;
				else
					spellId, spellName, _, amount, overkill, _, _, _, _, critical = ...;
				end
				self:DamageEvent(destGUID, spellName, amount, overkill, "pet", critical, spellId);
			end
		-- If we wanted to show pet miss events, it would be here in a separate elseif block
		end
	end
end

---------------
-- ANIMATION --
---------------
function NameplateBoom:DamageEvent(guid, spellName, amount, overkill, school, isCrit, spellId)
	local text, animation, pow, size, alpha;
	local isAutoAttack = clh.IsAutoAttackSpell(spellName);

	-- select an animation
	if (isAutoAttack and isCrit) then
		animation = defaults.global.animation
		pow = true;
	elseif (isAutoAttack) then
		animation = defaults.global.animation
		pow = false;
	elseif (isCrit) then
		animation = defaults.global.animation
		pow = true;
	elseif (not isAutoAttack and not isCrit) then
		animation = defaults.global.animation
		pow = false;
	end

	-- skip if this damage event is disabled
	if (animation == "disabled") then
		return;
	end;

	local unit = guidToUnit[guid];
	local isTarget = unit and UnitIsUnit(unit, "target");

	if (self.db.global.useOffTarget and not isTarget and playerGUID ~= guid) then
		size = self.db.global.offTargetFormatting.size;
		alpha = self.db.global.offTargetFormatting.alpha;
	else
		size = self.db.global.formatting.size;
		alpha = self.db.global.formatting.alpha;
	end

	-- truncate
	if (self.db.global.truncate and amount >= 1000000 and self.db.global.truncateLetter) then
		text = string.format("%.1fM", amount / 1000000);
	elseif (self.db.global.truncate and amount >= 10000) then
		text = string.format("%.0f", amount / 1000);

		if (self.db.global.truncateLetter) then
			text = text.."k";
		end
	elseif (self.db.global.truncate and amount >= 1000) then
		text = string.format("%.1f", amount / 1000);

		if (self.db.global.truncateLetter) then
			text = text.."k";
		end
	else
		if (self.db.global.commaSeperate) then
			text = commaSeperate(amount);
		else
			text = tostring(amount);
		end
	end

	-- color text
	text = self:ColorText(text, guid, playerGuid, school, spellName);

	-- shrink small hits
	if (self.db.global.sizing.smallHits or self.db.global.sizing.smallHitsHide) and playerGUID ~= guid then
		if (not lastDamageEventTime or (lastDamageEventTime + SMALL_HIT_EXPIRY_WINDOW < GetTime())) then
			numDamageEvents = 0;
			runningAverageDamageEvents = 0;
		end

		runningAverageDamageEvents = ((runningAverageDamageEvents*numDamageEvents) + amount)/(numDamageEvents + 1);
		numDamageEvents = numDamageEvents + 1;
		lastDamageEventTime = GetTime();

		if ((not isCrit and amount < SMALL_HIT_MULTIPIER*runningAverageDamageEvents)
				or (isCrit and amount/2 < SMALL_HIT_MULTIPIER*runningAverageDamageEvents)) then
			if (self.db.global.sizing.smallHitsHide) then
				-- skip this damage event, it's too small
				return;
			else
				size = size * self.db.global.sizing.smallHitsScale;
			end
		end
	end

	-- embiggen crit's size
	if (self.db.global.sizing.crits and isCrit) and playerGUID ~= guid then
		if (isAutoAttack and not self.db.global.sizing.autoattackcritsizing) then
			-- don't embiggen autoattacks
			pow = false;
		else
			size = size * self.db.global.sizing.critsScale;
		end
	end

	-- make sure that size is larger than 5
	if (size < 5) then
		size = 5;
	end

	if (overkill > 0 and self.db.global.shouldDisplayOverkill) then
		text = self:ColorText(text.." Overkill("..overkill..")", guid, playerGUID, school, spellName);
		self:DisplayTextOverkill(guid, text, size, animation, spellId, pow, spellName);
	else
		self:DisplayText(guid, text, size, animation, spellId, pow, spellName);
	end
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
