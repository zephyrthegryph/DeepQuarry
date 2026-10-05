/**
 * I7: bulk domain snapshot for the machinery/ATMOSPHERICS/power domains converted to
 * interaction entries (roadmap I7, doc/rewrite/interactions.md section 13). One snapshot
 * covering every converted type that doesn't already have a dedicated test, instead of
 * hand-writing hundreds of individual per-id tests; see dq_interaction_snapshots for the
 * smaller hand-picked domains. A change here shows up in review like any other snapshot.
 *
 * /obj/machinery/mineral/stacking_unit_console is excluded: it requires a linked stacking
 * machine on the map to initialize without a runtime, so it isn't included here; its one
 * id (stacking_console_use) is listed in dq_interaction_definitions/tested_ids instead.
 */
/datum/unit_test/dq_interaction_domain_snapshot/i7_bulk
	snapshot_dir = "code/modules/unit_tests/snapshots/i7_bulk/"

// Some snapshot targets deliberately leave things behind: the generic arcade replaces
// itself with a random game, an APC spills its cell (OWN_SPILL). Those are the test's.
/datum/unit_test/dq_interaction_domain_snapshot/i7_bulk/Run()
	..()
	own_turf_contents(test_floor())
