local _, ns = ...
local L = ns.L
L.PLAYER_TOOLTIP_SETTINGS = "Player tooltips"
L.PLAYER_TOOLTIP_DESC = "Keep the game's tooltip and add Olympus guild ranks in a compact, readable line."
L.PLAYER_TOOLTIP_DETAILS = "Show Olympus player details"
L.PLAYER_TOOLTIP_COLORS = "Use class colors for guild ranks"
L.PLAYER_TOOLTIP_SIZE = "Tooltip size: %d%%"
L.PLAYER_TOOLTIP_NEXT = "Changes apply on the next hover. These additions pause with gamepad UI or in combat."
-- (1.5.5) The switch for Olympus's lines in the game's right-click menus (PlayerMenu.lua), in this panel.
L.PLAYERMENU_SETTING = "Right-click menus"
L.PLAYERMENU_SETTING_LABEL = "Olympus lines in the game's right-click menus"
L.PLAYERMENU_SETTING_NOTE = "Takes effect at once. Turned off, Olympus also stops joining those menus after a /reload. /oly menus on|off does the same."
L.PLAYERMENU_ON = "Olympus lines in the game's right-click menus: on, at once. /oly menus off removes them."
L.PLAYERMENU_OFF = "Olympus lines in the game's right-click menus: off, at once. After a /reload Olympus no longer joins those menus at all. /oly menus on brings them back."
L.HELP_MENUS = "  /oly menus on | off - Olympus's lines in the game's right-click menus for a player (version, profile, report...); takes effect at once"
if GetLocale() == "ptBR" then
	L.PLAYER_TOOLTIP_SETTINGS = "Dicas de jogadores"
	L.PLAYER_TOOLTIP_DESC = "Mantenha a dica do jogo e acrescente o posto na guilda Olympus em uma linha compacta."
	L.PLAYER_TOOLTIP_DETAILS = "Mostrar detalhes dos jogadores Olympus"
	L.PLAYER_TOOLTIP_COLORS = "Usar cores de classe nos postos da guilda"
	L.PLAYER_TOOLTIP_SIZE = "Tamanho da dica: %d%%"
	L.PLAYER_TOOLTIP_NEXT = "As mudanças valem ao passar o mouse novamente. Estes detalhes ficam pausados com controle ou em combate."
	L.PLAYERMENU_SETTING = "Menus do clique direito"
	L.PLAYERMENU_SETTING_LABEL = "Linhas do Olympus nos menus do clique direito do jogo"
	L.PLAYERMENU_SETTING_NOTE = "Vale na hora. Desligado, depois de um /reload o Olympus também deixa de entrar nesses menus. /oly menus on|off faz o mesmo."
	L.PLAYERMENU_ON = "Linhas do Olympus nos menus do clique direito do jogo: ligadas, na hora. /oly menus off tira elas."
	L.PLAYERMENU_OFF = "Linhas do Olympus nos menus do clique direito do jogo: desligadas, na hora. Depois de um /reload o Olympus nem entra mais nesses menus. /oly menus on traz elas de volta."
	L.HELP_MENUS = "  /oly menus on | off - as linhas do Olympus nos menus do clique direito do jogo para um jogador (versão, perfil, denúncia...); vale na hora"
end
