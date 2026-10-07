GLOBAL_LIST_EMPTY(grub_machine_overlays)

/mob/living/simple_mob/animal/solargrub_larva
	name = "solargrub larva"
	desc = "A tiny wormy thing that can grow to massive sizes under the right conditions."
	catalogue_data = list(/datum/category_item/catalogue/fauna/solargrub)
	icon = 'icons/mob/vore.dmi'
	icon_state = "grublarva"
	icon_living = "grublarva"
	icon_dead = "grublarva-dead"

	endurance = 5
	movement_cooldown = 0

	melee_damage_lower = 1	// This is a tiny worm. It will nibble and thats about it.
	melee_damage_upper = 1

	meat_amount = 1
	meat_type = /obj/item/reagent_containers/food/snacks/meat/grubmeat
	butchery_loot = list()		// No hides

	faction = FACTION_GRUBS

	response_help = "pats"
	response_disarm = "nudges"
	response_harm = "stomps on"

	mob_size = MOB_MINISCULE
	pass_flags = PASSTABLE
	can_pull_size = ITEMSIZE_TINY
	can_pull_mobs = MOB_PULL_NONE
	density = FALSE


	var/static/list/ignored_machine_types = list(
		/obj/machinery/atmospherics/unary/vent_scrubber,
		/obj/machinery/door/firedoor,
		/obj/machinery/button/windowtint
		)

	var/image/machine_effect

	var/obj/machinery/abstract_grub_machine/powermachine
	var/power_drained = 0

	var/tracked = FALSE

	glow_override = TRUE

/mob/living/simple_mob/animal/solargrub_larva/on_death(gibbed)
	powermachine.set_draining(0)
	set_light(0)
	return ..()

REGISTRY_MEMBERSHIP(/mob/living/simple_mob/animal/solargrub_larva, REGISTRY_SOLARGRUBS)


/mob/living/simple_mob/animal/solargrub_larva/life_type_post_due()
	return TRUE

