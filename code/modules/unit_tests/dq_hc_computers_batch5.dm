// Computers, batch 5: the arcade machines (the battle game, the claw machine). See dq_hc_computers_base.dm for the rules.

/datum/unit_test/dq_hc_computers/arcade_battle_newgame
/datum/unit_test/dq_hc_computers/arcade_battle_newgame/run_gate()
	var/obj/machinery/computer/arcade/battle/C = hc_console(/obj/machinery/computer/arcade/battle)
	var/mob/living/carbon/human/H = hc_actor()
	C.set_player_hp(3)
	C.set_gameover(1)
	press(H, C, "newgame")
	TEST_ASSERT_EQUAL(C.player_hp, 30, "a new game resets the player's health")
	TEST_ASSERT_EQUAL(C.enemy_hp, 45, "and the enemy's")
	TEST_ASSERT(!C.gameover, "and the game is on")
	var/list/data = hc_data(C, H)
	TEST_ASSERT_EQUAL(data["playerHP"], 30, "the window shows the player's health")
	TEST_ASSERT_EQUAL(data["enemyName"], C.enemy_name, "and the enemy's name")

/datum/unit_test/dq_hc_computers/arcade_claw_machine
/datum/unit_test/dq_hc_computers/arcade_claw_machine/run_gate()
	var/obj/machinery/computer/arcade/clawmachine/C = hc_console(/obj/machinery/computer/arcade/clawmachine)
	var/mob/living/carbon/human/H = hc_actor()
	C.set_gamepaid(0)
	var/status = C.gameStatus
	press(H, C, "newgame")
	TEST_ASSERT_EQUAL(C.gameStatus, status, "an unpaid game does not start")
	C.set_gamepaid(1)
	press(H, C, "newgame")
	TEST_ASSERT_EQUAL(C.gameStatus, "CLAWMACHINE_ON", "a paid game starts")
	TEST_ASSERT_EQUAL(C.wintick, 0, "from the first move")
	press(H, C, "pointless")
	TEST_ASSERT_EQUAL(C.wintick, 1, "a move counts")
	C.set_wintick(9)
	C.winprob = 0
	press(H, C, "pointless")
	TEST_ASSERT_EQUAL(C.gameStatus, "CLAWMACHINE_END", "the tenth move ends the game")
	TEST_ASSERT_EQUAL(C.gamepaid, 0, "which must be paid again")
	press(H, C, "return")
	TEST_ASSERT_EQUAL(C.gameStatus, "CLAWMACHINE_NEW", "returning goes back to the start")
	var/list/data = hc_data(C, H)
	TEST_ASSERT_EQUAL(data["gameStatus"], "CLAWMACHINE_NEW", "the window shows the state")
// ---- added with the conversion: the battle's moves were dead on the legacy forms (they only ever ran from a guard no button reached) ----

/datum/unit_test/dq_hc_computers/arcade_battle_moves
/datum/unit_test/dq_hc_computers/arcade_battle_moves/run_gate()
	var/obj/machinery/computer/arcade/battle/C = hc_console(/obj/machinery/computer/arcade/battle)
	var/mob/living/carbon/human/H = hc_actor()
	press(H, C, "newgame")
	TEST_ASSERT_EQUAL(C.player_hp, 30, "a new game resets the player's health")
	TEST_ASSERT_EQUAL(C.enemy_hp, 45, "and the enemy's")
	var/mp = C.player_mp
	press(H, C, "charge")
	TEST_ASSERT(C.player_mp > mp, "charging gains points")
	TEST_ASSERT(!C.blocked, "and the move has been resolved by the time it is over")
	var/enemy = C.enemy_hp
	press(H, C, "attack")
	TEST_ASSERT(C.enemy_hp < enemy, "an attack hurts the enemy")
	C.set_player_hp(10)
	press(H, C, "heal")
	TEST_ASSERT(C.player_hp > 10, "healing restores health")
	var/list/data = hc_data(C, H)
	TEST_ASSERT_EQUAL(data["playerHP"], C.player_hp, "the window shows the player's health")
	TEST_ASSERT_EQUAL(data["enemyName"], C.enemy_name, "and the enemy's name")

