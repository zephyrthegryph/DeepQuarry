/// Append-effect only: no UI/request, range, capacity, or modify-handler coverage.
/datum/unit_test/round2_song_append_effect/Run()
	var/turf/surface = test_floor()
	var/obj/item/instrument/violin/first = allocate(/obj/item/instrument/violin, surface)
	var/obj/item/instrument/violin/second = allocate(/obj/item/instrument/violin, surface)
	var/datum/song/first_song = first.song
	var/datum/song/second_song = second.song
	TEST_ASSERT(istype(first_song) && istype(second_song), "real instrument constructors install their owned songs")
	TEST_ASSERT(first_song != second_song, "real instruments have independent song identities")
	TEST_ASSERT_EQUAL(first_song.parent(), first, "first song belongs to the exact actual instrument")
	TEST_ASSERT_EQUAL(second_song.parent(), second, "second song belongs to the exact actual instrument")
	first_song.append_answered_line("C4-E4-G4")
	TEST_ASSERT_EQUAL(length(first_song.lines), 1, "actual append effect adds exactly one normal line")
	TEST_ASSERT_EQUAL(first_song.lines[1], "C4-E4-G4", "actual append keeps the normal line text exact")
	var/long_line = ""
	for(var/i in 1 to MUSIC_MAXLINECHARS + 10)
		long_line += "x"
	TEST_ASSERT(length(long_line) > MUSIC_MAXLINECHARS, "the actual long input exceeds the production line limit")
	first_song.append_answered_line(long_line)
	TEST_ASSERT_EQUAL(length(first_song.lines), 2, "long input adds exactly one further line")
	TEST_ASSERT_EQUAL(length(first_song.lines[2]), MUSIC_MAXLINECHARS - 1, "actual append preserves the original exclusive-end truncation length")
	TEST_ASSERT_EQUAL(first_song.lines[1], "C4-E4-G4", "long append preserves the original line")
	TEST_ASSERT_EQUAL(length(second_song.lines), 0, "the independent real instrument song remains untouched")
