/// Abstract test system stays outside the real kernel registry; inherited helpers still run their real guards.
/datum/system/media_tracks/interim_actor_probe
	abstract_type = /datum/system/media_tracks/interim_actor_probe
	var/tmp/mob/add_actor
	var/tmp/mob/remove_actor
	var/add_calls = 0
	var/remove_calls = 0

/datum/system/media_tracks/interim_actor_probe/manual_track_add(mob/user)
	rel_set(src, nameof(add_actor), user)
	add_calls++
	return ..()

/datum/system/media_tracks/interim_actor_probe/manual_track_remove(mob/user)
	rel_set(src, nameof(remove_actor), user)
	remove_calls++
	return ..()

/obj/machinery/media/jukebox/ghost/interim_actor_probe
	var/tmp/mob/add_actor
	var/tmp/mob/remove_actor
	var/add_calls = 0
	var/remove_calls = 0

/obj/machinery/media/jukebox/ghost/interim_actor_probe/vv_topic_add_track(datum/act/op/A)
	rel_set(src, nameof(add_actor), A.actor)
	add_calls++
	return ..()

/obj/machinery/media/jukebox/ghost/interim_actor_probe/vv_topic_remove_track(datum/act/op/A)
	rel_set(src, nameof(remove_actor), A.actor)
	remove_calls++
	return ..()

/obj/interim_jukebox_actor_click
	var/obj/machinery/media/jukebox/ghost/interim_actor_probe/jukebox
	var/mob/actor
	var/action
	var/datum/op_result/result

/obj/interim_jukebox_actor_click/Click(location, control, params)
	var/list/href = list()
	href[action] = "1"
	result = op_topic_href(actor, jukebox, href, namespace = VV_TOPIC, gated = FALSE)

/datum/unit_test/om/interim_media_track_actor_refusal/run_om(list/made)
	set_global(nameof(GLOB.test_prompts), GLOB.test_prompts)
	test_prompts_reset()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	TEST_ASSERT_NULL(actor.client, "the actual media fixture cannot claim native admin rights")
	var/datum/system/media_tracks/interim_actor_probe/tracks = allocate(/datum/system/media_tracks/interim_actor_probe)
	TEST_ASSERT(is_abstract(tracks), "the actual test system is abstract for kernel boot discovery")
	TEST_ASSERT_NULL(system_table()[tracks.type], "the inherited system constructor does not register this abstract test fixture")
	var/datum/track/retained = allocate(/datum/track, "interim://local", "Retained test track", 30 SECONDS)
	var/list/catalog = tracks.all_tracks
	catalog += retained
	TEST_ASSERT_EQUAL(tracks.all_tracks[1], retained, "the actual test catalog contains its exact track before denial")
	TEST_ASSERT_EQUAL(tracks.vv_topic_add_track(actor, list()), TRUE, "the actual VV add wrapper preserves its handled return")
	TEST_ASSERT_EQUAL(tracks.add_actor, actor, "the actual VV add wrapper forwards its explicit actor to the real guarded helper")
	TEST_ASSERT_EQUAL(tracks.add_calls, 1, "the add wrapper really invokes the inherited guard once")
	TEST_ASSERT_EQUAL(tracks.vv_topic_remove_track(actor, list()), TRUE, "the actual VV remove wrapper preserves its handled return")
	TEST_ASSERT_EQUAL(tracks.remove_actor, actor, "the actual VV remove wrapper forwards its explicit actor")
	TEST_ASSERT_EQUAL(tracks.remove_calls, 1, "the remove wrapper really invokes the inherited guard once")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 0, "the real required-rights refusals open no media prompts")
	TEST_ASSERT_EQUAL(length(tracks.all_tracks), 1, "actual rights denial leaves the real catalog size intact")
	TEST_ASSERT_EQUAL(tracks.all_tracks[1], retained, "actual rights denial preserves the exact existing track")
	TEST_ASSERT(!QDELETED(retained), "actual rights denial does not dispose the existing track")
	tracks.manual_track_add(null)
	tracks.manual_track_remove(null)
	TEST_ASSERT_NULL(tracks.add_actor, "the actual add helper receives the absent actor without ambient adoption")
	TEST_ASSERT_NULL(tracks.remove_actor, "the actual remove helper receives the absent actor without ambient adoption")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 0, "an absent actor opens no media prompt")
	TEST_ASSERT_EQUAL(tracks.all_tracks[1], retained, "absent actor refusal preserves the actual catalog member")

