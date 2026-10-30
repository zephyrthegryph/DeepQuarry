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

/// The demon's grab abilities are refused with nothing grabbed in the active hand.
/datum/unit_test/dq_ability_ops_demon_grab_requires_grab

/datum/unit_test/dq_ability_ops_demon_grab_requires_grab/Run()
	var/mob/living/simple_mob/vore/demon/D = allocate(/mob/living/simple_mob/vore/demon, test_floor())
	for(var/key in list("sizespell", "demon_bite"))
		var/datum/op_result/R = dq_ability_menu_op(D, key)
		TEST_ASSERT_EQUAL(R?.outcome, ACT_REFUSED, "[key] is refused when nothing is grabbed")

/// Only an ace kururak can rally a pack, and a shantak leader always can.
/datum/unit_test/dq_ability_ops_rally_pack_requirements

/datum/unit_test/dq_ability_ops_rally_pack_requirements/Run()
	var/mob/living/simple_mob/animal/sif/kururak/K = allocate(/mob/living/simple_mob/animal/sif/kururak, test_floor())
	var/datum/op_result/plain = dq_ability_menu_op(K, "rally_pack")
	TEST_ASSERT_EQUAL(plain?.outcome, ACT_REFUSED, "a kururak without the ace effect cannot rally")
	var/mob/living/simple_mob/animal/sif/shantak/leader/S = allocate(/mob/living/simple_mob/animal/sif/shantak/leader, test_floor())
	var/datum/op_result/led = dq_ability_menu_op(S, "rally_pack")
	TEST_ASSERT(test_op_committed(led), "a shantak leader's rally op commits")

/// A pAI can only fold out of its card, and only fold up when it is not in it: each op's old verb guard is its requirement.
/datum/unit_test/dq_ability_ops_pai_fold_requirements

/datum/unit_test/dq_ability_ops_pai_fold_requirements/Run()
	var/obj/item/paicard/card = allocate(/obj/item/paicard, test_floor())
	var/mob/living/silicon/pai/P = allocate(/mob/living/silicon/pai, card)
	var/datum/op_result/in_card_fold_up = dq_ability_menu_op(P, "fold_up")
	TEST_ASSERT_EQUAL(in_card_fold_up?.outcome, ACT_REFUSED, "a pAI in its card cannot fold up")
	P.forceMove(test_floor())
	var/datum/op_result/loose_fold_out = dq_ability_menu_op(P, "fold_out")
	TEST_ASSERT_EQUAL(loose_fold_out?.outcome, ACT_REFUSED, "a pAI outside its card cannot fold out")

/// A borer outside a host can only infest or knock out; every power that needs a host is refused with the host-less reason, and infest is
/// refused once it has one.
/datum/unit_test/dq_ability_ops_borer_requirements

/datum/unit_test/dq_ability_ops_borer_requirements/Run()
	var/mob/living/simple_mob/animal/borer/B = allocate(/mob/living/simple_mob/animal/borer, test_floor())
	for(var/key in list("bond_brain", "release_host", "secrete_chemicals"))
		var/datum/op_result/R = dq_ability_menu_op(B, key)
		TEST_ASSERT_EQUAL(R?.outcome, ACT_REFUSED, "[key] is refused with no host")
	var/datum/op_result/loose = dq_ability_menu_op(B, "infest_host")
	TEST_ASSERT(test_op_committed(loose), "a hostless borer may start to infest")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	TEST_ASSERT(B.take_host(H), "the borer takes a host")
	var/datum/op_result/hosted = dq_ability_menu_op(B, "infest_host")
	TEST_ASSERT_EQUAL(hosted?.outcome, ACT_REFUSED, "a borer that already has a host cannot infest")
	var/datum/op_result/knock = dq_ability_menu_op(B, "knockout_victim")
	TEST_ASSERT_EQUAL(knock?.outcome, ACT_REFUSED, "a borer inside a host cannot knock anyone out")
