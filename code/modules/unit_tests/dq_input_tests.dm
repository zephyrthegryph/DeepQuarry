// Input layer (roadmap I1): default bindings, click tables and the router per actor.

/// Every macro the old skin.dmf "hotkeymode" and "borghotkeymode" sets defined,
/// as "profile|key|command". The default bindings must produce exactly these.
/// The intent keys kept their keys when combat mode replaced intents (I6).
/datum/unit_test/dq_keybinding_defaults_match_old_skin
	var/static/list/old_skin_macros = list(
		"[KEYBIND_PROFILE_ROBOT]|TAB|.dq-tab-noop",
		"[KEYBIND_PROFILE_ROBOT]|Shift|KeyDown Shift",
		"[KEYBIND_PROFILE_ROBOT]|Shift+UP|KeyUp Shift",
		"[KEYBIND_PROFILE_ROBOT]|Ctrl|KeyDown Ctrl",
		"[KEYBIND_PROFILE_ROBOT]|Ctrl+UP|KeyUp Ctrl",
		"[KEYBIND_PROFILE_ROBOT]|Alt|KeyDown Alt",
		"[KEYBIND_PROFILE_ROBOT]|Alt+UP|KeyUp Alt",
		"[KEYBIND_PROFILE_ROBOT]|NORTHEAST|.northeast",
		"[KEYBIND_PROFILE_ROBOT]|SOUTHEAST|.southeast",
		"[KEYBIND_PROFILE_ROBOT]|SOUTHWEST|.southwest",
		"[KEYBIND_PROFILE_ROBOT]|NORTHWEST|.northwest",
		"[KEYBIND_PROFILE_ROBOT]|ALT+WEST|westfaceperm",
		"[KEYBIND_PROFILE_ROBOT]|CTRL+WEST|westface",
		"[KEYBIND_PROFILE_ROBOT]|West|KeyDown West",
		"[KEYBIND_PROFILE_ROBOT]|West+UP|KeyUp West",
		"[KEYBIND_PROFILE_ROBOT]|ALT+NORTH|northfaceperm",
		"[KEYBIND_PROFILE_ROBOT]|CTRL+NORTH|northface",
		"[KEYBIND_PROFILE_ROBOT]|North|KeyDown North",
		"[KEYBIND_PROFILE_ROBOT]|North+UP|KeyUp North",
		"[KEYBIND_PROFILE_ROBOT]|ALT+EAST|eastfaceperm",
		"[KEYBIND_PROFILE_ROBOT]|CTRL+EAST|eastface",
		"[KEYBIND_PROFILE_ROBOT]|East|KeyDown East",
		"[KEYBIND_PROFILE_ROBOT]|East+UP|KeyUp East",
		"[KEYBIND_PROFILE_ROBOT]|ALT+SOUTH|southfaceperm",
		"[KEYBIND_PROFILE_ROBOT]|CTRL+SOUTH|southface",
		"[KEYBIND_PROFILE_ROBOT]|South|KeyDown South",
		"[KEYBIND_PROFILE_ROBOT]|South+UP|KeyUp South",
		"[KEYBIND_PROFILE_ROBOT]|CTRL+SHIFT+NORTH|shiftnorth",
		"[KEYBIND_PROFILE_ROBOT]|CTRL+SHIFT+SOUTH|shiftsouth",
		"[KEYBIND_PROFILE_ROBOT]|CTRL+SHIFT+WEST|shiftwest",
		"[KEYBIND_PROFILE_ROBOT]|CTRL+SHIFT+EAST|shifteast",
		"[KEYBIND_PROFILE_ROBOT]|INSERT|.combat-mode toggle",
		"[KEYBIND_PROFILE_ROBOT]|DELETE|delete-key-pressed",
		"[KEYBIND_PROFILE_ROBOT]|1|toggle-module 1",
		"[KEYBIND_PROFILE_ROBOT]|CTRL+1|toggle-module 1",
		"[KEYBIND_PROFILE_ROBOT]|2|toggle-module 2",
		"[KEYBIND_PROFILE_ROBOT]|CTRL+2|toggle-module 2",
		"[KEYBIND_PROFILE_ROBOT]|3|toggle-module 3",
		"[KEYBIND_PROFILE_ROBOT]|CTRL+3|toggle-module 3",
		"[KEYBIND_PROFILE_ROBOT]|4|.combat-mode toggle",
		"[KEYBIND_PROFILE_ROBOT]|CTRL+4|.combat-mode toggle",
		"[KEYBIND_PROFILE_ROBOT]|5|Me-verb",
		"[KEYBIND_PROFILE_ROBOT]|6|Subtle-verb",
		"[KEYBIND_PROFILE_ROBOT]|A|KeyDown A",
		"[KEYBIND_PROFILE_ROBOT]|A+UP|KeyUp A",
		"[KEYBIND_PROFILE_ROBOT]|D|KeyDown D",
		"[KEYBIND_PROFILE_ROBOT]|D+UP|KeyUp D",
		"[KEYBIND_PROFILE_ROBOT]|F|.combat-mode toggle",
		"[KEYBIND_PROFILE_ROBOT]|CTRL+F|.combat-mode toggle",
		"[KEYBIND_PROFILE_ROBOT]|G|.combat-mode toggle",
		"[KEYBIND_PROFILE_ROBOT]|CTRL+G|.combat-mode toggle",
		"[KEYBIND_PROFILE_ROBOT]|J|toggle-gun-mode",
		"[KEYBIND_PROFILE_ROBOT]|CTRL+J|toggle-gun-mode",
		"[KEYBIND_PROFILE_ROBOT]|Q|unequip-module",
		"[KEYBIND_PROFILE_ROBOT]|CTRL+Q|unequip-module",
		"[KEYBIND_PROFILE_ROBOT]|R|.southwest",
		"[KEYBIND_PROFILE_ROBOT]|CTRL+R|.southwest",
		"[KEYBIND_PROFILE_ROBOT]|S|KeyDown S",
		"[KEYBIND_PROFILE_ROBOT]|S+UP|KeyUp S",
		"[KEYBIND_PROFILE_ROBOT]|T|Say-verb",
		"[KEYBIND_PROFILE_ROBOT]|W|KeyDown W",
		"[KEYBIND_PROFILE_ROBOT]|W+UP|KeyUp W",
		"[KEYBIND_PROFILE_ROBOT]|X|.northeast",
		"[KEYBIND_PROFILE_ROBOT]|CTRL+X|.northeast",
		"[KEYBIND_PROFILE_ROBOT]|Y|Whisper-verb",
		"[KEYBIND_PROFILE_ROBOT]|CTRL+Y|Whisper-verb",
		"[KEYBIND_PROFILE_ROBOT]|Z|Activate-Held-Object",
		"[KEYBIND_PROFILE_ROBOT]|CTRL+Z|Robot-Activate-Held-Object",
		"[KEYBIND_PROFILE_ROBOT]|U|Rest",
		"[KEYBIND_PROFILE_ROBOT]|NUMPAD1|body-r-leg",
		"[KEYBIND_PROFILE_ROBOT]|NUMPAD2|body-groin",
		"[KEYBIND_PROFILE_ROBOT]|NUMPAD3|body-l-leg",
		"[KEYBIND_PROFILE_ROBOT]|NUMPAD4|body-r-arm",
		"[KEYBIND_PROFILE_ROBOT]|NUMPAD5|body-chest",
		"[KEYBIND_PROFILE_ROBOT]|NUMPAD6|body-l-arm",
		"[KEYBIND_PROFILE_ROBOT]|NUMPAD8|body-toggle-head",
		"[KEYBIND_PROFILE_ROBOT]|F1|request-help",
		"[KEYBIND_PROFILE_ROBOT]|CTRL+SHIFT+F1+REP|.options",
		"[KEYBIND_PROFILE_ROBOT]|F2|ooc",
		"[KEYBIND_PROFILE_ROBOT]|F2+REP|.screenshot auto",
		"[KEYBIND_PROFILE_ROBOT]|SHIFT+F2+REP|.screenshot",
		"[KEYBIND_PROFILE_ROBOT]|F3|Say-verb",
		"[KEYBIND_PROFILE_ROBOT]|F4|Me-verb",
		"[KEYBIND_PROFILE_ROBOT]|F5|asay",
		"[KEYBIND_PROFILE_ROBOT]|F6|Player-Panel-New",
		"[KEYBIND_PROFILE_ROBOT]|F7|Admin-PM",
		"[KEYBIND_PROFILE_ROBOT]|F8|Invisimin",
		"[KEYBIND_PROFILE_ROBOT]|F9|msay",
		"[KEYBIND_PROFILE_ROBOT]|F10|esay",
		"[KEYBIND_PROFILE_ROBOT]|F11|mentorsay",
		"[KEYBIND_PROFILE_ROBOT]|F12|F12",
		"[KEYBIND_PROFILE_ROBOT]|CTRL+SHIFT+ADD|planeup",
		"[KEYBIND_PROFILE_ROBOT]|CTRL+SHIFT+SUBTRACT|planedown",
		"[KEYBIND_PROFILE_DEFAULT]|TAB|.dq-tab-noop",
		"[KEYBIND_PROFILE_DEFAULT]|Shift|KeyDown Shift",
		"[KEYBIND_PROFILE_DEFAULT]|Shift+UP|KeyUp Shift",
		"[KEYBIND_PROFILE_DEFAULT]|Ctrl|KeyDown Ctrl",
		"[KEYBIND_PROFILE_DEFAULT]|Ctrl+UP|KeyUp Ctrl",
		"[KEYBIND_PROFILE_DEFAULT]|Alt|KeyDown Alt",
		"[KEYBIND_PROFILE_DEFAULT]|Alt+UP|KeyUp Alt",
		"[KEYBIND_PROFILE_DEFAULT]|NORTHEAST|.northeast",
		"[KEYBIND_PROFILE_DEFAULT]|SOUTHEAST|.southeast",
		"[KEYBIND_PROFILE_DEFAULT]|SOUTHWEST|.southwest",
		"[KEYBIND_PROFILE_DEFAULT]|NORTHWEST|.northwest",
		"[KEYBIND_PROFILE_DEFAULT]|ALT+WEST|westfaceperm",
		"[KEYBIND_PROFILE_DEFAULT]|CTRL+WEST|westface",
		"[KEYBIND_PROFILE_DEFAULT]|West|KeyDown West",
		"[KEYBIND_PROFILE_DEFAULT]|West+UP|KeyUp West",
		"[KEYBIND_PROFILE_DEFAULT]|ALT+NORTH|northfaceperm",
		"[KEYBIND_PROFILE_DEFAULT]|CTRL+NORTH|northface",
		"[KEYBIND_PROFILE_DEFAULT]|North|KeyDown North",
		"[KEYBIND_PROFILE_DEFAULT]|North+UP|KeyUp North",
		"[KEYBIND_PROFILE_DEFAULT]|ALT+EAST|eastfaceperm",
		"[KEYBIND_PROFILE_DEFAULT]|CTRL+EAST|eastface",
		"[KEYBIND_PROFILE_DEFAULT]|East|KeyDown East",
		"[KEYBIND_PROFILE_DEFAULT]|East+UP|KeyUp East",
		"[KEYBIND_PROFILE_DEFAULT]|ALT+SOUTH|southfaceperm",
		"[KEYBIND_PROFILE_DEFAULT]|CTRL+SOUTH|southface",
		"[KEYBIND_PROFILE_DEFAULT]|South|KeyDown South",
		"[KEYBIND_PROFILE_DEFAULT]|South+UP|KeyUp South",
		"[KEYBIND_PROFILE_DEFAULT]|CTRL+SHIFT+NORTH|shiftnorth",
		"[KEYBIND_PROFILE_DEFAULT]|CTRL+SHIFT+SOUTH|shiftsouth",
		"[KEYBIND_PROFILE_DEFAULT]|CTRL+SHIFT+WEST|shiftwest",
		"[KEYBIND_PROFILE_DEFAULT]|CTRL+SHIFT+EAST|shifteast",
		"[KEYBIND_PROFILE_DEFAULT]|INSERT|.combat-mode toggle",
		"[KEYBIND_PROFILE_DEFAULT]|DELETE|delete-key-pressed",
		"[KEYBIND_PROFILE_DEFAULT]|1|.combat-mode off",
		"[KEYBIND_PROFILE_DEFAULT]|CTRL+1|.combat-mode off",
		"[KEYBIND_PROFILE_DEFAULT]|2|.attack-variant disarm",
		"[KEYBIND_PROFILE_DEFAULT]|2+UP|.attack-variant-release disarm", // New in I6: the Disarm key is held.
		"[KEYBIND_PROFILE_DEFAULT]|CTRL+2|.attack-variant disarm",
		"[KEYBIND_PROFILE_DEFAULT]|CTRL+2+UP|.attack-variant-release disarm",
		"[KEYBIND_PROFILE_DEFAULT]|3|.attack-variant grab",
		"[KEYBIND_PROFILE_DEFAULT]|3+UP|.attack-variant-release grab", // New in I6: the Grab key is held.
		"[KEYBIND_PROFILE_DEFAULT]|CTRL+3|.attack-variant grab",
		"[KEYBIND_PROFILE_DEFAULT]|CTRL+3+UP|.attack-variant-release grab",
		"[KEYBIND_PROFILE_DEFAULT]|4|.combat-mode on",
		"[KEYBIND_PROFILE_DEFAULT]|CTRL+4|.combat-mode on",
		"[KEYBIND_PROFILE_DEFAULT]|5|Me-verb",
		"[KEYBIND_PROFILE_DEFAULT]|6|Subtle-verb",
		"[KEYBIND_PROFILE_DEFAULT]|A|KeyDown A",
		"[KEYBIND_PROFILE_DEFAULT]|A+UP|KeyUp A",
		"[KEYBIND_PROFILE_DEFAULT]|D|KeyDown D",
		"[KEYBIND_PROFILE_DEFAULT]|D+UP|KeyUp D",
		"[KEYBIND_PROFILE_DEFAULT]|E|quick-equip",
		"[KEYBIND_PROFILE_DEFAULT]|CTRL+E|quick-equip",
		"[KEYBIND_PROFILE_DEFAULT]|F|.combat-mode toggle",
		"[KEYBIND_PROFILE_DEFAULT]|CTRL+F|.combat-mode toggle",
		"[KEYBIND_PROFILE_DEFAULT]|G|.combat-mode toggle",
		"[KEYBIND_PROFILE_DEFAULT]|CTRL+G|.combat-mode toggle",
		"[KEYBIND_PROFILE_DEFAULT]|H|holster",
		"[KEYBIND_PROFILE_DEFAULT]|CTRL+H|holster",
		"[KEYBIND_PROFILE_DEFAULT]|J|toggle-gun-mode",
		"[KEYBIND_PROFILE_DEFAULT]|CTRL+J|toggle-gun-mode",
		"[KEYBIND_PROFILE_DEFAULT]|Q|.northwest",
		"[KEYBIND_PROFILE_DEFAULT]|CTRL+Q|.northwest",
		"[KEYBIND_PROFILE_DEFAULT]|R|.southwest",
		"[KEYBIND_PROFILE_DEFAULT]|CTRL+R|.southwest",
		"[KEYBIND_PROFILE_DEFAULT]|S|KeyDown S",
		"[KEYBIND_PROFILE_DEFAULT]|S+UP|KeyUp S",
		"[KEYBIND_PROFILE_DEFAULT]|T|Say-verb",
		"[KEYBIND_PROFILE_DEFAULT]|W|KeyDown W",
		"[KEYBIND_PROFILE_DEFAULT]|W+UP|KeyUp W",
		"[KEYBIND_PROFILE_DEFAULT]|X|.northeast",
		"[KEYBIND_PROFILE_DEFAULT]|CTRL+X|.northeast",
		"[KEYBIND_PROFILE_DEFAULT]|Y|Whisper-verb",
		"[KEYBIND_PROFILE_DEFAULT]|CTRL+Y|Whisper-verb",
		"[KEYBIND_PROFILE_DEFAULT]|Z|Activate-Held-Object",
		"[KEYBIND_PROFILE_DEFAULT]|CTRL+Z|Activate-Held-Object",
		"[KEYBIND_PROFILE_DEFAULT]|U|Rest",
		"[KEYBIND_PROFILE_DEFAULT]|SHIFT+U|Rest-Left",
		"[KEYBIND_PROFILE_DEFAULT]|CTRL+U|Rest-Right",
		"[KEYBIND_PROFILE_DEFAULT]|B|Resist",
		"[KEYBIND_PROFILE_DEFAULT]|NUMPAD1|body-r-leg",
		"[KEYBIND_PROFILE_DEFAULT]|NUMPAD2|body-groin",
		"[KEYBIND_PROFILE_DEFAULT]|NUMPAD3|body-l-leg",
		"[KEYBIND_PROFILE_DEFAULT]|NUMPAD4|body-r-arm",
		"[KEYBIND_PROFILE_DEFAULT]|NUMPAD5|body-chest",
		"[KEYBIND_PROFILE_DEFAULT]|NUMPAD6|body-l-arm",
		"[KEYBIND_PROFILE_DEFAULT]|NUMPAD8|body-toggle-head",
		"[KEYBIND_PROFILE_DEFAULT]|F1|request-help",
		"[KEYBIND_PROFILE_DEFAULT]|CTRL+SHIFT+F1+REP|.options",
		"[KEYBIND_PROFILE_DEFAULT]|F2|ooc",
		"[KEYBIND_PROFILE_DEFAULT]|F2+REP|.screenshot auto",
		"[KEYBIND_PROFILE_DEFAULT]|SHIFT+F2+REP|.screenshot",
		"[KEYBIND_PROFILE_DEFAULT]|F3|Say-verb",
		"[KEYBIND_PROFILE_DEFAULT]|F4|Me-verb",
		"[KEYBIND_PROFILE_DEFAULT]|F5|asay",
		"[KEYBIND_PROFILE_DEFAULT]|F6|Player-Panel-New",
		"[KEYBIND_PROFILE_DEFAULT]|F7|Admin-PM",
		"[KEYBIND_PROFILE_DEFAULT]|F8|Invisimin",
		"[KEYBIND_PROFILE_DEFAULT]|F9|msay",
		"[KEYBIND_PROFILE_DEFAULT]|F10|esay",
		"[KEYBIND_PROFILE_DEFAULT]|F11|mentorsay",
		"[KEYBIND_PROFILE_DEFAULT]|F12|F12",
		"[KEYBIND_PROFILE_DEFAULT]|CTRL+SHIFT+ADD|planeup",
		"[KEYBIND_PROFILE_DEFAULT]|CTRL+SHIFT+SUBTRACT|planedown",
	)

