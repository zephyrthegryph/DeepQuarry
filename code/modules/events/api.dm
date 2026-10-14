/datum/system/events/proc/enable_round_end_report()
	report_at_round_end = TRUE

/// Release only the panel that currently belongs to this service.
/datum/system/events/proc/forget_manager_panel(datum/event_manager_panel/panel)
	if(tgui_event_manager_panel == panel)
		rel_clear(src, nameof(tgui_event_manager_panel))
