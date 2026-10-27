//The UI portion. Should probably be made its own thing/made into a NanoUI thing later.
/datum/system/events
	var/report_at_round_end = 0
	var/tmp/datum/event_container/selected_event_container

/datum/system/events/proc/Interact(mob/living/user)
	// structured TGUI Event Manager panel (see
	// code/modules/admin/event_manager_panel.dm). Re-uses
	// the per-subsystem panel datum so a second open just updates the
	// open window via SStgui.update_uis instead of opening a duplicate.
	if(!tgui_event_manager_panel)
		rel_set(src, nameof(tgui_event_manager_panel), new /datum/event_manager_panel)
	tgui_event_manager_panel.tgui_interact(user)
	SStgui.update_uis(tgui_event_manager_panel)

ADMIN_VERB(forceEvent, R_DEBUG, "Trigger Event (Debug Only)", "Immediately triggers an event.", ADMIN_CATEGORY_DEBUG_DANGEROUS, type in SSevents.allEvents)
	if(!ispath(type))
		return
	new type(new /datum/event_meta(EVENT_LEVEL_MAJOR))
	message_admins("[key_name_admin(user)] has triggered an event. ([type])")

ADMIN_VERB(event_manager_panel, R_ADMIN|R_EVENT, "Event Manager Panel", "Opens the event manager panel.", ADMIN_CATEGORY_EVENTS)
	SSevents.Interact(user)
	feedback_add_details("admin_verb","EMP") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

/// Accessor for the selected_event_container var.
/datum/system/events/proc/selected_event_container() as /datum/event_container
	return selected_event_container
