/obj/machinery/shield_gen
	name = "bubble shield generator"
	desc = "A machine that generates a field of energy optimized for blocking meteorites when activated."
	icon = 'icons/obj/machines/shielding.dmi'
	icon_state = "generator0"
	active = 0
	var/field_radius = 3
	var/max_field_radius = 150
	var/list/field
	density = TRUE
	locked = 0
	var/average_field_strength = 0
	var/strengthen_rate = 0.2
	var/max_strengthen_rate = 0.5	//the maximum rate that the generator can increase the average field strength
	var/dissipation_rate = 0.030	//the percentage of the shield strength that needs to be replaced each second
	var/min_dissipation = 0.01		//will dissipate by at least this rate in renwicks per field tile (otherwise field would never dissipate completely as dissipation is a percentage)
	var/powered = 0
	var/check_powered = 1
	var/list/capacitors
	var/target_field_strength = 10
	var/max_field_strength = 10
	var/time_since_fail = 100
	var/energy_conversion_rate = 0.0006	//how many renwicks per watt?  Higher numbers equals more effiency.
	var/z_range = 0 // How far 'up and or down' to extend the shield to, in z-levels.  Only works on MultiZ supported z-levels.
	use_power = USE_POWER_OFF	//doesn't use APC power
	interact_offline = TRUE // don't check stat & NOPOWER|BROKEN for our UI. We check BROKEN ourselves.
	var/id //for button usage
	var/datum/looping_sound/shield_generator/shield_hum

CAPABILITIES(/obj/machinery/shield_gen)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(active), wakes_on = list(nameof(active)))
	owns_one(nameof(shield_hum), /datum/looping_sound/shield_generator, starts = /datum/looping_sound/shield_generator)
	owns_many(nameof(field))
	climb()
	interface("ShieldGenerator")
	emag(then(PROC_REF(on_emag)), repeatable = TRUE, powered = FALSE)
	without("ui_open")
	op("toggle", ui_act("toggle"), then(PROC_REF(ui_act_toggle)))
	op("change_radius", ui_act("change_radius", arg("val", num())), then(PROC_REF(ui_act_change_radius)))
	op("strengthen_rate", ui_act("strengthen_rate", arg("val", num())), then(PROC_REF(ui_act_strengthen_rate)))
	op("target_field_strength", ui_act("target_field_strength", arg("val", num())), then(PROC_REF(ui_act_target_field_strength)))
	op("z_range", ui_act("z_range", arg("val", num(0, 10))), then(PROC_REF(ui_act_z_range)))
	op("use_wrench", tool(TOOL_WRENCH), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(wrench_used)))
	op("shield_gen_swipe_id", item(/obj/item/card/id), priority(OP_PRIORITY_DEFAULT - 1), label("Swipe ID"), then(PROC_REF(interaction_swipe_id)))
	op("shield_gen_open_ui", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), needs(req_bool(PROC_REF(shield_gen_not_broken_holds), because = PROC_REF(shield_gen_not_broken_refusal))), then(PROC_REF(interaction_open_ui_impl)))
	on_notice(/datum/notice/hit/explosion, then(PROC_REF(shield_gen_blast_trip)))

/obj/machinery/shield_gen/advanced
	name = "advanced bubble shield generator"
	desc = "A machine that generates a field of energy optimized for blocking meteorites when activated.  This version comes with a more efficent shield matrix."
	energy_conversion_rate = 0.0012

// Capacitors feeding this generator (two-sided with each capacitor's owned_gen).
/obj/machinery/shield_gen/relations()
	. = ..()
	// Remote shield buttons find generators by id (REL_KEYED sources). Moves to the button's ref_many(by = nameof(id)) with code/game/machinery/door_control.dm.
	. += rel_key(nameof(id))

/obj/machinery/shield_gen/Initialize(mapload)
	if(anchored)
		for(var/obj/machinery/shield_capacitor/cap in range(1, src))
			if(!cap.anchored)
				continue
			if(cap.owned_gen())
				continue
			if(get_dir(cap, src) == cap.dir)
				rel_set(cap, nameof(cap.owned_gen), src)
	. = ..()

/// Maintains its field while on (toggle() raises it and drops the whole field when switched off).
/obj/machinery/shield_gen/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	. = OP_DECLINE
	if(prob(75))
		set_locked(!src.locked)
		to_chat(user, "Controls are now [src.locked ? "locked." : "unlocked."]")
		. = OP_OK
	fx_sparks(src, 5)

