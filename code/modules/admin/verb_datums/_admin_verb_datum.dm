GENERAL_PROTECT_DATUM(/datum/admin_verb)

/**
 * This is the admin verb datum. It is used to store the verb's information and handle the verb's functionality.
 * All of this is setup for you, and you should not be defining this manually.
 * That means you reader.
 */
/datum/admin_verb
	var/name //! The name of the verb.
	var/description //! The description of the verb.
	var/category //! The category of the verb.
	var/permissions //! The permissions required to use the verb.
	var/visibility_flag //! The flag that determines if the verb is visible.
	var/debug_only = FALSE //! Set by DEBUG_VERB: only exists in DEBUG builds; every invocation is logged.
	VAR_PROTECTED/verb_path //! The path to the verb proc.

// Admin verbs are singletons.
LIFECYCLE_KEEP_UNLESS_FORCED(/datum/admin_verb)

/// Assigns the verb to the admin.
/datum/admin_verb/proc/assign_to_client(client/admin)
	grant(admin, granted_verb(verb_path), src)

/// Unassigns the verb from the admin.
/datum/admin_verb/proc/unassign_from_client(client/admin)
	revoke(admin, granted_verb(verb_path), src)
