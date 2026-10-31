/// Real parent deletion cleans up the original nullspace particle emitter and its visibility attachments.
/datum/unit_test/interim_particle_parent_cleanup
	var/attached = FALSE

/datum/unit_test/interim_particle_parent_cleanup/attached
	attached = TRUE

/datum/unit_test/interim_particle_parent_cleanup/Run()
	var/turf/T = test_floor()
	var/obj/item/pen/parent = allocate(/obj/item/pen, T)
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/flags = attached ? PARTICLE_ATTACH_MOB : NONE
	var/obj/effect/abstract/particle_holder/holder = allocate(/obj/effect/abstract/particle_holder, parent, /particles/smoke, flags)
	TEST_ASSERT(holder && !QDELETED(holder), "The real emitter constructor succeeds on its original parent")
	TEST_ASSERT_EQUAL(holder.get_parent(), parent, "The real emitter retains the exact original parent relation")
	TEST_ASSERT_NULL(holder.loc, "The actual initialized emitter leaves parent storage for nullspace")
	TEST_ASSERT(holder.particles && istype(holder.particles, /particles/smoke), "The real initialized emitter owns its actual smoke particle effect")
	TEST_ASSERT(holder in parent.vis_contents, "The actual constructor attaches its original emitter to parent visibility")
	TEST_ASSERT_EQUAL(holder.particle_flags, flags, "The actual constructor preserves the exact attachment flags")
	if(attached)
		TEST_ASSERT(actor.put_in_active_hand(parent), "The real actor picks up the original emitter parent")
		TEST_ASSERT(holder in actor.vis_contents, "The actual moved event attaches the original emitter to its real mob holder")
	qdel(parent)
	TEST_ASSERT(QDELETED(parent), "The original real parent completes ordinary deletion")
	TEST_ASSERT(QDELETED(holder), "The actual parent qdeleting event consumes the original nullspace emitter")
	TEST_ASSERT(!(holder in actor.vis_contents), "Actual emitter cleanup leaves no original visibility attachment on the surviving actor")
	TEST_ASSERT(!QDELETED(actor) && actor.loc == T, "Actual emitter cleanup preserves the surviving actor and original floor")
