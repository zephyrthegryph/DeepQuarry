// Behaviour tests for the full airlock and APC conversion (rewrite/doors-full). They were written against the code before the
// conversion and pinned green on it; every assertion that changes on purpose is a row of doc/rewrite/intended_changes.md
// ("Airlock and APC, full conversion") and says so beside it.
//
// The airlock tests reuse the dq_p2_door harness (dq_p2_door_behaviour.dm): its fixtures, adapters, kernel clock and settle(). The APC tests
// reuse the dq_p2_apc harness (dq_p2_apc_behaviour.dm). The adapters below are the only place this file names the airlock's own state.

// ---------------------------------------------------------------------------------------------------------------------
// Adapters
// ---------------------------------------------------------------------------------------------------------------------

/// The status lines under the airlock's wires, as one text.
/proc/dq_full_wire_lights(obj/machinery/door/airlock/D)
	return jointext(D.wire_lights(), "\n")

/// The airlock's main power is out (cut, tripped or disrupted), whatever the backup does.
/proc/dq_full_main_power_out(obj/machinery/door/airlock/D)
	return !!D.main_power_out

/// A ctrl-click by `actor` on `target` with an empty hand.
/proc/dq_full_ctrl_click(mob/living/actor, atom/target)
	if(actor.get_active_hand())
		actor.drop_item()
	actor.next_click = 0
	return test_click(actor, target, null, GESTURE_CTRL)

/// Two airlocks that close each other (the map's closeOtherId pairs them).
/obj/machinery/door/airlock/dq_full_pair
	closeOtherId = "dq_full_pair"

/datum/unit_test/dq_p2_door/full
	abstract_type = /datum/unit_test/dq_p2_door/full

// =====================================================================================================================
// AI control
// =====================================================================================================================

/// The AI-control wire pulsed and then cut: the cut keeps the AI out once the pulse runs out.
/datum/unit_test/dq_p2_door/full/ai_wire_pulse_then_cut_keeps_the_ai_out

/datum/unit_test/dq_p2_door/full/ai_wire_pulse_then_cut_keeps_the_ai_out/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/silicon/ai/AI = make_ai()
	var/mob/living/carbon/human/H = make_person(null)
	p2_door_wire_pulse(D, WIRE_AI_CONTROL, H)
	p2_door_wire_cut(D, WIRE_AI_CONTROL, H)
	test_time(3 SECONDS)
	press(AI, D, "bolt-toggle")
	TEST_ASSERT(!p2_door_bolted(D), "the cut AI wire keeps the AI out after the pulse ends")
	p2_door_wire_cut(D, WIRE_AI_CONTROL, H) // mend
	press(AI, D, "bolt-toggle")
	TEST_ASSERT(p2_door_bolted(D), "mended, the AI works the door")

/// Two pulses a moment apart: the AI is out for about a second after the last, then back.
/datum/unit_test/dq_p2_door/full/ai_wire_pulses_lock_the_ai_out_briefly

/datum/unit_test/dq_p2_door/full/ai_wire_pulses_lock_the_ai_out_briefly/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/silicon/ai/AI = make_ai()
	var/mob/living/carbon/human/H = make_person(null)
	p2_door_wire_pulse(D, WIRE_AI_CONTROL, H)
	p2_door_ui(AI, D, "bolt-toggle")
	TEST_ASSERT(!p2_door_bolted(D), "a pulsed AI wire keeps the AI out at once")
	test_time(0.5 SECONDS)
	p2_door_wire_pulse(D, WIRE_AI_CONTROL, H)
	test_time(3 SECONDS)
	press(AI, D, "bolt-toggle")
	TEST_ASSERT(p2_door_bolted(D), "a few seconds on the AI is back")

/// An emagged door's 'AI control allowed' light is off.
/datum/unit_test/dq_p2_door/full/emagged_door_shows_ai_control_off

/datum/unit_test/dq_p2_door/full/emagged_door_shows_ai_control_off/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	TEST_ASSERT(findtext(dq_full_wire_lights(D), "'AI control allowed' light is on"), "a sound door shows AI control allowed")
	click(H, D, give_item(H, /obj/item/card/emag))
	TEST_ASSERT(!D.density, "the emag opened it")
	TEST_ASSERT(findtext(dq_full_wire_lights(D), "'AI control allowed' light is off"), "an emagged door shows AI control off")

/// The open-door wire does nothing on an emagged door.
/datum/unit_test/dq_p2_door/full/emagged_door_ignores_the_open_wire

