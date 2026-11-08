-- 1.5.4: an integration's profile presentation (FX) names its guild and goes to that guild's
-- reporter alone. Its 10-second heartbeat to every reporter was most of what a relay sent.
local ns, test, eq, extra = ...

test("relay fan-out (1.5.4): the relay's own profile presentation goes to the reporter of the guild it names alone; any other word of its own still reaches every reporter", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local R, _, sent = extra.RelayWorld("Hildryn Payne-CAMWOWUS2Realm1PvE", "Olympus II")
		local timers = {}
		R.After = function(_, _, fn) timers[#timers + 1] = fn end
		for i = 1, 10 do
			R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i))
		end
		R.Relay.HandleIn("WHISPER", "Dawn Keeper-CAMWOWUS2Realm7PvE", "RL~P~RR~Olympus Dawn")
		-- A grant's heartbeat (FX~2~G~style~session~sequence~time~guild~grant id), then another word.
		local presentation = "FX~2~G~w~123~1~1794011276~Olympus Dawn~42"
		local other = "ZZ~1~a word of the relay's own"
		R.Relay.HandleIn("WHISPER", R.me, "RL~P~" .. presentation)
		R.Relay.HandleIn("WHISPER", R.me, "RL~P~" .. other)
		for _ = 1, 200 do
			R.Comm.Pump()
			local due = timers; timers = {}
			for _, fn in ipairs(due) do fn() end
		end
		local function Reached(word)
			local who = {}
			for _, s in ipairs(sent) do
				local body = s.target and s.msg:match("^RM~[LP]~[^~]+~(.*)$")
				if body == word then who[ns.ShortName(s.target)] = true end
			end
			local names = {}
			for name in pairs(who) do names[#names + 1] = name end
			table.sort(names)
			return names
		end
		local got = Reached(presentation)
		eq(#got, 1, "one reporter receives the presentation")
		eq(got[1], "Dawn Keeper", "the reporter of the guild it names")
		eq(#Reached(other), 11, "any other word of the relay's own still reaches every reporter")
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild = saved.channel, saved.member, saved.guild, saved.inGuild
	C_ChatInfo = nil
	if not ok then error(err, 0) end
end)
