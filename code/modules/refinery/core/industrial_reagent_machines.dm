/obj/machinery/reagent_refinery
	step_on_power_change = TRUE
	maintenance_flags = MACHINE_MAINT_STANDARD
	icon = 'icons/obj/machines/refinery_machines.dmi'
	VAR_PROTECTED/default_max_vol = 120
	VAR_PROTECTED/amount_per_transfer_from_this = 120
	VAR_PROTECTED/possible_transfer_amounts = REFINERY_DEFAULT_TRANSFER_AMOUNTS
	VAR_PROTECTED/reagent_type = /datum/reagents

/obj/machinery/reagent_refinery/Initialize(mapload)
	. = ..()
	// reagent control
	if(default_max_vol > 0)
		create_reagents(default_max_vol, reagent_type)
	// Update neighbours and self for state
	update_neighbours()
	update_icon()
	make_rotatable()

// its reagents are flushed.
/obj/machinery/reagent_refinery/on_destroy(force)
	reagent_flush()
	..()

/obj/machinery/reagent_refinery/dismantle()
	reagent_flush()
	. = ..()

/obj/machinery/reagent_refinery/set_dir(newdir)
	. = ..()
	update_icon()
	wake_refinery_line()

/obj/machinery/reagent_refinery/on_reagent_change(changetype)
	update_icon()
	wake_refinery_line()

// A refinery line runs on the machine pipeline only while something moves (roadmap S5): a machine
// steps while its reagents change or it is otherwise busy (refinery_busy()), and sleeps once a
// step moves nothing -- empty, blocked downstream, or waiting on input. Anything that could let
// it move again wakes it and its neighbours: reagents arriving or leaving (on_reagent_change()),
// wrenching, turning, a player's setting (interaction_ran()), power.

/// Wakes this machine and the refinery machines next to it (a change here can unblock them).
/obj/machinery/reagent_refinery/proc/wake_refinery_line()
	work_start(src)
	for(var/direction in GLOB.cardinal)
		var/obj/machinery/reagent_refinery/other = locate_within(get_step(get_turf(src), direction), /obj/machinery/reagent_refinery)
		if(other)
			MACHINE_WAKE(other)

/obj/machinery/reagent_refinery/interaction_ran(mob/actor, datum/interaction/interaction)
	wake_refinery_line()

/// Unanchored refinery machines are disconnected and do nothing.
// Its periodic work: work_step() while it is started (code/library/machine/started_work.dm).
CAPABILITIES(/obj/machinery/reagent_refinery)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(anchored), wakes_on = list(nameof(anchored), nameof(stat)))
	op("reagent_refinery_drain", inputs(item(/obj/item/reagent_containers/glass), item(/obj/item/reagent_containers/food/drinks/glass2), item(/obj/item/reagent_containers/food/drinks/shaker)), priority(OP_PRIORITY_DEFAULT - 1), label("Drain"), when(req(PROC_REF(has_reagents_holder_holds))), needs(req_reagents(0, more = TRUE, because = MSG(reagent_refinery/nothing_to_drain))), then(PROC_REF(interaction_drain)))
	op("reagent_refinery_set_transfer_amount", menu(), label("Set transfer amount"), needs(req_adjacent(), req_capable()), then(PROC_REF(interaction_set_transfer_amount)))

/obj/machinery/reagent_refinery/proc/work_step(datum/act/timer/A)
	var/before = reagents ? reagents.total_volume : 0
	refinery_step()
	if(QDELETED(src))
		return PROCESS_KILL
	if(refinery_busy())
		return
	if(!reagents || reagents.total_volume <= 0 || reagents.total_volume == before)
		return PROCESS_KILL

/// One step of this machine's work (moving, filtering, reacting reagents).
/obj/machinery/reagent_refinery/proc/refinery_step()
	return

/// TRUE while the machine has work even though its reagent volume didn't change this step.
/obj/machinery/reagent_refinery/proc/refinery_busy()
	return FALSE

/// Splashes reagents all over the floor, called from destroy and dismantle.
/obj/machinery/reagent_refinery/proc/reagent_flush()
	if(reagents && reagents.total_volume > 30)
		visible_message(span_danger("\The [src] splashes everywhere as it is disassembled!"))
		reagents.splash_area(get_turf(src),2)

