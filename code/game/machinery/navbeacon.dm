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

// ALLOW(init/INSTANCE_STATE): hides under the floor tile it is placed on
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
	changed(src)

// update the icon_state
/// The look (the draw sweep: from its template).
/obj/machinery/navbeacon/draw(datum/look/look)
	..()
	look.state("navbeacon[open][invisibility ? "-f" : ""]")

/obj/machinery/navbeacon/proc/interaction_toggle_lock(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/held = A.held
	var/turf/T = loc
	if(!T.is_plating())
		return OP_OK		// prevent intraction when T-scanner revealed
	if(held.GetID())
		togglelock(user)
	return OP_OK

/obj/machinery/navbeacon/proc/actor_has_dexterity(mob/actor, atom/target, obj/item/held)
	return actor.IsAdvancedToolUser()

/obj/machinery/navbeacon/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	var/turf/floor = loc
	if(!floor.is_plating())
		return OP_OK
	open = !open
	playsound(src, tool.usesound, 50, TRUE)
	act_message(user, null, MSG_SELF(span_infoplain("You [open ? "open" : "close"] the beacon's cover.")), \
		MSG_OTHERS(span_notice("%U% [open ? "opens" : "closes"] the beacon's cover.")))
	return OP_OK

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

CAPABILITIES(/obj/machinery/navbeacon)
	silicon_ui()
	interface("NavBeacon")
	op("lock", ui_act("lock"), then(PROC_REF(ui_act_lock)))
	op("loc_edit", ui_act("loc_edit", arg("new_loc", schema_text(4096))), then(PROC_REF(ui_act_loc_edit)))
	op("trans_edit_key", ui_act("trans_edit_key", arg("code", schema_text(4096)), arg("new_key", schema_text(4096))), then(PROC_REF(ui_act_trans_edit_key)))
	op("trans_edit_code", ui_act("trans_edit_code", arg("code", schema_text(4096)), arg("new_val", schema_text(4096))), then(PROC_REF(ui_act_trans_edit_code)))
	op("trans_add_code", ui_act("trans_add_code", arg("new_key", schema_text(4096)), arg("new_val", schema_text(4096))), then(PROC_REF(ui_act_trans_add_code)))
	op("trans_del", ui_act("trans_del", arg("code", schema_text(4096))), then(PROC_REF(ui_act_trans_del)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(screwdriver_used)))
	op("toggle_lock", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Swipe ID"), then(PROC_REF(interaction_toggle_lock)))

/obj/machinery/navbeacon/ui_prepare(mob/user, datum/tgui/ui)
	var/turf/T = loc
	if(!T.is_plating())
		return FALSE

	if(!open && !isAI(user))	// can't alter controls if not open, unless you're an AI
		to_chat(user, span_warning("The beacon's control cover is closed."))
		return FALSE

	return TRUE

/obj/machinery/navbeacon/ui_data(datum/act/eval/A)
	var/mob/user = A.actor

	return list(
		"siliconUser" = !!(A.authority & AUTH_REMOTE_ACCESS),
		"locked" = locked,
		"open" = open,
		"location" = location,
		"codes" = (codes || list()),
	)

/obj/machinery/navbeacon/proc/ui_act_lock(datum/act/op/A)
	var/mob/user = A.actor
	if(!open)
		return
	return togglelock(user)

/obj/machinery/navbeacon/proc/ui_act_loc_edit(datum/act/op/A, raw_new_loc)
	if(!open || locked)
		return FALSE
	var/new_loc = sanitize(raw_new_loc, MAX_NAME_LEN)
	if(!new_loc)
		return FALSE
	location = new_loc
	return TRUE

/obj/machinery/navbeacon/proc/ui_act_trans_edit_key(datum/act/op/A, code, raw_new_key)
	if(!open || locked)
		return FALSE
	var/codekey = code
	if(!codekey || !(codekey in codes))
		return FALSE
	var/new_key = sanitize(raw_new_key, MAX_NAME_LEN)
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

/obj/machinery/navbeacon/proc/ui_act_trans_edit_code(datum/act/op/A, code, raw_new_val)
	if(!open || locked)
		return FALSE
	var/codekey = code
	if(!codekey)
		return FALSE
	var/new_val = sanitize(raw_new_val, MAX_NAME_LEN)
	if(!new_val)
		return FALSE
	LAZYSET(codes, codekey, new_val)
	return TRUE

/obj/machinery/navbeacon/proc/ui_act_trans_add_code(datum/act/op/A, raw_new_key, raw_new_val)
	if(!open || locked)
		return FALSE
	var/new_key = sanitize(raw_new_key, MAX_NAME_LEN)
	if(!new_key)
		return FALSE
	if(LAZYACCESS(codes, new_key))
		return FALSE
	var/new_val = sanitize(raw_new_val, MAX_NAME_LEN)
	if(!new_val)
		return FALSE
	LAZYSET(codes, new_key, new_val)
	return TRUE

/obj/machinery/navbeacon/proc/ui_act_trans_del(datum/act/op/A, code)
	if(!open || locked)
		return FALSE
	var/codekey = code
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

// ALLOW(init/INSTANCE_STATE): its patrol codes come from the next stop the map gave it
/obj/machinery/navbeacon/patrol/Initialize(mapload)
	codes = list("patrol" = 1, "next_patrol" = next_patrol)
	. = ..()