/datum/unit_test/dq_keybinding_defaults_match_old_skin/Run()
	var/list/actual = list()
	for(var/profile in KEYBIND_PROFILES)
		for(var/list/macro as anything in keybinding_macros(profile, null))
			var/entry = "[profile]|[macro[1]]|[macro[2]]"
			TEST_ASSERT(!(entry in actual), "duplicate default macro [entry]")
			actual += entry
	for(var/entry in old_skin_macros)
		TEST_ASSERT(entry in actual, "the old skin macro [entry] has no default binding")
	for(var/entry in actual)
		TEST_ASSERT(entry in old_skin_macros, "default binding [entry] was not in the old skin")
	TEST_ASSERT_EQUAL(length(actual), length(old_skin_macros), "default macro count should match the old skin")

/// Player overrides replace a binding's keys in one profile only, and an empty list unbinds.
/datum/unit_test/dq_keybinding_overrides

/datum/unit_test/dq_keybinding_overrides/Run()
	var/datum/keybinding/say = GLOB.keybindings["say"]
	var/list/overrides = sanitize_keybinding_overrides(list(
		KEYBIND_PROFILE_DEFAULT = list("say" = list("k", "ctrl+k", "bad key!", "K"), "no_such_binding" = list("L")),
		"no_such_profile" = list("say" = list("M")),
	))
	TEST_ASSERT_EQUAL(jointext(keybinding_keys(say, KEYBIND_PROFILE_DEFAULT, overrides), ","), "K,CTRL+K", "overrides are sanitised, uppercased and deduplicated")
	TEST_ASSERT_EQUAL(jointext(keybinding_keys(say, KEYBIND_PROFILE_ROBOT, overrides), ","), "T,F3", "an override in one profile leaves the other on its defaults")
	TEST_ASSERT(!("no_such_profile" in overrides), "unknown profiles are dropped")
	var/list/default_overrides = overrides[KEYBIND_PROFILE_DEFAULT]
	TEST_ASSERT(!("no_such_binding" in default_overrides), "unknown binding ids are dropped")
	overrides = list(KEYBIND_PROFILE_DEFAULT = list("say" = list()))
	TEST_ASSERT_EQUAL(length(keybinding_keys(say, KEYBIND_PROFILE_DEFAULT, overrides)), 0, "an empty override unbinds")
	TEST_ASSERT(!keybinding_profile_uses_hover(KEYBIND_PROFILE_DEFAULT, null), "no default binding needs hover tracking")
	overrides = list(KEYBIND_PROFILE_DEFAULT = list("category_[INTERACTION_CAT_TOGGLE]" = list("V")))
	TEST_ASSERT(keybinding_profile_uses_hover(KEYBIND_PROFILE_DEFAULT, overrides), "a bound category key turns hover tracking on")
	TEST_ASSERT_NULL(sanitize_keybind_key("W+UP"), "release macros are generated, not bound")

