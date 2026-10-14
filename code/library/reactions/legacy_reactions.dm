// Compatibility names for old declarations; the engine owns actual reaction forms.
/proc/legacy_on_notice(type, handler)
	return reaction_on_notice(type, handler)

/proc/legacy_on_change(list/reads, handler, at_most = 0, when = null)
	return reaction_on_change(reads, handler, at_most, when)
