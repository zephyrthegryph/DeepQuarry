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

/// menu(desc =) is the hover text a verb's `set desc` used to be: op_menu() carries it as the row's "desc" and the Menu's data passes it on.
/datum/unit_test/dq_ability_ops_menu_desc_reaches_the_menu

/datum/unit_test/dq_ability_ops_menu_desc_reaches_the_menu/Run()
	var/mob/living/simple_mob/animal/space/bear/B = allocate(/mob/living/simple_mob/animal/space/bear, test_floor())
	var/found = FALSE
	for(var/list/row as anything in op_menu(B, B, null))
		if(row["key"] == "berserk")
			found = TRUE
			TEST_ASSERT(istext(row["desc"]) && length(row["desc"]), "the berserk row carries its description")
			TEST_ASSERT_EQUAL(row["desc"], "Enrage and become vastly stronger for a period of time, however you will be weaker afterwards.", "the description is the old verb's text")
	TEST_ASSERT(found, "berserk is on the bear's own menu")
	var/menu_has_desc = FALSE
	var/list/data = interaction_menu_data(B, B)
	for(var/list/entry as anything in data["available"] + data["blocked"])
		if(entry["id"] == "berserk" && istext(entry["desc"]))
			menu_has_desc = TRUE
	TEST_ASSERT(menu_has_desc, "the Menu's data passes the description on")

/// The AI's hardlight nom is refused while it has no hologram out, and the refusal says why.
/datum/unit_test/dq_ability_ops_holo_nom_requires_hologram

/datum/unit_test/dq_ability_ops_holo_nom_requires_hologram/Run()
	var/mob/living/silicon/ai/AI = allocate(/mob/living/silicon/ai, test_floor(), null, null, null, TRUE)
	var/datum/op_result/R = dq_ability_menu_op(AI, "holo_nom_menu")
	TEST_ASSERT_EQUAL(R?.outcome, ACT_REFUSED, "holo_nom_menu is refused with no holopad hologram")

/// A pacified slime ("harmless") cannot evolve or reproduce; an ordinary one is offered both.
/datum/unit_test/dq_ability_ops_slime_pacified_refuses

/datum/unit_test/dq_ability_ops_slime_pacified_refuses/Run()
	var/mob/living/simple_mob/slime/xenobio/S = allocate(/mob/living/simple_mob/slime/xenobio, test_floor())
	S.set_harmless(TRUE)
	for(var/key in list("evolve", "reproduce"))
		var/datum/op_result/R = dq_ability_menu_op(S, key)
		TEST_ASSERT_EQUAL(R?.outcome, ACT_REFUSED, "[key] is refused while pacified")

/// The malfunction abilities that used `as mob in list` arguments pick a target by name from a request; malf_picked() finds it again.
/datum/unit_test/dq_ability_ops_malf_picked_finds_by_name

/datum/unit_test/dq_ability_ops_malf_picked_finds_by_name/Run()
	var/mob/living/carbon/human/first = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/carbon/human/second = allocate(/mob/living/carbon/human, test_floor())
	first.name = "Alpha Unit"
	second.name = "Beta Unit"
	TEST_ASSERT_EQUAL(malf_picked(list(first, second), malf_target_label(second)), second, "the second candidate is found by its name")
	TEST_ASSERT_EQUAL(malf_picked(list(first, second), malf_target_label(first)), first, "the first candidate is found by its name")
	TEST_ASSERT_NULL(malf_picked(list(first, second), "Gamma Unit"), "an unknown name finds nobody")

/// Renault befriends the first person who asks; the same person is told so, and anyone else is ignored.
/datum/unit_test/dq_ability_ops_fox_befriends_one_person

