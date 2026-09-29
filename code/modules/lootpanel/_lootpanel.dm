/**
 * ## Loot panel
 * A datum that stores info containing the contents of a turf.
 * Handles opening the lootpanel UI and searching the turf for items.
 */
/datum/lootpanel
	/// The owner of the panel
	var/tmp/client/owner
	/// The list of all search objects indexed (owned).
	var/list/datum/search_object/searchables = list() // ALLOW(instance_list): d: loot panel state
	/// The search_objects needing processed (a relation list: searchables owns them)
	var/list/datum/search_object/to_image
	/// We've been notified about client version
	var/notified = FALSE
	/// The turf being searched
	var/tmp/turf/source_turf

/datum/lootpanel/New(client/owner)
	. = ..()

	rel_set(src, "owner", owner)

// its searched contents are reset.
/datum/lootpanel/on_destroy(force)
	reset_contents()
	..()

DECLARE_UI(/datum/lootpanel, "LootPanel")

/datum/lootpanel/tgui_close(mob/user)
	. = ..()

	rel_clear(src, "source_turf")
	reset_contents()

UI_DATA_REPLACE(/datum/lootpanel, "merge:ui_data_datum_lootpanel{contents:unknown,is_blind:bool,searching:num}")

/// The computed part of /datum/lootpanel's window data (declared on its UI_DATA row).
/datum/lootpanel/proc/ui_data_datum_lootpanel(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	data["contents"] = get_contents()
	data["is_blind"] = !!user.is_blind()
	data["searching"] = length(to_image)

	return data

/datum/lootpanel/tgui_status(mob/user, datum/tgui_state/state)
	// note: different from /tg/, we prohibit non-viewers from trying to update the window and close it automatically for them
	if(!(user in viewers(source_turf())))
		return STATUS_CLOSE

	if(user.incapacitated())
		return STATUS_DISABLED

	return STATUS_INTERACTIVE

UI_ACT(/datum/lootpanel, "refresh", ui_act_refresh)
UI_ACT_PROC(/datum/lootpanel, ui_act_refresh)
	return populate_contents()

/// The source_turf this refers to (a relation view: null once that is deleted).
/datum/lootpanel/proc/source_turf() as /turf
	return source_turf

/// The owner this refers to (a relation view: null once that is deleted).
/datum/lootpanel/proc/owner() as /client
	return owner

