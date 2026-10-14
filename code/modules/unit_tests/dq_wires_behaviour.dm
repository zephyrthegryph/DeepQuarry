// Behaviour-preservation tests for wires: the wire mechanics every holder shares (the layout per round, duds, cut, mend, pulse, the signaler) and
// each holder's wire effects that no other test pins. Written against the legacy wire datums and kept passing through the conversion to the wires
// library: only the adapter block below names the wire API, so after the conversion only its bodies change.
//
// Covered elsewhere (and not repeated here): the APC (dq_p2_apc_behaviour), the airlock (interim_airlock_*, dq_p2_door_behaviour), the vendor
// (dq_p2_vending_behaviour), the SMES (dq_p2_smes_behaviour), the jukebox and the grid checker (interim_wire_actor), the air alarm, the camera,
// the lathes, the particle accelerator and the RIG (interim_*_wire_actor).

// ---------------------------------------------------------------------------------------------------------------------
// Adapters: today's wire API, wrapped. After the conversion only these bodies change.
// ---------------------------------------------------------------------------------------------------------------------

/// The interactive cut: cuts an intact wire, mends a cut one (the window's cut button).
/proc/wbt_cut(atom/H, wire, mob/user)
	wires_toggle(H, wire, user)

/proc/wbt_pulse(atom/H, wire, mob/user)
	wires_pulse(H, wire, user)

/proc/wbt_is_cut(atom/H, wire)
	return !!wire_is_cut(H, wire)

/// Every wire of the holder, duds included.
/proc/wbt_all(atom/H)
	return wires_all(H)

/// The holder's colour layout: colour -> wire.
/proc/wbt_layout(atom/H)
	return wires_layout(H)

/proc/wbt_cut_all(atom/H)
	return wires_cut_all(H)

/proc/wbt_mend_all(atom/H)
	return wires_mend_all(H)

/proc/wbt_all_cut(atom/H)
	return !!wires_all_cut(H)

/proc/wbt_attach(atom/H, color, obj/item/assembly/signaler/S)
	return wire_attach_signaler(H, color, S)

/proc/wbt_detach(atom/H, color)
	return wire_detach_signaler(H, color)

/proc/wbt_attached(atom/H, color)
	return wire_signaler_at(H, color)

/// The colour of `wire` in the holder's layout.
/proc/wbt_color_of(atom/H, wire)
	var/list/layout = wbt_layout(H)
	for(var/color in layout)
		if(layout[color] == wire)
			return color
	return null

/proc/wbt_is_dud(wire)
	return findtext(wire, WIRE_DUD_PREFIX) == 1

// ---------------------------------------------------------------------------------------------------------------------
// Probes
// ---------------------------------------------------------------------------------------------------------------------

/obj/machinery/power/tesla_coil/wbt_probe
	var/zaps = 0

/obj/machinery/power/tesla_coil/wbt_probe/zap(power, explosive, current_jumps)
	zaps++

/obj/item/plastique/wbt_probe
	var/explosions = 0

/obj/item/plastique/wbt_probe/explode(location)
	explosions++

/obj/machinery/smartfridge/wbt_probe
	var/shocks = 0

/obj/machinery/smartfridge/wbt_probe/shock(mob/user, prb)
	shocks++
	return FALSE

/obj/machinery/smartfridge/secure/wbt_probe

/obj/machinery/suit_cycler/wbt_probe
	var/shocks = 0

/obj/machinery/suit_cycler/wbt_probe/shock(mob/user, prb)
	shocks++
	return FALSE

// ---------------------------------------------------------------------------------------------------------------------
// The shared mechanics
// ---------------------------------------------------------------------------------------------------------------------