MSG_DEF_SELF(reagent_refinery/nothing_to_drain, "it's empty; there is nothing to drain")

/// Requirement (was REQ_* has_reagents_holder): the legacy check answers TRUE to pass.
/obj/machinery/reagent_refinery/proc/has_reagents_holder_holds(datum/act/op/A)
	var/answer = has_reagents_holder(A.actor, src, A.held)
	return !istext(answer) && !!answer

/obj/machinery/reagent_refinery/proc/has_reagents_holder(mob/actor, atom/target, obj/item/held)
	return !!reagents

/obj/machinery/reagent_refinery/proc/interaction_drain(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/held = A.held
	// Fill up the whole volume if we can, DUMP IT OUT
	var/obj/item/reagent_containers/C = held
	reagents.trans_to_obj(C, reagents.total_volume)
	play_sfx(src, SFX_MACHINES_REAGENT_DISPENSE)
	to_chat(user, "You drain \the [src] into \the [C].")
	return OP_OK

/obj/machinery/reagent_refinery/wrench_act(mob/user, obj/item/tool)
	if(!anchored)
		for(var/obj/machinery/reagent_refinery/other in contents_of(loc))
			if(other != src)
				to_chat(user, span_warning("You cannot anchor \the [src] until \the [other] is moved out of the way!"))
				return ITEM_INTERACT_BLOCKING
	playsound(src, tool.usesound, 75, TRUE)
	set_anchored(!anchored)
	act_message(user, src, MSG_SELF("You [anchored ? "secure" : "unsecure"] the bolts holding %T% to the floor."), \
		MSG_OTHERS("[user.name] [anchored ? "secures" : "unsecures"] the bolts holding [src.name] to the floor."), \
		MSG_BLIND("You hear a ratchet."))
	update_neighbours()
	update_icon()
	wake_refinery_line()
	return ITEM_INTERACT_SUCCESS

/// Updates the icons of all neighbour machines, used when connecting.
/obj/machinery/reagent_refinery/proc/update_neighbours()
	// Update icons and neighbour icons to avoid loss of sanity
	for(var/direction in GLOB.cardinal)
		var/turf/T = get_step(get_turf(src),direction)
		var/obj/machinery/other = locate_on(T, /obj/machinery/reagent_refinery)
		if(other && other.anchored)
			other.update_icon()

/// Changes the transfer rate of reagents from this machine to the next
/datum/interaction/machine_verb/reagent_refinery_set_transfer_amount
	id = "reagent_refinery_set_transfer_amount"
	name = "Set transfer amount"
	requires = list(REQ_INTERACTION_REACH)
	effect = /obj/machinery/reagent_refinery/proc/interaction_set_transfer_amount

/obj/machinery/reagent_refinery/proc/interaction_set_transfer_amount(datum/act/op/A)
	var/mob/user = A.actor
	var/N = rerun_ask(user, "k140", PROC_REF(interaction_set_transfer_amount), args, /datum/prompt/choice, question = "Amount per transfer from this:", title = "[src]", choices = possible_transfer_amounts)
	if(isnull(N))
		return
	if(N && Adjacent(user))
		amount_per_transfer_from_this = N
		update_icon()
	return TRUE

/// Transfers reagents from us to the next machine. Calls handle_transfer() on any target machines to check if they can accept reagents.
/obj/machinery/reagent_refinery/proc/transfer_tank( datum/reagents/RT, obj/machinery/reagent_refinery/target, source_forward_dir, filter_id = "")
	PROTECTED_PROC(TRUE)
	if(RT.total_volume <= 0 || !anchored || !target.anchored)
		return 0
	if(active_power_usage > 0 && !can_use_power_oneoff(active_power_usage))
		return 0
	if(!istype(target,/obj/machinery/reagent_refinery) || istype(target,/obj/machinery/reagent_refinery/grinder)) // Grinders don't allow input
		return 0
	var/transfered = target.handle_transfer(src,RT,source_forward_dir, amount_per_transfer_from_this, filter_id)
	if(transfered > 0 && active_power_usage > 0)
		use_power_oneoff(active_power_usage)
	return transfered

/// Handles reagent recieving from transfer_tank(), returns how much reagent was transfered if successful. Overriden to prevent access from certain sides or for filtering.
/obj/machinery/reagent_refinery/proc/handle_transfer(atom/origin_machine, datum/reagents/RT, source_forward_dir, transfer_rate, filter_id = "") // Handle transfers in an override, instead of one monster function that typechecks like transfer_tank() used to be
	// Transfer to target in amounts every process tick!
	if(filter_id == "")
		var/amount = RT.trans_to_obj(src, transfer_rate)
		return amount
	// Split out reagent...
	return RT.trans_id_to(src, filter_id, transfer_rate, TRUE)

/obj/machinery/reagent_refinery/proc/refinery_transfer()
	if(amount_per_transfer_from_this <= 0 || reagents.total_volume <= 0)
		return 0

	// dump reagents to next refinery machine
	var/obj/machinery/reagent_refinery/target = locate_within(get_step(get_turf(src),dir), /obj/machinery/reagent_refinery)
	if(!target)
		return 0
	if(reagents.total_volume < minimum_reagents_for_transfer(target))
		return 0

	return transfer_tank( reagents, target, dir)

/// Handle transfers that require a minimum amount of reagents to happen
/obj/machinery/reagent_refinery/proc/minimum_reagents_for_transfer(obj/machinery/reagent_refinery/target)
	return 0

/obj/machinery/reagent_refinery/proc/tutorial(flags,list/examine_list)
	// Specialty
	if(flags & REFINERY_TUTORIAL_HUB)
		examine_list += "A trolly tanker can be drained or filled depending on if this machine is attached to the input or output of another machine. "
	// Input handling
	if(flags & REFINERY_TUTORIAL_NOINPUT)
		examine_list += "This machine does not accept any inputs, and only outputs. "
	if(flags & REFINERY_TUTORIAL_ALLIN)
		examine_list += "This machine accepts input from all sides. "
	if(flags & REFINERY_TUTORIAL_SINGLEOUTPUT)
		examine_list += "This machine accepts inputs on all sides, except for its output. "
	if(flags & REFINERY_TUTORIAL_NOOUTPUT)
		examine_list += "This machine does not have any outputs. "
	// Pipe markings
	if(flags & REFINERY_TUTORIAL_INPUT)
		examine_list += "The red pipe marks the input. "
	if(flags & REFINERY_TUTORIAL_FILTER)
		examine_list += "The purple pipe marks the filtered output. "
	// No power needed
	if(flags & REFINERY_TUTORIAL_NOPOWER)
		examine_list += "Does not require power. "

/// Checks neighbouring machines for if we should connect visually to them
/obj/machinery/reagent_refinery/proc/update_input_connection_overlays(overlay_state)
	. = list()
	for(var/direction in GLOB.cardinal)
		var/turf/T = get_step(get_turf(src),direction)
		var/obj/machinery/reagent_refinery/other = locate_on(T, /obj/machinery/reagent_refinery)
		if(!other?.anchored)
			continue

		// Waste processors do not connect to anything as outgoing
		if(istype(other,/obj/machinery/reagent_refinery/waste_processor))
			continue

		// Filter allows side connection
		if(istype(other,/obj/machinery/reagent_refinery/filter))
			var/obj/machinery/reagent_refinery/filter/filt = other
			var/check_dir = 0
			if(filt.get_filter_side() == 1)
				check_dir = turn(filt.dir, 270)
			else
				check_dir = turn(filt.dir, 90)
			if(check_dir == GLOB.reverse_dir[direction])
				var/image/intake = image(icon, icon_state = overlay_state, dir = direction)
				. += intake
				continue

		// Splitter only allows side connections
		if(istype(other,/obj/machinery/reagent_refinery/splitter))
			if(GLOB.reverse_dir[direction] in list(turn(other.dir,90),turn(other.dir,-90)))
				var/image/intake = image(icon, icon_state = overlay_state, dir = direction)
				. += intake
			continue

		// Standard connection
		if(other.dir == GLOB.reverse_dir[direction] && (dir != direction || istype(src,/obj/machinery/reagent_refinery/waste_processor)))
			var/image/intake = image(icon, icon_state = overlay_state, dir = direction)
			. += intake
