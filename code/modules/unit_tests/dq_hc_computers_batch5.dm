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
