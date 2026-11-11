local ns, test, eq = ...

test("1.2.4 profile menu: own name offers View profile and collapse; others open the main person page", function()
	local P = ns.PlayerMenu
	local old = { member = ns.IsMember, me = ns.me, ui = ns.UI, edit = ns.ProfileEdit, profile = ns.PlayerProfile, pad = ns.GamepadUI }
	local own, other = 0, nil
	local ok, err = pcall(function()
		ns.IsMember, ns.GamepadUI = function() return true end, function() return false end
		ns.me = "Tester-Realm"
		ns.UI = { OpenPlayerProfile = function() end }
		ns.ProfileEdit = { Open = function() own = own + 1; return true end }
		ns.PlayerProfile = { OpenName = function(name) other = name; return true end }
		local root = { buttons = {} }
		function root:CreateDivider() end
		function root:CreateTitle() end
		function root:CreateButton(text, click) self.buttons[#self.buttons + 1] = { text = text, click = click }; return {} end
		eq(P.Target("FRIEND", { name = ns.me }), nil, "legacy callers still exclude self")
		eq(P.Target("FRIEND", { name = "Other-Realm", isSelf = true }, true), nil, "self flag cannot authorize another character")
		eq(P.Build("FRIEND", root, { name = "Other-Realm", isSelf = true }), 0)
		eq(#root.buttons, 0, "inconsistent native self context adds no buttons")
		eq(P.Build("FRIEND", root, { name = ns.me, isSelf = true }), 1)
		eq(#root.buttons, 2, "profile and collapse only: no self challenge, version request or portrait settings")
		eq(root.buttons[1].text, ns.L.ARENA_MENU_PROFILE)
		eq(root.buttons[2].text, ns.L.PLAYERMENU_COLLAPSE)
		root.buttons[1].click(); eq(own, 1); eq(other, nil)
		eq(P.OpenProfile("Other-Realm"), true); eq(other, "Other-Realm")
		ns.GamepadUI = function() return true end
		eq(P.Build("FRIEND", root, { name = ns.me, isSelf = true }), 0, "no native menu integration with gamepad")
		eq(#root.buttons, 2)
		ns.IsMember = function() return false end
		eq(P.OpenProfile("Other-Realm"), false)
	end)
	ns.IsMember, ns.me, ns.UI, ns.ProfileEdit, ns.PlayerProfile, ns.GamepadUI = old.member, old.me, old.ui, old.edit, old.profile, old.pad
	if not ok then error(err, 0) end
end)

-- 1.5.5 (a contributor's ask): /oly menus on|off and the panel's switch for Olympus's lines in the
-- game's right-click menus. On unless turned off; off takes effect at once (the next menu opened gets
-- nothing of Olympus's) and, from a login with it off, Olympus gives the game's menus no callback at
-- all; back on, the lines come at once, the menus joined then. The Olympus window's own row menus stay.
test("1.5.5 player menus switch: /oly menus off removes Olympus's lines at once, a login with it off joins no menu, on brings them back", function()
	local P = ns.PlayerMenu
	local L = ns.L
	local old = { member = ns.IsMember, me = ns.me, ui = ns.UI, pad = ns.GamepadUI, menu = Menu, print = ns.Print,
		setting = ns.db.playerMenus, collapsed = ns.db.playerMenuCollapsed }
	local ok, err = pcall(function()
		ns.IsMember, ns.GamepadUI = function() return true end, function() return false end
		ns.me = "Tester-Realm"
		ns.UI = { OpenPlayerProfile = function() end }
		ns.db.playerMenuCollapsed = nil
		local printed = {}
		ns.Print = function(m) printed[#printed + 1] = m end
		local registered = {}
		Menu = { ModifyMenu = function(tag, cb) registered[#registered + 1] = { tag = tag, cb = cb } end }
		local function Root()
			local root = { buttons = 0, titles = 0 }
			function root:CreateDivider() end
			function root:CreateTitle() self.titles = self.titles + 1 end
			function root:CreateButton() self.buttons = self.buttons + 1; return {} end
			return root
		end
		local function Lines(which, ctx)
			local root = Root()
			P.Build(which, root, ctx)
			return root.buttons + root.titles
		end
		-- On (nothing saved): as before.
		ns.db.playerMenus = nil
		eq(P.Enabled(), true, "on unless turned off")
		assert(Lines("SELF", { name = ns.me, isSelf = true }) > 0, "the own portrait's lines")
		-- Off: at once, every game menu; the Olympus window's own rows keep theirs.
		P.Slash("off")
		eq(ns.db.playerMenus, false); eq(printed[#printed], L.PLAYERMENU_OFF)
		eq(Lines("SELF", { name = ns.me, isSelf = true }), 0, "nothing in the game's menu at once")
		eq(Lines("FRIEND", { name = "Other-Realm" }), 0)
		assert(Lines(P.ROW, { name = "Other-Realm" }) > 0, "Olympus's own row menu stays")
		assert(P.StatusLine():find("off (/oly menus on)", 1, true), P.StatusLine())
		-- A login with it off: no callback given to the game's menus.
		P.Reset()
		eq(P.Hook(), false); eq(#registered, 0, "no menu joined")
		-- On again: joined at once, the lines back.
		P.Slash("on")
		eq(ns.db.playerMenus, true); eq(printed[#printed], L.PLAYERMENU_ON)
		eq(P.Hooked(), true); assert(#registered >= #P.WHICH - 1, "every menu joined then")
		assert(Lines("SELF", { name = ns.me, isSelf = true }) > 0, "the lines at once")
		-- Alone: whether they show (and the panel, where there is one).
		local n = #printed
		P.Slash("")
		eq(printed[n + 1], L.PLAYERMENU_ON)
		-- With the gamepad UI, turning it on joins no menu (the switch back to mouse and keyboard does).
		P.Reset(); registered = {}
		ns.db.playerMenus = false
		ns.GamepadUI = function() return true end
		P.SetEnabled(true, true)
		eq(#registered, 0, "no callback with the gamepad UI")
		-- What a backup keeps of it.
		eq(ns.Backup.SETTINGS.playerMenus, "boolean")
	end)
	ns.IsMember, ns.me, ns.UI, ns.GamepadUI, Menu, ns.Print = old.member, old.me, old.ui, old.pad, old.menu, old.print
	ns.db.playerMenus, ns.db.playerMenuCollapsed = old.setting, old.collapsed
	P.Reset()
	if not ok then error(err, 0) end
end)
