// Sound and effect sets (doc/rewrite/systems.md section 16): SOUND_SET rows, get_sfx() and the
// pooled fx_sparks().

/// Every row is well formed: its id matches its key, it has files, and every file is a sound file.
/datum/unit_test/dq_sys_sfx_rows_well_formed

/datum/unit_test/dq_sys_sfx_rows_well_formed/Run()
	var/list/table = build_sound_sets()
	TEST_ASSERT(length(table) > 100, "the sound set table is populated ([length(table)] rows)")
	for(var/id in table)
		var/datum/sound_set/row = table[id]
		TEST_ASSERT_EQUAL(row.id, id, "row [id] carries its own id")
		TEST_ASSERT(length(row.files), "row [id] has files")
		TEST_ASSERT(isnum(row.volume) && row.volume > 0, "row [id] has a positive volume")
		for(var/file in row.files)
			TEST_ASSERT(isfile(file), "row [id] lists a file resource ([file])")
	QDEL_LIST_ASSOC_VAL(table)

/// get_sfx() resolves a set id to one of its files and passes anything else through.
/datum/unit_test/dq_sys_sfx_get_sfx

/datum/unit_test/dq_sys_sfx_get_sfx/Run()
	var/datum/sound_set/sparks = sound_set(SFX_SPARKS)
	TEST_ASSERT_NOTNULL(sparks, "the old \"sparks\" key is a sound set")
	for(var/i in 1 to 10)
		TEST_ASSERT(get_sfx(SFX_SPARKS) in sparks.files, "get_sfx(SFX_SPARKS) picks from the set")
	TEST_ASSERT_EQUAL(get_sfx('sound/effects/sparks1.ogg'), 'sound/effects/sparks1.ogg', "a file passes through")
	TEST_ASSERT_EQUAL(get_sfx("no_such_set"), "no_such_set", "an unknown key passes through")

/// fx_sparks() throws at most FX_SPARKS_MAX_PER_CALL (10) sparks and keeps the shared pool count.
/datum/unit_test/dq_sys_sfx_sparks_pool

/datum/unit_test/dq_sys_sfx_sparks_pool/Run()
	var/turf/T = test_floor()
	var/before = GLOB.fx_live_sparks
	fx_sparks(T, 50)
	var/thrown = GLOB.fx_live_sparks - before
	TEST_ASSERT(thrown > 0 && thrown <= 10, "one call throws between 1 and 10 sparks ([thrown])")
	for(var/obj/effect/effect/sparks/spark in world)
		qdel(spark)
	TEST_ASSERT_EQUAL(GLOB.fx_live_sparks, 0, "deleted sparks leave the pool")