/// Each holder has its wire count: the wires that do something plus duds, every one with its own colour.
/datum/unit_test/dq_wires_counts_and_duds
/datum/unit_test/dq_wires_counts_and_duds/Run()
	var/turf/T = test_floor()
	var/list/expect = list(
		/obj/machinery/power/tesla_coil = list(1, 1),
		/obj/machinery/smartfridge = list(3, 3),
		/obj/machinery/smartfridge/secure = list(4, 3),
		/obj/machinery/suit_cycler = list(3, 3),
		/obj/machinery/power/shield_generator = list(5, 4),
		/obj/item/radio = list(3, 3),
		/obj/structure/disposalpipe/sortjunction = list(6, 3),
		/obj/item/plastique = list(1, 1),
		/obj/machinery/seed_storage = list(4, 4),
		/obj/machinery/media/jukebox = list(11, 9),
		/obj/machinery/power/grid_checker = list(8, 6),
		/obj/machinery/alarm = list(5, 5),
		/obj/machinery/autolathe = list(6, 3),
		/obj/machinery/camera = list(6, 4),
		/obj/machinery/vending = list(4, 4),
		/obj/machinery/door/airlock = list(12, 12),
	)
	for(var/path in expect)
		var/atom/H = allocate(path, T)
		var/list/all = wbt_all(H)
		var/list/layout = wbt_layout(H)
		TEST_ASSERT_EQUAL(length(all), expect[path][1], "[path] has its wire count")
		TEST_ASSERT_EQUAL(length(layout), expect[path][1], "[path]: every wire has a colour")
		var/real = 0
		for(var/wire in all)
			if(!wbt_is_dud(wire))
				real++
		TEST_ASSERT_EQUAL(real, expect[path][2], "[path] has its working wires, the rest duds")

/// A holder that does not randomize shares its type's colour layout for the round; one that randomizes has its own.
/datum/unit_test/dq_wires_layout_per_round
/datum/unit_test/dq_wires_layout_per_round/Run()
	var/turf/T = test_floor()
	var/obj/machinery/vending/V1 = allocate(/obj/machinery/vending, T)
	var/obj/machinery/vending/V2 = allocate(/obj/machinery/vending, T)
	TEST_ASSERT(V1 != V2, "two vendors")
	var/list/l1 = wbt_layout(V1)
	var/list/l2 = wbt_layout(V2)
	for(var/color in l1)
		TEST_ASSERT_EQUAL(l2[color], l1[color], "two vendors share the round's layout ([color])")
	var/obj/machinery/door/airlock/D1 = allocate(/obj/machinery/door/airlock, T)
	var/obj/machinery/door/airlock/D2 = allocate(/obj/machinery/door/airlock, T)
	var/list/d1 = wbt_layout(D1)
	var/list/d2 = wbt_layout(D2)
	for(var/color in d1)
		TEST_ASSERT_EQUAL(d2[color], d1[color], "two airlocks share the round's layout ([color])")
	// the seed storage randomizes: two of them (four wires, fourteen colours) almost never match; ten pairs never do by chance
	var/differ = FALSE
	for(var/i in 1 to 10)
		var/obj/machinery/seed_storage/S1 = allocate(/obj/machinery/seed_storage, T)
		var/obj/machinery/seed_storage/S2 = allocate(/obj/machinery/seed_storage, T)
		var/list/s1 = wbt_layout(S1)
		var/list/s2 = wbt_layout(S2)
		for(var/color in s1)
			if(s2[color] != s1[color])
				differ = TRUE
		for(var/color in s2)
			if(s2[color] != s1[color])
				differ = TRUE
		if(differ)
			break
	TEST_ASSERT(differ, "a randomized holder has its own layout")
	// a layout stays put for the holder's life
	var/list/again = wbt_layout(V1)
	for(var/color in l1)
		TEST_ASSERT_EQUAL(again[color], l1[color], "the layout does not change between reads")

