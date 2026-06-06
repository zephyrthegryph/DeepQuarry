// DQEdit — original fix_atmos verb was a ZAS-specific reset (purge pipenets,
// delete zones, reset all turf .air vars, reboot SSair). Under LINDA atmos the
// concepts (zones, pipenets-as-/datum/pipe_network, turf.air var) don't exist
// in the same shape. The LINDA equivalent is SSair.process_excited_groups()
// for transient cleanup, plus deleting active turfs from SSair.active_turfs.
//
// Until a LINDA-shaped equivalent is wired in, the verb is stubbed to a clear
// admin message. Admins who need to reset can still depower the supermatter
// manually via varedit.
ADMIN_VERB(fix_atmos, (R_ADMIN|R_DEBUG|R_EVENT), "Fix Atmospherics Grief", "View or retrieve logfiles for the current round.", ADMIN_CATEGORY_GAME)
	feedback_add_details("admin_verb","FA")
	log_and_message_admins("Atmos-grief-fixer verb invoked by [user]. NOTE: Stub under LINDA migration — please use SSair varedit instead.")
	to_chat(user, span_warning("LINDA migration: the bulk atmos-reset verb is currently stubbed. Use SSair varedit (clear active_turfs, then call SSair.fire) for manual reset."))
