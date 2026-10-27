// Notices that had listeners and no publish site, wired back where the old event fired (atom_extinguish, atom_take_damage, click_alt,
// do_after_began / do_after_ended), and the listeners moved onto the notice that is published now (attack_self -> self_attacked,
// mob_apply_damage -> living_injured).

/// Records which notices it heard.
/datum/wired_notice_rec
	var/list/heard = list()

/datum/wired_notice_rec/proc/hear(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	heard += "[N.type]"

/// An experiment handler that records the configuration requests instead of opening the panel.
/datum/experiment_handler/wired_notice_rec
	var/configured = 0
	var/datum/last_source
	var/mob/last_user

/datum/experiment_handler/wired_notice_rec/configure_experiment(datum/source, mob/user)
	configured++
	last_source = source
	last_user = user

/// /atom/proc/extinguish() publishes atom_extinguish: a burning mob's fire_stacks status hears it on its owner and stops burning.
/datum/unit_test/dq_wired_notice_extinguish/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	H.adjust_fire_stacks(3)
	H.ignite_mob()
	var/datum/status_effect/fire_handler/fire_stacks/fire = H.has_status_effect(/datum/status_effect/fire_handler/fire_stacks)
	TEST_ASSERT(fire?.on_fire, "setup: the mob burns")
	H.extinguish()
	TEST_ASSERT(!fire.on_fire, "extinguish() reached the fire_stacks status through atom_extinguish")

/// take_damage() publishes atom_take_damage with the damage that landed (after armour); a blow that armour soaks away publishes nothing.
/datum/unit_test/dq_wired_notice_take_damage/Run()
	var/obj/item/clothing/suit/armor/vest/vest = allocate(/obj/item/clothing/suit/armor/vest)
	vest.set_armor(dq_armor(list(MELEE = 50)))
	var/datum/wired_notice_rec/rec = allocate(/datum/wired_notice_rec)
	TEST_ASSERT(observe(vest, /datum/notice/atom_take_damage, rec, then(PROC_REF(hear))), "observed")
	vest.take_damage(10, BRUTE, MELEE, FALSE)
	TEST_ASSERT_EQUAL(length(rec.heard), 1, "the landed blow published atom_take_damage once")
	vest.set_armor(dq_armor(list(MELEE = 100)))
	vest.take_damage(10, BRUTE, MELEE, FALSE)
	TEST_ASSERT_EQUAL(length(rec.heard), 1, "a fully soaked blow publishes nothing")

/// Using an item in hand reaches an experiment handler through self_attacked; alt-clicking reaches one through click_alt, which handles the click.
/datum/unit_test/dq_wired_notice_experiment_config/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/pen/held = allocate(/obj/item/pen, T)
	var/datum/experiment_handler/wired_notice_rec/self_handler = allocate(/datum/experiment_handler/wired_notice_rec, held, list(), list(), EXPERIMENT_CONFIG_ATTACKSELF, null, EXPERIMENT_CONFIG_NO_AUTOCONNECT)
	user.put_in_active_hand(held)
	held.attack_self(user)
	TEST_ASSERT_EQUAL(self_handler.configured, 1, "using the item in hand asked for the configuration panel")
	TEST_ASSERT_EQUAL(self_handler.last_source, held, "from the item")
	TEST_ASSERT_EQUAL(self_handler.last_user, user, "for the user")
	var/obj/item/pen/clicked = allocate(/obj/item/pen, T)
	var/datum/experiment_handler/wired_notice_rec/alt_handler = allocate(/datum/experiment_handler/wired_notice_rec, clicked, list(), list(), EXPERIMENT_CONFIG_ALTCLICK, null, EXPERIMENT_CONFIG_NO_AUTOCONNECT)
	TEST_ASSERT(user.base_click_alt(clicked), "a listened alt-click is handled")
	TEST_ASSERT_EQUAL(alt_handler.configured, 1, "alt-clicking asked for the configuration panel")
	TEST_ASSERT_EQUAL(alt_handler.last_source, clicked, "from the clicked item")
	TEST_ASSERT_EQUAL(alt_handler.last_user, user, "for the user")

/// A robot's cloak hears the injuries that land on it (living_injured): a hit of 5 or more counts against the cloak.
/datum/unit_test/dq_wired_notice_robot_cloak/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, run_loc_floor_bottom_left)
	R.apply_body_effect(/datum/body_effect/robot_cloak)
	var/datum/robot_cloak_state/state = R.body_effect_state(/datum/body_effect/robot_cloak)
	TEST_ASSERT_NOTNULL(state, "setup: the cloak is on")
	R.injure(INJURY_BLUNT, 20, BP_TORSO)
	TEST_ASSERT_EQUAL(state.times_hit, 1, "the landed injury counted against the cloak")

/// An actor's op that starts a timed wait publishes do_after_began on the actor, and do_after_ended when it ends.
/datum/unit_test/dq_timed_pin_w7/wired_notice_do_after

/datum/unit_test/dq_timed_pin_w7/wired_notice_do_after/run_pin()
	var/mob/living/carbon/human/user = person()
	dq_give_zone_sel(user)
	var/mob/living/carbon/human/victim = h_mortal()
	victim.adjust_fire_stacks(3)
	victim.ignite_mob()
	var/datum/wired_notice_rec/rec = allocate(/datum/wired_notice_rec)
	TEST_ASSERT(observe(user, /datum/notice/do_after_began, rec, then(TYPE_PROC_REF(/datum/wired_notice_rec, hear))), "observed began")
	TEST_ASSERT(observe(user, /datum/notice/do_after_ended, rec, then(TYPE_PROC_REF(/datum/wired_notice_rec, hear))), "observed ended")
	test_click(user, victim, null)
	h_started(user, 1.5 SECONDS)
	TEST_ASSERT_EQUAL(jointext(rec.heard, ","), "[/datum/notice/do_after_began]", "the timed action began")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(jointext(rec.heard, ","), "[/datum/notice/do_after_began],[/datum/notice/do_after_ended]", "and ended")
