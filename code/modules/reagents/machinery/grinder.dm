/obj/machinery/reagentgrinder
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "All-In-One Grinder"
	desc = "Grinds stuff into itty bitty bits."
	icon = 'icons/obj/kitchen.dmi'
	icon_state = "juicer1"
	density = FALSE
	anchored = FALSE
	use_power = USE_POWER_IDLE
	idle_power_usage = 5
	active_power_usage = 100
	circuit = /obj/item/circuitboard/grinder
	var/inuse = 0
	var/obj/item/reagent_containers/beaker = null
	var/limit = 10
	var/list/holdingitems = list()

	var/static/radial_examine = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_examine")
	var/static/radial_eject = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_eject")
	var/static/radial_grind = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_grind")
	// var/static/radial_juice = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_juice")
	// var/static/radial_mix = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_mix")

/obj/machinery/reagentgrinder/Initialize(mapload)
	. = ..()
	beaker = new /obj/item/reagent_containers/glass/beaker/large(src)
	default_apply_parts()

/obj/machinery/reagentgrinder/examine(mob/user)
	. = ..()
	if(!in_range(user, src) && !issilicon(user) && !isobserver(user))
		. += span_warning("You're too far away to examine [src]'s contents and display!")
		return

	if(inuse)
		. += span_warning("\The [src] is operating.")
		return

	if(beaker || length(holdingitems))
		. += span_notice("\The [src] contains:")
		if(beaker)
			. += span_notice("- \A [beaker].")
		for(var/obj/item/O as anything in holdingitems)
			. += span_notice("- \A [O.name].")

	if(!(stat & (NOPOWER|BROKEN)))
		. += span_notice("The status display reads:") + "\n"
		if(beaker)
			for(var/datum/reagent/R in beaker.reagents.reagent_list)
				. += span_notice("- [R.volume] units of [R.name].")

/obj/machinery/reagentgrinder/update_icon()
	icon_state = "juicer"+num2text(!isnull(beaker))
	return

/obj/machinery/reagentgrinder/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/reagentgrinder_attackby,
		/datum/interaction/machine_alt/reagentgrinder_replace_beaker,
		/datum/interaction/machine_hand/ungated/reagentgrinder_interact,
	)
	..()

/// Old attackby, kept whole: every branch returns without ever calling ..().
/datum/interaction/machine_item/reagentgrinder_attackby
	id = "reagentgrinder_attackby"
	name = "Use"
	held_type = /obj/item
	effect = /obj/machinery/reagentgrinder/proc/interaction_attackby

/obj/machinery/reagentgrinder/proc/interaction_attackby(mob/user, obj/item/O, datum/interaction/interaction)
	if (istype(O,/obj/item/reagent_containers/glass) || \
		istype(O,/obj/item/reagent_containers/food/drinks/glass2) || \
		istype(O,/obj/item/reagent_containers/food/drinks/shaker))

		if (beaker)
			return TRUE
		else
			beaker =  O
			user.drop_item()

			O.loc = src
			update_icon()
			return TRUE

	if(holdingitems && holdingitems.len >= limit)
		to_chat(user, "The machine cannot hold anymore items.")
		return TRUE

	if(!istype(O))
		return TRUE

	if(istype(O,/obj/item/storage/bag/plants))
		var/obj/item/storage/bag/plants/bag = O
		var/failed = 1
		for(var/obj/item/G in O.contents)
			if(!G.reagents || !G.reagents.total_volume)
				continue
			failed = 0
			bag.remove_from_storage(G, src)
			holdingitems += G
			if(holdingitems && holdingitems.len >= limit)
				break

		if(failed)
			to_chat(user, "Nothing in the plant bag is usable.")
			return TRUE

		if(!O.contents.len)
			to_chat(user, "You empty \the [O] into \the [src].")
		else
			to_chat(user, "You fill \the [src] from \the [O].")

		return TRUE

	if(istype(O,/obj/item/gripper))
		var/obj/item/gripper/B = O	//B, for Borg.
		var/obj/item/wrapped = B.get_wrapped_item()
		if(!wrapped)
			to_chat(user, "\The [B] is not holding anything.")
			return TRUE
		else
			to_chat(user, "You use \the [B] to load \the [src] with \the [wrapped].")

		return TRUE

	if(!GLOB.sheet_reagents[O.type] && !GLOB.ore_reagents[O.type] && (!O.reagents || !O.reagents.total_volume))
		to_chat(user, "\The [O] is not suitable for blending.")
		return TRUE

	user.remove_from_mob(O)
	O.loc = src
	holdingitems += O
	// start
	if(istype(O,/obj/item/stack/material/supermatter))
		var/obj/item/stack/material/supermatter/S = O
		set_light(l_range = max(1, S.get_amount()/10), l_power = max(1, S.get_amount()/10), l_color = "#8A8A00")
		addtimer(CALLBACK(src, PROC_REF(puny_protons)), 30 SECONDS)
	// end
	return TRUE

