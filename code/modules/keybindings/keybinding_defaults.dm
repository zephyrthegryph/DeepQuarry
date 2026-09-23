// Default keybindings. Together these reproduce the two macro sets that used to
// be hard-coded in interface/skin.dmf: "hotkeymode" (KEYBIND_PROFILE_DEFAULT) and
// "borghotkeymode" (KEYBIND_PROFILE_ROBOT). The non-hotkey "macro" and
// "borgmacro" sets were unreachable (hotkey mode is forced on) and are gone.
// dq_keybinding_defaults_match_old_skin pins every default to the old skin.

#define KB_BOTH(keys...) list(KEYBIND_PROFILE_DEFAULT = list(##keys), KEYBIND_PROFILE_ROBOT = list(##keys))
#define KB_HUMAN(keys...) list(KEYBIND_PROFILE_DEFAULT = list(##keys))
#define KB_ROBOT(keys...) list(KEYBIND_PROFILE_ROBOT = list(##keys))

/// One row per binding: id, name, category, command, release command, default keys.
/proc/keybinding_definitions()
	. = list(
		// Movement
		list("move_north", "Move north", KEYBIND_CAT_MOVEMENT, "KeyDown North", "KeyUp North", KB_BOTH("North")),
		list("move_south", "Move south", KEYBIND_CAT_MOVEMENT, "KeyDown South", "KeyUp South", KB_BOTH("South")),
		list("move_east", "Move east", KEYBIND_CAT_MOVEMENT, "KeyDown East", "KeyUp East", KB_BOTH("East")),
		list("move_west", "Move west", KEYBIND_CAT_MOVEMENT, "KeyDown West", "KeyUp West", KB_BOTH("West")),
		list("move_w", "Move up (WASD)", KEYBIND_CAT_MOVEMENT, "KeyDown W", "KeyUp W", KB_BOTH("W")),
		list("move_a", "Move left (WASD)", KEYBIND_CAT_MOVEMENT, "KeyDown A", "KeyUp A", KB_BOTH("A")),
		list("move_s", "Move down (WASD)", KEYBIND_CAT_MOVEMENT, "KeyDown S", "KeyUp S", KB_BOTH("S")),
		list("move_d", "Move right (WASD)", KEYBIND_CAT_MOVEMENT, "KeyDown D", "KeyUp D", KB_BOTH("D")),
		list("face_north", "Face north", KEYBIND_CAT_MOVEMENT, "northface", null, KB_BOTH("CTRL+NORTH")),
		list("face_south", "Face south", KEYBIND_CAT_MOVEMENT, "southface", null, KB_BOTH("CTRL+SOUTH")),
		list("face_east", "Face east", KEYBIND_CAT_MOVEMENT, "eastface", null, KB_BOTH("CTRL+EAST")),
		list("face_west", "Face west", KEYBIND_CAT_MOVEMENT, "westface", null, KB_BOTH("CTRL+WEST")),
		list("face_north_hold", "Keep facing north", KEYBIND_CAT_MOVEMENT, "northfaceperm", null, KB_BOTH("ALT+NORTH")),
		list("face_south_hold", "Keep facing south", KEYBIND_CAT_MOVEMENT, "southfaceperm", null, KB_BOTH("ALT+SOUTH")),
		list("face_east_hold", "Keep facing east", KEYBIND_CAT_MOVEMENT, "eastfaceperm", null, KB_BOTH("ALT+EAST")),
		list("face_west_hold", "Keep facing west", KEYBIND_CAT_MOVEMENT, "westfaceperm", null, KB_BOTH("ALT+WEST")),
		list("shift_north", "Shift north", KEYBIND_CAT_MOVEMENT, "shiftnorth", null, KB_BOTH("CTRL+SHIFT+NORTH")),
		list("shift_south", "Shift south", KEYBIND_CAT_MOVEMENT, "shiftsouth", null, KB_BOTH("CTRL+SHIFT+SOUTH")),
		list("shift_east", "Shift east", KEYBIND_CAT_MOVEMENT, "shifteast", null, KB_BOTH("CTRL+SHIFT+EAST")),
		list("shift_west", "Shift west", KEYBIND_CAT_MOVEMENT, "shiftwest", null, KB_BOTH("CTRL+SHIFT+WEST")),
		list("mod_shift", "Shift (held)", KEYBIND_CAT_MOVEMENT, "KeyDown Shift", "KeyUp Shift", KB_BOTH("Shift")),
		list("mod_ctrl", "Ctrl (held)", KEYBIND_CAT_MOVEMENT, "KeyDown Ctrl", "KeyUp Ctrl", KB_BOTH("Ctrl")),
		list("mod_alt", "Alt (held)", KEYBIND_CAT_MOVEMENT, "KeyDown Alt", "KeyUp Alt", KB_BOTH("Alt")),

		// Mob actions
		list("swap_hands", "Swap hands", KEYBIND_CAT_MOB, ".northeast", null, KB_BOTH("NORTHEAST", "X", "CTRL+X")),
		list("throw_mode", "Toggle throw mode", KEYBIND_CAT_MOB, ".southwest", null, KB_BOTH("SOUTHWEST", "R", "CTRL+R")),
		list("drop", "Drop held item", KEYBIND_CAT_MOB, ".northwest", null, list(KEYBIND_PROFILE_DEFAULT = list("NORTHWEST", "Q", "CTRL+Q"), KEYBIND_PROFILE_ROBOT = list("NORTHWEST"))),
		list("self_use_diagonal", "Use held item (Page Down)", KEYBIND_CAT_MOB, ".southeast", null, KB_BOTH("SOUTHEAST")),
		list("self_use", "Use held item", KEYBIND_CAT_MOB, "Activate-Held-Object", null, list(KEYBIND_PROFILE_DEFAULT = list("Z", "CTRL+Z"), KEYBIND_PROFILE_ROBOT = list("Z"))),
		list("robot_self_use", "Use held module (multibelt aware)", KEYBIND_CAT_ROBOT, "Robot-Activate-Held-Object", null, KB_ROBOT("CTRL+Z")),
		list("stop_pulling", "Stop pulling", KEYBIND_CAT_MOB, "delete-key-pressed", null, KB_BOTH("DELETE")),
		list("rest", "Rest", KEYBIND_CAT_MOB, "Rest", null, KB_BOTH("U")),
		list("rest_left", "Rest (lie left)", KEYBIND_CAT_MOB, "Rest-Left", null, KB_HUMAN("SHIFT+U")),
		list("rest_right", "Rest (lie right)", KEYBIND_CAT_MOB, "Rest-Right", null, KB_HUMAN("CTRL+U")),
		list("resist", "Resist", KEYBIND_CAT_MOB, "Resist", null, KB_HUMAN("B")),
		list("quick_equip", "Quick equip", KEYBIND_CAT_ITEMS, "quick-equip", null, KB_HUMAN("E", "CTRL+E")),
		list("holster", "Holster", KEYBIND_CAT_ITEMS, "holster", null, KB_HUMAN("H", "CTRL+H")),
		list("toggle_gun_mode", "Toggle gun aiming mode", KEYBIND_CAT_ITEMS, "toggle-gun-mode", null, KB_BOTH("J", "CTRL+J")),

		// Combat mode (I6; code/modules/mob/combat_mode.dm). It replaced the intents, on
		// the same keys: 1 and 4 (help and harm) turn it off and on, the two
		// cycle keys toggle it, and 2 and 3 (disarm and grab) became the Disarm
		// and Grab keys, held like modifiers.
		list("combat_mode_off", "Combat mode off", KEYBIND_CAT_COMBAT, ".combat-mode off", null, KB_HUMAN("1", "CTRL+1")),
		list(COMBAT_DISARM_BINDING, "Disarm (hold)", KEYBIND_CAT_COMBAT, ".attack-variant [ATTACK_VARIANT_DISARM]", ".attack-variant-release [ATTACK_VARIANT_DISARM]", KB_HUMAN("2", "CTRL+2")),
		list(COMBAT_GRAB_BINDING, "Grab (hold)", KEYBIND_CAT_COMBAT, ".attack-variant [ATTACK_VARIANT_GRAB]", ".attack-variant-release [ATTACK_VARIANT_GRAB]", KB_HUMAN("3", "CTRL+3")),
		list("combat_mode_on", "Combat mode on", KEYBIND_CAT_COMBAT, ".combat-mode on", null, KB_HUMAN("4", "CTRL+4")),
		list("combat_mode_toggle", "Toggle combat mode", KEYBIND_CAT_COMBAT, ".combat-mode toggle", null, list(KEYBIND_PROFILE_DEFAULT = list("F", "CTRL+F"), KEYBIND_PROFILE_ROBOT = list("4", "CTRL+4", "F", "CTRL+F"))),
		list("combat_mode_toggle_alt", "Toggle combat mode (second key)", KEYBIND_CAT_COMBAT, ".combat-mode toggle", null, KB_BOTH("INSERT", "G", "CTRL+G")),

		// Robot modules
		list("module_1", "Module 1", KEYBIND_CAT_ROBOT, "toggle-module 1", null, KB_ROBOT("1", "CTRL+1")),
		list("module_2", "Module 2", KEYBIND_CAT_ROBOT, "toggle-module 2", null, KB_ROBOT("2", "CTRL+2")),
		list("module_3", "Module 3", KEYBIND_CAT_ROBOT, "toggle-module 3", null, KB_ROBOT("3", "CTRL+3")),
		list("unequip_module", "Unequip module", KEYBIND_CAT_ROBOT, "unequip-module", null, KB_ROBOT("Q", "CTRL+Q")),

		// Targeting
		list("target_r_leg", "Target right leg", KEYBIND_CAT_TARGETING, "body-r-leg", null, KB_BOTH("NUMPAD1")),
		list("target_groin", "Target groin", KEYBIND_CAT_TARGETING, "body-groin", null, KB_BOTH("NUMPAD2")),
		list("target_l_leg", "Target left leg", KEYBIND_CAT_TARGETING, "body-l-leg", null, KB_BOTH("NUMPAD3")),
		list("target_r_arm", "Target right arm", KEYBIND_CAT_TARGETING, "body-r-arm", null, KB_BOTH("NUMPAD4")),
		list("target_chest", "Target chest", KEYBIND_CAT_TARGETING, "body-chest", null, KB_BOTH("NUMPAD5")),
		list("target_l_arm", "Target left arm", KEYBIND_CAT_TARGETING, "body-l-arm", null, KB_BOTH("NUMPAD6")),
		list("target_head", "Target head, eyes, mouth", KEYBIND_CAT_TARGETING, "body-toggle-head", null, KB_BOTH("NUMPAD8")),

		// Communication
		list("say", "Say", KEYBIND_CAT_COMMS, "Say-verb", null, KB_BOTH("T", "F3")),
		list("emote", "Emote", KEYBIND_CAT_COMMS, "Me-verb", null, KB_BOTH("5", "F4")),
		list("subtle", "Subtle emote", KEYBIND_CAT_COMMS, "Subtle-verb", null, KB_BOTH("6")),
		list("whisper", "Whisper", KEYBIND_CAT_COMMS, "Whisper-verb", null, KB_BOTH("Y", "CTRL+Y")),
		list("ooc", "OOC", KEYBIND_CAT_COMMS, "ooc", null, KB_BOTH("F2")),
		list("ahelp", "Admin help", KEYBIND_CAT_COMMS, "request-help", null, KB_BOTH("F1")),

		// Client
		list("tab_noop", "Swallow Tab (keeps hotkey mode on)", KEYBIND_CAT_CLIENT, ".dq-tab-noop", null, KB_BOTH("TAB")),
		list("options", "Client options", KEYBIND_CAT_CLIENT, ".options", null, KB_BOTH("CTRL+SHIFT+F1+REP")),
		list("screenshot_auto", "Screenshot (quick save)", KEYBIND_CAT_CLIENT, ".screenshot auto", null, KB_BOTH("F2+REP")),
		list("screenshot", "Screenshot (save as)", KEYBIND_CAT_CLIENT, ".screenshot", null, KB_BOTH("SHIFT+F2+REP")),
		list("toggle_hud", "Toggle HUD", KEYBIND_CAT_CLIENT, "F12", null, KB_BOTH("F12")),
		list("plane_up", "Look up a level", KEYBIND_CAT_CLIENT, "planeup", null, KB_BOTH("CTRL+SHIFT+ADD")),
		list("plane_down", "Look down a level", KEYBIND_CAT_CLIENT, "planedown", null, KB_BOTH("CTRL+SHIFT+SUBTRACT")),

		// Admin
		list("asay", "Admin say", KEYBIND_CAT_ADMIN, "asay", null, KB_BOTH("F5")),
		list("player_panel", "Player panel", KEYBIND_CAT_ADMIN, "Player-Panel-New", null, KB_BOTH("F6")),
		list("admin_pm", "Admin PM", KEYBIND_CAT_ADMIN, "Admin-PM", null, KB_BOTH("F7")),
		list("invisimin", "Invisimin", KEYBIND_CAT_ADMIN, "Invisimin", null, KB_BOTH("F8")),
		list("msay", "Mentor say", KEYBIND_CAT_ADMIN, "msay", null, KB_BOTH("F9")),
		list("esay", "Event say", KEYBIND_CAT_ADMIN, "esay", null, KB_BOTH("F10")),
		list("mentorsay", "Mentor chat", KEYBIND_CAT_ADMIN, "mentorsay", null, KB_BOTH("F11")),
	)
	// The interaction Menu and the interaction categories (code/datums/interactions/). Unbound by default.
	. += list(list(INTERACTION_MENU_BINDING, "Interaction menu (hovered or in front)", KEYBIND_CAT_INTERACTION, ".input-menu", null, null))
	for(var/category in INTERACTION_CATEGORIES)
		. += list(list(INTERACTION_CATEGORY_BINDING(category), "[capitalize(category)] (hovered or in front)", KEYBIND_CAT_INTERACTION, ".input-category [category]", null, null))
	// Abilities (doc/rewrite/rules.md §5): one row per declared ability, unbound
	// by default. Whether it's usable right now (component, state, cost) is
	// checked when the key is pressed, not here. Reads `initial()` rather than
	// the GLOB.interactions_by_type singleton: global var init order between
	// the two lists isn't guaranteed, but compile-time initial values are
	// always available.
	for(var/datum/interaction/ability/path as anything in subtypesof(/datum/interaction/ability))
		if(!initial(path.id))
			continue
		. += list(list(ABILITY_KEYBIND(initial(path.id)), initial(path.name), KEYBIND_CAT_ABILITIES, ".use-ability [initial(path.id)]", null, null))

#undef KB_BOTH
#undef KB_HUMAN
#undef KB_ROBOT
