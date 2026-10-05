/**
 * I7: bulk domain snapshot for the items domain converted to interaction entries
 * (roadmap I7, doc/rewrite/interactions.md section 13). One snapshot covering every
 * converted item type, generated from the resolver's actual current output, the
 * same technique as dq_i7_bulk_capture.dm / dq_i7_structures_bulk_capture.dm for the
 * machinery and structures domains. Grows as more items subdomains are converted.
 */
/datum/unit_test/dq_interaction_domain_snapshot/i7_items_bulk
	snapshot_dir = "code/modules/unit_tests/snapshots/i7_items_bulk/"
