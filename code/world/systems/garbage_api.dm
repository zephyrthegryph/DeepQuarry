// The garbage system's API (code/controllers/subsystems/garbage.dm declares the system).
//
//   SSgarbage.pause() / resume()                      the collector stops or restarts firing (reference searches hold it still)
//   SSgarbage.find_reference_on_fail_enabled()        whether a failed hard delete starts a reference search
//   SSgarbage.save_refs(save) / references_saved()    reference searches record where they found a reference
//   garbage_*()                                       reads (code/contracts/accessors/accessors.dm)
//
// The reference-tracking flags exist only in a REFERENCE_TRACKING build; every other build answers with the off value.

/datum/system/garbage/proc/pause()
	set_can_fire(FALSE)

/datum/system/garbage/proc/resume()
	set_can_fire(TRUE)

/datum/system/garbage/proc/find_reference_on_fail_enabled()
#ifdef REFERENCE_TRACKING
	return find_reference_on_fail_global_toggle
#else
	return FALSE
#endif

/// Starts or stops recording where reference searches find a reference (a REFERENCE_TRACKING_DEBUG build; elsewhere it does nothing).
/datum/system/garbage/proc/save_refs(save)
#ifdef REFERENCE_TRACKING_DEBUG
	should_save_refs = save
#endif

/datum/system/garbage/proc/references_saved()
#ifdef REFERENCE_TRACKING_DEBUG
	return should_save_refs
#else
	return FALSE
#endif
