/datum/proc/lifecycle_keep(force)
	SHOULD_NOT_SLEEP(TRUE)
	// A registered singleton (REGISTRY_TYPE, doc/rewrite/ownership.md sec 2) is immortal: an
	// unforced qdel() of one is refused. Controllers keep the MC's own replacement rules.
	return !force && lifecycle_registry_immortal()


/datum/proc/lifecycle_dematerialize()
	return


/datum/proc/lifecycle_registry_immortal()
	return is_registered(src)

/datum/proc/on_destroy(force)
	SHOULD_CALL_PARENT(TRUE)
	return


/datum/proc/lifecycle_unbind()
	return
