// ex_act() overrides are explosion hit hooks now (extend(/datum/act/hit/explosion, instead(then(...)))).

/datum/unit_test/dq_blast_hook_anomaly_consumed

/datum/unit_test/dq_blast_hook_anomaly_consumed/Run()
	var/turf/T = dq_containment_floor()
	var/obj/effect/anomaly/mild = allocate(/obj/effect/anomaly, T)
	mild.ex_act(3)
	TEST_ASSERT(!QDELETED(mild), "a light blast leaves an anomaly alone")
	mild.ex_act(1)
	TEST_ASSERT(QDELETED(mild), "the worst blast consumes it")

/datum/unit_test/dq_blast_hook_simple_mob_ladder

/datum/unit_test/dq_blast_hook_simple_mob_ladder/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/simple_mob/animal/passive/mouse/mouse = allocate(/mob/living/simple_mob/animal/passive/mouse, T)
	mouse.ex_act(3)
	TEST_ASSERT(blast_test_injury(mouse) > 0 || QDELETED(mouse), "a blast on a simple mob hurts it through the hook")

/datum/unit_test/dq_blast_hook_human_ladder

/datum/unit_test/dq_blast_hook_human_ladder/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.ex_act(3)
	TEST_ASSERT(blast_test_injury(H) > 0 || QDELETED(H), "a blast on a human injures it through the hook")

/// Injury load in every category.
/proc/blast_test_injury(mob/living/L)
	. = 0
	if(QDELETED(L))
		return
	for(var/category in 1 to INJURY_CATEGORY_COUNT)
		. += L.injury_load(category)
