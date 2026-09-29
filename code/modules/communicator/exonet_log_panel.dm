// Exonet message log viewer (ghost) — structured TGUI.

/mob/observer/dead
	var/datum/exonet_log_panel/dq_exonet_log_panel_cache

/datum/exonet_log_panel
	var/tmp/host_handle

/datum/exonet_log_panel/New(mob/observer/dead/host_mob)
	host_handle = om_handle(host_mob)

/// Phase 2: its host's panel cache lets go.
/datum/exonet_log_panel/lifecycle_dematerialize()
	. = ..()
	if(host()?.dq_exonet_log_panel_cache == src)
		host().dq_exonet_log_panel_cache = null

DECLARE_UI_STATE(/datum/exonet_log_panel, GLOB.tgui_always_state)

DECLARE_UI(/datum/exonet_log_panel, "ExonetLog", UI_TITLE("Exonet Message Log"))

/datum/exonet_log_panel/ui_prepare(mob/user, datum/tgui/ui)
	if(!host() || user != host())
		return FALSE
	return TRUE

UI_DATA_REPLACE(/datum/exonet_log_panel, "merge:ui_data_datum_exonet_log_panel{lines:unknown}")

/// The computed part of /datum/exonet_log_panel's window data (declared on its UI_DATA row).
/datum/exonet_log_panel/proc/ui_data_datum_exonet_log_panel(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["lines"] = host() ? (host().exonet_messages ? host().exonet_messages.Copy() : list()) : list()
	return data

// Show Text Messages verb now opens a structured TGUI panel.
/mob/observer/dead/verb/show_text_messages()
	set category = "Ghost.Settings"
	set name = "Show Text Messages"
	set desc = "Allows you to see exonet text messages you've sent and received."
	if(!dq_exonet_log_panel_cache)
		dq_exonet_log_panel_cache = new(src)
	dq_exonet_log_panel_cache.tgui_interact(src)

DECLARE_REF(/mob/observer/dead, "dq_exonet_log_panel_cache", OWNED, null)

/// LC-refs: the host this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/exonet_log_panel/proc/host() as /mob/observer/dead
	return om_resolve(host_handle)
