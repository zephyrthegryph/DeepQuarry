// The simple_mob abilities that used to be verbs are menu ops now. Each op carries its old verb's guard as a requirement (a refusal is a
// requirement, not a message-and-return in the handler), so these tests check the effect of a committed op and the refusal reason of a blocked one.

/// Runs the menu op `key` for `actor` on itself, the way the context menu does.
/datum/unit_test/proc/dq_ability_menu_op(mob/actor, key)
	return perform_op(actor, actor, key, null, ORIGIN_MENU)

/// Berserk has no guard: the op commits and the mob is berserk afterwards.
/datum/unit_test/dq_ability_ops_berserk_applies_effect

/datum/unit_test/dq_ability_ops_berserk_applies_effect/Run()
	var/mob/living/simple_mob/animal/space/bear/B = allocate(/mob/living/simple_mob/animal/space/bear, test_floor())
	TEST_ASSERT(!B.has_body_effect(/datum/body_effect/berserk), "a fresh bear is not berserk")
	var/datum/op_result/R = dq_ability_menu_op(B, "berserk")
	TEST_ASSERT(test_op_committed(R), "the berserk op commits")
	TEST_ASSERT(B.has_body_effect(/datum/body_effect/berserk), "the berserk op applies the body effect")

/// A docile leech is too tired for every menu ability; a leech with no host cannot produce chemicals; an awake one can uninfest.
/datum/unit_test/dq_ability_ops_leech_guards

/datum/unit_test/dq_ability_ops_leech_guards/Run()
	var/mob/living/simple_mob/animal/sif/leech/L = allocate(/mob/living/simple_mob/animal/sif/leech, test_floor())
	L.set_docile(TRUE)
	for(var/key in list("infest_host", "uninfest", "inject_victim", "medicate_host", "feed_on_organ"))
		var/datum/op_result/tired = dq_ability_menu_op(L, key)
		TEST_ASSERT_EQUAL(tired?.outcome, ACT_REFUSED, "[key] is refused while docile")
	L.set_docile(FALSE)
	L.set_chemicals(100)
	var/datum/op_result/no_host = dq_ability_menu_op(L, "medicate_host")
	TEST_ASSERT_EQUAL(no_host?.outcome, ACT_REFUSED, "medicate_host is refused with no host")
	var/datum/op_result/awake = dq_ability_menu_op(L, "uninfest")
	TEST_ASSERT(test_op_committed(awake), "an awake leech's uninfest passes its requirement")

/// The kururak's flash is refused while its cooldown runs, and committing it starts the cooldown.
/datum/unit_test/dq_ability_ops_kururak_cooldown_refuses

/datum/unit_test/dq_ability_ops_kururak_cooldown_refuses/Run()
	var/mob/living/simple_mob/animal/sif/kururak/K = allocate(/mob/living/simple_mob/animal/sif/kururak, test_floor())
	var/datum/op_result/first = dq_ability_menu_op(K, "do_flash")
	TEST_ASSERT(test_op_committed(first), "the first flash commits")
	TEST_ASSERT(!COOLDOWN_FINISHED(K, flash_cooldown), "the flash started its cooldown")
	var/datum/op_result/second = dq_ability_menu_op(K, "do_flash")
	TEST_ASSERT_EQUAL(second?.outcome, ACT_REFUSED, "a second flash inside the cooldown is refused")

/// The demon's guards: no blood to crawl through, and blood cannot be made twice inside its cooldown.
/datum/unit_test/dq_ability_ops_demon_guards

/datum/unit_test/dq_ability_ops_demon_guards/Run()
	var/mob/living/simple_mob/vore/demon/D = allocate(/mob/living/simple_mob/vore/demon, test_floor())
	var/datum/op_result/crawl = dq_ability_menu_op(D, "blood_crawl")
	TEST_ASSERT_EQUAL(crawl?.outcome, ACT_REFUSED, "blood_crawl is refused with no blood underfoot")
	STAMP(D, blood_spawn, CLOCK_WORLD)
	var/datum/op_result/burst = dq_ability_menu_op(D, "blood_burst")
	TEST_ASSERT_EQUAL(burst?.outcome, ACT_REFUSED, "blood_burst is refused inside its cooldown")
	D.set_shifted_out(TRUE)
	var/datum/op_result/shifted = dq_ability_menu_op(D, "demonic_phase_shift")
	TEST_ASSERT_EQUAL(shifted?.outcome, ACT_REFUSED, "a shifted-out demon cannot phase-shift again")