/datum/unit_test/dq_hc_computers/arcade_battle_blocked_and_over
/datum/unit_test/dq_hc_computers/arcade_battle_blocked_and_over/run_gate()
	var/obj/machinery/computer/arcade/battle/C = hc_console(/obj/machinery/computer/arcade/battle)
	var/mob/living/carbon/human/H = hc_actor()
	press(H, C, "newgame")
	C.set_gameover(1)
	var/enemy = C.enemy_hp
	press(H, C, "attack")
	TEST_ASSERT_EQUAL(C.enemy_hp, enemy, "nothing happens once the game is over")
	C.set_gameover(0)
	C.blocked = 1
	press(H, C, "attack")
	TEST_ASSERT_EQUAL(C.enemy_hp, enemy, "nor while a move is under way")
	press(H, C, "newgame")
	TEST_ASSERT(!C.gameover, "a new game starts again")


// ---- the mass driver console ----

/datum/unit_test/dq_hc_computers/pod_console
/datum/unit_test/dq_hc_computers/pod_console/run_gate()
	var/obj/machinery/computer/pod/C = hc_console(/obj/machinery/computer/pod)
	var/mob/living/carbon/human/H = hc_actor()
	press(H, C, "adjust_time", list("value" = 45))
	TEST_ASSERT_EQUAL(C.time, 45, "the timer is set")
	press(H, C, "adjust_time", list("value" = 500))
	TEST_ASSERT_EQUAL(C.time, 120, "and clamped to two minutes")
	press(H, C, "adjust_time", list("value" = -5))
	TEST_ASSERT_EQUAL(C.time, 0, "and to nothing")
	TEST_ASSERT(!C.timing, "the countdown is off")
	press(H, C, "adjust_time", list("value" = 60))
	press(H, C, "start_stop")
	TEST_ASSERT(C.timing, "start starts it")
	press(H, C, "start_stop")
	TEST_ASSERT(!C.timing, "and stop stops it")
	press(H, C, "adjust_power", list("value" = 4))

// Public sequencer swipes pin the legacy declarations before replacement.
/datum/unit_test/dq_hc_computers/proc/hc_emag(mob/living/carbon/human/H)
	var/obj/item/card/emag/E = allocate(/obj/item/card/emag, hc_side())
	E.set_uses(8)
	TEST_ASSERT(H.put_in_active_hand(E), "the sequencer is held for an actual click")
	return E

/datum/unit_test/dq_hc_computers/arcade_emag_modes
/datum/unit_test/dq_hc_computers/arcade_emag_modes/run_gate()
	var/mob/living/carbon/human/H = hc_actor()
	var/obj/item/card/emag/E = hc_emag(H)
	var/obj/machinery/computer/arcade/battle/B = hc_console(/obj/machinery/computer/arcade/battle)
	test_click(H, B, E)
	TEST_ASSERT_EQUAL(B.enemy_name, "Cuban Pete", "battle sequencer starts lethal enemy mode")
	TEST_ASSERT_EQUAL(B.player_hp, 30, "battle mode resets the player's health")
	TEST_ASSERT(B.emagged(), "battle cheat mode sets its own gameplay state")
	TEST_ASSERT_EQUAL(E.uses, 7, "battle mode spends one sequencer use")
	B.set_player_hp(7)
	test_click(H, B, E)
	TEST_ASSERT_EQUAL(B.player_hp, 7, "a second swipe cannot reset a one-shot battle mode")
	TEST_ASSERT_EQUAL(E.uses, 7, "a refused repeat does not spend a use")
	var/obj/machinery/computer/arcade/orion_trail/O = hc_console(/obj/machinery/computer/arcade/orion_trail)
	test_click(H, O, E)
	TEST_ASSERT_EQUAL(O.name, "The Orion Trail: Realism Edition", "orion sequencer selects realism mode")
	TEST_ASSERT(O.emagged(), "orion realism mode sets its own gameplay state")
	TEST_ASSERT_EQUAL(E.uses, 6, "orion mode spends one use")
	var/obj/machinery/computer/arcade/clawmachine/C = hc_console(/obj/machinery/computer/arcade/clawmachine)
	C.set_gamepaid(TRUE)
	test_click(H, C, E)
	TEST_ASSERT_EQUAL(C.winprob, 100, "claw sequencer guarantees a win")
	TEST_ASSERT_EQUAL(C.gamepaid, 0, "claw mode still requires a new payment")
	TEST_ASSERT_EQUAL(C.gameStatus, "CLAWMACHINE_NEW", "claw mode resets the actual game state")
	TEST_ASSERT_EQUAL(E.uses, 5, "claw mode spends one use")