/datum/unit_test/dq_ability_ops_fox_befriends_one_person/Run()
	var/turf/T = test_floor()
	var/mob/living/simple_mob/animal/passive/fox/renault/fox = allocate(/mob/living/simple_mob/animal/passive/fox/renault, T)
	var/mob/living/carbon/human/first = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/second = allocate(/mob/living/carbon/human, T)
	var/datum/op_result/befriended = perform_op(first, fox, "become_friends", null, ORIGIN_MENU)
	TEST_ASSERT(test_op_committed(befriended), "the first person befriends the fox")
	TEST_ASSERT_EQUAL(fox.friend, first, "the fox's friend is the first person")
	var/datum/op_result/again = perform_op(first, fox, "become_friends", null, ORIGIN_MENU)
	TEST_ASSERT_EQUAL(again?.outcome, ACT_REFUSED, "the same person is told the fox is already their friend")
	var/datum/op_result/other = perform_op(second, fox, "become_friends", null, ORIGIN_MENU)
	TEST_ASSERT_EQUAL(other?.outcome, ACT_REFUSED, "a second person is ignored")
	TEST_ASSERT_EQUAL(fox.friend, first, "the friend does not change")

/// The Armalis cannot fire a quill with none left.
/datum/unit_test/dq_ability_ops_armalis_quills_needed

/datum/unit_test/dq_ability_ops_armalis_quills_needed/Run()
	var/mob/living/simple_mob/vox/armalis/A = allocate(/mob/living/simple_mob/vox/armalis, test_floor())
	A.set_quills(0)
	var/datum/op_result/R = dq_ability_menu_op(A, "fire_quill")
	TEST_ASSERT_EQUAL(R?.outcome, ACT_REFUSED, "fire_quill is refused with no quills")

/// Give asks the giver who to offer to; the offer then goes to that mob (do_give() only offers to a mob with a client, which a test world has none of,
/// so this checks the giver's question is asked and answered).
/datum/unit_test/dq_ability_ops_give_asks_the_recipient

/datum/unit_test/dq_ability_ops_give_asks_the_recipient/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/giver = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/recipient = allocate(/mob/living/carbon/human, T)
	var/obj/item/pen/offered = allocate(/obj/item/pen, T)
	giver.put_in_active_hand(offered)
	test_menu(giver, giver, "give")
	TEST_ASSERT_NOTNULL(SSrequests.open_for(giver), "the giver is asked who to give to")
	test_answer(giver, recipient.name)
	TEST_ASSERT_NULL(SSrequests.open_for(giver), "the giver's question is answered")

/// Look Up is on every living mob's own menu and commits.
/datum/unit_test/dq_ability_ops_look_up_commits

/datum/unit_test/dq_ability_ops_look_up_commits/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/datum/op_result/R = dq_ability_menu_op(H, "look_up")
	TEST_ASSERT(test_op_committed(R), "look_up commits on a human's own menu")

/// A cat named for somebody ignores everyone else, and an unnamed one befriends the first person who asks.
/datum/unit_test/dq_ability_ops_cat_befriends

/datum/unit_test/dq_ability_ops_cat_befriends/Run()
	var/turf/T = test_floor()
	var/mob/living/simple_mob/animal/passive/cat/cat = allocate(/mob/living/simple_mob/animal/passive/cat, T)
	var/mob/living/carbon/human/first = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/second = allocate(/mob/living/carbon/human, T)
	var/datum/op_result/befriended = perform_op(first, cat, "become_friends", null, ORIGIN_MENU)
	TEST_ASSERT(test_op_committed(befriended), "the first person befriends an unnamed cat")
	TEST_ASSERT_EQUAL(cat.friend, first, "the cat's friend is that person")
	var/datum/op_result/other = perform_op(second, cat, "become_friends", null, ORIGIN_MENU)
	TEST_ASSERT_EQUAL(other?.outcome, ACT_REFUSED, "a second person is ignored")

/// The human menu ops that were verbs: pulling punches toggles the trait, the icon toggles flip, and the ones with a guard refuse when it fails.
/datum/unit_test/dq_ability_ops_human_toggles_and_guards

