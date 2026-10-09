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

// ---- what a remote button is, declared ----
//
// A switch that works something at a distance: the hand that presses it (by the machinery's hand gate), any thing held (an ID or a PDA only, for
// the mass driver's), a silicon at any range when its network wire is whole. An access lock keeps out whoever has no access (with the check
// wire whole), a sequencer scorches the lock off, and a single use one is spent once pressed. What each kind works is its trigger().

MSG_DEF_SELF(button/denied, "Access Denied")
MSG_DEF_SELF(button/dead, "It has no power.")
MSG_DEF_SELF(button/spent, "Nothing happens.")
MSG_DEF_SELF(button/no_route, "Error, no route to host.")
MSG_DEF_SELF(button/no_lock, "It has no lock to subvert.")

CAPABILITIES(/obj/machinery/button/remote)
	emag(then(PROC_REF(lock_scorched)), repeatable = TRUE)
	extend("emag.use", needs(req_bool(PROC_REF(has_access_lock), because = MSG(button/no_lock))))
	extend("emag.subvert", needs(req_bool(PROC_REF(has_access_lock), because = MSG(button/no_lock))))
	op("press_hand", hand(), label("Toggle"), wait(0),
		needs(req_bool(PROC_REF(hand_ok), because = PROC_REF(hand_refusal)), req_bool(PROC_REF(can_press), because = MSG(button/spent)), req_bool(PROC_REF(may_press), because = MSG(button/denied))), then(PROC_REF(pressed)))
	op("press_item", item(/obj/item), label("Toggle"), when(req_bool(PROC_REF(item_presses))), priority(OP_PRIORITY_NORMAL + 1), wait(0),
		needs(req_bool(PROC_REF(button_works), because = MSG(button/dead)), req_bool(PROC_REF(can_press), because = MSG(button/spent)), req_bool(PROC_REF(may_press), because = MSG(button/denied))), then(PROC_REF(pressed)))
	op("press_silicon", ai(), wait(0),
		needs(req_bool(PROC_REF(has_network), because = MSG(button/no_route)), req_bool(PROC_REF(hand_ok), because = PROC_REF(hand_refusal)), req_bool(PROC_REF(can_press), because = MSG(button/spent)), req_bool(PROC_REF(may_press), because = MSG(button/denied))), then(PROC_REF(pressed)))
	on_op("press_hand", then(PROC_REF(denied_flash)), outcome = ACT_REFUSED)
	on_op("press_item", then(PROC_REF(denied_flash)), outcome = ACT_REFUSED)
	on_op("press_silicon", then(PROC_REF(denied_flash)), outcome = ACT_REFUSED)
	op("silicon_pressed", remote(), priority(OP_PRIORITY_DEFAULT - 1), label("Toggle"), then(PROC_REF(silicon_pressed)))

/// A silicon presses it from wherever it can see it (the same press as a hand's).
/obj/machinery/button/remote/proc/silicon_pressed(datum/act/op/A)
	var/mob/user = A.actor
	perform_op(user, src, "press_silicon", origin = ORIGIN_SYSTEM)
	return TRUE

/// Any held thing presses it (the mass driver's takes only an ID or a PDA).
/obj/machinery/button/remote/proc/item_presses(datum/act/op/A)
	return TRUE

/// Not spent (a single use button is, once pressed).
/obj/machinery/button/remote/proc/can_press(datum/act/A)
	return TRUE

/// It works at all (it has power and is not broken).
/obj/machinery/button/remote/proc/button_works(datum/act/A)
	return operable()

/// Its network wire is whole (a silicon cannot reach it otherwise).
/obj/machinery/button/remote/proc/has_network(datum/act/A)
	return !!(wires_num & 2)

/// Whoever has access presses it, and anyone does while its check wire is cut.
/obj/machinery/button/remote/proc/may_press(datum/act/op/A)
	return allowed(A.actor) || !(wires_num & 1)

/// A refusal flashes the denial on a working button that is not spent and checks access (what refused it, then, was its lock).
/obj/machinery/button/remote/proc/denied_flash(datum/act/A)
	if(operable() && can_press(A) && (wires_num & 1))
		flick("doorctrl-denied", src)
	return OP_OK