/datum/unit_test/dq_hc_computers/prison_emag_once_effect
/datum/unit_test/dq_hc_computers/prison_emag_once_effect/run_gate()
	var/mob/living/carbon/human/H = hc_actor()
	var/obj/item/card/emag/E = hc_emag(H)
	var/obj/machinery/computer/prison_shuttle/C = hc_console(/obj/machinery/computer/prison_shuttle)
	test_click(H, C, E)
	TEST_ASSERT(C.hacked, "the sequencer disables the prison shuttle lock")
	TEST_ASSERT_EQUAL(E.uses, 7, "unlocking spends one use")
	test_click(H, C, E)
	TEST_ASSERT_EQUAL(E.uses, 7, "an already unlocked repeat does not spend another use")

/datum/unit_test/dq_hc_computers/supply_emag_contraband
/datum/unit_test/dq_hc_computers/supply_emag_contraband/run_gate()
	var/mob/living/carbon/human/H = hc_actor()
	var/obj/item/card/emag/E = hc_emag(H)
	var/obj/machinery/computer/supplycomp/C = hc_console(/obj/machinery/computer/supplycomp)
	test_click(H, C, E)
	TEST_ASSERT(C.can_order_contraband, "the sequencer enables contraband ordering")
	TEST_ASSERT(C.authorization & SUP_CONTRABAND, "the actual authorization bit is enabled")
	TEST_ASSERT_EQUAL(length(C.req_access), 0, "the sequencer removes the access requirement")
	TEST_ASSERT_EQUAL(E.uses, 7, "contraband unlock spends one use")
	test_click(H, C, E)
	TEST_ASSERT_EQUAL(E.uses, 7, "an already unlocked repeat does not spend another use")

/datum/unit_test/dq_hc_computers/specops_emag_declines
/datum/unit_test/dq_hc_computers/specops_emag_declines/run_gate()
	var/mob/living/carbon/human/H = hc_actor()
	var/obj/item/card/emag/E = hc_emag(H)
	var/obj/machinery/computer/specops_shuttle/C = hc_console(/obj/machinery/computer/specops_shuttle)
	test_click(H, C, E)
	TEST_ASSERT_EQUAL(E.uses, 8, "advanced specops systems reject the sequencer without payment")
	TEST_ASSERT(!is_emagged(C), "a declined swipe does not mark the console subverted")

/// The Orion Trail event screen's choices are window ops (ui_act), not links: eventclose only continues an event that can continue, and a part selector must be 1 to 3.
/datum/unit_test/dq_hc_computers/orion_event_close_and_schema
/datum/unit_test/dq_hc_computers/orion_event_close_and_schema/run_gate()
	var/obj/machinery/computer/arcade/orion_trail/C = hc_console(/obj/machinery/computer/arcade/orion_trail)
	var/mob/living/carbon/human/H = hc_actor()
	C.set_event(C.events[1])
	var/starting_event = C.event
	C.canContinueEvent = FALSE
	var/datum/op_result/pending = own(press(H, C, "eventclose"))
	TEST_ASSERT_EQUAL(pending?.outcome, ACT_COMMITTED, "the close choice reaches its op; reason=[pending?.reason]")
	TEST_ASSERT_EQUAL(C.event, starting_event, "an event that cannot continue remains pending after its close choice")
	C.canContinueEvent = TRUE
	var/datum/op_result/continued = own(press(H, C, "eventclose"))
	TEST_ASSERT_EQUAL(continued?.outcome, ACT_COMMITTED, "a continuable event reaches the real close handler; reason=[continued?.reason]")
	TEST_ASSERT_NULL(C.event, "the real close handler clears a continuable game event")
	var/fuel_before = C.fuel
	var/engine_before = C.engine
	var/datum/op_result/bad = own(press(H, C, "buyparts", list("part" = "not a number")))
	TEST_ASSERT_EQUAL(bad?.outcome, ACT_REFUSED, "the op schema rejects an invalid part selector")
	TEST_ASSERT_EQUAL(C.fuel, fuel_before, "a rejected choice spends no fuel")
	TEST_ASSERT_EQUAL(C.engine, engine_before, "and creates no part")

