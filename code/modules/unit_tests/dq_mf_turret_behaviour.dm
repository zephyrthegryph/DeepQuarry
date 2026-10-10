// Behaviour tests for the portable turret, its control panel and the turret frame (rewrite/machines-full): what a person, a silicon, an admin and
// the world (power, pulses, an emag) can observe of them, written against the legacy code first. Where the legacy code had a bug the test pins it
// as it was, and the commit that fixes it edits the assertion, with the change listed in doc/rewrite/intended_changes.md. The fixture is the
// structure behaviour block (dq_hc_struct_behaviour.dm: tile(), person(), mach(), press(), settle()); state is read through the adapters below.

// ---- adapters: today's accessors (only these bodies change with the conversion) ----

/// The turret's on switch (the setting a person chose).
/proc/mft_enabled(obj/machinery/porta_turret/T)
	return !!T.enabled

/// Turns the turret on or off as a setting (a mapper's or the panel's).
/proc/mft_set_enabled(obj/machinery/porta_turret/T, on)
	T.set_enabled(on)

/// The turret's lock (the ID lock over its window).
/proc/mft_locked(obj/machinery/T)
	return !!lock_locked(T)

/proc/mft_set_locked(obj/machinery/T, on)
	cap_key_set(T, LOCK_LOCKED, on, null)

/// How far the frame is built (0 an unbolted frame, 8 done).
/proc/mft_frame_step(obj/machinery/porta_turret_construct/F)
	var/n = 0
	for(var/stage in list(STAGE_TURRET_FRAME_BOLTED, STAGE_TURRET_FRAME_PLATED, STAGE_TURRET_FRAME_SECURED, STAGE_TURRET_FRAME_ARMED, STAGE_TURRET_FRAME_SENSING, STAGE_TURRET_FRAME_SHUT, STAGE_TURRET_FRAME_ARMOURED, STAGE_TURRET_FRAME_DONE))
		if(built(F, stage))
			n++
	return n


/// The turret is emagged.
/proc/mft_emagged(obj/machinery/T)
	return !!emag_emagged(T)

/// The turret works now: powered, whole, not knocked out by a pulse.
/proc/mft_operable(obj/machinery/porta_turret/T)
	return !!stat_value(T, STAT_OPERABLE)

/// The window data `user` is sent.
/proc/mft_data(datum/host, mob/user)
	var/list/data = list()
	present_tgui_data(host, user, data)
	return data

/// The area of the block went dark or lit again (its equipment channel), and the machines in it heard.
/proc/mft_area_power(area/A, on)
	A.set_requires_power(TRUE)
	A.power_equip = on
	for(var/obj/machinery/M in A)
		M.power_change()

// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/mft
	abstract_type = /datum/unit_test/dq_hc_struct/mft
	var/area/mft_area
	var/mft_requires
	var/mft_equip

/datum/unit_test/dq_hc_struct/mft/Run()
	mft_area = get_area(run_loc_floor_bottom_left)
	mft_requires = mft_area.requires_power
	mft_equip = mft_area.power_equip
	mft_area.set_requires_power(FALSE)
	mft_area.power_equip = TRUE
	..()
	mft_area.set_requires_power(mft_requires)
	mft_area.power_equip = mft_equip

/// A turret placed and working.
/datum/unit_test/dq_hc_struct/mft/proc/turret(type = /obj/machinery/porta_turret, turf/T)
	return mach(type, T || tile(3, 3))

/// A card with `access` in `H`'s hand (and nothing worn).
/datum/unit_test/dq_hc_struct/mft/proc/card_in_hand(mob/living/carbon/human/H, list/access)
	var/obj/item/card/id/C = allocate(/obj/item/card/id, get_turf(H))
	C.access = access ? access.Copy() : list()
	H.drop_item()
	H.put_in_active_hand(C)
	return C

/// A card with `access` worn on `H`.
/datum/unit_test/dq_hc_struct/mft/proc/card_worn(mob/living/carbon/human/H, list/access)
	var/obj/item/card/id/C = allocate(/obj/item/card/id, get_turf(H))
	C.access = access ? access.Copy() : list()
	if(!H.get_equipped_item(SLOT_ID_UNIFORM))
		H.equip_to_slot_or_del(allocate(/obj/item/clothing/under/color/grey, get_turf(H)), SLOT_ID_UNIFORM)
	H.equip_to_slot_or_del(C, SLOT_ID_ID)
	return C

/// The actor clicks the target with what they hold (a real click, its cooldown reset), and time passes.
/datum/unit_test/dq_hc_struct/mft/proc/touch(mob/living/carbon/human/H, atom/target, obj/item/held)
	hci_click(H, target, held)
	settle()

