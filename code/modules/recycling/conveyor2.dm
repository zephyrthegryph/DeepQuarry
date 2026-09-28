#define OFF 0
#define FORWARDS 1
#define BACKWARDS -1

//conveyor2 is pretty much like the original, except it supports corners, but not diverters.
//note that corner pieces transfer stuff clockwise when running forward, and anti-clockwise backwards.

/obj/machinery/conveyor
	maintenance_flags = MACHINE_MAINT_STANDARD
	icon = 'icons/obj/recycling.dmi'
	icon_state = "conveyor0"
	name = "conveyor belt"
	desc = "A conveyor belt."
	plane = OBJ_PLANE
	layer = STAIRS_LAYER
	anchored = TRUE
	active_power_usage = 100
	circuit = /obj/item/circuitboard/conveyor
	var/operating = OFF	// 1 if running forward, -1 if backwards, 0 if off
	var/operable = 1	// true if can operate (no broken segments in this belt run)
	var/forwards		// this is the default (forward) direction, set by the map dir
	var/backwards		// hopefully self-explanatory
	var/movedir			// the actual direction to move stuff in

	var/list/affecting	// the list of all items that will be moved this ptick
	var/id = ""			// the control ID	- must match controller ID

/obj/machinery/conveyor/centcom_auto
	id = "round_end_belt"

	// create a conveyor
/obj/machinery/conveyor/Initialize(mapload, newdir, on = 0)
	. = ..()
	if(loc)
		om_hook(loc, /datum/om/event/atom_entered, src, PROC_REF(on_turf_entered))
	if(newdir)
		set_dir(newdir)

	update_dir()

	if(on)
		set_operating(FORWARDS)

	default_apply_parts()

/// Phase 2: conveyor switches drop it.
/obj/machinery/conveyor/lifecycle_dematerialize()
	. = ..()
	for(var/obj/machinery/conveyor_switch/conveyor_switch in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		LAZYREMOVE(conveyor_switch.conveyors, src)

/obj/machinery/conveyor/Moved(atom/old_loc, direction, forced = FALSE)
	if(old_loc)
		om_unhook(old_loc, /datum/om/event/atom_entered, src)
	. = ..()
	if(loc)
		om_hook(loc, /datum/om/event/atom_entered, src, PROC_REF(on_turf_entered))

/obj/machinery/conveyor/proc/on_turf_entered(datum/source, datum/om/event/atom_entered/event)
	EVENT_HANDLER
	var/atom/movable/arrived = event.arrived
	if(operating && arrived && !arrived.anchored && !istype(arrived, /obj/effect/abstract) && !arrived.is_incorporeal())
		MACHINE_WAKE(src)

/obj/machinery/conveyor/proc/toggle_speed(forced)
	if(forced)
		set_speed_process(forced)
	else
		set_speed_process(!speed_process) // switching gears
	if(speed_process) // high gear
		update_active_power_usage(initial(idle_power_usage) * 4)
	else // low gear
		update_active_power_usage(initial(idle_power_usage))
	update()

/obj/machinery/conveyor/proc/set_operating(new_operating)
	if(new_operating == operating)
		return // No change
	operating = new_operating
	if(operating == FORWARDS)
		movedir = forwards
	else if(operating == BACKWARDS)
		movedir = backwards
	else
		operating = OFF
	// update() enrols a running belt in the machine (or fast) roster, so cargo
	// already sitting on it is picked up without waiting for a new arrival.
	update()

/obj/machinery/conveyor/set_dir()
	.=..()
	update_dir()

/obj/machinery/conveyor/proc/update_dir()
	if(!(dir in GLOB.cardinal)) // Diagonal. Forwards is *away* from dir, curving to the right.
		forwards = turn(dir, 45)
		backwards = turn(dir, 135)
	else
		forwards = dir
		backwards = turn(dir, 180)

/obj/machinery/conveyor/proc/update()
	if(stat & BROKEN)
		icon_state = "conveyor-broken"
		operating = OFF
		update_use_power(USE_POWER_OFF)
		return
	if(!operable)
		operating = OFF
	if(stat & NOPOWER)
		// Keep the commanded direction across a power blip: process() already
		// kills itself on NOPOWER, and power_change() re-enters here to restart
		// the belt. Clearing `operating` left belts (and their cargo) stalled
		// until someone re-toggled the switch.
		icon_state = "conveyor[OFF]"
		update_use_power(USE_POWER_OFF)
		return
	icon_state = "conveyor[operating]"

	if(!operating)
		update_use_power(USE_POWER_OFF)
		return
	if(speed_process) // high gear
		MACHINE_SLEEP(src)
		PERIODIC_START(src, PERIODIC_FAST)
		update_use_power(USE_POWER_ACTIVE)
	else // low gear
		PERIODIC_STOP(src)
		MACHINE_WAKE(src)
		update_use_power(USE_POWER_ACTIVE)

	// machine process
	// move items to the target location
/obj/machinery/conveyor/machine_step()
	if(stat & (BROKEN | NOPOWER))
		return PROCESS_KILL
	if(!operating)
		return PROCESS_KILL

	var/list/movable_contents = list()
	for(var/atom/movable/A in contents_of(loc))
		if(A == src || A.anchored || istype(A, /obj/effect/abstract) || A.is_incorporeal())
			continue
		movable_contents += A
	if(!length(movable_contents))
		return PROCESS_KILL
	affecting = movable_contents
	om_after(src, 1, PROC_REF(move_affecting)) // slight delay to prevent infinite propagation due to map order

/obj/machinery/conveyor/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/conveyor_drop_item,
		/datum/interaction/machine_hand/ungated/conveyor_push_pulled,
	)
	..()

