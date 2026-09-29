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

/obj/machinery/shield_gen/advanced
	name = "advanced bubble shield generator"
	desc = "A machine that generates a field of energy optimized for blocking meteorites when activated.  This version comes with a more efficent shield matrix."
	energy_conversion_rate = 0.0012

// Capacitors feeding this generator (two-sided with each capacitor's owned_gen).
REL_PAIR_LIST(/obj/machinery/shield_gen, capacitors, owned_gen)

/obj/machinery/shield_gen/Initialize(mapload)
	if(anchored)
		for(var/obj/machinery/shield_capacitor/cap in range(1, src))
			if(!cap.anchored)
				continue
			if(cap.owned_gen())
				continue
			if(get_dir(cap, src) == cap.dir)
				rel_set(cap, "owned_gen", src)
	own_set(src, "shield_hum", new /datum/looping_sound/shield_generator(list(src), FALSE))
	. = ..()
	make_climbable()


DECLARE_EMAG_REPEATABLE(/obj/machinery/shield_gen, PROC_REF(on_emag), null)
/obj/machinery/shield_gen/proc/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	if(prob(75))
		set_locked(!src.locked)
		to_chat(user, "Controls are now [src.locked ? "locked." : "unlocked."]")
		. = 1
	fx_sparks(src, 5)

/// Old attackby: swipe an ID to lock/unlock the controls.
/datum/interaction/machine_item/shield_gen_swipe_id
	id = "shield_gen_swipe_id"
	name = "Swipe ID"
	category = INTERACTION_CAT_LOCK
	held_type = /obj/item/card/id
	effect = /obj/machinery/shield_gen/proc/interaction_swipe_id

/obj/machinery/shield_gen/proc/interaction_swipe_id(mob/user, obj/item/card/id/C, datum/interaction/interaction)
	if((ACCESS_CAPTAIN in C.GetAccess()) || (ACCESS_SECURITY in C.GetAccess()) || (ACCESS_ENGINE in C.GetAccess()))
		set_locked(!src.locked)
		to_chat(user, "Controls are now [src.locked ? "locked." : "unlocked."]")
	else
		to_chat(user, span_red("Access denied."))
	return TRUE

/obj/machinery/shield_gen/wrench_act(mob/user, obj/item/W)
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
				rel_set(cap, "owned_gen", src)
	else
		rel_clear(src, "capacitors")
	return ITEM_INTERACT_SUCCESS

/obj/machinery/shield_gen/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/shield_gen_swipe_id,
		/datum/interaction/machine_hand/ungated/shield_gen_open_ui,
	)
	..()

/// Old attack_hand (never called ..()): open the interface unless broken.
/datum/interaction/machine_hand/ungated/shield_gen_open_ui
	id = "shield_gen_open_ui"
	name = "Use"
	requires = list(REQ_REACH_ADJACENT, REQ_ON(PRED_TARGET, /obj/machinery/shield_gen/proc/shield_gen_not_broken, null))
	effect = /obj/machinery/shield_gen/proc/interaction_open_ui_impl

/obj/machinery/shield_gen/proc/shield_gen_not_broken(mob/actor, atom/target, obj/item/held)
	return !has_stat(BROKEN)

/obj/machinery/shield_gen/proc/interaction_open_ui_impl(mob/user, obj/item/held, datum/interaction/interaction)
	tgui_interact(user)
	return TRUE

DECLARE_UI(/obj/machinery/shield_gen, "ShieldGenerator")

/obj/machinery/shield_gen/tgui_status(mob/user)
	if(has_stat(BROKEN))
		return STATUS_CLOSE
	return ..()

UI_DATA_REPLACE(/obj/machinery/shield_gen, "merge:ui_data_obj_machinery_shield_gen{capacitors:list,active:num,failing:bool,radius:num,max_radius:num,z_range:num,max_z_range:num,average_field_strength:num,target_field_strength:num,max_field_strength:num,shields:num,upkeep:num,strengthen_rate:num,max_strengthen_rate:num,gen_power:num}")