/// The interactive cut toggles; a pulse on a cut wire does nothing; cut-all and mend-all change each wire once.
/datum/unit_test/dq_wires_cut_mend_pulse
/datum/unit_test/dq_wires_cut_mend_pulse/Run()
	var/turf/T = test_floor()
	var/obj/machinery/power/tesla_coil/wbt_probe/coil = allocate(/obj/machinery/power/tesla_coil/wbt_probe, T)
	TEST_ASSERT(!wbt_is_cut(coil, WIRE_TESLACOIL_ZAP), "starts intact")
	wbt_pulse(coil, WIRE_TESLACOIL_ZAP)
	TEST_ASSERT_EQUAL(coil.zaps, 1, "a pulse on the zap wire zaps")
	wbt_cut(coil, WIRE_TESLACOIL_ZAP)
	TEST_ASSERT(wbt_is_cut(coil, WIRE_TESLACOIL_ZAP), "the cut button cuts an intact wire")
	TEST_ASSERT(wbt_all_cut(coil), "its only wire is cut")
	wbt_pulse(coil, WIRE_TESLACOIL_ZAP)
	TEST_ASSERT_EQUAL(coil.zaps, 1, "a cut wire takes no pulse")
	wbt_cut(coil, WIRE_TESLACOIL_ZAP)
	TEST_ASSERT(!wbt_is_cut(coil, WIRE_TESLACOIL_ZAP), "the cut button mends a cut wire")
	var/obj/machinery/suit_cycler/wbt_probe/cycler = allocate(/obj/machinery/suit_cycler/wbt_probe, T)
	TEST_ASSERT_EQUAL(wbt_cut_all(cycler), 3, "cut-all cuts every intact wire")
	TEST_ASSERT(wbt_all_cut(cycler), "every wire is cut")
	TEST_ASSERT_EQUAL(wbt_cut_all(cycler), 0, "a second cut-all changes nothing")
	TEST_ASSERT_EQUAL(wbt_mend_all(cycler), 3, "mend-all mends every cut wire")
	TEST_ASSERT(!wbt_all_cut(cycler) && !wbt_is_cut(cycler, WIRE_SAFETY), "the wires are whole again")
	TEST_ASSERT_EQUAL(wbt_mend_all(cycler), 0, "a second mend-all changes nothing")

/// A signaler on a wire pulses it when it goes off; taking it off drops it out of the holder.
/datum/unit_test/dq_wires_signaler
/datum/unit_test/dq_wires_signaler/Run()
	var/turf/T = test_floor()
	var/obj/machinery/power/tesla_coil/wbt_probe/coil = allocate(/obj/machinery/power/tesla_coil/wbt_probe, T)
	var/obj/item/assembly/signaler/S = allocate(/obj/item/assembly/signaler, T)
	var/color = wbt_color_of(coil, WIRE_TESLACOIL_ZAP)
	TEST_ASSERT(color, "the zap wire has a colour")
	TEST_ASSERT(wbt_attach(coil, color, S), "the signaler goes on the wire")
	TEST_ASSERT_EQUAL(S.loc, coil, "the attached signaler sits in the holder")
	TEST_ASSERT_EQUAL(wbt_attached(coil, color), S, "it is the wire's signaler")
	var/obj/item/assembly/signaler/S2 = allocate(/obj/item/assembly/signaler, T)
	TEST_ASSERT(!wbt_attach(coil, color, S2), "a wire takes one signaler")
	S.pulse(0)
	TEST_ASSERT_EQUAL(coil.zaps, 1, "the signal pulses its wire")
	wbt_cut(coil, WIRE_TESLACOIL_ZAP)
	S.pulse(0)
	TEST_ASSERT_EQUAL(coil.zaps, 1, "a signal on a cut wire does nothing")
	wbt_cut(coil, WIRE_TESLACOIL_ZAP)
	TEST_ASSERT_EQUAL(wbt_detach(coil, color), S, "the signaler comes off")
	TEST_ASSERT_EQUAL(S.loc, T, "a detached signaler drops beside the holder")
	TEST_ASSERT_NULL(wbt_attached(coil, color), "the wire is free")
	S.pulse(0)
	TEST_ASSERT_EQUAL(coil.zaps, 1, "a detached signaler pulses nothing")
	var/obj/item/assembly/signaler/S3 = allocate(/obj/item/assembly/signaler, T)
	wbt_attach(coil, color, S3)
	qdel(coil)
	TEST_ASSERT(!QDELETED(S3) && S3.loc == T, "a deleted holder drops its signalers")

