--
--	Grail Research
--
--	Optional data collection for people who help to complete the Grail database.
--	Nothing in this file runs unless it has been switched on with
--		/grail research
--	which stores the choice in the saved variables.  When it is off, the only code
--	that executes is the tiny event handler at the bottom of the file.
--
--	What is collected (everything goes into the normal tracking data):
--		LIGHT_QUEST_COMPLETE	a quest Blizzard reports as completed that Grail did not see being turned in
--		WARBAND_QUEST_COMPLETE	quests that became completed while this character was logged out
--		GOSSIP_QUEST_LINK		the gossip option chosen right before such a quest completed
--		BOOK_QUEST_LINK			the readable object opened right before such a quest completed
--		VIGNETTE_QUEST_LINK		a vignette that vanished right before such a quest completed (late=N: it vanished
--								N seconds after the quest was noticed)
--		VIGNETTE_REP_LINK		a vignette that vanished together with a reputation change
--		QUESTPIN				quest offers that appear or disappear on the map after accepting or turning in a quest
--								(trigger=reset:daily/... or reset:weekly/... when a quest reset happened in between)
--
--	UTF-8 file
--

if nil == Grail then return end

local Grail = Grail
local strformat, strmatch, strsub, gmatch = string.format, string.match, string.sub, string.gmatch
local strsplit = strsplit
local tinsert, tconcat = table.insert, table.concat
local pairs, ipairs, next, select, tonumber, tostring, type = pairs, ipairs, next, select, tonumber, tostring, type
local pcall = pcall
local GetTime = GetTime
local hooksecurefunc = hooksecurefunc
local C_Timer = C_Timer

local R = {
	version = 1,
	linkWindow = 10,			-- seconds within which two observations are treated as belonging together
	pollGap = 2,				-- minimum seconds between two comparisons of the completed quests
	pollGapBusy = 10,			-- the same for triggers that fire very often
	diffDelays = { 1, 3, 7, 15 },	-- seconds after a quest action at which the map offers are compared
	maxLoginLines = 300,		-- cap for the lines written when many quests completed while logged out
	maxAtOnce = 50,				-- more newly completed quests than this in one comparison is late quest data, not gameplay
	resetWindow = 60,			-- seconds after a quest reset in which map offer changes are credited to the reset
	}
Grail.research = R

--	Chat output from an event handler taints the chat frame, so it is routed the same
--	way the main file does it and only happens when debug is on.
local function securePrint(...)
	if securecallfunction then
		securecallfunction(print, ...)
	else
		print(...)
	end
end

local function enabled()
	return nil ~= Grail.GDE and Grail.GDE.research
end

local function log(message)
	Grail:_AddTrackingMessage(message)
	if Grail.GDE.debug then
		securePrint(message)
	end
end

local function playerMap()
	return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
end

local function guidPart(guid, position)
	return (select(position, strsplit("-", guid)))
end

--	----------------------------------------------------------------------------------
--	Completed quests: one comparison shortly after something happened that can complete
--	a quest silently, instead of one on every quest log update.
--	----------------------------------------------------------------------------------

function R.PrimeCompleted()
	R.completed = {}
	if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
		local ids = C_QuestLog.GetAllCompletedQuestIDs()
		if ids then
			for _, questId in ipairs(ids) do
				R.completed[questId] = true
			end
		end
	end
	R.lastPoll = GetTime()
end

function R.RequestCheck(reason, gap)
	if not enabled() or nil == R.completed then return end
	R.pollReason = R.pollReason or reason
	if R.pollPending then return end
	R.pollPending = true
	local wait = 1
	local remaining = (gap or R.pollGap) - (GetTime() - (R.lastPoll or 0))
	if remaining > wait then wait = remaining end
	C_Timer.After(wait, R.RunCheck)
end

