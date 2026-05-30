// Exonet message log viewer (ghost) — structured TGUI.

/mob/observer/dead
	var/datum/exonet_log_panel/dq_exonet_log_panel_cache

/datum/exonet_log_panel
	var/mob/observer/dead/host

/datum/exonet_log_panel/New(mob/observer/dead/host_mob)
	host = host_mob

/datum/exonet_log_panel/Destroy(force, ...)
	if(host)
		host.dq_exonet_log_panel_cache = null
	host = null
	return ..()

/datum/exonet_log_panel/tgui_state(mob/user)
	return GLOB.tgui_always_state

/datum/exonet_log_panel/tgui_interact(mob/user, datum/tgui/ui)
	if(!host || user != host)
		return
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "ExonetLog", "Exonet Message Log")
		ui.open()

/datum/exonet_log_panel/tgui_data(mob/user)
	var/list/data = list()
	data["lines"] = host ? (host.exonet_messages ? host.exonet_messages.Copy() : list()) : list()
	return data

// DQEdit Start — Show Text Messages verb now opens a structured TGUI panel.
/mob/observer/dead/verb/show_text_messages()
	set category = "Ghost.Settings"
	set name = "Show Text Messages"
	set desc = "Allows you to see exonet text messages you've sent and received."
	if(!dq_exonet_log_panel_cache)
		dq_exonet_log_panel_cache = new(src)
	dq_exonet_log_panel_cache.tgui_interact(src)
// DQEdit End
