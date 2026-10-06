// Exonet message log viewer (ghost) — structured TGUI.

/mob/observer/dead
	var/datum/exonet_log_panel/dq_exonet_log_panel_cache

CAPABILITIES(/mob/observer/dead)
	owns_one(nameof(dq_exonet_log_panel_cache), /datum/exonet_log_panel)
	owns_one(nameof(exonet), /datum/exonet_protocol, starts = /datum/exonet_protocol)
	op("observer_tome_manifest", item(/obj/item/book/tome), label("Manifest"), then(PROC_REF(observer_tome_manifest)))
	drag_onto(PROC_REF(drop_input))
	param(nameof(admin_ghosted), pos = 1)

/datum/exonet_log_panel
	var/tmp/mob/observer/dead/host

/datum/exonet_log_panel/New(mob/observer/dead/host_mob)
	rel_set(src, nameof(host), host_mob)

/// Phase 2: its host's panel cache lets go.
/datum/exonet_log_panel/lifecycle_dematerialize()
	. = ..()
	if(host()?.dq_exonet_log_panel_cache == src)
		host().dq_exonet_log_panel_cache = null

CAPABILITIES(/datum/exonet_log_panel)
	interface("ExonetLog", title = "Exonet Message Log", state = nameof(GLOB.tgui_always_state))
	ui_shape(lines = any)

/datum/exonet_log_panel/ui_prepare(mob/user, datum/tgui/ui)
	if(!host() || user != host())
		return FALSE
	return TRUE

/// /datum/exonet_log_panel's window data.
/datum/exonet_log_panel/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["lines"] = host() ? (host().exonet_messages ? host().exonet_messages.Copy() : list()) : list()
	return data

// Show Text Messages verb now opens a structured TGUI panel.
/mob/observer/dead/verb/show_text_messages()
	set category = VERB_CAT_GHOST_SETTINGS
	set name = "Show Text Messages"
	set desc = "Allows you to see exonet text messages you've sent and received."
	if(!dq_exonet_log_panel_cache)
		rel_set(src, nameof(dq_exonet_log_panel_cache), new /datum/exonet_log_panel(src))
	dq_exonet_log_panel_cache.tgui_interact(src)


/// The host this refers to (a relation view: null once that is deleted).
/datum/exonet_log_panel/proc/host() as /mob/observer/dead
	return host
