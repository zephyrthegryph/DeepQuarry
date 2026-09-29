// Navigation beacon for AI robots
// Functions as a transponder: looks for incoming signal matching

/obj/machinery/navbeacon
	icon = 'icons/obj/objects.dmi'
	icon_state = "navbeacon0-f"
	name = "navigation beacon"
	desc = "A beacon used for bot navigation."
	plane = PLATING_PLANE
	anchored = TRUE
	var/open = FALSE		// true if cover is open
	locked = TRUE		// true if controls are locked
	var/location = ""	// location response text
	var/list/codes	// assoc. list of transponder codes
	req_access = list(ACCESS_ENGINE)

REGISTRY_MEMBERSHIP(/obj/machinery/navbeacon, REGISTRY_NAVBEACONS)

/obj/machinery/navbeacon/Initialize(mapload)
	. = ..()
	var/turf/T = loc
	hide(!T.is_plating())

/obj/machinery/navbeacon/hides_under_flooring()
	return 1

// called when turf state changes
// hide the object if turf is intact
/obj/machinery/navbeacon/hide(intact)
	invisibility = intact ? INVISIBILITY_ABSTRACT : INVISIBILITY_NONE
	update_icon()

// update the icon_state
APPEARANCE_TEMPLATE(/obj/machinery/navbeacon, "navbeacon{open}{invisibility?-f:}")

/obj/machinery/navbeacon/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/navbeacon_toggle_lock,
		/datum/interaction/machine_hand/ungated/navbeacon_use,
	)
	..()

/// Old attackby: swipe an ID to toggle the lock. Never fell through to ..(), so the whole thing stays inside the effect.
/datum/interaction/machine_item/navbeacon_toggle_lock
	id = "navbeacon_toggle_lock"
	name = "Swipe ID"
	effect = /obj/machinery/navbeacon/proc/interaction_toggle_lock

/obj/machinery/navbeacon/proc/interaction_toggle_lock(mob/user, obj/item/held, datum/interaction/interaction)
	var/turf/T = loc
	if(!T.is_plating())
		return TRUE		// prevent intraction when T-scanner revealed
	if(held.GetID())
		togglelock(user)
	return TRUE

/// Old attack_hand: never called ..(), so ungated.
/datum/interaction/machine_hand/ungated/navbeacon_use
	id = "navbeacon_use"
	name = "Use"
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_ACTOR, /obj/machinery/navbeacon/proc/actor_has_dexterity, "you don't have the dexterity"))
	effect = /atom/proc/interaction_open_ui

/obj/machinery/navbeacon/proc/actor_has_dexterity(mob/actor, atom/target, obj/item/held)
	return actor.IsAdvancedToolUser()

/obj/machinery/navbeacon/screwdriver_act(mob/user, obj/item/tool)
	var/turf/floor = loc
	if(!floor.is_plating())
		return ITEM_INTERACT_BLOCKING
	open = !open
	playsound(src, tool.usesound, 50, TRUE)
	act_message(user, null, MSG_SELF(span_infoplain("You [open ? "open" : "close"] the beacon's cover.")), \
		MSG_OTHERS(span_notice("%U% [open ? "opens" : "closes"] the beacon's cover.")))
	update_icon()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/navbeacon
	silicon_use = SILICON_USE_UI

/obj/machinery/navbeacon/proc/togglelock(mob/user)
	if(!open)
		to_chat(user, span_warning("You must open the cover first!"))
		return FALSE

	if(allowed(user))
		set_locked(!locked)
		to_chat(user, span_notice("Controls are now [locked ? "locked." : "unlocked."]"))
		return TRUE

	to_chat(user, span_warning("Access denied."))
	return FALSE

DECLARE_UI(/obj/machinery/navbeacon, "NavBeacon")

/obj/machinery/navbeacon/ui_prepare(mob/user, datum/tgui/ui)
	var/turf/T = loc
	if(!T.is_plating())
		return FALSE

	if(!open && !isAI(user))	// can't alter controls if not open, unless you're an AI
		to_chat(user, span_warning("The beacon's control cover is closed."))
		return FALSE

	return TRUE

UI_DATA_REPLACE(/obj/machinery/navbeacon, "merge:ui_data_obj_machinery_navbeacon{siliconUser:num,locked:num,open:num,location:text,codes:bool}")

/// The computed part of /obj/machinery/navbeacon's window data (declared on its UI_DATA row).
/obj/machinery/navbeacon/proc/ui_data_obj_machinery_navbeacon(mob/user, datum/tgui/ui, datum/tgui_state/state)

	return list(
		"siliconUser" = issilicon(user),
		"locked" = locked,
		"open" = open,
		"location" = location,
		"codes" = (codes || list()),
	)

