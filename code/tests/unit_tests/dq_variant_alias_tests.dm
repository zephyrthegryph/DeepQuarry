// Old type paths of collapsed variant families (code/content/variants/variant_alias.dm): every row of a registered table is reachable by the
// path its type used to have, and a map that names that path loads the parent with the row's vars.

/// The registered families this file guards: every table in the registry whose rows are keyed by var name.
/proc/dq_variant_alias_families()
	var/list/families = list()
	for(var/parent in GLOB.dq_variant_tables)
		var/table = GLOB.vars[GLOB.dq_variant_tables[parent]]
		if(islist(table) && length(table))
			families[parent] = table
	return families

/datum/unit_test/dq_variant_alias_resolves

/datum/unit_test/dq_variant_alias_resolves/Run()
	var/checked = 0
	var/list/families = dq_variant_alias_families()
	TEST_ASSERT(length(families), "the registry holds families")
	for(var/parent in families)
		var/list/table = families[parent]
		for(var/key in table)
			var/list/alias = variant_alias_of("[parent]/[key]")
			TEST_ASSERT(islist(alias), "[parent]/[key] resolves as an old path")
			TEST_ASSERT_EQUAL(alias[1], parent, "[parent]/[key] names its parent")
			TEST_ASSERT_EQUAL(alias[2], key, "[parent]/[key] names its row")
			checked++
	TEST_ASSERT(checked > 0, "some old paths were checked")
	TEST_ASSERT_NULL(variant_alias_of("[/obj/structure/sign/department]/no_such_sign_ever"), "a key with no row is no alias")
	TEST_ASSERT_NULL(variant_alias_of("/obj/item/no_such_family/x"), "a path under no family is no alias")
	TEST_ASSERT_NULL(variant_alias_of("/obj"), "a one-segment path is no alias")
	TEST_ASSERT_NULL(variant_alias_of(null), "no text, no alias")

/// The signs: a made variant carries exactly what its row says, the same as the type it replaced did.
/datum/unit_test/dq_variant_alias_sign_rows

/datum/unit_test/dq_variant_alias_sign_rows/Run()
	set_global(nameof(GLOB.refresh_dispatched_draws_spared), GLOB.refresh_dispatched_draws_spared)
	var/turf/T = dq_containment_floor()
	var/made = 0
	var/list/families = dq_variant_alias_families()
	for(var/parent in families)
		if(!ispath(parent, /obj/structure/sign))
			continue
		var/list/table = families[parent]
		for(var/key in table)
			var/obj/structure/sign/S = variant_new(VARIANT(parent, key), T)
			TEST_ASSERT(istype(S), "[parent]/[key] makes a sign")
			var/list/row = table[key]
			for(var/var_name in row)
				if(!row[var_name])
					continue
				TEST_ASSERT_EQUAL(S.vars[var_name], row[var_name], "[parent]/[key] has its row's [var_name]")
			qdel(S)
			made++
	TEST_ASSERT(made > 0, "some sign rows were made")

/// A map that names an old path loads the parent with the row, and its own edits win.
/datum/unit_test/dq_variant_alias_map_load

/datum/unit_test/dq_variant_alias_map_load/Run()
	// Parsing a map text bumps this draw counter; set_global() restores it at teardown.
	set_global(nameof(GLOB.refresh_dispatched_draws_spared), GLOB.refresh_dispatched_draws_spared)
	var/list/row = dq_variant_vars(/obj/structure/sign/department, "medbay")
	TEST_ASSERT(islist(row), "the sign department table has a medbay row")
	var/text = jointext(list(
		"//MAP CONVERTED BY dmm2tgm.py THIS HEADER COMMENT PREVENTS RECONVERSION, DO NOT REMOVE",
		"\"a\" = (",
		"/obj/structure/sign/department/medbay,",
		"/turf/space,",
		"/area/space)",
		"\"b\" = (",
		"/obj/structure/sign/department/medbay{",
		"\tname = \"mapper name\";",
		"\tpixel_x = 3",
		"\t},",
		"/turf/space,",
		"/area/space)",
		"",
		"(1,1,1) = {\"",
		"ab",
		"\"}",
		""), "\n")
	var/datum/parsed_map/P = new(text)
	var/list/cache = P.build_cache(FALSE)
	TEST_ASSERT(islist(cache), "the model cache builds")
	var/list/plain = cache["a"]
	TEST_ASSERT(islist(plain), "model a is cached (models: [json_encode(P.grid_models)])")
	var/list/members = plain[1]
	TEST_ASSERT_EQUAL(members[1], /obj/structure/sign/department, "the old path loads its parent")
	var/list/attrs = plain[2][1]
	TEST_ASSERT_EQUAL(attrs["name"], row["name"], "and the row's name is an edit")
	TEST_ASSERT_EQUAL(attrs["icon_state"], row["icon_state"], "and its icon state")
	var/list/edited = cache["b"]
	var/list/edited_attrs = edited[2][1]
	TEST_ASSERT_EQUAL(edited_attrs["name"], "mapper name", "the map's own edit replaces the row's value")
	TEST_ASSERT_EQUAL(edited_attrs["pixel_x"], 3, "and its other edits stay")
	TEST_ASSERT_EQUAL(edited_attrs["icon_state"], row["icon_state"], "while the row's other vars stay")
