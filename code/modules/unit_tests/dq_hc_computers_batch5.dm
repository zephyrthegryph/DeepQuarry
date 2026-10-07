// Computers, batch 5: the arcade machines (the battle game, the claw machine). See dq_hc_computers_base.dm for the rules.

/datum/unit_test/dq_hc_computers/arcade_battle_newgame
/datum/unit_test/dq_hc_computers/arcade_battle_newgame/run_gate()
	var/obj/machinery/computer/arcade/battle/C = hc_console(/obj/machinery/computer/arcade/battle)
	var/mob/living/carbon/human/H = hc_actor()
	C.player_hp = 3
	C.gameover = 1
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
	C.gamepaid = 0
	var/status = C.gameStatus
	press(H, C, "newgame")
	TEST_ASSERT_EQUAL(C.gameStatus, status, "an unpaid game does not start")
	C.gamepaid = 1
	press(H, C, "newgame")
	TEST_ASSERT_EQUAL(C.gameStatus, "CLAWMACHINE_ON", "a paid game starts")
	TEST_ASSERT_EQUAL(C.wintick, 0, "from the first move")
	press(H, C, "pointless")
	TEST_ASSERT_EQUAL(C.wintick, 1, "a move counts")
	C.wintick = 9
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
	var/hp = C.player_hp
	C.player_hp = 10
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
	C.gameover = 1
	var/enemy = C.enemy_hp
	press(H, C, "attack")
	TEST_ASSERT_EQUAL(C.enemy_hp, enemy, "nothing happens once the game is over")
	C.gameover = 0
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
	E.uses = 8
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
	TEST_ASSERT(B.emagged, "battle cheat mode sets its own gameplay state")
	TEST_ASSERT_EQUAL(E.uses, 7, "battle mode spends one sequencer use")
	B.player_hp = 7
	test_click(H, B, E)
	TEST_ASSERT_EQUAL(B.player_hp, 7, "a second swipe cannot reset a one-shot battle mode")
	TEST_ASSERT_EQUAL(E.uses, 7, "a refused repeat does not spend a use")
	var/obj/machinery/computer/arcade/orion_trail/O = hc_console(/obj/machinery/computer/arcade/orion_trail)
	test_click(H, O, E)
	TEST_ASSERT_EQUAL(O.name, "The Orion Trail: Realism Edition", "orion sequencer selects realism mode")
	TEST_ASSERT(O.emagged, "orion realism mode sets its own gameplay state")
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
