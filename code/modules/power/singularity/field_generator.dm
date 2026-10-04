//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:33

/**
 * field_generator power level display
 * The icon used for the field_generator need to have 'num_power_levels' number of icon states
 * named 'Field_Gen +p[num]' where 'num' ranges from 1 to 'num_power_levels'
 *
 * The power level is displayed using overlays. The current displayed power level is stored in 'powerlevel'.
 * The overlay in use and the powerlevel variable must be kept in sync.  A powerlevel equal to 0 means that
 * no power level overlay is currently in the overlays list.
 * -Aygar
 */

#define field_generator_max_power 250000
/obj/machinery/field_generator
	name = "Field Generator"
	desc = "A large thermal battery that projects a high amount of energy when powered."
	icon = 'icons/obj/machines/field_generator.dmi'
	icon_state = "Field_Gen"
	anchored = FALSE
	density = TRUE
	use_power = USE_POWER_OFF
	var/const/num_power_levels = 6	// Total number of power level icon has
	var/Varpower = 0
	active = 0
	var/power = 30000  // Current amount of power
	state = 0
	/// The containment fields this generator powers (shared with the generator at the far end;
	/// each field is a map object, rooted by its turf).
	var/list/obj/machinery/containment_field/fields
	/// Generators linked to this one (symmetric membership).
	var/list/obj/machinery/field_generator/connected_gens
	var/clean_up = 0

	//If keeping field generators powered is hard then increase the emitter active power usage.
	var/gen_power_draw = 5500	//power needed per generator
	var/field_power_draw = 2000	//power needed per field object

	var/light_range_on = 3
	var/light_power_on = 1
	light_color = "#5BA8FF"

/// Admin quick-start (debug.dm): the next step brings it straight online.
OM_FIELD(/obj/machinery/field_generator, Varedit_start, FALSE, CHANGE_MACHINE_SETTINGS)
/// Warm-up stage 0-3 (turn_on(), warm_up_step()); the fields go up at 3.
OM_FIELD(/obj/machinery/field_generator, warming_up, 0, CHANGE_MACHINE_SETTINGS)
/// Fields up (active 2) and drawing power, or an admin quick-start pending.
OM_DERIVE_FIELD(/obj/machinery/field_generator, fields_running, list("active", "Varedit_start"))
/obj/machinery/field_generator/proc/fields_running()
	return active == 2 || Varedit_start
/// Switched on (active 1) and still warming up.
OM_DERIVE_FIELD(/obj/machinery/field_generator, warming, list("active", "warming_up"))
/obj/machinery/field_generator/proc/warming()
	return active == 1 && warming_up && warming_up < 3

DECLARE_PERIODIC_WHILE(/obj/machinery/field_generator, MACHINE_PIPELINE, "fields_running")
DECLARE_REPEAT(/obj/machinery/field_generator, 5 SECONDS, warm_up_step, "warming")

/obj/machinery/field_generator/examine()
	. = ..()
	switch(state)
		if(0)
			. += span_warning("It is not secured in place!")
		if(1)
			. += span_warning("It has been bolted down securely, but not welded into place.")
		if(2)
			. += span_notice("It has been bolted down securely and welded down into place.")

DECLARE_APPEARANCE_PROC(/obj/machinery/field_generator, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/field_generator/appearance_overlays()
	. = list()
	if(!active)
		if(warming_up)
			. += "+a[warming_up]"
	if(length(fields))
		. += "+on"
	// Power level indicator
	// Scale % power to % num_power_levels and truncate value
	var/level = round(num_power_levels * power / field_generator_max_power)
	// Clamp between 0 and num_power_levels for out of range power values
	level = between(0, level, num_power_levels)
	if(level)
		. += "+p[level]"

	return .

CAPABILITIES(/obj/machinery/field_generator)
	climb()

/obj/machinery/field_generator/Initialize(mapload)
	. = ..()
	emp_protection_flags |= EMP_PROTECT_SELF

/obj/machinery/field_generator/machine_step()
	if(Varedit_start)
		if(active == 0)
			set_active(1)
			set_state(2)
			power = field_generator_max_power
			set_anchored(TRUE)
			set_warming_up(3)
			start_fields()
			update_icon()
		set_Varedit_start(FALSE)
		return

	calc_power()
	update_icon()

/obj/machinery/field_generator/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/field_generator_activate,
	)
	..()

/// Old attack_hand (never called ..()). The old dist > 1 case did nothing silently;
/// here it's folded into the reach requirement, which shows a reach message instead.
/datum/interaction/machine_hand/ungated/field_generator_activate
	id = "field_generator_activate"
	name = "Activate"
	category = INTERACTION_CAT_TOGGLE
	requires = list(REQ_REACH_ADJACENT, REQ_ON(PRED_TARGET, /obj/machinery/field_generator/proc/is_secured, "needs to be firmly secured to the floor first"), REQ_ON(PRED_TARGET, /obj/machinery/field_generator/proc/is_off, "you are unable to turn off the field generator once it is online"))
	effect = /obj/machinery/field_generator/proc/interaction_activate