/datum/unit_test/om/interim_ghost_jukebox_track_actor_refusal

/// Real native VV admission preserves the supplied actor under an unrelated ambient caller.
/datum/unit_test/om/interim_ghost_jukebox_track_actor_refusal/run_om(list/made)
	set_global(nameof(GLOB.test_prompts), GLOB.test_prompts)
	test_prompts_reset()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/bystander = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT_NULL(actor.client, "the actual jukebox fixture cannot claim native admin rights")
	var/obj/machinery/media/jukebox/ghost/interim_actor_probe/jukebox = allocate(/obj/machinery/media/jukebox/ghost/interim_actor_probe, T)
	var/datum/track/retained = allocate(/datum/track, "interim://local", "Retained test track", 30 SECONDS)
	rel_add(jukebox, nameof(jukebox.custom_tracks), retained)
	TEST_ASSERT_EQUAL(jukebox.custom_tracks[1], retained, "the actual jukebox owns its exact custom track before denial")
	var/obj/interim_jukebox_actor_click/probe = allocate(/obj/interim_jukebox_actor_click, T)
	rel_set(probe, nameof(probe.jukebox), jukebox)
	rel_set(probe, nameof(probe.actor), actor)
	for(var/action in list("add_track", "remove_track"))
		probe.action = action
		test_record(actor, bystander, jukebox)
		km_synthetic_click(bystander, probe)
		var/list/events = test_recorded()
		var/outcomes = 0
		for(var/datum/test_event/event as anything in events)
			if(event.kind == TEST_EVENT_OUTCOME && event.key == "vv_[action]")
				outcomes++
				TEST_ASSERT_EQUAL(event.entity, actor, "native rights refusal is attributed to the supplied actor, not ambient usr")
		TEST_ASSERT_EQUAL(outcomes, 1, "the actual native VV action emits exactly one actor-attributed outcome")
		made += probe.result
		TEST_ASSERT_EQUAL(probe.result?.outcome, ACT_REFUSED, "the actual native VV [action] refuses the supplied actor without rights")
	TEST_ASSERT_EQUAL(jukebox.add_calls, 0, "the native add pipeline checks rights before running the actual effect")
	TEST_ASSERT_EQUAL(jukebox.remove_calls, 0, "the native remove pipeline checks rights before running the actual effect")
	TEST_ASSERT_NULL(jukebox.add_actor, "refusal never substitutes the ambient bystander in the add effect")
	TEST_ASSERT_NULL(jukebox.remove_actor, "refusal never substitutes the ambient bystander in the remove effect")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 0, "actual jukebox rights refusal opens no track prompt")
	TEST_ASSERT_EQUAL(length(jukebox.custom_tracks), 1, "actual jukebox rights refusal preserves catalog size")
	TEST_ASSERT_EQUAL(jukebox.custom_tracks[1], retained, "actual jukebox refusal preserves exact owned track identity")
	TEST_ASSERT(!QDELETED(retained), "actual jukebox refusal does not dispose its track")
	TEST_ASSERT_EQUAL(jukebox.playing, FALSE, "actual refused track controls start no audio playback")
	for(var/action in list("add_track", "remove_track"))
		var/list/href = list()
		href[action] = "1"
		var/datum/op_result/missing_actor = op_topic_href(null, jukebox, href, namespace = VV_TOPIC, gated = FALSE)
		TEST_ASSERT_NULL(missing_actor, "native VV transport rejects an absent actor before opening a question")
	TEST_ASSERT_EQUAL(jukebox.add_calls, 0, "an absent actor runs no native add effect")
	TEST_ASSERT_EQUAL(jukebox.remove_calls, 0, "an absent actor runs no native remove effect")
	TEST_ASSERT_NULL(jukebox.add_actor, "the actual native add keeps an absent actor absent")
	TEST_ASSERT_NULL(jukebox.remove_actor, "the actual native remove keeps an absent actor absent")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 0, "an absent jukebox actor opens no prompt")
	TEST_ASSERT_EQUAL(jukebox.custom_tracks[1], retained, "absent actor refusal preserves actual jukebox ownership")
