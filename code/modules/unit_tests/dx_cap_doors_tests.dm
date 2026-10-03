// Door capabilities (code/datums/capabilities/library/doors.dm) and the airlock proof conversion
// (code/game/machinery/doors/airlock.dm).

/obj/cap_fixture/door_caps
	/// Whether touching it shocks (its electrify subtype's is_electrified() reads it).
	var/live = FALSE
	/// How many shocks its electrify subtype's shock() delivered.
	var/shocks = 0

/obj/cap_fixture/door_caps/capabilities()
	. = ..()
	. += cap_bolts()
	. += cap_weld_shut()
	. += cap_pry()
	. += cap_emergency_access()
	. += cap_electrify(type = /datum/capability/electrify/door_caps_fixture)
	. += cap_hand("Poke", PROC_REF(poke))

/obj/cap_fixture/door_caps/proc/poke(mob/user)
	return TRUE

/// The fixture's electrification: a holder-interface subtype (nothing on /atom).
/datum/capability/electrify/door_caps_fixture

/datum/capability/electrify/door_caps_fixture/is_electrified(obj/cap_fixture/door_caps/holder)
	return holder.live

/datum/capability/electrify/door_caps_fixture/shock(obj/cap_fixture/door_caps/holder, mob/user, chance)
	holder.shocks++
	return TRUE

/// Every capability's UI data flattened into one list (as AiAirlock.tsx reads data.caps).
/proc/dx_flat_caps_data(atom/A, mob/user)
	. = list()
	var/list/data = list()
	caps_ui_data(A, user, data)
	var/list/caps = data["caps"]
	for(var/key in caps)
		var/list/part = caps[key]
		for(var/field in part)
			.[field] = part[field]

/// Bolts and emergency access: the bits, the layers, the examine line and the UI data.
/datum/unit_test/dx_cap_doors_bolts/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/door_caps/A = allocate(/obj/cap_fixture/door_caps, T)
	TEST_ASSERT(!is_bolted(A), "starts unbolted")
	TEST_ASSERT(set_bolted(A, TRUE), "set_bolted drops the bolts")
	TEST_ASSERT(A.cap_state & CAP_BOLTED, "the bit is set")
	refresh_flush()
	TEST_ASSERT(cap_test_has_layer(A, "bolts"), "the bolts layer is drawn")
	TEST_ASSERT(set_bolted(A, FALSE) && !is_bolted(A), "set_bolted raises them")
	refresh_flush()
	TEST_ASSERT(!cap_test_has_layer(A, "bolts"), "the layer is gone")

	TEST_ASSERT(set_emergency_access(A, TRUE), "emergency access engages")
	TEST_ASSERT(A.cap_state & CAP_EMERGENCY_ACCESS, "its bit is set")
	TEST_ASSERT("Its emergency access mode is engaged." in caps_examine(A, H), "examine says so")
	var/list/data = list()
	for(var/datum/capability/C as anything in caps_all(A))
		C.legacy_ui_data(A, H, data)
	TEST_ASSERT_EQUAL(data["emergency"], TRUE, "UI data carries emergency")
	TEST_ASSERT_EQUAL(data["bolted"], FALSE, "UI data carries bolted")

/// Welding: the toggle, the name, the examine line and the layer; prying is refused while welded or
/// bolted.
/datum/unit_test/dx_cap_doors_weld_and_pry/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/door_caps/A = allocate(/obj/cap_fixture/door_caps, T)
	var/obj/item/tool/crowbar/bar = allocate(/obj/item/tool/crowbar, T)
	var/datum/interaction/capability/weld = cap_test_entry(A, "weld_shut:[TOOL_WELDER]:[I_HELP]")
	var/datum/interaction/capability/pry = cap_test_entry(A, "pry:[TOOL_CROWBAR]:[I_HELP]")
	TEST_ASSERT_NOTNULL(weld, "a weld entry per stance")
	TEST_ASSERT_NOTNULL(pry, "a pry entry per stance")
	TEST_ASSERT_EQUAL(weld.display_name(H, A), "Weld shut", "named Weld shut")
	TEST_ASSERT_NULL(pry.why_not(H, A, bar), "an unbolted, unwelded fixture pries")

	TEST_ASSERT(cap_weld_toggle(A, H, null), "the weld toggles")
	TEST_ASSERT(is_welded(A), "welded")
	TEST_ASSERT_EQUAL(weld.display_name(H, A), "Unweld", "named Unweld while welded")
	TEST_ASSERT("It has been welded shut." in caps_examine(A, H), "examine says welded")
	refresh_flush()
	TEST_ASSERT(cap_test_has_layer(A, "welded"), "the welded layer is drawn")
	TEST_ASSERT_EQUAL(pry.why_not(H, A, bar), "it's welded shut", "prying a welded fixture is refused")

	cap_weld_toggle(A, H, null)
	set_bolted(A, TRUE)
	TEST_ASSERT_EQUAL(pry.why_not(H, A, bar), "its bolts prevent it from being forced", "prying a bolted fixture is refused")

