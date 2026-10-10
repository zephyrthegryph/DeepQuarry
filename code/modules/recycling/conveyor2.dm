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

	var/list/affecting	// the list of all items that will be moved this ptick
	var/id = ""			// the control ID	- must match controller ID

TRACKED(/obj/machinery/conveyor, operating)
/// Moves what sits on it while running and operable (the declaration also picks the machine
/// pipeline or the fast lane on speed_process); with nothing to move it sleeps until cargo arrives.
/obj/machinery/conveyor/centcom_auto
	id = "round_end_belt"

	// create a conveyor
CAPABILITIES(/obj/machinery/conveyor)
	on_change(nameof(operating), ANY, then(PROC_REF(operating_changed)))
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(operating), gate = PROC_REF(operable), wakes_on = list(nameof(operating), STAT_OPERABLE))
	param(nameof(dir), pos = 1)
	param(nameof(starts_on), pos = 2)
	adjacency(ADJ_KIND_CONVEYOR, dirs = ADJ_ALL_AROUND)
	// a cyborg's module never drops onto the belt: its item click is taken and nothing happens
	// the multitool sets the id behind an open panel; with the panel shut it takes the click and does nothing
	op("use_multitool", tool(TOOL_MULTITOOL), priority(OP_PRIORITY_DEFAULT), wait(0), label("Set ID"), needs(req(PROC_REF(maintenance_panel_open), silent = TRUE)),
		asks(/datum/prompt/text/conveyor_id, fields = list("question" = "What id would you like to give this conveyor?", "title" = "Multitool-Conveyor interface", "default" = nameof(id))),
		then(PROC_REF(conveyor_id_answered)))
	op("conveyor_drop_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 2), label("Drop on belt"), then(PROC_REF(interaction_drop_item)))
	op("conveyor_push_pulled", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Push pulled object"), then(PROC_REF(interaction_push_pulled)))

/// A conveyor that starts running (its constructor param).
/obj/machinery/conveyor/var/starts_on = FALSE

// ALLOW(init/INSTANCE_STATE): a conveyor watches what enters its turf, sets its belt direction and parts, and may start running
/obj/machinery/conveyor/Initialize(mapload)
	. = ..()
	if(loc)
		observe(loc, /datum/notice/atom_entered, src, then(PROC_REF(on_turf_entered)))
	update_dir()

	if(starts_on)
		set_operating(FORWARDS)

	default_apply_parts()

/obj/machinery/conveyor/Moved(atom/old_loc, direction, forced = FALSE)
	if(old_loc)
		unobserve(old_loc, /datum/notice/atom_entered, src)
	. = ..()
	if(loc)
		observe(loc, /datum/notice/atom_entered, src, then(PROC_REF(on_turf_entered)))

/obj/machinery/conveyor/proc/on_turf_entered(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/atom_entered/event = A
	var/atom/movable/arrived = event.arrived
	if(operating && arrived && !arrived.anchored && !istype(arrived, /obj/effect/abstract) && !arrived.is_incorporeal())
		work_start(src)

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

/// The belt started, stopped or reversed: it redraws.
/obj/machinery/conveyor/proc/operating_changed(datum/act/A)
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
	if(broken_now())
		icon_state = "conveyor-broken"
		set_operating(OFF)
		set_use_power(USE_POWER_OFF)
		return
	if(!operable)
		set_operating(OFF)
	if(power_lost())
		// Keep the commanded direction across a power blip: process() already
		// kills itself on NOPOWER, and power_change() re-enters here to restart
		// the belt. Clearing `operating` left belts (and their cargo) stalled
		// until someone re-toggled the switch.
		icon_state = "conveyor[OFF]"
		set_use_power(USE_POWER_OFF)
		return
	icon_state = "conveyor[operating]"

	if(!operating)
		set_use_power(USE_POWER_OFF)
		return
	// The operating/operable declaration runs the belt (fast lane in high gear).
	set_use_power(USE_POWER_ACTIVE)

	// machine process
	// move items to the target location
/obj/machinery/conveyor/proc/work_step(datum/act/timer/timer)
	var/list/movable_contents = list()
	for(var/atom/movable/A in contents_of(loc))
		if(A == src || A.anchored || istype(A, /obj/effect/abstract) || A.is_incorporeal())
			continue
		movable_contents += A
	if(!length(movable_contents))
		return PROCESS_KILL
	affecting = movable_contents
	after(src, 0.1 SECONDS, PROC_REF(move_affecting)) // slight delay to prevent infinite propagation due to map order

// attack with item, place item on conveyor. Old attackby never called ..(), so the whole thing stays in the effect.

/obj/machinery/conveyor/proc/interaction_drop_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(I.loc != user)	return OP_OK // This should stop mounted modules ending up outside the module.

	user.drop_item(get_turf(src))
	return OP_OK

// attack with hand, move pulled object onto conveyor. Old attack_hand never called ..(), so ungated.

/obj/machinery/conveyor/proc/interaction_push_pulled(datum/act/op/A)
	var/mob/user = A.actor
	var/atom/movable/pulling = user?.pulling_target()
	if ((!( user.canmove ) || user.restrained() || !pulling))
		return OP_OK
	if (pulling.anchored)
		return OP_OK
	if ((pulling.loc != user.loc && get_dist(user, pulling) > 1))
		return OP_OK
	if (ismob(pulling))
		var/mob/M = pulling
		M.stop_pulling()
		step(pulling, get_dir(pulling.loc, src))
		user.stop_pulling()
	else
		step(pulling, get_dir(pulling.loc, src))
		user.stop_pulling()
	return OP_OK

// make the conveyor broken
// also propagate inoperability to any connected conveyor with the same ID
/obj/machinery/conveyor/proc/broken()
	atom_break()
	update()

	var/obj/machinery/conveyor/C = adjacency_member_at(src, ADJ_KIND_CONVEYOR, dir)
	if(C)
		C.set_operable(dir, id, 0)

	C = adjacency_member_at(src, ADJ_KIND_CONVEYOR, turn(dir,180))
	if(C)
		C.set_operable(turn(dir,180), id, 0)

//set the operable var if ID matches, propagating in the given direction

/obj/machinery/conveyor/proc/set_operable(stepdir, match_id, op)

	if(id != match_id)
		return
	operable = op

	update()
	var/obj/machinery/conveyor/C = adjacency_member_at(src, ADJ_KIND_CONVEYOR, stepdir)
	if(C)
		C.set_operable(stepdir, id, op)

/obj/machinery/conveyor/power_change()
	if((. = ..()))
		update()


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
	var/oneway = 0				// Voreadd: One way levels mid-round!

	var/id = "" 				// must match conveyor IDs to control them

	var/list/conveyors		// the list of converyors that are controlled by this switch
	anchored = TRUE
	var/speed_active = FALSE // are the linked conveyors on SSfastprocess?

/// Other switches sharing our id (keyed; includes this one), kept in step with our position.
/obj/machinery/conveyor_switch/var/list/obj/machinery/conveyor_switch/linked_switches

/// TRUE when just operated: one step pushes the position to the linked conveyors.
/obj/machinery/conveyor_switch/var/operated = FALSE
TRACKED_BRIDGED(/obj/machinery/conveyor_switch, operated, CHANGE_MACHINE_SETTINGS)
CAPABILITIES(/obj/machinery/conveyor_switch)
	after_init(0, then(PROC_REF(init_update)))
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(operated), wakes_on = list(nameof(operated)))
	ref_many(nameof(conveyors), /obj/machinery/conveyor, by = nameof(id))
	ref_many(nameof(linked_switches), /obj/machinery/conveyor_switch, by = nameof(id))
	op("conveyor_switch_toggle", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Toggle"), needs(req(PROC_REF(lets_in_holds), because = PROC_REF(lets_in_refusal))), then(PROC_REF(interaction_toggle)))
	// the panel's tools: with the panel shut the welder, multitool and wirecutters take the click and do nothing
	op("use_welder", lit_welder(fuel = 0), priority(OP_PRIORITY_DEFAULT), wait(2 SECONDS), label("Deconstruct"), needs(req(PROC_REF(maintenance_panel_open), silent = TRUE)), then(PROC_REF(welded_apart)))
	op("use_multitool", tool(TOOL_MULTITOOL), priority(OP_PRIORITY_DEFAULT), wait(0), label("Set ID"), needs(req(PROC_REF(maintenance_panel_open), silent = TRUE)),
		asks(/datum/prompt/text/conveyor_id, fields = list("question" = "What id would you like to give this conveyor switch?", "title" = "Multitool-Conveyor interface", "default" = nameof(id))),
		then(PROC_REF(conveyor_switch_id_answered)))
	op("use_wrench", tool(TOOL_WRENCH), priority(OP_PRIORITY_DEFAULT), wait(0), label("Set one-way"), then(PROC_REF(wrench_used)))
	op("use_wirecutter", tool(TOOL_WIRECUTTER), priority(OP_PRIORITY_DEFAULT), wait(0), label("Adjust speed"), needs(req(PROC_REF(maintenance_panel_open), silent = TRUE)), then(PROC_REF(wirecutter_used)))

/obj/machinery/conveyor_switch/proc/init_update(datum/act/timer/A)
	update()


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

/obj/machinery/conveyor_switch/proc/work_step(datum/act/timer/timer)
	set_operated(FALSE)

	for(var/obj/machinery/conveyor/C in conveyors)
		C.set_operating(position)
	return PROCESS_KILL

/// Requirement (was REQ_* lets_in): the legacy check answers TRUE to pass.
/obj/machinery/conveyor_switch/proc/lets_in_holds(datum/act/op/A)
	var/answer = lets_in(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why lets_in_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/conveyor_switch/proc/lets_in_refusal(datum/act/op/A)
	var/answer = lets_in(A.actor, src, A.held)
	return istext(answer) ? answer : "access denied"

// attack with hand, switch position. Old attack_hand never called ..(), so ungated.

/obj/machinery/conveyor_switch/proc/lets_in(mob/actor, atom/target, obj/item/held)
	return allowed(actor)

/obj/machinery/conveyor_switch/proc/interaction_toggle(datum/act/op/A)
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

	set_operated(TRUE)
	update()

	// find any switches with same id as this one, and set their positions to match us
	for(var/obj/machinery/conveyor_switch/S as anything in linked_switches)
		S.position = position
		S.update()
	return OP_OK

/// The welder's work, after its wait behind the open panel: the switch comes apart into steel.
/obj/machinery/conveyor_switch/proc/welded_apart(datum/act/op/A)
	to_chat(A.actor, span_notice("You deconstruct the frame."))
	replace_with(src, /obj/item/stack/material/steel, 2)
	return OP_OK

/// The wrench: one-way or two-way operation.
/obj/machinery/conveyor_switch/proc/wrench_used(datum/act/op/A)
	var/obj/item/tool = A.held
	oneway = !oneway
	to_chat(A.actor, "You set the switch to [oneway ? "one" : "two"] way operation.")
	playsound(src, tool.usesound, 50, 1)
	return OP_OK

/// The wirecutters, behind the open panel: the conveyors' speed.
/obj/machinery/conveyor_switch/proc/wirecutter_used(datum/act/op/A)
	toggle_speed()
	to_chat(A.actor, "You adjust the speed of the conveyor switch")
	return OP_OK

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
				step(A, operating == BACKWARDS ? backwards : forwards)
				items_moved++
		if(items_moved >= 10)
			break

/// A conveyor's or switch's id, asked by the multitool op behind the open panel: the panel is still open when the answer comes.
/datum/prompt/text/conveyor_id
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/text/conveyor_id/recheck_extra()
	var/obj/machinery/device = owner
	if(!isnull(value) && istype(device) && !device.panel_open)
		return "panel closed"
	return null

/// The multitool's answer: the conveyor's id (the keyed switches follow it).
/obj/machinery/conveyor/proc/conveyor_id_answered(datum/act/op/A)
	if(A.answer?.value)
		keyed_set_id(src, nameof(id), A.answer.value)
	else
		to_chat(A.actor, "No input found. Please hang up and try your call again.")
	SStgui.update_uis(src)
	return OP_OK

/// The multitool's answer: the switch's id (its conveyors and the other switches follow it).
/obj/machinery/conveyor_switch/proc/conveyor_switch_id_answered(datum/act/op/A)
	if(A.answer?.value)
		keyed_set_id(src, nameof(id), A.answer.value)
	else
		to_chat(A.actor, "No input found. Please hang up and try your call again.")
	SStgui.update_uis(src)
	return OP_OK

#undef OFF
#undef FORWARDS
#undef BACKWARDS