// ---------------------------------------------------------------------------------------------------------------------
// Each holder's effects
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_wires_smartfridge
/datum/unit_test/dq_wires_smartfridge/Run()
	var/turf/T = test_floor()
	var/obj/machinery/smartfridge/wbt_probe/F = allocate(/obj/machinery/smartfridge/wbt_probe, T)
	TEST_ASSERT(!F.shoot_inventory && !stat_value(F, STAT_ELECTRIFIED) && F.scan_id, "a quiet fridge that scans")
	wbt_pulse(F, WIRE_THROW_ITEM)
	TEST_ASSERT(F.shoot_inventory, "the throw wire pulsed starts it throwing")
	wbt_pulse(F, WIRE_THROW_ITEM)
	TEST_ASSERT(!F.shoot_inventory, "pulsed again it stops")
	wbt_pulse(F, WIRE_ELECTRIFY)
	TEST_ASSERT(stat_value(F, STAT_ELECTRIFIED), "the shock wire pulsed electrifies it (a 30 s hold)")
	wbt_pulse(F, WIRE_IDSCAN)
	TEST_ASSERT(!F.scan_id, "the ID wire pulsed stops the scan")
	wbt_cut(F, WIRE_IDSCAN)
	TEST_ASSERT(F.scan_id, "the ID wire cut puts the scan back")
	wbt_cut(F, WIRE_THROW_ITEM)
	TEST_ASSERT(F.shoot_inventory, "the throw wire cut throws")
	wbt_cut(F, WIRE_THROW_ITEM)
	TEST_ASSERT(!F.shoot_inventory, "mended it stops")
	wbt_cut(F, WIRE_ELECTRIFY)
	TEST_ASSERT(stat_value(F, STAT_ELECTRIFIED), "the shock wire cut electrifies it for good")
	wbt_cut(F, WIRE_ELECTRIFY)
	TEST_ASSERT(!stat_value(F, STAT_ELECTRIFIED), "mended it is safe")

/datum/unit_test/dq_wires_seed_storage
/datum/unit_test/dq_wires_seed_storage/Run()
	var/turf/T = test_floor()
	var/obj/machinery/seed_storage/S = allocate(/obj/machinery/seed_storage, T)
	var/smart = S.smart
	wbt_pulse(S, WIRE_SEED_SMART)
	TEST_ASSERT_EQUAL(S.smart, !smart, "the smart wire pulsed toggles smart mode")
	wbt_cut(S, WIRE_SEED_SMART)
	TEST_ASSERT(!S.smart, "the smart wire cut turns smart mode off")
	wbt_pulse(S, WIRE_CONTRABAND)
	TEST_ASSERT(S.hacked, "the contraband wire pulsed hacks it")
	wbt_cut(S, WIRE_CONTRABAND)
	TEST_ASSERT(S.hacked, "cut it stays hacked")
	wbt_cut(S, WIRE_CONTRABAND)
	TEST_ASSERT(!S.hacked, "mended it is not")
	wbt_pulse(S, WIRE_ELECTRIFY)
	TEST_ASSERT(stat_value(S, STAT_ELECTRIFIED), "the shock wire pulsed electrifies it")
	wbt_cut(S, WIRE_ELECTRIFY)
	TEST_ASSERT(stat_value(S, STAT_ELECTRIFIED), "cut it is live for good")
	wbt_cut(S, WIRE_ELECTRIFY)
	TEST_ASSERT(!stat_value(S, STAT_ELECTRIFIED), "mended it is safe")
	var/lockdown = S.lockdown
	wbt_pulse(S, WIRE_SEED_LOCKDOWN)
	TEST_ASSERT_EQUAL(S.lockdown, !lockdown, "the lockdown wire pulsed toggles the lock")

/datum/unit_test/dq_wires_suit_cycler
/datum/unit_test/dq_wires_suit_cycler/Run()
	var/turf/T = test_floor()
	var/obj/machinery/suit_cycler/wbt_probe/C = allocate(/obj/machinery/suit_cycler/wbt_probe, T)
	var/safeties = C.safeties
	wbt_pulse(C, WIRE_SAFETY)
	TEST_ASSERT_EQUAL(C.safeties, !safeties, "the safety wire pulsed toggles the safeties")
	wbt_cut(C, WIRE_SAFETY)
	TEST_ASSERT(!C.safeties, "the safety wire cut drops the safeties")
	wbt_cut(C, WIRE_SAFETY)
	TEST_ASSERT(C.safeties, "mended they are back")
	wbt_pulse(C, WIRE_ELECTRIFY)
	TEST_ASSERT(stat_value(C, STAT_ELECTRIFIED), "the shock wire pulsed electrifies it")
	wbt_cut(C, WIRE_ELECTRIFY)
	TEST_ASSERT(stat_value(C, STAT_ELECTRIFIED), "cut it is live for good")
	wbt_cut(C, WIRE_ELECTRIFY)
	TEST_ASSERT(!stat_value(C, STAT_ELECTRIFIED), "mended it is safe")
	var/locked = C.locked
	wbt_pulse(C, WIRE_IDSCAN)
	TEST_ASSERT_EQUAL(C.locked, !locked, "the ID wire pulsed toggles the lock")
	wbt_cut(C, WIRE_IDSCAN)
	TEST_ASSERT(!C.locked, "the ID wire cut unlocks it")
	wbt_cut(C, WIRE_IDSCAN)
	TEST_ASSERT(C.locked, "mended it locks")

