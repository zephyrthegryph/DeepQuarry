/datum/gizmo/proc/attach(mob/owner)
	om_grant(owner, GRANT_VERB, /mob/proc/gizmo_menu, src)
	om_grant(owner, GRANT_VERB, VERB_NAMED(/mob/proc/gizmo_other, "Other", "Another"), src) // renamed

/datum/gizmo/proc/detach(mob/owner)
	om_revoke(owner, GRANT_VERB, /mob/proc/gizmo_menu, src)
	om_revoke(owner, GRANT_VERB, VERB_NAMED(/mob/proc/gizmo_other, "Other", "Another"), src)
