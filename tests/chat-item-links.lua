local ns, test, eq, X = ...
local Codec = ns.Codec
local WithWindow, WithGamepadUI, RelayWorld = X.WithWindow, X.WithGamepadUI, X.RelayWorld
local Line, BubbleWith, T0, KeepSendGap = X.Line, X.BubbleWith, X.T0, X.KeepSendGap

-- 1.5.4 (the dev, 2026-11-08: "os itens aparecerem corretamente, porque tá aparecendo quebrado...
-- no chat da nossa janela. Não tá aparecendo certinho com o texto em highlight, clicável, com hover
-- que aparece os detalhes do item"; Fernmelder saw the same). On Forever a chat line travels
-- inside the relay's envelopes (RL, RM, RG: Relay.lua), which Comm strips of every "|" before
-- anything reads them (Codec.Plain, 0.9.2: only a bare M1 line kept its links), so a link arrived
-- as "cff1eff00Hitem:14342...h[Mooncloth]hr". The links a line may carry now travel as tokens
-- with no "|" (Codec.PackLinks, in EncodeChat) and are links again at the receiver
-- (Codec.UnpackLinks, in DecodeChat); the Chat tab shows an item with the name and colour this
-- client's item data gives it, and a left click on a link opens the game's link window as a click
-- in the game's chat does (SetItemRef), never with the gamepad UI. Invented names throughout.
local GUILD = "Olympus II"
local LINK = "item:14342::::::::60:::::"
local ITEM = "|cff1eff00|H" .. LINK .. "|h[Mooncloth]|h|r"
local SPELL = "|cff71d5ff|Hspell:8690|h[Hearthstone]|h|r"
local ENCHANT = "|cffffd000|Henchant:7420|h[Enchant Chest - Minor Health]|h|r"
local QUEST = "|cffffff00|Hquest:1234:60|h[The Defias Brotherhood]|h|r"
local BARE = "|Hitem:19019::::::::60:::::::::|h[Thunderfury]|h"
local NAMED = "|cnIQ4:|Hitem:19019::::::::60:::::::::|h[Thunderfury]|h|r"

local function Links(text)
	local out = {}
	for kind in text:gmatch("|H(%a+):") do out[#out + 1] = kind end
	return table.concat(out, ",")
end

test("1.5.4 chat links on the wire: a line's links leave as tokens without a pipe, so Codec.Plain leaves them whole, and come back as the same links", function()
	for _, link in ipairs({ ITEM, SPELL, ENCHANT, QUEST, BARE, NAMED }) do
		local text = "look " .. link .. " cheap, ~2g: a=b"
		eq(Codec.SanitizeChat(text), text, "a link a line may carry")
		local msg = Codec.EncodeChat("A", GUILD, 7, "WA", text)
		assert(msg, "encoded")
		assert(not msg:find("|", 1, true), "no pipe on the wire: " .. msg)
		eq(Codec.Plain(msg), msg, "the relay's envelopes lose nothing of it")
		local d = Codec.DecodeChat(msg)
		eq(d.text, text, "the same link at the receiver")
		eq(d.tier, "A"); eq(d.guild, GUILD); eq(d.id, 7); eq(d.class, "WA")
		assert(#Codec.PackLinks(link) < #link, "a token is never longer than its link: " .. Codec.PackLinks(link))
		-- The token is text to a client before 1.5.4: the name first, readable.
		assert(Codec.PackLinks(link):find("^%[[^%]]+%]%(") , "the name first: " .. Codec.PackLinks(link))
	end
	-- Pack and unpack are each other's inverse and idempotent; a "||" typed stays one.
	local text = "a||b " .. ITEM .. " " .. SPELL .. " c"
	local packed = Codec.PackLinks(text)
	eq(Codec.PackLinks(packed), packed, "pack twice")
	eq(Codec.UnpackLinks(packed), text, "unpack")
	eq(Codec.UnpackLinks(text), text, "unpack of links: as they are")
	eq(Codec.UnpackLinks(Codec.UnpackLinks(packed)), text, "unpack twice")
	-- A long line of links: each part fits one message and decodes to itself.
	local long = Codec.SanitizeChat((ITEM .. " "):rep(4) .. ("word "):rep(30) .. SPELL .. " " .. QUEST)
	local parts, cut = Codec.SplitChat(long, Codec.ChatBudget(GUILD, "WA"), Codec.CHAT_PARTS)
	eq(cut, false); assert(#parts >= 2, "split")
	for _, p in ipairs(parts) do
		local m = Codec.EncodeChat("C", GUILD, 9999, "WA", p)
		assert(m and #m <= 255, "fits")
		eq(Codec.DecodeChat(m).text, p, "a part with its links")
	end
	-- A line without a link: the wire is the text itself, as before.
	eq(Codec.EncodeChat("A", GUILD, 1, "", "hello there"), "M1~A~Olympus II~1~~hello there")
end)

test("1.5.4 chat link tokens: only item, spell, enchant and quest links with sound data become links again; anything else typed, and every escape code, stays text", function()
	local function Shown(text) return Codec.DecodeChat(Codec.EncodeChat("A", GUILD, 1, "", text)).text end
	for _, typed in ipairs({
		"[Someone](player:Someone/ff00ff00)",             -- a player link would open the game's chat box
		"[click](url:evil/ff00ff00)",                      -- a foreign link type
		"[Mooncloth](item:abc/ff1eff00)",                   -- letters in the data
		"[Mooncloth](item:/ff1eff00)",                      -- no id
		"[Mooncloth](item:0/ff1eff00)",                     -- a zero id
		"[Mooncloth](item:14342/zz1eff00)",                 -- a colour that is none
		"[Mooncloth](item:14342/ff1eff00ff)",               -- a colour too long
		"[](item:14342/ff1eff00)",                          -- no name
		"[" .. ("x"):rep(101) .. "](item:14342/ff1eff00)",  -- a name past 100 bytes
		"[Mooncloth](item:" .. ("1:"):rep(33) .. "1/)",     -- 34 fields
		"[Mooncloth](item:" .. ("9"):rep(121) .. "/)",      -- data past 120 bytes
		"[Mooncloth](achievement:1/ff1eff00)",              -- not one of the four
	}) do
		local shown = Shown(typed)
		eq(Links(shown), "", "no link from: " .. typed)
		assert(not shown:find("|", 1, true), "no escape from: " .. typed .. " -> " .. shown)
	end
	-- A pipe or a texture inside a token's name: the name may not hold one, and the pipe shows escaped.
	local piped = Shown("[Moon|cffff0000cloth](item:14342/ff1eff00)")
	eq(Links(piped), ""); eq(piped, "[Moon||cffff0000cloth](item:14342/ff1eff00)")
	eq(Links(Shown("[|TInterface\\Icons\\x:16|t](item:14342/ff1eff00)")), "")
	-- Escape codes typed raw are neutralised as ever (SanitizeChat), beside a real link.
	eq(Shown("|cffff0000red|r " .. ITEM .. " |TInterface\\Icons\\x:16|t |Hplayer:Someone|h[Someone]|h"),
		"||cffff0000red||r " .. ITEM .. " ||TInterface\\Icons\\x:16||t ||Hplayer:Someone||h[Someone]||h")
	-- A sound token typed by hand is a link, as a raw link typed into an addon message was: the
	-- four kinds, with or without a colour, a Mainline colour name too.
	eq(Shown("[Mooncloth](item:14342::::::::60:::::/ff1eff00)"), ITEM)
	eq(Shown("[Thunderfury](item:19019::::::::60:::::::::/)"), BARE)
	eq(Shown("[Thunderfury](item:19019::::::::60:::::::::/nIQ4:)"), NAMED)
	eq(Links(Shown("[a](spell:1/) [b](enchant:2/) [c](quest:3:60/)")), "spell,enchant,quest")
	-- What comes out is what SanitizeChat lets through, and nothing more.
	for _, typed in ipairs({ "[x](item:1/)", "[Someone](player:Someone/)", "a [b](c) d", "[](x)" }) do
		local shown = Shown(typed)
		eq(Codec.SanitizeChat(shown), shown, "clean: " .. typed)
	end
end)

test("1.5.4 chat links by the relay: a line's link reaches a guildmate whole through the relay's hop to the guild (RG), the relay's hop to the reporters (RM), and the channel's own text, each the same text", function()
	local saved = { channel = GetChannelName, member = ns.IsMember, guild = GetGuildInfo, inGuild = IsInGuild }
	local ok, err = pcall(function()
		GetChannelName = function() return 0 end
		ns.IsMember = function() return true end
		IsInGuild = function() return true end
		GetGuildInfo = function() return GUILD, "Member", 3 end
		local R, Deliver, _, heard, Pump, Sent = RelayWorld("Hildryn Payne-Realm", GUILD)
		local text = "look " .. ITEM .. " cheap"
		local msg = R.Codec.EncodeChat("A", GUILD, 7, "WA", text)
		-- Hop 3: a reporter's hand-over to the guild, as every guildmate hears a line on Forever.
		Deliver("GUILD", "Guild Rep-Realm", "RG~L~Orig Inal-Realm~" .. msg)
		eq(#heard, 1, "the line heard"); eq(heard[1].sender, "Orig Inal-Realm")
		local got = R.Codec.DecodeChat(heard[1].text)
		assert(got, "a chat line: " .. tostring(heard[1].text))
		eq(got.text, text, "the link whole, by the guild")
		-- The channel's own text (ChatHall.OnChannel hands it to Comm.Inject): the same text.
		R.Comm.Inject("CHANNEL", "Orig Inal-Realm", msg, true)
		eq(#heard, 2); eq(heard[2].text, heard[1].text, "one text on both ways: each client takes the line once")
		-- Hop 1 at a relay's client: a reporter registered, the line forwarded to him with its link.
		Deliver("WHISPER", "Zed Far-Realm", "RL~P~RR~Olympus Zeus")
		Deliver("WHISPER", "Orig Inal-Realm", "RL~L~" .. msg)
		Pump()
		local rm = Sent("RM~L~")
		eq(#rm, 1, "forwarded once")
		local body = rm[1].msg:match("^RM~L~[^~]+~(.*)$")
		eq(R.Codec.DecodeChat(body).text, text, "the link whole, to the reporter")
	end)
	GetChannelName, ns.IsMember, GetGuildInfo, IsInGuild = saved.channel, saved.member, saved.guild, saved.inGuild
	C_ChatInfo = nil
	if not ok then error(err, 0) end
end)

test("1.5.4 chat links at the sender: a line with a link leaves without a pipe, the sender's own line and echo are the link, and the history (what moderation reads) holds the link", function()
	local C = ns.Channels
	local saved = { me = ns.me, split = ns.splitNames, ready = ns.Comm.ChannelReady, room = ns.Comm.ChatRoom, send = ns.Comm.SendChat,
		guild = GetGuildInfo, realm = ns.realm }
	local ok, err = pcall(KeepSendGap, function()
		ns.me, ns.splitNames, ns.realm = "Tester Surname-Realm", true, "Realm"
		GetGuildInfo = function() return GUILD, "Member", 3 end
		ns.Comm.ChannelReady = function() return true end
		ns.Comm.ChatRoom = function() return 3 end
		local sent
		ns.Comm.SendChat = function(msg, done) sent = msg; done(true); return true end
		local t = 2000000
		local text = "wts " .. ITEM .. " 5g"
		assert(C.Send("A", text, t))
		assert(sent, "sent")
		assert(not sent:find("|", 1, true), "no pipe on the wire: " .. sent)
		eq(Codec.DecodeChat(sent).text, text, "the others read the link")
		local list = C.History("A")
		eq(list[#list].text, text, "our own line kept as the link")
		eq(list[#list].mine, true)
		-- Our own echo, however the server writes our name: ours, not shown again.
		local shown, why = C.Receive("CHANNEL", "Tester-Surname", sent, t + 1)
		eq(shown, false); eq(why, "own")
		-- A token typed by hand goes out as the link it names, so what we keep is what the others see.
		sent = nil
		assert(C.Send("A", "see [Hearthstone](spell:8690/ff71d5ff) now", t + 10))
		eq(Codec.DecodeChat(sent).text, "see " .. SPELL .. " now")
		list = C.History("A")
		eq(list[#list].text, "see " .. SPELL .. " now")
	end)
	ns.me, ns.splitNames, ns.Comm.ChannelReady, ns.Comm.ChatRoom, ns.Comm.SendChat = saved.me, saved.split, saved.ready, saved.room, saved.send
	GetGuildInfo, ns.realm = saved.guild, saved.realm
	if not ok then error(err, 0) end
end)

