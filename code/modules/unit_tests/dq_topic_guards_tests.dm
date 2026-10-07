// Guards of question links that are requirements, checked before the question is asked: a refused link opens no question and says why; the same
// link with its guard satisfied opens its question. The guards read tracked mirrors (the mob's played and knows-language keys, a mech's state, the reel's cable_length,
// the admin caster's readiness).

/// The client-presence and language keys stay in step with what they mirror.
/datum/unit_test/dq_mob_state_keys

/datum/unit_test/dq_mob_state_keys/Run()
	var/mob/living/carbon/human/M = allocate(/mob/living/carbon/human, test_floor())
	TEST_ASSERT_EQUAL(mob_state_played(M), !!M.client, "a mob nobody plays says what the builtin does")
	key_set(M, MOB_STATE_PLAYED, TRUE)
	M.Logout()
	TEST_ASSERT_EQUAL(mob_state_played(M), !!M.client, "a mob that logs out follows its client (none here)")
	TEST_ASSERT_EQUAL(mob_state_played(M), FALSE, "so a logout clears the key")
	for(var/mob/each in world)
		TEST_ASSERT_EQUAL(mob_state_played(each), !!each.client, "no mob in the world disagrees with its client: [each] [each.type]")
	TEST_ASSERT_EQUAL(mob_state_knows_language(M), length(M.languages) > 0, "a fresh mob's key is its list")
	M.add_language(LANGUAGE_TRADEBAND)
	TEST_ASSERT_EQUAL(mob_state_knows_language(M), TRUE, "adding a language sets the key")
	M.add_language(LANGUAGE_TRADEBAND)
	TEST_ASSERT_EQUAL(mob_state_knows_language(M), TRUE, "adding it again changes nothing")
	for(var/datum/language/L in M.languages.Copy())
		M.remove_language(L.name)
		TEST_ASSERT_EQUAL(mob_state_knows_language(M), length(M.languages) > 0, "removing [L.name] keeps the key in step")
	TEST_ASSERT_EQUAL(mob_state_knows_language(M), FALSE, "a mob that knows nothing has the key off")

/datum/unit_test/om/dq_topic_guards

/// Performs `key` on `target` as `actor` (an admin) and returns the result; the questions it opened are in GLOB.test_prompts.
/datum/unit_test/om/dq_topic_guards/proc/perform(mob/actor, atom/target, key, list/arg_values = null)
	test_prompts_reset()
	return op_perform_by_key(actor, target, null, key, ORIGIN_UI, AUTH_ADMIN, FALSE, arg_values)

/datum/unit_test/om/dq_topic_guards/proc/refused_without_question(datum/op_result/R, reason_type, what)
	if(R?.outcome != ACT_REFUSED)
		return "[what]: expected a refusal, got [R?.outcome]"
	if(length(GLOB.test_prompts))
		return "[what]: a refused link must not open a question"
	if(reason_type && R.reason != reason_type)
		return "[what]: expected reason [reason_type], got [R.reason]"
	return null

/datum/unit_test/om/dq_topic_guards/proc/asks_question(datum/op_result/R, list/made, what)
	if(R?.outcome == ACT_REFUSED)
		return "[what]: refused ([R.reason])"
	if(length(GLOB.test_prompts) != 1)
		return "[what]: expected one question, found [length(GLOB.test_prompts)]"
	made += GLOB.test_prompts[1]
	return null

/datum/unit_test/om/dq_topic_guards
	/// The section being run, named in a runtime's failure.
	var/step = "start"

/datum/unit_test/om/dq_topic_guards/run_om(list/made)
	try
		guard_checks(made)
	catch(var/exception/e)
		TEST_FAIL("runtime in [step]: [e] [e.desc]")