function R.RunCheck()
	R.pollPending = false
	if not enabled() or nil == R.completed then return end
	if InCombatLockdown() then
		R.pollAfterCombat = true
		return
	end
	if not (C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs) then return end
	local reason = R.pollReason or "unknown"
	R.pollReason = nil
	if nil == next(R.completed) then
		--	The client had no completed quests to report when research was switched on
		--	(quest data can arrive late).  Take the baseline now instead of reporting
		--	every completed quest as new.
		R.PrimeCompleted()
		R.TryLoginDifference()
		return
	end
	R.lastPoll = GetTime()
	local ids = C_QuestLog.GetAllCompletedQuestIDs()
	if not ids then return end
	local found
	for _, questId in ipairs(ids) do
		if not R.completed[questId] then
			R.completed[questId] = true
			found = found or {}
			tinsert(found, questId)
		end
	end
	if found then
		if #found > R.maxAtOnce then
			log(strformat("LIGHT_QUEST_COMPLETE [%s]: %d quests appeared at once, treated as late quest data and not processed", reason, #found))
		else
			R.HandleNewlyCompleted(found, reason)
		end
	end
end

--	A quest Grail does not know as completed is reported and marked.  Unless the quest
--	was just turned in the normal way, it is also matched against what the player did
--	in the last few seconds.
function R.HandleNewlyCompleted(found, reason)
	local now = GetTime()
	local coordinates
	for _, questId in ipairs(found) do
		local title = Grail:QuestName(questId) or "UNKNOWN"
		if not Grail:IsQuestCompleted(questId) then
			coordinates = coordinates or tostring(Grail:Coordinates())
			log(strformat("LIGHT_QUEST_COMPLETE [%s]: quest=%d title=%s coords=%s", reason, questId, title, coordinates))
			Grail:_MarkQuestComplete(questId, true)
		end
		local turnedInAt = R.turnedIn and R.turnedIn[questId]
		if nil == turnedInAt or (now - turnedInAt) > 3 * R.linkWindow then
			R.LinkGossip(questId, title, now)
			R.LinkBook(questId, title, now)
			R.LinkVignettes(questId, now)
		end
	end
end

function R.TryLoginDifference()
	if R.wantLoginDifference and nil ~= R.completed and nil ~= next(R.completed) then
		R.wantLoginDifference = false
		R.LoginDifference()
	end
end

--	Quests that are completed now but were not at the end of the previous session of
--	this character.  previousCompleted is a copy of Grail's own record taken before
--	Grail refreshes it for the new session.
function R.LoginDifference()
	local previous = R.previousCompleted
	R.previousCompleted = nil
	if type(previous) ~= "table" or nil == next(previous) or nil == R.completed then return end
	local count, written = 0, 0
	for questId in pairs(R.completed) do
		local index = math.floor((questId - 1) / 32)
		local offset = questId - (index * 32) - 1
		local bits = previous[index]
		if nil == bits or bit.band(bits, 2 ^ offset) == 0 then
			count = count + 1
			if written < R.maxLoginLines then
				written = written + 1
				log(strformat("WARBAND_QUEST_COMPLETE [login]: quest=%d title=%s", questId, Grail:QuestName(questId) or "UNKNOWN"))
			end
		end
	end
	if count > written then
		log(strformat("WARBAND_QUEST_COMPLETE [login]: %d more quests not listed", count - written))
	end
end

--	----------------------------------------------------------------------------------
--	Gossip.  Blizzard's gossip window calls C_GossipInfo.SelectOptionByIndex with the
--	orderIndex of the option, both for a click and when it picks the only option by
--	itself.  Other addons may call C_GossipInfo.SelectOption with the option id.
--	----------------------------------------------------------------------------------

function R.OnGossipShow()
	local targetName, npcId, coordinates = Grail:TargetInformation()
	local options = C_GossipInfo and C_GossipInfo.GetOptions and C_GossipInfo.GetOptions() or {}
	R.gossip = { npcName = targetName, npcId = npcId, coords = coordinates, options = options }
end

function R.OnGossipSelected(byIndex, value)
	if not enabled() then return end
	local gossip = R.gossip
	if nil == gossip then return end
	local chosen
	for _, option in ipairs(gossip.options) do
		if (byIndex and option.orderIndex == value) or (not byIndex and option.gossipOptionID == value) then
			chosen = option
			break
		end
	end
	R.lastGossip = {
		npcName = gossip.npcName, npcId = gossip.npcId, coords = gossip.coords,
		optionId = chosen and chosen.gossipOptionID or (not byIndex and value or nil),
		optionName = chosen and chosen.name or nil,
		time = GetTime(),
		}
	R.RequestCheck("gossip option")
end

function R.LinkGossip(questId, title, now)
	local gossip = R.lastGossip
	if nil == gossip or (now - gossip.time) > R.linkWindow or nil == gossip.optionId then return end
	local key = strformat("%d|%s|%s", questId, tostring(gossip.npcId), tostring(gossip.optionId))
	if GrailDatabase.gossipQuestLinks[key] then return end
	GrailDatabase.gossipQuestLinks[key] = true
	log(strformat("GOSSIP_QUEST_LINK: quest=%d title=%s npc=%s(%s) option=%s(id=%s) coords=%s",
		questId, title, tostring(gossip.npcName), tostring(gossip.npcId),
		tostring(gossip.optionName), tostring(gossip.optionId), tostring(gossip.coords)))
end

--	----------------------------------------------------------------------------------
--	Readable objects
--	----------------------------------------------------------------------------------

function R.OnItemTextReady()
	local targetName, npcId, coordinates = Grail:TargetInformation()
	R.lastBook = { name = targetName, npcId = npcId, coords = coordinates, time = GetTime() }
	R.RequestCheck("book")
end

function R.LinkBook(questId, title, now)
	local book = R.lastBook
	if nil == book or (now - book.time) > R.linkWindow then return end
	log(strformat("BOOK_QUEST_LINK: quest=%d title=%s | book=%s(%s) | coords=%s",
		questId, title, tostring(book.name), tostring(book.npcId), tostring(book.coords)))
end

--	----------------------------------------------------------------------------------
--	Vignettes.  Links are stored per vignette id (the sixth part of the GUID), not per
--	spawn, so killing the same rare again adds to a counter instead of a new entry.
--	----------------------------------------------------------------------------------

function R.VignetteSnapshot()
	local snapshot = {}
	if not (C_VignetteInfo and C_VignetteInfo.GetVignettes and C_VignetteInfo.GetVignetteInfo) then return snapshot end
	local mapId = playerMap()
	local guids = C_VignetteInfo.GetVignettes()
	if guids then
		for _, guid in ipairs(guids) do
			local info = C_VignetteInfo.GetVignetteInfo(guid)
			if info then
				local coordinates
				if mapId and C_VignetteInfo.GetVignettePosition then
					local position = C_VignetteInfo.GetVignettePosition(guid, mapId)
					if position then
						coordinates = strformat("%d:%.2f,%.2f", mapId, position.x * 100, position.y * 100)
					end
				end
				snapshot[guid] = {
					id = info.vignetteID or tonumber(guidPart(guid, 6)),
					spawn = guidPart(guid, 7),
					name = info.name,
					coords = coordinates,
					}
			end
		end
	end
	return snapshot
end

function R.OnVignettesUpdated()
	local current = R.VignetteSnapshot()
	local previous = R.vignettes
	R.vignettes = current
	if nil == previous then return end		-- the first snapshot only sets the baseline
	local now = GetTime()
	R.goneVignettes = R.goneVignettes or {}
	for guid, entry in pairs(R.goneVignettes) do
		if (now - entry.time) > 3 * R.linkWindow then
			R.goneVignettes[guid] = nil
		end
	end
	local fresh = {}
	for guid, entry in pairs(previous) do
		if nil == current[guid] and nil ~= entry.id then
			entry.time = now
			entry.linked = {}
			R.goneVignettes[guid] = entry
			tinsert(fresh, entry)
		end
	end
	if #fresh > 0 then
		R.LinkReputation(now)
		R.LinkWaiting(now, fresh)
		R.RequestCheck("vignette")
	end
end

function R.VignetteEntry(vignette)
	local db = GrailDatabase.vignetteQuestLinks
	local entry = db[vignette.id]
	if nil == entry then
		entry = { quests = {}, npcs = {}, reps = {} }
		db[vignette.id] = entry
	end
	entry.name = vignette.name or entry.name
	entry.coords = vignette.coords or entry.coords
	return entry
end

local function recentlyGone(now)
	local list = {}
	if R.goneVignettes then
		for _, entry in pairs(R.goneVignettes) do
			if (now - entry.time) <= R.linkWindow then
				tinsert(list, entry)
			end
		end
	end
	return list
end

--	One vanished vignette linked to one quest.  late is how many seconds the vignette
--	vanished after the quest had been noticed (nil when it vanished first).
local function linkVignette(vignette, questId, candidates, now, late)
	local loot = R.lastLoot
	if nil ~= loot and (now - loot.time) > R.linkWindow then loot = nil end
	local entry = R.VignetteEntry(vignette)
	entry.quests[questId] = (entry.quests[questId] or 0) + 1
	local npcId = nil
	if nil ~= loot and nil ~= loot.spawn and loot.spawn == vignette.spawn then
		npcId = loot.npcId
		entry.npcs[npcId] = (entry.npcs[npcId] or 0) + 1
	end
	--	candidates tells how many vignettes vanished at the same time; 1 is an unambiguous link
	log(strformat("VIGNETTE_QUEST_LINK: vignetteId=%s name=%s | quest=%d | npcId=%s | coords=%s | candidates=%d%s",
		tostring(vignette.id), tostring(vignette.name), questId, tostring(npcId), tostring(vignette.coords), candidates,
		late and strformat(" | late=%.1f", late) or ""))
end

--	The quest comparison can run before the client removes the vignette of a looted
--	object.  A quest found without a vanished vignette therefore waits for one for a
--	short time (see LinkWaiting).
function R.LinkVignettes(questId, now)
	local gone = recentlyGone(now)
	if 0 == #gone then
		R.waitingQuests = R.waitingQuests or {}
		R.waitingQuests[questId] = now
		return
	end
	for _, vignette in ipairs(gone) do
		linkVignette(vignette, questId, #gone, now)
	end
end

--	fresh are the vignettes that vanished with the update that is being handled.
function R.LinkWaiting(now, fresh)
	local waiting = R.waitingQuests
	if nil == waiting then return end
	local quests = {}
	for questId, since in pairs(waiting) do
		if (now - since) > R.linkWindow then
			waiting[questId] = nil
		else
			tinsert(quests, questId)
		end
	end
	table.sort(quests)
	for _, questId in ipairs(quests) do
		local late = now - waiting[questId]
		waiting[questId] = nil
		for _, vignette in ipairs(fresh) do
			linkVignette(vignette, questId, #fresh, now, late)
		end
	end
end

function R.OnReputation(tag)
	local now = GetTime()
	R.recentReputation = R.recentReputation or {}
	tinsert(R.recentReputation, { tag = tag, time = now })
	R.LinkReputation(now)
end

function R.LinkReputation(now)
	local reputations = R.recentReputation
	if nil == reputations then return end
	local kept = {}
	for _, reputation in ipairs(reputations) do
		if (now - reputation.time) <= R.linkWindow then
			tinsert(kept, reputation)
		end
	end
	R.recentReputation = kept
	if 0 == #kept then return end
	local gone = recentlyGone(now)
	for _, vignette in ipairs(gone) do
		for _, reputation in ipairs(kept) do
			if not vignette.linked[reputation.tag] then
				vignette.linked[reputation.tag] = true
				local entry = R.VignetteEntry(vignette)
				entry.reps[reputation.tag] = (entry.reps[reputation.tag] or 0) + 1
				log(strformat("VIGNETTE_REP_LINK: vignetteId=%s name=%s | rep=%s | coords=%s | candidates=%d",
					tostring(vignette.id), tostring(vignette.name), reputation.tag, tostring(vignette.coords), #gone))
			end
		end
	end
end

function R.OnLootOpened()
	--	The GUID of a corpse can be a protected value; anything that goes wrong here just
	--	means the loot source is not known for this link.
	R.lastLoot = nil
	pcall(function()
		local guid = GetLootSourceInfo(1)
		if guid then
			R.lastLoot = { npcId = tonumber(guidPart(guid, 6)), spawn = guidPart(guid, 7), time = GetTime() }
		end
	end)
end

--	Brings the links recorded by earlier versions (one entry per spawn and source text)
--	into the per-vignette structure.  The old table is left as it is.
function R.MigrateOldVignetteLinks()
	local old = GrailDatabase.vignetteLinks
	if type(old) ~= "table" or GrailDatabase.researchVignettesMigrated then return end
	for key, name in pairs(old) do
		local guid, source = strmatch(key, "^([^|]+)|(.*)$")
		if guid and strsub(guid, 1, 9) == "Vignette-" then
			local id = tonumber(guidPart(guid, 6))
			if id then
				local entry = R.VignetteEntry({ id = id, name = (type(name) == "string") and name or nil })
				local quests = strmatch(source, "quests=([%d,]+)")
				if quests then
					for questId in gmatch(quests, "%d+") do
						questId = tonumber(questId)
						entry.quests[questId] = (entry.quests[questId] or 0) + 1
					end
				end
				local npcId = tonumber(strmatch(source, "npcId=(%d+)"))
				if npcId then
					entry.npcs[npcId] = (entry.npcs[npcId] or 0) + 1
				end
				local reputation = strmatch(source, "rep=([^|]+)")
				if reputation then
					reputation = strmatch(reputation, "^%s*(.-)%s*$")
					entry.reps[reputation] = (entry.reps[reputation] or 0) + 1
				end
				local coordinates = strmatch(source, "coords=([^|]+)")
				if coordinates and nil == entry.coords then
					entry.coords = strmatch(coordinates, "^%s*(.-)%s*$")
				end
			end
		end
	end
	GrailDatabase.researchVignettesMigrated = true
end

--	----------------------------------------------------------------------------------
--	Quest offers on the map.  Blizzard builds its quest offer and quest hub pins from
--	the functions used here, so the map does not have to be open and no pin frame is
--	touched.  The pins themselves are only read as a fallback, when the functions are
--	missing or return nothing while the map is showing the map in question.
--	----------------------------------------------------------------------------------

local function addOffer(offers, questId, kind, x, y, name)
	questId = tonumber(questId)
	if nil == questId or questId <= 0 or nil ~= offers[questId] then return end
	offers[questId] = { kind = kind, x = x, y = y, name = name }
end

function R.OffersFromPins(mapId)
	local offers = {}
	if not (WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame:GetMapID() == mapId) then return offers end
	local pools = WorldMapFrame.pinPools
	if type(pools) ~= "table" then return offers end
	--	Only pools that already exist are read; nothing is created and the canvas is not walked.
	pcall(function()
		local offerPool = pools["QuestOfferPinTemplate"]
		if offerPool and offerPool.EnumerateActive then
			for pin in offerPool:EnumerateActive() do
				addOffer(offers, pin.questID, pin.isCampaign and "campaign_offer" or "offer", pin.normalizedX, pin.normalizedY, pin.questName)
			end
		end
		local hubPool = pools["QuestHubPinTemplate"]
		if hubPool and hubPool.EnumerateActive then
			for pin in hubPool:EnumerateActive() do
				local provider = pin.dataProvider
				if provider and type(provider.questOffers) == "table" then
					for questId, info in pairs(provider.questOffers) do
						addOffer(offers, questId, info.isCampaign and "campaign_offer" or "offer", info.x, info.y, info.questName)
					end
				end
			end
		end
	end)
	return offers
end

--	Returns the offers of a map keyed by quest id, and where they came from ("api" or "pins").
--	The API part is Grail:_MapQuestOffers, which the map scan in the main file uses as well.
function R.MapOffers(mapId)
	local offers, source = {}, "api"
	if nil == mapId then return offers, source end
	if Grail._MapQuestOffers then
		offers = Grail:_MapQuestOffers(mapId)
	end
	if nil ~= next(offers) then
		return offers, source
	end
	local fromPins = R.OffersFromPins(mapId)
	if nil ~= next(fromPins) then
		offers, source = fromPins, "pins"
	end
	--	Offers read from the pins still need their quest hub.
	if source == "pins" and C_AreaPoiInfo and C_AreaPoiInfo.GetQuestHubsForMap and C_QuestHub and C_QuestHub.IsQuestCurrentlyRelatedToHub then
		local hubs = C_AreaPoiInfo.GetQuestHubsForMap(mapId)
		if hubs and #hubs > 0 then
			for questId, offer in pairs(offers) do
				for _, hubId in ipairs(hubs) do
					if C_QuestHub.IsQuestCurrentlyRelatedToHub(questId, hubId) then
						offer.hub = hubId
						break
					end
				end
			end
		end
	end
	return offers, source
end

--	The offers of the map the player is on and of its parent, so an offer that is only
--	drawn on the zone map is noticed while standing in a city or a cave.
function R.OffersAroundPlayer()
	local mapId = playerMap()
	local offers, sources = {}, {}
	if nil == mapId then return offers, mapId, "" end
	local maps = { mapId }
	local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mapId)
	if info and info.parentMapID and info.parentMapID > 0 then
		tinsert(maps, info.parentMapID)
	end
	for _, id in ipairs(maps) do
		local found, source = R.MapOffers(id)
		sources[source] = true
		for questId, offer in pairs(found) do
			if nil == offers[questId] then
				offer.mapId = id
				offers[questId] = offer
			end
		end
	end
	local names = {}
	for source in pairs(sources) do tinsert(names, source) end
	return offers, mapId, tconcat(names, "+")
end

--	Taken when a quest is offered or about to be turned in, so there is a state from
--	before the action to compare against.
function R.CaptureBaseline(label)
	if not enabled() then return end
	local mapId = playerMap()
	local baseline = R.baseline
	if baseline and baseline.mapId == mapId and (GetTime() - baseline.time) <= 30 then return end
	R.baseline = { mapId = mapId, offers = R.OffersAroundPlayer(), time = GetTime(), label = label }
end

function R.OnQuestAction(action, questId)
	if not enabled() or nil == questId then return end
	local baseline = R.baseline
	R.baseline = nil
	if nil == baseline or baseline.mapId ~= playerMap() then return end
	local actionTrigger = strformat("%s:%d", action, questId)
	local reported = {}
	for _, delay in ipairs(R.diffDelays) do
		C_Timer.After(delay, function()
			if not enabled() then return end
			local current, mapId, source = R.OffersAroundPlayer()
			if mapId ~= baseline.mapId then return end
			--	A quest reset between the baseline and now changes offers by itself (new
			--	dailies, rotated world quests), so those changes are credited to the reset.
			--	The baseline is at most 30 s older than the action, hence the window.
			local trigger = actionTrigger
			local resetKind = Grail._NearQuestReset and Grail:_NearQuestReset(R.resetWindow) or nil
			if resetKind then
				trigger = strformat("reset:%s/%s", resetKind, actionTrigger)
			end
			R.ReportOfferChanges(baseline.offers, current, questId, trigger, delay, source, reported)
		end)
	end
end

local function coordinatesOf(offer)
	if nil ~= offer.x and nil ~= offer.y then
		return strformat("%s:%.2f,%.2f", tostring(offer.mapId), offer.x * 100, offer.y * 100)
	end
	return tostring(offer.mapId)
end

--	Writes one line per offer that appeared or disappeared.  The quest that was just
--	accepted or turned in is left out, and each change is written once per action and
--	once for all time (the same pair is not interesting a second time).
function R.ReportOfferChanges(before, after, actionQuestId, trigger, delay, source, reported)
	local seen = GrailDatabase.researchSeen
	local function report(event, questId, offer)
		if questId == actionQuestId then return end
		local key = strformat("%s|%d", event, questId)
		if reported[key] then return end
		reported[key] = true
		local seenKey = strformat("O|%d|%s|%s", questId, event, trigger)
		if seen[seenKey] then return end
		seen[seenKey] = true
		log(strformat("QUESTPIN: %s questId=%d type=%s | trigger=%s delay=%d | coords=%s | hub=%s | source=%s",
			event, questId, tostring(offer.kind), trigger, delay, coordinatesOf(offer), tostring(offer.hub), source))
	end
	for questId, offer in pairs(after) do
		if nil == before[questId] then report("appeared", questId, offer) end
	end
	for questId, offer in pairs(before) do
		if nil == after[questId] then report("disappeared", questId, offer) end
	end
end

--	----------------------------------------------------------------------------------
--	Switching on and off
--	----------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
R.frame = frame

local researchEvents = {
	"PLAYER_REGEN_ENABLED",
	"GOSSIP_SHOW", "GOSSIP_CLOSED",
	"ITEM_TEXT_READY",
	"LOOT_OPENED", "LOOT_CLOSED",
	"QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_ACCEPTED", "QUEST_TURNED_IN",
	"CRITERIA_UPDATE",
	"VIGNETTES_UPDATED",
	"MAJOR_FACTION_RENOWN_LEVEL_CHANGED",
	"COMBAT_TEXT_UPDATE",
	}

local function eventExists(event)
	if C_EventUtils and C_EventUtils.IsEventValid then
		return C_EventUtils.IsEventValid(event)
	end
	return true
end

function R.InstallHooks()
	if R.hooksInstalled then return end
	R.hooksInstalled = true
	if C_GossipInfo then
		if C_GossipInfo.SelectOptionByIndex then
			hooksecurefunc(C_GossipInfo, "SelectOptionByIndex", function(orderIndex) R.OnGossipSelected(true, orderIndex) end)
		end
		if C_GossipInfo.SelectOption then
			hooksecurefunc(C_GossipInfo, "SelectOption", function(optionId) R.OnGossipSelected(false, optionId) end)
		end
	end
	--	The map scan in the main file records offers and their type flags itself.
end

function R.Enable(atLogin)
	GrailDatabase.gossipQuestLinks = GrailDatabase.gossipQuestLinks or {}
	GrailDatabase.vignetteQuestLinks = GrailDatabase.vignetteQuestLinks or {}
	GrailDatabase.researchSeen = GrailDatabase.researchSeen or {}
	R.MigrateOldVignetteLinks()
	R.InstallHooks()
	for _, event in ipairs(researchEvents) do
		if eventExists(event) then
			pcall(frame.RegisterEvent, frame, event)
		end
	end
	R.PrimeCompleted()
	R.vignettes = nil
	if atLogin then
		R.wantLoginDifference = true
		R.TryLoginDifference()
	else
		R.previousCompleted = nil
	end
end

function R.Disable()
	for _, event in ipairs(researchEvents) do
		pcall(frame.UnregisterEvent, frame, event)
	end
	R.completed = nil
	R.baseline = nil
	R.gossip = nil
	R.lastGossip = nil
	R.lastBook = nil
	R.lastLoot = nil
	R.vignettes = nil
	R.goneVignettes = nil
	R.waitingQuests = nil
	R.recentReputation = nil
	R.turnedIn = nil
	R.wantLoginDifference = false
end

local handlers = {
	PLAYER_REGEN_ENABLED = function()
		if R.pollAfterCombat then
			R.pollAfterCombat = false
			R.RequestCheck("combat ended")
		end
	end,
	GOSSIP_SHOW = function() R.OnGossipShow() end,
	GOSSIP_CLOSED = function() R.RequestCheck("gossip closed") end,
	ITEM_TEXT_READY = function() R.OnItemTextReady() end,
	LOOT_OPENED = function() R.OnLootOpened() end,
	LOOT_CLOSED = function() R.RequestCheck("loot") end,
	QUEST_DETAIL = function() R.CaptureBaseline("QUEST_DETAIL") end,
	QUEST_PROGRESS = function() R.CaptureBaseline("QUEST_PROGRESS") end,
	QUEST_COMPLETE = function() R.CaptureBaseline("QUEST_COMPLETE") end,
	--	Older clients pass (questIndex, questId), newer ones only (questId).
	QUEST_ACCEPTED = function(first, second) R.OnQuestAction("accept", tonumber(second or first)) end,
	QUEST_TURNED_IN = function(questId)
		questId = tonumber(questId)
		if nil ~= questId then
			local now = GetTime()
			R.turnedIn = R.turnedIn or {}
			for id, when in pairs(R.turnedIn) do
				if (now - when) > 60 then R.turnedIn[id] = nil end
			end
			R.turnedIn[questId] = now
		end
		R.OnQuestAction("turnin", questId)
		R.RequestCheck("quest turned in")
	end,
	CRITERIA_UPDATE = function() R.RequestCheck("criteria", R.pollGapBusy) end,
	VIGNETTES_UPDATED = function() R.OnVignettesUpdated() end,
	MAJOR_FACTION_RENOWN_LEVEL_CHANGED = function(factionId, newLevel)
		R.OnReputation(strformat("renown:%s+%s", tostring(factionId), tostring(newLevel)))
	end,
	COMBAT_TEXT_UPDATE = function(kind)
		if "FACTION" ~= kind then return end
		local getInfo = (C_CombatText and C_CombatText.GetCurrentEventInfo) or GetCurrentCombatTextEventInfo
		if nil == getInfo then return end
		local factionName, amount = getInfo()
		if nil ~= factionName then
			R.OnReputation(strformat("%s+%s", tostring(factionName), tostring(amount)))
		end
	end,
	}

frame:SetScript("OnEvent", function(_, event, ...)
	if "ADDON_LOADED" == event then
		if "Grail" ~= ... then return end
		frame:UnregisterEvent("ADDON_LOADED")
		--	Grail's record of completed quests as the previous session left it; Grail
		--	itself refreshes it later during startup.
		if type(GrailDatabasePlayer) == "table" and type(GrailDatabasePlayer["completedQuests"]) == "table" then
			local copy = {}
			for index, bits in pairs(GrailDatabasePlayer["completedQuests"]) do
				copy[index] = bits
			end
			R.previousCompleted = copy
		end
		--	Earlier research versions ran WoW: Forever under the "_classic_" name.  The data
		--	is moved to the name Grail uses now, unless something is already stored there.
		if Grail.existsForever and type(GrailDatabase) == "table"
			and nil ~= GrailDatabase["_classic_"] and nil == GrailDatabase["_forever_"]
			and not (IsBetaBuild and IsBetaBuild()) and not (IsTestBuild and IsTestBuild()) then
			GrailDatabase["_forever_"] = GrailDatabase["_classic_"]
			GrailDatabase["_classic_"] = nil
		end
	elseif "PLAYER_ENTERING_WORLD" == event then
		frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
		if enabled() then
			R.Enable(true)
		else
			R.previousCompleted = nil
		end
	elseif enabled() then
		local handler = handlers[event]
		if handler then handler(...) end
	end
end)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

Grail:RegisterSlashOption("research", "|cFF00FF00research|r => toggles the optional data collection for database contributors on and off, printing new value", function()
	if nil == Grail.GDE then return end
	Grail.GDE.research = not Grail.GDE.research
	if Grail.GDE.research then
		R.Enable(false)
	else
		R.Disable()
	end
	securePrint(strformat("Grail research data collection now %s", Grail.GDE.research and "ON" or "OFF"))
end)
