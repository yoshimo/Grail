--
--	Grail NPCs
--	Written by scott@mithrandir.com
--
--	Version History
--		Stopped keeping history as it was not maintained.
--
--	Each NPC value is a table that can contain:
--		[1]	code information (see below) like map location
--		[2] optional friendly notes
--		[3] optional faction association
--
--	NPC Codes
--		A:npcId			npcId that is what Blizzard returns for this alias NPC
--		Created			indicates item is created by player
--		D:<npc list>	comma separated list of NPC IDs that drop this item
--		H<holidayCode>	holidayCode is a single character indicating the holiday the NPC is available
--		K:<quest list>	comma separated list of quest IDs for which this is killed
--		Mailbox			indicates item in a mailbox (any map area)
--		Mailbox<mapId>	indicates item in a mailbox in the specified map area
--		N:npcId			npcId whose name is to be used for this NPC
--		Near			indicates the NPC is nearby (any map area)
--		Near<mapId>		indicates the NPC is nearby in the specified map area
--		Preowned		indicates item is already owned
--		Q:<quest list>	comma separated list of quest IDs to which this is associated
--		Self			special NPC indicator for Self (the player)
--		X				indicates NPC is in heroic only
--		Z<mapId>		indicates NPC found in the map area
--		anything else should be the format (without spaces):
--			mapId [mapLevel] : xx.xx , yy.yy > realMapId
--		the "[mapLevel]" is only required for maps with levels, most do not need it
--		the "> realMapId" indicates the coordinates are in a map that contains the realMap...this allows an outer map to show a point for maps that are contained within
--
--	Known issues
--
--	Maps
--
--		947		Azeroth				World
--		1411	Durotar				Zone	Kalimdor
--		1412	Mulgore				Zone	Kalimdor
--		1413	The Barrens			Zone	Kalimdor
--		1414	Kalimdor			Cont	Azeroth
--		1415	Eastern Kingdoms	Cont	Azeroth
--		1416	Alterac Mountains	Zone	Eastern Kingdoms
--		1417	Arathi Highlands	Zone	Eastern Kingdoms
--		1418	Badlands			Zone	Eastern Kingdoms
--		1419	Blasted Lands		Zone	Eastern Kingdoms
--		1420	Tirisfal Glades		Zone	Eastern Kingdoms
--		1421	Silverpine Forest	Zone	Eastern Kingdoms
--		1422	Western Plaguelands	Zone	Eastern Kingdoms
--		1423	Eastern Plaguelands	Zone	Eastern Kingdoms
--		1424	Hillsbrad Foothills	Zone	Eastern Kingdoms
--		1425	The Hinterlands		Zone	Eastern Kingdoms
--		1426	Dun Morogh			Zone	Eastern Kingdoms
--		1427	Searing Gorge		Zone	Eastern Kingdoms
--		1428	Burning Steppes		Zone	Eastern Kingdoms
--		1429	Elwynn Forest		Zone	Eastern Kingdoms
--		1430	Deadwind Pass		Zone	Eastern Kingdoms
--		1431	Duskwood			Zone	Eastern Kingdoms
--		1432	Loch Modan			Zone	Eastern Kingdoms
--		1433	Redridge Mountains	Zone	Eastern Kingdoms
--		1434	Stranglethorn Vale	Zone	Eastern Kingdoms
--		1435	Swamp of Sorrows	Zone	Eastern Kingdoms
--		1436	Westfall			Zone	Eastern Kingdoms
--		1437	Wetlands			Zone	Eastern Kingdoms
--		1438	Teldrassil			Zone	Kalimdor
--		1439	Darkshore			Zone	Kalimdor
--		1440	Ashenvale			Zone	Kalimdor
--		1441	Thousand Needles	Zone	Kalimdor
--		1442	Stonetalon Mountains Zone	Kalimdor
--		1443	Desolace			Zone	Kalimdor
--		1444	Feralas				Zone	Kalimdor
--		1445	Dustwallow Marsh	Zone	Kalimdor
--		1446	Tanaris				Zone	Kalimdor
--		1447	Azshara				Zone	Kalimdor
--		1448	Felwood				Zone	Kalimdor
--		1449	Un'Goro Crater		Zone	Kalimdor
--		1450	Moonglade			Zone	Kalimdor
--		1451	Silithus			Zone	Kalimdor
--		1452	Winterspring		Zone	Kalimdor
--		1453	Stormwind City		Zone	Eastern Kingdoms
--		1454	Orgrimmar			Zone	Kalimdor
--		1455	Ironforge			Zone	Eastern Kingdoms
--		1456	Thunder Bluff		Zone	Kalimdor
--		1457	Darnassus			Zone	Kalimdor
--		1458	Undercity			Zone	Eastern Kingdoms
--		1459	Alterac Valley		Zone	Azeroth
--		1460	Warsong Gulch		Zone	Azeroth
--		1461	Arathi Basin		Zone	Azeroth
--		1463	Eastern Kingdoms	Cont	(how differ from 1415?)
--		1464	Kalimdor			Cont 	(how differ from 1414?)
--
--	Dungeon entrances:
--		Ahn'Qiraj			1451:29.06,93.46
--		Blackfathom Deeps	1440:14.09,14.87
--		Blackrock Depths	1427:34.57,84.04	1428:31.86,50.45
--		Blackrock Spire		1427:34.57,84.04	1428:31.86,50.45
--		Deeprun Tram
--			Ironforge end	1455:76.19,51.00
--			Stormwind end	1453:51.77,12.08
--		Dire Maul			1444:59.12,45.18
--		Maraudon			1443:29.86,62.53
--		Ragefire Chasm		1454:52.76,48.99
--		Razorfen Downs		1413:49.26,98.08
--		Razorfen Kraul		1413:42.63,90.14
--		Scholomance			1422:69.93,74.01
--		Shadowfang Keep		1421:44.82,67.83
--		Stratholme			1423:30.85,20.08	1423:47.91,23.87
--		The Deadmines		1436:40.68,79.58
--		The Temple of Atal'Hakkar
--							1435:68.81,59.27
--		The Wailing Caverns	1414:52.40,55.19
--		Uldaman	1418:44.54,12.22 1418:65.03,43.51
--		Zul'Farrak			1446:38.72,20.00
--		Zul'Gurub			1434:53.85,17.58
--
--	UTF-8 file
--
local _, release, _, interface = GetBuildInfo()
release = tonumber(release)
interface = tonumber(interface)

if not Grail.existsForever then return end

Grail_NPCs_File_Version = 015

if Grail.npcsVersionNumber >= Grail_NPCs_File_Version then return end
Grail.npcsVersionNumber = Grail_NPCs_File_Version

Grail.npcs = {}

local G = Grail.npcs

if release >= 0 then

end

-- End of NPCs
