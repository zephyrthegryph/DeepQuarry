// The field generator (doc/rewrite/final_api.html section 16): the singularity engine's containment. Bolted and welded to the floor
// (floor_weld()), switched on by hand, it warms up for FIELD_GEN_WARMUP_STAGE twice (warming_up 1 -> 3) and then raises containment fields toward
// every active generator within 9 tiles. While its fields stand it pays for them every machine service interval (field_step(): half of
// gen_power_draw, plus gen_power_draw per linked generator and field_power_draw per field, from its own store and then its partners'); a
// generator that cannot pay shuts down and its fields fall. Emitter beams charge its store.
//
// SAFETY: the fields are what holds a singularity (its can_move() refuses a field tile and an active generator's tile). Every number here is
// pinned in code/modules/unit_tests/dq_power_plants_behaviour.dm (fg_*, containment_field_*).

/// The store a field generator holds at most, J.
#define FIELD_GEN_MAX_POWER 250000
/// One warm-up stage; the fields rise after the second.
#define FIELD_GEN_WARMUP_STAGE (5 SECONDS)

MSG_DEF_SELF(fieldgen/unsecured, "It needs to be firmly secured to the floor first.")
MSG_DEF_SELF(fieldgen/online, "You are unable to turn off the field generator once it is online.")
MSG_DEF(fieldgen/activated, "You turn on %T%.", "%U% turns on %T%.")

/obj/machinery/field_generator
	name = "Field Generator"
	desc = "A large thermal battery that projects a high amount of energy when powered."
	icon = 'icons/obj/machines/field_generator.dmi'
	icon_state = "Field_Gen"
	anchored = FALSE
	density = TRUE
	use_power = USE_POWER_OFF
	/// The number of power level overlays the icon has ("+p1" .. "+p6").
	var/const/num_power_levels = 6
	/// Admin: the store never drains (calc_power() pays nothing).
	var/Varpower = 0
	active = 0
	/// The store the fields are paid from, J.
	var/power = 30000
	state = 0
	/// The containment fields this generator powers (shared with the generator at the far end; each field is a map object, rooted by its turf).
	var/list/obj/machinery/containment_field/fields
	/// Generators linked to this one (a symmetric link).
	var/list/obj/machinery/field_generator/connected_gens
	var/clean_up = 0

	//If keeping field generators powered is hard then increase the emitter active power usage.
	var/gen_power_draw = 5500	//power needed per generator
	var/field_power_draw = 2000	//power needed per field object

	var/light_range_on = 3
	var/light_power_on = 1
	light_color = "#5BA8FF"
	/// Admin quick-start: the next step brings it straight online.
	var/Varedit_start = FALSE
	/// Warm-up stage 0-3 (turn_on(), warm_up_step()); the fields go up at 3.
	var/warming_up = 0

TRACKED(/obj/machinery/field_generator, Varedit_start)
TRACKED(/obj/machinery/field_generator, warming_up)

CAPABILITIES(/obj/machinery/field_generator)
	climb()
	floor_weld(busy = nameof(active))
	ref_many(nameof(fields), /obj/machinery/containment_field)
	links(/obj/machinery/field_generator::connected_gens, /obj/machinery/field_generator::connected_gens, a_many = TRUE, b_many = TRUE)
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(field_step)), when = PROC_REF(fields_running))
	op("activate", hand(), when(req_empty_hand()), label("Activate"), ungated(), wait(0),
		needs(req(PROC_REF(is_secured), because = MSG(fieldgen/unsecured)), req(PROC_REF(is_off), because = MSG(fieldgen/online))),
		says(MSG(fieldgen/activated)), then(PROC_REF(activated)))

/obj/machinery/field_generator/Initialize(mapload)
	. = ..()
	emp_protection_flags |= EMP_PROTECT_SELF

/// Its fields stand (active 2) and must be paid for, or an admin quick-start is pending.
/obj/machinery/field_generator/proc/fields_running(datum/act/A)
	return active == 2 || Varedit_start