// attack with item, place item on conveyor. Old attackby never called ..(), so the whole thing stays in the effect.
/datum/interaction/machine_item/conveyor_drop_item
	id = "conveyor_drop_item"
	name = "Drop on belt"
	held_type = /obj/item
	effect = /obj/machinery/conveyor/proc/interaction_drop_item

/obj/machinery/conveyor/proc/interaction_drop_item(mob/user, obj/item/I, datum/interaction/interaction)
	if(isrobot(user))	return TRUE //Carn: fix for borgs dropping their modules on conveyor belts
	if(I.loc != user)	return TRUE // This should stop mounted modules ending up outside the module.

	user.drop_item(get_turf(src))
	return TRUE

/obj/machinery/conveyor/multitool_act(mob/user, obj/item/I)
	if(!panel_open)
		return ITEM_INTERACT_BLOCKING
	var/input = rerun_ask(user, "k166", TYPE_PROC_REF(/atom, multitool_act), args, /datum/om/prompt/text, message = "What id would you like to give this conveyor?", title = "Multitool-Conveyor interface", default = id)
	if(isnull(input))
		return ITEM_INTERACT_BLOCKING
	if(!input)
		to_chat(user, "No input found. Please hang up and try your call again.")
		return ITEM_INTERACT_BLOCKING
	id = input
	for(var/obj/machinery/conveyor_switch/C in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(C.id == id)
			C.conveyors |= src
	return ITEM_INTERACT_SUCCESS

// attack with hand, move pulled object onto conveyor. Old attack_hand never called ..(), so ungated.
/datum/interaction/machine_hand/ungated/conveyor_push_pulled
	id = "conveyor_push_pulled"
	name = "Push pulled object"
	effect = /obj/machinery/conveyor/proc/interaction_push_pulled

/obj/machinery/conveyor/proc/interaction_push_pulled(mob/user, obj/item/held, datum/interaction/interaction)
	var/atom/movable/pulling = user?.pulling_target()
	if ((!( user.canmove ) || user.restrained() || !pulling))
		return TRUE
	if (pulling.anchored)
		return TRUE
	if ((pulling.loc != user.loc && get_dist(user, pulling) > 1))
		return TRUE
	if (ismob(pulling))
		var/mob/M = pulling
		M.stop_pulling()
		step(pulling, get_dir(pulling.loc, src))
		user.stop_pulling()
	else
		step(pulling, get_dir(pulling.loc, src))
		user.stop_pulling()
	return TRUE

// make the conveyor broken
// also propagate inoperability to any connected conveyor with the same ID
/obj/machinery/conveyor/proc/broken()
	atom_break()
	update()

	var/obj/machinery/conveyor/C = locate_within(get_step(src, dir), /obj/machinery/conveyor)
	if(C)
		C.set_operable(dir, id, 0)

	C = locate_within(get_step(src, turn(dir,180)), /obj/machinery/conveyor)
	if(C)
		C.set_operable(turn(dir,180), id, 0)

//set the operable var if ID matches, propagating in the given direction

/obj/machinery/conveyor/proc/set_operable(stepdir, match_id, op)

	if(id != match_id)
		return
	operable = op

	update()
	var/obj/machinery/conveyor/C = locate_within(get_step(src, stepdir), /obj/machinery/conveyor)
	if(C)
		C.set_operable(stepdir, id, op)

/obj/machinery/conveyor/power_change()
	if((. = ..()))
		update()

#undef OFF
#undef FORWARDS
#undef BACKWARDS

// the conveyor control switch
//
//

/obj/machinery/conveyor_switch
	maintenance_flags = MACHINE_MAINT_PANEL

	name = "conveyor switch"
	desc = "A conveyor control switch."
	icon = 'icons/obj/recycling.dmi'
	icon_state = "switch-off"
	var/position = 0			// 0 off, -1 reverse, 1 forward
	var/last_pos = -1			// last direction setting
	var/operated = 1			// true if just operated
	var/oneway = 0				// Voreadd: One way levels mid-round!

	var/id = "" 				// must match conveyor IDs to control them

	var/list/conveyors		// the list of converyors that are controlled by this switch
	anchored = TRUE
	var/speed_active = FALSE // are the linked conveyors on SSfastprocess?

/obj/machinery/conveyor_switch/Initialize(mapload)
	..()
	update()
	return INITIALIZE_HINT_LATELOAD

/obj/machinery/conveyor_switch/LateInitialize()
	conveyors = list()
	for(var/obj/machinery/conveyor/C in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(C.id == id)
			conveyors += C // ALLOW(object_keyed_lists): conveyors sharing our id, rebuilt on relink; each conveyor removes itself in lifecycle_dematerialize()

/obj/machinery/conveyor_switch/proc/toggle_speed(forced)
	speed_active = !speed_active // switching gears
	if(speed_active) // high gear
		for(var/obj/machinery/conveyor/C in conveyors)
			C.toggle_speed(TRUE)
	else // low gear
		for(var/obj/machinery/conveyor/C in conveyors)
			C.toggle_speed(FALSE)

// update the icon depending on the position

/obj/machinery/conveyor_switch/proc/update()
	if(position<0)
		icon_state = "switch-rev"
	else if(position>0)
		icon_state = "switch-fwd"
	else
		icon_state = "switch-off"

// timed process
// if the switch changed, update the linked conveyors

/obj/machinery/conveyor_switch/machine_step()
	if(!operated)
		return PROCESS_KILL
	operated = 0

	for(var/obj/machinery/conveyor/C in conveyors)
		C.set_operating(position)
	return PROCESS_KILL

/obj/machinery/conveyor_switch/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/conveyor_switch_toggle,
	)
	..()

// attack with hand, switch position. Old attack_hand never called ..(), so ungated.
/datum/interaction/machine_hand/ungated/conveyor_switch_toggle
	id = "conveyor_switch_toggle"
	name = "Toggle"
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/conveyor_switch/proc/lets_in, "access denied"))
	effect = /obj/machinery/conveyor_switch/proc/interaction_toggle

