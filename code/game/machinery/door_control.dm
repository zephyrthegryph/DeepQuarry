/obj/machinery/button/remote
	name = "remote object control"
	desc = "It controls objects, remotely."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "doorctrl0"
	power_channel = ENVIRON
	layer = ABOVE_WINDOW_LAYER
	flags = WALL_ITEM
	var/desiredstate = 0
	var/exposedwires_num = 0
	var/wires_num = 3
	/*
	Bitflag,	1=checkID
				2=Network Access
	*/

	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 2
	active_power_usage = 4

/obj/machinery/button/remote/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/remote_toggle,
		/datum/interaction/machine_item/remote_toggle_item,
	)
	into += dq_interaction_from_spec(type, INTERACT_SILICON("Toggle", PROC_REF(remote_silicon_use)))
	..()

/// Old attack_ai: silicons press it as a hand would, when its network wire is intact.
/obj/machinery/button/remote/proc/remote_silicon_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(wires_num & 2)
		attack_hand(user)
	else
		to_chat(user, "Error, no route to host.")
	return TRUE

/// The old attack_hand, gated (it called ..()).
/datum/interaction/machine_hand/remote_toggle
	id = "remote_toggle"
	name = "Toggle"
	category = INTERACTION_CAT_TOGGLE
	also_requires = list(REQ_TARGET_STATE(/obj/machinery/button/remote/proc/can_press))
	effect = /obj/machinery/button/remote/proc/interaction_toggle

/// Requirement: TRUE, or why pressing the button does nothing (a spent single-use button).
/obj/machinery/button/remote/proc/can_press(mob/user, atom/target, obj/item/held)
	return TRUE

/// The old attackby: `return attack_hand(user)` for any item.
/datum/interaction/machine_item/remote_toggle_item
	id = "remote_toggle_item"
	name = "Toggle"
	category = INTERACTION_CAT_TOGGLE
	held_type = /obj/item
	also_requires = list(REQ_TARGET_STATE(/obj/machinery/button/remote/proc/can_press))
	effect = /obj/machinery/button/remote/proc/interaction_toggle

/**
 * The remote/driver subtype's own attackby replaced this one outright (no ..()),
 * restricting it to ID cards/PDAs; excluded here so driver instances don't also
 * offer this generic any-item version.
 */
/datum/interaction/machine_item/remote_toggle_item/applies_to(atom/target)
	return !istype(target, /obj/machinery/button/remote/driver)

/obj/machinery/button/remote/emag_act(remaining_charges, mob/user)
	if(LAZYLEN(req_access) || LAZYLEN(req_one_access))
		req_access = null
		req_one_access = null
		play_sfx(src, SFX_SPARKS, 2)
		return 1