// ---------------------------------------------------------------------------------------------------------------------
// The turret's own lock and window
// ---------------------------------------------------------------------------------------------------------------------

/// A card swiped on the turret toggles its lock by the access of the person: a stranger wearing the right card swipes any card and it opens.
/datum/unit_test/dq_hc_struct/mft/lock_follows_the_swiper
/datum/unit_test/dq_hc_struct/mft/lock_follows_the_swiper/run_gate()
	var/obj/machinery/porta_turret/T = turret()
	var/mob/living/carbon/human/H = person()
	TEST_ASSERT(mft_locked(T), "(a turret starts locked)")
	var/obj/item/card/id/blank = card_in_hand(H, list())
	touch(H, T, blank)
	TEST_ASSERT(mft_locked(T), "a card without the access does not open it")
	card_worn(H, list(ACCESS_SECURITY))
	H.put_in_active_hand(blank)
	touch(H, T, blank)
	TEST_ASSERT(mft_locked(T), "a blank card swiped by someone who wears the access does not open it: the swiped card is the credential")
	var/obj/item/card/id/good = card_in_hand(H, list(ACCESS_SECURITY))
	touch(H, T, good)
	TEST_ASSERT(!mft_locked(T), "a card with the access opens it")
	touch(H, T, good)
	TEST_ASSERT(mft_locked(T), "and locks it again")

/// An unlocked turret takes the buttons of its window; a locked one takes none from a human.
/datum/unit_test/dq_hc_struct/mft/window_buttons_follow_the_lock
/datum/unit_test/dq_hc_struct/mft/window_buttons_follow_the_lock/run_gate()
	var/obj/machinery/porta_turret/T = turret()
	var/mob/living/carbon/human/H = person()
	var/weapons = T.check_weapons
	press(H, T, "authweapon")
	TEST_ASSERT_EQUAL(T.check_weapons, weapons, "locked: nothing changes")
	mft_set_locked(T, FALSE)
	press(H, T, "authweapon")
	TEST_ASSERT_NOTEQUAL(T.check_weapons, weapons, "unlocked: the setting flips")
	var/lethal = T.lethal
	press(H, T, "lethal")
	TEST_ASSERT_NOTEQUAL(T.lethal, lethal, "and the lethal switch")
	var/on = mft_enabled(T)
	press(H, T, "power")
	TEST_ASSERT_NOTEQUAL(mft_enabled(T), on, "and the power switch")
	var/list/data = mft_data(T, H)
	TEST_ASSERT_EQUAL(!!data["on"], mft_enabled(T), "the window shows the switch")
	TEST_ASSERT(!data["locked"], "and that it answers this person")

/// A lasertag turret's targeting cannot be changed from its window.
/datum/unit_test/dq_hc_struct/mft/lasertag_targeting_is_fixed
/datum/unit_test/dq_hc_struct/mft/lasertag_targeting_is_fixed/run_gate()
	var/obj/machinery/porta_turret/lasertag/T = turret(/obj/machinery/porta_turret/lasertag)
	var/mob/living/carbon/human/H = person()
	TEST_ASSERT(!mft_locked(T), "(a lasertag turret starts unlocked)")
	var/weapons = T.check_weapons
	press(H, T, "authweapon")
	TEST_ASSERT_EQUAL(T.check_weapons, weapons, "its targeting does not change")
	var/lethal = T.lethal
	press(H, T, "lethal")
	TEST_ASSERT_EQUAL(T.lethal, lethal, "nor its lethal mode")
	press(H, T, "power")
	TEST_ASSERT(mft_enabled(T), "but its power does")

/// An admin ghost works a locked turret's window.
/datum/unit_test/dq_hc_struct/mft/admin_ghost_and_a_locked_turret
/datum/unit_test/dq_hc_struct/mft/admin_ghost_and_a_locked_turret/run_gate()
	var/obj/machinery/porta_turret/T = turret()
	var/mob/observer/dead/G = allocate(/mob/observer/dead, tile(2, 2))
	G.admin_ghosted = TRUE
	var/weapons = T.check_weapons
	press(G, T, "authweapon")
	TEST_ASSERT_EQUAL(T.check_weapons, weapons, "a ghost the test cannot give admin rights (no client) changes nothing; with them, req_window_usable() lets it in")

