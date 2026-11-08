local ADDON, ns = ...
local Relay = {}
ns.Relay = Relay

-- 1.4.3 (launch night, 2026-11-04). WoW: Forever's live realms accept an addon's messages on any
-- player-made chat channel and never deliver them, not even back to the sender (measured on launch
-- night: 0 of 123 members' messages heard in a minute; the beta delivered them, as Classic's beta
-- did before patch 1.13.3 cut it). The guild and addon whispers are delivered, to any player of the
-- faction on any of Forever's sub-realms, by his plain "First Surname". So where names split
-- (ns.splitNames: Forever), everything the addon says "on the channel" travels like this instead,
-- and no module changes: the census, the signed lists, the key, the rankings' words, the chat.
--
--   hop 1  origin -> relay      RL~<f>~<text>            by whisper, to one relay (Pick)
--   hop 2  relay -> reporters   RM~<f>~<origin>~<text>   by whisper, one per guild (its reporter)
--   hop 3  reporter -> guild    RG~<f>~<origin>~<text>   over GUILD, once, to everyone there
--
-- The relays are the signed High Council's characters, the author's, the King and the Treasurer:
-- names every client holds from the signed list, so a guild that just arrived knows whom to
-- whisper. A client picks one relay (its guild's name decides which, changing every PICK_WINDOW so
-- the load spreads), pings it once (RP) and expects an answer (RA): a relay that does not answer
-- (offline, or an older version that cannot; the answer is RY: RA is the Records' ask) is left out for DEAD_FOR and the next one is picked;
-- the server's "No player named X" names an offline one at once. The relays know each guild's
-- reporter from its registration (RR, sent every REGISTER_EVERY while elected: Comm.MaybeBroadcast)
-- and forward to those alone; a reporter hands each message to its guild over GUILD once, where
-- every guildmate takes it as if it had come on the channel (Comm.Inject: the same handlers, the
-- origin as its sender). What came by the relay is taken once (Seen): a relay's copy and the
-- guild's copy of one message count once. <f> is L for a chat line (the origin sends it logged,
-- so his own words are on the server's log) and P for anything else. A piece too long for one
-- whisper travels in Codec's pieces (the assemblers put RL, RM and RG together like any other).
--
-- Trust: the server stamps every hop's sender. A relay is believed about the origin because it is
-- a signed councillor's, the author's, the King's or the Treasurer's character (RM from anyone else
-- is dropped); a reporter is believed by its guild because it is a guildmate (GUILD). Nothing here
-- lets a stranger speak as the King: his words still reach the guilds only through those clients.
-- Off Forever (the beta, Era, Anniversary) nothing here runs and the channel works as before.

--
-- 1.4.4 (the morning after): with one live relay among twenty signed names, a guild took up to an
-- hour to find it, picking one name at a time and waiting PING_WAIT for each. Now the first message
-- with no relay answered yet pings every relay at once (Sweep), is held for the first answer
-- (Flush, from HandleAck) and goes to whoever answered; the pick is made among the relays that
-- answered (VERIFIED_FOR) while any did. The server's "No player named X" for each ping to an
-- offline relay is kept out of the chat (Accord.Quiet) and still read (NotFound).

Relay.PICK_WINDOW = 600      -- seconds one relay serves a guild before the pick moves on
Relay.DEAD_FOR = 600         -- a relay that did not answer, or is offline, is left out this long
Relay.PING_WAIT = 30         -- an answer to the ping is due within this
Relay.VERIFIED_FOR = 900     -- a relay that answered is preferred this long (pinged again after DEAD_FOR)
Relay.PENDING_MAX = 40       -- messages held while no relay has answered yet
Relay.REGISTER_EVERY = 170   -- a reporter tells its relay it is the reporter this often
Relay.REPORTER_FOR = 600     -- a relay keeps a reporter this long past its last registration
Relay.SEEN_FOR = 300         -- a message taken is remembered this long (a second copy counts once)
Relay.SEEN_MAX = 2000
Relay.MAX_RELAYS = 40
Relay.MAX_GUILD_NAME = 48   -- (1.5.4) bytes: the game's 24 letters, accented ones taking 2, in a registration (RR)
Relay.MAX_REPORTERS = 400   -- (1.5.4) guilds a relay keeps a reporter for
Relay.VERIFY_ASK_EVERY = 180 -- one recovery ask across the signed relays, never per reporter
Relay.SNAPSHOT_WINDOW = 60  -- at most one bounded snapshot transfer per signed origin in this window
Relay.LAUNCH_PINS = { ForeverPvE = { "Developus Olympicus", "Asmongold Thereal" }, ForeverPvP = { "Twalin Firebraid", "Elrond Oaklance" } }
-- (1.5.0) Words every client says on the channel on its own clock (the channel's hello H3, the
-- census ask Q1, the lists' ask HQ, positions P1, the Wanted list's ask W4, verification asks GV)
-- are heard by the relay and answered from there, but never fanned out: with 46 guilds registered
-- (the dev's log, 2026-11-05) each such word became 46 whispers, and the reports and the lists
-- waited behind them. A guild's census reports, the chats, the signed lists and every other word
-- go on to every reporter. Verification asks additionally cross signed relays at a bounded
-- cadence, without reaching reporters: the selected relay may not be the verifier holding a word.
Relay.NO_FORWARD = { H3 = true, Q1 = true, HQ = true, P1 = true, W4 = true, GV = true, CG = true }
-- (1.5.4) Guild verification between relays. A relay's own client counts itself as answered
-- (Pick), so it never pings the others and never learns that one answered: Across and the 1.5.2
-- crossing of verification asks went to nobody, and every verifier (the King, the High Council, the
-- author: each a relay) was an island. Verification alone now crosses, as RW, to every relay not
-- left out, answered or not: a verifier's decision (once, to each relay's reporters after), a
-- relay's own ask, one client's ask every VERIFY_ASK_EVERY, and a verifier's answer to a relay that
-- asked. RW never marks a relay as answered (verified), so no other word starts crossing (the census
-- alone would be every word a relay hears, times every other relay); older relays ignore the type.
-- (1.5.0) What one reporter can be sent of other clients' words that are not chat lines: pieces
-- a minute (REPORTER_RATE). 51 guilds reporting every three minutes, three pieces each, to 51
-- reporters is 2,700 pieces a minute; a relay sends 200. So each reporter gets a trickle of the
-- guilds' own reports, and the whole picture from the relay's own global census snapshot (CG,
-- Data.SendGlobalCensus: every guild's counts, trusted as the relay's signed name), sent every
-- GLOBAL_EVERY and exempt from the trickle, as the relay's own words all are.
Relay.REPORTER_RATE = 4
Relay.GLOBAL_EVERY = 120
-- (1.5.4) The King's crown (King.lua: T1~P where he is, T1~Q hidden again; his client says it every
-- 5 s while he moves, every 20 s while he stands) is what every member's map and minimap arrow
-- follow, and it reached nobody: his client, a relay itself, takes its own words to its own
-- reporters alone (relays hear one another only once one pinged the other); any other relay held
-- it in the trickle behind the guilds' reports; and his standing still was a second copy (Seen).
-- Now his client also whispers each crown to every other relay not left out, once each KING_GAP
-- at most; each relay hands the newest to its reporters, each once each KING_GAP at most and the
-- longest waiting first, KING_PER_MIN a minute in all (KING_BURST at once), ahead of the queue's
-- other words so a busy relay neither drops nor delays it; a repeat renews it wherever it arrives;
-- "hidden" goes to all at once. Clients keep it King.LOCATION_EXPIRE_RELAYED, past the slowest pace.
Relay.KING_GAP = 30
Relay.KING_PER_MIN = 40
Relay.KING_BURST = 20
local crownBucket = { tokens = 0, at = -math.huge } -- (on a relay) the crowns it may hand on now
local budget = {} -- reporter name (lower) -> { at = when refilled, left = pieces }
-- (The load review of the 1.5.4 candidate.) REPORTER_RATE to each reporter made the trickle grow with
-- the reporters: 35 of them could take 140 whispers a minute and 80 of them 320, more than a relay
-- sends in all (200), so the queue was never empty enough for a reporter's whole census snapshot
-- (the drip waits for room; the offline load model: about one whole snapshot per reporter in 20
-- minutes at 35 reporters, almost none at 80, and the trickle's own words gained nothing). The
-- trickle now shares TRICKLE_PER_MIN a minute among the reporters, REPORTER_RATE at most each: an
-- allowance refilled at its share, holding at most REPORTER_RATE and, at a smaller share, a wrapped
-- piece (two whispers) still (the model: half again as many whole snapshots at 35 reporters and
-- five times as many at 80, none left without one at 35; more chat lines and decisions arrive).
Relay.TRICKLE_PER_MIN = 60
local share = Relay.REPORTER_RATE -- each reporter's whispers a minute (ToReporters sets it)
local function Afford(name, pieces, now)
	local most = math.min(Relay.REPORTER_RATE, math.max(2, share))
	local key = name:lower()
	local b = budget[key]
	if not b then b = { at = now, left = most }; budget[key] = b end
	b.left = math.min(most, b.left + math.max(0, now - b.at) * share / 60)
	b.at = now
	if b.left < pieces then return false end
	b.left = b.left - pieces
	return true
end

local offline = {}   -- relay name (lower) -> until (ns.Now())
local verified = {}  -- relay name (lower) -> when its RA last came
local pinged = {}    -- relay name (lower) -> when we pinged it, while an answer is due
local reporters = {} -- (on a relay) guild name (lower) -> { name = "First Surname-Realm", t = when }
local seen = {}      -- origin .. "|" .. text -> when
local lastVerifyAsk = -math.huge
local snapshotTransfers = {}
local crownSent = {} -- "r:" reporter or "x:" relay (lower) -> when the King's crown last went to it
local crownLayer = {} -- (1.5.4) "l:" relay (lower) -> the King's layer word last whispered to it
local seenCount = 0
local pending = {}   -- (1.4.4) what waits for the first relay to answer: { parts, logged, done, key, urgent, options }
local holding = false -- a timer runs to send what waits anyway after PING_WAIT
local flushing = false
local stats = { out = 0, forwarded = 0, delivered = 0, dropped = 0, dead = 0, registered = 0 }
function Relay.Stats()
	local n = 0
	for _, r in pairs(reporters) do n = n + 1 end
	local relay, sure = Relay.Pick()
	return { out = stats.out, forwarded = stats.forwarded, delivered = stats.delivered, dropped = stats.dropped,
		dead = stats.dead, reporters = n, relay = relay, sure = sure == true, pending = #pending, on = Relay.On(),
		across = stats.across or 0, kept = stats.kept or 0, trickled = stats.trickled or 0 }
end

local function Now() return ns.Now() end
local function Lower(s) return type(s) == "string" and s:lower() or "" end

-- (1.5.4) The King's crown, by his signed name (KING_GAP above), and whether one more is due to `to`.
local function Crown(origin, body)
	if type(body) ~= "string" or not body:match("^T1~[PQ]~") then return false end
	return type(origin) == "string" and ns.IsKingCharacter ~= nil and ns.IsKingCharacter(ns.FullName(origin)) == true
end
local function Hide(body) return body:match("^T1~Q~") ~= nil end
local function CrownDue(to, body, now)
	return Hide(body) or now - (crownSent[to] or -math.huge) >= Relay.KING_GAP
end

-- Where it runs: where the game splits names (Forever), unless switched off for a test.
function Relay.On()
	return ns.splitNames == true and ns.rdb ~= nil and ns.rdb.relayOff ~= true
end

-- The relays' names, as whispers reach them: the plain "First Surname", sorted; ours left out
-- unless asked for (IsRelay asks: our own client is a relay too).
function Relay.Names(withSelf)
	local out, set = {}, {}
	local mine = ns.ShortName(ns.me or ""):lower()
	local function Add(n)
		if type(n) ~= "string" or n == "" then return end
		local short = ns.ShortName(n)
		local key = short:lower()
		if key == "" or set[key] or (not withSelf and key == mine) then return end
		if #out >= Relay.MAX_RELAYS then return end
		set[key] = true
		out[#out + 1] = short
	end
	local c = ns.rdb and ns.rdb.council
	if type(c) == "table" and type(c.names) == "table" then
		local list = {}
		for _, name in pairs(c.names) do list[#list + 1] = name end
		table.sort(list)
		for _, name in ipairs(list) do Add(name) end
	end
	if ns.AuthorCharacters then for _, n in ipairs((ns.AuthorCharacters())) do Add(n) end end
	if ns.KingCharacter then Add(ns.KingCharacter()) end
	-- (1.4.6) A client with no signed list yet (a guild nobody handed it to) must still find a
	-- relay to get it from: the launch's author and King, by code, on their Forever family alone.
	local family = ns.ForeverFamily and ns.ForeverFamily(ns.realm)
	if family then for _, p in ipairs(Relay.LAUNCH_PINS[family] or {}) do Add(p) end end
	if ns.TreasurerPins then for _, n in ipairs((ns.TreasurerPins())) do Add(n) end end
	table.sort(out)
	return out
end
function Relay.IsRelay(name)
	local key = ns.ShortName(name or ""):lower()
	if key == "" then return false end
	for _, n in ipairs(Relay.Names(true)) do if n:lower() == key then return true end end
	return false
end

local function Hash(text)
	local h = 5381
	for i = 1, #text do h = (h * 33 + text:byte(i)) % 2147483647 end
	return h
end
-- The relay this client whispers to now, and whether it is sure: among the relays that answered
-- a ping within VERIFIED_FOR (our own client counts, when it is a relay: no whisper needed), the
-- one our guild's name and the window pick, sure; with none answered yet, the same among those
-- not left out, not sure (Out then holds the message and pings them all); nil without any (then
-- the channel, as before).
function Relay.Pick()
	if not Relay.On() then return nil end
	local now = Now()
	local mine = ns.ShortName(ns.me or ""):lower()
	local live, answered = {}, {}
	for _, n in ipairs(Relay.Names(true)) do
		local key = n:lower()
		if (offline[key] or 0) <= now then
			live[#live + 1] = n
			if key == mine or now - (verified[key] or -math.huge) < Relay.VERIFIED_FOR then answered[#answered + 1] = n end
		end
	end
	local pool = #answered > 0 and answered or live
	if #pool == 0 then return nil end
	local seed = Lower(GetGuildInfo and GetGuildInfo("player") or ns.me or "") .. "#" .. tostring(math.floor(now / Relay.PICK_WINDOW))
	return pool[(Hash(seed) % #pool) + 1], #answered > 0
end

local function LeaveOut(name, why)
	local key = ns.ShortName(name or ""):lower()
	if key == "" then return end
	offline[key] = Now() + Relay.DEAD_FOR
	pinged[key] = nil
	stats.dead = stats.dead + 1
	ns.Log("relay %s left out for %ds: %s", tostring(name), Relay.DEAD_FOR, tostring(why))
end
Relay.LeaveOut = LeaveOut

-- The envelope of hop 1 for one message: whole, or in pieces when a whisper cannot carry it.
local relayId = 0
local function Envelope(kind, text)
	if #text <= 255 then return { text } end
	relayId = (relayId + 1) % 1000
	return ns.Codec.Chunk(text, "R" .. relayId)
end

-- A relay not answered lately is pinged once; no answer in PING_WAIT leaves it out.
-- The server's "No player named X" for a whisper to someone offline: kept out of the chat for the
-- Accord's quiet window (Accord.Quiet, gated there); NotFound still reads the event.
local function Quiet(name)
	local A = ns.Accord
	if type(A) == "table" and type(A.Quiet) == "function" then ns.SafeCall("relay quiet", A.Quiet, name) end
end
Relay.Quiet = Quiet

local function Ping(relay)
	local key = relay:lower()
	local now = Now()
	if now - (verified[key] or -math.huge) < Relay.DEAD_FOR then return end
	if pinged[key] then return end
	pinged[key] = now
	Quiet(relay)
	ns.Comm.Whisper(relay, "RL~P~RP~", "relay ping:" .. key, true)
	ns.After(Relay.PING_WAIT, "relay ping", function()
		if pinged[key] == now and now - (verified[key] or -math.huge) >= Relay.DEAD_FOR then
			pinged[key] = nil
			LeaveOut(relay, "no answer to the ping")
		end
	end)
end
-- (1.4.4) Every relay not answered yet, pinged at once (one short whisper each): the first answer
-- takes what waits (HandleAck -> Flush); the offline ones the server names at once (NotFound), the
-- rest fall out after PING_WAIT, and each stays out for DEAD_FOR before it is pinged again.
local function Sweep()
	local now = Now()
	for _, n in ipairs(Relay.Names(false)) do
		if (offline[n:lower()] or 0) <= now then Ping(n) end
	end
end
Relay.Sweep = Sweep

-- Held for the first relay to answer. A keyed message takes a waiting one's place, as in Comm's
-- queue (the newest payload, a supplied callback replaces the old one); past PENDING_MAX the
-- oldest is dropped (its callback told).
local function Hold(parts, logged, done, key, urgent, options)
	if key then
		for _, p in ipairs(pending) do
			if p.key == key then
				p.parts, p.logged, p.urgent, p.options = parts, logged, urgent, options
				p.done = done or p.done
				return
			end
		end
	end
	if #pending >= Relay.PENDING_MAX then
		local old = table.remove(pending, 1)
		if old.done then ns.SafeCall("relay done", old.done, false) end
	end
	pending[#pending + 1] = { parts = parts, logged = logged, done = done, key = key, urgent = urgent, options = options }
end
-- What waited goes out to the relay picked now: once one answered, or anyway after PING_WAIT (to
-- the pick as 1.4.3 did; an older relay may not hear it, and registrations and the census repeat).
local function Flush(anyway)
	if flushing or #pending == 0 then return end
	local _, sure = Relay.Pick()
	if not sure and not anyway then return end
	flushing = true
	local list = pending
	pending = {}
	for _, p in ipairs(list) do
		if not Relay.Out(p.parts, p.logged, p.done, p.key, p.urgent, p.options, true) and p.done then
			ns.SafeCall("relay done", p.done, false)
		end
	end
	flushing = false
end
Relay.Flush = Flush

-- Hop 1: what a module said "on the channel" goes to our relay. parts: the message's pieces as the
-- channel would carry them (each one whisper). Returns true when handed to the queue.
local ToGuild -- (below: hop 3)
local function PermitParts(parts, options)
	for _, p in ipairs(parts) do
		local ok, valid, why = true, true
		if options and options.guard then ok, valid = pcall(options.guard) end
		if ok and valid == true and options and options.permit then
			ok, valid, why = pcall(options.permit, options.owner, options.guardKey, "CHANNEL", nil, p)
		end
		if not ok or valid ~= true then return false, why or "guard" end
	end
	return true
end

-- (The layer hop on Forever, after 1.5.3.) A layer-hop ask (LQ) and the King-sighting query (LY~Q)
-- are for helpers who can answer them, and on Forever those are the asker's own guildmates:
-- Hop.Member takes another guild's ordinary member for a stranger, a relay hands another client's
-- word to a reporter only within REPORTER_RATE (the dev's relay on 2026-11-07: about 149 words a
-- minute for 34 reporters, four of them passed a minute), and a word that passes waits in the
-- relay's queue past the ask's NOBODY window. So these go to the asker's guild at once over GUILD,
-- as the relay's hand-over from himself (RG, which 1.5.3 guildmates already take:
-- Relay.HandleGuild), and to no relay. Layer words (L1, L0) go to the guild at once as well, and
-- still to the relay. The origin is the plain name: Forever's roster files every guildmate by his
-- bare name under the reader's own sub-realm, so a name stamped with another sub-realm missed that
-- row and the guildmate was a stranger (Hop.Member, Roster.RankOf).
Relay.GUILD_ONLY = { LQ = true } -- (and LY~Q, GuildRoute)
Relay.GUILD_TOO = { L0 = true, L1 = true }
local function GuildRoute(text)
	if type(text) ~= "string" then return nil end
	if Relay.GUILD_ONLY[text:sub(1, 2)] or text:find("^LY~Q~") then return "only" end
	if Relay.GUILD_TOO[text:sub(1, 2)] then return "too" end
	return nil
end
Relay.GuildRoute = GuildRoute
-- nil when it cannot be wrapped (then the relay as before); else whether Comm took it.
local function OwnGuild(original, done, key, urgent, options)
	local me = ns.ShortName(ns.me or "") or ""
	local wrapped = "RG~P~" .. me .. "~" .. original
	if me == "" or #wrapped > 255 then return nil end
	local pass = { owner = options and options.owner or Relay, guard = function()
		-- The wrapped text names no type Comm's holds read: the original's are asked here, at the
		-- actual send, as Comm asks the original's on the channel (quiet presence, net-off).
		if ns.Comm.QuietHolds and ns.Comm.QuietHolds(original) then return false, "quiet" end
		local M = ns.Moderation
		if type(M) == "table" and not M.missing and type(M.Blocks) == "function" and M.Blocks(original) == true then
			return false, "held"
		end
		if options and options.guard then
			local ok, valid, why = pcall(options.guard)
			if not ok or valid ~= true then return false, why or "guard" end
		end
		return true
	end }
	if options and options.permit then
		-- The owner's permit keeps seeing its original lane and payload (as Relay.Out's whispers do).
		pass.key = options.guardKey
		pass.permit = function(owner, guardKey, dist, target, message)
			if owner ~= options.owner or guardKey ~= options.guardKey or dist ~= "GUILD" or target ~= nil
				or message ~= wrapped then return false, "lane" end
			return options.permit(owner, guardKey, "CHANNEL", nil, original)
		end
	end
	return ns.Comm.Send("GUILD", wrapped, key and ("guild " .. key) or nil, urgent, false, done, pass) ~= false
end

-- (1.5.4) The King's own crown, to every other relay not left out: one whisper each, once each
-- KING_GAP at most, ahead of his queue's other words; the relay picked has it by the usual hop below.
local function CrownToRelays(parts, pick)
	if not (ns.me and ns.IsKingCharacter and ns.IsKingCharacter(ns.me)) then return end
	local now, mine, picked = Now(), Lower(ns.ShortName(ns.me)), Lower(pick)
	for _, p in ipairs(parts) do
		-- (His presence, T1~o every King.PRESENCE_EVERY, goes the same way, on its own gap slot: a
		-- relay never pings another, so the other relays' guilds heard it from nobody.)
		local presence = type(p) == "string" and p:match("^T1~o~%d+~") ~= nil
		-- (And his layer, L1 or L0: when it changes, else once each KING_REFRESH, as relays hand it on.)
		local layer = type(p) == "string" and p:match("^L[01]~") ~= nil
		if type(p) == "string" and (p:match("^T1~[PQ]~") or presence or layer) then
			for _, n in ipairs(Relay.Names(false)) do
				local to = Lower(n)
				local slot = (presence and "o:" or layer and "l:" or "x:") .. to
				local due = presence or (layer and (crownLayer[slot] ~= p or now - (crownSent[slot] or -math.huge) >= Relay.KING_REFRESH))
					or (not layer and CrownDue(slot, p, now))
				if to ~= mine and to ~= picked and (offline[to] or 0) <= now and due then
					if layer then crownLayer[slot] = p end
					crownSent[slot] = now
					Quiet(n)
					ns.Comm.Whisper(n, "RL~P~" .. p, (presence and "presence " or layer and "layer " or "crown ") .. to, true, false)
				end
			end
		end
	end
end
function Relay.Out(parts, logged, done, key, urgent, options, anyway)
	if not anyway and not logged and #parts == 1 and IsInGuild() then
		local route = GuildRoute(parts[1])
		if route == "only" then
			if OwnGuild(parts[1], done, key, urgent, options) ~= nil then return true end
		elseif route == "too" then
			OwnGuild(parts[1], nil, key, urgent, options)
		end
	end
	local relay, sure = Relay.Pick()
	if not relay then return false end
	if not anyway then CrownToRelays(parts, relay) end
	-- (1.4.5) A chat line reaches the sender's own guild at once, over GUILD, as hop 3 from himself,
	-- whatever the relays do (one dead, none answered yet): guildmates take it once (Seen), and
	-- the relay's copy that comes back later counts once too. The relay still carries it to the
	-- other guilds. The flush of a held line sends to the guild no second time.
	if logged and not anyway and IsInGuild() then
		local valid, why = PermitParts(parts, options)
		if not valid then
			if done then ns.SafeCall("relay done", done, false, why) end
			return true
		end
		for _, p in ipairs(parts) do ToGuild("L", ns.me, p) end
	end
	if not sure and not anyway then
		-- A held message is refused now, as its whispers would be later, when the capability
		-- that guards it refuses it (1.5.2 checked it for the text fallback, gone in 1.5.4).
		local valid, why = PermitParts(parts, options)
		if not valid then
			if done then ns.SafeCall("relay done", done, false, why) end
			return true
		end
		-- (1.4.4) No relay answered yet: all pinged at once, the message held for the first answer.
		-- (1.5.4: no channel text meanwhile; ChatHall.lua says why.)
		Sweep()
		Hold(parts, logged, done, key, urgent, options)
		if not holding then
			holding = true
			ns.After(Relay.PING_WAIT + 1, "relay hold", function()
				holding = false
				Flush(true)
			end)
		end
		return true
	end
	local flag = logged and "L" or "P"
	-- Our own client the relay: handed to it here, whole (a whisper to oneself is never delivered).
	if relay:lower() == ns.ShortName(ns.me or ""):lower() then
		-- No physical queue exists on this route. Apply the same logical-channel
		-- guards before handing off any part, including a transfer held for a ping.
		local valid, why = PermitParts(parts, options)
		if not valid then
			if done then ns.SafeCall("relay done", done, false, why) end
			return true -- handled refusal; never fall back to an unguarded channel send
		end
		stats.out = stats.out + 1
		for _, p in ipairs(parts) do Relay.HandleIn("WHISPER", ns.me, "RL~" .. flag .. "~" .. p) end
		if done then ns.SafeCall("relay done", done, true) end
		return true
	end
	local pieces, originals = {}, {}
	for _, p in ipairs(parts) do
		for _, e in ipairs(Envelope("RL", "RL~" .. flag .. "~" .. p)) do
			pieces[#pieces + 1], originals[e] = e, p
		end
	end
	if #pieces == 0 or #pieces > ns.Codec.MAX_CHUNKS then return false end
	Ping(relay)
	Quiet(relay)
	stats.out = stats.out + 1
	local pass
	if options then
		pass = { owner = options.owner, guard = options.guard, guardKey = options.guardKey }
		if options.permit then
			-- Comm normalized key -> guardKey on the logical CHANNEL job. Restore
			-- the public capability shape when creating its physical WHISPER job.
			-- Only these exact envelopes to this still-signed relay may spend it;
			-- the owner's permit continues to see its original lane and payload.
			pass.key = options.guardKey
			pass.permit = function(owner, guardKey, dist, target, message)
				local original = originals[message]
				if owner ~= options.owner or guardKey ~= options.guardKey or dist ~= "WHISPER"
					or target ~= relay or not Relay.IsRelay(target) or not original then return false, "lane" end
				return options.permit(owner, guardKey, "CHANNEL", nil, original)
			end
		end
	end
	if #pieces == 1 then
		return ns.Comm.Whisper(relay, pieces[1], key, urgent, logged, done, pass) ~= false
	end
	return ns.Comm.SendBatch("WHISPER", pieces, key, relay, urgent, done, pass) ~= false
end

-- The reporter's registration (Comm.MaybeBroadcast, every REGISTER_EVERY while elected).
local lastRegister = -math.huge
function Relay.Register(force)
	if not Relay.On() then return false end
	local now = Now()
	if not force and now - lastRegister < Relay.REGISTER_EVERY then return false end
	local guild = GetGuildInfo and GetGuildInfo("player")
	if type(guild) ~= "string" or guild == "" then return false end
	lastRegister = now
	return Relay.Out({ "RR~" .. guild }, false, nil, "relay register", false)
end

-- Taking a message and deciding whether to forward it use the same age limit. An expired
-- key may remain in this bounded table until cleanup; its presence alone is not a duplicate.
local function Remembered(origin, text, now)
	local at = seen[Lower(origin) .. "|" .. text]
	return at ~= nil and (now or Now()) - at < Relay.SEEN_FOR
end

-- Taken once: a message by its origin and text (the relay's copy and the guild's count once).
local function Seen(origin, text)
	local now = Now()
	local key = Lower(origin) .. "|" .. text
	if Remembered(origin, text, now) then return true end
	if seenCount >= Relay.SEEN_MAX then
		for k, t in pairs(seen) do
			if now - t >= Relay.SEEN_FOR then seen[k] = nil seenCount = seenCount - 1 end
		end
		if seenCount >= Relay.SEEN_MAX then wipe(seen) seenCount = 0 end
	end
	if not seen[key] then seenCount = seenCount + 1 end
	seen[key] = now
	return false
end

-- The last hop on this client: the message as if it had come on the channel from its origin.
local function Deliver(origin, text, logged)
	-- (1.5.4) The King's crown again (him standing still: the same words every 20 s) renews it.
	if Seen(origin, text) and not (text:match("^T1~P~") and Crown(origin, text)) then return false end
	-- (The review of the 1.5.4 candidate.) A layer word (L1, L0: GUILD_TOO) reaches the origin's
	-- guildmates twice: his own copy over GUILD names him plain (OwnGuild), the relay's copy as the
	-- relay's client stamped him, "Name-<its sub-realm>". Layers counted him twice, and a reporter
	-- handed the relay's copy to the guild again. A name is one across a Forever family: one word,
	-- once, whichever copy came first.
	if GuildRoute(text) == "too" and origin:find("-", 1, true) and Seen(ns.ShortName(origin), text) then return false end
	stats.delivered = stats.delivered + 1
	ns.Comm.Inject("CHANNEL", origin, text, logged)
	return true
end

-- A reporter hands a message to its guild once (hop 3).
ToGuild = function(flag, origin, text)
	if not IsInGuild() then return false end
	local pieces = Envelope("RG", "RG~" .. flag .. "~" .. origin .. "~" .. text)
	if #pieces == 1 then return ns.Comm.Send("GUILD", pieces[1], nil, false, false) ~= false end
	return ns.Comm.SendBatch("GUILD", pieces, nil, nil, false) ~= false
end

-- A word to every guild's reporter we hold (ours included: delivered here and handed to our
-- guild), and heard here (a relay in a guild whose reporter is elsewhere, or none).
local function QueueWord(body)
	-- Fragment i and fragment i+1 are both required. Coalescing them by the first
	-- two bytes (C1, etc.) discarded all but the last before the queue could send.
	-- (1.5.4) The Throne's kinds apart too: the King's newest crown never takes a waiting call's place.
	return body:match("^(C[^:]+:%d+):%d+:") or body:match("^(T1~%a)~") or body:sub(1, 2)
end

local function SnapshotPart(origin, body, now)
	if not Relay.IsRelay(origin) then return false end
	local id, index, total, part = body:match("^C(%w+):(%d+):(%d+):(.*)$")
	index, total = tonumber(index), tonumber(total)
	if not id or #id > 16 or total < 1 or total > ns.Codec.MAX_CHUNKS
		or index < 1 or index > total or #part > ns.Codec.CHUNK
		or (index < total and #part ~= ns.Codec.CHUNK) then return false end
	local key = Lower(ns.FullName(origin))
	local transfer = snapshotTransfers[key]
	if transfer and now - transfer.at >= Relay.SNAPSHOT_WINDOW then transfer = nil; snapshotTransfers[key] = nil end
	if not transfer then
		if index ~= 1 or not (part:match("^GV~1~S~%d+~")
			or part:match("^CG~[12]~S~%d+~") or part:match("^CX~[123]~S~")) then return false end
		local count = 0
		for who, entry in pairs(snapshotTransfers) do
			if now - entry.at >= Relay.SNAPSHOT_WINDOW then snapshotTransfers[who] = nil
			else count = count + 1 end
		end
		if count >= Relay.MAX_RELAYS then return false end
		transfer = { id = id, total = total, at = now, bytes = 0, parts = {} }
		snapshotTransfers[key] = transfer
	end
	if transfer.id ~= id or transfer.total ~= total or transfer.parts[index] then return false end
	if transfer.bytes + #part > ns.Codec.CHUNK * ns.Codec.MAX_CHUNKS then return false end
	transfer.parts[index], transfer.bytes = true, transfer.bytes + #part
	return true
end
-- Whole sets, one reporter at a time (GitHub #76: the census showed only the player's own guild).
--
-- A word in pieces that skips the trickle (the relay's own global census snapshot, another relay's
-- signed snapshot) used to go out piece by piece to every reporter at once. With 46 guilds, an
-- 8-piece snapshot was 368 whispers; the send queue holds 60 (Comm's MAX_QUEUE) and dropped the
-- rest, so every reporter got one or two pieces of a message he could never put together.
--
-- Now the relay waits until it holds every piece of such a word, then hands each reporter the
-- whole set as one batch, and the next reporter's batch only once that one is done. A batch that
-- has begun is never dropped by the queue and reaches its reporter in seconds, well inside the
-- 60 seconds a receiver waits for missing pieces. Nothing new is trusted and nothing on the wire
-- changes: a reporter receives the same whispers as before, only all of them.
Relay.SET_WAIT = 60 -- seconds the relay waits for a set's missing pieces (as receivers do)
local sets = {}   -- origin#id -> { n = pieces expected, got = pieces held, pieces = { [i] = body }, t = first piece }
local drip = {}   -- batches waiting, first in first out: { name = reporter, word = what it is, whispers = { ... } }
local dripSince   -- when the batch in flight was handed to the queue (nil: none in flight)
local dripping = false

-- The pieces of a word, in order, once all of them are here; false while some are missing;
-- nil when the body is not a piece of a larger word (it goes on as before).
local function CollectSet(origin, body, now)
	local id, i, n = body:match("^C(%w+):(%d+):(%d+):")
	i, n = tonumber(i), tonumber(n)
	if not id or n < 2 or n > ns.Codec.MAX_CHUNKS or i < 1 or i > n then return nil end
	for key, s in pairs(sets) do
		if now - s.t > Relay.SET_WAIT then sets[key] = nil end -- (a set that never completed)
	end
	local key = Lower(origin) .. "#" .. id
	local s = sets[key]
	if not s or s.n ~= n then
		s = { n = n, got = 0, pieces = {}, t = now }
		sets[key] = s
	end
	if not s.pieces[i] then s.pieces[i], s.got = body, s.got + 1 end
	if s.got < n then return false end
	sets[key] = nil
	return s.pieces
end

-- Sends the next waiting batch, unless one is still in flight. Called again when it is done.
local function Drip()
	if dripping then return end
	if dripSince and Now() - dripSince < Relay.SET_WAIT then return end
	dripping, dripSince = true, nil
	while not dripSince and drip[1] do
		local d = drip[1]
		-- A batch waits for room in the queue: forced in, it would push out the words already
		-- waiting there (a verifier's approval among them). Tried again in a second.
		if ns.Comm.QueueRoom() < #d.whispers then
			dripSince = Now()
			ns.After(1, "relay drip", function() dripSince = nil; Drip() end)
			break
		end
		table.remove(drip, 1)
		Quiet(d.name) -- (a reporter gone offline since: the server's line out of the chat)
		-- (The review of the 1.5.4 candidate.) Its time counts from its first turn, not from when it
		-- was queued: a batch waits a whole round of reporters (more than SET_WAIT), so one pushed
		-- out before it began was never put back and its reporter waited another round. Put back
		-- for SET_WAIT after its first turn, never longer (a retry keeps this time).
		if not d.tried then stats.forwarded, d.tried, d.t = stats.forwarded + 1, true, Now() end
		dripSince = Now()
		-- done runs once, whatever happens. A batch the queue had no room for, or pushed out for
		-- newer words, goes back to the front while it is fresh; otherwise the next batch goes.
		ns.Comm.SendBatch("WHISPER", d.whispers, nil, d.name, false, function(sent, why)
			if not sent and (why == "full" or why == "dropped") and Now() - d.t < Relay.SET_WAIT then
				table.insert(drip, 1, d)
				ns.After(1, "relay drip", function() dripSince = nil; Drip() end)
				return
			end
			dripSince = nil
			Drip()
		end)
	end
	dripping = false
end

-- Queues a whole set for one reporter. A newer copy of the same word for him replaces one still
-- waiting, so a busy relay sends the latest snapshot, never a backlog.
local function DripSet(name, word, whispers)
	for _, d in ipairs(drip) do
		if d.name == name and d.word == word then
			d.whispers = whispers
			return Drip()
		end
	end
	drip[#drip + 1] = { name = name, word = word, whispers = whispers, t = Now() }
	Drip()
end

-- The whispers that carry a whole set to a reporter, cut into batches the queue accepts.
-- The set goes as the one word it carries, wrapped once and cut once, so every whisper is full.
-- Wrapped piece by piece, a full piece and its RM label overflowed one whisper and each piece went
-- as two (an 8-piece census snapshot as 16 whispers to every reporter). A reporter takes either
-- form the same way: it puts the RM together, then the word inside it.
local function SetWhispers(flag, origin, set)
	local parts = {}
	for i, body in ipairs(set) do parts[i] = body:match("^C%w+:%d+:%d+:(.*)$") end
	local word = table.concat(parts)
	-- (review prototype) Only a word with a type a handler takes whole: a census report (R1, R2)
	-- is decoded from its pieces alone (Comm's CHANNEL path), so it keeps its pieces.
	if #parts == #set and word:match("^%u%w~") and not word:match("^R[12]~") then
		local whispers = Envelope("RM", "RM~" .. flag .. "~" .. origin .. "~" .. word)
		if #whispers <= ns.Codec.MAX_CHUNKS then return whispers end
	end
	local whispers
	-- (Too long to travel as one word: the pieces as they came, each wrapped on its own.)
	whispers = {}
	for _, body in ipairs(set) do
		for _, e in ipairs(Envelope("RM", "RM~" .. flag .. "~" .. origin .. "~" .. body)) do
			whispers[#whispers + 1] = e
		end
	end
	return whispers
end

local function SetBatches(flag, origin, set)
	local whispers = SetWhispers(flag, origin, set)
	local batches, size = {}, ns.Codec.MAX_CHUNKS
	for first = 1, #whispers, size do
		local batch = {}
		for k = first, math.min(first + size - 1, #whispers) do batch[#batch + 1] = whispers[k] end
		batches[#batches + 1] = batch
	end
	return batches
end

-- (1.5.4) An integration's profile presentation (ProfileEffects, FX) names its guild. A presenter's
-- own words (S, and its stop X) go to that guild's reporter alone. Their heartbeat (every 10 s, a
-- 32 s lease) to every reporter was most of what a relay sent: 44 of 353 words on the dev's relay
-- in 142 s, each to 32-36 reporters outside the trickle, about three times the relay's 200 whispers
-- a minute by itself, and the census snapshots waited behind it (the offline harness: complete
-- snapshots per reporter more than doubled without it).
-- The issuer's grant (G) and close (C) name the issuer's own guild, yet a member of any guild
-- presents only under a grant he holds: scoped like the rest, no other guild ever got one (the
-- review of the 1.5.4 candidate). A close goes to every reporter at once. A grant (its issuer beats
-- every 10 s) goes to every reporter at most once each GRANT_EVERY per origin, and to the named
-- guild's reporter alone in between; where names split a heard grant lives
-- ProfileEffects.SESSION_TTL_RELAYED, past two such beats.
Relay.GRANT_EVERY = 60
Relay.GRANT_ORIGINS = 64 -- origins whose last grant to every reporter a relay remembers
local grantSent = {} -- origin (short name, lower) -> when its grant last went to every reporter
-- Whether this origin's grant goes to every reporter now (and noted so). Keyed by the short name:
-- a name is one across a Forever family, whichever sub-realm stamped it. Bounded: the stale ones
-- leave, then the oldest, before a new origin is kept.
local function GrantToAll(origin, now)
	local key = Lower(ns.ShortName(origin))
	if now - (grantSent[key] or -math.huge) < Relay.GRANT_EVERY then return false end
	if not grantSent[key] then
		local n, oldest = 0, nil
		for k, at in pairs(grantSent) do
			if now - at >= Relay.GRANT_EVERY then grantSent[k] = nil
			else
				n = n + 1
				if not oldest or at < grantSent[oldest] then oldest = k end
			end
		end
		if n >= Relay.GRANT_ORIGINS and oldest then grantSent[oldest] = nil end
	end
	grantSent[key] = now
	return true
end
-- The guild (lower) a presentation goes to alone, or nil when it goes to every reporter.
local function PresentationScope(origin, body, now)
	if type(body) ~= "string" then return nil end
	local kind, guild = body:match("^FX~%d+~(%a)~[^~]*~%d+~%d+~%d+~([^~]+)")
	if not kind then return nil end
	if kind == "C" or (kind == "G" and GrantToAll(origin, now)) then return nil end
	return Lower(guild)
end
-- (1.5.4) The King's crown to this relay's reporters (KING_GAP above): each at most once a KING_GAP,
-- the longest waiting first, within the relay's KING_PER_MIN (KING_BURST at once), ahead in the
-- queue; "hidden" to all at once. Heard here too.
local function CrownToReporters(flag, origin, body, now)
	local hide, due = Hide(body), {}
	for g, r in pairs(reporters) do
		if now - r.t > Relay.REPORTER_FOR then reporters[g] = nil
		elseif CrownDue("r:" .. Lower(r.name), body, now) then due[#due + 1] = r end
	end
	local function Last(r) return crownSent["r:" .. Lower(r.name)] or -math.huge end
	table.sort(due, function(a, b) return Last(a) < Last(b) end)
	local b = crownBucket
	b.tokens = math.min(Relay.KING_BURST, b.tokens + math.max(0, now - b.at) * Relay.KING_PER_MIN / 60)
	b.at = now
	local pieces, heard, ahead = nil, nil, 0
	for _, r in ipairs(due) do
		if r.name == ns.me then
			crownSent["r:" .. Lower(r.name)] = now
			heard = Deliver(origin, body, false)
			ToGuild(flag, origin, body)
		elseif hide or b.tokens >= 1 then
			if not hide then b.tokens = b.tokens - 1 end
			crownSent["r:" .. Lower(r.name)] = now
			pieces = pieces or Envelope("RM", "RM~" .. flag .. "~" .. origin .. "~" .. body)
			stats.forwarded = stats.forwarded + 1
			Quiet(r.name)
			-- (A "hidden" to more than KING_BURST reporters: the rest in line, never past the queue's room.)
			local urgent = ahead < Relay.KING_BURST
			ahead = ahead + 1
			local key = "relay " .. r.name .. " " .. Lower(origin) .. " " .. QueueWord(body)
			if #pieces == 1 then ns.Comm.Whisper(r.name, pieces[1], key, urgent, false)
			else ns.Comm.SendBatch("WHISPER", pieces, key, r.name, urgent) end
		else
			stats.trickled = (stats.trickled or 0) + 1
		end
	end
	if not heard then Deliver(origin, body, false) end
end
-- (1.5.4) The King's presence (T1~o, King.SendPresence: one piece from his signed character every
-- King.PRESENCE_EVERY) goes to every reporter as the relay's own words do, ahead of the queue and keyed
-- per reporter: a busy relay holds at most one per reporter, the latest. 60 reporters, every five
-- minutes: 12 pieces a minute of the 200 a relay sends. Within the trickle it reached a reporter
-- only by chance, and the army never saw him online (the dev's report, 2026-11-08).
local function KingPresence(origin, body)
	return #body <= 64 and body:match("^T1~o~%d+~") ~= nil and ns.IsKingCharacter ~= nil and ns.IsKingCharacter(origin) == true
end
Relay.KingPresence = KingPresence
-- (The layer hop on Forever, after 1.5.3.) The King's own layer word (L1, or L0 when he hides it,
-- from his pinned character: the relay is believed about its origin) reaches every reporter outside
-- the trickle: once when it changes, and again at most every KING_REFRESH for each reporter, so a
-- guild's members learn where to ask for his layer without his minute-by-minute repeats costing a
-- whisper per reporter each minute. With 34 reporters: 34 whispers a change, under 7 a minute else.
Relay.KING_REFRESH = 300
local kingSent = {} -- reporter name (lower) -> { body, at }: the King's layer word last sent to him
local function KingLayer(origin, body, name, now)
	if type(body) ~= "string" or not body:find("^L[01]~") or type(ns.IsKingCharacter) ~= "function"
		or not ns.IsKingCharacter(origin) then return false end
	local key = name:lower()
	local last = kingSent[key]
	if last and last.body == body and now - last.at < Relay.KING_REFRESH then return false end
	kingSent[key] = { body = body, at = now }
	return true
end
Relay.ResetKingSent = function() wipe(kingSent) end -- (tests)

local function ToReporters(flag, origin, body, sender)
	local now = Now()
	if Crown(origin, body) then
		local n = 0
		for _ in pairs(reporters) do n = n + 1 end
		if not Remembered(origin, body) then ns.Log("relay: %s's word (T1) to %d reporters", tostring(sender), n) end
		return CrownToReporters(flag, origin, body, now)
	end
	local own = ns.FullName(origin) == ns.me
	local fresh = 0
	for _, r in pairs(reporters) do
		if now - r.t <= Relay.REPORTER_FOR then fresh = fresh + 1 end
	end
	share = math.min(Relay.REPORTER_RATE, Relay.TRICKLE_PER_MIN / math.max(1, fresh))
	local scoped = PresentationScope(origin, body, now)
	local presence = flag ~= "L" and KingPresence(origin, body)
	-- Reserve a complete, bounded snapshot from a signed origin. Charging each
	-- fragment against the four-piece ordinary trickle stranded every larger
	-- snapshot mid-transfer. This admits no new authority and does not bypass
	-- Comm's queue/throughput limits; malformed or unreserved parts use the trickle.
	local snapshot = SnapshotPart(origin, body, now)
	-- A trickle-exempt word in pieces goes to the other reporters as a whole set (above).
	local set, batches
	if (own or snapshot) and flag ~= "L" then set = CollectSet(origin, body, now) end
	local pieces
	for g, r in pairs(reporters) do
		if now - r.t > Relay.REPORTER_FOR then
			reporters[g] = nil
		elseif scoped and g ~= scoped then
			stats.scoped = (stats.scoped or 0) + 1 -- (another guild's presentation: heard here alone)
		elseif r.name == ns.me then
			if Deliver(origin, body, flag == "L") then ToGuild(flag, origin, body) end
		elseif set == false then
			-- (Some pieces of the set are still on their way: the whole set goes once they are here.)
		elseif set then
			batches = batches or SetBatches(flag, origin, set)
			-- (review prototype) A newer copy replaces a waiting one only where it supersedes it: the
			-- same origin's snapshot of one kind, or its census report. Any other word keeps its own
			-- place (two of the King's T1 words, say, are different words).
			-- (The review of the 1.5.4 candidate.) The relay's own words in pieces are its repeats (the
			-- King's Hands every 300 s, the Treasury's every 300 s, a ranking's repeat): keyed by their
			-- message id, each repeat waited as a new batch behind the rest, the drip grew without end
			-- and the census snapshots waited behind it. Its own word of one kind (as QueueWord keys
			-- the same word in one whisper) takes the waiting copy's place, as a snapshot does.
			local id, head = set[1]:match("^C(%w+):%d+:%d+:(.*)$")
			local kind = head and (head:match("^(%u%w~%d+~S)~") or head:match("^(R[12])~")
				or (own and head:match("^%u%w~") and QueueWord(head)))
			local word = Lower(origin) .. " " .. (kind or ("#" .. tostring(id)))
			for k, batch in ipairs(batches) do DripSet(r.name, word .. " " .. k, batch) end
		else
			pieces = pieces or Envelope("RM", "RM~" .. flag .. "~" .. origin .. "~" .. body)
			-- (1.5.0) Another client's word that is not a chat line: within the reporter's trickle
			-- (REPORTER_RATE) or not sent to him; the relay's own words and chat lines always.
			if flag == "L" or own or snapshot or presence or KingLayer(origin, body, r.name, now) or Afford(r.name, #pieces, now) then
				stats.forwarded = stats.forwarded + 1
				Quiet(r.name) -- (a reporter gone offline since: the server's line out of the chat)
				-- A word that is not a chat line is keyed by its origin, kind and reporter: a newer
				-- census of the same guild takes the waiting one's place in the queue (Comm's keyed
				-- jobs), so a busy relay sends the latest, never a backlog.
				local word = presence and "T1~o" or QueueWord(body)
				local key = flag ~= "L" and ("relay " .. r.name .. " " .. Lower(origin) .. " " .. word) or nil
				if #pieces == 1 then ns.Comm.Whisper(r.name, pieces[1], key, presence, false)
				else ns.Comm.SendBatch("WHISPER", pieces, key, r.name, presence) end
			else
				stats.trickled = (stats.trickled or 0) + 1
			end
		end
	end
	local n = 0
	for _ in pairs(reporters) do n = n + 1 end
	if not Remembered(origin, body) then ns.Log("relay: %s's word (%s) to %d reporters", tostring(sender), body:sub(1, 2), n) end
	Deliver(origin, body, flag == "L")
end

-- (1.4.6) The same word to every other relay that answered us lately (RX), each to hand to its
-- own reporters. The origin, when it is a relay itself, is not sent its own word.
local function Across(flag, origin, body)
	local now = Now()
	local mine, from = ns.ShortName(ns.me or ""):lower(), ns.ShortName(origin):lower()
	-- (1.5.4) The King's presence keyed apart from his crown (both T1): a crown sent after it must not
	-- take its place in the queue, since only the presence passes the other relay's trickle.
	local presence = flag ~= "L" and KingPresence(origin, body)
	local pieces
	for _, name in ipairs(Relay.Names(false)) do
		local key = name:lower()
		if key ~= mine and key ~= from and now - (verified[key] or -math.huge) < Relay.VERIFIED_FOR then
			pieces = pieces or Envelope("RX", "RX~" .. flag .. "~" .. origin .. "~" .. body)
			stats.across = (stats.across or 0) + 1
			Quiet(name)
			local key = flag ~= "L" and ("across " .. name .. " " .. from .. " " .. (presence and "T1~o" or QueueWord(body))) or nil
			if #pieces == 1 then ns.Comm.Whisper(name, pieces[1], key, presence, false)
			else ns.Comm.SendBatch("WHISPER", pieces, key, name, presence) end
		end
	end
end

-- A verifier may be on another relay. Only the small, validated query crosses;
-- it never becomes one whisper per guild and never authorizes a cached decision.
local function VerificationAsk(body)
	if type(body) ~= "string" or #body > 128 then return false end
	return body:match("^GV~1~Q~%d+~%d+~%d+$") ~= nil
		or body:match("^GV~1~Q~%d+~%d+~%d+~%x+$") ~= nil
end

-- (1.5.4) A verifier's approval or revocation, and whether its origin is a verifier as this relay
-- knows them (Verify.Trusted): only such a decision is fanned out and crossed.
local function Decision(body) return type(body) == "string" and body:match("^GV~1~[AR]~") ~= nil end
local function Signed(origin)
	local V = ns.Verify
	return type(V) == "table" and type(V.Trusted) == "function" and V.Trusted(origin) == true
end

-- (1.5.4) Verification to every other relay not left out (RW), answered or not (see the top); the
-- origin, when a relay, is not sent its own word. Never marks a relay as answered. Urgent: a few
-- short whispers, rare (a decision, a relay's half-hourly ask, one client's ask each
-- VERIFY_ASK_EVERY), never evicted behind the reports.
local function ToRelays(flag, origin, body)
	local now = Now()
	local mine, from = ns.ShortName(ns.me or ""):lower(), ns.ShortName(origin):lower()
	local pieces
	for _, name in ipairs(Relay.Names(false)) do
		local key = name:lower()
		if key ~= mine and key ~= from and (offline[key] or 0) <= now then
			pieces = pieces or Envelope("RW", "RW~" .. flag .. "~" .. origin .. "~" .. body)
			stats.verifyAcross = (stats.verifyAcross or 0) + 1
			Quiet(name)
			if #pieces == 1 then ns.Comm.Whisper(name, pieces[1], nil, true, false)
			else ns.Comm.SendBatch("WHISPER", pieces, nil, name, true) end
		end
	end
end

-- (1.5.4) A verifier's answer to the one client that asked, never to every reporter: a whole store
-- (up to MAX_CHUNKS pieces) to each of 30-60 reporters never got through a relay's queue of
-- MAX_QUEUE parts. A relay that asked takes it as RW; any other client as RM from its relay, and
-- hands it to its guild once (HandleRelayed). One urgent transfer. True when queued.
function Relay.Direct(target, body, key)
	if not Relay.On() or not Relay.IsRelay(ns.me) or type(target) ~= "string" or target == "" or type(body) ~= "string" then return false end
	if ns.ShortName(target):lower() == ns.ShortName(ns.me or ""):lower() then return false end
	local kind = Relay.IsRelay(target) and "RW" or "RM"
	local pieces = Envelope(kind, kind .. "~P~" .. ns.me .. "~" .. body)
	if #pieces == 0 or #pieces > ns.Codec.MAX_CHUNKS then return false end
	stats.direct = (stats.direct or 0) + 1
	Quiet(target)
	if #pieces == 1 then return ns.Comm.Whisper(target, pieces[1], key, true, false) ~= false end
	return ns.Comm.SendBatch("WHISPER", pieces, key, target, true) ~= false
end

-- Hop 1 heard (we are a relay): a ping is answered, a registration kept, anything else forwarded
-- to every guild's reporter (ours included: delivered here and handed to our guild).
function Relay.HandleIn(dist, sender, text)
	if dist ~= "WHISPER" or not Relay.On() then return false end
	local flag, body = tostring(text):match("^RL~([LP])~(.*)$")
	if not flag then return false end
	if not Relay.IsRelay(ns.me) then return false end -- (only a relay's client answers hop 1)
	local now = Now()
	if body == "RP~" then
		if ns.FullName(sender) ~= ns.me then ns.Comm.Whisper(sender, "RY~", "relay ack:" .. sender, true) end
		return true
	end
	local guild = body:match("^RR~(.+)$")
	if guild then
		-- (1.5.4, a player's security report of 1.5.3) A registration was taken from any whisperer,
		-- for any number of guilds, of any length: one character could take every guild's feed.
		-- A guild's name as the game allows it (at most MAX_GUILD_NAME, no separator), one guild
		-- per reporter (a new one leaves his old one), and at most MAX_REPORTERS guilds.
		local who, key = ns.FullName(sender), guild:lower()
		if #guild > Relay.MAX_GUILD_NAME or guild:find("[~|%c]") then
			stats.dropped = stats.dropped + 1
			return true
		end
		local count = 0
		for g, r in pairs(reporters) do
			if r.name == who and g ~= key then reporters[g] = nil else count = count + 1 end
		end
		if not reporters[key] and count >= Relay.MAX_REPORTERS then
			stats.dropped = stats.dropped + 1
			return true
		end
		local had = reporters[key]
		reporters[key] = { name = who, t = now, guild = guild }
		stats.registered = stats.registered + 1
		if not had or had.name ~= ns.FullName(sender) then ns.Log("relay: %s's reporter is %s", guild, tostring(sender)) end
		return true
	end
	local origin = ns.FullName(sender)
	local fresh = not Remembered(origin, body, now)
	local localOnly = Relay.NO_FORWARD[body:sub(1, 2)]
	-- Verification queries are periodic background traffic; decisions and recovery snapshots
	-- must reach the guilds. Keeping the entire GV prefix here swallowed a verifier's direct
	-- approvals and revocations on Forever's relay-only route. Verify still checks the original
	-- sender against this origin group's signed authority at the destination.
	if body:match("^GV~1~[ARS]~") then localOnly = false end
	-- (1.5.4) A verifier's decision (as this relay knows them) also goes once to every other relay
	-- (RW), each handing it to its own reporters: no client makes every relay fan out a forged one.
	if fresh and Decision(body) and Signed(origin) then ToRelays(flag, origin, body) end
	if localOnly and (origin ~= ns.me or VerificationAsk(body)) then
		stats.kept = (stats.kept or 0) + 1
		Deliver(origin, body, flag == "L") -- (heard and answered here, fanned out to nobody)
		-- (1.5.4) Our own ask always crosses (our client is its own relay: nobody else hears it);
		-- a client's, one each VERIFY_ASK_EVERY, for a verifier on another relay to answer it.
		if fresh and VerificationAsk(body) and (origin == ns.me or now - lastVerifyAsk >= Relay.VERIFY_ASK_EVERY) then
			if origin ~= ns.me then lastVerifyAsk = now end
			ToRelays("P", origin, body)
		end
		return true
	end
	ToReporters(flag, origin, body, sender)
	-- (1.4.6) To the other relays that answered our pings too (hop 1b, RX): each hands it to its
	-- own reporters. Without this every live relay was an island of the guilds registered with it
	-- (the dev's cousin saw other guilds and other numbers, 2026-11-05). A relay forwards RX no
	-- further, and a word already taken is not sent across again.
	if fresh then Across(flag, origin, body) end
	return true
end

-- (1.4.6) Hop 1b heard (we are a relay): another relay's copy of a word, from a relay alone,
-- handed to our reporters and heard here once; never sent across again.
function Relay.HandleAcross(dist, sender, text)
	if dist ~= "WHISPER" or not Relay.On() then return false end
	local flag, origin, body = tostring(text):match("^RX~([LP])~([^~]+)~(.*)$")
	if not flag then return false end
	if not Relay.IsRelay(sender) or not Relay.IsRelay(ns.me) then stats.dropped = stats.dropped + 1 return false end
	verified[ns.ShortName(sender):lower()] = Now()
	if Remembered(origin, body) then return true end
	if VerificationAsk(body) then Deliver(origin, body, false); return true end
	ToReporters(flag, origin, body, sender)
	return true
end

-- (1.5.4) Verification between relays heard (RW): from a relay alone, to a relay, GV words alone.
-- A verifier's decision goes to our reporters and is heard here; an ask is heard here (our verifier
-- answers whoever asked, Verify.lua); an answer to our own ask is taken here. Never sent across
-- again, never fanned out as a store, and it marks nobody as answered (see the top).
-- (The review of the 1.5.4 candidate.) Each relay that asks is answered on its own gap
-- (Verify.RELAY_ANSWER_GAP), apart from the clients' one ANSWER_GAP. That gap was given to any ask
-- whose origin was a relay's name, and an ask's origin is a payload's word on RG, RM and RX: one
-- guildmate naming each relay in turn got the verifier's whole store sent once per relay, and the
-- real relay's own ask then waited RELAY_ANSWER_GAP. Only an ask that came across here, its relay's
-- name stamped by the server, is a relay's ask now (Relay.AskedAcross, read by Verify.lua).
local acrossFrom -- while an ask that came across is heard here: its relay's short name (lower)
function Relay.AskedAcross(name)
	return acrossFrom ~= nil and type(name) == "string" and Lower(ns.ShortName(name)) == acrossFrom
end
function Relay.HandleVerify(dist, sender, text)
	if dist ~= "WHISPER" or not Relay.On() then return false end
	local flag, origin, body = tostring(text):match("^RW~([LP])~([^~]+)~(.*)$")
	if not flag then return false end
	if not Relay.IsRelay(sender) or not Relay.IsRelay(ns.me) or not body:match("^GV~1~[ARQS]~") then
		stats.dropped = stats.dropped + 1
		return false
	end
	if Remembered(origin, body) then return true end
	if Decision(body) then
		if not Signed(origin) then stats.dropped = stats.dropped + 1 return false end
		ToReporters(flag, origin, body, sender) -- (heard here too)
		return true
	end
	acrossFrom = Lower(ns.ShortName(sender))
	local ok, err = pcall(Deliver, origin, body, false)
	acrossFrom = nil -- (whatever happened: no later ask may pass for this one)
	if not ok then error(err, 0) end
	return true
end

-- Hop 2 heard (we are a reporter): from a relay alone; delivered here and handed to our guild.
function Relay.HandleRelayed(dist, sender, text)
	if dist ~= "WHISPER" or not Relay.On() then return false end
	local flag, origin, body = tostring(text):match("^RM~([LP])~([^~]+)~(.*)$")
	if not flag then return false end
	if not Relay.IsRelay(sender) then stats.dropped = stats.dropped + 1 return false end
	verified[ns.ShortName(sender):lower()] = Now()
	if not Remembered(origin, body) then ns.Log("relay: %s's word (%s) by %s", tostring(origin), body:sub(1, 2), tostring(sender)) end
	if Deliver(origin, body, flag == "L") then ToGuild(flag, origin, body) end
	return true
end

-- Hop 3 heard (a guildmate's hand-over): delivered here once.
function Relay.HandleGuild(dist, sender, text)
	if dist ~= "GUILD" or not Relay.On() then return false end
	local flag, origin, body = tostring(text):match("^RG~([LP])~([^~]+)~(.*)$")
	if not flag then return false end
	Deliver(origin, body, flag == "L")
	return true
end

-- The relay's answer to our ping.
function Relay.HandleAck(dist, sender, text)
	if dist ~= "WHISPER" or tostring(text) ~= "RY~" then return false end
	local key = ns.ShortName(sender):lower()
	if not verified[key] then ns.Log("relay: %s answers", tostring(sender)) end
	verified[key] = Now()
	pinged[key] = nil
	offline[key] = nil
	Flush() -- (1.4.4) what waited for an answer goes out now
	return true
end

-- The server's "No player named X is currently playing": a relay named is offline now.
function Relay.NotFound(text)
	local T = ns.Treasury
	local pattern = type(T) == "table" and type(T.NotFoundPattern) == "function" and T.NotFoundPattern()
	local who = type(pattern) == "string" and type(text) == "string" and text:match(pattern)
	if type(who) ~= "string" then return false end
	who = who:gsub("^'", ""):gsub("'$", "")
	if not Relay.IsRelay(who) then return false end
	LeaveOut(who, "offline")
	return true
end

ns.Comm.Handle("RL", function(...) Relay.HandleIn(...) end)
ns.Comm.Handle("RM", function(...) Relay.HandleRelayed(...) end)
ns.Comm.Handle("RG", function(...) Relay.HandleGuild(...) end)
ns.Comm.Handle("RY", function(...) Relay.HandleAck(...) end)
ns.Comm.Handle("RX", function(...) Relay.HandleAcross(...) end)
ns.Comm.Handle("RW", function(...) Relay.HandleVerify(...) end)
ns.Comm.RelayPieces({ RL = true, RM = true, RG = true, RX = true, RW = true })

-- (1.4.6, the dev's ask) The server's "No player named X is currently playing" for a relay or a
-- reporter the relay whispered: out of the chat for good, not for a window (Accord.Quiet's ten
-- seconds left the login's first sweep in sight). Read all the same (NotFound, the event).
local function NotFoundName(text)
	local T = ns.Treasury
	local pattern = type(T) == "table" and type(T.NotFoundPattern) == "function" and T.NotFoundPattern()
	local who = type(pattern) == "string" and type(text) == "string" and text:match(pattern)
	if type(who) ~= "string" then return nil end
	return (who:gsub("^'", ""):gsub("'$", ""))
end
function Relay.QuietLine(_, _, text) -- gp:system-filters
	if not ns.Gate.Allowed("system-filters") or not Relay.On() then return false end
	local who = NotFoundName(text)
	if not who then return false end
	if Relay.IsRelay(who) then return true end
	local key = ns.ShortName(who):lower()
	for _, r in pairs(reporters) do
		if ns.ShortName(r.name or ""):lower() == key then return true end
	end
	return false
end
local filtering
local function QuietLines() -- gp:system-filters!hook
	if filtering or not ns.Gate.Allowed("system-filters") then return end
	local add = rawget(_G, "ChatFrame_AddMessageEventFilter") -- gp:system-filters
	if type(add) ~= "function" then
		local U = rawget(_G, "ChatFrameUtil") -- gp:system-filters
		add = type(U) == "table" and rawget(U, "AddMessageEventFilter") or nil -- gp:system-filters
	end
	if type(add) ~= "function" then return end
	filtering = true
	pcall(add, "CHAT_MSG_SYSTEM", Relay.QuietLine) -- gp:system-filters
end
Relay.QuietLines = QuietLines

-- (1.5.0) A relay's own global census snapshot to its reporters every GLOBAL_EVERY (it hears every
-- guild's report; Data.SendGlobalCensus sends it "on the channel", so by this relay to every
-- reporter, keyed: the latest alone waits in the queue).
local lastGlobal = -math.huge
function Relay.SendGlobal(force)
	if not Relay.On() or not Relay.IsRelay(ns.me) then return false end
	local now = Now()
	if not force and now - lastGlobal < Relay.GLOBAL_EVERY then return false end
	local D = ns.Data
	if type(D) ~= "table" or type(D.SendGlobalCensus) ~= "function" then return false end
	lastGlobal = now
	return D.SendGlobalCensus() == true
end

ns.On("LOGIN", function()
	if not Relay.On() then return end
	pcall(ns.RegisterEvent, "CHAT_MSG_SYSTEM", function(text) ns.SafeCall("relay not found", Relay.NotFound, text) end)
	QuietLines()
	if ns.Every then ns.Every(Relay.GLOBAL_EVERY, "relay global census", function() ns.SafeCall("relay global", Relay.SendGlobal) end) end
end)

-- Tests: a clean slate.
function Relay.Reset()
	wipe(offline); wipe(verified); wipe(pinged); wipe(reporters); wipe(seen); wipe(pending); wipe(budget)
	seenCount, lastRegister, holding, flushing, lastGlobal = 0, -math.huge, false, false, -math.huge
	lastVerifyAsk = -math.huge
	wipe(snapshotTransfers); wipe(crownSent); wipe(kingSent); wipe(crownLayer); wipe(grantSent)
	crownBucket.tokens, crownBucket.at = 0, -math.huge
	wipe(sets); wipe(drip)
	dripSince, dripping = nil, false
	for k in pairs(stats) do stats[k] = 0 end
end
