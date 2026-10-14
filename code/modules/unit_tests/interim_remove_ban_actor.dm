/// The native boundary supplies an unrelated ambient caller while invoking automatic ban cleanup.
/obj/interim_remove_ban_actor_probe
	var/result

/obj/interim_remove_ban_actor_probe/Click(location, control, params)
	result = RemoveBan("expiredfixture", null)

/datum/unit_test/interim_remove_ban_actor/Run()
	set_config(/datum/config_entry/string/chat_webhook_url, "")
	var/savefile/fixture = new
	set_global("banlist", fixture)
	fixture.cd = "/base/expiredfixture"
	fixture["key"] << "interimexpiredfixture"
	fixture["id"] << "expiredfixtureid"
	fixture.cd = "/base/retainedfixture"
	fixture["key"] << "interimretainedfixture"
	fixture["id"] << "retainedfixtureid"
	fixture.cd = "/base"
	TEST_ASSERT_EQUAL(length(fixture.dir), 2, "the actual isolated native savefile contains both ban folders")
	var/mob/living/carbon/human/unrelated = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/interim_remove_ban_actor_probe/probe = allocate(/obj/interim_remove_ban_actor_probe, run_loc_floor_bottom_left)
	km_synthetic_click(unrelated, probe)
	TEST_ASSERT_EQUAL(probe.result, 1, "actual automatic removal completes under an unrelated clientless native caller")
	fixture.cd = "/base"
	TEST_ASSERT_EQUAL(length(fixture.dir), 1, "actual removal deletes exactly one ban folder")
	TEST_ASSERT(!("expiredfixture" in fixture.dir), "the actual expired folder is removed")
	TEST_ASSERT("retainedfixture" in fixture.dir, "the unrelated real ban folder survives")
	fixture.cd = "/base/retainedfixture"
	var/retained_key
	var/retained_id
	fixture["key"] >> retained_key
	fixture["id"] >> retained_id
	TEST_ASSERT_EQUAL(retained_key, "interimretainedfixture", "the unrelated native savefile entry preserves its exact key")
	TEST_ASSERT_EQUAL(retained_id, "retainedfixtureid", "the unrelated native savefile entry preserves its exact ID")
	ClearAllBans(null)
	fixture.cd = "/base"
	TEST_ASSERT_EQUAL(length(fixture.dir), 0, "the actual actorless clear-all helper removes the remaining isolated folder")
