/// Actual player-note deletion retains the other persisted entry and uses the supplied actor.
/datum/unit_test/interim_player_notes_delete_actor/Run()
	set_config(/datum/config_entry/string/chat_webhook_url, "")
	var/fixture_key = "interimnotesdeleteactor[world.realtime]"
	var/path = "data/player_saves/[copytext(fixture_key, 1, 2)]/[fixture_key]/info.sav"
	TEST_ASSERT(!fexists(path), "the dedicated persistence fixture does not overwrite an existing player save")
	defer_cleanup(src, PROC_REF(cleanup_fixture_file), path)
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/player_info/first = allocate(/datum/player_info)
	var/datum/player_info/second = allocate(/datum/player_info)
	first.author = "first-author"
	first.content = "remove this exact note"
	first.timestamp = "first-time"
	second.author = "second-author"
	second.content = "retain this exact note"
	second.timestamp = "second-time"
	var/savefile/fixture = new(path)
	var/list/infos = list(first, second)
	fixture.cd = "/"
	fixture << infos
	fixture.Flush()
	fixture.cd = "/"
	fixture = null
	TEST_ASSERT(fexists(path), "the actual two-entry fixture is persisted before deletion")
	var/savefile/precheck = new(path)
	precheck.cd = "/"
	var/list/before
	precheck >> before
	for(var/datum/player_info/entry as anything in before)
		own(entry)
	precheck.cd = "/"
	precheck = null
	TEST_ASSERT_EQUAL(length(before), 2, "a fresh actual root-buffer read contains both persisted notes before deletion")
	var/datum/player_info/before_first = before[1]
	var/datum/player_info/before_second = before[2]
	TEST_ASSERT(istype(before_first) && istype(before_second), "both pre-deletion serialized entries are real player-info datums")
	TEST_ASSERT_EQUAL(before_first.author, "first-author", "the actual initial first author is preserved by native serialization")
	TEST_ASSERT_EQUAL(before_first.content, "remove this exact note", "the actual initial first note is present before deletion")
	TEST_ASSERT_EQUAL(before_second.author, "second-author", "the actual initial second author is preserved by native serialization")
	TEST_ASSERT_EQUAL(before_second.content, "retain this exact note", "the actual initial second note is present before deletion")
	notes_del(fixture_key, 1, actor)
	var/savefile/result = new(path)
	result.cd = "/"
	var/list/remaining
	result >> remaining
	for(var/datum/player_info/entry as anything in remaining)
		own(entry)
	result = null
	fdel(path)
	TEST_ASSERT_EQUAL(length(remaining), 1, "the actual helper removes exactly one persisted entry")
	var/datum/player_info/retained = remaining[1]
	TEST_ASSERT(istype(retained), "the persisted remainder is a real player-info datum")
	TEST_ASSERT_EQUAL(retained.author, "second-author", "actual deletion preserves the other note's exact author")
	TEST_ASSERT_EQUAL(retained.content, "retain this exact note", "actual deletion preserves the other note's exact text")
	TEST_ASSERT_EQUAL(retained.timestamp, "second-time", "actual deletion preserves the other note's exact timestamp")
	TEST_ASSERT(!fexists(path), "the dedicated fixture file is removed after the real persistence check")

/datum/unit_test/interim_player_notes_delete_actor/proc/cleanup_fixture_file(path)
	fdel(path)