/datum/unit_test/om/dq_topic_guards/proc/guard_checks(list/made)
	test_prompts_reset()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/fail
	step = "mech"
	// The mech: tank valve and passenger removal need the bolts exposed.
	var/obj/mecha/working/ripley/mech = allocate(/obj/mecha/working/ripley, T)
	fail = refused_without_question(perform(actor, mech, "set_internal_tank_valve"), null, "valve with the bolts hidden")
	TEST_ASSERT_NULL(fail, fail)
	mech.set_state(MECHA_BOLTS_SECURED)
	fail = asks_question(perform(actor, mech, "set_internal_tank_valve"), made, "valve with the bolts exposed")
	TEST_ASSERT_NULL(fail, fail)
	var/obj/item/mecha_parts/mecha_equipment/tool/passenger/P = allocate(/obj/item/mecha_parts/mecha_equipment/tool/passenger, T)
	var/mob/living/carbon/human/rider = allocate(/mob/living/carbon/human, T)
	P.attach(mech)
	TEST_ASSERT(move_into(P, OCCUPANT_SLOT_MECHA_PASSENGER, rider), "a passenger takes the compartment")
	fail = asks_question(perform(actor, mech, "remove_passenger"), made, "a passenger to remove")
	TEST_ASSERT_NULL(fail, fail)
	mech.set_state(MECHA_OPERATING)
	fail = refused_without_question(perform(actor, mech, "remove_passenger"), null, "passenger removal with the bolts hidden")
	TEST_ASSERT_NULL(fail, fail)
	step = "cable layer"
	// The mech's cable layer: nothing to cut on an empty reel.
	var/obj/item/mecha_parts/mecha_equipment/tool/cable_layer/layer = allocate(/obj/item/mecha_parts/mecha_equipment/tool/cable_layer, T)
	layer.attach(mech)
	var/mob/living/carbon/human/pilot = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT(move_into(mech, MECHA_SLOT_PILOT, pilot), "the pilot gets in (the cut question is asked inside the suit)")
	TEST_ASSERT_EQUAL(layer.chassis, mech, "the reel is on the suit")
	TEST_ASSERT_EQUAL(layer.cable_length, 0, "the reel starts empty")
	fail = refused_without_question(perform(pilot, layer, "cut"), /datum/msg/mecha_cable/no_cable, "cutting an empty reel")
	TEST_ASSERT_NULL(fail, fail)
	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, T, 20)
	TEST_ASSERT_EQUAL(layer.load_cable(coil), 20, "the reel takes the cable")
	TEST_ASSERT_EQUAL(layer.cable_length, 20, "and the mirror follows")
	fail = asks_question(perform(pilot, layer, "cut"), made, "cutting a loaded reel")
	TEST_ASSERT_NULL(fail, fail)
	step = "view variables"
	// View Variables: remove language and give AI.
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, T)
	for(var/datum/language/L in target.languages.Copy())
		target.remove_language(L.name)
	fail = refused_without_question(perform(actor, target, "vv_remlanguage"), /datum/msg/vv/no_languages, "removing a language from a mob that knows none")
	TEST_ASSERT_NULL(fail, fail)
	target.add_language(LANGUAGE_TRADEBAND)
	fail = asks_question(perform(actor, target, "vv_remlanguage"), made, "removing a language from a mob that knows one")
	TEST_ASSERT_NULL(fail, fail)
	// (The question's own check needs a real holder's rights, which a clientless actor has none of: the passing case asks the requirements themselves.)
	TEST_ASSERT(!mob_state_played(target) && target.vv_not_remote_driven(), "a mob nobody plays may be given an AI")
	key_set(target, MOB_STATE_PLAYED, TRUE)
	fail = refused_without_question(perform(actor, target, "vv_give_ai"), /datum/msg/vv/player_mob, "giving AI to a player's mob")
	TEST_ASSERT_NULL(fail, fail)
	key_set(target, MOB_STATE_PLAYED, FALSE)
	step = "admin round mode"
	// Admin panels: round mode and the replies refuse before asking.
	set_global("admin_datums", GLOB.admin_datums.Copy())
	set_global("deadmins", GLOB.deadmins.Copy())
	var/fixture_key = "dq_topic_guards"
	var/datum/admins/dq_topic_admin_fixture/holder = allocate(/datum/admins/dq_topic_admin_fixture, list(), fixture_key)
	GLOB.admin_datums -= fixture_key
	made += holder.admincaster_feed_message
	made += holder.admincaster_scratch_channel
	fail = refused_without_question(perform(actor, holder, "c_mode"), /datum/msg/admin_topic/round_started, "picking a mode once the round has started")
	TEST_ASSERT_NULL(fail, fail)
	set_var(SSticker, "mode", null)
	set_global("master_mode", "extended")
	fail = refused_without_question(perform(actor, holder, "f_secret"), /datum/msg/admin_topic/not_secret, "forcing a secret round when it is not")
	TEST_ASSERT_NULL(fail, fail)
	var/mob/living/carbon/human/unreachable = allocate(/mob/living/carbon/human, T)
	fail = refused_without_question(perform(actor, holder, "CentComReply", list("CentComReply" = unreachable)), /datum/msg/admin_topic/centcom_unreachable, "a CentCom reply to someone with no radio")
	TEST_ASSERT_NULL(fail, fail)
	set_global("master_mode", "secret")
	fail = asks_question(perform(actor, holder, "f_secret"), made, "forcing a secret round when it is secret")
	TEST_ASSERT_NULL(fail, fail)
	step = "newscaster"
	// The newscaster: a channel or Wanted draft that cannot be sent is refused before the confirmation.
	holder.admincaster_feed_channel().channel_name = ""
	holder.admincaster_resync()
	fail = refused_without_question(perform(actor, holder, "ac_submit_new_channel"), /datum/msg/admin_topic/channel_unsubmittable, "an unnamed channel")
	TEST_ASSERT_NULL(fail, fail)
	holder.admincaster_feed_channel().channel_name = "Guards Test Channel"
	holder.admincaster_resync()
	fail = asks_question(perform(actor, holder, "ac_submit_new_channel"), made, "a named channel")
	TEST_ASSERT_NULL(fail, fail)
	holder.admincaster_feed_message.author = ""
	holder.admincaster_feed_message.body = ""
	holder.admincaster_resync()
	fail = refused_without_question(perform(actor, holder, "ac_submit_wanted", list("ac_submit_wanted" = 1)), /datum/msg/admin_topic/wanted_unsubmittable, "a Wanted draft with no name")
	TEST_ASSERT_NULL(fail, fail)
	holder.admincaster_feed_message.author = "Somebody"
	holder.admincaster_feed_message.body = "Wanted for tests"
	holder.admincaster_resync()
	fail = asks_question(perform(actor, holder, "ac_submit_wanted", list("ac_submit_wanted" = 1)), made, "a Wanted draft that can be sent")
	TEST_ASSERT_NULL(fail, fail)
	test_prompts_reset()
