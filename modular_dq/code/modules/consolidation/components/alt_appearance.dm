// Per-atom alternate-appearance storage. Component-backed, sparse.
// Global helpers to avoid proc-table bloat on every /atom subtype.

/datum/component/alt_appearances_owner
	dupe_mode = COMPONENT_DUPE_UNIQUE
	var/list/appearances

/datum/component/alt_appearances_owner/Initialize()
	. = ..()
	appearances = list()

/datum/component/alt_appearances_owner/Destroy(force)
	// Don't iterate-and-qdel here. The qdel chain runs both ways:
	//   /atom/Destroy() → remove_all_alt_appearances() → qdel each entry
	//   /datum/alternate_appearance/Destroy() → remove() → clear component
	// If this proc also iterated, we'd re-enter alternate_appearance.Destroy
	// after it had already deleted itself, triggering the "destroy proc
	// was called multiple times" runtime. The atom-level cleanup is the
	// authoritative path; we just drop our reference.
	appearances = null
	return ..()

/datum/component/alt_appearances_viewer
	dupe_mode = COMPONENT_DUPE_UNIQUE
	var/list/viewing

/datum/component/alt_appearances_viewer/Initialize()
	. = ..()
	viewing = list()

/datum/component/alt_appearances_viewer/Destroy(force)
	viewing = null
	return ..()

/proc/dq_get_alt_appearances(atom/a, create = FALSE)
	var/datum/component/alt_appearances_owner/c = a.GetComponent(/datum/component/alt_appearances_owner)
	if(!c && create)
		c = a.AddComponent(/datum/component/alt_appearances_owner)
	return c?.appearances

/proc/dq_clear_alt_appearances_component(atom/a)
	var/datum/component/alt_appearances_owner/c = a.GetComponent(/datum/component/alt_appearances_owner)
	if(c)
		qdel(c)

/proc/dq_get_viewing_alt_appearances(atom/a, create = FALSE)
	var/datum/component/alt_appearances_viewer/c = a.GetComponent(/datum/component/alt_appearances_viewer)
	if(!c && create)
		c = a.AddComponent(/datum/component/alt_appearances_viewer)
	return c?.viewing

/proc/dq_clear_viewing_alt_appearances_component(atom/a)
	var/datum/component/alt_appearances_viewer/c = a.GetComponent(/datum/component/alt_appearances_viewer)
	if(c)
		qdel(c)