/// Each event offers the choices its old screen had, as data, and the choices change the game as the old links did.
/datum/unit_test/dq_hc_computers/orion_event_screens
/datum/unit_test/dq_hc_computers/orion_event_screens/run_gate()
	var/obj/machinery/computer/arcade/orion_trail/C = hc_console(/obj/machinery/computer/arcade/orion_trail)
	var/mob/living/carbon/human/H = hc_actor()
	C.newgame(H)
	// Interstellar flux: slowing down costs supplies and ends the event.
	C.set_event(ORION_TRAIL_FLUX)
	C.event()
	var/list/data = hc_data(C, H)
	TEST_ASSERT_EQUAL(data["screen"], "event", "a pending event shows the event screen")
	TEST_ASSERT_EQUAL(data["event_title"], ORION_TRAIL_FLUX, "the window names the event")
	TEST_ASSERT(length(data["event_lines"]) >= 1, "the story is sent as lines")
	TEST_ASSERT_NULL(data["event_html"], "no markup is sent")
	var/list/keys = list()
	for(var/list/choice in data["event_actions"])
		keys += choice["action"]
	TEST_ASSERT_EQUAL(jointext(keys, ","), "slow,keepspeed", "the flux offers slowing down or keeping speed")
	var/food_before = C.food
	var/fuel_before = C.fuel
	press(H, C, "slow")
	TEST_ASSERT_NULL(C.event, "slowing down ends the event")
	TEST_ASSERT_EQUAL(C.food, food_before - ((C.alive + C.traitors_aboard) * 2), "and costs the crew's food")
	TEST_ASSERT_EQUAL(C.fuel, fuel_before - 5, "and fuel")
	// A breakdown: the engine part is only offered while one is held; using it spends it.
	C.set_engine(0)
	C.set_event(ORION_TRAIL_BREAKDOWN)
	C.event()
	keys = list()
	for(var/list/choice in C.orion_event_actions())
		keys += choice["action"]
	TEST_ASSERT_EQUAL(jointext(keys, ","), "wait", "without an engine part only waiting is offered")
	C.set_engine(1)
	press(H, C, "useengine")
	TEST_ASSERT_EQUAL(C.engine, 0, "using the part spends it")
	TEST_ASSERT_NULL(C.event, "and ends the event")
	// A choice for another event does nothing (the old handlers checked the event too).
	C.set_event(ORION_TRAIL_RAIDERS)
	C.set_engine(1)
	press(H, C, "useengine")
	TEST_ASSERT_EQUAL(C.engine, 1, "an engine part is not used when the engine did not break")
	TEST_ASSERT_EQUAL(C.event, ORION_TRAIL_RAIDERS, "and the event stays")

/// The spaceport's rows: buying a part, trading, and the rows the crew cannot afford.
/datum/unit_test/dq_hc_computers/orion_spaceport_market
/datum/unit_test/dq_hc_computers/orion_spaceport_market/run_gate()
	var/obj/machinery/computer/arcade/orion_trail/C = hc_console(/obj/machinery/computer/arcade/orion_trail)
	var/mob/living/carbon/human/H = hc_actor()
	C.newgame(H)
	C.set_event(ORION_TRAIL_SPACEPORT)
	C.set_fuel(30)
	C.set_food(30)
	C.event()
	TEST_ASSERT_EQUAL(C.gameStatus, ORION_STATUS_MARKET, "docking opens the market")
	var/hull_before = C.hull
	press(H, C, "buyparts", list("part" = 2))
	TEST_ASSERT_EQUAL(C.hull, hull_before + 1, "buying hull plates adds one")
	TEST_ASSERT_EQUAL(C.fuel, 25, "for five fuel")
	press(H, C, "trade", list("kind" = 1))
	TEST_ASSERT_EQUAL(C.fuel, 20, "trading fuel for food spends fuel")
	TEST_ASSERT_EQUAL(C.food, 35, "and gains food")
	C.set_fuel(5)
	var/hull_poor = C.hull
	press(H, C, "buyparts", list("part" = 2))
	TEST_ASSERT_EQUAL(C.hull, hull_poor, "five fuel is not enough for a part")
	var/list/unaffordable = list()
	for(var/list/choice in C.orion_event_actions())
		if(!choice["action"])
			unaffordable += choice["label"]
	TEST_ASSERT(("You cannot afford to buy Hull Plates" in unaffordable), "the unaffordable row is a label without an action")
	press(H, C, "leave_spaceport")
	TEST_ASSERT_NULL(C.event, "leaving ends the event")
	TEST_ASSERT_EQUAL(C.gameStatus, ORION_STATUS_NORMAL, "and goes back to the trail")

