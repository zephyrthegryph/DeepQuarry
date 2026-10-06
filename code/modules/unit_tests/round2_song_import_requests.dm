/// Real violin/song/window and public legacy UI inbox path; no browser client or status mutation.
/datum/unit_test/round2_song_import_multibyte
	var/import_case = "multibyte"

/datum/unit_test/round2_song_import_multibyte/Run()
	test_driver_begin()
	exercise_import()
	own_turf_contents(test_floor())
	test_driver_end()

/datum/unit_test/round2_song_import_multibyte/proc/repeat_text(value, count)
	var/list/chunks = list()
	for(var/i in 1 to count)
		chunks += value
	return jointext(chunks, "")

/datum/unit_test/round2_song_import_multibyte/proc/exercise_import()
	var/turf/surface = test_floor()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, surface)
	var/obj/item/instrument/violin/instrument = allocate(/obj/item/instrument/violin, surface)
	var/datum/song/song = instrument.song
	TEST_ASSERT(istype(song) && song.parent() == instrument, "Actual violin constructor installs its owned real song")
	var/datum/tgui/editor = allocate(/datum/tgui, user, song, "InstrumentEditor")
	TEST_ASSERT_EQUAL(editor.user, user, "Actual UI constructor binds its original human")
	TEST_ASSERT_EQUAL(editor.src_object(), song, "Actual UI constructor binds its real song source")
	TEST_ASSERT_EQUAL(editor.status, STATUS_INTERACTIVE, "Real UI constructor starts interactive without a gate mutation")
	input_submit(new /datum/input_event/ui_act(user, editor, "import_song", list(), editor.state()))
	var/datum/prompt/text/song_import/initial = SSrequests.open_for(user)
	TEST_ASSERT(istype(initial), "Actual public UI button asks for the song")
	var/limit = MUSIC_MAXLINES * MUSIC_MAXLINECHARS
	if(import_case == "multibyte")
		var/line = repeat_text("é", 250)
		var/list/input_lines = list("BPM: 100")
		for(var/i in 1 to 600)
			input_lines += line
		var/raw = jointext(input_lines, "\n")
		TEST_ASSERT(length_char(raw) < limit && length(raw) > limit, "Real Unicode input is under the character limit but over the byte limit")
		test_answer(user, raw)
		TEST_ASSERT_NULL(SSrequests.open_for(user), "Character-valid Unicode import needs no size confirmation")
		TEST_ASSERT_EQUAL(length(song.lines), 600, "Actual parser retains every valid Unicode line")
		TEST_ASSERT_EQUAL(song.lines[1], line, "Actual first line preserves raw multibyte text")
		TEST_ASSERT_EQUAL(song.lines[600], line, "Actual final line proves byte normalization did not truncate input")
		TEST_ASSERT_EQUAL(song.tempo, song.sanitize_tempo(BPM_TO_TEMPO_SETTING(100)), "Actual parser reads the imported tempo header")
		return
	var/prefix = "BPM: 100\nC4\n"
	var/raw = prefix + repeat_text("x", limit - length_char(prefix) + (import_case == "oversize_yes" ? 1 : 0))
	TEST_ASSERT_EQUAL(length_char(raw), limit + (import_case == "oversize_yes" ? 1 : 0), "Actual raw import has the intended precise character boundary")
	test_answer(user, raw)
	var/datum/prompt/choice/song_import_continue/confirmation = SSrequests.open_for(user)
	TEST_ASSERT(istype(confirmation), "Boundary-sized input asks for confirmation in the same op")
	TEST_ASSERT_EQUAL(length(song.lines), 0, "Opening size confirmation does not prematurely mutate the actual song")
	test_answer(user, import_case == "exact_no" ? "No" : "Yes")
	if(import_case == "oversize_yes")
		// "Yes" to an oversized import ends it unparsed; the player presses import again to paste anew.
		TEST_ASSERT_NULL(SSrequests.open_for(user), "Oversize Yes ends the import")
		TEST_ASSERT_EQUAL(length(song.lines), 0, "Continuing editing leaves the real song unchanged")
		input_submit(new /datum/input_event/ui_act(user, editor, "import_song", list(), editor.state()))
		var/datum/prompt/text/song_import/reopened = SSrequests.open_for(user)
		TEST_ASSERT(istype(reopened) && reopened != initial, "Pressing import again asks for a new song")
		test_answer(user, "BPM: 100\né-C4\nD4")
		TEST_ASSERT_NULL(SSrequests.open_for(user), "Replacement text completes the actual resumed import")
		TEST_ASSERT_EQUAL(length(song.lines), 2, "Replacement multiline input is really parsed")
		TEST_ASSERT_EQUAL(song.lines[1], "é-C4", "Replacement import retains raw multibyte content")
		TEST_ASSERT_EQUAL(song.lines[2], "D4", "Replacement import retains its second actual line")
	else
		TEST_ASSERT_NULL(SSrequests.open_for(user), "Exact-limit Yes and No both complete import without reopening text")
		TEST_ASSERT_EQUAL(length(song.lines), 1, "Actual parser discards the oversized individual line and retains valid content")
		TEST_ASSERT_EQUAL(song.lines[1], "C4", "Exact-limit confirmation really commits parsed song content")
	TEST_ASSERT_EQUAL(song.tempo, song.sanitize_tempo(BPM_TO_TEMPO_SETTING(100)), "Completed boundary import really applies its tempo header")

/datum/unit_test/round2_song_import_multibyte/exact_yes
	import_case = "exact_yes"

/datum/unit_test/round2_song_import_multibyte/exact_no
	import_case = "exact_no"

/datum/unit_test/round2_song_import_multibyte/oversize_yes
	import_case = "oversize_yes"
