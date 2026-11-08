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

-- The review of the 1.5.4 candidate: the relay's own repeats in pieces (the King's Hands and the
-- Treasury's words every 300 s, a ranking's repeat) were keyed by their message id, so each repeat
-- waited in the drip as one more batch behind the rest: on a busy relay the drip grew without end
-- and the census snapshots waited behind it. Its newer word of one kind takes the waiting copy's
-- place now, as a newer snapshot does. Fails before (every reporter gets the older copy too).
test("relay fan-out (1.5.4): the relay's own newer word in pieces takes its waiting copy's place in the drip; a word of another kind keeps its own", function()
	Relayed(function(R, sent, Run)
		local REPORTERS = 3
		for i = 1, REPORTERS do
			R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i))
		end
		-- The queue full: the batches wait in the drip for room (they never push out what waits there).
		for i = 1, R.Comm.MAX_QUEUE do R.Comm.Whisper("Filler Target-CAMWOWUS2Realm7PvE", "X1~filler " .. i, "filler " .. i, false, false) end
		eq(R.Comm.QueueRoom(), 0)
		local older, other, newer = "T1~H~" .. ("a"):rep(400), "T1~N~" .. ("c"):rep(400), "T1~H~" .. ("b"):rep(400)
		for _, word in ipairs({ { older, "61" }, { other, "62" }, { newer, "63" } }) do
			for _, p in ipairs(R.Codec.Chunk(word[1], word[2])) do R.Relay.HandleIn("WHISPER", R.me, "RL~P~" .. p) end
		end
		Run(400)
		eq(R.Comm.QueueSize(), 0, "everything went out")
		local olderSent, newerOnce, otherSent = 0, 0, 0
		for i = 1, REPORTERS do
			local got = Assembled(R, sent, ("Rep Number%d-"):format(i))
			if got[older] then olderSent = olderSent + 1 end
			if got[newer] == 1 then newerOnce = newerOnce + 1 end
			if got[other] then otherSent = otherSent + 1 end
		end
		eq(olderSent, 0, "no reporter is sent the copy the newer word replaced")
		eq(newerOnce, REPORTERS, "each reporter gets the newer word, once")
		eq(otherSent, REPORTERS, "the word of another kind keeps its own place")
	end)
end)

-- The load review of the 1.5.4 candidate: each reporter's trickle of other clients' words
-- (REPORTER_RATE a minute) grew with the reporters, 320 whispers a minute at 80 of them against the
-- relay's 200 in all, and the census snapshots never found room in its queue. The reporters now
-- share TRICKLE_PER_MIN a minute, REPORTER_RATE at most each. Fails before (each of 60 reporters
-- took REPORTER_RATE a minute).
test("relay trickle (1.5.4): many reporters share TRICKLE_PER_MIN a minute of other clients' words, the same share each; a few still get REPORTER_RATE each", function()
	Relayed(function(R)
		local function Trial(reporters, minutes)
			R.Relay.Reset()
			for i = 1, reporters do
				R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i))
			end
			local got, raw = {}, R.Comm.Whisper
			R.Comm.Whisper = function(target, msg, ...)
				if tostring(target):find("^Rep Number") and tostring(msg):find("^RM~P~Some Client") then got[target] = (got[target] or 0) + 1 end
				return raw(target, msg, ...)
			end
			for second = 1, minutes * 60 do
				R.clock = R.clock + 1
				R.Relay.HandleIn("WHISPER", "Some Client-CAMWOWUS2Realm3PvE", ("RL~P~X1~word %d"):format(second))
			end
			R.Comm.Whisper = raw
			local total, least, most = 0, math.huge, 0
			for i = 1, reporters do
				local n = got[("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i)] or 0
				total, least, most = total + n, math.min(least, n), math.max(most, n)
			end
			return total, least, most
		end
		local rate, all = R.Relay.REPORTER_RATE, R.Relay.TRICKLE_PER_MIN
		-- Many: the share is TRICKLE_PER_MIN among them (one whisper each a minute here), plus the
		-- allowance each starts with (a wrapped piece, two whispers).
		local total, least, most = Trial(60, 5)
		eq(total <= all * 5 + 60 * 2, true, ("60 reporters in 5 minutes: %d whispers, at most %d"):format(total, all * 5 + 60 * 2))
		eq(total >= all * 5 * 0.9, true, ("and the share is spent: %d whispers"):format(total))
		eq(most - least <= 1, true, ("the same share each: %d to %d"):format(least, most))
		-- A few: REPORTER_RATE a minute each, as before.
		total, least, most = Trial(10, 5)
		eq(least >= rate * 5 and most <= rate * 6, true, ("10 reporters: %d to %d whispers each in 5 minutes"):format(least, most))
	end)
end)