/mob/living/simple_mob/animal/solargrub_larva/life_type_post(datum/seq_frame/life/F)
	..()

	if(src.machine_effect && !istype(src.loc, /obj/machinery))
		QDEL_NULL(src.machine_effect)

	if(!F.alive())	// || ai_inactive
		return

	if(src.power_drained >= 7 MEGAWATTS && prob(5))
		src.expand_grub()
		return

	if(istype(src.loc, /obj/machinery))
		if(src.machine_effect && SSair.times_fired%30)
			for(var/mob/M in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
				M << src.machine_effect
		if(prob(10))
			fx_sparks(src, 3, FALSE)
		return

/mob/living/simple_mob/animal/solargrub_larva/attack_target(atom/A)
	if(istype(A, /obj/machinery) && !istype(A, /obj/machinery/atmospherics/unary/vent_pump))
		var/obj/machinery/M = A
		if(is_type_in_list(M, ignored_machine_types))
			return
		if(!M.idle_power_usage && !M.active_power_usage && !(istype(M, /obj/machinery/power/apc) || istype(M, /obj/machinery/power/smes)))
			return
		if(locate_in_list(M, /mob/living/simple_mob/animal/solargrub_larva))
			return
		enter_machine(M)
		return TRUE

	if(istype(A, /obj/machinery/atmospherics/unary/vent_pump))
		var/obj/machinery/atmospherics/unary/vent_pump/V = A
		if(is_welded(V))
			return
		do_ventcrawl(V)
		return TRUE

	return FALSE

/mob/living/simple_mob/animal/solargrub_larva/proc/enter_machine(obj/machinery/M)
	if(!istype(M))
		return
	ai_busy_begin()
	forceMove(M)
	powermachine.set_draining(2)
	act_message(src, M, null, MSG_OTHERS(span_warning("%U% finds an opening and crawls inside %T%.")))
	if(!(M.type in GLOB.grub_machine_overlays))
		generate_machine_effect(M)
	machine_effect = image(GLOB.grub_machine_overlays[M.type], M) //Can't do this the reasonable way with an overlay,
	for(var/mob/L in REGISTRY_MEMBERS(REGISTRY_PLAYERS))				//because nearly every machine updates its icon by removing all overlays first
		L << machine_effect

/mob/living/simple_mob/animal/solargrub_larva/proc/generate_machine_effect(obj/machinery/M)
	var/icon/I = new /icon(M.icon, M.icon_state)
	I.Blend(new /icon('icons/effects/blood.dmi', rgb(255,255,255)),ICON_ADD)
	I.Blend(new /icon('icons/effects/alert.dmi', "_red"),ICON_MULTIPLY)
	GLOB.grub_machine_overlays[M.type] = I

/mob/living/simple_mob/animal/solargrub_larva/proc/eject_from_machine(obj/machinery/M)
	if(!M)
		if(istype(loc, /obj/machinery))
			M = loc
		else
			return
	forceMove(get_turf(M))
	fx_sparks(src, 3, FALSE)
	if(machine_effect)
		QDEL_NULL(machine_effect)
	ai_brain?.lose_target()
	powermachine.set_draining(1)
	after(src, 3 SECONDS, PROC_REF(ai_brain_resume))
/mob/living/simple_mob/animal/solargrub_larva/proc/do_ventcrawl(obj/machinery/atmospherics/unary/vent_pump/vent)
	if(!vent)
		return
	var/obj/machinery/atmospherics/unary/vent_pump/end_vent = get_safe_ventcrawl_target(vent)
	if(!end_vent)
		return
	forceMove(vent)
	play_sfx(vent, SFX_MACHINES_VENTCRAWL)
	vent.visible_message("\The [src] wiggles into \the [vent]!")
	ventcrawl_travel(vent, end_vent, 3)

/// Travel time through the ducts; welded exits redirect up to `redirect_attempts` times.
/mob/living/simple_mob/animal/solargrub_larva/proc/ventcrawl_travel(obj/machinery/atmospherics/unary/vent_pump/vent, obj/machinery/atmospherics/unary/vent_pump/end_vent, redirect_attempts)
	var/travel_time = round(get_dist(get_turf(src), get_turf(end_vent)) / 2)
	after(src, travel_time, PROC_REF(ventcrawl_arrive), with = list(vent, end_vent, redirect_attempts), keeps_dead = TRUE)

/mob/living/simple_mob/animal/solargrub_larva/proc/ventcrawl_arrive(obj/machinery/atmospherics/unary/vent_pump/vent, obj/machinery/atmospherics/unary/vent_pump/end_vent, redirect_attempts)
	if(!end_vent)
		forceMove(get_turf(vent) || get_turf(src))
		return
	if(is_welded(end_vent) && redirect_attempts)
		if(!vent)
			forceMove(get_turf(src))
			return
		end_vent = get_safe_ventcrawl_target(vent)
		if(!end_vent)
			forceMove(get_turf(vent))
			return
		ventcrawl_travel(vent, end_vent, redirect_attempts - 1)
		return
	play_sfx(end_vent, SFX_MACHINES_VENTCRAWL)
	forceMove(get_turf(end_vent))

/mob/living/simple_mob/animal/solargrub_larva/proc/expand_grub()
	eject_from_machine()
	act_message(src, null, null, MSG_OTHERS(span_warning("%U% suddenly balloons in size!")))
	log_game("A larva has matured into a grub in area [src.loc.name] ([src.x],[src.y],[src.z]")
	var/mob/living/simple_mob/vore/solargrub/adult = new(get_turf(src))
	adult.tracked = tracked
//	grub.power_drained = power_drained //TODO
	replaced_by(src, adult)

/mob/living/simple_mob/animal/solargrub_larva/life_light_due()
	return TRUE

/mob/living/simple_mob/animal/solargrub_larva/life_light(datum/seq_frame/life/F)
	. = ..()
	if(. == 0 && !src.is_dead())
		src.set_light(1.5, 1, COLOR_YELLOW)
		return 1
	else if(src.is_dead())
		src.set_glow_override(FALSE)

/obj/machinery/abstract_grub_machine
	var/total_active_power_usage = 45 KILOWATTS
	var/list/active_power_usages = list(15 KILOWATTS, 15 KILOWATTS, 15 KILOWATTS) // ALLOW(instance_list): d: replaced per instance at runtime (1 assignments)
	var/total_idle_power_usage = 3 KILOWATTS
	var/list/idle_power_usages = list(1 KILOWATTS, 1 KILOWATTS, 1 KILOWATTS) // ALLOW(instance_list): d: replaced per instance at runtime (1 assignments)
	var/mob/living/simple_mob/animal/solargrub_larva/grub

/// 0 stopped, 1 idle drain, 2 active drain.
/obj/machinery/abstract_grub_machine/var/draining = 1
TRACKED_BRIDGED(/obj/machinery/abstract_grub_machine, draining, CHANGE_MACHINE_SETTINGS)
// ALLOW(init/INSTANCE_STATE): rolls its power use and binds to the grub it is made inside
/obj/machinery/abstract_grub_machine/Initialize(mapload)
	. = ..()
	shuffle_power_usages()
	if(!istype(loc, /mob/living/simple_mob/animal/solargrub_larva))
		return INITIALIZE_HINT_QDEL
	rel_set(src, nameof(grub), loc)

/// Drains its area's power for its grub while draining; stopped, it sleeps until the grub moves.
// Its periodic work: work_step() while it is started (code/library/machine/started_work.dm).
CAPABILITIES(/obj/machinery/abstract_grub_machine)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(draining), wakes_on = list(nameof(draining)))