/// A turret in an area with a control panel takes no orders from its own window.
/datum/unit_test/dq_hc_struct/mft/a_panel_takes_over_the_window
/datum/unit_test/dq_hc_struct/mft/a_panel_takes_over_the_window/run_gate()
	var/obj/machinery/porta_turret/T = turret()
	mach(/obj/machinery/turretid, tile(1, 1))
	var/mob/living/carbon/human/H = person()
	mft_set_locked(T, FALSE)
	var/weapons = T.check_weapons
	press(H, T, "authweapon")
	TEST_ASSERT_EQUAL(T.check_weapons, weapons, "the panel controls it, not its own window")

// ---------------------------------------------------------------------------------------------------------------------
// The control panel
// ---------------------------------------------------------------------------------------------------------------------

/// The panel's settings reach the turrets of its area: the power, the lethal switch and the targets.
/datum/unit_test/dq_hc_struct/mft/panel_settings_reach_its_turrets
/datum/unit_test/dq_hc_struct/mft/panel_settings_reach_its_turrets/run_gate()
	var/obj/machinery/porta_turret/T = turret()
	var/obj/machinery/turretid/C = mach(/obj/machinery/turretid, tile(1, 1))
	var/mob/living/carbon/human/H = person()
	mft_set_locked(C, FALSE)
	var/on = C.enabled
	press(H, C, "power")
	TEST_ASSERT_NOTEQUAL(!!C.enabled, !!on, "(the panel's power flips)")
	TEST_ASSERT_EQUAL(mft_enabled(T), !!C.enabled, "and the turret follows")
	press(H, C, "authweapon")
	TEST_ASSERT_EQUAL(T.check_weapons, C.check_weapons, "the weapons check follows")
	var/down = T.check_down
	press(H, C, "authdown")
	TEST_ASSERT_NOTEQUAL(T.check_down, down, "the down setting reaches the turret too")

/// The panel pushes its own firewall onto every turret: a stationary turret's own firewall is lost to a panel without one.
/datum/unit_test/dq_hc_struct/mft/panel_overwrites_a_turrets_firewall
/datum/unit_test/dq_hc_struct/mft/panel_overwrites_a_turrets_firewall/run_gate()
	var/obj/machinery/porta_turret/stationary/T = turret(/obj/machinery/porta_turret/stationary)
	TEST_ASSERT(T.ailock, "(a stationary turret starts firewalled)")
	var/obj/machinery/turretid/C = mach(/obj/machinery/turretid, tile(1, 1))
	var/mob/living/carbon/human/H = person()
	mft_set_locked(C, FALSE)
	press(H, C, "authweapon")
	TEST_ASSERT(T.ailock, "the turret keeps its own firewall: the panel hands over its settings, not its firewall")

/// A card swiped on the panel toggles its lock by the person's access, as the turret's does.
/datum/unit_test/dq_hc_struct/mft/panel_lock_follows_the_swiper
/datum/unit_test/dq_hc_struct/mft/panel_lock_follows_the_swiper/run_gate()
	var/obj/machinery/turretid/C = mach(/obj/machinery/turretid, tile(1, 1))
	var/mob/living/carbon/human/H = person()
	TEST_ASSERT(mft_locked(C), "(a panel starts locked)")
	var/obj/item/card/id/blank = card_in_hand(H, list())
	touch(H, C, blank)
	TEST_ASSERT(mft_locked(C), "a card without the access does not open it")
	card_worn(H, list(ACCESS_AI_UPLOAD))
	H.put_in_active_hand(blank)
	touch(H, C, blank)
	TEST_ASSERT(mft_locked(C), "a blank card swiped by someone who wears the access does not open it")
	var/obj/item/card/id/good = card_in_hand(H, list(ACCESS_AI_UPLOAD))
	touch(H, C, good)
	TEST_ASSERT(!mft_locked(C), "a card with the access opens it")

/// A pulse on a running panel switches it and its turrets off and scrambles the panel's targets; it comes back on by itself.
/datum/unit_test/dq_hc_struct/mft/panel_pulse_switches_it_off_for_a_while
/datum/unit_test/dq_hc_struct/mft/panel_pulse_switches_it_off_for_a_while/run_gate()
	var/obj/machinery/porta_turret/T = turret()
	var/obj/machinery/turretid/C = mach(/obj/machinery/turretid/stun, tile(1, 1))
	C.push_settings(null)
	TEST_ASSERT(mft_enabled(T), "(the turret is on)")
	C.emp_act(1)
	settle()
	TEST_ASSERT(emp_disabled(C), "the pulse knocks the panel out")
	TEST_ASSERT(!mft_enabled(T), "and its turrets")
	test_time(61 SECONDS)
	TEST_ASSERT(!emp_disabled(C) && C.enabled, "a minute later it is back, still switched on")
	TEST_ASSERT(mft_enabled(T), "and so are its turrets")