/// The press: it draws power, shows pressed, toggles what it is set to and works whatever it controls; the picture comes back a moment later.
/obj/machinery/button/remote/proc/pressed(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	use_power(5)
	icon_state = "doorctrl1"
	desiredstate = !desiredstate
	trigger(user)
	after(src, 1.5 SECONDS, TYPE_PROC_REF(/atom, update_icon), key = "reset_look", clock = CLOCK_WORLD)
	return OP_OK

/// A lock (an access list) is there to scorch off.
/obj/machinery/button/remote/proc/has_access_lock(datum/act/A)
	return LAZYLEN(req_access) || LAZYLEN(req_one_access) // ALLOW(reads): the access lists are read when the sequencer is tried

/// The sequencer scorches the access lock off.
/obj/machinery/button/remote/proc/lock_scorched(datum/act/op/A)
	req_access = null
	req_one_access = null
	play_sfx(src, SFX_SPARKS, 2)
	return OP_OK

/obj/machinery/button/remote/proc/trigger()
	return

/obj/machinery/button/remote/proc/appearance_powered()
	return power_lost() ? 0 : 1

/// The look (the draw sweep: from its template).
/obj/machinery/button/remote/draw(datum/look/look)
	..()
	look.state("doorctrl[appearance_powered() ? "0" : "-p"]")

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

/// Airlocks whose id_tag matches our id (keyed: linked when either end materializes).
/obj/machinery/button/remote/airlock/var/list/obj/machinery/door/airlock/controlled_airlocks
/obj/machinery/button/remote/airlock/relations()
	. = ..()
	. += rel_many(nameof(controlled_airlocks), keyed = nameof(id), keyed_target = /obj/machinery/door/airlock)

/obj/machinery/button/remote/airlock/trigger()
	for(var/obj/machinery/door/airlock/D as anything in controlled_airlocks)
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
				set_bolted(D, TRUE)
			if(specialfunctions & SHOCK)
				D.electrify(-1)
			if(specialfunctions & SAFE)
				D.set_safeties(0)
			continue

		if(specialfunctions & IDSCAN)
			D.set_idscan(1)
		if(specialfunctions & BOLTS)
			set_bolted(D, FALSE)
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

/// Blast doors whose id matches ours (keyed).
/obj/machinery/button/remote/blast_door/var/list/obj/machinery/door/blast/controlled_doors
CAPABILITIES(/obj/machinery/button/remote/blast_door)
	ref_many(nameof(controlled_doors), /obj/machinery/door/blast, by = nameof(id))

/obj/machinery/button/remote/blast_door/trigger()
	for(var/obj/machinery/door/blast/M as anything in controlled_doors)
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
/obj/machinery/button/remote/blast_door/bear/pressed(datum/act/op/A)
	. = ..()
	icon_state = "stuffedbear"

/// The look (the draw sweep: from its template).
/obj/machinery/button/remote/blast_door/bear/draw(datum/look/look)
	..()
	look.state("stuffedbear")


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

/// Blast doors and mass drivers whose id matches ours (keyed).
/obj/machinery/button/remote/driver/var/list/obj/machinery/door/blast/controlled_doors
/obj/machinery/button/remote/driver/var/list/obj/machinery/mass_driver/controlled_drivers
CAPABILITIES(/obj/machinery/button/remote/driver)
	ref_many(nameof(controlled_doors), /obj/machinery/door/blast, by = nameof(id))
	ref_many(nameof(controlled_drivers), /obj/machinery/mass_driver, by = nameof(id))
	op("set_id", tool(TOOL_MULTITOOL), label("Set the id"), wait(0), asks(/datum/prompt/number, fields = list("question" = computed(PROC_REF(id_question)))), then(PROC_REF(id_entered)))

/obj/machinery/button/remote/driver/trigger(mob/user)
	if(active)
		return
	set_active(TRUE)

	for(var/obj/machinery/door/blast/M as anything in controlled_doors)
		M.open()
	after(src, 2 SECONDS, PROC_REF(trigger_step_one), key = "drive_start", clock = CLOCK_WORLD)

/obj/machinery/button/remote/driver/proc/trigger_step_one()
	PRIVATE_PROC(TRUE)
	for(var/obj/machinery/mass_driver/M as anything in controlled_drivers)
		M.drive()
	after(src, 5 SECONDS, PROC_REF(trigger_step_two), key = "drive_end", clock = CLOCK_WORLD)

/obj/machinery/button/remote/driver/proc/trigger_step_two()
	PRIVATE_PROC(TRUE)

	for(var/obj/machinery/door/blast/M as anything in controlled_doors)
		M.close()

	set_active(FALSE)

/// Only an ID or a PDA presses it (any other held thing does nothing).
/obj/machinery/button/remote/driver/item_presses(datum/act/op/A)
	return istype(A.held, /obj/item/card/id) || istype(A.held, /obj/item/pda)

/// What the id is, asked of whoever holds a multitool to it.
/obj/machinery/button/remote/driver/proc/id_question(datum/act/A)
	return "[src] has an id of \"[id]\". What would you like it to be?"

/obj/machinery/button/remote/driver/proc/id_entered(datum/act/op/A)
	var/datum/prompt/R = A.answer
	var/new_id = R?.value
	if(new_id)
		keyed_set_id(src, nameof(id), new_id) // re-links the keyed doors and drivers
	return OP_OK

/obj/machinery/button/remote/driver/proc/appearance_active()
	return (active && !power_lost()) ? 1 : 0

/// The look (the draw sweep: from its template).
/obj/machinery/button/remote/driver/draw(datum/look/look)
	..()
	look.state("launcher[appearance_active() ? "act" : "btt"]")

/*
	Shieldgen remote control
*/
/obj/machinery/button/remote/shields
	name = "remote shield control"
	desc = "It controls shields, remotely."
	icon = 'icons/obj/stationobjs.dmi'

/// Shield generators whose id matches ours (keyed).
/obj/machinery/button/remote/shields/var/list/obj/machinery/shield_gen/controlled_shields
/obj/machinery/button/remote/shields/relations()
	. = ..()
	. += rel_many(nameof(controlled_shields), keyed = nameof(id), keyed_target = /obj/machinery/shield_gen)

/obj/machinery/button/remote/shields/trigger(mob/user)
	for(var/obj/machinery/shield_gen/SG as anything in controlled_shields)
		if(SG.anchored)
			SG.toggle()

/obj/machinery/button/remote/airlock/release
	icon = 'icons/obj/door_release.dmi'
	name = "emergency door release"
	desc = "Forces the opening of doors in an emergency, regardless of whether they're powered."

	use_power = USE_POWER_OFF
	idle_power_usage = 0
	active_power_usage = 0

/obj/machinery/button/remote/airlock/release/trigger()
	for(var/obj/machinery/door/airlock/D as anything in controlled_airlocks)
		if(is_bolted(D))
			set_bolted(D, FALSE, TRUE)
		if(D.density)
			D.open(1)

/obj/machinery/button/remote/airlock/release/powered()
	return 1 //Is always able to be used


/obj/machinery/button/remote/blast_door/single_use
	name = "single use button"
	var/has_been_pressed = FALSE

TRACKED(/obj/machinery/button/remote/blast_door/single_use, has_been_pressed)

/obj/machinery/button/remote/blast_door/single_use/can_press(datum/act/A)
	return !has_been_pressed

/obj/machinery/button/remote/blast_door/single_use/trigger()
	set_has_been_pressed(TRUE)
	..()


/obj/machinery/button/remote/blast_door/single_use/slab
	name = "Button Slab Parent"
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "slab1-off"
	use_power = USE_POWER_OFF
	/// The sprite once pressed.
	var/pressed_state = "slab1"

/obj/machinery/button/remote/blast_door/single_use/slab/pressed(datum/act/op/A)
	. = ..()
	to_chat(A.actor, span_notice("You hear a heavy mechanism open somewhere in the distance."))
	icon_state = pressed_state

/// The look (the draw sweep: from APPEARANCE_NONE).
/obj/machinery/button/remote/blast_door/single_use/slab/draw(datum/look/look)
	..()
	// APPEARANCE_NONE: the mapped sprite, without the parent's declared states and layers
	look.state(null)

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