-- The review of the 1.5.4 candidate: a reporter's allowance refilled a fraction at a time went to the
-- first word that fitted one whisper, so a word in two whispers (a census look in one chunk, as
-- Data.CapturePortable builds it, once wrapped with its carrier's name; any full piece of a word in
-- pieces) never passed again beside one short word every few seconds, with 10 reporters (REPORTER_RATE
-- each, "as before") or with 35 (60 a minute shared). A whole allowance at a time, taken in the order
-- the words come, as 1.5.3 did. Fails before (no look reached any reporter after the first minute).
test("relay trickle (1.5.4): a word in two whispers still gets through beside short words, with a few reporters and with many", function()
	Relayed(function(R)
		local function Trial(reporters, seconds)
			R.Relay.Reset()
			for i = 1, reporters do
				R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i))
			end
			local wide, small = {}, {}
			local rawBatch, rawWhisper = R.Comm.SendBatch, R.Comm.Whisper
			R.Comm.SendBatch = function(dist, pieces, key, target, ...)
				if tostring(target):find("^Rep Number") then wide[target] = (wide[target] or 0) + #pieces end
				return rawBatch(dist, pieces, key, target, ...)
			end
			R.Comm.Whisper = function(target, msg, ...)
				if tostring(target):find("^Rep Number") and tostring(msg):find("^RM~P~") then small[target] = (small[target] or 0) + 1 end
				return rawWhisper(target, msg, ...)
			end
			local start = R.clock
			for second = 1, seconds do
				R.clock = start + second
				if second % 2 == 0 then
					-- A look as Data.CapturePortable builds it, whole rows within one chunk (219-220 bytes here).
					local carrier = ("Look Carrier%d-CAMWOWUS2Realm1PvE"):format(second % 40)
					local rows = {}
					for k = 1, 3 do rows[k] = ("OLYMPUS FORCES OF EVIL,%d,43,300,1794011276"):format(100 + k) end
					local look = ("CX~3~S~%s~ForeverPvP~Alliance~3626,2100,19,%d~"):format(carrier, 1794011276 + second)
						.. table.concat(rows, ";")
					assert(#look <= R.Codec.CHUNK, "one chunk")
					R.Relay.HandleIn("WHISPER", carrier, "RL~P~" .. R.Codec.Chunk(look, tostring(second % 1000))[1])
				end
				if second % 6 == 0 then
					R.Relay.HandleIn("WHISPER", ("Some Asker%d-CAMWOWUS2Realm1PvE"):format(second % 40), ("RL~P~T7~%d"):format(second))
				end
				if second % 3 == 0 then R.Comm.Pump() end
			end
			R.Comm.SendBatch, R.Comm.Whisper = rawBatch, rawWhisper
			local fewest, most = math.huge, 0
			for i = 1, reporters do
				local name = ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i)
				fewest = math.min(fewest, (wide[name] or 0) / 2)
				most = math.max(most, (wide[name] or 0) + (small[name] or 0))
			end
			return fewest, most
		end
		local rate, all = R.Relay.REPORTER_RATE, R.Relay.TRICKLE_PER_MIN
		local looks, most = Trial(10, 300)
		eq(looks >= 5, true, ("10 reporters: each is handed a look in two whispers each minute: at least %d in 5 minutes"):format(looks))
		eq(most <= rate * 6, true, ("and no more than REPORTER_RATE a minute: at most %d whispers"):format(most))
		looks, most = Trial(35, 300)
		eq(looks >= 4, true, ("35 reporters: each is handed one about every 70 s: at least %d in 5 minutes"):format(looks))
		eq(most <= 2 + all / 35 * 5 + 1, true, ("and no more than his share: at most %d whispers"):format(most))
	end)