/datum/unit_test/dq_hc_computers/syndicate_pod_public_access_gate
/datum/unit_test/dq_hc_computers/syndicate_pod_public_access_gate/run_gate()
	var/obj/machinery/computer/pod/old/syndicate/C = hc_console(/obj/machinery/computer/pod/old/syndicate)
	var/mob/living/carbon/human/H = hc_actor()
	TEST_ASSERT(!C.allowed(H), "the real actor starts without the console's credential")
	var/datum/op_result/denied = own(test_click(H, C, null))
	TEST_ASSERT_EQUAL(denied?.outcome, ACT_REFUSED, "the generated window binding cannot bypass the syndicate credential requirement")
	TEST_ASSERT_EQUAL(denied?.reason, MSG(pod/access_denied), "public window dispatch preserves the canonical access refusal")
	var/obj/item/card/id/I = allocate(/obj/item/card/id, hc_side())
	I.set_access(list(ACCESS_SYNDICATE))
	var/obj/item/clothing/under/color/grey/U = allocate(/obj/item/clothing/under/color/grey, hc_side())
	TEST_ASSERT(H.equip_to_slot_if_possible(U, SLOT_ID_UNIFORM, quiet = TRUE), "the actual uniform supplies the worn credential slot")
	TEST_ASSERT(H.equip_to_slot_if_possible(I, SLOT_ID_ID, quiet = TRUE), "the actual credential is worn in the ID slot")
	TEST_ASSERT_NULL(H.get_active_hand(), "the public hand click uses the actor's actual empty hand")
	TEST_ASSERT(C.allowed(H), "the actual worn credential grants console access")
	var/datum/op_result/accepted = own(test_click(H, C, null))
	TEST_ASSERT_EQUAL(accepted?.key, "ui_open", "public dispatch selects the generated window operation")
	TEST_ASSERT_EQUAL(accepted?.outcome, ACT_COMMITTED, "the same public window gate admits an actor with the actual credential; reason=[accepted?.reason]")

/datum/unit_test/dq_hc_computers/prison_public_window_access_and_break_gate
/datum/unit_test/dq_hc_computers/prison_public_window_access_and_break_gate/run_gate()
	var/obj/machinery/computer/prison_shuttle/C = hc_console(/obj/machinery/computer/prison_shuttle)
	var/mob/living/carbon/human/H = hc_actor()
	var/datum/op_result/no_access = own(test_click(H, C, null))
	TEST_ASSERT_EQUAL(no_access?.outcome, ACT_REFUSED, "the generated window cannot bypass the prison credential gate")
	TEST_ASSERT_EQUAL(reason_text(no_access?.reason), "access denied", "the real access policy supplies the refusal")
	var/obj/item/card/id/I = allocate(/obj/item/card/id, hc_side())
	I.set_access(list(ACCESS_SECURITY))
	var/obj/item/clothing/under/color/grey/U = allocate(/obj/item/clothing/under/color/grey, hc_side())
	TEST_ASSERT(H.equip_to_slot_if_possible(U, SLOT_ID_UNIFORM, quiet = TRUE), "the actual uniform supplies the worn credential slot")
	TEST_ASSERT(H.equip_to_slot_if_possible(I, SLOT_ID_ID, quiet = TRUE), "the actual credential is worn in the ID slot")
	TEST_ASSERT_NULL(H.get_active_hand(), "the public hand click uses the actor's actual empty hand")
	C.set_prison_break(TRUE)
	var/datum/op_result/broken_route = own(test_click(H, C, null))
	TEST_ASSERT_EQUAL(broken_route?.outcome, ACT_REFUSED, "a real credential cannot bypass a broken prison route")
	TEST_ASSERT_EQUAL(reason_text(broken_route?.reason), "unable to locate shuttle", "the actual route failure supplies its refusal")
	C.set_prison_break(FALSE)
	var/datum/op_result/accepted = own(test_click(H, C, null))
	TEST_ASSERT_EQUAL(accepted?.key, "ui_open", "the generated binding remains the actual public window operation")
	TEST_ASSERT_EQUAL(accepted?.outcome, ACT_COMMITTED, "restoring the route permits the actual credentialed actor")

/datum/unit_test/dq_hc_computers/skills_public_window_contact_gate
	var/list/contact_levels_before
/datum/unit_test/dq_hc_computers/skills_public_window_contact_gate/proc/restore_contact_levels()
	using_map.contact_levels = contact_levels_before
