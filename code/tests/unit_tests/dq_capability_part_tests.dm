// CAPABILITIES_PART(T, feature): a feature adds entries to a type from its own file; the type's one declared_entries() holds the root's
// entries first, then each part's by feature name, and every entry keeps the file:line it was written at
// (doc/rewrite/proposals/capability_contributions.md).

/// The origin ("file:line") a compiled table gives its entry of `key`, or null.
/proc/dq_part_test_origin(datum/type_table/T, key)
	for(var/datum/centry/C as anything in T.items)
		var/datum/entry/E = C.item
		if(istype(E) && E.key == key)
			return C.origin
	return null

/datum/unit_test/dq_capability_part_entries_keep_their_own_file

/datum/unit_test/dq_capability_part_entries_keep_their_own_file/Run()
	// /obj/effect is rooted in effect_system.dm; its two "pass_insert" ops are the mopping part, written in mop_deploy.dm.
	var/obj/effect/effect/probe = new(null)
	var/datum/type_table/own = type_blocks_cache()[/obj/effect]
	TEST_ASSERT_NOTNULL(own, "the /obj/effect block compiled")
	var/part_origin = dq_part_test_origin(own, "pass_insert")
	TEST_ASSERT_NOTNULL(part_origin, "the mopping part's op is in the /obj/effect table")
	TEST_ASSERT(findtext(part_origin, "mop_deploy.dm"), "a part's entry names the part's file, got [part_origin]")
	var/root_origin = dq_part_test_origin(own, "melee_hit")
	TEST_ASSERT(isnull(root_origin) || findtext(root_origin, "effect_system.dm") || findtext(root_origin, "mop_deploy.dm") == 0, "the root's entries name the root's file, got [root_origin]")
	qdel(probe)

/datum/unit_test/dq_capability_part_relations_reach_the_base_tables

/datum/unit_test/dq_capability_part_relations_reach_the_base_tables/Run()
	// The xenoarch part owns /atom's artifact_master; the forensics part owns forensic_data; the root keeps light and reagents.
	var/obj/item/probe = new(null)
	for(var/var_name in list("artifact_master", "forensic_data", "reagents", "alt_appearances_owned"))
		TEST_ASSERT_NOTNULL(own_entry(probe, var_name), "[var_name] is owned by an atom through its root or a part")
	qdel(probe)
