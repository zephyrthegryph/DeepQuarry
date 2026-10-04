/datum/gizmo/proc/shared(mob/owner)
	om_grant(owner, GRANT_VERB, /mob/proc/shared_verb, "text source")
	om_revoke_each(owner, GRANT_VERB, list(/mob/proc/other_shared), src)
