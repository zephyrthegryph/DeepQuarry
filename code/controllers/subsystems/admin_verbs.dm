GENERAL_PROTECT_DATUM(/datum/system/admin_verbs)

SYSTEM_DEF(admin_verbs)
	name = "Admin Verbs"
	init_stage = INITSTAGE_EARLY
	/// A list of all admin verbs indexed by their type.
	var/list/datum/admin_verb/admin_verbs_by_type = list()
	/// A list of all admin verbs indexed by their visibility flag.
	var/list/list/datum/admin_verb/admin_verbs_by_visibility_flag = list()
	/// A map of all assosciated admins and their visibility flags.
	var/list/admin_visibility_flags = list()
	/// A list of all admins that are pending initialization of this SS.
	var/list/admins_pending_subsytem_init = list()

/datum/system/admin_verbs/initialize()
	setup_verb_list()
	process_pending_admins()


/datum/system/admin_verbs/stat_entry(msg)
	return "[..()] | V: [length(admin_verbs_by_type)]"

/datum/system/admin_verbs/proc/process_pending_admins()
	var/list/pending_admins = admins_pending_subsytem_init
	admins_pending_subsytem_init = null
	for(var/admin_ckey in pending_admins)
		assosciate_admin(GLOB.directory[admin_ckey])

/datum/system/admin_verbs/proc/setup_verb_list()
	if(length(admin_verbs_by_type))
		CRASH("Attempting to setup admin verbs twice!")
	for(var/datum/admin_verb/verb_type as anything in subtypesof(/datum/admin_verb))
		var/datum/admin_verb/verb_singleton = new verb_type
		if(!verb_singleton.__avd_check_should_exist())
			spent(verb_singleton, force = TRUE)
			continue

		if(verb_singleton.debug_only && verb_singleton.permissions == R_NONE)
			CRASH("Debug verb '[verb_type]' must require a permission; R_NONE exposes it to every admin.")

		admin_verbs_by_type[verb_type] = verb_singleton
		if(verb_singleton.visibility_flag)
			if(!(verb_singleton.visibility_flag in admin_verbs_by_visibility_flag))
				admin_verbs_by_visibility_flag[verb_singleton.visibility_flag] = list()
			admin_verbs_by_visibility_flag[verb_singleton.visibility_flag] |= list(verb_singleton)

/datum/system/admin_verbs/proc/get_valid_verbs_for_admin(client/admin)
	if(isnull(admin.holder))
		CRASH("Why are we checking a non-admin for their valid... ahem... admin verbs?")

	var/list/has_permission = list()
	for(var/permission_flag in GLOB.bitflags)
		if(admin.holder.check_for_rights(permission_flag))
			has_permission["[permission_flag]"] = TRUE

	var/list/valid_verbs = list()
	for(var/datum/admin_verb/verb_type as anything in admin_verbs_by_type)
		var/datum/admin_verb/verb_singleton = admin_verbs_by_type[verb_type]
		if(!verify_visibility(admin, verb_singleton))
			continue

		var/verb_permissions = verb_singleton.permissions
		if(verb_permissions == R_NONE)
			valid_verbs |= list(verb_singleton)
		else for(var/permission_flag in bitfield_to_list(verb_permissions))
			if(!has_permission["[permission_flag]"])
				continue
			valid_verbs |= list(verb_singleton)

	return valid_verbs

/datum/system/admin_verbs/proc/verify_visibility(client/admin, datum/admin_verb/verb_singleton)
	var/needed_flag = verb_singleton.visibility_flag
	return !needed_flag || (needed_flag in admin_visibility_flags[admin.ckey])

/datum/system/admin_verbs/proc/update_visibility_flag(client/admin, flag, state)
	if(state)
		admin_visibility_flags[admin.ckey] |= list(flag)
		assosciate_admin(admin)
		return

	admin_visibility_flags[admin.ckey] -= list(flag)
	// they lost the flag, iterate over verbs with that flag and yoink em
	for(var/datum/admin_verb/verb_singleton as anything in admin_verbs_by_visibility_flag[flag])
		verb_singleton.unassign_from_client(admin)
	admin.init_verbs()

/datum/system/admin_verbs/proc/dynamic_invoke_verb(client/admin, datum/admin_verb/verb_type, ...)
	if(IsAdminAdvancedProcCall())
		message_admins("PERMISSION ELEVATION: [key_name_admin(admin)] attempted to dynamically invoke admin verb '[verb_type]'.")
		return

	if(ismob(admin))
		var/mob/mob = admin
		admin = mob.client

	if(!ispath(verb_type, /datum/admin_verb) || verb_type == /datum/admin_verb)
		CRASH("Attempted to dynamically invoke admin verb with invalid typepath '[verb_type]'.")
	if(isnull(admin.holder))
		CRASH("Attempted to dynamically invoke admin verb '[verb_type]' with a non-admin.")

	var/list/verb_args = args.Copy()
	verb_args.Cut(2, 3)
	var/datum/admin_verb/verb_singleton = admin_verbs_by_type[verb_type] // this cannot be typed because we need to use `:`
	if(isnull(verb_singleton))
		CRASH("Attempted to dynamically invoke admin verb '[verb_type]' that doesn't exist.")

	if(!admin_can(admin, verb_singleton.permissions))
		admin_log_denial(admin, "verb:[verb_type]", verb_singleton.permissions)
		to_chat(admin, span_adminnotice("You lack the permissions to do this."))
		return

	if(verb_singleton.debug_only)
		log_admin("DEBUG VERB: [key_name(admin)] invoked '[verb_singleton.name]' ([verb_type])")
	METRICS_EVENT(METRICS_EVENT_ADMIN_VERB, verb_singleton.category, "[verb_type]", admin.ckey, verb_singleton.name, null)

	// THE MACRO ENSURES THIS EXISTS. IF IT EVER DOESNT EXIST SOMEONE DIDNT USE THE DAMN MACRO!
	with_actor(arglist(list(admin.mob, verb_singleton, "__avd_do_verb") + verb_args))

/**
 * Assosciates and/or resyncs an admin with their accessible admin verbs.
 */
/datum/system/admin_verbs/proc/assosciate_admin(client/admin)
	if(IsAdminAdvancedProcCall())
		return

	if(!isnull(admins_pending_subsytem_init)) // if the list exists we are still initializing
		to_chat(admin, span_large(span_green("Admin Verbs are still initializing. Please wait and you will be automatically assigned your verbs when it is complete.")))
		admins_pending_subsytem_init |= list(admin.ckey)
		return

	// refresh their verbs
	admin_visibility_flags[admin.ckey] ||= list()
	if(admin.is_localhost())
		admin_visibility_flags[admin.ckey] |= list(ADMIN_VERB_VISIBLITY_FLAG_LOCALHOST)
	for(var/datum/admin_verb/verb_singleton as anything in get_valid_verbs_for_admin(admin))
		verb_singleton.assign_to_client(admin)
	admin.init_verbs()

/**
 * Unassosciates an admin from their admin verbs.
 * Goes over all admin verbs because we don't know which ones are assigned to the admin's mob without a bunch of extra bookkeeping.
 * This might be a performance issue in the future if we have a lot of admin verbs.
 */
/datum/system/admin_verbs/proc/deassosciate_admin(client/admin)
	if(IsAdminAdvancedProcCall())
		return

	for(var/datum/admin_verb/verb_type as anything in admin_verbs_by_type)
		admin_verbs_by_type[verb_type].unassign_from_client(admin)
	admin_visibility_flags -= list(admin.ckey)