/// What a click produces with an adapter's click table: "use", "none", or the mob proc the old ladder called.
/datum/unit_test/proc/dq_click_result(datum/input_adapter/adapter, params, right_click_binding)
	var/action = GLOB.input_router.classify(params2list(params), adapter.click_table(), right_click_binding)
	if(action == INPUT_ACTION_USE)
		return "use"
	return adapter.handler_for(action) || "none"

/// Checks rows of list(params, right-click binding, expected result) against an adapter.
/datum/unit_test/proc/dq_check_click_rows(datum/input_adapter/adapter, list/rows)
	for(var/list/row as anything in rows)
		var/result = dq_click_result(adapter, row[1], row[2])
		TEST_ASSERT_EQUAL(result, row[3], "[adapter.name] click '[row[1]]' with right-click bound to [row[2]]")

/// The standard table maps each modifier combination to the proc the old
/// ladders in click.dm, observer.dm and cyborg.dm called.
/datum/unit_test/dq_input_standard_click_table

/datum/unit_test/dq_input_standard_click_table/Run()
	var/list/rows = list(
		list("left=1", INPUT_ACTION_MENU, "use"),
		list("left=1;shift=1", INPUT_ACTION_MENU, TYPE_PROC_REF(/mob, ShiftClickOn)),
		list("right=1;shift=1", INPUT_ACTION_ALTERNATE, TYPE_PROC_REF(/mob, ShiftClickOn)),
		list("middle=1;shift=1", INPUT_ACTION_MENU, TYPE_PROC_REF(/mob, ShiftMiddleClickOn)),
		list("middle=1;shift=1;ctrl=1", INPUT_ACTION_MENU, TYPE_PROC_REF(/mob, ShiftMiddleClickOn)),
		list("left=1;shift=1;ctrl=1", INPUT_ACTION_MENU, TYPE_PROC_REF(/mob, CtrlShiftClickOn)),
		list("left=1;shift=1;ctrl=1;alt=1", INPUT_ACTION_MENU, TYPE_PROC_REF(/mob, CtrlShiftClickOn)),
		list("left=1;shift=1;alt=1", INPUT_ACTION_MENU, TYPE_PROC_REF(/mob, alt_shift_click_on)),
		list("middle=1;ctrl=1", INPUT_ACTION_MENU, TYPE_PROC_REF(/mob, CtrlMiddleClickOn)),
		list("middle=1", INPUT_ACTION_MENU, TYPE_PROC_REF(/mob, MiddleClickOn)),
		list("middle=1;alt=1", INPUT_ACTION_MENU, TYPE_PROC_REF(/mob, MiddleClickOn)),
		list("right=1;alt=1", INPUT_ACTION_MENU, TYPE_PROC_REF(/mob, AltClickSecondaryOn)),
		list("left=1;alt=1", INPUT_ACTION_MENU, TYPE_PROC_REF(/mob, AltClickOn)),
		list("left=1;alt=1;ctrl=1", INPUT_ACTION_MENU, TYPE_PROC_REF(/mob, AltClickOn)),
		list("left=1;ctrl=1", INPUT_ACTION_MENU, TYPE_PROC_REF(/mob, CtrlClickOn)),
		list("xbutton1=1", INPUT_ACTION_MENU, "none"),
		list("xbutton2=1;shift=1", INPUT_ACTION_MENU, "none"),
		// Right-click is new (B21): it follows the player's binding.
		list("right=1", INPUT_ACTION_MENU, "none"),
		list("right=1", INPUT_ACTION_ALTERNATE, TYPE_PROC_REF(/mob, AltClickOn)),
		list("right=1;ctrl=1", INPUT_ACTION_ALTERNATE, TYPE_PROC_REF(/mob, CtrlClickOn)),
	)
	for(var/adapter_type in list(/datum/input_adapter/hands, /datum/input_adapter/ghost, /datum/input_adapter/robot))
		dq_check_click_rows(GLOB.input_adapters[adapter_type], rows)

