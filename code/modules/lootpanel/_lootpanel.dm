/**
 * ## Loot panel
 * A datum that stores info containing the contents of a turf.
 * Handles opening the lootpanel UI and searching the turf for items.
 */
/datum/lootpanel
	/// The owner of the panel
	var/tmp/client/owner
	/// The list of all search objects indexed (owned).
	var/list/datum/search_object/searchables = list() // ALLOW(instance_list): the search results are live per-panel state: always in use, so a lazy list saves nothing
	/// The search_objects needing processed (a relation list: searchables owns them)
	var/list/datum/search_object/to_image
	/// We've been notified about client version
	var/notified = FALSE
	/// The turf being searched
	var/tmp/turf/source_turf

CAPABILITIES(/datum/lootpanel)
	owns_many(nameof(searchables), /datum/search_object)
	interface("LootPanel")
	op("refresh", ui_act("refresh"), then(PROC_REF(ui_act_refresh)))
	op("grab", ui_act("grab", arg("ref", schema_ref(/datum/search_object)), arg("ctrl", bool()), arg("middle", bool()), arg("shift", bool()), arg("alt", bool()), arg("right", bool())), then(PROC_REF(ui_act_grab)))

/datum/lootpanel/New(client/owner)
	. = ..()

	rel_set(src, nameof(owner), owner)

// its searched contents are reset.
/datum/lootpanel/on_destroy(force)
	reset_contents()
	..()

/datum/lootpanel/tgui_close(mob/user)
	. = ..()

	rel_clear(src, nameof(source_turf))
	reset_contents()

/// /datum/lootpanel's window data.
/datum/lootpanel/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
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

/datum/lootpanel/proc/ui_act_refresh(datum/act/op/A)
	return populate_contents()

/// The source_turf this refers to (a relation view: null once that is deleted).
/datum/lootpanel/proc/source_turf() as /turf
	return source_turf

/// The owner this refers to (a relation view: null once that is deleted).
/datum/lootpanel/proc/owner() as /client
	return owner

