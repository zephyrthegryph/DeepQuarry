ADMIN_VERB(spawn_panel, R_SPAWN, "Spawn Panel", "Spawn Panel (TGUI).", ADMIN_CATEGORY_GAME)
	var/datum/spawnpanel/panel = user.holder.spawn_panel
	if(!panel)
		panel = rel_set(user.admin_datum(), nameof(/datum/admins::spawn_panel), new /datum/spawnpanel())
	panel.tgui_interact(user.mob)
	feedback_add_details("admin_verb","SP") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB_AND_CONTEXT_MENU(machine_access_check, R_DEBUG, "Check Access List", "Read and edit the access list of a machine.", ADMIN_CATEGORY_GAME, obj/machinery/req_thing in world)
	var/datum/access_viewer/panel = user.holder.access_view_menu
	if(!panel)
		panel = rel_set(user.admin_datum(), nameof(/datum/admins::access_view_menu), new /datum/access_viewer())
	panel.set_access_focus(req_thing)
	panel.tgui_interact(user.mob)
	feedback_add_details("admin_verb","SR") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
