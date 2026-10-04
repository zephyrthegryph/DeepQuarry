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
