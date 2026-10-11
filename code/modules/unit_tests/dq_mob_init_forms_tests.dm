// Mobs whose Initialize() overrides became forms (rewrite/init-mob): rolls(), look_from(), wears(), trait(), swarming(), registries.

/datum/unit_test/dq_mob_init_forms_looks

/datum/unit_test/dq_mob_init_forms_looks/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/simple_mob/animal/passive/chicken/C = allocate(/mob/living/simple_mob/animal/passive/chicken, T)
	TEST_ASSERT(C.body_color in list("brown", "black", "white"), "a chicken rolls its colour ([C.body_color])")
	TEST_ASSERT_EQUAL(C.icon_living, "chicken_[C.body_color]", "look_from() names its living state after the colour")
	TEST_ASSERT_EQUAL(C.icon_dead, "chicken_[C.body_color]_dead", "and its dead state")
	TEST_ASSERT(REGISTRY_COUNT(REGISTRY_CHICKENS) >= 1, "the chicken counts toward the population cap")

	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, T)
	TEST_ASSERT(findtext(M.name, "mouse ("), "a mouse is numbered ([M.name])")
	TEST_ASSERT_EQUAL(M.real_name, M.name, "its real name follows")
	TEST_ASSERT_EQUAL(M.icon_rest, "mouse_[M.body_color]_sleep", "its sleeping state follows its colour")
	TEST_ASSERT_EQUAL(M.holder_type, text2path("/obj/item/holder/mouse/[M.body_color]"), "and its holder")
	TEST_ASSERT(has_trait(M, TRAIT_AMBIENT_PEST_MOB), "a mouse is an ambient pest")
	TEST_ASSERT(M.ghostjoin, "a mouse is open to ghosts")

	var/mob/living/simple_mob/animal/passive/mouse/brown/Tom/tom = allocate(/mob/living/simple_mob/animal/passive/mouse/brown/Tom, T)
	TEST_ASSERT_EQUAL(tom.name, "Tom", "a named mouse keeps its name")
	TEST_ASSERT_EQUAL(tom.real_name, "Tom", "and its real name follows it")

	var/mob/living/simple_mob/animal/passive/mouse/mining/cooper = allocate(/mob/living/simple_mob/animal/passive/mouse/mining, T)
	TEST_ASSERT_EQUAL(cooper.icon_dead, "mouse_miner_dead", "the miner mouse wears its own sprites")
	TEST_ASSERT_EQUAL(cooper.holder_type, /obj/item/holder/mouse/brown, "and keeps its brown holder")

	var/mob/living/simple_mob/vore/catgirl/girl = allocate(/mob/living/simple_mob/vore/catgirl, T)
	TEST_ASSERT(girl.icon_living in girl.skins, "a random-skinned mob picks one of its skins ([girl.icon_living])")
	TEST_ASSERT_EQUAL(girl.icon_dead, "[girl.icon_living]-dead", "and its dead state follows")

	var/mob/living/simple_mob/animal/passive/lizard/large/big = allocate(/mob/living/simple_mob/animal/passive/lizard/large, T)
	TEST_ASSERT(big.icon_scale_x >= 1.2 && big.icon_scale_x <= 2.0001, "a large lizard rolls its scale ([big.icon_scale_x])")
	TEST_ASSERT_EQUAL(big.icon_scale_y, big.icon_scale_x, "keeping its proportions")

	var/mob/living/simple_mob/vore/bigdragon/dragon = allocate(/mob/living/simple_mob/vore/bigdragon, T)
	TEST_ASSERT(dragon.overlay_colors["Body"] != "#FFFFFF" || dragon.under, "a dragon rolls its look")
	TEST_ASSERT_EQUAL(dragon.nutrition, dragon.max_nutrition, "and spawns fed")

	var/mob/living/simple_mob/vore/zorgoia/goia = allocate(/mob/living/simple_mob/vore/zorgoia, T)
	TEST_ASSERT_EQUAL(goia.goia_overlays["main"], "zorgoia_main", "a zorgoia rolls its overlay table")
	TEST_ASSERT(REAGENT_ID_STOXIN in goia.trait_injection_reagents, "and can inject its venoms")

	var/mob/living/simple_mob/animal/giant_spider/spider = allocate(/mob/living/simple_mob/animal/giant_spider, T)
	TEST_ASSERT(is_swarmer(spider), "a giant spider swarms from creation")

/datum/unit_test/dq_mob_init_forms_bodies

/datum/unit_test/dq_mob_init_forms_bodies/Run()
	var/turf/T = dq_containment_floor()

	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT(istype(H.reagents, /datum/reagents/metabolism/bloodstream), "a carbon's reagents are its bloodstream")
	TEST_ASSERT_EQUAL(H.bloodstr, H.reagents, "and bloodstr names it")
	TEST_ASSERT(istype(H.ingested, /datum/reagents/metabolism/ingested) && istype(H.touching, /datum/reagents/metabolism/touch), "it has a stomach and a skin")
	TEST_ASSERT(H.nutrition >= 200 && H.nutrition <= 400, "a human starts with 200-400 nutrition ([H.nutrition])")
	TEST_ASSERT(length(H.hide_underwear), "every underwear category starts shown")

	var/mob/living/carbon/human/skrell/S = allocate(/mob/living/carbon/human/skrell, T)
	TEST_ASSERT_EQUAL(S.species?.name, SPECIES_SKRELL, "a species subtype is made as its species")
	TEST_ASSERT_EQUAL(S.looks.hair_style, "Skrell Short Tentacles", "with its hair")

	var/mob/living/carbon/human/monkey/punpun/P = allocate(/mob/living/carbon/human/monkey/punpun, T)
	TEST_ASSERT_EQUAL(P.name, "Pun Pun", "Pun Pun is named over its species' name")

	var/mob/living/carbon/human/ai_controlled/joe = allocate(/mob/living/carbon/human/ai_controlled, T)
	TEST_ASSERT(istype(joe.get_equipped_item(SLOT_ID_SHOES), /obj/item/clothing/shoes/galoshes), "an ai-controlled human wears its outfit (wears())")
	var/obj/item/card/id/card = joe.get_equipped_item(SLOT_ID_ID)
	TEST_ASSERT_EQUAL(card?.registered_name, joe.real_name, "and its ID card is fitted to it")

	var/mob/living/silicon/ai/AI = allocate(/mob/living/silicon/ai, T, null, null, TRUE)
	TEST_ASSERT(AI.aiRadio, "an AI has its radio")
	TEST_ASSERT_EQUAL(AI.common_radio, AI.aiRadio, "which is its common radio")
	TEST_ASSERT(AI.laws, "and its laws")
	TEST_ASSERT_EQUAL(AI.announcement?.title, "A.I. Announcement", "its announcements are titled")
	TEST_ASSERT(AI.real_name in GLOB.ai_names, "it takes an AI name ([AI.real_name])")
	TEST_ASSERT_EQUAL(AI.announcement?.announcer, AI.name, "which its announcements carry")
	TEST_ASSERT(AI.psupply, "it has its power supply")
	TEST_ASSERT(AI.aiPDA && AI.aiCommunicator, "a real AI has a PDA and a communicator")

	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, T)
	TEST_ASSERT_EQUAL(R.robot_modules_background?.icon_state, "block", "a robot's module screen is made")
	TEST_ASSERT(GLOB.all_languages[LANGUAGE_ROBOT_TALK] in R.languages, "a robot knows robot talk")