/obj/machinery/field_generator/proc/is_secured(mob/actor, atom/target, obj/item/held)
	return state == 2

/obj/machinery/field_generator/proc/is_off(mob/actor, atom/target, obj/item/held)
	return active < 1

/obj/machinery/field_generator/proc/interaction_activate(mob/user, obj/item/held, datum/interaction/interaction)
	act_message(user, null, MSG_SELF("You turn on the [name]."), MSG_OTHERS("[user.name] turns on the [name]"), MSG_BLIND("You hear heavy droning"))
	turn_on()
	log_game("FIELDGEN([x],[y],[z]) Activated by [key_name(user)]")
	investigate_log(span_green("activated") + " by [user.key].","singulo")

	add_fingerprint(user)
	return TRUE

/obj/machinery/field_generator/proc/construction_tool_act(mob/user, obj/item/W, tool_quality)
	if(active)
		to_chat(user, "The [src] needs to be off.")
		return ITEM_INTERACT_BLOCKING
	if(tool_quality == TOOL_WRENCH)
		switch(state)
			if(0)
				set_state(1)
				playsound(src, W.usesound, 75, 1)
				act_message(user, null, MSG_SELF("You secure the external reinforcing bolts to the floor."), \
					MSG_OTHERS("[user.name] secures [src.name] to the floor."), \
					MSG_BLIND("You hear ratchet"))
				set_anchored(TRUE)
			if(1)
				set_state(0)
				playsound(src, W.usesound, 75, 1)
				act_message(user, null, MSG_SELF("You undo the external reinforcing bolts."), \
					MSG_OTHERS("[user.name] unsecures [src.name] reinforcing bolts from the floor."), \
					MSG_BLIND("You hear ratchet"))
				set_anchored(FALSE)
			if(2)
				to_chat(user, span_red("The [src.name] needs to be unwelded from the floor."))
				return
	else if(tool_quality == TOOL_WELDER)
		switch(state)
			if(0)
				to_chat(user, span_red("The [src.name] needs to be wrenched to the floor."))
				return
			if(1)
				use_tool(user, W, src, delay = 2 SECONDS, quality = TOOL_WELDER, volume = 50, start_self = "You start to weld the [src] to the floor.", start_others = "[user.name] starts to weld the [src.name] to the floor.", receiver = src, on_done = PROC_REF(construction_tool_act_tool_done), done_args = list(user))
			if(2)
				use_tool(user, W, src, delay = 2 SECONDS, quality = TOOL_WELDER, volume = 50, start_self = "You start to cut the [src] free from the floor.", start_others = "[user.name] starts to cut the [src.name] free from the floor.", receiver = src, on_done = PROC_REF(construction_tool_act_tool_done2), done_args = list(user))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/field_generator/proc/construction_tool_act_tool_done(mob/user)
	if(!src)
		return
	set_state(2)
	to_chat(user, "You weld the field generator to the floor.")
/obj/machinery/field_generator/proc/construction_tool_act_tool_done2(mob/user)
	if(!src)
		return
	set_state(1)
	to_chat(user, "You cut the [src] free from the floor.")

/obj/machinery/field_generator/wrench_act(mob/user, obj/item/W)
	return construction_tool_act(user, W, TOOL_WRENCH)

/obj/machinery/field_generator/welder_act(mob/user, obj/item/W)
	return construction_tool_act(user, W, TOOL_WELDER)

/obj/machinery/field_generator/bullet_act(obj/item/projectile/Proj)
	if(istype(Proj, /obj/item/projectile/beam))
		power += Proj.damage * EMITTER_DAMAGE_POWER_TRANSFER
		update_icon()
		return 0
	return ..()

// its field comes down.
/obj/machinery/field_generator/on_destroy(force)
	src.cleanup()
	..()

/obj/machinery/field_generator/proc/turn_off()
	set_active(0)
	after(src, 0.1 SECONDS, PROC_REF(finish_turn_off))
	update_icon()

/obj/machinery/field_generator/proc/finish_turn_off()
	cleanup()
	set_light(0)

/obj/machinery/field_generator/proc/turn_on()
	set_active(1)
	set_warming_up(1)
	update_icon()

/// Warming up (declared on `warming`): one stage every five seconds, fields up at the third.
/obj/machinery/field_generator/proc/warm_up_step()
	set_warming_up(warming_up + 1)
	update_icon()
	if(warming_up >= 3)
		start_fields()
		set_light(light_range_on, light_power_on)
		return REPEAT_STOP

/obj/machinery/field_generator/proc/calc_power()
	if(Varpower)
		return 1

	update_icon()
	if(src.power > field_generator_max_power)
		src.power = field_generator_max_power

	var/power_draw = gen_power_draw
	power_draw += gen_power_draw * length(connected_gens)
	for (var/obj/machinery/containment_field/F in fields)
		if (!isnull(F))
			power_draw += field_power_draw
	power_draw /= 2	//because this will be mirrored for both generators
	if(draw_power(round(power_draw)) >= power_draw)
		return 1
	else
		for(var/mob/M in viewers(src))
			M.show_message(span_red("\The [src] shuts down!"))
		turn_off()
		log_game("FIELDGEN([x],[y],[z]) Lost power and was ON.")
		investigate_log("ran out of power and " + span_red("deactivated"),"singulo")
		src.power = 0
		return 0

