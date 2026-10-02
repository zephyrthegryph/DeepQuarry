/// Self-targeting through pre_attack compares the supplied actor, outside a verb.
/datum/unit_test/interim_mindbinder_self_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human, T)
	var/obj/item/mindbinder/binder = allocate(/obj/item/mindbinder, T)
	actor.allow_mind_transfer = TRUE
	other.allow_mind_transfer = FALSE
	TEST_ASSERT(!binder.self_bind, "the binder starts with self-binding disabled")
	binder.pre_attack(other, actor, null)
	TEST_ASSERT(!binder.self_bind, "a different refused target does not arm self-binding")
	binder.pre_attack(actor, actor, null)
	TEST_ASSERT(binder.self_bind, "targeting the explicit actor arms self-binding")
	binder.pre_attack(actor, actor, null)
	TEST_ASSERT(!binder.self_bind, "targeting the actor again disables self-binding")