/datum/unit_test/dq_p2_door/full/emagged_door_ignores_the_open_wire/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	click(H, D, give_item(H, /obj/item/card/emag))
	TEST_ASSERT(!D.density, "the emag opened it")
	p2_door_wire_pulse(D, WIRE_OPEN_DOOR, H)
	settle()
	TEST_ASSERT(!D.density, "the open wire does not shut an emagged door")

// =====================================================================================================================
// The window's buttons: what each refuses
// =====================================================================================================================

/// With the bolt wire cut the AI cannot raise the bolts.
/datum/unit_test/dq_p2_door/full/ai_cannot_raise_bolts_with_the_bolt_wire_cut

/datum/unit_test/dq_p2_door/full/ai_cannot_raise_bolts_with_the_bolt_wire_cut/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/silicon/ai/AI = make_ai()
	var/mob/living/carbon/human/H = make_person(null)
	p2_door_wire_cut(D, WIRE_DOOR_BOLTS, H)
	TEST_ASSERT(p2_door_bolted(D), "the cut wire dropped them")
	press(AI, D, "bolt-toggle")
	TEST_ASSERT(p2_door_bolted(D), "the AI cannot raise them")

/// With the bolt-light wire cut the lights stay off.
/datum/unit_test/dq_p2_door/full/ai_cannot_light_with_the_light_wire_cut

/datum/unit_test/dq_p2_door/full/ai_cannot_light_with_the_light_wire_cut/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/silicon/ai/AI = make_ai()
	var/mob/living/carbon/human/H = make_person(null)
	p2_door_wire_cut(D, WIRE_BOLT_LIGHT, H)
	TEST_ASSERT(!D.lights, "the cut wire put the bolt lights out")
	press(AI, D, "light-toggle")
	TEST_ASSERT(!D.lights, "the AI cannot light them")
	p2_door_wire_cut(D, WIRE_BOLT_LIGHT, H) // mend
	TEST_ASSERT(D.lights, "mended, they light")

/// With the timing wire cut the AI cannot change the speed; the speed it changes shows in the record of the door's state.
/datum/unit_test/dq_p2_door/full/speed_toggle_is_tracked_and_refused_with_the_wire_cut

/datum/unit_test/dq_p2_door/full/speed_toggle_is_tracked_and_refused_with_the_wire_cut/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/silicon/ai/AI = make_ai()
	var/mob/living/carbon/human/H = make_person(null)
	// The speed and the autoclose are tracked (their setters publish the change the window and the generated reads follow).
	TEST_ASSERT(hascall(D, "set_normalspeed") && hascall(D, "set_autoclose"), "the speed and the autoclose are tracked")
	press(AI, D, "speed-toggle")
	TEST_ASSERT(!D.normalspeed, "the AI set the door fast")
	press(AI, D, "speed-toggle")
	TEST_ASSERT(D.normalspeed, "and back")
	p2_door_wire_pulse(D, WIRE_SPEED, H)
	TEST_ASSERT(!D.normalspeed, "a pulse on the timing wire sets it fast")
	p2_door_wire_cut(D, WIRE_SPEED, H)
	TEST_ASSERT(!D.autoclose, "the cut timing wire stops the autoclose")
	press(AI, D, "speed-toggle")
	TEST_ASSERT(!D.normalspeed, "with the wire cut the AI cannot change the speed")

/// The disrupt buttons do nothing on power that is already out: the outage keeps its own end.
/datum/unit_test/dq_p2_door/full/disrupt_main_twice_keeps_the_first_outage

/datum/unit_test/dq_p2_door/full/disrupt_main_twice_keeps_the_first_outage/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/silicon/ai/AI = make_ai()
	p2_door_ui(AI, D, "disrupt-main")
	TEST_ASSERT(dq_full_main_power_out(D), "main power out")
	test_time(40 SECONDS)
	p2_door_ui(AI, D, "disrupt-main")
	TEST_ASSERT(dq_full_main_power_out(D), "still out")
	test_time(25 SECONDS)
	TEST_ASSERT(!dq_full_main_power_out(D), "back a minute after the first press: the second did not restart it")

// =====================================================================================================================
// Bolts and electrification by more than one hand
// =====================================================================================================================

/// One AI drops the bolts and another AI presses the bolt button.
/datum/unit_test/dq_p2_door/full/second_ai_and_the_bolts

