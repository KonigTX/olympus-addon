-- Codec.Gc's window is meant to drop assemblies whose sender stopped, not ones still arriving.
-- A report paced behind a busy queue (Comm's SEND_INTERVAL, one message a tick) can take longer
-- than the window from its first piece to its last; before the sliding window below, every such
-- report was discarded and the census never heard that guild (issue #79).
local ns, test, eq = ...
local Codec = ns.Codec

test("a steadily arriving report is not dropped", function()
	local asm = Codec.NewAssembler()
	local payload = string.rep("x", Codec.CHUNK * 4 + 10)
	local parts = Codec.Chunk(payload, "1")
	eq(#parts, 5)
	local now, done = 0, nil
	for i = 1, #parts do
		done = Codec.Feed(asm, "Someone-OtherRealm", parts[i], now) or done
		now = now + 25
		eq(Codec.Gc(asm, now), 0)
	end
	eq(done, payload)
end)

test("a stalled report is still dropped", function()
	local asm = Codec.NewAssembler()
	local parts = Codec.Chunk(string.rep("y", Codec.CHUNK * 2), "2")
	Codec.Feed(asm, "Quiet-OtherRealm", parts[1], 0)
	eq(Codec.Gc(asm, 30), 0)
	local dropped, sample = Codec.Gc(asm, 61)
	eq(dropped, 1)
	eq(type(sample), "string")
end)

-- (1.5.4 review: pieces 50 s apart keep the sliding window alive, so only the cap can drop it.)
test("a drip-fed report expires at ASM_MAX_AGE", function()
	local asm = Codec.NewAssembler()
	local parts = Codec.Chunk(string.rep("z", Codec.CHUNK * 9 + 1), "3")
	eq(#parts, 10)
	for i = 1, 7 do
		local at = (i - 1) * 50
		Codec.Feed(asm, "Slow-OtherRealm", parts[i], at)
		if i < 7 then eq(Codec.Gc(asm, at + 1), 0, "still arriving at " .. at .. " s") end
	end
	eq(Codec.Gc(asm, Codec.ASM_MAX_AGE + 1), 1, "open past ASM_MAX_AGE since its first piece")
end)

-- (1.5.4 review: Room still closes the stranger's message opened first, as 1.2.1 says.)
test("a stranger's message opened first is the one closed for room, however recently it grew", function()
	local asm = Codec.NewAssembler()
	local function Piece(fill, id, i) return Codec.Chunk(string.rep(fill, Codec.CHUNK * 3), id)[i] end
	local saved = Codec.OPEN_MAX
	Codec.OPEN_MAX = 2
	local ok, err = pcall(function()
		Codec.Feed(asm, "Stranger-OtherRealm", Piece("a", "4", 1), 0)
		Codec.Feed(asm, "Stranger-OtherRealm", Piece("b", "5", 1), 10)
		Codec.Feed(asm, "Stranger-OtherRealm", Piece("a", "4", 2), 20) -- the first one grew last
		Codec.Feed(asm, "Another-OtherRealm", Piece("c", "6", 1), 30) -- the buffer is full: room is made
	end)
	Codec.OPEN_MAX = saved
	if not ok then error(err, 0) end
	local left = {}
	for key in pairs(asm.buf) do left[#left + 1] = key end
	table.sort(left)
	local all = table.concat(left, ",")
	eq(all:find("#4", 1, true), nil, "the message opened first went, though it grew last: " .. all)
	eq(all:find("#5", 1, true) ~= nil, true, "the later one stays: " .. all)
end)
