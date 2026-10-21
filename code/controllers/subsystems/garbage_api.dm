// The garbage system's API (code/controllers/subsystems/garbage.dm declares the system).
//
//   SSgarbage.pause() / resume()                      the collector stops or restarts firing (reference searches hold it still)
//   SSgarbage.set_should_save_refs(save)              reference searches record where they found a reference
//   garbage_*()                                       reads (code/contracts/accessors/accessors.dm)

/datum/system/garbage/proc/pause()
	set_can_fire(FALSE)

/datum/system/garbage/proc/resume()
	set_can_fire(TRUE)

/datum/system/garbage/proc/set_should_save_refs(save)
	should_save_refs = save