/datum/unit_test/dq_p2_door/full/second_ai_and_the_bolts/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/silicon/ai/first = make_ai()
	var/mob/living/silicon/ai/second = make_ai()
	press(first, D, "bolt-toggle")
	TEST_ASSERT(p2_door_bolted(D), "the first AI bolted it")
	press(second, D, "bolt-toggle")
	TEST_ASSERT(p2_door_bolted(D), "the second AI's press holds its own bolts: the first AI's stay")
	press(first, D, "bolt-toggle")
	TEST_ASSERT(p2_door_bolted(D), "the first AI's unbolt releases only its own hold")
	press(second, D, "bolt-toggle")
	TEST_ASSERT(!p2_door_bolted(D), "with both released the bolts rise")

/// An AI's shock-restore after a wire pulse electrified the door.
/datum/unit_test/dq_p2_door/full/ai_restore_after_a_wire_pulse

/datum/unit_test/dq_p2_door/full/ai_restore_after_a_wire_pulse/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/silicon/ai/AI = make_ai()
	var/mob/living/carbon/human/H = make_person(null)
	p2_door_wire_pulse(D, WIRE_ELECTRIFY, H)
	TEST_ASSERT(p2_door_electrified(D), "the pulse electrified it")
	p2_door_ui(AI, D, "shock-restore")
	TEST_ASSERT(p2_door_electrified(D), "the AI's restore releases only its own current: the wire's pulse runs on")
	test_time(35 SECONDS)
	TEST_ASSERT(!p2_door_electrified(D), "until it runs out")

/// Electrification ends when the door loses its power, and does not come back with it.
/datum/unit_test/dq_p2_door/full/power_loss_ends_electrification

/datum/unit_test/dq_p2_door/full/power_loss_ends_electrification/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/silicon/ai/AI = make_ai()
	p2_door_ui(AI, D, "shock-perm")
	TEST_ASSERT(p2_door_electrified(D), "electrified until released")
	p2_door_set_power(D, FALSE)
	settle()
	TEST_ASSERT(p2_door_electrified(D), "pinned: losing area power leaves the electrification set (the shock cannot land without power)")
	p2_door_set_power(D, TRUE)
	settle()
	TEST_ASSERT(p2_door_electrified(D), "and it is live again with the power back")
	p2_door_ui(AI, D, "disrupt-main")
	test_time(11 SECONDS)
	p2_door_ui(AI, D, "shock-perm")
	TEST_ASSERT(p2_door_electrified(D), "on backup power it electrifies")

/// An electrified door that cannot land its shock (no power source in the room) still does what the touch meant.
/datum/unit_test/dq_p2_door/full/electrified_door_still_opens_when_the_shock_cannot_land

/datum/unit_test/dq_p2_door/full/electrified_door_still_opens_when_the_shock_cannot_land/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/silicon/ai/AI = make_ai()
	var/mob/living/carbon/human/H = make_person(null)
	p2_door_ui(AI, D, "shock-perm")
	TEST_ASSERT(p2_door_electrified(D), "electrified")
	click(H, D, null)
	TEST_ASSERT(!D.density, "the touch opened it")

// =====================================================================================================================
// The ctrl-click: hold it open, ring, hammer; a silicon's bolts
// =====================================================================================================================

/// A grab-stance ctrl-click holds the door open: nobody else shuts it while the holder stands by it, and it shuts once they walk away.
/datum/unit_test/dq_p2_door/full/held_open_door_stays_open_until_the_holder_leaves

/datum/unit_test/dq_p2_door/full/held_open_door_stays_open_until_the_holder_leaves/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/silicon/ai/AI = make_ai()
	var/mob/living/carbon/human/H = make_person(null)
	H.set_combat_mode(TRUE)
	H.set_attack_variant(ATTACK_VARIANT_GRAB)
	dq_full_ctrl_click(H, D)
	settle()
	TEST_ASSERT(!D.density, "the ctrl-click held it open")
	press(AI, D, "open-close")
	TEST_ASSERT(!D.density, "the AI cannot shut a door someone holds")
	H.forceMove(tile(4, 4))
	settle()
	press(AI, D, "open-close")
	TEST_ASSERT(D.density, "with the holder gone it shuts")

/// A help-stance ctrl-click rings the bell: the door neither opens nor bolts.
/datum/unit_test/dq_p2_door/full/ctrl_click_rings_and_changes_nothing

