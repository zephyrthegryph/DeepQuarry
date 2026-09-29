/**
 * ## Loot panel
 * A datum that stores info containing the contents of a turf.
 * Handles opening the lootpanel UI and searching the turf for items.
 */
/datum/lootpanel
	/// The owner of the panel
	var/tmp/owner_handle
	/// The list of all search objects indexed.
	var/list/datum/search_object/searchables = list() // ALLOW(instance_list): d: loot panel state
	/// The list of search_objects needing processed
	var/list/datum/search_object/to_image
	/// We've been notified about client version
	var/notified = FALSE
	/// The turf being searched
	var/tmp/source_turf_handle

/datum/lootpanel/New(client/owner)
	. = ..()

	src.owner_handle = om_handle(owner)

// its searched contents are reset.
/datum/lootpanel/on_destroy(force)
	reset_contents()
	..()

DECLARE_UI(/datum/lootpanel, "LootPanel")

/datum/lootpanel/tgui_close(mob/user)
	. = ..()

	source_turf_handle = null
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

/// LC-refs: the source_turf this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/lootpanel/proc/source_turf() as /turf
	return om_resolve(source_turf_handle)

/// LC-refs: the owner this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/lootpanel/proc/owner() as /client
	return om_resolve(owner_handle)

DECLARE_REF(/datum/lootpanel, "searchables", OWNED_LIST, null)
DECLARE_REF(/datum/lootpanel, "to_image", OWNED_LIST, null)
DECLARE_REF(/datum/lootpanel, "contents", OWNED_LIST, null)