/obj/machinery/conveyor_switch/proc/lets_in(mob/actor, atom/target, obj/item/held)
	return allowed(actor)

/obj/machinery/conveyor_switch/proc/interaction_toggle(mob/user, obj/item/held, datum/interaction/interaction)
	if(position == 0)
		if(last_pos < 0 || oneway == 1)
			position = 1
			last_pos = 0
		else
			position = -1
			last_pos = 0
	else
		last_pos = position
		position = 0

	operated = 1
	MACHINE_WAKE(src)
	update()

	// find any switches with same id as this one, and set their positions to match us
	for(var/obj/machinery/conveyor_switch/S in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(S.id == src.id)
			S.position = position
			S.update()
	return TRUE

/obj/machinery/conveyor_switch/welder_act(mob/user, obj/item/I)
	if(!panel_open)
		return ITEM_INTERACT_BLOCKING
	use_tool(user, I, src, delay = 2 SECONDS, quality = TOOL_WELDER, volume = 50, receiver = src, on_done = PROC_REF(welder_act_tool_done), done_args = list(user))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/conveyor_switch/proc/welder_act_tool_done(mob/user)
	if(!src)
		return ITEM_INTERACT_BLOCKING
	to_chat(user, span_notice("You deconstruct the frame."))
	replace_with(src, /obj/item/stack/material/steel, 2)

/obj/machinery/conveyor_switch/multitool_act(mob/user, obj/item/I)
	if(!panel_open)
		return ITEM_INTERACT_BLOCKING
	var/input = rerun_ask(user, "k363", TYPE_PROC_REF(/atom, multitool_act), args, /datum/om/prompt/text, message = "What id would you like to give this conveyor switch?", title = "Multitool-Conveyor interface", default = id)
	if(isnull(input))
		return ITEM_INTERACT_BLOCKING
	if(!input)
		to_chat(user, "No input found. Please hang up and try your call again.")
		return ITEM_INTERACT_BLOCKING
	id = input
	conveyors = list()
	for(var/obj/machinery/conveyor/C in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(C.id == id)
			conveyors += C // ALLOW(object_keyed_lists): conveyors sharing our id, rebuilt on relink; each conveyor removes itself in lifecycle_dematerialize()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/conveyor_switch/wrench_act(mob/user, obj/item/I)
	oneway = !oneway
	to_chat(user, "You set the switch to [oneway ? "one" : "two"] way operation.")
	playsound(src, I.usesound, 50, 1)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/conveyor_switch/wirecutter_act(mob/user, obj/item/I)
	if(!panel_open)
		return ITEM_INTERACT_BLOCKING
	toggle_speed()
	to_chat(user, "You adjust the speed of the conveyor switch")
	return ITEM_INTERACT_SUCCESS

/obj/machinery/conveyor_switch/allow_pai_interaction(mob/living/silicon/pai/user, proximity_flag)
	return proximity_flag

/obj/machinery/conveyor_switch/oneway
	oneway = 1

/obj/machinery/conveyor_switch/examine()
	.=..()
	if(oneway == 1)
		. += " It appears to only go in one direction."

/obj/machinery/conveyor/proc/move_affecting()
	var/items_moved = 0
	for(var/atom/movable/A in affecting)
		if(istype(A,/obj/effect/abstract)) // Flashlight's lights are not physical objects
			continue
		if(A.is_incorporeal())
			continue
		if(!A.anchored)
			if(A.loc == src.loc) // prevents the object from being affected if it's not currently here.
				step(A,movedir)
				items_moved++
		if(items_moved >= 10)
			break

/// Its declared start condition (machine_pipeline.dm, materialize_wakes()).
/obj/machinery/conveyor/step_start_condition()
	return operating