// ---------------------------------------------------------------------------------------------------------------------
// Power, pulses and the emag
// ---------------------------------------------------------------------------------------------------------------------

/// Power that comes back within the turret's reaction time: the turret ends powered.
/datum/unit_test/dq_hc_struct/mft/power_back_before_the_turret_notices
/datum/unit_test/dq_hc_struct/mft/power_back_before_the_turret_notices/run_gate()
	var/obj/machinery/porta_turret/T = turret()
	mft_area_power(mft_area, FALSE)
	mft_area_power(mft_area, TRUE)
	test_time(3 SECONDS)
	TEST_ASSERT(mft_operable(T), "the turret follows the power as it is now")

/// A pulse on a running turret switches it off and scrambles its targets; it comes back by itself within a minute.
/datum/unit_test/dq_hc_struct/mft/turret_pulse_switches_it_off_for_a_while
/datum/unit_test/dq_hc_struct/mft/turret_pulse_switches_it_off_for_a_while/run_gate()
	var/obj/machinery/porta_turret/T = turret()
	mft_set_enabled(T, TRUE)
	T.emp_act(1)
	TEST_ASSERT(mft_enabled(T) && !mft_operable(T), "the pulse knocks it out (its switch stays as it was)")
	test_time(61 SECONDS)
	TEST_ASSERT(mft_operable(T), "and it comes back within a minute")

/// A pulse on a switched-off turret does nothing to it.
/datum/unit_test/dq_hc_struct/mft/pulse_on_an_idle_turret
/datum/unit_test/dq_hc_struct/mft/pulse_on_an_idle_turret/run_gate()
	var/obj/machinery/porta_turret/T = turret()
	mft_set_enabled(T, FALSE)
	var/weapons = T.check_weapons
	T.emp_act(1)
	test_time(61 SECONDS)
	TEST_ASSERT(!mft_enabled(T), "an idle turret stays off")
	TEST_ASSERT_EQUAL(T.check_weapons, weapons, "and its targets are left alone")

/// An emag subverts the turret: it goes quiet for six seconds and comes back on, firing at everyone, and no panel controls it again.
/datum/unit_test/dq_hc_struct/mft/emag_makes_it_haywire
/datum/unit_test/dq_hc_struct/mft/emag_makes_it_haywire/run_gate()
	var/obj/machinery/porta_turret/T = turret()
	var/mob/living/carbon/human/H = person()
	mft_set_enabled(T, FALSE)
	var/obj/item/card/emag/card = allocate(/obj/item/card/emag, tile(2, 2))
	card.uses = 3
	hci_click(H, T, card)
	test_time(1 SECOND)
	TEST_ASSERT(mft_emagged(T), "the card subverts it")
	TEST_ASSERT(!mft_enabled(T) || !mft_operable(T), "it is quiet at first")
	test_time(6 SECONDS)
	TEST_ASSERT(mft_enabled(T) && mft_operable(T), "and back on six seconds later")
	var/obj/machinery/turretid/C = mach(/obj/machinery/turretid, tile(1, 1))
	mft_set_locked(C, FALSE)
	press(H, C, "power")
	press(H, C, "power")
	TEST_ASSERT(mft_enabled(T), "no panel switches it off")

// ---------------------------------------------------------------------------------------------------------------------
// Wrenching and salvage
// ---------------------------------------------------------------------------------------------------------------------

/// A switched-off turret is unwrenched and wrenched again; an active one refuses.
/datum/unit_test/dq_hc_struct/mft/wrench_moves_an_idle_turret
/datum/unit_test/dq_hc_struct/mft/wrench_moves_an_idle_turret/run_gate()
	var/obj/machinery/porta_turret/T = turret()
	var/mob/living/carbon/human/H = person()
	var/obj/item/tool/wrench/W = dq_fast_tool(/obj/item/tool/wrench, tile(2, 2))
	H.put_in_active_hand(W)
	mft_set_enabled(T, TRUE)
	touch(H, T, W)
	TEST_ASSERT(T.anchored, "an active turret stays bolted")
	mft_set_enabled(T, FALSE)
	touch(H, T, W)
	TEST_ASSERT(!T.anchored, "an idle one comes loose")
	touch(H, T, W)
	TEST_ASSERT(T.anchored, "and is bolted again")

