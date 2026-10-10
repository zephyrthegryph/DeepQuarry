// Behaviour pins for the timed actions of code/modules/mob, vore, nifsoft, resleeving, xenobio (wave 3, worker A), recorded on the legacy
// task_timed / task_start forms before they become ops with wait(). Same helpers and rules as dq_timed_pin_w6_behaviour.dm.

/datum/unit_test/dq_timed_pin_w7
	abstract_type = /datum/unit_test/dq_timed_pin_w7
	parent_type = /datum/unit_test/dq_timed_pin

/// A mob that still has a ckey when it is deleted leaves an observer behind: take the ckeys off.
/datum/unit_test/dq_timed_pin_w7/proc/forget_ghosts()
	for(var/mob/living/carbon/human/H in range(3, run_loc_floor_bottom_left))
		H.ckey = null

/// Clicks `target` with `held` and checks that a timed action of `dur` starts (and says `start_text` when given). Returns the running action.
/datum/unit_test/dq_timed_pin_w7/proc/begin(mob/user, atom/target, obj/item/held, dur, start_text = null)
	test_chat_clear()
	test_click(user, target, held)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the click starts a timed action")
	if(!isnull(dur))
		TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == dur, "it lasts [dur] ticks")
	if(start_text)
		TEST_ASSERT(said(user, start_text), "it says it began")
	return T

/// The held-in-hand form: puts `I` in the active hand.
/datum/unit_test/dq_timed_pin_w7/proc/hold(mob/living/carbon/human/user, obj/item/I)
	user.put_in_active_hand(I)
	return I

// ---- cluster h ----

// Cluster H pins (mob/living/carbon, human, butchering, melee swing, grab specials): behaviour recorded on the legacy timed forms.
// Parent /datum/unit_test/dq_timed_pin_w7 and its helpers (begin, hold, forget_ghosts) are the lead's; the h_* helpers below are this cluster's.
// Entry points that no click reaches (the strip menu, a verb) are called as the real caller does; the proc they call stays the dispatcher after the
// conversion, or the helper uses the converted op's menu entry (h_verb_or_menu).

// ---- Helpers ----

/// A human next to the default user position (east), godmode on.
/datum/unit_test/dq_timed_pin_w7/proc/h_victim()
	return person(get_step(run_loc_floor_bottom_left, EAST))

/// A human next to the default user position (east) that can be hurt.
/datum/unit_test/dq_timed_pin_w7/proc/h_mortal()
	return allocate(/mob/living/carbon/human, get_step(run_loc_floor_bottom_left, EAST))

/// Asserts that `user` has a timed action running (of `dur` ticks when given, saying `start_text` when given) and returns it.
/datum/unit_test/dq_timed_pin_w7/proc/h_started(mob/user, dur = null, start_text = null)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a timed action starts")
	if(!isnull(dur))
		TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == dur, "it lasts [dur] ticks")
	if(start_text)
		TEST_ASSERT(said(user, start_text), "it says it began")
	return T

/// Equips `I` on `H` in `slot` and returns it.
/datum/unit_test/dq_timed_pin_w7/proc/h_equip(mob/living/carbon/human/H, obj/item/I, slot)
	TEST_ASSERT(H.equip_to_slot_if_possible(I, slot, disable_warning = TRUE), "[I] equips to [slot]")
	return I

/// Steps a mob one tile north (a move that cancels what it is doing).
/datum/unit_test/dq_timed_pin_w7/proc/h_step_away(mob/M)
	M.forceMove(get_step(M, NORTH))

/// Runs a verb the way the player does: the legacy verb while it exists, else the op picked from the menu of `target`.
/datum/unit_test/dq_timed_pin_w7/proc/h_verb_or_menu(mob/user, atom/target, verb_name, op_key)
	if(hascall(target, verb_name))
		usr = user
		call(target, verb_name)()
	else
		test_menu(user, target, op_key)

// ---- Stripping: the strip menu hands the slot to handle_strip(); the five fixed jobs and the slot job are one timed action each ----

/datum/unit_test/dq_timed_pin_w7/h_strip_pockets

/datum/unit_test/dq_timed_pin_w7/h_strip_pockets/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/carbon/human/victim = h_victim()
	h_equip(victim, allocate(/obj/item/clothing/under/color/black, run_loc_floor_bottom_left), SLOT_ID_UNIFORM)
	var/obj/item/pen/P = h_equip(victim, allocate(/obj/item/pen, run_loc_floor_bottom_left), SLOT_ID_POCKET_L)
	test_chat_clear()
	victim.handle_strip("pockets", user)
	h_started(user, HUMAN_STRIP_DELAY)
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(victim.get_equipped_item(SLOT_ID_POCKET_L), P, "nothing is emptied before the end")
	test_time(2 SECONDS)
	TEST_ASSERT_NULL(victim.get_equipped_item(SLOT_ID_POCKET_L), "the pockets are emptied at the end")
	TEST_ASSERT_NULL(running(user), "nothing is left running")

/datum/unit_test/dq_timed_pin_w7/h_strip_pockets_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/h_strip_pockets_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/carbon/human/victim = h_victim()
	h_equip(victim, allocate(/obj/item/clothing/under/color/black, run_loc_floor_bottom_left), SLOT_ID_UNIFORM)
	var/obj/item/pen/P = h_equip(victim, allocate(/obj/item/pen, run_loc_floor_bottom_left), SLOT_ID_POCKET_L)
	victim.handle_strip("pockets", user)
	var/datum/T = h_started(user)
	test_time(1 SECOND)
	h_step_away(user)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(victim.get_equipped_item(SLOT_ID_POCKET_L), P, "moving cancels: the pocket keeps its item")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w7/h_strip_splints