/// The AI's table reproduces the old AI ladder in ai.dm, which read fewer modifiers.
/datum/unit_test/dq_input_ai_click_table

/datum/unit_test/dq_input_ai_click_table/Run()
	dq_check_click_rows(INPUT_ADAPTER(ai), list(
		list("left=1", INPUT_ACTION_MENU, "use"),
		list("left=1;shift=1;ctrl=1", INPUT_ACTION_MENU, TYPE_PROC_REF(/mob, CtrlShiftClickOn)),
		list("middle=1;shift=1", INPUT_ACTION_MENU, TYPE_PROC_REF(/mob, MiddleClickOn)),
		list("middle=1;ctrl=1", INPUT_ACTION_MENU, TYPE_PROC_REF(/mob, MiddleClickOn)),
		list("left=1;shift=1", INPUT_ACTION_MENU, TYPE_PROC_REF(/mob, ShiftClickOn)),
		list("left=1;shift=1;alt=1", INPUT_ACTION_MENU, TYPE_PROC_REF(/mob, ShiftClickOn)),
		list("right=1;alt=1", INPUT_ACTION_MENU, TYPE_PROC_REF(/mob, AltClickOn)),
		list("left=1;alt=1;ctrl=1", INPUT_ACTION_MENU, TYPE_PROC_REF(/mob, AltClickOn)),
		list("left=1;ctrl=1", INPUT_ACTION_MENU, TYPE_PROC_REF(/mob, CtrlClickOn)),
		list("xbutton1=1", INPUT_ACTION_MENU, "use"),
		list("right=1", INPUT_ACTION_ALTERNATE, TYPE_PROC_REF(/mob, AltClickOn)),
	))