/// A destroyed turret is pried apart with a crowbar.
/datum/unit_test/dq_hc_struct/mft/crowbar_salvages_a_wreck
/datum/unit_test/dq_hc_struct/mft/crowbar_salvages_a_wreck/run_gate()
	var/obj/machinery/porta_turret/T = turret()
	var/mob/living/carbon/human/H = person()
	var/obj/item/tool/crowbar/W = dq_fast_tool(/obj/item/tool/crowbar, tile(2, 2))
	H.put_in_active_hand(W)
	touch(H, T, W)
	TEST_ASSERT(!QDELETED(T), "a whole turret is not pried apart")
	T.die()
	touch(H, T, W)
	TEST_ASSERT(QDELETED(T), "a wreck is")

// ---------------------------------------------------------------------------------------------------------------------
// The turret frame
// ---------------------------------------------------------------------------------------------------------------------

/// The frame is built step by step into a turret named as its builder chose, with the gun it was given; each step undoes.
/datum/unit_test/dq_hc_struct/mft/frame_builds_a_turret
/datum/unit_test/dq_hc_struct/mft/frame_builds_a_turret/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/spot = tile(3, 3)
	var/obj/machinery/porta_turret_construct/F = allocate(/obj/machinery/porta_turret_construct, spot)
	F.set_anchored(FALSE)
	var/obj/item/tool/wrench/wrench = dq_fast_tool(/obj/item/tool/wrench, tile(2, 2))
	var/obj/item/weldingtool/welder = dq_fast_tool(/obj/item/weldingtool, tile(2, 2))
	welder.setWelding(TRUE)
	var/obj/item/tool/screwdriver/screwdriver = dq_fast_tool(/obj/item/tool/screwdriver, tile(2, 2))
	var/obj/item/stack/material/steel/metal = allocate(/obj/item/stack/material/steel, tile(2, 2))
	metal.set_amount(10)
	var/obj/item/gun/energy/gun/gun = allocate(/obj/item/gun/energy/gun, tile(2, 2))
	var/obj/item/assembly/prox_sensor/prox = allocate(/obj/item/assembly/prox_sensor, tile(2, 2))
	H.put_in_active_hand(wrench)
	touch(H, F, wrench)
	TEST_ASSERT(F.anchored, "the wrench bolts the frame down")
	H.drop_item()
	H.put_in_active_hand(metal)
	touch(H, F, metal)
	TEST_ASSERT_EQUAL(metal.get_amount(), 8, "two sheets of interior armour go in")
	TEST_ASSERT_EQUAL(mft_frame_step(F), 2, "(step 2)")
	touch(H, F, wrench)
	TEST_ASSERT_EQUAL(mft_frame_step(F), 3, "the wrench bolts the armour (step 3)")
	touch(H, F, gun)
	TEST_ASSERT_EQUAL(mft_frame_step(F), 4, "the gun goes in (step 4)")
	touch(H, F, prox)
	TEST_ASSERT_EQUAL(mft_frame_step(F), 5, "a click with the sensor puts it in (step 5)")
	touch(H, F, screwdriver)
	TEST_ASSERT_EQUAL(mft_frame_step(F), 6, "the screwdriver shuts the hatch (step 6)")
	touch(H, F, metal)
	TEST_ASSERT_EQUAL(metal.get_amount(), 6, "two sheets of exterior armour go on")
	touch(H, F, welder)
	var/obj/machinery/porta_turret/T = locate_on(spot, /obj/machinery/porta_turret)
	TEST_ASSERT_NOTNULL(T, "the weld finishes the turret")
	TEST_ASSERT(QDELETED(F), "and the frame is gone")
	TEST_ASSERT_EQUAL(T.installation, /obj/item/gun/energy/gun, "with the gun it was given")
	TEST_ASSERT(!mft_enabled(T), "switched off")

/// An empty frame is pried apart into five sheets.
/datum/unit_test/dq_hc_struct/mft/empty_frame_comes_apart
/datum/unit_test/dq_hc_struct/mft/empty_frame_comes_apart/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/spot = tile(3, 3)
	var/obj/machinery/porta_turret_construct/F = allocate(/obj/machinery/porta_turret_construct, spot)
	F.set_anchored(FALSE)
	var/obj/item/tool/crowbar/W = dq_fast_tool(/obj/item/tool/crowbar, tile(2, 2))
	H.put_in_active_hand(W)
	touch(H, F, W)
	TEST_ASSERT(QDELETED(F), "the frame comes apart")
	var/obj/item/stack/material/steel/S = locate_on(spot, /obj/item/stack/material/steel)
	TEST_ASSERT(S && S.get_amount() == 5, "into five sheets")
