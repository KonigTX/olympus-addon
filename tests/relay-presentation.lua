-- 1.5.4 relay fixes. An integration's profile presentation (FX) names its guild and goes to that
-- guild's reporter alone (its 10-second heartbeat to every reporter was most of what a relay sent);
-- and a reporter's registration (RR) is bounded (below).
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

-- 1.5.4 (a player's security report of 1.5.3): a relay took any whisperer as any number of guilds'
-- reporter, with names of any length; one character could take every guild's feed. Fails before.
test("relay registration (1.5.4): one guild per reporter, a guild name as the game allows it, and a bounded number of guilds", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local R = extra.RelayWorld("Hildryn Payne-CAMWOWUS2Realm1PvE", "Olympus II")
		local function Count() return R.Relay.Stats().reporters end
		R.Relay.HandleIn("WHISPER", "Grab Ber-CAMWOWUS2Realm7PvE", "RL~P~RR~Guild One")
		eq(Count(), 1)
		R.Relay.HandleIn("WHISPER", "Grab Ber-CAMWOWUS2Realm7PvE", "RL~P~RR~Guild Two")
		eq(Count(), 1, "a reporter's new guild leaves his old one")
		R.Relay.HandleIn("WHISPER", "Long Name-CAMWOWUS2Realm7PvE", "RL~P~RR~" .. ("x"):rep(R.Relay.MAX_GUILD_NAME + 1))
		eq(Count(), 1, "a guild name longer than the game allows is refused")
		R.Relay.HandleIn("WHISPER", "Long Name-CAMWOWUS2Realm7PvE", "RL~P~RR~Guild Ünïcode Ésprit")
		eq(Count(), 2, "an accented name within the bytes is kept")
		local cap = R.Relay.MAX_REPORTERS
		R.Relay.MAX_REPORTERS = 3
		for i = 1, 4 do R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i)) end
		eq(Count(), 3, "no more guilds than the cap")
		R.Relay.HandleIn("WHISPER", "Rep Number1-CAMWOWUS2Realm7PvE", "RL~P~RR~Guild 1")
		eq(Count(), 3, "a known guild's reporter still registers again at the cap")
		R.Relay.MAX_REPORTERS = cap
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild = saved.channel, saved.member, saved.guild, saved.inGuild
	C_ChatInfo = nil
	if not ok then error(err, 0) end
end)