//Tries to draw the needed power from our own power reserve, or connected generators if we can. Returns the amount of power we were able to get.
/obj/machinery/field_generator/proc/draw_power(draw = 0, list/flood_list = list())
	flood_list += src

	if(src.power >= draw)//We have enough power
		src.power -= draw
		return draw

	//Need more power
	var/actual_draw = src.power	//already checked that power < draw
	src.power = 0

	for(var/obj/machinery/field_generator/FG as anything in connected_gens?.Copy())
		if (FG in flood_list)
			continue
		actual_draw += FG.draw_power(draw - actual_draw, flood_list) //since the flood list reference is shared this actually works.
		if (actual_draw >= draw)
			return actual_draw

	return actual_draw

/obj/machinery/field_generator/proc/start_fields()
	if(src.state != 2 || !anchored)
		turn_off()
		return
	after(src, 0.1 SECONDS, PROC_REF(setup_field), with = list(1))
	after(src, 0.2 SECONDS, PROC_REF(setup_field), with = list(2))
	after(src, 0.3 SECONDS, PROC_REF(setup_field), with = list(4))
	after(src, 0.4 SECONDS, PROC_REF(setup_field), with = list(8))
	set_active(2)

/obj/machinery/field_generator/proc/setup_field(NSEW)
	var/turf/T = src.loc
	var/obj/machinery/field_generator/G
	var/steps = 0
	if(!NSEW)//Make sure its ran right
		return
	for(var/dist = 0, dist <= 9, dist += 1) // checks out to 8 tiles away for another generator
		T = get_step(T, NSEW)
		if(T.density)//We cant shoot a field though this
			return 0
		for(var/atom/A in turf_contents_of_type(T, /atom))
			if(ismob(A))
				continue
			if(!istype(A,/obj/machinery/field_generator))
				if((istype(A,/obj/machinery/door)||istype(A,/obj/machinery/the_singularitygen))&&(A.density))
					return 0
		steps += 1
		G = locate_on(T, /obj/machinery/field_generator)
		if(!isnull(G))
			steps -= 1
			if(!G.active)
				return 0
			break
	if(isnull(G))
		return
	T = src.loc
	for(var/dist = 0, dist < steps, dist += 1) // creates each field tile
		var/field_dir = get_dir(T,get_step(G.loc, NSEW))
		T = get_step(T, NSEW)
		if(!locate_on(T, /obj/machinery/containment_field))
			var/obj/machinery/containment_field/CF = new/obj/machinery/containment_field(T)
			CF.set_master(src,G)
			rel_add(src, nameof(fields), CF)
			rel_add(G, nameof(G.fields), CF)
			CF.set_dir(field_dir)
	rel_add(src, nameof(connected_gens), G) // symmetric: G lists us too

/obj/machinery/field_generator/proc/cleanup()
	clean_up = 1
	// Each field leaves both generators' lists as it is destroyed.
	for (var/obj/machinery/containment_field/F as anything in fields?.Copy())
		if (QDELETED(F))
			continue
		qdel(F)
	for(var/obj/machinery/field_generator/FG as anything in connected_gens?.Copy())
		rel_remove(src, nameof(connected_gens), FG) // symmetric: FG forgets us too
		if (QDELETED(FG))
			continue
		if(!FG.clean_up)//Makes the other gens clean up as well
			FG.cleanup()
	clean_up = 0

	update_icon()

	//This is here to help fight the "hurr durr, release singulo cos nobody will notice before the
	//singulo eats the evidence". It's not fool-proof but better than nothing.
	//I want to avoid using global variables.
	var/temp = 1 //stops spam
	for(var/obj/singularity/O in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(O.last_warning && temp)
			if(ELAPSED(O, last_warning, CLOCK_WORLD) > 5 SECONDS) //to stop message-spam
				temp = 0
				admin_chat_message(message = "SINGUL/TESLOOSE!", color = "#FF2222")
				message_admins("A singulo exists and a containment field has failed.")
				investigate_log("has " + span_red("failed") + " whilst a singulo exists.","singulo")
				log_game("FIELDGEN([x],[y],[z]) Containment failed while singulo/tesla exists.")
		EXPIRY_STAMP(O, last_warning, CLOCK_WORLD)

/obj/machinery/field_generator/pre_mapped
	state = 2 //Start welded.
	anchored = TRUE

/obj/machinery/field_generator/pre_mapped/Initialize(mapload)
	. = ..()
	update_icon()

/obj/machinery/field_generator/relations()
	. = ..()
	. += rel_many(nameof(fields))
	. += rel_many(nameof(connected_gens), back = nameof(/obj/machinery/field_generator::connected_gens))