/// The computed part of /obj/machinery/shield_gen's window data (declared on its UI_DATA row).
/obj/machinery/shield_gen/proc/ui_data_obj_machinery_shield_gen(mob/user, datum/tgui/ui, datum/tgui_state/state)
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

/obj/machinery/shield_gen/machine_step()
	if (!anchored && active)
		toggle()
	if(!active && !length(field))
		return PROCESS_KILL

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
				MACHINE_WAKE(capacitor)

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

UI_ACT(/obj/machinery/shield_gen, "toggle", ui_act_toggle)
UI_ACT_PROC(/obj/machinery/shield_gen, ui_act_toggle)
	if (!active && !anchored)
		to_chat(ui.user, span_red("The [src] needs to be firmly secured to the floor first."))
		return
	toggle()
	. = TRUE

UI_ACT(/obj/machinery/shield_gen, "change_radius", ui_act_change_radius, UI_ARG_NUM("val"))
UI_ACT_PROC(/obj/machinery/shield_gen, ui_act_change_radius)
	field_radius = clamp(params["val"], 0, max_field_radius)
	. = TRUE

UI_ACT(/obj/machinery/shield_gen, "strengthen_rate", ui_act_strengthen_rate, UI_ARG_NUM("val"))
UI_ACT_PROC(/obj/machinery/shield_gen, ui_act_strengthen_rate)
	strengthen_rate = clamp(params["val"], 0, max_strengthen_rate)
	. = TRUE

UI_ACT(/obj/machinery/shield_gen, "target_field_strength", ui_act_target_field_strength, UI_ARG_NUM("val"))
UI_ACT_PROC(/obj/machinery/shield_gen, ui_act_target_field_strength)
	target_field_strength = clamp(params["val"], 1, max_field_strength)
	. = TRUE

UI_ACT(/obj/machinery/shield_gen, "z_range", ui_act_z_range, UI_ARG_NUM("val", 0, 10))
UI_ACT_PROC(/obj/machinery/shield_gen, ui_act_z_range)
	z_range = params["val"]
	. = TRUE

DAMAGE_REACTION(/obj/machinery/shield_gen, DAMAGE_EXPLOSION, PROC_REF(shield_gen_blast_trip))

/// A blast trips a running generator off.
/obj/machinery/shield_gen/proc/shield_gen_blast_trip(datum/damage_packet/packet)
	if(active)
		toggle()

/obj/machinery/shield_gen/proc/toggle()
	set background = 1
	set_active(!active)
	if(active)
		MACHINE_WAKE(src)
	if(active)
		var/list/covered_turfs = get_shielded_turfs()
		var/turf/T = get_turf(src)
		if(T in covered_turfs)
			covered_turfs.Remove(T)
		for(var/turf/O in covered_turfs)
			own_add(src, "field", new /obj/effect/energy_field(O, src))
		covered_turfs = null

		for(var/mob/M in view(5,src))
			to_chat(M, "[icon2html(src, M.client)] You hear heavy droning start up.")
		for(var/obj/effect/energy_field/E in field) // Update the icons here to ensure all the shields have been made already.
			E.update_icon()
		shield_hum.start()
	else
		own_clear(src, "field", OWN_DELETE)

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
			own_add(src, "field", new /obj/effect/energy_field(O, src))

DECLARE_APPEARANCE_PROC(/obj/machinery/shield_gen, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/shield_gen/appearance_overlays()
	. = list()
	if(has_stat(BROKEN))
		icon_state = "broke"
		set_light(0)
		shield_hum.stop()
	else
		if (src.active)
			icon_state = "generator1"
			set_light(4, 2, "#00CCFF")
		else
			icon_state = "generator0"
			set_light(0)

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

/// Its declared start condition (machine_pipeline.dm, materialize_wakes()).
/obj/machinery/shield_gen/step_start_condition()
	return active

// Remote shield buttons find generators by id (REL_KEYED sources).
KEYED_TARGET(/obj/machinery/shield_gen, id)