/obj/machinery/button/remote/proc/interaction_toggle(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	if(!operable())
		return TRUE

	if(!allowed(user) && (wires_num & 1))
		to_chat(user, span_warning("Access Denied"))
		flick("doorctrl-denied",src)
		return TRUE

	use_power(5)
	icon_state = "doorctrl1"
	desiredstate = !desiredstate
	trigger(user)
	om_after_unique(src, 1.5 SECONDS, TYPE_PROC_REF(/atom, update_icon))
	return TRUE

/obj/machinery/button/remote/proc/trigger()
	return

/obj/machinery/button/remote/power_change()
	. = ..()
	update_icon()

/obj/machinery/button/remote/update_icon()
	if(has_stat(NOPOWER))
		icon_state = "doorctrl-p"
	else
		icon_state = "doorctrl0"

/*
	Airlock remote control
*/

// Bitmasks for door switches.
#define OPEN   0x1
#define IDSCAN 0x2
#define BOLTS  0x4
#define SHOCK  0x8
#define SAFE   0x10

/obj/machinery/button/remote/airlock
	icon = 'icons/obj/stationobjs.dmi'
	name = "remote door-control"
	desc = "It controls doors, remotely."

	var/specialfunctions = 1
	/*
	Bitflag, 	1= open
				2= idscan,
				4= bolts
				8= shock
				16= door safties
	*/

/obj/machinery/button/remote/airlock/trigger()
	for(var/obj/machinery/door/airlock/D in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(D.id_tag == id)
			if(specialfunctions & OPEN)
				if(D.density)
					D.open()
					continue
				D.close()
				continue

			if(desiredstate == 1)
				if(specialfunctions & IDSCAN)
					D.set_idscan(0)
				if(specialfunctions & BOLTS)
					D.lock()
				if(specialfunctions & SHOCK)
					D.electrify(-1)
				if(specialfunctions & SAFE)
					D.set_safeties(0)
				continue

			if(specialfunctions & IDSCAN)
				D.set_idscan(1)
			if(specialfunctions & BOLTS)
				D.unlock()
			if(specialfunctions & SHOCK)
				D.electrify(0)
			if(specialfunctions & SAFE)
				D.set_safeties(1)

#undef OPEN
#undef IDSCAN
#undef BOLTS
#undef SHOCK
#undef SAFE

/*
	Blast door remote control
*/
/obj/machinery/button/remote/blast_door
	icon = 'icons/obj/stationobjs.dmi'
	name = "remote blast door-control"
	desc = "It controls blast doors, remotely."

/obj/machinery/button/remote/blast_door/trigger()
	for(var/obj/machinery/door/blast/M in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(M.id == id)
			if(M.density)
				M.open()
			else
				M.close()


/obj/machinery/button/remote/blast_door/bear
	name = "stuffed bear"
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "stuffedbear"
	desc = "A stuffed and mounted bear. Quite a statement piece, but holds a curious glare."
	density = 1

/// Toggles like any remote button but keeps the bear's sprite.
/obj/machinery/button/remote/blast_door/bear/interaction_toggle(mob/user, obj/item/held, datum/interaction/interaction)
	. = ..()
	icon_state = "stuffedbear"

/obj/machinery/button/remote/blast_door/bear/update_icon()
	if(has_stat(NOPOWER))
		icon_state = "stuffedbear"
	else
		icon_state = "stuffedbear"


/*
	Emitter remote control
*/
/obj/machinery/button/remote/emitter
	name = "remote emitter control"
	desc = "It controls emitters, remotely."

/obj/machinery/button/remote/emitter/trigger(mob/user as mob)
	for(var/obj/machinery/power/emitter/E in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(E.id == id)
			E.activate(user)

/*
	Mass driver remote control
*/
/obj/machinery/button/remote/driver
	name = "mass driver button"
	desc = "A remote control switch for a mass driver."
	icon = 'icons/obj/objects.dmi'
	icon_state = "launcherbtt"
	circuit = /obj/item/circuitboard/mass_driver_button

/obj/machinery/button/remote/driver/trigger(mob/user)
	if(active)
		return
	set_active(TRUE)
	update_icon()

	for(var/obj/machinery/door/blast/M in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(M.id == id)
			M.open()
	om_after_unique(src, 2 SECONDS, PROC_REF(trigger_step_one))

/obj/machinery/button/remote/driver/proc/trigger_step_one()
	PRIVATE_PROC(TRUE)
	for(var/obj/machinery/mass_driver/M in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(M.id == id)
			M.drive()
	om_after_unique(src, 5 SECONDS, PROC_REF(trigger_step_two))

/obj/machinery/button/remote/driver/proc/trigger_step_two()
	PRIVATE_PROC(TRUE)

	for(var/obj/machinery/door/blast/M in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(M.id == id)
			M.close()

	set_active(FALSE)
	update_icon()

/obj/machinery/button/remote/driver/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/remote_driver_id_swipe,
	)
	..()

/// The old attackby: replaced the base's any-item forward with an ID/PDA-only one.
/datum/interaction/machine_item/remote_driver_id_swipe
	id = "remote_driver_id_swipe"
	name = "Swipe ID"
	category = INTERACTION_CAT_TOGGLE
	held_type = list(/obj/item/card/id, /obj/item/pda)
	also_requires = list(REQ_TARGET_STATE(/obj/machinery/button/remote/proc/can_press))
	effect = /obj/machinery/button/remote/proc/interaction_toggle

/obj/machinery/button/remote/driver/multitool_act(mob/user, obj/item/tool)
	om_ask(user, /datum/om/prompt/number, PROC_REF(driver_id_entered), message = "[src] has an id of \"[id]\". What would you like it to be?", title = "[src] ID]", default = id, max = 9999, requires = PROMPT_ADJACENT)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/button/remote/driver/proc/driver_id_entered(datum/om/prompt/number/ask)
	var/new_id = ask.number
	if(new_id)
		id = new_id
	return ITEM_INTERACT_SUCCESS

/obj/machinery/button/remote/driver/update_icon()
	if(!active || (has_stat(NOPOWER)))
		icon_state = "launcherbtt"
	else
		icon_state = "launcheract"

/*
	Shieldgen remote control
*/
/obj/machinery/button/remote/shields
	name = "remote shield control"
	desc = "It controls shields, remotely."
	icon = 'icons/obj/stationobjs.dmi'

/obj/machinery/button/remote/shields/trigger(mob/user)
	for(var/obj/machinery/shield_gen/SG in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(SG.id == id)
			if(SG?.anchored)
				SG.toggle()

/obj/machinery/button/remote/airlock/release
	icon = 'icons/obj/door_release.dmi'
	name = "emergency door release"
	desc = "Forces the opening of doors in an emergency, regardless of whether they're powered."

	use_power = USE_POWER_OFF
	idle_power_usage = 0
	active_power_usage = 0

/obj/machinery/button/remote/airlock/release/trigger()
	for(var/obj/machinery/door/airlock/D in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(D.id_tag == id)
			if(D.locked)
				D.unlock(1)
			if(D.density)
				D.open(1)

/obj/machinery/button/remote/airlock/release/powered()
	return 1 //Is always able to be used


/obj/machinery/button/remote/blast_door/single_use
	name = "single use button"
	var/has_been_pressed = FALSE

/obj/machinery/button/remote/blast_door/single_use/can_press(mob/user, atom/target, obj/item/held)
	if(has_been_pressed)
		return "nothing happens"
	return ..()

/obj/machinery/button/remote/blast_door/single_use/trigger()
	has_been_pressed = TRUE
	update_icon()
	..()


/obj/machinery/button/remote/blast_door/single_use/slab
	name = "Button Slab Parent"
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "slab1-off"
	use_power = USE_POWER_OFF
	/// The sprite once pressed.
	var/pressed_state = "slab1"

/obj/machinery/button/remote/blast_door/single_use/slab/interaction_toggle(mob/user, obj/item/held, datum/interaction/interaction)
	. = ..()
	to_chat(user,span_notice("You hear a heavy mechanism open somewhere in the distance."))
	icon_state = pressed_state

/obj/machinery/button/remote/blast_door/single_use/slab/update_icon()
	return

/obj/machinery/button/remote/blast_door/single_use/slab/slab1
	name = "Button Slab 1"
	icon_state = "slab1-off"
	pressed_state = "slab1"

/obj/machinery/button/remote/blast_door/single_use/slab/slab2
	name = "Button Slab 2"
	icon_state = "slab2-off"
	pressed_state = "slab2"

/obj/machinery/button/remote/blast_door/single_use/slab/slab3
	name = "Button Slab 3"
	icon_state = "slab3-off"
	pressed_state = "slab3"

/obj/machinery/button/remote/blast_door/single_use/slab/slab4
	name = "Button Slab 4"
	icon_state = "slab4-off"
	pressed_state = "slab4"
