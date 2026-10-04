/datum/gizmo/proc/attach(mob/owner)
	grant(owner, granted_verb(/mob/proc/gizmo_menu), src)
	grant(owner, granted_verb(/mob/proc/gizmo_other, verb_name = "Other", verb_desc = "Another"), src) // renamed

/datum/gizmo/proc/detach(mob/owner)
	revoke(owner, granted_verb(/mob/proc/gizmo_menu), src)
	revoke(owner, granted_verb(/mob/proc/gizmo_other, verb_name = "Other", verb_desc = "Another"), src)
