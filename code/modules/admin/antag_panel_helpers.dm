// Helper declarations for the structured antag panel. The legacy
// antagonist_panel.dm's HTML procs were deleted; this keeps the small
// extension point that subtypes (borer, traitor) override.

/datum/antagonist/proc/get_extra_panel_options(datum/mind/player)
	return ""