/datum/unit_test/dq_hc_computers/skills_public_window_contact_gate/run_gate()
	TEST_ASSERT(using_map, "the test world supplies a real map policy")
	contact_levels_before = using_map.contact_levels
	defer_cleanup(src, PROC_REF(restore_contact_levels))
	var/obj/machinery/computer/skills/C = hc_console(/obj/machinery/computer/skills)
	var/mob/living/carbon/human/H = hc_actor()
	using_map.contact_levels = list()
	var/datum/op_result/out_of_range = own(test_click(H, C, null))
	TEST_ASSERT_EQUAL(out_of_range?.outcome, ACT_REFUSED, "the generated records window cannot bypass the real map contact policy")
	using_map.contact_levels = list(C.z)
	var/datum/op_result/accepted = own(test_click(H, C, null))
	TEST_ASSERT_EQUAL(accepted?.key, "ui_open", "the public window remains the generated operation")
	TEST_ASSERT_EQUAL(accepted?.outcome, ACT_COMMITTED, "the real map policy admits the console once its level is contactable")

// A headless actor has no native key, so the effect's actual dispatch is observed before chaining the real fingerprint implementation.
/obj/machinery/computer/secure_data/dq_public_touch_probe
	var/touch_calls = 0
	var/mob/touched_by
/obj/machinery/computer/secure_data/dq_public_touch_probe/record_open_touch(datum/act/op/A)
	touch_calls++
	touched_by = A.actor
	return ..()

/datum/unit_test/dq_hc_computers/security_public_window_touch_effect
/datum/unit_test/dq_hc_computers/security_public_window_touch_effect/run_gate()
	var/obj/machinery/computer/secure_data/dq_public_touch_probe/C = hc_console(/obj/machinery/computer/secure_data/dq_public_touch_probe)
	var/mob/living/carbon/human/H = hc_actor()
	TEST_ASSERT_EQUAL(C.touch_calls, 0, "constructing the real console does not count a touch")
	var/datum/op_result/opened = own(test_click(H, C, null))
	TEST_ASSERT_EQUAL(opened?.key, "ui_open", "the actual generated operation handles the touch")
	TEST_ASSERT_EQUAL(opened?.outcome, ACT_COMMITTED, "the public touch opens the real console")
	TEST_ASSERT_EQUAL(C.touch_calls, 1, "the generated window invokes the real touch effect exactly once")
	TEST_ASSERT_EQUAL(C.touched_by, H, "the real touch effect receives the actual input actor before chaining the fingerprint implementation")

/datum/unit_test/dq_hc_computers/security_public_held_id_insertion
/datum/unit_test/dq_hc_computers/security_public_held_id_insertion/run_gate()
	var/obj/machinery/computer/secure_data/C = hc_console(/obj/machinery/computer/secure_data)
	var/mob/living/carbon/human/H = hc_actor()
	var/obj/item/card/id/I = allocate(/obj/item/card/id, hc_side())
	hc_hold(H, I)
	TEST_ASSERT_EQUAL(H.get_active_hand(), I, "the actual ID is held for the public input")
	TEST_ASSERT_NULL(C.scan, "the real console starts with an empty card bay")
	var/datum/op_result/inserted = own(test_click(H, C, I))
	TEST_ASSERT_EQUAL(inserted?.key, "secure_data_insert_id", "held ID insertion outranks the window fallback")
	TEST_ASSERT_EQUAL(inserted?.outcome, ACT_COMMITTED, "the actual held ID is accepted")
	TEST_ASSERT_EQUAL(C.scan, I, "the real scan bay contains that exact ID")
	TEST_ASSERT_NULL(H.get_active_hand(), "successful insertion removes the actual card from the hand")

/datum/unit_test/dq_hc_computers/skills_public_held_id_insertion
/datum/unit_test/dq_hc_computers/skills_public_held_id_insertion/run_gate()
	var/obj/machinery/computer/skills/C = hc_console(/obj/machinery/computer/skills)
	var/mob/living/carbon/human/H = hc_actor()
	var/obj/item/card/id/I = allocate(/obj/item/card/id, hc_side())
	hc_hold(H, I)
	TEST_ASSERT_EQUAL(H.get_active_hand(), I, "the actual ID is held for the public input")
	TEST_ASSERT_NULL(C.scan, "the real console starts with an empty card bay")
	var/datum/op_result/inserted = own(test_click(H, C, I))
	TEST_ASSERT_EQUAL(inserted?.key, "insert_id", "held ID insertion outranks the window fallback")
	TEST_ASSERT_EQUAL(inserted?.outcome, ACT_COMMITTED, "the actual held ID is accepted")
	TEST_ASSERT_EQUAL(C.scan, I, "the real scan bay contains that exact ID")
	TEST_ASSERT_NULL(H.get_active_hand(), "successful insertion removes the actual card from the hand")