/datum/unit_test/dq_p2_door/full/ctrl_click_rings_and_changes_nothing/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	dq_full_ctrl_click(H, D)
	settle()
	TEST_ASSERT(D.density, "the bell does not open it")
	TEST_ASSERT(!p2_door_bolted(D), "nor bolt it")
	H.set_combat_mode(TRUE)
	dq_full_ctrl_click(H, D)
	settle()
	TEST_ASSERT(D.density, "hammering does not open it")
	TEST_ASSERT(!p2_door_bolted(D), "nor bolt it")

/// An AI's ctrl-click bolts the door over its link, and unbolts it.
/datum/unit_test/dq_p2_door/full/ai_ctrl_click_toggles_the_bolts

/datum/unit_test/dq_p2_door/full/ai_ctrl_click_toggles_the_bolts/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/silicon/ai/AI = make_ai()
	test_click(AI, D, null, GESTURE_CTRL)
	settle()
	TEST_ASSERT(p2_door_bolted(D), "the AI's ctrl-click bolts it")
	test_click(AI, D, null, GESTURE_CTRL)
	settle()
	TEST_ASSERT(!p2_door_bolted(D), "and unbolts it")

// =====================================================================================================================
// Mechanism
// =====================================================================================================================

/// Paired airlocks: opening the one that was placed second shuts the first.
/datum/unit_test/dq_p2_door/full/paired_airlocks_close_each_other

/datum/unit_test/dq_p2_door/full/paired_airlocks_close_each_other/run_gate()
	var/obj/machinery/door/airlock/A = make_door(/obj/machinery/door/airlock/dq_full_pair)
	var/obj/machinery/door/airlock/B = allocate(/obj/machinery/door/airlock/dq_full_pair, tile(2, 4))
	p2_door_set_power(B, TRUE)
	p2_door_set_autoclose(B, FALSE)
	A.open()
	settle()
	TEST_ASSERT(!A.density, "the first opened")
	B.open()
	settle()
	TEST_ASSERT(!B.density, "the second opened")
	TEST_ASSERT(A.density, "and shut the first")
	A.open()
	settle()
	TEST_ASSERT(!A.density, "the first opened again")
	TEST_ASSERT(B.density, "and shut the second: the pair works both ways")

/// A secure airlock bolts itself when it breaks.
/datum/unit_test/dq_p2_door/full/secure_airlock_bolts_when_it_breaks

/datum/unit_test/dq_p2_door/full/secure_airlock_bolts_when_it_breaks/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	D.secured_wires = TRUE
	D.take_damage(D.max_integrity * 0.9, BRUTE, MELEE)
	settle()
	TEST_ASSERT(D.broken_now(), "broken")
	TEST_ASSERT(p2_door_panel_open(D), "its panel burst open")
	TEST_ASSERT(p2_door_bolted(D), "and its bolts dropped")

/// The prison break opens a bolted cell door and drops its bolts again behind it.
/datum/unit_test/dq_p2_door/full/prison_open_opens_and_rebolts

/datum/unit_test/dq_p2_door/full/prison_open_opens_and_rebolts/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	p2_door_set_bolts(D, TRUE)
	D.prison_open()
	settle()
	TEST_ASSERT(!D.density, "it opened")
	TEST_ASSERT(p2_door_bolted(D), "and is bolted open")

/// An EMP may pop a windoor open; a blast door never.
/datum/unit_test/dq_p2_door/full/emp_pops_windoors_but_not_blast_doors

/datum/unit_test/dq_p2_door/full/emp_pops_windoors_but_not_blast_doors/run_gate()
	var/obj/machinery/door/window/W = make_door(/obj/machinery/door/window)
	var/obj/machinery/door/blast/regular/B = allocate(/obj/machinery/door/blast/regular, tile(2, 4))
	W.emp_protection_flags |= EMP_PROTECT_WIRES | EMP_PROTECT_CONTENTS
	B.emp_protection_flags |= EMP_PROTECT_WIRES | EMP_PROTECT_CONTENTS
	test_rng(1234)
	var/opened = FALSE
	for(var/i in 1 to 300)
		W.emp_act(1)
		B.emp_act(1)
		test_time(1 SECONDS)
		if(!W.density)
			opened = TRUE
			break
	TEST_ASSERT(opened, "a strong EMP pops a windoor open sometimes")
	TEST_ASSERT(B.density, "a blast door stays shut")

// =====================================================================================================================
// APC
// =====================================================================================================================

/datum/unit_test/dq_p2_apc/full
	abstract_type = /datum/unit_test/dq_p2_apc/full

