-- GitHub #76: a relay's snapshot in pieces must reach every registered reporter whole, without
-- pushing out the single words waiting beside it (a verifier's approval).
local ns, test, eq, extra = ...

test("relay fan-out (#76): with 46 guilds registered, the relay's own snapshot in pieces reaches every reporter whole, and a verifier's approval sent with it reaches every reporter too", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local R, _, sent = extra.RelayWorld("Hildryn Payne-CAMWOWUS2Realm1PvE", "Olympus II")
		local timers = {}
		R.After = function(_, _, fn) timers[#timers + 1] = fn end
		for i = 1, 46 do
			R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i))
		end
		-- An approval, then an 8-piece global census snapshot handed in as Relay.Out's own path does
		-- (1.5.4 review: the approval first, which 1.5.3's fan-out pushed out of the queue: 0 of 46).
		local approval = "GV~1~A~1794011276~Olympus Dawn~Some Master-CAMWOWUS2Realm7PvE"
		R.Relay.HandleIn("WHISPER", R.me, "RL~L~" .. approval)
		local snapshot = "CG~2~S~1~ForeverPvE~Alliance~" .. ("Olympus Dawn,640,40,300,1;"):rep(66)
		for _, p in ipairs(R.Codec.Chunk(snapshot, "77")) do R.Relay.HandleIn("WHISPER", R.me, "RL~P~" .. p) end
		for _ = 1, 2000 do
			R.Comm.Pump()
			local due = timers; timers = {}
			for _, fn in ipairs(due) do fn() end
		end

		-- Each reporter puts back together what it was sent: the RM envelopes, then the snapshot.
		local whole, approved, fewest = 0, 0, 0
		-- The snapshot wrapped once for a reporter, cut into full whispers: the fewest it can take.
		local least = math.ceil(#("RM~P~" .. R.me .. "~" .. snapshot) / R.Codec.CHUNK)
		for i = 1, 46 do
			local outer, inner, prefix = R.Codec.NewAssembler(), R.Codec.NewAssembler(), ("Rep Number%d-"):format(i)
			local got, ok, whispers = false, false, 0
			for _, s in ipairs(sent) do
				if s.target and s.target:sub(1, #prefix) == prefix then
					local rm = s.msg:sub(1, 3) == "RM~" and s.msg or R.Codec.Feed(outer, "relay", s.msg, 0)
					local body = rm and rm:match("^RM~[LP]~[^~]+~(.*)$")
					if s.msg:sub(1, 3) ~= "RM~" then whispers = whispers + 1 end
					if body == approval then ok = true
					elseif body and (body == snapshot or R.Codec.Feed(inner, "origin", body, 0) == snapshot) then got = true end
				end
			end
			if got then whole = whole + 1 end
			if ok then approved = approved + 1 end
			if whispers == least then fewest = fewest + 1 end
		end
		eq(whole, 46, "every reporter can put the whole snapshot together")
		eq(approved, 46, "the snapshot's batches never push the approval out of the queue")
		eq(fewest, 46, ("each reporter gets the snapshot in %d full whispers, not a piece and its label apart"):format(least))
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild = saved.channel, saved.member, saved.guild, saved.inGuild
	C_ChatInfo = nil
	if not ok then error(err, 0) end
end)

-- 1.5.4 (the review of #81 and #82): a relay's own census report keeps its pieces (reports decode
-- from pieces alone, and a whole "R2~" word reached every reporter's Comm and went nowhere), and two
-- different words of one kind from one origin never take each other's place in the drip.
test("relay fan-out (1.5.4): the relay's own census report reaches each reporter in its pieces; two different words of one kind both reach every reporter", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local R, _, sent = extra.RelayWorld("Hildryn Payne-CAMWOWUS2Realm1PvE", "Olympus II")
		local timers = {}
		R.After = function(_, _, fn) timers[#timers + 1] = fn end
		for i = 1, 46 do
			R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i))
		end
		local report = "R2~" .. ("Olympus II,1,2,3;"):rep(30)
		local first, second = "T1~H~" .. ("a"):rep(400), "T1~N~" .. ("b"):rep(400)
		for _, word in ipairs({ { report, "91" }, { first, "92" }, { second, "93" } }) do
			for _, p in ipairs(R.Codec.Chunk(word[1], word[2])) do R.Relay.HandleIn("WHISPER", R.me, "RL~P~" .. p) end
		end
		for _ = 1, 3000 do
			R.Comm.Pump()
			local due = timers; timers = {}
			for _, fn in ipairs(due) do fn() end
		end
		local whole, pieced, both = 0, 0, 0
		for i = 1, 46 do
			local outer, prefix = R.Codec.NewAssembler(), ("Rep Number%d-"):format(i)
			local inner = R.Codec.NewAssembler()
			local got = {}
			for _, s in ipairs(sent) do
				if s.target and s.target:sub(1, #prefix) == prefix then
					local rm = s.msg:sub(1, 3) == "RM~" and s.msg or R.Codec.Feed(outer, "relay", s.msg, 0)
					local body = rm and rm:match("^RM~[LP]~[^~]+~(.*)$")
					if body == report then got.whole = true end
					local assembled = body and (body:match("^C%w+:") and R.Codec.Feed(inner, "origin", body, 0) or body)
					if assembled then got[assembled] = true end
				end
			end
			if got.whole then whole = whole + 1 end
			if got[report] and not got.whole then pieced = pieced + 1 end
			if got[first] and got[second] then both = both + 1 end
		end
		eq(whole, 0, "no reporter is sent the report as one whole word")
		eq(pieced, 46, "every reporter can put the report together from its pieces")
		eq(both, 46, "neither word of the same kind takes the other's place")
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild = saved.channel, saved.member, saved.guild, saved.inGuild
	C_ChatInfo = nil
	if not ok then error(err, 0) end
end)

-- What each reporter could put together from what the relay sent it: the words, and how often each.
local function Assembled(R, sent, prefix)
	local outer, inner, got = R.Codec.NewAssembler(), R.Codec.NewAssembler(), {}
	for _, s in ipairs(sent) do
		if s.target and s.target:sub(1, #prefix) == prefix then
			local rm = s.msg:sub(1, 3) == "RM~" and s.msg or R.Codec.Feed(outer, "relay", s.msg, 0)
			local body = rm and rm:match("^RM~[LP]~[^~]+~(.*)$")
			local word = body and (body:match("^C%w+:%d+:%d+:") and R.Codec.Feed(inner, "origin", body, 0) or body)
			if word then got[word] = (got[word] or 0) + 1 end
		end
	end
	return got
end

local function Relayed(fn)
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local R, _, sent = extra.RelayWorld("Hildryn Payne-CAMWOWUS2Realm1PvE", "Olympus II")
		local timers = {}
		R.After = function(delay, _, f) timers[#timers + 1] = { at = R.clock + (tonumber(delay) or 0), f = f } end
		-- One pump each SEND_INTERVAL (1.2 s), the timers due by then first.
		local function Run(pumps)
			for _ = 1, pumps do
				R.clock = R.clock + 1.2
				local due, keep = {}, {}
				for _, t in ipairs(timers) do if t.at <= R.clock then due[#due + 1] = t else keep[#keep + 1] = t end end
				timers = keep
				for _, t in ipairs(due) do t.f() end
				R.Comm.Pump()
			end
		end
		fn(R, sent, Run)
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild = saved.channel, saved.member, saved.guild, saved.inGuild
	C_ChatInfo = nil
	if not ok then error(err, 0) end
end

-- The review of the 1.5.4 candidate: a reporter's batch the queue pushed out before it began (two
-- chat lines to every reporter arriving at once) goes back to the front while it is fresh, but its
-- time counted from when it was queued: a round of 35 reporters takes more than SET_WAIT, so past
-- the first minute no batch was ever put back and that reporter waited another whole round. Its
-- time counts from its own turn now. Fails before (one reporter without the snapshot).
test("relay fan-out (1.5.4): a snapshot batch pushed out of the queue before it began goes back to its reporter, SET_WAIT counted from its own turn", function()
	Relayed(function(R, sent, Run)
		local REPORTERS = 35
		for i = 1, REPORTERS do
			R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i))
		end
		local raw, handed, start, burst = R.Comm.SendBatch, 0, R.clock, nil
		R.Comm.SendBatch = function(dist, pieces, key, target, urgent, done, options)
			local queued = raw(dist, pieces, key, target, urgent, done, options)
			if done and dist == "WHISPER" and tostring(target):find("^Rep Number") then
				handed = handed + 1
				if handed == 20 and not burst then
					-- Two chat lines arrive before the 20th reporter's batch began (a whisper to each reporter).
					burst = R.clock - start
					for line = 1, 2 do
						R.Relay.HandleIn("WHISPER", "Some Member-CAMWOWUS2Realm3PvE", ("RL~L~M1~W~Guild 7~%d~WA~hello there, line %d"):format(line, line))
					end
				end
			end
			return queued
		end
		local snapshot = ("CG~2~S~1~ForeverPvE~Alliance~" .. ("OLYMPUS GUILD NAME,640,40,300,1794011276;"):rep(108)):sub(1, 20 * 220 - 30)
		for _, p in ipairs(R.Codec.Chunk(snapshot, "501")) do R.Relay.HandleIn("WHISPER", R.me, "RL~P~" .. p) end
		Run(3000)
		eq(burst ~= nil and burst > R.Relay.SET_WAIT, true, "the 20th reporter's turn came past SET_WAIT after the batches were queued")
		local whole = 0
		for i = 1, REPORTERS do
			if Assembled(R, sent, ("Rep Number%d-"):format(i))[snapshot] then whole = whole + 1 end
		end
		eq(whole, REPORTERS, "every reporter can put the snapshot together, the one whose batch was pushed out too")
	end)
end)
