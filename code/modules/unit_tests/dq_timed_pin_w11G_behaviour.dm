// Behaviour pins for the timed actions of group G in round 3 of the timed-action lane (rewrite/timed3-G), on the harness of
// dq_timed_pin_w8_behaviour.dm. Only what a test can reach is pinned: the ladder climb and the slug glue struggle start from a plain proc call. The
// verbs, prompt answers and legacy afterattack() hooks of the other group G sites (stardog, worm, kururak, ddraig, macrophage, mob yank-out,
// z-moves, wall climbing, ship eating, grab pinning, the Nikki hat) have no click or menu entry a test driver reaches.

/datum/unit_test/dq_timed_pin_w11G
	abstract_type = /datum/unit_test/dq_timed_pin_w11G
	parent_type = /datum/unit_test/dq_timed_pin_w8
	/// The ladder the climb ends on.
	var/obj/structure/ladder/far_ladder

// ---- A ladder: climbing takes the ladder's climb time scaled by the climber's species ----

/datum/unit_test/dq_timed_pin_w11G/ladder_climb
	loss_cancels = TRUE
	drop_cancels = FALSE

/datum/unit_test/dq_timed_pin_w11G/ladder_climb/setup_scene()
	user = person()
	var/obj/structure/ladder/near = allocate(/obj/structure/ladder, get_turf(user))
	far_ladder = allocate(/obj/structure/ladder, get_step(user, NORTH))
	target = near
	held = null
	duration = near.climb_time * (user.species ? user.species.climb_mult : 1)

/datum/unit_test/dq_timed_pin_w11G/ladder_climb/start_click()
	test_chat_clear()
	var/obj/structure/ladder/near = target
	near.climbLadder(user, far_ladder)

/datum/unit_test/dq_timed_pin_w11G/ladder_climb/is_done()
	return !QDELETED(far_ladder) && user.loc == get_turf(far_ladder)

// ---- Slug glue: tugging free takes a minute for a normal sized victim ----

/datum/unit_test/dq_timed_pin_w11G/slug_glue_tug_free
	duration = 1 MINUTE
	finished = "You tug free"
	loss_cancels = TRUE
	drop_cancels = FALSE

/datum/unit_test/dq_timed_pin_w11G/slug_glue_tug_free/setup_scene()
	user = person()
	var/obj/effect/slug_glue/glue = allocate(/obj/effect/slug_glue, get_turf(user))
	glue.buckle_mob(user)
	target = glue
	held = null

/datum/unit_test/dq_timed_pin_w11G/slug_glue_tug_free/start_click()
	test_chat_clear()
	var/obj/effect/slug_glue/glue = target
	glue.user_unbuckle_mob(user, user)

/datum/unit_test/dq_timed_pin_w11G/slug_glue_tug_free/is_done()
	return !user.buckled_to()