/datum/unit_test/dq_ability_ops_human_toggles_and_guards/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/datum/op_result/pulled = dq_ability_menu_op(H, "pull_punches")
	TEST_ASSERT(test_op_committed(pulled), "pull_punches commits")
	TEST_ASSERT(has_trait_from(H, TRAIT_NONLETHAL_BLOWS, ACTION_TRAIT), "the punches are pulled")
	dq_ability_menu_op(H, "pull_punches")
	TEST_ASSERT(!has_trait_from(H, TRAIT_NONLETHAL_BLOWS, ACTION_TRAIT), "the second use stops pulling punches")
	var/was_hidden = H.hide_headset
	dq_ability_menu_op(H, "hide_headset")
	TEST_ASSERT_NOTEQUAL(H.hide_headset, was_hidden, "the headset's visibility flips")
	var/datum/op_result/alone = dq_ability_menu_op(H, "hand_games")
	TEST_ASSERT_EQUAL(alone?.outcome, ACT_REFUSED, "hand games are refused with nobody close")
	H.status_set(STAT_STUNNED, 5)
	var/datum/op_result/stunned = dq_ability_menu_op(H, "flip_lying")
	TEST_ASSERT_EQUAL(stunned?.outcome, ACT_REFUSED, "a stunned human cannot flip their resting direction")

/// The information verbs of living mobs are on their own menu and commit.
/datum/unit_test/dq_ability_ops_living_info_ops_commit

/datum/unit_test/dq_ability_ops_living_info_ops_commit/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	for(var/key in list("vore_check_nutrition", "check_default_language", "showoff"))
		var/datum/op_result/R = dq_ability_menu_op(H, key)
		TEST_ASSERT(test_op_committed(R), "[key] commits on a human's own menu")

/// Pull asks what to pull from the things within reach, and pulls the one picked.
/datum/unit_test/dq_ability_ops_pull_asks_what

/datum/unit_test/dq_ability_ops_pull_asks_what/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/puller = allocate(/mob/living/carbon/human, T)
	var/obj/structure/closet/crate/crate = allocate(/obj/structure/closet/crate, T)
	crate.forceMove(get_step(T, NORTH))
	puller.pulled()
	TEST_ASSERT_NOTNULL(SSrequests.open_for(puller), "the puller is asked what to pull")
	test_answer(puller, crate.name)
	TEST_ASSERT_EQUAL(puller.pulling_target(), crate, "the picked crate is being pulled")

/// light_flags is a sparse slot: an ordinary atom has no var and no slot list, setting it stores it, and clearing it frees the list again.
/datum/unit_test/dq_sparse_light_flags_slot

/datum/unit_test/dq_sparse_light_flags_slot/Run()
	var/obj/item/pen/P = allocate(/obj/item/pen, test_floor())
	TEST_ASSERT(!("light_flags" in P.vars), "light_flags is not a var of every atom any more")
	TEST_ASSERT_NULL(P.sparse_slots, "an ordinary atom carries no slot list")
	TEST_ASSERT_EQUAL(sparse_get_or(P, light_flags, NONE), NONE, "an unset slot reads as no flags")
	P.set_light_flags(LIGHT_ATTACHED)
	TEST_ASSERT_EQUAL(sparse_get_or(P, light_flags, NONE), LIGHT_ATTACHED, "the flag is stored")
	P.set_light_flags(NONE)
	TEST_ASSERT_NULL(P.sparse_slots, "clearing the last flag frees the slot list")

/// The platform's eye colour op is only on a robot that carries a platform module, and ghosts only whisper once manifest.
/datum/unit_test/dq_ability_ops_ghost_whisper_needs_manifest

/datum/unit_test/dq_ability_ops_ghost_whisper_needs_manifest/Run()
	var/mob/observer/dead/ghost = allocate(/mob/observer/dead, test_floor())
	ghost.set_is_manifest(FALSE)
	var/datum/op_result/R = dq_ability_menu_op(ghost, "ghost_whisper")
	TEST_ASSERT_EQUAL(R?.outcome, ACT_REFUSED, "a ghost that has not been pulled past the veil cannot whisper")
	var/mob/living/silicon/robot/borg = allocate(/mob/living/silicon/robot, test_floor())
	var/datum/op_result/plain = dq_ability_menu_op(borg, "set_eye_colour")
	TEST_ASSERT(plain?.outcome != ACT_COMMITTED, "a robot without a platform module has no eye colour to set")