/// cap_electrify(): every entry zaps first through the holder's before_entry(); a shock stops it, a
/// silicon is never zapped, and an unelectrified holder lets it through.
/datum/unit_test/dx_cap_doors_electrify/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/door_caps/A = allocate(/obj/cap_fixture/door_caps, T)
	var/datum/interaction/capability/poke
	for(var/datum/interaction/capability/E as anything in cap_interactions(A))
		if(E.name == "Poke")
			poke = E
	TEST_ASSERT_NOTNULL(poke, "the fixture has its Poke entry")
	TEST_ASSERT(A.before_entry(H, poke, null), "not electrified: the entry goes ahead")
	TEST_ASSERT_EQUAL(A.shocks, 0, "and nobody is shocked")
	A.live = TRUE
	TEST_ASSERT(!A.before_entry(H, poke, null), "electrified: the entry stops")
	TEST_ASSERT_EQUAL(A.shocks, 1, "the user was shocked")
	TEST_ASSERT_EQUAL(poke.run_effect(H, A, null), UI_REFUSED, "a full run stops at the shock")
	TEST_ASSERT_EQUAL(A.shocks, 2, "shocked again")
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, T)
	TEST_ASSERT(A.before_entry(R, poke, null), "a silicon is never zapped")
	TEST_ASSERT_EQUAL(A.shocks, 2, "no shock for the silicon")

// ---- the airlock proof conversion ----

/// A test airlock: anyone may use its panel, and its shock is counted instead of delivered.
/obj/machinery/door/airlock/dx_test
	var/shocks = 0

/obj/machinery/door/airlock/dx_test/user_allowed(mob/user)
	return TRUE

/obj/machinery/door/airlock/dx_test/shock(mob/user, prb)
	shocks++
	return TRUE

/// The converted airlock lists its capabilities.
/datum/unit_test/dx_airlock_capabilities/Run()
	var/obj/machinery/door/airlock/A = allocate(/obj/machinery/door/airlock, run_loc_floor_bottom_left)
	for(var/path in list(/datum/capability/panel, /datum/capability/wires, /datum/capability/lock/door, /datum/capability/breakable, /datum/capability/emag, /datum/capability/bolts, /datum/capability/electrify, /datum/capability/weld_shut, /datum/capability/pry, /datum/capability/emergency_access, /datum/capability/ai_control, /datum/capability/frozen_shut, /datum/capability/crush, /datum/capability/door_timing))
		TEST_ASSERT_NOTNULL(cap_of(A, path), "the airlock has [path]")