/datum/unit_test/dq_wires_shield_generator
/datum/unit_test/dq_wires_shield_generator/Run()
	var/turf/T = test_floor()
	var/obj/machinery/power/shield_generator/S = allocate(/obj/machinery/power/shield_generator, T)
	wbt_cut(S, WIRE_MAIN_POWER1)
	TEST_ASSERT(S.input_cut, "the power wire cut cuts the input")
	wbt_cut(S, WIRE_MAIN_POWER1)
	TEST_ASSERT(!S.input_cut, "mended the input is back")
	wbt_pulse(S, WIRE_CONTRABAND)
	TEST_ASSERT(S.hacked, "the contraband wire pulsed hacks it")
	wbt_cut(S, WIRE_CONTRABAND)
	TEST_ASSERT(!S.hacked, "cut the hack is gone")
	wbt_cut(S, WIRE_CONTRABAND)
	wbt_cut(S, WIRE_SHIELD_CONTROL)
	TEST_ASSERT(S.mode_changes_locked, "the control wire cut locks the modes")
	wbt_cut(S, WIRE_SHIELD_CONTROL)
	TEST_ASSERT(!S.mode_changes_locked, "mended they unlock")
	wbt_cut(S, WIRE_AI_CONTROL)
	TEST_ASSERT(S.ai_control_disabled, "the AI wire cut locks the AI out")
	wbt_cut(S, WIRE_AI_CONTROL)
	TEST_ASSERT(!S.ai_control_disabled, "mended the AI is back")

/datum/unit_test/dq_wires_radio
/datum/unit_test/dq_wires_radio/Run()
	var/turf/T = test_floor()
	var/obj/item/radio/R = allocate(/obj/item/radio, T)
	R.listening = TRUE
	R.broadcasting = FALSE
	wbt_pulse(R, WIRE_RADIO_TRANSMIT)
	TEST_ASSERT(R.broadcasting, "the transmit wire pulsed turns the mic on")
	wbt_pulse(R, WIRE_RADIO_RECEIVER)
	TEST_ASSERT(!R.listening, "the receiver wire pulsed turns the speaker off")
	wbt_cut(R, WIRE_RADIO_SIGNAL)
	TEST_ASSERT(!R.listening && !R.broadcasting, "the signal wire cut kills both")
	wbt_pulse(R, WIRE_RADIO_RECEIVER)
	TEST_ASSERT(!R.listening, "with the signal wire cut the speaker stays off")
	wbt_cut(R, WIRE_RADIO_SIGNAL)
	TEST_ASSERT(R.listening && R.broadcasting, "mended both come back")
	wbt_cut(R, WIRE_RADIO_TRANSMIT)
	TEST_ASSERT(!R.broadcasting, "the transmit wire cut kills the mic")
	TEST_ASSERT(wbt_is_cut(R, WIRE_RADIO_TRANSMIT), "the transmit wire reads cut")