/obj/machinery/field_generator/proc/is_secured(datum/act/A)
	return state == FLOOR_WELD_WELDED

/obj/machinery/field_generator/proc/is_off(datum/act/A)
	return active < 1

/obj/machinery/field_generator/draw(datum/look/look)
	..()
	if(!active)
		look.overlay("+a[warming_up]", when = warming_up)
	look.overlay("+on", when = length(fields))
	// The power level: the store's share of the maximum, in num_power_levels steps.
	var/level = between(0, round(num_power_levels * power / FIELD_GEN_MAX_POWER), num_power_levels)
	look.overlay("+p[level]", when = level)

/// One step while the fields stand (every machine service interval): an admin quick-start, or the fields' bill.
/obj/machinery/field_generator/proc/field_step(datum/act/timer/A)
	if(Varedit_start)
		if(active == 0)
			set_active(1)
			set_state(FLOOR_WELD_WELDED)
			power = FIELD_GEN_MAX_POWER
			set_anchored(TRUE)
			set_warming_up(3)
			start_fields()
			update_icon()
		set_Varedit_start(FALSE)
		return
	calc_power()
	update_icon()

/// Switched on by hand: the warm-up starts.
/obj/machinery/field_generator/proc/activated(datum/act/op/A)
	var/mob/user = A.actor
	turn_on()
	log_game("FIELDGEN([x],[y],[z]) Activated by [key_name(user)]")
	investigate_log(span_green("activated") + " by [user?.key].","singulo")
	add_fingerprint(user)
	return OP_OK

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
	cancel_after(src, "warm_up_1")
	cancel_after(src, "warm_up_2")
	set_warming_up(0)
	after(src, 0.1 SECONDS, PROC_REF(finish_turn_off))
	update_icon()

/obj/machinery/field_generator/proc/finish_turn_off()
	cleanup()
	set_light(0)

/obj/machinery/field_generator/proc/turn_on()
	set_active(1)
	set_warming_up(1)
	after(src, FIELD_GEN_WARMUP_STAGE, PROC_REF(warm_up_step), key = "warm_up_1")
	after(src, FIELD_GEN_WARMUP_STAGE * 2, PROC_REF(warm_up_step), key = "warm_up_2")
	update_icon()

/// One warm-up stage (turn_on() arms both, FIELD_GEN_WARMUP_STAGE apart): the fields go up at the third.
/obj/machinery/field_generator/proc/warm_up_step()
	if(active != 1)
		return
	set_warming_up(warming_up + 1)
	update_icon()
	if(warming_up >= 3)
		start_fields()
		set_light(light_range_on, light_power_on)

/obj/machinery/field_generator/proc/calc_power()
	if(Varpower)
		return 1

	update_icon()
	if(src.power > FIELD_GEN_MAX_POWER)
		src.power = FIELD_GEN_MAX_POWER

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
	if(src.state != FLOOR_WELD_WELDED || !anchored)
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
		if(!T || T.density)//We cant shoot a field though this (or off the map)
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
		spent(F)
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
	var/temp = 1 //stops spam
	for(var/obj/singularity/O in REGISTRY_MEMBERS(REGISTRY_SINGULARITIES))
		if(O.last_warning && temp)
			if(ELAPSED(O, last_warning, CLOCK_WORLD) > 5 SECONDS) //to stop message-spam
				temp = 0
				admin_chat_message(message = "SINGUL/TESLOOSE!", color = "#FF2222")
				message_admins("A singulo exists and a containment field has failed.")
				investigate_log("has " + span_red("failed") + " whilst a singulo exists.","singulo")
				log_game("FIELDGEN([x],[y],[z]) Containment failed while singulo/tesla exists.")
		EXPIRY_STAMP(O, last_warning, CLOCK_WORLD)

/obj/machinery/field_generator/pre_mapped
	state = FLOOR_WELD_WELDED //Start welded.
	anchored = TRUE

#undef FIELD_GEN_MAX_POWER
#undef FIELD_GEN_WARMUP_STAGE