/// Bolting through the airlock's own mechanism, welding, and prying refused while bolted.
/datum/unit_test/dx_airlock_bolt_weld_pry/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/door/airlock/A = allocate(/obj/machinery/door/airlock, T)
	var/obj/item/tool/crowbar/bar = allocate(/obj/item/tool/crowbar, T)
	TEST_ASSERT(A.lock(), "lock() drops the bolts")
	TEST_ASSERT(is_bolted(A), "bolted")
	TEST_ASSERT(!A.allowed(H), "a bolted airlock lets nobody through")
	TEST_ASSERT(A.unlock(TRUE), "a forced unlock raises them")
	TEST_ASSERT(!is_bolted(A), "unbolted")

	TEST_ASSERT(cap_weld_toggle(A, H, null), "the weld toggles")
	TEST_ASSERT(is_welded(A), "welded")
	TEST_ASSERT("It has been welded shut." in caps_examine(A, H), "examine says welded")
	cap_weld_toggle(A, H, null)
	TEST_ASSERT(!is_welded(A), "unwelded")

	A.lock()
	var/datum/interaction/capability/pry = cap_test_entry(A, "pry:[TOOL_CROWBAR]:[I_HELP]")
	TEST_ASSERT_NOTNULL(pry, "the airlock has a pry entry")
	TEST_ASSERT_NOTNULL(pry.why_not(H, A, bar), "prying a bolted airlock is refused")
	var/reason = cap_pry_reason(H, A, bar)
	TEST_ASSERT(istext(reason), "the airlock gives a reason ([reason])")
	if(!A.arePowerSystemsOn())
		TEST_ASSERT_EQUAL(reason, "the airlock's bolts prevent it from being forced", "unpowered, the bolts refuse")

/// Electrification is a timed_set value: it reverts on its own, and before_entry shocks while it holds.
/datum/unit_test/dx_airlock_electrify/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/door/airlock/dx_test/A = allocate(/obj/machinery/door/airlock/dx_test, T)
	var/datum/interaction/capability/pry = cap_test_entry(A, "pry:[TOOL_CROWBAR]:[I_HELP]")
	TEST_ASSERT(A.before_entry(H, pry, null), "not electrified: no shock")
	timed_set(A, nameof(A.electrified_until), 1, for_time = 30 SECONDS, clock = CLOCK_WORLD, revert_to = 0)
	TEST_ASSERT(A.isElectrified(), "electrified")
	TEST_ASSERT(electrified_left(A) > 0, "with time left ([electrified_left(A)])")
	TEST_ASSERT(!A.before_entry(H, pry, null), "touching it shocks and stops the entry")
	TEST_ASSERT_EQUAL(A.shocks, 1, "one shock")
	var/list/pending = A.timed_until[nameof(A.electrified_until)]
	TEST_ASSERT_NOTNULL(pending, "a revert is pending")
	timed_expire(A, nameof(A.electrified_until), pending[1])
	TEST_ASSERT(!A.isElectrified(), "the electrification reverted")
	TEST_ASSERT(A.before_entry(H, pry, null), "and touching it is safe again")

/// The AiAirlock window's actions are act_<action> procs: the TSX's hyphenated names reach them.
/datum/unit_test/dx_airlock_ai_actions/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/door/airlock/dx_test/A = allocate(/obj/machinery/door/airlock/dx_test, T)
	var/datum/tgui/ui = ui_test_window(A)
	ui.user = H
	TEST_ASSERT(!hascall(A, "act_bolt_toggle"), "the airlock writes no action of its own: cap_ai_control() owns them")
	TEST_ASSERT(A.tgui_act("bolt-toggle", list(), ui), "bolt-toggle ran")
	TEST_ASSERT(is_bolted(A), "the bolts dropped")
	var/was_lights = A.lights
	TEST_ASSERT(A.tgui_act("light-toggle", list(), ui), "light-toggle ran")
	TEST_ASSERT_EQUAL(A.lights, !was_lights, "the bolt lights toggled")
	TEST_ASSERT(A.tgui_act("emergency-toggle", list(), ui), "emergency-toggle ran")
	TEST_ASSERT(emergency_access_on(A), "emergency access engaged")
	var/list/data = dx_flat_caps_data(A, H)
	TEST_ASSERT_EQUAL(data["bolted"], TRUE, "the window sees the bolts")
	TEST_ASSERT_EQUAL(data["emergency"], TRUE, "and emergency access")
	TEST_ASSERT_NOTNULL(data["wires"], "and the wires")