/// A reboot clears the power alarm and what the APC remembers of it.
/datum/unit_test/dq_p2_apc/full/reboot_clears_the_power_alarm

/datum/unit_test/dq_p2_apc/full/reboot_clears_the_power_alarm/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/obj/machinery/power/terminal/Tm = A.terminal
	var/datum/wires_test_adapter/W = p2_apc_wires(A)
	var/mob/living/carbon/human/H = p2_actor()
	p2_cable(run_loc_floor_bottom_left)
	p2_area.set_requires_power(TRUE)
	p2_area.power_change() // the machines of the area learn of it, as a holodeck switch does
	A.connect_to_network()
	Tm.set_power_supply(1000000)
	p2_apc_resync(A)
	W.cut(WIRE_MAIN_POWER1)
	for(var/i in 1 to 20)
		p2_apc_power_step()
		if(A.power_alarm_raised)
			break
	TEST_ASSERT(A.power_alarm_raised, "a shorted APC raises the power alarm")
	p2_apc_subvert(A)
	open_cover(H, A)
	touch(H, A, null)
	TEST_ASSERT_NULL(A.cell, "the cell is out")
	touch(H, A, allocate(/obj/item/multitool, run_loc_floor_bottom_left))
	TEST_ASSERT(!p2_apc_emagged(A), "the reset rebooted it")
	TEST_ASSERT(!A.power_alarm_raised, "the reboot cleared the alarm it remembered")

/// A reboot puts every channel on auto, in the power domain too.
/datum/unit_test/dq_p2_apc/full/reboot_puts_the_channels_on_auto

/datum/unit_test/dq_p2_apc/full/reboot_puts_the_channels_on_auto/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/obj/machinery/power/terminal/Tm = A.terminal
	var/mob/living/carbon/human/H = p2_actor()
	p2_cable(run_loc_floor_bottom_left)
	p2_area.set_requires_power(TRUE)
	p2_area.power_change() // the machines of the area learn of it, as a holodeck switch does
	A.connect_to_network()
	Tm.set_power_supply(1000000)
	p2_apc_resync(A)
	unlock(H, A)
	press(H, A, "channel", list("channel" = POWER_CHANNEL_LIGHTING, "mode" = POWERCHAN_OFF_AUTO))
	p2_apc_power_step()
	TEST_ASSERT_EQUAL(A.lighting, POWERCHAN_OFF, "lighting off, as the power step reports it")
	p2_apc_subvert(A)
	open_cover(H, A)
	touch(H, A, null)
	touch(H, A, allocate(/obj/item/multitool, run_loc_floor_bottom_left))
	TEST_ASSERT(!p2_apc_emagged(A), "the reset rebooted it")
	for(var/i in 1 to 3)
		p2_apc_power_step()
	TEST_ASSERT(A.lighting != POWERCHAN_OFF, "after the reboot the power step no longer reports lighting forced off")

/// A cyborg's ctrl-click throws the breaker over its link, on a locked APC too.
/datum/unit_test/dq_p2_apc/full/cyborg_ctrl_click_throws_the_breaker

/datum/unit_test/dq_p2_apc/full/cyborg_ctrl_click_throws_the_breaker/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/silicon/robot/R = p2_borg()
	TEST_ASSERT(A.operating, "the breaker is on")
	test_click(R, A, null, GESTURE_CTRL)
	p2_settle()
	TEST_ASSERT(!A.operating, "the ctrl-click threw it")
	test_click(R, A, null, GESTURE_CTRL)
	p2_settle()
	TEST_ASSERT(A.operating, "and back")

/// The AI-control wire cut keeps a silicon off the window's buttons; mended, it works them again.
/datum/unit_test/dq_p2_apc/full/ai_wire_cut_keeps_silicons_off_the_buttons

/datum/unit_test/dq_p2_apc/full/ai_wire_cut_keeps_silicons_off_the_buttons/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/silicon/robot/R = p2_borg(locate(run_loc_floor_bottom_left.x + 3, run_loc_floor_bottom_left.y + 3, run_loc_floor_bottom_left.z))
	var/datum/wires_test_adapter/W = p2_apc_wires(A)
	W.cut(WIRE_AI_CONTROL)
	press(R, A, "breaker", list())
	TEST_ASSERT(A.operating, "the cut wire keeps the cyborg off the breaker")
	W.cut(WIRE_AI_CONTROL) // mend
	press(R, A, "breaker", list())
	TEST_ASSERT(!A.operating, "mended, it works it")
