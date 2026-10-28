// Admin panel and admin link object ids are ref_token() handles: a live thing resolves through the topic and window resolvers, a deleted one
// (a stale link or window row) names nothing, and a thing of the wrong type is refused.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/datum/unit_test/dq_ref_text_admin_topic_resolves_token

/datum/unit_test/dq_ref_text_admin_topic_resolves_token/Run()
	var/turf/T = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/mob/living/L = allocate(/mob/living, T)
	var/token = ref_token(L)
	TEST_ASSERT(istext(token), "the mob has a handle")
	TEST_ASSERT_EQUAL(topic_resolve_ref(null, token, /mob, TOPIC_ANY), L, "an anywhere lookup resolves the handle")
	TEST_ASSERT_EQUAL(topic_resolve_ref(null, token, /mob/living, TOPIC_IN_WORLD), L, "a world lookup resolves the handle of an atom")
	TEST_ASSERT_NULL(topic_resolve_ref(null, token, /obj, TOPIC_ANY), "a handle of another type than wanted names nothing")
	TEST_ASSERT_NULL(topic_resolve_ref(null, "999999:1", /mob, TOPIC_ANY), "a made-up handle names nothing")
	var/mob/living/doomed = new /mob/living(T)
	var/stale = ref_token(doomed)
	qdel(doomed)
	TEST_ASSERT_NULL(topic_resolve_ref(null, stale, /mob, TOPIC_ANY), "a stale handle (its mob deleted) is refused")
	TEST_ASSERT_NULL(topic_resolve_ref(null, stale, /mob, TOPIC_IN_WORLD), "a stale handle is refused in the world lookup too")

/datum/unit_test/dq_ref_text_admin_list_lookup_token

/datum/unit_test/dq_ref_text_admin_list_lookup_token/Run()
	var/turf/T = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/mob/living/in_list = allocate(/mob/living, T)
	var/mob/living/outside = allocate(/mob/living, T)
	var/list/pool = list(in_list)
	TEST_ASSERT_EQUAL(locate_in_list(pool, ref_token(in_list)), in_list, "a handle of a member resolves in its list")
	TEST_ASSERT_NULL(locate_in_list(pool, ref_token(outside)), "a live thing outside the list is not found by its handle")
	var/mob/living/doomed = new /mob/living(T)
	var/stale = ref_token(doomed)
	pool += doomed
	qdel(doomed)
	TEST_ASSERT_NULL(locate_in_list(pool, stale), "a stale handle finds nothing in the list")

/datum/unit_test/dq_ref_text_admin_window_arg_token

/datum/unit_test/dq_ref_text_admin_window_arg_token/Run()
	var/turf/T = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/mob/living/L = allocate(/mob/living, T)
	var/datum/schema/mob_ref = schema_ref(/mob)
	var/list/ok = schema_input(mob_ref, ref_token(L))
	TEST_ASSERT_EQUAL(ok[1], L, "a window's ref argument resolves from its handle")
	var/datum/schema/obj_ref = schema_ref(/obj)
	var/list/wrong = schema_input(obj_ref, ref_token(L))
	TEST_ASSERT_EQUAL(wrong[1], SCHEMA_REJECT, "a handle of the wrong type is refused")
	var/mob/living/doomed = new /mob/living(T)
	var/stale = ref_token(doomed)
	qdel(doomed)
	var/list/gone = schema_input(mob_ref, stale)
	TEST_ASSERT_NULL(gone[1], "a stale handle resolves to nothing")
	TEST_ASSERT_NULL(ui_token(stale, null, /mob), "ui_token refuses a stale handle")
	TEST_ASSERT_EQUAL(ui_token(ref_token(L), null, /mob), L, "ui_token resolves a live handle")

/datum/unit_test/dq_ref_text_admin_links_carry_handles

/datum/unit_test/dq_ref_text_admin_links_carry_handles/Run()
	var/turf/T = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/mob/living/L = allocate(/mob/living, T)
	var/token = url_encode(ref_token(L))
	var/jump = admin_jump_link(L, "holder")
	TEST_ASSERT(findtext(jump, "adminplayerobservejump=[token]"), "the jump link names its target by handle")
	TEST_ASSERT(!findtext(jump, "\[0x"), "and carries no raw ref text")
	TEST_ASSERT(findtext(ADMIN_QUE(L), "adminmoreinfo=[token]"), "the ? link names its target by handle")
	TEST_ASSERT(findtext(ADMIN_PP(L), "adminplayeropts=[token]"), "the PP link names its target by handle")
	TEST_ASSERT(findtext(ADMIN_SM(L), "subtlemessage=[token]"), "the SM link names its target by handle")

#endif