/// draw(): the closed state follows the bolts, the lights and the power; welding and the frost draw.
/datum/unit_test/dx_airlock_draw/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/machinery/door/airlock/A = allocate(/obj/machinery/door/airlock, run_loc_floor_bottom_left)
	refresh_flush()
	TEST_ASSERT_EQUAL(A.icon_state, "door_closed", "a closed airlock draws door_closed")
	A.lock()
	refresh_flush()
	TEST_ASSERT_EQUAL(A.icon_state, A.arePowerSystemsOn() ? "door_locked" : "door_closed", "the bolt lights show while powered")
	A.frozen = TRUE
	changed(A)
	refresh_flush()
	TEST_ASSERT(look_image('icons/turf/overlays.dmi', "snowairlock") in A.look_overlays, "the frost is drawn from the turf overlays")
	A.frozen = FALSE
	changed(A)
	cap_weld_toggle(A, H, null)
	refresh_flush()
	TEST_ASSERT(!(look_image('icons/turf/overlays.dmi', "snowairlock") in A.look_overlays), "the frost is gone")
	TEST_ASSERT(cap_test_has_layer(A, "welded"), "the welded layer is drawn")

/// door(): the bundle lists the parts, in order, with the variations its named args pick; the wires
/// sit behind the panel.
/datum/unit_test/dx_cap_doors_bundle/Run()
	var/list/plain = door()
	var/list/plain_types = list()
	for(var/datum/capability/C as anything in plain)
		plain_types += C.type
	for(var/path in list(/datum/capability/panel, /datum/capability/lock/door, /datum/capability/breakable, /datum/capability/emag, /datum/capability/bolts, /datum/capability/weld_shut, /datum/capability/pry, /datum/capability/emergency_access, /datum/capability/crush, /datum/capability/door_timing))
		TEST_ASSERT(path in plain_types, "a plain door has [path]")
	for(var/path in list(/datum/capability/wires, /datum/capability/electrify, /datum/capability/ai_control))
		TEST_ASSERT(!(path in plain_types), "a plain door has no [path]")
	TEST_ASSERT_EQUAL(plain_types[1], /datum/capability/panel, "the panel comes first")

	var/list/full = door(wires = /datum/wires/airlock, electrify = TRUE, ai_control = TRUE, crush_damage = 7)
	var/datum/capability/wires/W
	var/datum/capability/crush/K
	var/found_electrify = FALSE
	var/found_ai = FALSE
	for(var/datum/capability/C as anything in full)
		if(istype(C, /datum/capability/wires))
			W = C
		else if(istype(C, /datum/capability/crush))
			K = C
		else if(istype(C, /datum/capability/electrify))
			found_electrify = TRUE
		else if(istype(C, /datum/capability/ai_control))
			found_ai = TRUE
	TEST_ASSERT_NOTNULL(W, "wires = adds the wiring")
	TEST_ASSERT(W.behind & PANEL, "behind the panel")
	TEST_ASSERT(found_electrify, "electrify = TRUE adds cap_electrify()")
	TEST_ASSERT(found_ai, "ai_control = TRUE adds cap_ai_control()")
	TEST_ASSERT_EQUAL(K.damage, 7, "crush_damage = reaches cap_crush()")

/// cap_crush() crushes what stands in the door; cap_door_timing() picks the autoclose wait.
/datum/unit_test/dx_cap_doors_crush_and_timing/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/machinery/door/airlock/A = allocate(/obj/machinery/door/airlock, T)
	TEST_ASSERT(!door_crush(A), "nothing to crush in an empty doorway")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT(door_crush(A), "a human in the doorway is crushed")
	TEST_ASSERT(H.status_units(EFFECT_STUNNED) > 0, "and stunned")
	for(var/obj/effect/decal/cleanable/mess in T)
		qdel(mess)
	TEST_ASSERT_EQUAL(door_safeties_on(A), TRUE, "the safeties start on")
	var/list/data = dx_flat_caps_data(A, H)
	TEST_ASSERT_EQUAL(data["safe"], TRUE, "the window sees the safeties")

	A.normalspeed = FALSE
	TEST_ASSERT_EQUAL(A.next_close_wait(), 0.5 SECONDS, "at high speed the door closes fast")
	A.normalspeed = TRUE
	var/wait = A.next_close_wait()
	TEST_ASSERT(wait == 15 SECONDS || wait == 1.5 SECONDS, "at normal speed it waits the normal or thermal time ([wait])")
