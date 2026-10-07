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

/datum/unit_test/om/interim_media_track_actor_refusal
/datum/unit_test/om/interim_media_track_actor_refusal/run_om(list/made)
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
/datum/unit_test/om/interim_ghost_jukebox_track_actor_refusal/run_om(list/made)
	test_prompts_reset()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	TEST_ASSERT_NULL(actor.client, "the actual jukebox actor cannot claim native admin rights")
	var/obj/machinery/media/jukebox/ghost/jukebox = allocate(/obj/machinery/media/jukebox/ghost, run_loc_floor_bottom_left)
	var/datum/track/retained = allocate(/datum/track, "interim://local", "Retained test track", 30 SECONDS)
	rel_add(jukebox, nameof(jukebox.custom_tracks), retained)
	TEST_ASSERT_EQUAL(jukebox.custom_tracks[1], retained, "the jukebox owns its exact custom track before denial")
	var/datum/op_result/add = op_perform_by_key(actor, jukebox, null, "vv_add_track", ORIGIN_UI, AUTH_ADMIN, FALSE)
	TEST_ASSERT_EQUAL(add?.outcome, ACT_REFUSED, "the declared add workflow refuses missing rights")
	TEST_ASSERT_EQUAL(add?.reason, /datum/msg/req_no_rights, "admin origin does not invent actor rights")
	var/datum/op_result/remove = op_perform_by_key(actor, jukebox, null, "vv_remove_track", ORIGIN_UI, AUTH_ADMIN, FALSE)
	TEST_ASSERT_EQUAL(remove?.outcome, ACT_REFUSED, "the declared removal workflow refuses missing rights")
	TEST_ASSERT_EQUAL(remove?.reason, /datum/msg/req_no_rights, "the removal also checks actual actor rights")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 0, "rights refusals open no track prompts")
	TEST_ASSERT_EQUAL(length(jukebox.custom_tracks), 1, "refusal preserves catalog size")
	TEST_ASSERT_EQUAL(jukebox.custom_tracks[1], retained, "refusal preserves exact owned track identity")
	TEST_ASSERT(!QDELETED(retained), "refusal does not dispose the track")
	TEST_ASSERT_EQUAL(jukebox.playing, FALSE, "refused track controls start no audio playback")