/obj/machinery/reagentgrinder/screwdriver_act(mob/user, obj/item/tool)
	if(!beaker)
		return ..()
	return ..()

/obj/machinery/reagentgrinder/crowbar_act(mob/user, obj/item/tool)
	if(!beaker)
		return ..()
	return ..()

/// Old click_alt: `. = ..()` was never checked, so its own logic always ran afterward.
/datum/interaction/machine_alt/reagentgrinder_replace_beaker
	id = "reagentgrinder_replace_beaker"
	name = "Replace beaker"
	requires = list(REQ_REACH_ADJACENT)
	effect = /obj/machinery/reagentgrinder/proc/interaction_replace_beaker

/obj/machinery/reagentgrinder/proc/interaction_replace_beaker(mob/user, obj/item/held, datum/interaction/interaction)
	if(user.incapacitated() || !Adjacent(user))
		return TRUE
	replace_beaker(user)
	return TRUE

/// Old attack_hand: never called ..().
/datum/interaction/machine_hand/ungated/reagentgrinder_interact
	id = "reagentgrinder_interact"
	name = "Use"
	effect = /obj/machinery/reagentgrinder/proc/interaction_use

/obj/machinery/reagentgrinder/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	interact(user)
	return TRUE

/obj/machinery/reagentgrinder/interact(mob/user) // The microwave Menu //I am reasonably certain that this is not a microwave
	if(inuse || user.incapacitated())
		return

	var/list/options = list()

	if(beaker || length(holdingitems))
		options["eject"] = radial_eject

	if(isAI(user))
		if(stat & NOPOWER)
			return
		options["examine"] = radial_examine

	// if there is no power or it's broken, the procs will fail but the buttons will still show
	if(length(holdingitems))
		options["grind"] = radial_grind

	var/choice = show_radial_menu(user, src, options, require_near = !issilicon(user), autopick_single_option = FALSE)

	// post choice verification
	if(inuse || (isAI(user) && stat & NOPOWER) || user.incapacitated())
		return

	switch(choice)
		if("eject")
			eject(user)
		if("grind")
			grind(user)
		if("examine")
			examine(user)

/obj/machinery/reagentgrinder/proc/eject(mob/user)
	if(user.incapacitated())
		return
	for(var/obj/item/O in holdingitems)
		O.loc = src.loc
		holdingitems -= O
	holdingitems.Cut()
	if(beaker)
		replace_beaker(user)

/obj/machinery/reagentgrinder/proc/grind()

	power_change()
	if(stat & (NOPOWER|BROKEN))
		return

	// Sanity check.
	if (!beaker || (beaker && beaker.reagents.total_volume >= beaker.reagents.maximum_volume))
		return

	playsound(src, 'sound/machines/blender.ogg', 50, 1)
	inuse = 1

	// Reset the machine.
	spawn(60)
		inuse = 0

	// Process.
	grind_items_to_reagents(holdingitems,beaker.reagents)

/obj/machinery/reagentgrinder/proc/replace_beaker(mob/living/user, obj/item/reagent_containers/new_beaker)
	if(!user)
		return FALSE
	if(beaker)
		if(!user.incapacitated() && Adjacent(user))
			user.put_in_hands(beaker)
		else
			beaker.forceMove(drop_location())
		beaker = null
	if(new_beaker)
		beaker = new_beaker
	update_icon()
	return TRUE