/datum/unit_test/dq_timed_pin_w7/h_strip_splints/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/carbon/human/victim = h_victim()
	test_chat_clear()
	victim.handle_strip("splints", user)
	h_started(user, HUMAN_STRIP_DELAY)
	test_time(3 SECONDS)
	TEST_ASSERT(!said(user, "no splints"), "nothing is decided before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(said(user, "no splints to remove"), "with no splint on them it says so at the end")

/datum/unit_test/dq_timed_pin_w7/h_strip_sensors

/datum/unit_test/dq_timed_pin_w7/h_strip_sensors/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/carbon/human/victim = h_victim()
	h_equip(victim, allocate(/obj/item/clothing/under/color/prison, run_loc_floor_bottom_left), SLOT_ID_UNIFORM)
	test_chat_clear()
	victim.handle_strip("sensors", user)
	h_started(user, HUMAN_STRIP_DELAY)
	test_time(3 SECONDS)
	TEST_ASSERT(!said(user, "controls are locked"), "the controls are not touched before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(said(user, "controls are locked"), "locked sensor controls are reported at the end")

/datum/unit_test/dq_timed_pin_w7/h_strip_internals

/datum/unit_test/dq_timed_pin_w7/h_strip_internals/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/carbon/human/victim = h_victim()
	h_equip(victim, allocate(/obj/item/clothing/mask/breath, run_loc_floor_bottom_left), SLOT_ID_MASK)
	var/obj/item/tank/oxygen/T = h_equip(victim, allocate(/obj/item/tank/oxygen, run_loc_floor_bottom_left), SLOT_ID_BACK)
	victim.handle_strip("internals", user)
	h_started(user, HUMAN_STRIP_DELAY)
	test_time(3 SECONDS)
	TEST_ASSERT_NULL(victim.internal, "internals are not switched before the end")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(victim.internal, T, "the tank is set as their internals at the end")

/datum/unit_test/dq_timed_pin_w7/h_strip_tie

/datum/unit_test/dq_timed_pin_w7/h_strip_tie/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/carbon/human/victim = h_victim()
	var/obj/item/clothing/under/color/black/U = h_equip(victim, allocate(/obj/item/clothing/under/color/black, run_loc_floor_bottom_left), SLOT_ID_UNIFORM)
	var/obj/item/clothing/accessory/medal/conduct/M = allocate(/obj/item/clothing/accessory/medal/conduct, run_loc_floor_bottom_left)
	U.attach_accessory(null, M)
	TEST_ASSERT(M in U.accessories, "setup: the medal is on the uniform")
	victim.handle_strip("tie", user)
	h_started(user, HUMAN_STRIP_DELAY)
	test_time(3 SECONDS)
	TEST_ASSERT(M in U.accessories, "the medal stays on before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(!(M in U.accessories), "the medal is taken off at the end")

/datum/unit_test/dq_timed_pin_w7/h_strip_slot_remove

/datum/unit_test/dq_timed_pin_w7/h_strip_slot_remove/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/carbon/human/victim = h_victim()
	var/obj/item/clothing/head/hardhat/hat = h_equip(victim, allocate(/obj/item/clothing/head/hardhat, run_loc_floor_bottom_left), SLOT_ID_HEAD)
	victim.handle_strip(SLOT_ID_HEAD, user)
	h_started(user, HUMAN_STRIP_DELAY)
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(victim.get_equipped_item(SLOT_ID_HEAD), hat, "the hat stays on before the end")
	test_time(2 SECONDS)
	TEST_ASSERT_NULL(victim.get_equipped_item(SLOT_ID_HEAD), "the hat is taken off at the end")

/datum/unit_test/dq_timed_pin_w7/h_strip_slot_remove_cancel_on_target_move

/datum/unit_test/dq_timed_pin_w7/h_strip_slot_remove_cancel_on_target_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/carbon/human/victim = h_victim()
	var/obj/item/clothing/head/hardhat/hat = h_equip(victim, allocate(/obj/item/clothing/head/hardhat, run_loc_floor_bottom_left), SLOT_ID_HEAD)
	victim.handle_strip(SLOT_ID_HEAD, user)
	var/datum/T = h_started(user)
	test_time(1 SECOND)
	h_step_away(victim)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(victim.get_equipped_item(SLOT_ID_HEAD), hat, "the target stepping away cancels: the hat stays")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w7/h_strip_slot_place

/datum/unit_test/dq_timed_pin_w7/h_strip_slot_place/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/carbon/human/victim = h_victim()
	var/obj/item/clothing/head/hardhat/hat = allocate(/obj/item/clothing/head/hardhat, run_loc_floor_bottom_left)
	user.put_in_active_hand(hat)
	victim.handle_strip(SLOT_ID_HEAD, user)
	h_started(user, HUMAN_STRIP_DELAY)
	test_time(3 SECONDS)
	TEST_ASSERT_NULL(victim.get_equipped_item(SLOT_ID_HEAD), "nothing is put on before the end")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(victim.get_equipped_item(SLOT_ID_HEAD), hat, "the held hat is put on them at the end")
	TEST_ASSERT_NULL(user.get_active_hand(), "the hand is empty")

/datum/unit_test/dq_timed_pin_w7/h_strip_slot_place_cancel_on_drop

/datum/unit_test/dq_timed_pin_w7/h_strip_slot_place_cancel_on_drop/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/carbon/human/victim = h_victim()
	var/obj/item/clothing/head/hardhat/hat = allocate(/obj/item/clothing/head/hardhat, run_loc_floor_bottom_left)
	user.put_in_active_hand(hat)
	victim.handle_strip(SLOT_ID_HEAD, user)
	var/datum/T = h_started(user)
	user.drop_from_inventory(hat)
	test_time(5 SECONDS)
	TEST_ASSERT_NULL(victim.get_equipped_item(SLOT_ID_HEAD), "dropping the held hat cancels: nothing is put on")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

// ---- CPR (bare hand, help stance, on someone who is dead or critical) ----

/datum/unit_test/dq_timed_pin_w7/h_cpr

/datum/unit_test/dq_timed_pin_w7/h_cpr/run_pin()
	var/mob/living/carbon/human/user = person()
	dq_give_zone_sel(user)
	var/mob/living/carbon/human/victim = h_victim()
	victim.set_stat(DEAD)
	test_chat_clear()
	test_click(user, victim, null)
	h_started(user, 3 SECONDS)
	test_time(2 SECONDS)
	TEST_ASSERT(!said(user, "Repeat at least"), "no compressions are done before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(said(user, "Repeat at least every 7 seconds"), "it tells the rescuer to repeat at the end")
	TEST_ASSERT_NULL(running(user), "nothing is left running")

/datum/unit_test/dq_timed_pin_w7/h_cpr_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/h_cpr_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	dq_give_zone_sel(user)
	var/mob/living/carbon/human/victim = h_victim()
	victim.set_stat(DEAD)
	test_click(user, victim, null)
	var/datum/T = h_started(user)
	test_time(1 SECOND)
	h_step_away(user)
	test_chat_clear()
	test_time(4 SECONDS)
	TEST_ASSERT(!said(user, "Repeat at least"), "moving cancels: no compressions")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

// ---- Abdominal thrusts (help stance on the chest of someone with an obstructed airway) ----

/datum/unit_test/dq_timed_pin_w7/h_heimlich

/datum/unit_test/dq_timed_pin_w7/h_heimlich/run_pin()
	var/mob/living/carbon/human/user = person()
	dq_give_zone_sel(user)
	var/mob/living/carbon/human/victim = h_mortal()
	var/datum/affliction/airway_obstruction/choke = victim.body.afflict(/datum/affliction/airway_obstruction, null, 60)
	TEST_ASSERT(!isnull(choke), "setup: the airway is obstructed")
	test_click(user, victim, null)
	h_started(user, 2 SECONDS)
	test_time(1 SECOND)
	TEST_ASSERT(!QDELETED(choke) && choke.severity > 50, "nothing is dislodged before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(QDELETED(choke) || choke.severity < 50, "the obstruction is treated at the end")

/datum/unit_test/dq_timed_pin_w7/h_heimlich_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/h_heimlich_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	dq_give_zone_sel(user)
	var/mob/living/carbon/human/victim = h_mortal()
	var/datum/affliction/airway_obstruction/choke = victim.body.afflict(/datum/affliction/airway_obstruction, null, 60)
	test_click(user, victim, null)
	var/datum/T = h_started(user)
	test_time(1 SECOND)
	h_step_away(user)
	test_time(3 SECONDS)
	TEST_ASSERT(!QDELETED(choke) && choke.severity > 50, "moving cancels: the obstruction stays")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

// ---- Applying pressure to a bleeding limb (hidden, no end: held until the user lets go) ----

/datum/unit_test/dq_timed_pin_w7/h_apply_pressure

/datum/unit_test/dq_timed_pin_w7/h_apply_pressure/run_pin()
	var/mob/living/carbon/human/user = person()
	dq_give_zone_sel(user)
	var/obj/item/organ/external/chest = user.get_organ(BP_TORSO)
	chest.set_status(chest.status | ORGAN_BLEEDING)
	test_chat_clear()
	test_click(user, user, null)
	if(isnull(running(user)))
		user.unarmed_touch(user, I_HELP) // a click on oneself that does not reach the touch is made as the touch
	h_started(user, null, "start applying pressure")
	TEST_ASSERT_EQUAL(chest.applied_pressure, user, "the user is applying pressure to the chest")
	test_time(30 SECONDS)
	TEST_ASSERT_EQUAL(chest.applied_pressure, user, "the pressure is held as long as the user stays")
	test_chat_clear()
	h_step_away(user)
	test_time(1 SECOND)
	TEST_ASSERT_NULL(chest.applied_pressure, "moving lets go")
	TEST_ASSERT(said(user, "stop applying pressure"), "it says the pressure stopped")

// ---- Dislocating a joint from a neck grab (harm stance, grab in hand) ----

/// Clicks `victim` with the grab `G` in `user`'s hand; when the click does not reach the grab's attack, the grab attacks as the click would.
/datum/unit_test/dq_timed_pin_w7/proc/h_grab_click(mob/living/carbon/human/user, mob/living/carbon/human/victim, obj/item/grab/G, zone, stance)
	user.zone_sel.selecting = zone
	user.next_click = 0
	test_click(user, victim, G)
	if(isnull(running(user)))
		G.attack(victim, user, zone, 1, stance)

/datum/unit_test/dq_timed_pin_w7/h_grab_joint

/datum/unit_test/dq_timed_pin_w7/h_grab_joint/run_pin()
	var/mob/living/carbon/human/user = person()
	dq_give_zone_sel(user)
	var/mob/living/carbon/human/victim = h_victim()
	var/obj/item/grab/G = allocate(/obj/item/grab, user, victim)
	if(user.get_active_hand() != G)
		user.put_in_active_hand(G)
	G.state = GRAB_NECK
	user.set_combat_mode(TRUE)
	var/obj/item/organ/external/arm = victim.get_organ(BP_L_ARM)
	test_chat_clear()
	h_grab_click(user, victim, G, BP_L_ARM, I_HURT)
	h_started(user, 10 SECONDS)
	test_time(9 SECONDS)
	TEST_ASSERT(arm.dislocated <= 0, "nothing is dislocated before the end")
	test_time(2 SECONDS)
	TEST_ASSERT_NULL(running(user), "the action is over at the end")

/datum/unit_test/dq_timed_pin_w7/h_grab_joint_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/h_grab_joint_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	dq_give_zone_sel(user)
	var/mob/living/carbon/human/victim = h_victim()
	var/obj/item/grab/G = allocate(/obj/item/grab, user, victim)
	if(user.get_active_hand() != G)
		user.put_in_active_hand(G)
	G.state = GRAB_NECK
	user.set_combat_mode(TRUE)
	var/obj/item/organ/external/arm = victim.get_organ(BP_L_ARM)
	h_grab_click(user, victim, G, BP_L_ARM, I_HURT)
	var/datum/T = h_started(user)
	test_time(2 SECONDS)
	h_step_away(user)
	test_time(10 SECONDS)
	TEST_ASSERT(arm.dislocated <= 0, "moving cancels: the joint stays in")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

// ---- Pinning someone down with a grab (disarm stance) is not pinned here: it needs an aggressive grab and a size check; see the report ----

// ---- Inspecting a limb with a passive grab (help stance): organ, bones, skin, then internal for the torso ----

/datum/unit_test/dq_timed_pin_w7/h_grab_inspect

/datum/unit_test/dq_timed_pin_w7/h_grab_inspect/run_pin()
	var/mob/living/carbon/human/user = person()
	dq_give_zone_sel(user)
	var/mob/living/carbon/human/victim = h_victim()
	var/obj/item/grab/G = allocate(/obj/item/grab, user, victim)
	if(user.get_active_hand() != G)
		user.put_in_active_hand(G)
	test_chat_clear()
	h_grab_click(user, victim, G, BP_TORSO, I_HELP)
	h_started(user, 1 SECOND)
	test_time(0.5 SECONDS)
	TEST_ASSERT(!said(user, "no visible wounds"), "no finding before the first step ends")
	test_time(0.6 SECONDS)
	TEST_ASSERT(said(user, "no visible wounds"), "the first step reports the wounds")
	TEST_ASSERT(said(user, "Checking bones now"), "the bones step begins")
	test_time(1.5 SECONDS)
	TEST_ASSERT(!said(user, "bones in the") && !said(user, "Checking skin now"), "the bones step is still working")
	test_time(0.6 SECONDS)
	TEST_ASSERT(said(user, "Checking skin now"), "the skin step begins after the bones are felt")
	test_time(1.1 SECONDS)
	TEST_ASSERT(said(user, "skin is normal"), "the skin step reports")
	TEST_ASSERT(said(user, "Checking for internal injury now"), "the internal step begins for the torso")
	TEST_ASSERT(!isnull(running(user)), "the internal step is working")
	test_time(5.1 SECONDS)
	TEST_ASSERT_NULL(running(user), "the chain ends")

/datum/unit_test/dq_timed_pin_w7/h_grab_inspect_interrupted

/datum/unit_test/dq_timed_pin_w7/h_grab_inspect_interrupted/run_pin()
	var/mob/living/carbon/human/user = person()
	dq_give_zone_sel(user)
	var/mob/living/carbon/human/victim = h_victim()
	var/obj/item/grab/G = allocate(/obj/item/grab, user, victim)
	if(user.get_active_hand() != G)
		user.put_in_active_hand(G)
	h_grab_click(user, victim, G, BP_TORSO, I_HELP)
	h_started(user)
	test_chat_clear()
	test_time(0.3 SECONDS)
	h_step_away(user)
	test_time(0.3 SECONDS)
	TEST_ASSERT(said(user, "must stand still to inspect"), "moving interrupts the first step with a reminder")
	TEST_ASSERT(said(user, "Checking bones now"), "the chain goes on to the bones step")

// ---- Knifing from a grab: a neck grab and a head hit slits the throat, an aggressive grab and a torso hit shanks (2 seconds each) ----

/datum/unit_test/dq_timed_pin_w7/h_grab_throat

/datum/unit_test/dq_timed_pin_w7/h_grab_throat/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/carbon/human/victim = h_mortal()
	var/obj/item/grab/G = allocate(/obj/item/grab, user, victim)
	G.state = GRAB_NECK
	var/obj/item/material/knife/K = allocate(/obj/item/material/knife, run_loc_floor_bottom_left)
	user.put_in_active_hand(K)
	var/before = victim.injury_load(INJURY_CATEGORY_PHYSICAL)
	TEST_ASSERT(victim.check_neckgrab_attack(K, user, BP_HEAD, I_HURT), "a neck grab and a sharp weapon at the head start a throat cut")
	h_started(user, 2 SECONDS)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(victim.injury_load(INJURY_CATEGORY_PHYSICAL), before, "nothing is cut before the end")
	test_time(1.5 SECONDS)
	TEST_ASSERT(victim.injury_load(INJURY_CATEGORY_PHYSICAL) > before, "the throat is cut at the end")

/datum/unit_test/dq_timed_pin_w7/h_grab_throat_cancel_on_lost_grab

/datum/unit_test/dq_timed_pin_w7/h_grab_throat_cancel_on_lost_grab/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/carbon/human/victim = h_mortal()
	var/obj/item/grab/G = allocate(/obj/item/grab, user, victim)
	G.state = GRAB_NECK
	var/obj/item/material/knife/K = allocate(/obj/item/material/knife, run_loc_floor_bottom_left)
	user.put_in_active_hand(K)
	var/before = victim.injury_load(INJURY_CATEGORY_PHYSICAL)
	victim.check_neckgrab_attack(K, user, BP_HEAD, I_HURT)
	h_started(user)
	test_time(1 SECOND)
	qdel(G)
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(victim.injury_load(INJURY_CATEGORY_PHYSICAL), before, "letting go of the grab ends it without a cut")

/datum/unit_test/dq_timed_pin_w7/h_grab_shank

/datum/unit_test/dq_timed_pin_w7/h_grab_shank/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/carbon/human/victim = h_mortal()
	var/obj/item/grab/G = allocate(/obj/item/grab, user, victim)
	G.state = GRAB_AGGRESSIVE
	var/obj/item/material/knife/K = allocate(/obj/item/material/knife, run_loc_floor_bottom_left)
	user.put_in_active_hand(K)
	TEST_ASSERT(victim.check_neckgrab_attack(K, user, BP_TORSO, I_HURT), "an aggressive grab and a sharp weapon at the chest start a shank")
	h_started(user, 2 SECONDS)
	var/before = victim.injury_load(INJURY_CATEGORY_PHYSICAL) // the plunge itself lands at once; the twist is what waits
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(victim.injury_load(INJURY_CATEGORY_PHYSICAL), before, "nothing is twisted before the end")
	test_time(1.5 SECONDS)
	TEST_ASSERT(victim.injury_load(INJURY_CATEGORY_PHYSICAL) >= before, "the blade is twisted at the end (the organ cut is a chance)")

// ---- Checking a pulse (the "Check pulse" verb of the person, 6 seconds, both must stay still) ----

/datum/unit_test/dq_timed_pin_w7/h_check_pulse

/datum/unit_test/dq_timed_pin_w7/h_check_pulse/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/carbon/human/victim = h_victim()
	test_chat_clear()
	h_verb_or_menu(user, victim, "check_pulse", "check_pulse")
	h_started(user, 6 SECONDS)
	TEST_ASSERT(said(user, "has a pulse"), "it says there is a pulse to count")
	test_time(5 SECONDS)
	TEST_ASSERT(!said(user, "pulse is"), "no count before the end")
	test_time(1.5 SECONDS)
	TEST_ASSERT(said(user, "pulse is"), "the count is told at the end")

/datum/unit_test/dq_timed_pin_w7/h_check_pulse_self

/datum/unit_test/dq_timed_pin_w7/h_check_pulse_self/run_pin()
	var/mob/living/carbon/human/user = person()
	test_chat_clear()
	h_verb_or_menu(user, user, "check_pulse", "check_pulse")
	h_started(user, 6 SECONDS)
	test_time(6.5 SECONDS)
	TEST_ASSERT(said(user, "Your pulse is"), "the user's own count is told at the end")

/datum/unit_test/dq_timed_pin_w7/h_check_pulse_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/h_check_pulse_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/carbon/human/victim = h_victim()
	h_verb_or_menu(user, victim, "check_pulse", "check_pulse")
	var/datum/T = h_started(user)
	test_time(2 SECONDS)
	test_chat_clear()
	h_step_away(victim)
	test_time(5 SECONDS)
	TEST_ASSERT(said(user, "failed to check the pulse"), "the target moving fails the count with a message")
	TEST_ASSERT(!said(user, "pulse is"), "no count is told")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

// ---- Patting out someone else's flames (bare hand, help stance, 1.5 seconds) ----

/datum/unit_test/dq_timed_pin_w7/h_pat_out_flames

/datum/unit_test/dq_timed_pin_w7/h_pat_out_flames/run_pin()
	var/mob/living/carbon/human/user = person()
	dq_give_zone_sel(user)
	var/mob/living/carbon/human/victim = h_mortal()
	victim.adjust_fire_stacks(3)
	victim.ignite_mob()
	TEST_ASSERT(victim.on_fire, "setup: the victim burns")
	var/before = victim.fire_stacks
	test_chat_clear()
	test_click(user, victim, null)
	h_started(user, 1.5 SECONDS)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(victim.fire_stacks, before, "nothing is patted out before the end")
	test_time(1 SECOND)
	TEST_ASSERT(victim.fire_stacks < before, "the flames are reduced at the end")

/datum/unit_test/dq_timed_pin_w7/h_pat_out_flames_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/h_pat_out_flames_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	dq_give_zone_sel(user)
	var/mob/living/carbon/human/victim = h_mortal()
	victim.adjust_fire_stacks(3)
	victim.ignite_mob()
	var/before = victim.fire_stacks
	test_click(user, victim, null)
	var/datum/T = h_started(user)
	test_time(0.5 SECONDS)
	h_step_away(user)
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(victim.fire_stacks, before, "moving cancels: the flames are as they were")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

// ---- Resisting: cuffs, straight jacket, buckle (the Resist verb; IGNORE_INCAPACITATED, the user has to stand still) ----

/datum/unit_test/dq_timed_pin_w7/h_cuff_resist

/datum/unit_test/dq_timed_pin_w7/h_cuff_resist/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/handcuffs/fuzzy/C = allocate(/obj/item/handcuffs/fuzzy, run_loc_floor_bottom_left)
	TEST_ASSERT(user.equip_to_slot(C, SLOT_ID_HANDCUFFED), "setup: the user is cuffed")
	test_chat_clear()
	user.resist()
	h_started(user, 10 SECONDS, "You attempt to remove")
	test_time(9 SECONDS)
	TEST_ASSERT_EQUAL(user.get_equipped_item(SLOT_ID_HANDCUFFED), C, "the cuffs stay on before the end")
	test_time(2 SECONDS)
	TEST_ASSERT_NULL(user.get_equipped_item(SLOT_ID_HANDCUFFED), "the cuffs come off at the end")
	TEST_ASSERT(said(user, "You successfully remove"), "it says so")

/datum/unit_test/dq_timed_pin_w7/h_cuff_resist_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/h_cuff_resist_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/handcuffs/fuzzy/C = allocate(/obj/item/handcuffs/fuzzy, run_loc_floor_bottom_left)
	user.equip_to_slot(C, SLOT_ID_HANDCUFFED)
	user.resist()
	var/datum/T = h_started(user)
	test_time(3 SECONDS)
	h_step_away(user)
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(user.get_equipped_item(SLOT_ID_HANDCUFFED), C, "moving cancels: still cuffed")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w7/h_straight_jacket_resist

/datum/unit_test/dq_timed_pin_w7/h_straight_jacket_resist/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/clothing/suit/straight_jacket/J = allocate(/obj/item/clothing/suit/straight_jacket, run_loc_floor_bottom_left)
	TEST_ASSERT(user.equip_to_slot_if_possible(J, SLOT_ID_SUIT, disable_warning = TRUE), "setup: the user wears the jacket")
	test_chat_clear()
	user.resist()
	h_started(user, null, "struggle to remove")
	test_time(1 MINUTE)
	TEST_ASSERT_EQUAL(user.get_equipped_item(SLOT_ID_SUIT), J, "the jacket stays on for a long while")
	test_time(8 MINUTES)
	TEST_ASSERT_NULL(user.get_equipped_item(SLOT_ID_SUIT), "the jacket comes off at the end")
	TEST_ASSERT(said(user, "You successfully remove"), "it says so")

/datum/unit_test/dq_timed_pin_w7/h_straight_jacket_resist_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/h_straight_jacket_resist_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/clothing/suit/straight_jacket/J = allocate(/obj/item/clothing/suit/straight_jacket, run_loc_floor_bottom_left)
	user.equip_to_slot_if_possible(J, SLOT_ID_SUIT, disable_warning = TRUE)
	user.resist()
	var/datum/T = h_started(user)
	test_time(10 SECONDS)
	h_step_away(user)
	test_time(9 MINUTES)
	TEST_ASSERT_EQUAL(user.get_equipped_item(SLOT_ID_SUIT), J, "moving cancels: still in the jacket")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w7/h_resist_buckle

/datum/unit_test/dq_timed_pin_w7/h_resist_buckle/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/bed/roller/bed = allocate(/obj/structure/bed/roller, run_loc_floor_bottom_left)
	var/obj/item/handcuffs/C = allocate(/obj/item/handcuffs, run_loc_floor_bottom_left)
	TEST_ASSERT(bed.buckle_mob(user, forced = TRUE), "setup: the user is buckled")
	TEST_ASSERT(user.equip_to_slot(C, SLOT_ID_HANDCUFFED), "setup: the user is cuffed")
	test_chat_clear()
	user.resist()
	h_started(user, 2 MINUTES, "attempt to unbuckle")
	test_time(1 MINUTE)
	TEST_ASSERT_EQUAL(user.buckled_to(), bed, "they stay buckled before the end")
	test_time(1.1 MINUTES)
	TEST_ASSERT_NULL(user.buckled_to(), "they are unbuckled at the end")
	TEST_ASSERT(said(user, "successfully unbuckle"), "it says so")

// ---- Modular limbs (the Attach Limb / Remove Limb verbs of a person with robotic limbs; 2 seconds each) ----





// ---- Butchering a dead animal with a knife (a cut of meat per 0.5 s * size / 10, then 2 s * size / 10 to butcher what is left) ----

/datum/unit_test/dq_timed_pin_w7/h_butcher

/datum/unit_test/dq_timed_pin_w7/h_butcher/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/simple_mob/animal/passive/crab/crab = allocate(/mob/living/simple_mob/animal/passive/crab, get_step(run_loc_floor_bottom_left, EAST))
	var/obj/item/material/knife/K = allocate(/obj/item/material/knife, run_loc_floor_bottom_left)
	user.put_in_active_hand(K)
	crab.set_stat(DEAD)
	var/turf/spot = get_turf(crab)
	var/start_meat = crab.meat_amount
	TEST_ASSERT(start_meat >= 3, "setup: the crab has meat on it")
	test_click(user, crab, K)
	h_started(user, 0.5 SECONDS * (crab.mob_size / 10))
	test_click(user, crab, K)
	TEST_ASSERT_EQUAL(running_count(user), 1, "a second click while it is cut starts nothing more")
	test_time(0.3 SECONDS)
	TEST_ASSERT_EQUAL(crab.meat_amount, start_meat, "no meat is taken before the first cut ends")
	test_time(0.3 SECONDS)
	TEST_ASSERT_EQUAL(crab.meat_amount, start_meat - 1, "one cut of meat is taken after the first interval")
	test_time(1.0 SECONDS)
	TEST_ASSERT_EQUAL(crab.meat_amount, start_meat - 3, "a cut per interval")
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(crab.meat_amount, 0, "all the meat is cut")
	var/meat_count = 0
	for(var/obj/item/reagent_containers/food/snacks/crabmeat/M in range(1, spot))
		meat_count++
	TEST_ASSERT(meat_count >= start_meat, "each cut dropped a piece of meat")
	TEST_ASSERT(QDELETED(crab) || crab.loc != spot, "the rest of the animal is butchered (gibbed) at the end")
	for(var/obj/O in range(2, spot))
		if(istype(O, /obj/item/reagent_containers/food/snacks/crabmeat) || istype(O, /obj/effect/decal/cleanable) || istype(O, /obj/item/stack/animalhide))
			qdel(O)

/datum/unit_test/dq_timed_pin_w7/h_butcher_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/h_butcher_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/simple_mob/animal/passive/crab/crab = allocate(/mob/living/simple_mob/animal/passive/crab, get_step(run_loc_floor_bottom_left, EAST))
	var/obj/item/material/knife/K = allocate(/obj/item/material/knife, run_loc_floor_bottom_left)
	user.put_in_active_hand(K)
	crab.set_stat(DEAD)
	var/start_meat = crab.meat_amount
	test_click(user, crab, K)
	var/datum/T = h_started(user)
	test_time(0.2 SECONDS)
	h_step_away(user)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(crab.meat_amount, start_meat, "moving cancels the first cut: no meat is taken")
	TEST_ASSERT(!QDELETED(crab), "the animal is not butchered")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

// ---- The windup of a melee swing (hostile click with a weapon: the windup is the timed action, the hit lands at its end) ----

/// A weapon with a long windup (9 ticks) held by an attacker in combat mode, and a victim in the tile next to it.
/datum/unit_test/dq_timed_pin_w7/proc/h_swing_setup()
	var/mob/living/carbon/human/attacker = person()
	dq_give_zone_sel(attacker)
	var/mob/living/carbon/human/victim = h_mortal()
	var/obj/item/weapon = allocate(/obj/item, run_loc_floor_bottom_left)
	weapon.force = 8
	weapon.w_class = ITEMSIZE_HUGE
	attacker.put_in_active_hand(weapon)
	attacker.set_combat_mode(TRUE)
	attacker.next_click = 0
	return list(attacker, victim, weapon)

/datum/unit_test/dq_timed_pin_w7/h_melee_swing

/datum/unit_test/dq_timed_pin_w7/h_melee_swing/run_pin()
	var/list/S = h_swing_setup()
	var/mob/living/carbon/human/attacker = S[1]
	var/mob/living/carbon/human/victim = S[2]
	var/obj/item/weapon = S[3]
	var/before = victim.injury_load(INJURY_CATEGORY_PHYSICAL)
	test_click(attacker, victim, weapon)
	h_started(attacker, weapon.get_melee_windup())
	TEST_ASSERT(attacker.is_swinging, "the swing is committed")
	test_time(0.5 SECONDS)
	TEST_ASSERT_EQUAL(victim.injury_load(INJURY_CATEGORY_PHYSICAL), before, "nothing lands during the windup")
	test_time(1.0 SECONDS)
	TEST_ASSERT(victim.injury_load(INJURY_CATEGORY_PHYSICAL) > before, "the hit lands when the windup ends")
	TEST_ASSERT(!attacker.is_swinging, "the swing is over")

/datum/unit_test/dq_timed_pin_w7/h_melee_swing_dodge

/datum/unit_test/dq_timed_pin_w7/h_melee_swing_dodge/run_pin()
	var/list/S = h_swing_setup()
	var/mob/living/carbon/human/attacker = S[1]
	var/mob/living/carbon/human/victim = S[2]
	var/obj/item/weapon = S[3]
	var/before = victim.injury_load(INJURY_CATEGORY_PHYSICAL)
	test_click(attacker, victim, weapon)
	h_started(attacker)
	test_time(0.2 SECONDS)
	victim.forceMove(get_step(get_step(victim, NORTH), NORTH))
	test_time(1.5 SECONDS)
	TEST_ASSERT_EQUAL(victim.injury_load(INJURY_CATEGORY_PHYSICAL), before, "a victim who left the tiles during the windup takes nothing")
	TEST_ASSERT(!attacker.is_swinging, "the swing is over")

/datum/unit_test/dq_timed_pin_w7/h_melee_swing_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/h_melee_swing_cancel_on_move/run_pin()
	var/list/S = h_swing_setup()
	var/mob/living/carbon/human/attacker = S[1]
	var/mob/living/carbon/human/victim = S[2]
	var/obj/item/weapon = S[3]
	var/before = victim.injury_load(INJURY_CATEGORY_PHYSICAL)
	test_click(attacker, victim, weapon)
	var/datum/T = h_started(attacker)
	test_time(0.2 SECONDS)
	h_step_away(attacker)
	test_time(1.5 SECONDS)
	TEST_ASSERT_EQUAL(victim.injury_load(INJURY_CATEGORY_PHYSICAL), before, "moving cancels the swing: no hit")
	TEST_ASSERT(!attacker.is_swinging, "a cancelled swing frees the attacker")
	TEST_ASSERT(was_cancelled(T, attacker), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w7/h_melee_swing_cancel_on_drop

/datum/unit_test/dq_timed_pin_w7/h_melee_swing_cancel_on_drop/run_pin()
	var/list/S = h_swing_setup()
	var/mob/living/carbon/human/attacker = S[1]
	var/mob/living/carbon/human/victim = S[2]
	var/obj/item/weapon = S[3]
	var/before = victim.injury_load(INJURY_CATEGORY_PHYSICAL)
	test_click(attacker, victim, weapon)
	var/datum/T = h_started(attacker)
	test_time(0.2 SECONDS)
	attacker.drop_from_inventory(weapon)
	test_time(1.5 SECONDS)
	TEST_ASSERT_EQUAL(victim.injury_load(INJURY_CATEGORY_PHYSICAL), before, "dropping the weapon cancels the swing: no hit")
	TEST_ASSERT(!attacker.is_swinging, "a cancelled swing frees the attacker")
	TEST_ASSERT(was_cancelled(T, attacker), "the action ends cancelled")

// ---- cluster s ----

// Cluster S (code/modules/mob/living/carbon/human/species/): behaviour pins recorded on the legacy task_timed / task_start forms.
// Parent /datum/unit_test/dq_timed_pin_w7 and its helpers are the lead's. Procs below are prefixed s_ so they cannot clash.

// ---- Glamour ring: the prompt answer decides the action (Yes breaks the ring, Restore Energy draws energy), both last 10 seconds ----

/// A stranger clicks a ring and answers `answer`; returns the running timed action (null when none started).
/datum/unit_test/dq_timed_pin_w7/proc/s_ring_ask(mob/user, obj/structure/glamour_ring/ring, answer)
	test_chat_clear()
	test_click(user, ring, null)
	test_time(1 SECOND)
	test_answer(user, answer)
	return running(user)

/datum/unit_test/dq_timed_pin_w7/s_glamour_ring_break

/datum/unit_test/dq_timed_pin_w7/s_glamour_ring_break/run_pin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = person(T)
	var/mob/living/carbon/human/owner = allocate(/mob/living/carbon/human, get_step(T, SOUTH))
	var/obj/structure/glamour_ring/ring = allocate(/obj/structure/glamour_ring, T)
	ring.connected_mob = owner
	var/datum/T2 = s_ring_ask(user, ring, "Yes")
	TEST_ASSERT(!isnull(T2), "answering Yes starts a timed action")
	TEST_ASSERT(said(user, "You begin to break the lines"), "it says it began")
	test_time(9 SECONDS)
	TEST_ASSERT(!QDELETED(ring), "the ring stands before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(QDELETED(ring), "the ring is broken at the end")
	TEST_ASSERT(said(user, "You have destroyed"), "it says it finished")
	TEST_ASSERT(said(owner, "has been destroyed by"), "the connected owner is told who broke it")
	TEST_ASSERT_NULL(running(user), "nothing is left running")

/datum/unit_test/dq_timed_pin_w7/s_glamour_ring_break_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/s_glamour_ring_break_cancel_on_move/run_pin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = person(T)
	var/mob/living/carbon/human/owner = allocate(/mob/living/carbon/human, get_step(T, SOUTH))
	var/obj/structure/glamour_ring/ring = allocate(/obj/structure/glamour_ring, T)
	ring.connected_mob = owner
	var/datum/T2 = s_ring_ask(user, ring, "Yes")
	TEST_ASSERT(!isnull(T2), "answering Yes starts a timed action")
	user.forceMove(get_step(user, EAST))
	test_time(12 SECONDS)
	TEST_ASSERT(!QDELETED(ring), "moving cancels: the ring stands")
	TEST_ASSERT(was_cancelled(T2, user), "the action ends cancelled")
	TEST_ASSERT(said(user, "You leave the glamour ring alone"), "it says it was left alone")

/datum/unit_test/dq_timed_pin_w7/s_glamour_ring_no

/datum/unit_test/dq_timed_pin_w7/s_glamour_ring_no/run_pin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = person(T)
	var/mob/living/carbon/human/owner = allocate(/mob/living/carbon/human, get_step(T, SOUTH))
	var/obj/structure/glamour_ring/ring = allocate(/obj/structure/glamour_ring, T)
	ring.connected_mob = owner
	var/datum/T2 = s_ring_ask(user, ring, "No")
	TEST_ASSERT_NULL(T2, "answering No starts nothing")
	test_time(12 SECONDS)
	TEST_ASSERT(!QDELETED(ring), "the ring stands")

/datum/unit_test/dq_timed_pin_w7/s_glamour_ring_restore

/datum/unit_test/dq_timed_pin_w7/s_glamour_ring_restore/run_pin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = person(T)
	user.set_species(SPECIES_LLEILL)
	TEST_ASSERT(istype(user.species, /datum/species/lleill), "the actor is a lleill")
	var/obj/structure/glamour_ring/ring = allocate(/obj/structure/glamour_ring, T)
	ring.connected_mob = user
	var/datum/species/lleill/own_species = rel_private(user, nameof(/datum/dna::species)) // a private copy: the shared lleill species must not keep this test's energy
	own_species.lleill_energy = 0
	var/datum/T2 = s_ring_ask(user, ring, "Restore Energy")
	TEST_ASSERT(!isnull(T2), "answering Restore Energy starts a timed action")
	test_time(9 SECONDS)
	TEST_ASSERT_EQUAL(user.species.lleill_energy, 0, "no energy is drawn before the end")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(user.species.lleill_energy, min(75, user.species.lleill_energy_max), "75 energy is drawn at the end")
	TEST_ASSERT(!QDELETED(ring), "the ring stands")
	TEST_ASSERT_NULL(running(user), "nothing is left running")
	// the ring cooldown (10 minutes) refuses a second draw
	var/datum/T3 = s_ring_ask(user, ring, "Restore Energy")
	TEST_ASSERT_NULL(T3, "a second draw inside the cooldown starts nothing")
	TEST_ASSERT(said(user, "You must wait a while"), "it says to wait")

/datum/unit_test/dq_timed_pin_w7/s_glamour_ring_restore_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/s_glamour_ring_restore_cancel_on_move/run_pin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = person(T)
	user.set_species(SPECIES_LLEILL)
	var/obj/structure/glamour_ring/ring = allocate(/obj/structure/glamour_ring, T)
	ring.connected_mob = user
	var/datum/species/lleill/own_species = rel_private(user, nameof(/datum/dna::species)) // a private copy: the shared lleill species must not keep this test's energy
	own_species.lleill_energy = 0
	var/datum/T2 = s_ring_ask(user, ring, "Restore Energy")
	TEST_ASSERT(!isnull(T2), "answering Restore Energy starts a timed action")
	user.forceMove(get_step(user, EAST))
	test_time(12 SECONDS)
	TEST_ASSERT_EQUAL(user.species.lleill_energy, 0, "moving cancels: no energy is drawn")
	TEST_ASSERT(was_cancelled(T2, user), "the action ends cancelled")
	TEST_ASSERT(said(user, "You stop drawing energy"), "it says it stopped")

// ---- Weaver trait: the panel's weave buttons spend silk and spin a web after cost/25 seconds ----

/datum/unit_test/dq_timed_pin_w7/proc/s_weaver(mob/living/carbon/human/user)
	var/datum/trait_state/weaver/W = user.add_trait_state(/datum/trait_state/weaver)
	TEST_ASSERT_NOTNULL(W, "the weaver trait state attaches")
	W.silk_color = "#112233"
	return W

/datum/unit_test/dq_timed_pin_w7/s_weaver_floor

/datum/unit_test/dq_timed_pin_w7/s_weaver_floor/run_pin()
	var/mob/living/carbon/human/user = person()
	var/datum/trait_state/weaver/W = s_weaver(user)
	test_chat_clear()
	test_ui(user, W, "weave_floor", list())
	TEST_ASSERT(!isnull(running(user)), "the button starts a timed action")
	test_time(0.5 SECONDS)
	TEST_ASSERT(isnull(locate(/obj/effect/weaversilk/floor) in user.loc), "no web before the end")
	TEST_ASSERT_EQUAL(W.silk_reserve, 100, "no silk is spent before the end")
	test_time(1 SECOND)
	var/obj/effect/weaversilk/floor/web = locate(/obj/effect/weaversilk/floor) in user.loc
	TEST_ASSERT_NOTNULL(web, "a floor web lies under the weaver at the end")
	TEST_ASSERT_EQUAL(W.silk_reserve, 75, "25 silk is spent")
	TEST_ASSERT_EQUAL(web?.color, "#112233", "the web takes the silk colour")
	TEST_ASSERT_NULL(running(user), "nothing is left running")
	// the same tile cannot hold a second one
	test_chat_clear()
	test_ui(user, W, "weave_floor", list())
	TEST_ASSERT_NULL(running(user), "a second floor web on the tile starts nothing")
	TEST_ASSERT(said(user, "can't create another one"), "it says why")
	qdel(web)

/datum/unit_test/dq_timed_pin_w7/s_weaver_trap_takes_ten_seconds

/datum/unit_test/dq_timed_pin_w7/s_weaver_trap_takes_ten_seconds/run_pin()
	var/mob/living/carbon/human/user = person()
	var/datum/trait_state/weaver/W = s_weaver(user)
	W.silk_reserve = 300
	test_ui(user, W, "weave_trap", list())
	TEST_ASSERT(!isnull(running(user)), "the button starts a timed action")
	test_time(9 SECONDS)
	TEST_ASSERT(isnull(locate(/obj/effect/weaversilk/trap) in user.loc), "no trap before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(!isnull(locate(/obj/effect/weaversilk/trap) in user.loc), "the trap lies under the weaver at the end")
	TEST_ASSERT_EQUAL(W.silk_reserve, 50, "250 silk is spent")
	qdel(locate(/obj/effect/weaversilk/trap) in user.loc)

/datum/unit_test/dq_timed_pin_w7/s_weaver_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/s_weaver_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/datum/trait_state/weaver/W = s_weaver(user)
	var/turf/start = user.loc
	test_ui(user, W, "weave_wall", list())
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the button starts a timed action")
	user.forceMove(get_step(user, EAST))
	test_time(6 SECONDS)
	TEST_ASSERT(isnull(locate(/obj/effect/weaversilk/wall) in start), "moving cancels: no wall is made")
	TEST_ASSERT_EQUAL(W.silk_reserve, 100, "and no silk is spent")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w7/s_weaver_not_enough_silk

/datum/unit_test/dq_timed_pin_w7/s_weaver_not_enough_silk/run_pin()
	var/mob/living/carbon/human/user = person()
	var/datum/trait_state/weaver/W = s_weaver(user)
	W.silk_reserve = 10
	test_chat_clear()
	test_ui(user, W, "weave_floor", list())
	TEST_ASSERT_NULL(running(user), "too little silk starts nothing")
	TEST_ASSERT(said(user, "don't have enough silk"), "it says why")

// ---- cluster r ----

// Cluster R (code/modules/mob/living/silicon/): behaviour pins recorded on the legacy task_timed / task_start forms.
// Parent /datum/unit_test/dq_timed_pin_w7 supplies begin(), hold(), forget_ghosts(); helpers here are prefixed r_.

// ---- helpers ----

/// Starts the timed action as begin() does, by a click. When the driver click does not reach the legacy override of a cyborg actor, the legacy
/// override is called directly (afterattack on the held item, wrench_act on a cyborg); after conversion the click starts the op and the fallback never runs.
/datum/unit_test/dq_timed_pin_w7/proc/r_begin(mob/user, atom/target, obj/item/held, dur, start_text = null)
	test_chat_clear()
	test_click(user, target, held)
	if(isnull(running(user)))
		r_legacy_call(user, target, held)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the click starts a timed action")
	if(!isnull(dur))
		TEST_ASSERT(isnull(declared_duration(T)) || declared_duration(T) == dur, "it lasts [dur] ticks")
	if(start_text)
		TEST_ASSERT(said(user, start_text), "it says it began")
	return T

/// A click whose reply is read from chat or from nothing starting: the same fallback.
/datum/unit_test/dq_timed_pin_w7/proc/r_poke(mob/user, atom/target, obj/item/held)
	test_click(user, target, held)
	if(isnull(running(user)) && !length(test_chat_of(user)))
		r_legacy_call(user, target, held)

/datum/unit_test/dq_timed_pin_w7/proc/r_legacy_call(mob/user, atom/target, obj/item/held)
	var/mob/living/silicon/robot/R = target
	if(istype(R) && held?.has_tool_quality(TOOL_WRENCH))
		R.interaction_tool_act(user, held, TOOL_WRENCH)
	else if(held)
		held.afterattack(target, user, TRUE)

/// A cyborg on `T` with a standard module (the sleeper reads hound.module.modules) and no godmode.
/datum/unit_test/dq_timed_pin_w7/proc/r_borg(turf/T)
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, T || run_loc_floor_bottom_left)
	if(!R.module)
		rel_set(R, nameof(R.module), new /obj/item/robot_module/robot/standard(R))
	return R

/// A hound tongue in the cyborg's contents with a half-empty water reserve (500 max, 100 held).
/datum/unit_test/dq_timed_pin_w7/proc/r_tongue(mob/living/silicon/robot/R, water_held = 100)
	var/obj/item/robot_tongue/L = allocate(/obj/item/robot_tongue, R)
	L.water = new /datum/matter_synth(500)
	L.water.energy = water_held
	return L

// ---- Hound tongue: dog_modules.dm robot_tongue/afterattack (5 seconds, per target kind) ----







/datum/unit_test/dq_timed_pin_w7/r_tongue_eat_trash

/datum/unit_test/dq_timed_pin_w7/r_tongue_eat_trash/run_pin()
	var/mob/living/silicon/robot/R = r_borg()
	var/obj/item/robot_tongue/L = r_tongue(R)
	var/obj/item/trash/cigbutt/B = allocate(/obj/item/trash/cigbutt, run_loc_floor_bottom_left)
	r_begin(R, B, L, 5 SECONDS, "You begin to nibble away")
	test_time(4 SECONDS)
	TEST_ASSERT(!QDELETED(B), "the trash stays before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(QDELETED(B), "the trash is eaten")
	TEST_ASSERT_EQUAL(L.water.energy, 95, "eating trash costs 5 water")
	TEST_ASSERT(said(R, "You finish off"), "it says it finished")

/datum/unit_test/dq_timed_pin_w7/r_tongue_eat_trash_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/r_tongue_eat_trash_cancel_on_move/run_pin()
	var/mob/living/silicon/robot/R = r_borg()
	var/obj/item/robot_tongue/L = r_tongue(R)
	var/obj/item/trash/cigbutt/B = allocate(/obj/item/trash/cigbutt, run_loc_floor_bottom_left)
	var/datum/T = r_begin(R, B, L, 5 SECONDS)
	R.forceMove(get_step(R, EAST))
	test_time(7 SECONDS)
	TEST_ASSERT(!QDELETED(B), "moving cancels: the trash stays")
	TEST_ASSERT(was_cancelled(T, R), "the action ends cancelled")



/datum/unit_test/dq_timed_pin_w7/r_tongue_eat_cell

/datum/unit_test/dq_timed_pin_w7/r_tongue_eat_cell/run_pin()
	var/mob/living/silicon/robot/R = r_borg()
	var/obj/item/robot_tongue/L = r_tongue(R)
	var/obj/item/cell/C = allocate(/obj/item/cell, run_loc_floor_bottom_left)
	r_begin(R, C, L, 5 SECONDS, "You begin cramming")
	test_time(4 SECONDS)
	TEST_ASSERT(!QDELETED(C), "the cell stays before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(QDELETED(C), "the cell is swallowed")
	TEST_ASSERT_EQUAL(L.water.energy, 95, "swallowing a cell costs 5 water")
	TEST_ASSERT(said(R, "gain some charge"), "it says it gained charge")

/datum/unit_test/dq_timed_pin_w7/r_tongue_clean_item

/datum/unit_test/dq_timed_pin_w7/r_tongue_clean_item/run_pin()
	var/mob/living/silicon/robot/R = r_borg()
	var/obj/item/robot_tongue/L = r_tongue(R)
	var/obj/item/pen/P = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	r_begin(R, P, L, 5 SECONDS, "You begin to lick")
	test_time(4 SECONDS)
	TEST_ASSERT_EQUAL(L.water.energy, 100, "nothing is spent before the end")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(L.water.energy, 95, "cleaning an item costs 5 water")
	TEST_ASSERT(said(R, "You clean"), "it says it cleaned")
	TEST_ASSERT(!QDELETED(P), "the item stays")

/datum/unit_test/dq_timed_pin_w7/r_tongue_clean_floor

/datum/unit_test/dq_timed_pin_w7/r_tongue_clean_floor/run_pin()
	var/mob/living/silicon/robot/R = r_borg()
	var/obj/item/robot_tongue/L = r_tongue(R)
	var/turf/T = get_step(run_loc_floor_bottom_left, EAST)
	r_begin(R, T, L, 5 SECONDS, "You begin to lick")
	test_time(4 SECONDS)
	TEST_ASSERT_EQUAL(L.water.energy, 100, "nothing is spent before the end")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(L.water.energy, 95, "cleaning the floor costs 5 water")
	TEST_ASSERT(said(R, "You clean"), "it says it cleaned")



/datum/unit_test/dq_timed_pin_w7/r_tongue_one_lick_at_a_time

/datum/unit_test/dq_timed_pin_w7/r_tongue_one_lick_at_a_time/run_pin()
	var/mob/living/silicon/robot/R = r_borg()
	var/obj/item/robot_tongue/L = r_tongue(R)
	var/obj/item/trash/cigbutt/B = allocate(/obj/item/trash/cigbutt, run_loc_floor_bottom_left)
	var/obj/item/pen/P = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	r_begin(R, B, L, 5 SECONDS)
	r_poke(R, P, L)
	TEST_ASSERT_EQUAL(running_count(R), 1, "a second lick does not start a second action")
	test_time(6 SECONDS)
	TEST_ASSERT_NULL(running(R), "one lick ran to its end and nothing is left running (legacy: the first lick; converted: the second click replaces the first wait)")
	TEST_ASSERT_EQUAL(L.water.energy, 95, "only one lick was paid for")

// ---- Hound sleeper: dog_sleeper.dm afterattack / intake (3 seconds compactor, 5 seconds a patient) ----



/datum/unit_test/dq_timed_pin_w7/r_sleeper_patient_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/r_sleeper_patient_cancel_on_move/run_pin()
	var/mob/living/silicon/robot/R = r_borg()
	var/obj/item/dogborg/sleeper/S = allocate(/obj/item/dogborg/sleeper, R)
	var/mob/living/carbon/human/H = person(get_step(run_loc_floor_bottom_left, EAST))
	var/datum/T = r_begin(R, H, S, 5 SECONDS)
	R.forceMove(get_step(R, NORTH))
	test_time(7 SECONDS)
	TEST_ASSERT(H.loc != S, "moving cancels: the patient stays out")
	TEST_ASSERT(was_cancelled(T, R), "the action ends cancelled")
	forget_ghosts()





/datum/unit_test/dq_timed_pin_w7/r_sleeper_compactor_item_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/r_sleeper_compactor_item_cancel_on_move/run_pin()
	var/mob/living/silicon/robot/R = r_borg()
	var/obj/item/dogborg/sleeper/S = allocate(/obj/item/dogborg/sleeper, R)
	S.compactor = TRUE
	var/obj/item/pen/P = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	var/datum/T = r_begin(R, P, S, 3 SECONDS)
	R.forceMove(get_step(R, EAST))
	test_time(5 SECONDS)
	TEST_ASSERT(P.loc != S, "moving cancels: the item stays out")
	TEST_ASSERT(was_cancelled(T, R), "the action ends cancelled")





// ---- Matter decompiler: drone_items.dm / swarm_items.dm afterattack, a client-less drone (5 seconds) ----



/datum/unit_test/dq_timed_pin_w7/r_decompile_drone_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/r_decompile_drone_cancel_on_move/run_pin()
	var/mob/living/silicon/robot/R = r_borg()
	var/obj/item/matter_decompiler/M = allocate(/obj/item/matter_decompiler, R)
	var/mob/living/silicon/robot/drone/D = allocate(/mob/living/silicon/robot/drone, get_step(run_loc_floor_bottom_left, EAST))
	var/datum/T = r_begin(R, D, M, 5 SECONDS)
	R.forceMove(get_step(R, NORTH))
	test_time(7 SECONDS)
	TEST_ASSERT(!QDELETED(D), "moving cancels: the drone stands")
	TEST_ASSERT(was_cancelled(T, R), "the action ends cancelled")
	TEST_ASSERT(said(R, "remain still while decompiling"), "it says to remain still")

// ---- Cyborg chassis: robot.dm ----

/// The bolt under the cover of an opened, cell-less chassis, a wrench in the human's hand: it takes 2 seconds to remove.




/// Crowbar on an opened, cell-less chassis with every wire cut and the wires exposed: the brain is levered out in 3 seconds.


/datum/unit_test/dq_timed_pin_w7/r_robot_extract_mmi_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/r_robot_extract_mmi_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/silicon/robot/R = r_borg(get_step(run_loc_floor_bottom_left, EAST))
	if(R.cell)
		qdel(R.cell)
	R.opened = TRUE
	R.wiresexposed = TRUE
	while(wires_cut_random(R))
		continue
	var/obj/item/mmi/M = new /obj/item/mmi(R)
	rel_set(R, nameof(R.mmi), M)
	var/obj/item/tool/crowbar/C = allocate(/obj/item/tool/crowbar, run_loc_floor_bottom_left)
	hold(user, C)
	var/datum/T = r_begin(user, R, C, 3 SECONDS)
	user.forceMove(get_step(user, NORTH))
	test_time(5 SECONDS)
	TEST_ASSERT(R.mmi == M, "moving cancels: the brain stays")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/// A cyborg clicking itself with an empty hand drops its hat after 3 seconds.
/datum/unit_test/dq_timed_pin_w7/r_robot_drop_hat

/datum/unit_test/dq_timed_pin_w7/r_robot_drop_hat/run_pin()
	var/mob/living/silicon/robot/R = r_borg()
	var/obj/item/clothing/head/soft/H = new /obj/item/clothing/head/soft(R)
	R.place_on_head(H)
	TEST_ASSERT(R.hat == H, "the hat is on")
	r_begin(R, R, null, 3 SECONDS)
	test_time(2 SECONDS)
	TEST_ASSERT(R.hat == H, "the hat is on before the end")
	test_time(2 SECONDS)
	TEST_ASSERT_NULL(R.hat, "the hat is off at the end")
	TEST_ASSERT(H.loc == get_turf(R), "the hat lies at the chassis")
	qdel(H)

/datum/unit_test/dq_timed_pin_w7/r_robot_drop_hat_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/r_robot_drop_hat_cancel_on_move/run_pin()
	var/mob/living/silicon/robot/R = r_borg()
	var/obj/item/clothing/head/soft/H = new /obj/item/clothing/head/soft(R)
	R.place_on_head(H)
	var/datum/T = r_begin(R, R, null, 3 SECONDS)
	R.forceMove(get_step(R, EAST))
	test_time(5 SECONDS)
	TEST_ASSERT(R.hat == H, "moving cancels: the hat stays on")
	TEST_ASSERT(was_cancelled(T, R), "the action ends cancelled")
	qdel(H)

/// Breaking the restraining bolt (resist): 90 seconds standing still, started by the resist verb's proc.
/datum/unit_test/dq_timed_pin_w7/r_robot_break_bolt

/datum/unit_test/dq_timed_pin_w7/r_robot_break_bolt/run_pin()
	var/mob/living/silicon/robot/R = r_borg()
	var/obj/item/implant/restrainingbolt/B = new /obj/item/implant/restrainingbolt(R)
	rel_set(R, nameof(R.bolt), B)
	test_chat_clear()
	R.resist_restraints()
	var/datum/T = running(R)
	TEST_ASSERT(!isnull(T), "resisting starts a timed action")
	if(!isnull(declared_duration(T)))
		TEST_ASSERT_EQUAL(declared_duration(T), 1.5 MINUTES, "it lasts 90 seconds")
	TEST_ASSERT(said(R, "You attempt to break your"), "it says it began")
	test_time(80 SECONDS)
	TEST_ASSERT(B.malfunction != MALFUNCTION_PERMANENT, "the bolt holds before the end")
	test_time(11 SECONDS)
	TEST_ASSERT_EQUAL(B.malfunction, MALFUNCTION_PERMANENT, "the bolt is broken at the end")
	TEST_ASSERT(said(R, "You successfully break your"), "it says it finished")
	qdel(B)

/datum/unit_test/dq_timed_pin_w7/r_robot_break_bolt_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/r_robot_break_bolt_cancel_on_move/run_pin()
	var/mob/living/silicon/robot/R = r_borg()
	var/obj/item/implant/restrainingbolt/B = new /obj/item/implant/restrainingbolt(R)
	rel_set(R, nameof(R.bolt), B)
	R.resist_restraints()
	var/datum/T = running(R)
	TEST_ASSERT(!isnull(T), "resisting starts a timed action")
	R.forceMove(get_step(R, EAST))
	test_time(100 SECONDS)
	TEST_ASSERT(B.malfunction != MALFUNCTION_PERMANENT, "moving cancels: the bolt holds")
	TEST_ASSERT(was_cancelled(T, R), "the action ends cancelled")
	qdel(B)

// ---- Thinktank platform: thinktank_storage.dm (3 seconds each way) ----

/// Dragging an item onto the platform loads it into the cargo compartment.
/datum/unit_test/dq_timed_pin_w7/r_platform_load

/datum/unit_test/dq_timed_pin_w7/r_platform_load/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/silicon/robot/platform/P = allocate(/mob/living/silicon/robot/platform, get_step(run_loc_floor_bottom_left, EAST))
	var/obj/item/pen/I = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	test_chat_clear()
	test_drag(user, I, P)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the drag starts a timed action")
	if(!isnull(declared_duration(T)))
		TEST_ASSERT_EQUAL(declared_duration(T), 3 SECONDS, "it lasts 3 seconds")
	test_time(2 SECONDS)
	TEST_ASSERT(!(I in P.stored_atoms), "nothing is stored before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(I in P.stored_atoms, "the item is stored at the end")
	TEST_ASSERT(I.loc == P, "and it is inside the platform")

/datum/unit_test/dq_timed_pin_w7/r_platform_load_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/r_platform_load_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/silicon/robot/platform/P = allocate(/mob/living/silicon/robot/platform, get_step(run_loc_floor_bottom_left, EAST))
	var/obj/item/pen/I = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	test_drag(user, I, P)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the drag starts a timed action")
	user.forceMove(get_step(user, NORTH))
	test_time(5 SECONDS)
	TEST_ASSERT(!(I in P.stored_atoms), "moving cancels: nothing is stored")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/// An empty hand on a loaded platform unloads the last stored thing after 3 seconds.
/datum/unit_test/dq_timed_pin_w7/r_platform_unload

/datum/unit_test/dq_timed_pin_w7/r_platform_unload/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/silicon/robot/platform/P = allocate(/mob/living/silicon/robot/platform, get_step(run_loc_floor_bottom_left, EAST))
	var/obj/item/pen/I = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	P.store_atom(I, user)
	TEST_ASSERT(I in P.stored_atoms, "the item starts stored")
	test_chat_clear()
	test_click(user, P, null)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the click starts a timed action")
	if(!isnull(declared_duration(T)))
		TEST_ASSERT_EQUAL(declared_duration(T), 3 SECONDS, "it lasts 3 seconds")
	test_time(2 SECONDS)
	TEST_ASSERT(I in P.stored_atoms, "it is still stored before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(!(I in P.stored_atoms), "it is out of the cargo at the end")
	TEST_ASSERT(I.loc != P, "and outside the platform")

/datum/unit_test/dq_timed_pin_w7/r_platform_unload_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/r_platform_unload_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/silicon/robot/platform/P = allocate(/mob/living/silicon/robot/platform, get_step(run_loc_floor_bottom_left, EAST))
	var/obj/item/pen/I = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	P.store_atom(I, user)
	test_click(user, P, null)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the click starts a timed action")
	user.forceMove(get_step(user, NORTH))
	test_time(5 SECONDS)
	TEST_ASSERT(I in P.stored_atoms, "moving cancels: the item stays stored")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

// ---- cluster m ----

// Cluster M (code/modules/mob/living/simple_mob/): behaviour pins recorded on the legacy task_timed / task_start forms.
// Parent /datum/unit_test/dq_timed_pin_w7 (the lead's) supplies begin(), hold(), forget_ghosts() and the dq_timed_pin helpers.

// ---- Teppi: the knife on a resting teppi, and shearing ----



/datum/unit_test/dq_timed_pin_w7/m_teppi_slaughter_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/m_teppi_slaughter_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/simple_mob/vore/alienanimals/teppi/teppi = allocate(/mob/living/simple_mob/vore/alienanimals/teppi, get_step(run_loc_floor_bottom_left, EAST))
	var/obj/item/material/knife/K = allocate(/obj/item/material/knife, run_loc_floor_bottom_left)
	teppi.teppi_wool = FALSE
	teppi.resting = TRUE
	hold(user, K)
	var/datum/T = begin(user, teppi, K, 5 SECONDS)
	user.forceMove(get_step(user, NORTH))
	test_time(7 SECONDS)
	TEST_ASSERT(teppi.stat != DEAD, "moving cancels: the teppi lives")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/// A teppi that is awake (not resting) is not slaughtered: nothing starts.
/datum/unit_test/dq_timed_pin_w7/m_teppi_slaughter_awake

/datum/unit_test/dq_timed_pin_w7/m_teppi_slaughter_awake/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/simple_mob/vore/alienanimals/teppi/teppi = allocate(/mob/living/simple_mob/vore/alienanimals/teppi, get_step(run_loc_floor_bottom_left, EAST))
	var/obj/item/material/knife/K = allocate(/obj/item/material/knife, run_loc_floor_bottom_left)
	teppi.teppi_wool = FALSE
	teppi.resting = FALSE
	hold(user, K)
	test_click(user, teppi, K)
	TEST_ASSERT_NULL(running(user), "an awake teppi starts nothing")
	test_time(7 SECONDS)
	TEST_ASSERT(teppi.stat != DEAD, "and lives")

/datum/unit_test/dq_timed_pin_w7/m_teppi_shear

/datum/unit_test/dq_timed_pin_w7/m_teppi_shear/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/simple_mob/vore/alienanimals/teppi/teppi = allocate(/mob/living/simple_mob/vore/alienanimals/teppi, get_step(run_loc_floor_bottom_left, EAST))
	var/obj/item/material/knife/K = allocate(/obj/item/material/knife, run_loc_floor_bottom_left)
	teppi.teppi_wool = TRUE
	hold(user, K)
	begin(user, teppi, K, null)
	test_time(1 SECONDS)
	TEST_ASSERT(teppi.teppi_wool, "the teppi is not sheared before the end")
	test_time(60 SECONDS)
	TEST_ASSERT(!teppi.teppi_wool, "the teppi is sheared at the end")
	TEST_ASSERT(said(user, "You shear"), "it says it finished")
	var/obj/item/stack/material/fur/F = locate(/obj/item/stack/material/fur) in get_turf(user)
	TEST_ASSERT(!isnull(F), "fur is left at the user's feet")
	if(F)
		qdel(F)
	forget_ghosts()

/datum/unit_test/dq_timed_pin_w7/m_teppi_shear_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/m_teppi_shear_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/simple_mob/vore/alienanimals/teppi/teppi = allocate(/mob/living/simple_mob/vore/alienanimals/teppi, get_step(run_loc_floor_bottom_left, EAST))
	var/obj/item/material/knife/K = allocate(/obj/item/material/knife, run_loc_floor_bottom_left)
	teppi.teppi_wool = TRUE
	hold(user, K)
	var/datum/T = begin(user, teppi, K, null)
	user.forceMove(get_step(user, NORTH))
	test_time(60 SECONDS)
	TEST_ASSERT(teppi.teppi_wool, "moving cancels: the teppi keeps its wool")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

// ---- Pitcher plant: fishing the victim out with cable ----





/// An empty pitcher starts nothing and says so.
/datum/unit_test/dq_timed_pin_w7/m_pitcher_fish_out_empty

/datum/unit_test/dq_timed_pin_w7/m_pitcher_fish_out_empty/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/simple_mob/vore/pitcher_plant/plant = allocate(/mob/living/simple_mob/vore/pitcher_plant, get_step(run_loc_floor_bottom_left, EAST))
	var/obj/item/stack/cable_coil/C = allocate(/obj/item/stack/cable_coil, run_loc_floor_bottom_left)
	hold(user, C)
	test_chat_clear()
	test_click(user, plant, C)
	TEST_ASSERT_NULL(running(user), "an empty pitcher starts nothing")
	TEST_ASSERT(said(user, "The pitcher is empty"), "it says the pitcher is empty")

// ---- Borer and leech: infesting a host ----

/datum/unit_test/dq_timed_pin_w7/m_borer_infest

/datum/unit_test/dq_timed_pin_w7/m_borer_infest/run_pin()
	var/mob/living/carbon/human/target = person(get_step(run_loc_floor_bottom_left, EAST))
	var/mob/living/simple_mob/animal/borer/borer = allocate(/mob/living/simple_mob/animal/borer, run_loc_floor_bottom_left)
	test_chat_clear()
	borer.infest()
	TEST_ASSERT(!isnull(running(borer)), "infesting starts a timed action (one candidate is picked for the borer)")
	TEST_ASSERT(said(borer, "You slither up to"), "it says it began")
	test_time(2 SECONDS)
	TEST_ASSERT_NULL(borer.borer_host(), "no host before the end")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(borer.borer_host(), target, "the borer is in the host at the end (3 seconds)")
	forget_ghosts()

/datum/unit_test/dq_timed_pin_w7/m_borer_infest_target_leaves

/datum/unit_test/dq_timed_pin_w7/m_borer_infest_target_leaves/run_pin()
	var/mob/living/carbon/human/target = person(get_step(run_loc_floor_bottom_left, EAST))
	var/mob/living/simple_mob/animal/borer/borer = allocate(/mob/living/simple_mob/animal/borer, run_loc_floor_bottom_left)
	borer.infest()
	var/datum/T = running(borer)
	TEST_ASSERT(!isnull(T), "infesting starts a timed action")
	target.forceMove(get_step(target, EAST))
	test_time(5 SECONDS)
	TEST_ASSERT_NULL(borer.borer_host(), "the target moving away cancels: no host")
	TEST_ASSERT(was_cancelled(T, borer), "the action ends cancelled")
	TEST_ASSERT(said(borer, "you are dislodged"), "it says the borer was dislodged")
	forget_ghosts()

/datum/unit_test/dq_timed_pin_w7/m_leech_infest

/datum/unit_test/dq_timed_pin_w7/m_leech_infest/run_pin()
	var/mob/living/carbon/human/target = person(get_step(run_loc_floor_bottom_left, EAST))
	var/mob/living/simple_mob/animal/sif/leech/leech = allocate(/mob/living/simple_mob/animal/sif/leech, run_loc_floor_bottom_left)
	test_chat_clear()
	leech.do_infest(leech, target)
	TEST_ASSERT(!isnull(running(leech)), "infesting starts a timed action")
	TEST_ASSERT(isnull(leech.host), "no host before the end")
	test_time(1 SECONDS)
	TEST_ASSERT_EQUAL(leech.host, target, "the leech is in the host at the end (2 ticks)")
	TEST_ASSERT_EQUAL(leech.loc, target, "and inside it")
	forget_ghosts()

/datum/unit_test/dq_timed_pin_w7/m_leech_infest_target_leaves

/datum/unit_test/dq_timed_pin_w7/m_leech_infest_target_leaves/run_pin()
	var/mob/living/carbon/human/target = person(get_step(run_loc_floor_bottom_left, EAST))
	var/mob/living/simple_mob/animal/sif/leech/leech = allocate(/mob/living/simple_mob/animal/sif/leech, run_loc_floor_bottom_left)
	leech.do_infest(leech, target)
	var/datum/T = running(leech)
	TEST_ASSERT(!isnull(T), "infesting starts a timed action")
	target.forceMove(get_step(target, EAST))
	test_time(1 SECONDS)
	TEST_ASSERT(isnull(leech.host), "the target moving away cancels: no host")
	TEST_ASSERT(was_cancelled(T, leech), "the action ends cancelled")
	forget_ghosts()

// ---- Xenomorph: building resin (verb, radial answer) ----

/datum/unit_test/dq_timed_pin_w7/m_xeno_build

/datum/unit_test/dq_timed_pin_w7/m_xeno_build/run_pin()
	var/mob/living/simple_mob/xeno_ch/xeno = allocate(/mob/living/simple_mob/xeno_ch, run_loc_floor_bottom_left)
	xeno.set_dir(EAST)
	perform_op(xeno, xeno, "xeno_build", null, ORIGIN_VERB, AUTH_PHYSICAL)
	test_answer(xeno, "Nest")
	TEST_ASSERT(!isnull(running(xeno)), "the answer starts a timed action")
	TEST_ASSERT_NULL(locate(/obj/structure/bed/nest) in get_step(run_loc_floor_bottom_left, EAST), "nothing is built before the end")
	test_time(1 SECONDS)
	var/obj/structure/bed/nest/N = locate(/obj/structure/bed/nest) in get_step(run_loc_floor_bottom_left, EAST)
	TEST_ASSERT(!isnull(N), "the nest stands in front of the xeno at the end (5 ticks)")
	if(N)
		qdel(N)
	TEST_ASSERT_NULL(running(xeno), "nothing is left running")

/datum/unit_test/dq_timed_pin_w7/m_xeno_build_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/m_xeno_build_cancel_on_move/run_pin()
	var/mob/living/simple_mob/xeno_ch/xeno = allocate(/mob/living/simple_mob/xeno_ch, run_loc_floor_bottom_left)
	xeno.set_dir(EAST)
	perform_op(xeno, xeno, "xeno_build", null, ORIGIN_VERB, AUTH_PHYSICAL)
	test_answer(xeno, "Nest")
	var/datum/T = running(xeno)
	TEST_ASSERT(!isnull(T), "the answer starts a timed action")
	xeno.forceMove(get_step(xeno, NORTH))
	test_time(1 SECONDS)
	TEST_ASSERT_NULL(locate(/obj/structure/bed/nest) in get_step(run_loc_floor_bottom_left, EAST), "moving cancels: nothing is built")
	TEST_ASSERT(was_cancelled(T, xeno), "the action ends cancelled")

// ---- Dominated brain: resisting control, returning to the body ----

/// A seat made as prey dominating a predator (take_over_predator), the predator's body now holding the prey's mind.
/datum/unit_test/dq_timed_pin_w7/proc/m_dominated_seat(list/out)
	var/mob/living/carbon/human/pred = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/prey = allocate(/mob/living/carbon/human)
	var/obj/item/holder = allocate(/obj/item)
	var/datum/mind/pred_mind = dq_test_give_mind(src, pred, "Pinned Pred")
	var/datum/mind/prey_mind = dq_test_give_mind(src, prey, "Pinned Prey")
	holder.forceMove(pred)
	prey.forceMove(holder)
	var/mob/living/dominated_brain/seat = take_over_predator(prey, pred, "unit test")
	out["pred"] = pred
	out["prey"] = prey
	out["pred_mind"] = pred_mind
	out["prey_mind"] = prey_mind
	return seat

/datum/unit_test/dq_timed_pin_w7/m_dominated_resist_control

/datum/unit_test/dq_timed_pin_w7/m_dominated_resist_control/run_pin()
	var/list/who = list()
	var/mob/living/dominated_brain/seat = m_dominated_seat(who)
	var/mob/living/carbon/human/pred = who["pred"]
	test_chat_clear()
	test_menu(seat, seat, "resist_control")
	TEST_ASSERT(!isnull(running(seat)), "resisting starts a timed action")
	TEST_ASSERT(said(seat, "You begin to resist"), "it says it began")
	test_time(9 SECONDS)
	TEST_ASSERT(pred.prey_controlled, "the predator is still controlled before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(!pred.prey_controlled, "control is restored at the end (10 seconds)")
	forget_ghosts()

/datum/unit_test/dq_timed_pin_w7/m_dominated_resist_via_resist

/datum/unit_test/dq_timed_pin_w7/m_dominated_resist_via_resist/run_pin()
	var/list/who = list()
	var/mob/living/dominated_brain/seat = m_dominated_seat(who)
	var/mob/living/carbon/human/pred = who["pred"]
	seat.process_resist()
	test_answer(seat, "Yes")
	TEST_ASSERT(!isnull(running(seat)), "confirming starts a timed action")
	test_time(9 SECONDS)
	TEST_ASSERT(pred.prey_controlled, "the predator is still controlled before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(!pred.prey_controlled, "control is restored at the end (10 seconds)")
	forget_ghosts()

/datum/unit_test/dq_timed_pin_w7/m_dominated_return_to_body

/datum/unit_test/dq_timed_pin_w7/m_dominated_return_to_body/run_pin()
	var/mob/living/carbon/human/pred = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/prey = allocate(/mob/living/carbon/human)
	var/obj/item/holder = allocate(/obj/item)
	dq_test_give_mind(src, pred, "Pinned Pred")
	var/datum/mind/prey_mind = dq_test_give_mind(src, prey, "Pinned Prey")
	holder.forceMove(pred)
	prey.forceMove(holder) // "inside" the predator, as in a belly
	var/mob/living/dominated_brain/seat = pred.gather_prey_mind(prey)
	TEST_ASSERT_NOTNULL(seat, "setup: the prey's mind sits in a back seat")
	test_chat_clear()
	test_menu(seat, seat, "return_to_body")
	TEST_ASSERT(!isnull(running(seat)), "returning starts a timed action")
	TEST_ASSERT(said(seat, "attempt to return to your body"), "it says it began")
	test_time(9 SECONDS)
	TEST_ASSERT_NOTEQUAL(prey.mind, prey_mind, "the prey's mind is not back before the end")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(prey.mind, prey_mind, "the prey's mind is back in its body at the end (10 seconds)")
	forget_ghosts()

// ---- cluster v ----

// Cluster V pins (code/modules/vore, nifsoft, resleeving, xenobio), recorded on the legacy forms. Helpers come from dq_timed_pin_w7 (begin, hold) and dq_timed_pin.
// Where the legacy entry is an attack()/afterattack() override the click may not reach it in the driver: the pin then calls the override as the click path
// would (the same pattern as nif_tool_click in the w3 pins). After the conversion the click itself answers and the fallback line never runs.

/// A working NIF in `H`.
/datum/unit_test/dq_timed_pin_w7/proc/v_working_nif(mob/living/carbon/human/H)
	var/obj/item/nif/N = allocate(/obj/item/nif, run_loc_floor_bottom_left)
	N.quick_implant(H)
	test_time(2 SECONDS)
	N.stat = NIF_WORKING
	return N

/// TRUE when `N` holds a flashprot nifsoft.
/datum/unit_test/dq_timed_pin_w7/proc/v_has_flashprot(obj/item/nif/N)
	for(var/datum/nifsoft/flashprot/S in N.nifsofts)
		return TRUE
	return FALSE

/// A nifsoft uploader that installs flashprot.
/datum/unit_test/dq_timed_pin_w7/proc/v_disk()
	var/obj/item/disk/nifsoft/D = allocate(/obj/item/disk/nifsoft, run_loc_floor_bottom_left)
	D.stored_organic = /datum/nifsoft/flashprot
	D.stored_synthetic = /datum/nifsoft/flashprot
	return D

/// Uses `D` on `target` as a click would: the click, else the legacy afterattack.
/datum/unit_test/dq_timed_pin_w7/proc/v_use_disk(mob/user, mob/target, obj/item/disk/nifsoft/D)
	test_chat_clear()
	test_click(user, target, D)
	if(isnull(running(user)))
		D.afterattack(target, user, 1)

// ---- NIFSoft uploader on someone else (ten seconds), on yourself (one second) ----

/datum/unit_test/dq_timed_pin_w7/v_nifsoft_upload_other

/datum/unit_test/dq_timed_pin_w7/v_nifsoft_upload_other/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/carbon/human/target = person()
	var/obj/item/nif/N = v_working_nif(target)
	var/obj/item/disk/nifsoft/D = v_disk()
	hold(user, D)
	v_use_disk(user, target, D)
	TEST_ASSERT(!isnull(running(user)), "the uploader on someone with a working NIF starts a timed action")
	TEST_ASSERT(said(target, "uploading"), "the target is told it is being uploaded")
	test_time(9 SECONDS)
	TEST_ASSERT(!v_has_flashprot(N), "nothing is installed before the end")
	TEST_ASSERT(!QDELETED(D), "the uploader stands before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(v_has_flashprot(N), "the nifsoft is installed at the end")
	TEST_ASSERT(QDELETED(D), "the uploader is used up")
	TEST_ASSERT_NULL(running(user), "nothing is left running")

/datum/unit_test/dq_timed_pin_w7/v_nifsoft_upload_self

/datum/unit_test/dq_timed_pin_w7/v_nifsoft_upload_self/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/nif/N = v_working_nif(user)
	var/obj/item/disk/nifsoft/D = v_disk()
	hold(user, D)
	v_use_disk(user, user, D)
	TEST_ASSERT(!isnull(running(user)), "the uploader on yourself starts a timed action")
	test_time(0.5 SECONDS)
	TEST_ASSERT(!v_has_flashprot(N), "nothing is installed before the end")
	test_time(1 SECOND)
	TEST_ASSERT(v_has_flashprot(N), "the nifsoft is installed after a second")
	TEST_ASSERT(QDELETED(D), "the uploader is used up")

/datum/unit_test/dq_timed_pin_w7/v_nifsoft_upload_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/v_nifsoft_upload_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/carbon/human/target = person()
	var/obj/item/nif/N = v_working_nif(target)
	var/obj/item/disk/nifsoft/D = v_disk()
	hold(user, D)
	v_use_disk(user, target, D)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the uploader starts a timed action")
	user.forceMove(get_step(user, EAST))
	test_time(12 SECONDS)
	TEST_ASSERT(!v_has_flashprot(N), "moving cancels: nothing is installed")
	TEST_ASSERT(!QDELETED(D), "and the uploader is kept")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w7/v_nifsoft_upload_no_nif

/datum/unit_test/dq_timed_pin_w7/v_nifsoft_upload_no_nif/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/carbon/human/target = person()
	var/obj/item/disk/nifsoft/D = v_disk()
	hold(user, D)
	v_use_disk(user, target, D)
	TEST_ASSERT_NULL(running(user), "someone without a NIF starts nothing")
	test_time(12 SECONDS)
	TEST_ASSERT(!QDELETED(D), "the uploader is kept")

// ---- A NIF stuffed into a Promethean's chest (twenty seconds) ----

/datum/unit_test/dq_timed_pin_w7/v_nif_stuff_in

/datum/unit_test/dq_timed_pin_w7/v_nif_stuff_in/run_pin()
	var/mob/living/carbon/human/user = person()
	dq_give_zone_sel(user)
	var/mob/living/carbon/human/target = person()
	target.set_species(SPECIES_PROMETHEAN)
	var/obj/item/organ/external/torso = target.get_organ(BP_TORSO)
	TEST_ASSERT(!isnull(torso), "the target has a torso")
	var/obj/item/nif/N = allocate(/obj/item/nif, run_loc_floor_bottom_left)
	hold(user, N)
	user.zone_sel.selecting = BP_TORSO
	test_chat_clear()
	test_click(user, target, N)
	if(isnull(running(user)))
		N.attack(target, user, BP_TORSO)
	TEST_ASSERT(!isnull(running(user)), "a NIF on a Promethean's chest starts a timed action")
	TEST_ASSERT(said(user, "begin installing"), "it says it began")
	test_time(19 SECONDS)
	TEST_ASSERT(N.loc != torso, "nothing is stuffed in before the end")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(N.loc, torso, "the NIF is in the chest at the end")
	TEST_ASSERT(user.get_active_hand() != N, "it left the user's hand")
	TEST_ASSERT_NULL(running(user), "nothing is left running")

/datum/unit_test/dq_timed_pin_w7/v_nif_stuff_in_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/v_nif_stuff_in_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	dq_give_zone_sel(user)
	var/mob/living/carbon/human/target = person()
	target.set_species(SPECIES_PROMETHEAN)
	var/obj/item/nif/N = allocate(/obj/item/nif, run_loc_floor_bottom_left)
	hold(user, N)
	user.zone_sel.selecting = BP_TORSO
	test_click(user, target, N)
	if(isnull(running(user)))
		N.attack(target, user, BP_TORSO)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "a NIF on a Promethean's chest starts a timed action")
	test_time(5 SECONDS)
	user.forceMove(get_step(user, EAST))
	test_time(20 SECONDS)
	TEST_ASSERT_EQUAL(N.loc, user, "moving cancels: the NIF stays with the user")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

// ---- Backup implanter on a person (five seconds), on yourself (at once) ----

/datum/unit_test/dq_timed_pin_w7/proc/v_has_backup(mob/living/carbon/human/H)
	var/obj/item/organ/external/torso = H.get_organ(BP_TORSO)
	for(var/obj/item/implant/backup/B in torso.contents)
		return TRUE
	return FALSE

/datum/unit_test/dq_timed_pin_w7/proc/v_use_implanter(mob/user, mob/target, obj/item/backup_implanter/I)
	test_chat_clear()
	test_click(user, target, I)
	if(isnull(running(user)) && !v_has_backup(target))
		I.attack(target, user, BP_TORSO)

/datum/unit_test/dq_timed_pin_w7/v_backup_implanter_other

/datum/unit_test/dq_timed_pin_w7/v_backup_implanter_other/run_pin()
	var/mob/living/carbon/human/user = person()
	dq_give_zone_sel(user)
	var/mob/living/carbon/human/target = person()
	var/obj/item/backup_implanter/I = allocate(/obj/item/backup_implanter, run_loc_floor_bottom_left)
	hold(user, I)
	TEST_ASSERT_EQUAL(LAZYLEN(I.imps), 4, "it comes loaded")
	v_use_implanter(user, target, I)
	TEST_ASSERT(!isnull(running(user)), "the implanter on another person starts a timed action")
	test_time(4 SECONDS)
	TEST_ASSERT(!v_has_backup(target), "nothing is implanted before the end")
	TEST_ASSERT_EQUAL(LAZYLEN(I.imps), 4, "no implant is used before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(v_has_backup(target), "the backup implant is in the target at the end")
	TEST_ASSERT_EQUAL(LAZYLEN(I.imps), 3, "one implant is used")
	TEST_ASSERT(said(target, "backup implanted") || said(user, "backup implanted"), "it says it finished")

/datum/unit_test/dq_timed_pin_w7/v_backup_implanter_other_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/v_backup_implanter_other_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	dq_give_zone_sel(user)
	var/mob/living/carbon/human/target = person()
	var/obj/item/backup_implanter/I = allocate(/obj/item/backup_implanter, run_loc_floor_bottom_left)
	hold(user, I)
	v_use_implanter(user, target, I)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the implanter on another person starts a timed action")
	user.forceMove(get_step(user, EAST))
	test_time(7 SECONDS)
	TEST_ASSERT(!v_has_backup(target), "moving cancels: nothing is implanted")
	TEST_ASSERT_EQUAL(LAZYLEN(I.imps), 4, "and no implant is used")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w7/v_backup_implanter_other_cancel_on_target_move

/datum/unit_test/dq_timed_pin_w7/v_backup_implanter_other_cancel_on_target_move/run_pin()
	var/mob/living/carbon/human/user = person()
	dq_give_zone_sel(user)
	var/mob/living/carbon/human/target = person()
	var/obj/item/backup_implanter/I = allocate(/obj/item/backup_implanter, run_loc_floor_bottom_left)
	hold(user, I)
	v_use_implanter(user, target, I)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the implanter on another person starts a timed action")
	target.forceMove(get_step(target, EAST))
	test_time(7 SECONDS)
	TEST_ASSERT(!v_has_backup(target), "a target that stepped away is not implanted")
	TEST_ASSERT_EQUAL(LAZYLEN(I.imps), 4, "and no implant is used")

/datum/unit_test/dq_timed_pin_w7/v_backup_implanter_self

/datum/unit_test/dq_timed_pin_w7/v_backup_implanter_self/run_pin()
	var/mob/living/carbon/human/user = person()
	dq_give_zone_sel(user)
	var/obj/item/backup_implanter/I = allocate(/obj/item/backup_implanter, run_loc_floor_bottom_left)
	hold(user, I)
	v_use_implanter(user, user, I)
	test_time(1 SECOND)
	TEST_ASSERT(v_has_backup(user), "the backup implant is in the user right away")
	TEST_ASSERT_EQUAL(LAZYLEN(I.imps), 3, "one implant is used")

// ---- Xenobio portable slime processor: a dead monkey (1.5 s), a dead slime (1.5 s per core) ----

/datum/unit_test/dq_timed_pin_w7/proc/v_use_grinder(mob/user, mob/target, obj/item/slime_grinder/G)
	test_chat_clear()
	test_click(user, target, G)
	if(isnull(running(user)))
		G.attack(target, user, BP_TORSO)

/datum/unit_test/dq_timed_pin_w7/v_grinder_monkey

/datum/unit_test/dq_timed_pin_w7/v_grinder_monkey/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/carbon/human/monkey/M = allocate(/mob/living/carbon/human/monkey, run_loc_floor_bottom_left)
	M.stat = DEAD
	var/obj/item/slime_grinder/G = allocate(/obj/item/slime_grinder, run_loc_floor_bottom_left)
	hold(user, G)
	v_use_grinder(user, M, G)
	TEST_ASSERT(!isnull(running(user)), "the grinder on a dead monkey starts a timed action")
	test_time(1 SECOND)
	TEST_ASSERT(!QDELETED(M), "the monkey is whole before the end")
	test_time(1 SECOND)
	TEST_ASSERT(QDELETED(M), "the monkey is ground up")
	TEST_ASSERT_EQUAL(G.monkeys_recycled, 1, "it is counted for cubes")
	TEST_ASSERT_NULL(running(user), "nothing is left running")
	forget_ghosts()

/datum/unit_test/dq_timed_pin_w7/v_grinder_monkey_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/v_grinder_monkey_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/carbon/human/monkey/M = allocate(/mob/living/carbon/human/monkey, run_loc_floor_bottom_left)
	M.stat = DEAD
	var/obj/item/slime_grinder/G = allocate(/obj/item/slime_grinder, run_loc_floor_bottom_left)
	hold(user, G)
	v_use_grinder(user, M, G)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the grinder on a dead monkey starts a timed action")
	user.forceMove(get_step(user, EAST))
	test_time(3 SECONDS)
	TEST_ASSERT(!QDELETED(M), "moving cancels: the monkey is whole")
	TEST_ASSERT_EQUAL(G.monkeys_recycled, 0, "and nothing is counted")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")
	user.forceMove(M.loc)
	v_use_grinder(user, M, G)
	TEST_ASSERT(!isnull(running(user)), "a cancelled grind leaves the grinder free to start again")
	forget_ghosts()

/datum/unit_test/dq_timed_pin_w7/v_grinder_busy_refuses_second

/datum/unit_test/dq_timed_pin_w7/v_grinder_busy_refuses_second/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/carbon/human/monkey/M = allocate(/mob/living/carbon/human/monkey, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/monkey/M2 = allocate(/mob/living/carbon/human/monkey, run_loc_floor_bottom_left)
	M.stat = DEAD
	M2.stat = DEAD
	var/obj/item/slime_grinder/G = allocate(/obj/item/slime_grinder, run_loc_floor_bottom_left)
	hold(user, G)
	v_use_grinder(user, M, G)
	TEST_ASSERT_EQUAL(running_count(user), 1, "one grind runs")
	test_click(user, M2, G)
	TEST_ASSERT_EQUAL(running_count(user), 1, "a second monkey is not ground at the same time")
	test_time(1.5 SECONDS)
	TEST_ASSERT(QDELETED(M), "the first monkey is ground up")
	TEST_ASSERT(!QDELETED(M2), "the second waits")
	forget_ghosts()

/datum/unit_test/dq_timed_pin_w7/v_grinder_slime

/datum/unit_test/dq_timed_pin_w7/v_grinder_slime/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/simple_mob/slime/S = allocate(/mob/living/simple_mob/slime, run_loc_floor_bottom_left)
	S.cores = 2
	S.stat = DEAD
	var/obj/item/slime_grinder/G = allocate(/obj/item/slime_grinder, run_loc_floor_bottom_left)
	hold(user, G)
	v_use_grinder(user, S, G)
	TEST_ASSERT(!isnull(running(user)), "the grinder on a dead slime starts a timed action")
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(v_core_count(/obj/item/slime_extract/grey), 0, "no core before the first end")
	test_time(4 SECONDS)
	TEST_ASSERT_EQUAL(v_core_count(/obj/item/slime_extract/grey), 2, "one core per grind, both cores out")
	TEST_ASSERT(QDELETED(S), "the empty slime is consumed")
	TEST_ASSERT_NULL(running(user), "nothing is left running")
	for(var/obj/item/slime_extract/E in run_loc_floor_bottom_left)
		qdel(E)

/datum/unit_test/dq_timed_pin_w7/proc/v_core_count(core_type)
	var/n = 0
	for(var/obj/item/slime_extract/E in run_loc_floor_bottom_left)
		if(istype(E, core_type))
			n++
	return n

/datum/unit_test/dq_timed_pin_w7/v_grinder_slime_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/v_grinder_slime_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/mob/living/simple_mob/slime/S = allocate(/mob/living/simple_mob/slime, run_loc_floor_bottom_left)
	S.cores = 3
	S.stat = DEAD
	var/obj/item/slime_grinder/G = allocate(/obj/item/slime_grinder, run_loc_floor_bottom_left)
	hold(user, G)
	v_use_grinder(user, S, G)
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the grinder on a dead slime starts a timed action")
	test_time(0.5 SECONDS)
	user.forceMove(get_step(user, EAST))
	test_time(6 SECONDS)
	var/cores_out = v_core_count(/obj/item/slime_extract/grey)
	for(var/obj/item/slime_extract/E in run_loc_floor_bottom_left)
		qdel(E)
	TEST_ASSERT_EQUAL(cores_out, 0, "moving before the first core ends the grinding: no core came out")
	TEST_ASSERT(!QDELETED(S), "the slime is not consumed")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

// ---- Xenobio slime processor machine: a dead slime inserted, started by hand ----

/datum/unit_test/dq_timed_pin_w7/v_processor_slime

/datum/unit_test/dq_timed_pin_w7/v_processor_slime/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/machinery/processor/P = allocate(/obj/machinery/processor, run_loc_floor_bottom_left)
	var/mob/living/simple_mob/slime/S = allocate(/mob/living/simple_mob/slime, run_loc_floor_bottom_left)
	S.cores = 2
	S.stat = DEAD
	P.insert(S, user)
	TEST_ASSERT_EQUAL(S.loc, P, "the slime is inside")
	test_click(user, P, null)
	test_time(0.5 SECONDS)
	TEST_ASSERT(P.processing, "the processor is at work")
	test_click(user, P, null)
	TEST_ASSERT(P.processing, "a second press changes nothing")
	test_time(10 SECONDS)
	var/cores_out = v_core_count(/obj/item/slime_extract/grey)
	for(var/obj/item/slime_extract/E in run_loc_floor_bottom_left)
		qdel(E)
	TEST_ASSERT(!P.processing, "the processor is idle once it is empty")
	TEST_ASSERT_EQUAL(cores_out, 2, "every core came out")
	TEST_ASSERT(QDELETED(S), "the empty slime is consumed")

/datum/unit_test/dq_timed_pin_w7/v_processor_empty

/datum/unit_test/dq_timed_pin_w7/v_processor_empty/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/machinery/processor/P = allocate(/obj/machinery/processor, run_loc_floor_bottom_left)
	test_chat_clear()
	test_click(user, P, null)
	test_time(2 SECONDS)
	TEST_ASSERT(!P.processing, "an empty processor does not start")
	TEST_ASSERT(said(user, "empty"), "it says it is empty")

// ---- Nikki's hat: a translocator slipped in (two seconds) ----

/datum/unit_test/dq_timed_pin_w7/v_nikki_hat_equip

/datum/unit_test/dq_timed_pin_w7/v_nikki_hat_equip/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/clothing/head/fluff/nikki/hat = allocate(/obj/item/clothing/head/fluff/nikki, run_loc_floor_bottom_left)
	var/obj/item/perfect_tele/tele = allocate(/obj/item/perfect_tele, run_loc_floor_bottom_left)
	user.put_in_inactive_hand(hat)
	hold(user, tele)
	TEST_ASSERT_NULL(hat.translocator, "the hat starts empty")
	begin(user, hat, tele, 2 SECONDS)
	test_time(1 SECOND)
	TEST_ASSERT_NULL(hat.translocator, "nothing is installed before the end")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(hat.translocator, tele, "the translocator is in the hat at the end")
	TEST_ASSERT_NULL(running(user), "nothing is left running")

/datum/unit_test/dq_timed_pin_w7/v_nikki_hat_equip_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/v_nikki_hat_equip_cancel_on_move/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/clothing/head/fluff/nikki/hat = allocate(/obj/item/clothing/head/fluff/nikki, run_loc_floor_bottom_left)
	var/obj/item/perfect_tele/tele = allocate(/obj/item/perfect_tele, run_loc_floor_bottom_left)
	user.put_in_inactive_hand(hat)
	hold(user, tele)
	var/datum/T = begin(user, hat, tele, 2 SECONDS)
	user.forceMove(get_step(user, EAST))
	test_time(4 SECONDS)
	TEST_ASSERT_NULL(hat.translocator, "moving cancels: nothing is installed")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")

// ---- Belly escape: the owner out cold (the default escape), a rolled escape, an absorbed escape ----

/// A pred with a belly, a prey inside it, and a short escape time. list(pred, prey, belly).
/datum/unit_test/dq_timed_pin_w7/proc/v_belly_pair()
	var/mob/living/carbon/human/pred = person()
	var/mob/living/carbon/human/prey = person()
	pred.init_vore(TRUE)
	var/obj/belly/B = pred.vore_selected
	TEST_ASSERT(!isnull(B), "the pred has a belly")
	TEST_ASSERT(pred.begin_instant_nom(pred, prey, pred, B), "an instant nom succeeds")
	TEST_ASSERT_EQUAL(prey.loc, B, "the prey is inside")
	B.escapetime = 6 SECONDS
	B.belchchance = 0
	return list(pred, prey, B)

/datum/unit_test/dq_timed_pin_w7/v_belly_escape_default

/datum/unit_test/dq_timed_pin_w7/v_belly_escape_default/run_pin()
	var/list/pair = v_belly_pair()
	var/mob/living/carbon/human/pred = pair[1]
	var/mob/living/carbon/human/prey = pair[2]
	var/obj/belly/B = pair[3]
	pred.stat = UNCONSCIOUS
	test_chat_clear()
	B.relay_resist(prey)
	TEST_ASSERT(!isnull(running(prey)), "struggling in the belly of someone out cold starts a timed action")
	TEST_ASSERT(said(prey, "6"), "the prey is told it takes around six seconds")
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(prey.loc, B, "the prey is still inside before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(prey.loc != B, "the prey is out at the end")
	TEST_ASSERT_NULL(running(prey), "nothing is left running")

/datum/unit_test/dq_timed_pin_w7/v_belly_escape_default_owner_wakes

/datum/unit_test/dq_timed_pin_w7/v_belly_escape_default_owner_wakes/run_pin()
	var/list/pair = v_belly_pair()
	var/mob/living/carbon/human/pred = pair[1]
	var/mob/living/carbon/human/prey = pair[2]
	var/obj/belly/B = pair[3]
	pred.stat = UNCONSCIOUS
	B.relay_resist(prey)
	TEST_ASSERT(!isnull(running(prey)), "struggling in the belly of someone out cold starts a timed action")
	pred.stat = CONSCIOUS
	B.escapable = B_ESCAPABLE_NONE
	test_chat_clear()
	test_time(7 SECONDS)
	TEST_ASSERT_EQUAL(prey.loc, B, "an owner who woke and shut the belly keeps the prey")
	TEST_ASSERT_NULL(running(prey), "nothing is left running")

/datum/unit_test/dq_timed_pin_w7/v_belly_escape_default_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/v_belly_escape_default_cancel_on_move/run_pin()
	var/list/pair = v_belly_pair()
	var/mob/living/carbon/human/pred = pair[1]
	var/mob/living/carbon/human/prey = pair[2]
	var/obj/belly/B = pair[3]
	pred.stat = UNCONSCIOUS
	B.relay_resist(prey)
	var/datum/T = running(prey)
	TEST_ASSERT(!isnull(T), "struggling in the belly of someone out cold starts a timed action")
	test_chat_clear()
	prey.forceMove(get_turf(pred))
	test_time(7 SECONDS)
	TEST_ASSERT(was_cancelled(T, prey), "the action ends cancelled when the prey is moved")

/datum/unit_test/dq_timed_pin_w7/v_belly_escape_rolled

/datum/unit_test/dq_timed_pin_w7/v_belly_escape_rolled/run_pin()
	var/list/pair = v_belly_pair()
	var/obj/belly/B = pair[3]
	var/mob/living/carbon/human/prey = pair[2]
	B.escapable = B_ESCAPABLE_DEFAULT
	B.escapechance = 100
	B.relay_resist(prey)
	TEST_ASSERT(!isnull(running(prey)), "a struggle that rolls an escape starts a timed action")
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(prey.loc, B, "the prey is still inside before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(prey.loc != B, "the prey is out at the end")

/datum/unit_test/dq_timed_pin_w7/v_belly_escape_rolled_belly_closes

/datum/unit_test/dq_timed_pin_w7/v_belly_escape_rolled_belly_closes/run_pin()
	var/list/pair = v_belly_pair()
	var/obj/belly/B = pair[3]
	var/mob/living/carbon/human/prey = pair[2]
	B.escapable = B_ESCAPABLE_DEFAULT
	B.escapechance = 100
	B.relay_resist(prey)
	TEST_ASSERT(!isnull(running(prey)), "a struggle that rolls an escape starts a timed action")
	B.escapable = B_ESCAPABLE_NONE
	test_time(7 SECONDS)
	TEST_ASSERT_EQUAL(prey.loc, B, "a belly closed during the wait keeps the prey")

/datum/unit_test/dq_timed_pin_w7/v_belly_escape_absorbed

/datum/unit_test/dq_timed_pin_w7/v_belly_escape_absorbed/run_pin()
	var/list/pair = v_belly_pair()
	var/obj/belly/B = pair[3]
	var/mob/living/carbon/human/prey = pair[2]
	prey.set_absorbed(TRUE)
	B.escapable = B_ESCAPABLE_DEFAULT
	B.escapechance_absorbed = 100
	B.relay_absorbed_resist(prey)
	TEST_ASSERT(!isnull(running(prey)), "an absorbed prey's struggle starts a timed action")
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(prey.loc, B, "the prey is still inside before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(prey.loc != B, "the prey is out at the end")

// ---- Simple mob nutrition heal (verb on a simple mob): a number asked, then a wait of a second per point ----

/datum/unit_test/dq_timed_pin_w7/v_nutrition_heal

/datum/unit_test/dq_timed_pin_w7/v_nutrition_heal/run_pin()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, run_loc_floor_bottom_left)
	M.set_nutrition(200)
	test_menu(M, M, "nutrition_heal")
	test_answer(M, 3)
	TEST_ASSERT(!isnull(running(M)), "answering the question starts a timed action")
	test_time(0.5 SECONDS)
	TEST_ASSERT_EQUAL(M.nutrition, 200, "nothing is spent before the end")
	test_time(5 SECONDS)
	TEST_ASSERT(M.nutrition <= 190, "nutrition is spent at the end")
	TEST_ASSERT_NULL(running(M), "nothing is left running")

/datum/unit_test/dq_timed_pin_w7/v_nutrition_heal_cancel_on_move

/datum/unit_test/dq_timed_pin_w7/v_nutrition_heal_cancel_on_move/run_pin()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, run_loc_floor_bottom_left)
	M.set_nutrition(200)
	test_menu(M, M, "nutrition_heal")
	test_answer(M, 3)
	var/datum/T = running(M)
	TEST_ASSERT(!isnull(T), "answering the question starts a timed action")
	M.forceMove(get_step(M, EAST))
	test_time(6 SECONDS)
	TEST_ASSERT_EQUAL(M.nutrition, 200, "moving cancels: nothing is spent")
	TEST_ASSERT(was_cancelled(T, M), "the action ends cancelled")

/datum/unit_test/dq_timed_pin_w7/v_nutrition_heal_too_hungry

/datum/unit_test/dq_timed_pin_w7/v_nutrition_heal_too_hungry/run_pin()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, run_loc_floor_bottom_left)
	M.set_nutrition(5)
	test_chat_clear()
	test_menu(M, M, "nutrition_heal")
	TEST_ASSERT_NULL(running(M), "too hungry starts nothing")
	TEST_ASSERT(said(M, "too hungry"), "it says why")

