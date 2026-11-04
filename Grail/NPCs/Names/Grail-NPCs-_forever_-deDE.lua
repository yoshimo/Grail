--
--
--	UTF-8 file
--

--	We are using this as the base list of NPC names, so we do not look at the locale
--	to determine whether we should abandon further processing.

local G = Grail.npc.name
local _, release, _, interface = GetBuildInfo()
release = tonumber(release)
interface = tonumber(interface)

if not Grail.existsForever then return end

if release >= 0 then

end

--	End of localized NPC names
