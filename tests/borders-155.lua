-- 1.5.5, the portraits' frames: an appointed office's shield in the guild it was given for (the guild
-- master's list reaching his own guild over GUILD), a signed office's shield in any guild or none, the
-- King's crown before every other frame on his own characters and never on his guild's master where
-- names split (Forever), and the party's borders kept up as a member's facts reach the client late.
-- Made-up names only (the King's code pin aside, BORDER_KING, as the other border tests use it).
local ns, test, eq, h = ...
local WithNominees, WithBorders, BorderUnit = h.WithNominees, h.WithBorders, h.BorderUnit
local Msg, MASTER, OURS, THEIRS, BORDER_KING = h.Msg, h.MASTER, h.OURS, h.THEIRS, h.BORDER_KING
local N = ns.Nominees
local SHIELD = "Interface\\AddOns\\Olympus\\media\\pauldrons\\"

local function GuildParts(w)
	local out = {}
	for _, s in ipairs(w.sent) do if s.dist == "GUILD" and s.msg:find("^NM~") then out[#out + 1] = s.msg end end
	return out
end

test("1.5.5 nominees: the guild master's list goes to his own guild over GUILD too, and his guildmates take it there from him alone", function()
	WithNominees(function(w)
		w.as(MASTER, 0)
		eq(N.Name("legate", "Ada"), true)
		eq(N.Name("correspondent", "Bea", "Lore"), true)
		w.flush()
		local rev = ns.rdb.nominees[MASTER].rev
		local guild = GuildParts(w)
		eq(#guild, 1, "one part to his guild"); eq(guild[1], Msg(OURS, rev, "c=Ada;d=Lore=Bea"))
		-- (The channel's copy still goes, last: the other guilds hear it through the relays.)
		eq(w.sent[#w.sent].dist, "CHANNEL")
		-- A guildmate takes it over GUILD from our guild's master (our roster's word).
		w.as("Ada-Realm", 3)
		N.Handle("GUILD", MASTER, guild[1])
		eq(N.RoleOf("Ada-Realm", OURS), "centurion", "the Legate, in the guild the list is for")
		local role, dept = N.RoleOf("Bea-Realm", OURS)
		eq(role, "correspondent"); eq(dept, "Lore")
		-- The same list heard again on the channel: counted once, nothing new.
		local changed = w.changed
		N.Handle("CHANNEL", MASTER, guild[1])
		eq(w.changed, changed, "a repeat changes nothing")
		-- Over GUILD: a list from anyone but our master, or for another guild, or while we are in another
		-- guild, is nobody's.
		N.Reset()
		N.Handle("GUILD", "Pip Officer-Realm", Msg(OURS, rev + 1, "c=Pip"))
		eq(N.RoleOf("Pip-Realm", OURS), nil, "an officer's list over GUILD")
		N.Handle("GUILD", "Zeusy-Realm", Msg(THEIRS, rev + 1, "c=Capt"))
		eq(N.RoleOf("Capt-Realm", THEIRS), nil, "another guild's list never comes over our GUILD")
		w.asIn("Ada-Realm", "Olympus Elsewhere", 3)
		N.Handle("GUILD", MASTER, guild[1])
		eq(N.RoleOf("Ada-Realm", OURS), nil, "not while we are in another guild")
		-- Anyone but a guild master sends nothing to his guild.
		w.sent = {}
		w.as("Ada-Realm", 3)
		eq(N.Send(true), false); eq(#GuildParts(w), 0)
	end)
end)

test("1.5.5 office shields: a member sees his own Legate shield in the guild he is a member of, from his master's list over GUILD", function()
	local savedRoster = ns.Roster.byName
	N.Reset()
	local ok, err = pcall(WithBorders, function(w)
		-- (BORDER_ME, the player: Tester of <Olympus II>; our roster names Boss Hammer its master.)
		ns.Roster.byName = { [MASTER] = 0, ["Tester-Realm"] = 3 }
		w.internal("LOGIN")
		eq(w.roleBadge("player"), nil, "nothing heard yet")
		N.Handle("GUILD", MASTER, Msg(OURS, ns.Now(), "c=Tester"))
		w.internal("DATA_CHANGED")
		eq(assert(w.roleBadge("player"), "his own shield").file, SHIELD .. "legate")
		-- And on a guildmate's target frame: the same shield.
		w.target(BorderUnit("Tester", OURS, "Member", 3, { guid = "Player-other-view" }))
		eq(assert(w.roleBadge("target")).file, SHIELD .. "legate")
	end)
	ns.Roster.byName = savedRoster
	N.Reset()
	if not ok then error(err, 0) end
end)

test("1.5.5 office shields: a signed office's shield (the council titles list) is its holder's in any guild or none", function()
	WithBorders(function(w)
		w.ns.CouncilTitle = function(who) if ns.FullName(who) == "Sage Owl-Realm" then return { dept = "Federal Treasury" } end end
		w.internal("LOGIN")
		for _, guild in ipairs({ "Olympus II", "Olympus Zeus", "Wanderers", false }) do
			w.target(nil)
			w.target(BorderUnit("Sage Owl", guild or nil, guild and "Member" or nil, guild and 4 or nil))
			eq(assert(w.roleBadge("target"), "in " .. tostring(guild)).file, SHIELD .. "federal-treasury", tostring(guild))
		end
		-- A nominee's office stays its guild's alone: nobody else's name gets it.
		w.target(nil)
		w.target(BorderUnit("Plain Pip", nil, nil, nil))
		eq(w.roleBadge("target"), nil)
		-- Under a moderator's cover name on this client (Cover.lua): no shield that says what he is.
		w.ns.Cover = { AliasOf = function(n) if ns.FullName(n) == "Sage Owl-Realm" then return "Masked One" end end,
			Version = function() return 2 end }
		w.target(nil)
		w.target(BorderUnit("Sage Owl", nil, nil, nil))
		eq(w.roleBadge("target"), nil, "covered")
	end)
end)

test("1.5.5 the King's crown: before an honour's or a Most Wanted frame on his own characters, on every frame", function()
	WithBorders(function(w)
		w.ns.HonorsNet = { Verified = function() return { frame = "donor-top-1" } end,
			FrameTexture = function() return "Interface\\AddOns\\Olympus\\media\\honors\\donor-top-1", "plain" end }
		w.ns.Wanted = { GlobalBorder = function() return "wanted-slayer-1" end }
		w.internal("LOGIN")
		w.target(BORDER_KING)
		eq(w.shown("target"), "gold-elite", "the King's crown, not his honour's frame")
		w.units.focus = BORDER_KING
		w.fire("PLAYER_FOCUS_CHANGED")
		eq(w.shown("focus"), "gold-elite")
		w.party()
		w.units.party1 = BORDER_KING
		w.fire("GROUP_ROSTER_UPDATE")
		eq(w.shown("party1"), "gold-elite")
		-- Anyone else keeps the frame he earned over his rank's (as before): here a guild master.
		w.target(nil)
		w.target(BorderUnit("Zeusy", "Olympus Zeus", "Zeus", 0))
		eq(assert(w.shownTexture("target"), "a frame").file, "Interface\\AddOns\\Olympus\\media\\honors\\donor-top-1", "his earned frame, not his bronze")
	end)
	-- The King's own screen: his own portrait.
	WithBorders(function(w)
		w.ns.HonorsNet = { Verified = function() return { frame = "donor-top-1" } end,
			FrameTexture = function() return "Interface\\AddOns\\Olympus\\media\\honors\\donor-top-1", "plain" end }
		w.internal("LOGIN")
		eq(w.shown("player"), "gold-elite")
	end, function(w) w.units.player = BORDER_KING end)
end)

test("1.5.5 the King's crown: the King's guild's master never wears it where names split (Forever), only where no King can be named", function()
	local master = BorderUnit("Guild Head", "OLYMPUS", "Guild Master", 0)
	for _, split in ipairs({ true, false }) do
		WithBorders(function(w)
			-- No King named here and no launch list held: the case the guild master used to stand in for.
			w.ns.KingCharacter = function() return nil end
			w.ns.IsKingCharacter = function() return false end
			w.ns.LaunchListHeld = function() return false end
			ns.splitNames = split or nil
			w.internal("LOGIN")
			w.target(master)
			if split then
				eq(w.shown("target"), nil, "Forever: no crown for the guild master")
				eq(w.B.MarkOf("target") == "gold", false, "nor its nameplate mark")
				eq(w.B.MarkOfName("Guild Head-Realm", "OLYMPUS") == "gold", false, "nor its chat mark")
				eq(w.B.MasterWearsCrown("OLYMPUS", 0), false)
			else
				eq(w.shown("target"), "gold-elite", "elsewhere, with no King named, as before")
				eq(w.B.MasterWearsCrown("OLYMPUS", 0), true)
			end
		end)
	end
end)

test("1.5.5 party borders: a member's guild reaching the client with no event of its own: his border at his portrait's update or the roster's second look", function()
	WithBorders(function(w)
		w.party()
		w.internal("LOGIN")
		local later = {}
		w.ns.After = function(_, _, f) later[#later + 1] = f end
		-- Our guild's master joins before the client has his guild.
		w.units.party1 = BorderUnit("Mate", nil, nil, nil, { guid = "Player-late-3" })
		w.fire("GROUP_ROSTER_UPDATE")
		eq(w.shown("party1"), nil, "nothing known of his guild yet")
		eq(#later, 1, "a second look scheduled")
		w.fire("GROUP_ROSTER_UPDATE")
		eq(#later, 1, "one, however many updates come meanwhile")
		-- His guild arrives, no event says so: the second look shows his border.
		w.units.party1 = BorderUnit("Mate", "Olympus II", "Zeus", 0, { guid = "Player-late-3" })
		local n = w.computed()
		later[1]()
		eq(w.shown("party1"), "bronze-elite", "our guild master's bronze")
		eq(w.computed(), n + 1, "him alone, once")
		-- Again: another member, his portrait coming into view (UNIT_PORTRAIT_UPDATE).
		w.units.party2 = BorderUnit("Zeusy", nil, nil, nil, { guid = "Player-late-4" })
		w.fire("GROUP_ROSTER_UPDATE")
		eq(w.shown("party2"), nil)
		w.units.party2 = BorderUnit("Zeusy", "Olympus Zeus", "Zeus", 0, { guid = "Player-late-4" })
		n = w.computed()
		w.fire("UNIT_PORTRAIT_UPDATE", "party2")
		eq(w.shown("party2"), "bronze-elite", "another guild's master, as its census names him")
		eq(w.computed(), n + 1)
		-- Nothing late: a portrait's update works nothing out again; nor one of a unit outside the party.
		w.fire("UNIT_PORTRAIT_UPDATE", "party2"); w.fire("UNIT_FACTION", "party1"); w.fire("UNIT_PORTRAIT_UPDATE", "target")
		eq(w.computed(), n + 1, "nothing worked out again")
	end)
end)