/datum/unit_test/dq_wires_sort_junction
/datum/unit_test/dq_wires_sort_junction/Run()
	var/turf/T = test_floor()
	var/obj/structure/disposalpipe/sortjunction/J = allocate(/obj/structure/disposalpipe/sortjunction, T)
	J.sort_scan = TRUE
	wbt_pulse(J, WIRE_SORT_FORWARD)
	TEST_ASSERT(!J.last_sort, "the forward wire pulsed sends things forward")
	wbt_pulse(J, WIRE_SORT_SIDE)
	TEST_ASSERT(J.last_sort, "the side wire pulsed sends things aside")
	wbt_cut(J, WIRE_SORT_SCAN)
	TEST_ASSERT(!J.sort_scan, "the scan wire cut freezes the sorter")
	wbt_cut(J, WIRE_SORT_SCAN)
	TEST_ASSERT(J.sort_scan, "mended it scans again")
	wbt_pulse(J, WIRE_SORT_SCAN)
	TEST_ASSERT(!J.sort_scan, "the scan wire pulsed freezes it for a while")

/datum/unit_test/dq_wires_plastique
/datum/unit_test/dq_wires_plastique/Run()
	var/turf/T = test_floor()
	var/obj/item/plastique/wbt_probe/P = allocate(/obj/item/plastique/wbt_probe, T)
	wbt_pulse(P, WIRE_EXPLODE)
	TEST_ASSERT_EQUAL(P.explosions, 1, "the charge's wire pulsed sets it off")
	wbt_cut(P, WIRE_EXPLODE)
	TEST_ASSERT_EQUAL(P.explosions, 2, "cut it goes off too")
	wbt_cut(P, WIRE_EXPLODE)
	TEST_ASSERT_EQUAL(P.explosions, 2, "mended it does not")

/datum/unit_test/dq_wires_rnd
/datum/unit_test/dq_wires_rnd/Run()
	var/turf/T = test_floor()
	var/obj/machinery/rnd/destructive_analyzer/R = allocate(/obj/machinery/rnd/destructive_analyzer, T)
	TEST_ASSERT_EQUAL(length(wbt_all(R)), 8, "an R&D machine has three wires and five duds")
	wbt_pulse(R, WIRE_HACK)
	TEST_ASSERT(R.hacked, "the hack wire pulsed hacks it")
	wbt_pulse(R, WIRE_HACK)
	TEST_ASSERT(!R.hacked, "pulsed again it is not")
	wbt_cut(R, WIRE_DISABLE)
	TEST_ASSERT(R.disabled, "the disable wire cut disables it")
	wbt_cut(R, WIRE_DISABLE)
	TEST_ASSERT(!R.disabled, "mended it works")

// ---------------------------------------------------------------------------------------------------------------------
// The holder tests' adapter: what the legacy wire datum answered (cut(), pulse(), is_cut(), interactable()), over the library.
// ---------------------------------------------------------------------------------------------------------------------

/// Holder -> the mobs a wires window was opened for (recorded: a test mob has no client).
GLOBAL_LIST_EMPTY(wires_test_opened)

/datum/cap_data/wires/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, custom_state)
	if(owner)
		var/list/opened = GLOB.wires_test_opened[owner]
		if(!opened)
			opened = list()
			GLOB.wires_test_opened[owner] = opened
		opened += user
	return ..()

/datum/wires_test_adapter
	var/atom/holder

/datum/wires_test_adapter/New(atom/holder)
	src.holder = holder

/datum/wires_test_adapter/proc/cut(wire, mob/user)
	wires_toggle(holder, wire, user)

/datum/wires_test_adapter/proc/pulse(wire, mob/user)
	wires_pulse(holder, wire, user)

/datum/wires_test_adapter/proc/is_cut(wire)
	return wire_is_cut(holder, wire)

/datum/wires_test_adapter/proc/cut_all()
	return wires_cut_all(holder)

/datum/wires_test_adapter/proc/interactable(mob/user)
	var/datum/cap_data/wires/W = wiring_of(holder)
	return W && isnull(W.reach_reason(user))

/// The mobs the holder's wires window was opened for.
/datum/wires_test_adapter/proc/opened_for()
	return GLOB.wires_test_opened[holder] || list()

/// The adapter of a holder with wires, or null.
/proc/wires_test(atom/H)
	RETURN_TYPE(/datum/wires_test_adapter)
	return wiring_of(H) ? new /datum/wires_test_adapter(H) : null

/datum/wires_test_adapter/proc/cut_wire(wire, mob/user)
	return wires_cut(holder, wire, user)

/// Every wire, duds included (the legacy datum's `wires`).
/datum/wires_test_adapter/proc/all_wires()
	return wires_all(holder)