end)

-- (The same review.) A clock set back (time() is the computer's) starts a new allowance: a window
-- measured from a later second never froze the trickle until the clock caught up.
test("relay trickle (1.5.4): a clock set back starts a reporter's new allowance", function()
	Relayed(function(R)
		R.Relay.Reset()
		R.Relay.HandleIn("WHISPER", "Rep Number1-CAMWOWUS2Realm7PvE", "RL~P~RR~Guild 1")
		local got, raw = 0, R.Comm.Whisper
		R.Comm.Whisper = function(target, msg, ...)
			if tostring(msg):find("^RM~P~Some Client") then got = got + 1 end
			return raw(target, msg, ...)
		end
		for i = 1, R.Relay.REPORTER_RATE + 1 do R.Relay.HandleIn("WHISPER", "Some Client-CAMWOWUS2Realm3PvE", ("RL~P~X1~spent %d"):format(i)) end
		eq(got, R.Relay.REPORTER_RATE, "the allowance spent")
		R.clock = R.clock - 3600
		R.Relay.HandleIn("WHISPER", "Some Client-CAMWOWUS2Realm3PvE", "RL~P~X1~after the clock went back")
		R.Comm.Whisper = raw
		eq(got, R.Relay.REPORTER_RATE + 1, "a new allowance after the clock went back")
	end)
end)

-- The review of the 1.5.4 candidate: another client's word in pieces passes the trickle whole or not
-- at all. With 35 reporters an allowance holds two whispers; a census report in two pieces (385 bytes:
-- its full first piece and its RM label are two whispers, its last one more) can never reach a reporter
-- whole, yet its first piece took the allowance and the single words after it went to nobody. A last
-- piece alone (its first ones refused before) took a single word's place the same way. Fails before.
test("relay trickle (1.5.4): a word in pieces that can never pass whole spends nothing, and the single words after it still pass", function()
	Relayed(function(R)
		R.Relay.Reset()
		for i = 1, 35 do
			R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i))
		end
		R.clock = R.clock + 120 -- (every allowance full)
		local pieces, words, raw, rawBatch = 0, {}, R.Comm.Whisper, R.Comm.SendBatch
		local function Note(msg)
			msg = tostring(msg)
			if msg:find("^RM~P~Census Guy%-") then pieces = pieces + 1 end
			local w = msg:match("^RM~P~Some Client%-[^~]+~X2~(%d)~")
			if w then words[w] = (words[w] or 0) + 1 end
		end
		local function Watch()
			R.Comm.Whisper = function(target, msg, ...) Note(msg); return raw(target, msg, ...) end
			R.Comm.SendBatch = function(dist, list, key, target, ...)
				-- (a wrapped piece goes as the relay's own envelope in pieces: the first carries the label)
				if dist == "WHISPER" and type(list) == "table" and list[1] then Note(tostring(list[1]):match("^C%w+:1:%d+:(.*)$")) end
				return rawBatch(dist, list, key, target, ...)
			end
		end
		Watch()
		local report = R.Codec.Chunk("R2~" .. ("r"):rep(382), "7")
		eq(#report, 2, "a 385-byte census report is two pieces")
		for _, p in ipairs(report) do R.Relay.HandleIn("WHISPER", "Census Guy-CAMWOWUS2Realm3PvE", "RL~P~" .. p) end
		R.Relay.HandleIn("WHISPER", "Census Guy-CAMWOWUS2Realm3PvE", "RL~P~C8:3:3:" .. ("x"):rep(40))
		R.Relay.HandleIn("WHISPER", "Some Client-CAMWOWUS2Realm3PvE", "RL~P~X2~1~a word")
		R.Relay.HandleIn("WHISPER", "Some Client-CAMWOWUS2Realm3PvE", "RL~P~X2~2~a word")
		R.Comm.Whisper, R.Comm.SendBatch = raw, rawBatch
		eq(pieces, 0, "no piece of a word that can never pass whole is sent")
		eq(words["1"] or 0, 35, "the first single word reaches every reporter")
		eq(words["2"] or 0, 35, "and so does the second")
		-- A few reporters (an allowance of REPORTER_RATE): the same report still passes whole.
		R.Relay.Reset()
		for i = 1, 10 do
			R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i))
		end
		R.clock = R.clock + 120
		pieces = 0
		Watch()
		for _, p in ipairs(R.Codec.Chunk("R2~" .. ("s"):rep(382), "9")) do R.Relay.HandleIn("WHISPER", "Census Guy-CAMWOWUS2Realm3PvE", "RL~P~" .. p) end
		R.Comm.Whisper, R.Comm.SendBatch = raw, rawBatch
		eq(pieces, 20, "with 10 reporters both pieces of the report go to each")
	end)
