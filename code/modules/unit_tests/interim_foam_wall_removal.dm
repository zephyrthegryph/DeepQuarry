/// Actual foam-wall entry points preserve harmless hits and remove walls on guaranteed breaks.
/datum/unit_test/interim_foam_wall_removal
	var/mode = "projectile"

/datum/unit_test/interim_foam_wall_removal/trace
	mode = "trace"

/datum/unit_test/interim_foam_wall_removal/hulk
	mode = "hulk"

/datum/unit_test/interim_foam_wall_removal/weapon
	mode = "weapon"

/datum/unit_test/interim_foam_wall_removal/harmless_item
	mode = "harmless_item"

/datum/unit_test/interim_foam_wall_removal/grab
	mode = "grab"

/datum/unit_test/interim_foam_wall_removal/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/structure/foamedmetal/wall = allocate(/obj/structure/foamedmetal, T)
	TEST_ASSERT_EQUAL(wall.metal, 1, "the real aluminum foam wall gives deterministic projectile destruction")
	TEST_ASSERT(wall.density, "the actual foam wall starts as a physical obstacle")
	var/obj/item/item
	var/mob/living/carbon/human/victim
	var/obj/item/grab/grab
	switch(mode)
		if("projectile", "trace")
			var/projectile_type = mode == "trace" ? /obj/item/projectile/test : /obj/item/projectile/beam
			var/obj/item/projectile/projectile = allocate(projectile_type, T)
			wall.bullet_act(projectile)
			TEST_ASSERT(!QDELETED(projectile), "the actual wall hit preserves the supplied projectile object")
		if("hulk")
			user.add_mutation(HULK)
			TEST_ASSERT(user.has_mutation(HULK), "the real mutation enables guaranteed hand destruction")
			TEST_ASSERT_EQUAL(wall.interaction_hand(user, null, null), TRUE, "the actual hulk hand interaction succeeds")
			user.remove_mutation(HULK)
		if("weapon", "harmless_item")
			item = allocate(mode == "weapon" ? /obj/item/melee/cultblade : /obj/item/book, T)
			TEST_ASSERT(user.put_in_active_hand(item), "the actual item starts in the actor's active hand")
			if(mode == "weapon")
				TEST_ASSERT(item.force * 20 - wall.metal * 25 >= 100, "the real cult blade has guaranteed foam-breaking force")
			else
				TEST_ASSERT(item.force * 20 - wall.metal * 25 <= 0, "the real book has no chance to break the aluminum foam")
			TEST_ASSERT_EQUAL(wall.interaction_item(user, item, null), INTERACTION_HANDLED_PASS, "the actual item entry retains its handled-pass contract")
			TEST_ASSERT_EQUAL(user.get_active_hand(), item, "the actual item hit preserves the original held item")
			TEST_ASSERT(!QDELETED(item), "the actual item hit never consumes the attacking item")
		if("grab")
			victim = allocate(/mob/living/carbon/human, T)
			grab = allocate(/obj/item/grab, user, victim)
			TEST_ASSERT(!QDELETED(grab), "the real grab initializes a live relation")
			TEST_ASSERT_EQUAL(grab.grab_target(), victim, "the actual grab references the exact victim")
			TEST_ASSERT(grab in victim.grabbed_by_list(), "the actual victim records the real grabbing relation")
			TEST_ASSERT_EQUAL(wall.interaction_item(user, grab, null), INTERACTION_HANDLED_PASS, "the actual grab smash retains its handled-pass contract")
			TEST_ASSERT(QDELETED(grab), "the actual grab smash consumes its original grab item")
			TEST_ASSERT(!(grab in victim.grabbed_by_list()), "actual grab deletion clears the victim's grabbing relation")
			TEST_ASSERT(!QDELETED(victim), "the actual grab smash preserves its exact victim")
			TEST_ASSERT_EQUAL(victim.loc, T, "the actual grab smash leaves its victim on the wall's floor")
	own_turf_contents(T)
	if(mode == "trace" || mode == "harmless_item")
		TEST_ASSERT(!QDELETED(wall), "an actual harmless entry preserves the foam wall")
		TEST_ASSERT_EQUAL(wall.loc, T, "the surviving foam wall stays on its original floor")
		TEST_ASSERT(wall.density, "the surviving foam wall remains a physical obstacle")
	else
		TEST_ASSERT(QDELETED(wall), "an actual guaranteed break consumes the original foam wall")
		TEST_ASSERT_EQUAL(length(contents_of(T, /obj/structure/foamedmetal)), 0, "actual destruction leaves no replacement foam obstacle")
	TEST_ASSERT(!QDELETED(user), "the actual foam interaction preserves its actor")