UI_ACT(/obj/machinery/navbeacon, "lock", ui_act_lock)
UI_ACT_PROC(/obj/machinery/navbeacon, ui_act_lock)
	if(!open)
		return
	return togglelock(ui.user)

UI_ACT(/obj/machinery/navbeacon, "loc_edit", ui_act_loc_edit, UI_ARG_TEXT("new_loc"))
UI_ACT_PROC(/obj/machinery/navbeacon, ui_act_loc_edit)
	if(!open || locked)
		return FALSE
	var/new_loc = sanitize(params["new_loc"], MAX_NAME_LEN)
	if(!new_loc)
		return FALSE
	location = new_loc
	return TRUE

UI_ACT(/obj/machinery/navbeacon, "trans_edit_key", ui_act_trans_edit_key, UI_ARG_TEXT("code"), UI_ARG_TEXT("new_key"))
UI_ACT_PROC(/obj/machinery/navbeacon, ui_act_trans_edit_key)
	if(!open || locked)
		return FALSE
	var/codekey = params["code"]
	if(!codekey || !(codekey in codes))
		return FALSE
	var/new_key = sanitize(params["new_key"], MAX_NAME_LEN)
	if(!new_key)
		return FALSE
	var/list/new_codes = list()
	for(var/key, value in codes)
		if(key == codekey)
			new_codes[new_key] = value
			continue
		new_codes[key] = value
	codes = new_codes
	return TRUE

UI_ACT(/obj/machinery/navbeacon, "trans_edit_code", ui_act_trans_edit_code, UI_ARG_TEXT("code"), UI_ARG_TEXT("new_val"))
UI_ACT_PROC(/obj/machinery/navbeacon, ui_act_trans_edit_code)
	if(!open || locked)
		return FALSE
	var/codekey = params["code"]
	if(!codekey)
		return FALSE
	var/new_val = sanitize(params["new_val"], MAX_NAME_LEN)
	if(!new_val)
		return FALSE
	LAZYSET(codes, codekey, new_val)
	return TRUE

UI_ACT(/obj/machinery/navbeacon, "trans_add_code", ui_act_trans_add_code, UI_ARG_TEXT("new_key"), UI_ARG_TEXT("new_val"))
UI_ACT_PROC(/obj/machinery/navbeacon, ui_act_trans_add_code)
	if(!open || locked)
		return FALSE
	var/new_key = sanitize(params["new_key"], MAX_NAME_LEN)
	if(!new_key)
		return FALSE
	if(LAZYACCESS(codes, new_key))
		return FALSE
	var/new_val = sanitize(params["new_val"], MAX_NAME_LEN)
	if(!new_val)
		return FALSE
	LAZYSET(codes, new_key, new_val)
	return TRUE

UI_ACT(/obj/machinery/navbeacon, "trans_del", ui_act_trans_del, UI_ARG_TEXT("code"))
UI_ACT_PROC(/obj/machinery/navbeacon, ui_act_trans_del)
	if(!open || locked)
		return FALSE
	var/codekey = params["code"]
	if(!codekey)
		return FALSE
	LAZYREMOVE(codes, codekey)
	return TRUE


//
// Nav Beacon Mapping
// These subtypes are what you should actually put into maps! they will make your life much easier.
//
// Developer Note: navbeacons do not HAVE to use these subtypes.  They are purely for mapping convenience.
// You can feel free to construct them in-game as just /obj/machinery/navbeacon and they will work just
// fine, and you can define your own specific types for every instance on map if you want (BayStation does)
// This design is a compromise that means you can do mapping without every single one being its own type
// but with it still being easy to map ~ Leshana
//

// Mulebot delivery destinations

/obj/machinery/navbeacon/delivery/north
	codes = list("delivery" = 1, "dir" = NORTH)

/obj/machinery/navbeacon/delivery/south
	codes = list("delivery" = 1, "dir" = SOUTH)

/obj/machinery/navbeacon/delivery/east
	codes = list("delivery" = 1, "dir" = EAST)

/obj/machinery/navbeacon/delivery/west
	codes = list("delivery" = 1, "dir" = WEST)

// For part of the patrol route
// You MUST set "location"
// You MUST set "next_patrol"
/obj/machinery/navbeacon/patrol
	var/next_patrol

/obj/machinery/navbeacon/patrol/Initialize(mapload)
	codes = list("patrol" = 1, "next_patrol" = next_patrol)
	. = ..()
