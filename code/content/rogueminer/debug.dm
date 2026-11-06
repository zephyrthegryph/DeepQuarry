/client/proc/debug_rogueminer()
	set category = VERB_CAT_DEBUG
	set name = "Debug RogueMiner"
	set desc = "Debug the RogueMiner controller."

	if(!check_rights_for(src, R_HOLDER))	return
	debug_variables(GLOB.rm_controller)
	feedback_add_details("admin_verb","DRM")
