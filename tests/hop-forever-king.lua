-- The King's layer on WoW: Forever: the relay hands his own layer word to every guild's reporter
-- outside the trickle, bounded (Relay.KING_REFRESH), through the real Relay.lua.
local ns, test, eq, extra = ...

test("Forever King's layer: the relay hands the King's own layer word to every reporter outside the trickle, once per change and at most every KING_REFRESH; another client's layer word stays in the trickle", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return "Olympus II", "Member", 3 end
		local R = extra.RelayWorld("Hildryn Payne-Realm", "Olympus II")
		R.IsKingCharacter = function(name) return type(name) == "string" and ns.ShortName(name) == "Asmongold Thereal" end
		for i = 1, 34 do R.Relay.HandleIn("WHISPER", ("Rep Number%d-Realm"):format(i), ("RL~P~RR~Guild %d"):format(i)) end
		local king, other = {}, {}
		local whisper = R.Comm.Whisper
		R.Comm.Whisper = function(target, msg, ...)
			local origin, body = tostring(msg):match("^RM~P~([^~]+)~(.*)$")
			if body and body:find("^L1~") then
				local list = ns.ShortName(origin) == "Asmongold Thereal" and king or other
				list[#list + 1] = { target = target, body = body, at = R.clock }
			end
			return whisper(target, msg, ...)
		end
		-- Ten minutes of a busy relay: about 149 other words a minute fill every reporter's trickle,
		-- the King repeats his layer every 55 seconds and moves once, another member announces his.
		local kingBody = "L1~1453~7~0~OLYMPUS PRIME"
		local n = 0
		for second = 0, 599, 0.4 do
			n = n + 1
			R.clock = 100000 + second
			R.Relay.HandleIn("WHISPER", ("Origin Number%d-Realm"):format(n), ("RL~P~X1~census %d"):format(n))
			if n % 138 == 1 then -- (every 55.2 s)
				if second >= 300 then kingBody = "L1~1453~9~0~OLYMPUS PRIME" end
				R.Relay.HandleIn("WHISPER", "Asmongold Thereal-Realm", "RL~P~" .. kingBody)
			end
			if n % 300 == 150 then R.Relay.HandleIn("WHISPER", "Some Member-Realm", "RL~P~L1~1453~7~3~Olympus III") end
		end
		local per = {}
		for _, x in ipairs(king) do per[x.target] = (per[x.target] or 0) + 1 end
		local reporters, most = 0, 0
		for _, count in pairs(per) do reporters, most = reporters + 1, math.max(most, count) end
		print(("    King's layer words sent: %d to %d reporters (at most %d each) in ten minutes; another member's: %d")
			:format(#king, reporters, most, #other))
		eq(reporters, 34, "every reporter got the King's layer")
		assert(most <= 3, "at most once per change and per KING_REFRESH each: " .. most)
		assert(#king <= 34 * 3, "bounded: " .. #king)
		local moved = 0
		for _, x in ipairs(king) do if x.body == "L1~1453~9~0~OLYMPUS PRIME" then moved = moved + 1 end end
		eq(moved, 34, "his move reached every reporter at once")
		eq(#other, 0, "another member's layer word stays in the trickle")
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild = saved.channel, saved.member, saved.guild, saved.inGuild
	C_ChatInfo = nil
	if not ok then error(err, 0) end
end)