/obj/machinery/shield_gen/proc/interaction_swipe_id(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/card/id/C = A.held
	if((ACCESS_CAPTAIN in C.GetAccess()) || (ACCESS_SECURITY in C.GetAccess()) || (ACCESS_ENGINE in C.GetAccess()))
		set_locked(!src.locked)
		to_chat(user, "Controls are now [src.locked ? "locked." : "unlocked."]")
	else
		to_chat(user, span_red("Access denied."))
	return OP_OK

/obj/machinery/shield_gen/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	set_anchored(!anchored)
	playsound(src, W.usesound, 75, 1)
	act_message(user, src, others = span_blue("[icon2html(src,viewers(src))] %T% has been [anchored?"bolted to the floor":"unbolted from the floor"] by %U%."))

	if(active)
		toggle()
	if(anchored)
		for(var/obj/machinery/shield_capacitor/cap in range(1, src))
			if(cap.owned_gen())
				continue
			if(get_dir(cap, src) == cap.dir && src.anchored)
				rel_set(cap, nameof(cap.owned_gen), src)
	else
		rel_clear(src, nameof(capacitors))
	return OP_OK

/// Requirement (was REQ_* shield_gen_not_broken): the legacy check answers TRUE to pass.
/obj/machinery/shield_gen/proc/shield_gen_not_broken_holds(datum/act/op/A)
	var/answer = shield_gen_not_broken(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why shield_gen_not_broken_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/shield_gen/proc/shield_gen_not_broken_refusal(datum/act/op/A)
	var/answer = shield_gen_not_broken(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/obj/machinery/shield_gen/proc/shield_gen_not_broken(mob/actor, atom/target, obj/item/held)
	return !broken_now()

/obj/machinery/shield_gen/proc/interaction_open_ui_impl(datum/act/op/A)
	var/mob/user = A.actor
	tgui_interact(user)
	return OP_OK

/obj/machinery/shield_gen/tgui_status(mob/user)
	if(broken_now())
		return STATUS_CLOSE
	return ..()

/// /obj/machinery/shield_gen's window data.
/obj/machinery/shield_gen/ui_data(datum/act/eval/A)
	var/list/lockedData = list()

	if(!locked)
		var/list/caps = list()
		for(var/obj/machinery/shield_capacitor/C in capacitors)
			caps.Add(list(list(
				"active" = C.active,
				"stored_charge" = C.stored_charge,
				"max_charge" = C.max_charge,
				"failing" = (C.time_since_fail <= 2),
			)))
		lockedData["capacitors"] = caps

		lockedData["active"] = active
		lockedData["failing"] = (time_since_fail <= 2)
		lockedData["radius"] = field_radius
		lockedData["max_radius"] = max_field_radius
		lockedData["z_range"] = z_range
		lockedData["max_z_range"] = 10
		lockedData["average_field_strength"] = average_field_strength
		lockedData["target_field_strength"] = target_field_strength
		lockedData["max_field_strength"] = max_field_strength
		lockedData["shields"] = LAZYLEN(field)
		lockedData["upkeep"] = round(length(field) * max(average_field_strength * dissipation_rate, min_dissipation) / energy_conversion_rate)
		lockedData["strengthen_rate"] = strengthen_rate
		lockedData["max_strengthen_rate"] = max_strengthen_rate
		lockedData["gen_power"] = round(length(field) * min(strengthen_rate, target_field_strength - average_field_strength) / energy_conversion_rate)

	return list("locked" = locked, "lockedData" = lockedData)

/obj/machinery/shield_gen/proc/work_step(datum/act/timer/A)
	if (!anchored)
		toggle()
		return

	average_field_strength = max(average_field_strength, 0)

	if(length(field))
		time_since_fail++
		var/total_renwick_increase = 0 //the amount of renwicks that the generator can add this tick, over the entire field
		var/renwick_upkeep_per_field = max(average_field_strength * dissipation_rate, min_dissipation)

		//figure out how much energy we need to draw from the capacitor
		if(active && length(capacitors))
			// Get a list of active capacitors to drain from.
			var/list/active_capacitors = list()
			for(var/obj/machinery/shield_capacitor/capacitor in capacitors) // Some capacitors might be off.  Exclude them.
				if(capacitor.active && capacitor.stored_charge > 0)
					active_capacitors |= capacitor

			var/target_renwick_increase = min(target_field_strength - average_field_strength, strengthen_rate) + renwick_upkeep_per_field //per field tile

			var/required_energy = length(field) * target_renwick_increase / energy_conversion_rate

			// Gets the charge for all capacitors
			var/sum_charge = 0
			for(var/obj/machinery/shield_capacitor/capacitor in active_capacitors)
				sum_charge += capacitor.stored_charge

			var/assumed_charge = min(sum_charge, required_energy)
			total_renwick_increase = assumed_charge * energy_conversion_rate

			for(var/obj/machinery/shield_capacitor/capacitor in active_capacitors)
				capacitor.stored_charge -= max(assumed_charge / active_capacitors.len, 0) // Drain from all active capacitors evenly.
				work_start(capacitor)

		else
			renwick_upkeep_per_field = max(renwick_upkeep_per_field, 0.5)

		var/renwick_increase_per_field = total_renwick_increase/field.len //per field tile

		average_field_strength = 0 //recalculate the average field strength
		for(var/obj/effect/energy_field/E in field)
			E.set_max_strength(target_field_strength)
			var/amount_to_strengthen = renwick_increase_per_field - renwick_upkeep_per_field
			if(E.ticks_recovering > 0 && amount_to_strengthen > 0)
				E.adjust_strength( min(amount_to_strengthen / 10, 0.1), 0 )
				E.ticks_recovering -= 1
			else
				E.adjust_strength(amount_to_strengthen, 0)

			average_field_strength += E.get_strength()

		average_field_strength /= length(field)
		if(average_field_strength < 1)
			time_since_fail = 0
	else
		average_field_strength = 0

/obj/machinery/shield_gen/proc/ui_act_toggle(datum/act/op/A)
	var/mob/user = A.actor
	if (!active && !anchored)
		to_chat(user, span_red("The [src] needs to be firmly secured to the floor first."))
		return
	toggle()
	. = TRUE

/obj/machinery/shield_gen/proc/ui_act_change_radius(datum/act/op/A, val)
	field_radius = clamp(val, 0, max_field_radius)
	. = TRUE

/obj/machinery/shield_gen/proc/ui_act_strengthen_rate(datum/act/op/A, val)
	strengthen_rate = clamp(val, 0, max_strengthen_rate)
	. = TRUE

/obj/machinery/shield_gen/proc/ui_act_target_field_strength(datum/act/op/A, val)
	target_field_strength = clamp(val, 1, max_field_strength)
	. = TRUE

/obj/machinery/shield_gen/proc/ui_act_z_range(datum/act/op/A, val)
	z_range = val
	. = TRUE


/// A blast trips a running generator off.
/obj/machinery/shield_gen/proc/shield_gen_blast_trip(datum/act/A)
	if(active)
		toggle()

/obj/machinery/shield_gen/proc/toggle()
	set background = 1
	set_active(!active)
	if(active)
		var/list/covered_turfs = get_shielded_turfs()
		var/turf/T = get_turf(src)
		if(T in covered_turfs)
			covered_turfs.Remove(T)
		for(var/turf/O in covered_turfs)
			rel_add(src, nameof(field), new /obj/effect/energy_field(O, src))
		covered_turfs = null

		for(var/mob/M in view(5,src))
			to_chat(M, "[icon2html(src, M.client)] You hear heavy droning start up.")
		shield_hum.start()
	else
		rel_clear(src, nameof(field))

		for(var/mob/M in view(5,src))
			to_chat(M, "[icon2html(src, M.client)] You hear heavy droning fade out.")
		shield_hum.stop()

/obj/machinery/shield_gen/proc/fill_diffused()
	if(active)
		var/list/covered_turfs = get_shielded_turfs()
		var/turf/T = get_turf(src)
		if(T in covered_turfs)
			covered_turfs.Remove(T)
		for(var/turf/O in covered_turfs)
			if(locate(/obj/effect/energy_field, O) || locate(/obj/machinery/pointdefense, orange(2, O)))
				continue
			rel_add(src, nameof(field), new /obj/effect/energy_field(O, src))

/obj/machinery/shield_gen/draw(datum/look/look)
	..()
	if(broken_now())
		look.state("broke")
		look.light_off()
		look.effect(PROC_REF(look_effect_shield_hum_stop))
	else
		if (src.active)
			look.state("generator1")
			look.light(4, 2, "#00CCFF")
		else
			look.state("generator0")
			look.light_off()

/// An effect of the look (the draw sweep): run once the look is applied, not while it is drawn.
/obj/machinery/shield_gen/proc/look_effect_shield_hum_stop()
	shield_hum?.stop()

//grab the border tiles in a circle around this machine
/obj/machinery/shield_gen/proc/get_shielded_turfs()
	var/list/out = list()

	var/turf/T = get_turf(src)
	if (!T)
		return

	out += get_shielded_turfs_on_z_level(T)

	if(z_range)
		var/i = z_range
		while(HasAbove(T.z) && i)
			T = GetAbove(T)
			i--
			if(istype(T))
				out += get_shielded_turfs_on_z_level(T)

		T = get_turf(src)
		i = z_range

		while(HasBelow(T.z) && i)
			T = GetBelow(T)
			i--
			if(istype(T))
				out += get_shielded_turfs_on_z_level(T)

	return out

/obj/machinery/shield_gen/proc/get_shielded_turfs_on_z_level(turf/gen_turf)
	var/list/out = list()

	if (!gen_turf)
		return

	var/turf/T
	for (var/x_offset = -field_radius; x_offset <= field_radius; x_offset++)
		T = locate(gen_turf.x + x_offset, gen_turf.y - field_radius, gen_turf.z)
		if (T) out += T

		T = locate(gen_turf.x + x_offset, gen_turf.y + field_radius, gen_turf.z)
		if (T) out += T

	for (var/y_offset = -field_radius+1; y_offset < field_radius; y_offset++)
		T = locate(gen_turf.x - field_radius, gen_turf.y + y_offset, gen_turf.z)
		if (T) out += T

		T = locate(gen_turf.x + field_radius, gen_turf.y + y_offset, gen_turf.z)
		if (T) out += T

	return out

// === merged from shield_gen_chomp.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/machinery/shield_gen
	icon = 'icons/obj/machines/shielding.dmi'
