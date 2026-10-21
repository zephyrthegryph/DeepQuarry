// The presentation record is split from the reaction state (doc/rewrite/proposals/change_graph.md section 10, step 7): an atom's draw cache, verb
// decisions and worn watch live in its /datum/rx_look (atom/look_rec), the reaction layer's tables in /datum/rx_state (datum/rx).

/datum/unit_test/dq_change_rx_look_split

/datum/unit_test/dq_change_rx_look_split/Run()
	var/obj/cap_fixture/dx_core/F = allocate(/obj/cap_fixture/dx_core)
	refresh_flush()
	TEST_ASSERT_NOTNULL(F.look_rec, "a drawn atom carries a presentation record")
	TEST_ASSERT(!isnull(F.look_rec.look_key), "and its draw cache is in it")
	var/datum/rx_state/S = rx_of(F)
	for(var/name in list("look_key", "look_overlays", "look_underlays", "look_filters", "look_vis", "look_set_bits", "look_seen_dir", "refresh_hidden_verbs", "refresh_granted_verbs", "refresh_swept", "worn_watched"))
		TEST_ASSERT(!(name in S.vars), "[name] is no longer a reaction-state var")
		TEST_ASSERT(name in F.look_rec.vars, "[name] is a presentation-record var")
	var/datum/rx_look/rec = F.look_rec
	qdel(F)
	TEST_ASSERT(QDELETED(F), "the atom is gone")
	TEST_ASSERT_NULL(F.look_rec, "its presentation record is released with it")
	TEST_ASSERT(istype(rec), "the record itself is a plain record")
