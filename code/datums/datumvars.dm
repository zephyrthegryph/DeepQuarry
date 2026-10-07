/datum/proc/CanProcCall(procname)
	return TRUE

/datum/proc/can_vv_get(var_name)
	SHOULD_CALL_PARENT(TRUE)
	if(var_name == NAMEOF(src, vars))
		return FALSE
	return TRUE

/// Called when a var is edited with the new value to change to
/datum/proc/vv_edit_var(var_name, var_value)
	if(var_name == NAMEOF(src, vars))
		return FALSE
	datum_flags |= DF_VAR_EDITED
	// A var with a registered setter is edited through it, so everything that reacts to the change
	// reacts to an admin's edit too (dx_conventions.md §1).
	// Only a registered setter (TRACKED or SETTER): a proc merely named set_<x> may be a verb or take
	// other arguments.
	if(hascall(src, "__setter_[var_name]"))
		call(src, "set_[var_name]")(var_value)
		return TRUE
	vars[var_name] = var_value // ALLOW(api): VV: admins edit any var by name
	changed(src)
	return TRUE

/datum/proc/vv_get_var(var_name)
	switch(var_name)
		if (NAMEOF(src, vars))
			return debug_variable(var_name, list(), 0, src)
	return debug_variable(var_name, vars[var_name], 0, src)

/**
 * Gets all the dropdown options in the vv menu.
 * When overriding, make sure to call . = ..() first and append to the result, that way parent items are always at the top and child items are further down.
 * Add separators by doing VV_DROPDOWN_OPTION("", "---")
 */
/datum/proc/vv_get_dropdown()
	SHOULD_CALL_PARENT(TRUE)

	. = list()
	VV_DROPDOWN_OPTION("", "---")
	VV_DROPDOWN_OPTION(VV_HK_CALLPROC, "Call Proc")
	VV_DROPDOWN_OPTION(VV_HK_MARK, "Mark Object")
	VV_DROPDOWN_OPTION(VV_HK_TAG, "Tag Datum")
	VV_DROPDOWN_OPTION(VV_HK_DELETE, "Delete")
	VV_DROPDOWN_OPTION(VV_HK_EXPOSE, "Show VV To Player")
	VV_DROPDOWN_OPTION(VV_HK_ADDCOMPONENT, "Attach OM Behaviour")
	VV_DROPDOWN_OPTION(VV_HK_REMOVECOMPONENT, "Detach OM Behaviour")
	VV_DROPDOWN_OPTION(VV_HK_MASS_REMOVECOMPONENT, "Mass Detach OM Behaviour")

// The dropdown's "high level" actions (admin heal, set species, ...) are topic_in(VV_TOPIC, key) ops on
// the type (code/__defines/vv.dm); the low level ones are the admin holder's ops in
// admin/view_variables/topic_basic.dm, in case the type's own code runtimes.

/datum/proc/vv_get_header()
	. = list()
	if(("name" in vars) && !isatom(src))
		. += span_bold("[vars["name"]]") + "<br>"

/datum/proc/on_reagent_change(changetype)
	return