/// Records which legacy handler the router reached.
/obj/dq_input_probe
	var/last_handler
	var/mob/last_user

/obj/dq_input_probe/proc/note(handler, mob/user)
	last_handler = handler
	last_user = user

/obj/dq_input_probe/attack_hand(mob/user)
	note("attack_hand", user)

/obj/dq_input_probe/attack_ghost(mob/observer/dead/user)
	note("attack_ghost", user)

/obj/dq_input_probe/attack_robot(mob/user)
	note("attack_robot", user)

/obj/dq_input_probe/attack_ai(mob/user)
	note("attack_ai", user)

/obj/dq_input_probe/attack_tk(mob/user)
	note("attack_tk", user)

/obj/dq_input_probe/click_alt(mob/user)
	note("click_alt", user)
	return CLICK_ACTION_SUCCESS

/obj/dq_input_probe/MouseDrop_T(atom/dropping, mob/user, src_location, over_location, src_control, over_control, params)
	note("MouseDrop_T", user)

/obj/item/dq_input_probe_item
	var/mob/self_used_by

/obj/item/dq_input_probe_item/attack_self(mob/user, modifiers)
	. = ..()
	self_used_by = user

/// Clicks through the router as a mob; returns the handler the probe saw for that mob.
/datum/unit_test/proc/dq_route(mob/user, obj/dq_input_probe/probe, params)
	probe.last_handler = null
	probe.last_user = null
	user.next_click = 0
	GLOB.input_router.route_click(user, probe, params)
	return probe.last_user == user ? probe.last_handler : null