end)

-- The review of the 1.5.4 candidate: the relay's own word too long for one drip batch (wrapped whole
-- it is more than MAX_CHUNKS whispers, so each piece goes wrapped alone: two batches) was keyed by its
-- kind and replaced batch by batch. A newer copy that came while the older's first batch was already
-- in the queue replaced only its second: that reporter got half of each copy and could put the older
-- together never. Each copy of such a word goes whole now. Fails before (a reporter with half a copy).
test("relay fan-out (1.5.4): the relay's own word too long for one drip batch is never split by a newer copy: each reporter gets every piece of each copy it gets any of, and the newer copy whole", function()
	Relayed(function(R, sent, Run)
		local REPORTERS = 6
		for i = 1, REPORTERS do
			R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i))
		end
		local label = #("RM~P~" .. R.me .. "~")
		local size = R.Codec.CHUNK * R.Codec.MAX_CHUNKS - label + 1 -- one whisper past MAX_CHUNKS once wrapped whole
		local function Word(stamp, fill) return (("T9~Olympus~%d~"):format(stamp) .. fill:rep(size)):sub(1, size) end
		local older, newer = Word(1794011276, "a"), Word(1794011400, "b")
		local first = R.Codec.Chunk(older, "61")
		eq(#first <= R.Codec.MAX_CHUNKS, true, "the word itself fits MAX_CHUNKS pieces")
		for _, p in ipairs(first) do R.Relay.HandleIn("WHISPER", R.me, "RL~P~" .. p) end
		-- (The first reporter's first batch is in the queue already when the newer copy comes.)
		for _, p in ipairs(R.Codec.Chunk(newer, "62")) do R.Relay.HandleIn("WHISPER", R.me, "RL~P~" .. p) end
		Run(2000)
		eq(R.Comm.QueueSize(), 0, "everything went out")
		local half, newerWhole = 0, 0
		for i = 1, REPORTERS do
			local prefix = ("Rep Number%d-"):format(i)
			local outer, got, total = R.Codec.NewAssembler(), {}, {}
			for _, s in ipairs(sent) do
				if s.target and s.target:sub(1, #prefix) == prefix then
					local rm = s.msg:sub(1, 3) == "RM~" and s.msg or R.Codec.Feed(outer, "relay", s.msg, 0)
					local body = rm and rm:match("^RM~[LP]~[^~]+~(.*)$")
					local id, k, n = nil, nil, nil
					if body then id, k, n = body:match("^C(%w+):(%d+):(%d+):") end
					if id then
						got[id] = got[id] or {}
						got[id][tonumber(k)] = true
						total[id] = tonumber(n)
					end
				end
			end
			for id, ks in pairs(got) do
				local c = 0
				for _ in pairs(ks) do c = c + 1 end
				if c ~= total[id] then half = half + 1 end
			end
			local c = 0
			for _ in pairs(got["62"] or {}) do c = c + 1 end
			if total["62"] and c == total["62"] then newerWhole = newerWhole + 1 end
		end
		eq(half, 0, "no reporter is sent part of a copy")
		eq(newerWhole, REPORTERS, "every reporter gets the newer copy whole")
	end)
end)

-- The review of the 1.5.4 candidate: the Treasurer's client (a relay: Relay.Names takes his signed
-- pins) passes on each of his mail characters' books (TR~<name>~) in one tick (Treasury.Relay), each
-- as Treasury.Send sends it: in pieces above 250 bytes, else one channel message. Keyed "TR" alone,
-- the last book took the others' places for every reporter still waiting: in the drip for books in
-- pieces (one reporter of six had both), in Comm's keyed jobs for books in one whisper (none had
-- both). Each mail character's book keeps its own place now, and a newer copy of one character's
-- book still takes its waiting copy's place. Fails before (the first book at one reporter of six).
test("relay fan-out (1.5.4): the relay's own books of two mail characters (TR), sent in one tick, both reach every reporter, in pieces or in one whisper; a newer copy of one character's book still takes its waiting copy's place", function()
	Relayed(function(R, sent, Run)
		local REPORTERS = 6
		for i = 1, REPORTERS do
			R.Relay.HandleIn("WHISPER", ("Rep Number%d-CAMWOWUS2Realm7PvE"):format(i), ("RL~P~RR~Guild %d"):format(i))
		end
		-- As Treasury.Send sends each book: in pieces above 250 bytes, else one channel message.
		local options = { owner = "test treasury", guard = function() return true end }
		local function Send(book)
			if #book <= 250 then return R.Comm.Send("CHANNEL", book, nil, nil, nil, nil, options) end
			return R.Comm.SendChunked(book, nil, "CHANNEL", nil, options)
		end
		local function Both(a, b)
			local n = 0
			for i = 1, REPORTERS do
				local got = Assembled(R, sent, ("Rep Number%d-"):format(i))
				if got[a] and got[b] then n = n + 1 end
			end
			return n
		end
		local big1 = "TR~Pyralis Andarai-Realm~1794011276~TB~" .. ("a"):rep(700)
		local big2 = "TR~Pyralis Thirdchar-Realm~1794011276~TB~" .. ("b"):rep(700)
		Send(big1); Send(big2)
		Run(400)
		eq(Both(big1, big2), REPORTERS, "each mail character's book in pieces reaches every reporter")
		local small1, small2 = "TR~Pyralis Andarai-Realm~1794011277~TB~a", "TR~Pyralis Thirdchar-Realm~1794011277~TB~b"
		Send(small1); Send(small2)
		Run(100)
		eq(Both(small1, small2), REPORTERS, "each mail character's book in one whisper reaches every reporter")
		-- Still: the queue full, a newer copy of one character's book takes its waiting copy's place.
		for i = 1, R.Comm.MAX_QUEUE do R.Comm.Whisper("Filler Target-CAMWOWUS2Realm7PvE", "X1~filler " .. i, "filler " .. i, false, false) end
		local older = "TR~Pyralis Andarai-Realm~1794011300~TB~" .. ("c"):rep(700)
		local newer = "TR~Pyralis Andarai-Realm~1794011301~TB~" .. ("d"):rep(700)
		Send(older); Send(newer)
		Run(400)
		eq(R.Comm.QueueSize(), 0, "everything went out")
		local olderSent, newerOnce = 0, 0
		for i = 1, REPORTERS do
			local got = Assembled(R, sent, ("Rep Number%d-"):format(i))
			if got[older] then olderSent = olderSent + 1 end
			if got[newer] == 1 then newerOnce = newerOnce + 1 end
		end
		eq(olderSent, 0, "no reporter is sent the copy the newer one replaced")
		eq(newerOnce, REPORTERS, "each reporter gets the newer copy, once")
	end)
end)
