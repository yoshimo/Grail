--
--	Grail Quests
--	Written by scott@mithrandir.com
--
--	Version History
--		001	Initial verison.
--
--	UTF-8 file
--
local _, release, _, interface = GetBuildInfo()
release = tonumber(release)
interface = tonumber(interface)

if not Grail.existsForever then return end

Grail_Quests_File_Version = 001

if Grail.questsVersionNumber < Grail_Quests_File_Version then
Grail.questsVersionNumber = Grail_Quests_File_Version

Grail.dailyMaximums = {
	}

Grail.weeklyMaximums = {
	}

local G = Grail.questCodes

if release >= 0 then

end

end
