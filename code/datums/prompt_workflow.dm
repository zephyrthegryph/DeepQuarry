/// Nonspatial continuation state shared by native content prompt workflows.
/datum/prompt_workflow

/// Finish the continuation and unlink its borrowed participants; this is not an inventory removal.
/datum/prompt_workflow/proc/retire()
	qdel(src) // ALLOW(lifecycle): Finished nonspatial request state has no inventory release contract.
