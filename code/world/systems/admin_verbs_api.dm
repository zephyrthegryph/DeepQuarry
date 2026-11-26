// The admin verb system's API (code/world/systems/admin_verbs.dm declares the system).
//
//   SSadmin_verbs.browser_verbs_for(client)       the verbs the Admin Verbs browser lists for this admin
//   SSadmin_verbs.verb_by_id(id)                  the admin verb with this ADMIN_VERB path name
//   SSadmin_verbs.is_admin_verb_name(name)        whether a verb panel entry of this name is an ADMIN_VERB
//   SSadmin_verbs.visibility_flags_of(client)     the visibility flags (Localhost, Map-Debug) the admin has on
//   SSadmin_verbs.browser_resolve(id, rights, flags) / browser_run(client, id)   resolve and run a verb from the browser

/datum/system/admin_verbs/proc/browser_verbs_for(client/admin)
	return browser_verbs(admin_rank_flags(admin), visibility_flags_of(admin))

/datum/system/admin_verbs/proc/verb_by_id(id)
	RETURN_TYPE(/datum/admin_verb)
	return admin_verbs_by_id[id]

/datum/system/admin_verbs/proc/is_admin_verb_name(verb_name)
	return !!admin_verb_names[verb_name]

/datum/system/admin_verbs/proc/visibility_flags_of(client/admin)
	return admin_visibility_flags[admin?.ckey]