/obj/machinery/abstract_grub_machine/proc/work_step(datum/act/timer/timer)
	var/area/A = get_area(src)
	if(!A)
		return
	var/list/power_list
	switch(draining)
		if(1)
			power_list = idle_power_usages
		if(2)
			power_list = active_power_usages
	for(var/i = 1 to power_list.len)
		if(A.powered(i))
			use_power(power_list[i], i)
			grub.power_drained += power_list[i]
	if(prob(5))
		shuffle_power_usages()

/obj/machinery/abstract_grub_machine/proc/shuffle_power_usages()
	total_active_power_usage = rand(30 KILOWATTS, 60 KILOWATTS)
	total_idle_power_usage = rand(1 KILOWATTS, 5 KILOWATTS)
	active_power_usages = split_into_3(total_active_power_usage)
	idle_power_usages = split_into_3(total_idle_power_usage)

/obj/item/multitool/afterattack(obj/O, mob/user, proximity)
	if(proximity)
		if(istype(O, /obj/machinery))
			var/mob/living/simple_mob/animal/solargrub_larva/grub = locate_in_list(O, /mob/living/simple_mob/animal/solargrub_larva)
			if(grub)
				grub.eject_from_machine(O)
				to_chat(user, span_warning("You disturb a grub nesting in \the [O]!"))
				return
	return ..()

/obj/item/melee/baton/afterattack(obj/O, mob/user, proximity)
	if(proximity)
		if(istype(O, /obj/machinery))
			var/mob/living/simple_mob/animal/solargrub_larva/grub = locate_in_list(O, /mob/living/simple_mob/animal/solargrub_larva)
			if(grub)
				grub.eject_from_machine(O)
				to_chat(user, span_warning("You disturb a grub nesting in \the [O]!"))
				return
	return ..()


CAPABILITIES(/mob/living/simple_mob/animal/solargrub_larva)
	owns_one(nameof(powermachine), starts = /obj/machinery/abstract_grub_machine)
	verb_entry(/mob/living/proc/ventcrawl)