/// Each mob kind gets its adapter, and Use and Alternate reach today's handlers.
/datum/unit_test/dq_input_router_per_actor

/datum/unit_test/dq_input_router_per_actor/Run()
	var/turf/T = test_floor()
	var/obj/dq_input_probe/probe = allocate(/obj/dq_input_probe, T)

	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT_EQUAL(H.input_adapter(), INPUT_ADAPTER(hands), "humans use the hands adapter")
	TEST_ASSERT_EQUAL(H.keybind_profile(), KEYBIND_PROFILE_DEFAULT, "humans get the default keybinding profile")
	TEST_ASSERT_EQUAL(dq_route(H, probe, "left=1"), "attack_hand", "a human's Use with an empty hand reaches attack_hand")
	TEST_ASSERT_EQUAL(dq_route(H, probe, "left=1;alt=1"), "click_alt", "a human's Alternate reaches click_alt")

	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, T)
	TEST_ASSERT_EQUAL(R.input_adapter(), INPUT_ADAPTER(robot), "cyborgs use the robot adapter")
	TEST_ASSERT_EQUAL(R.keybind_profile(), KEYBIND_PROFILE_ROBOT, "cyborgs get the robot keybinding profile")
	TEST_ASSERT_EQUAL(dq_route(R, probe, "left=1"), "attack_robot", "a cyborg's Use with no module reaches attack_robot")
	TEST_ASSERT_EQUAL(dq_route(R, probe, "left=1;alt=1"), "click_alt", "a cyborg's Alternate reaches click_alt through BorgAltClick")

	var/mob/observer/dead/ghost = allocate(/mob/observer/dead, T)
	TEST_ASSERT_EQUAL(ghost.input_adapter(), INPUT_ADAPTER(ghost), "ghosts use the ghost adapter")
	TEST_ASSERT_EQUAL(dq_route(ghost, probe, "left=1"), "attack_ghost", "a ghost's Use reaches attack_ghost")
	TEST_ASSERT_EQUAL(dq_route(ghost, probe, "left=1;alt=1"), "click_alt", "a ghost's Alternate reaches click_alt")

	var/mob/living/silicon/ai/AI = allocate(/mob/living/silicon/ai, T)
	TEST_ASSERT_EQUAL(AI.input_adapter(), INPUT_ADAPTER(ai), "the AI uses the AI adapter")
	TEST_ASSERT_EQUAL(dq_route(AI, probe, "left=1"), "attack_ai", "the AI's Use reaches attack_ai")
	TEST_ASSERT_EQUAL(dq_route(AI, probe, "left=1;alt=1"), "click_alt", "the AI's Alternate reaches click_alt through AIAltClick")
	AI.control_disabled = TRUE
	TEST_ASSERT_NULL(dq_route(AI, probe, "left=1"), "an AI with control disabled does nothing")

/// Telekinesis, Self-use and Drag.
/datum/unit_test/dq_input_router_capabilities

/datum/unit_test/dq_input_router_capabilities/Run()
	var/turf/T = test_floor()
	var/obj/dq_input_probe/probe = allocate(/obj/dq_input_probe, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)

	var/datum/input_adapter/telekinesis/telekinesis = INPUT_ADAPTER(telekinesis)
	telekinesis.use(H, probe)
	TEST_ASSERT_EQUAL(probe.last_handler, "attack_tk", "the telekinesis adapter's Use reaches attack_tk")

	var/obj/item/dq_input_probe_item/item = allocate(/obj/item/dq_input_probe_item, T)
	TEST_ASSERT(H.put_in_active_hand(item), "the human should hold the probe item")
	H.next_click = 0
	GLOB.input_router.route_click(H, item, "left=1")
	TEST_ASSERT_EQUAL(item.self_used_by, H, "clicking the held item is Self-use, which runs attack_self")

	H.drop_from_inventory(item, T)
	probe.last_handler = null
	GLOB.input_router.route_drag(H, item, probe)
	TEST_ASSERT_EQUAL(probe.last_handler, "MouseDrop_T", "dragging onto an atom reaches MouseDrop_T")
