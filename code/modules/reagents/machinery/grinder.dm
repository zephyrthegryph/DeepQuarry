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
	var/obj/item/reagent_containers/beaker = null
	var/limit = 10
	var/list/holdingitems

	var/static/radial_examine = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_examine")
	var/static/radial_eject = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_eject")
	var/static/radial_grind = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_grind")

DECLARE_DEFAULT_CHILD(/obj/machinery/reagentgrinder, "beaker", /obj/item/reagent_containers/glass/beaker/large)

/obj/machinery/reagentgrinder/Initialize(mapload)
	. = ..()
	default_apply_parts()

/obj/machinery/reagentgrinder/examine(mob/user)
	. = ..()
	if(!in_range(user, src) && !issilicon(user) && !isobserver(user))
		. += span_warning("You're too far away to examine [src]'s contents and display!")
		return

	if(om_busy(src))
		. += span_warning("\The [src] is operating.")
		return

	if(beaker || length(holdingitems))
		. += span_notice("\The [src] contains:")
		if(beaker)
			. += span_notice("- \A [beaker].")
		for(var/obj/item/O as anything in holdingitems)
			. += span_notice("- \A [O.name].")

	if(operable())
		. += span_notice("The status display reads:") + "\n"
		if(beaker)
			for(var/datum/reagent/R in beaker.reagents.reagent_list)
				. += span_notice("- [R.volume] units of [R.name].")

APPEARANCE_TEMPLATE(/obj/machinery/reagentgrinder, "juicer{beaker?1:0}")

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
			user.drop_item()
			O.forceMove(src)
			own_set(src, "beaker", O) // CONTAINED: in our contents first
			update_icon()
			return TRUE

	if(holdingitems && length(holdingitems) >= limit)
		to_chat(user, "The machine cannot hold anymore items.")
		return TRUE

	if(!istype(O))
		return TRUE

	if(istype(O,/obj/item/storage/bag/plants))
		var/obj/item/storage/bag/plants/bag = O
		var/failed = 1
		for(var/obj/item/G in contents_of(O))
			if(!G.reagents || !G.reagents.total_volume)
				continue
			failed = 0
			bag.remove_from_storage(G, src)
			own_add(src, "holdingitems", G)
			if(holdingitems && length(holdingitems) >= limit)
				break

		if(failed)
			to_chat(user, "Nothing in the plant bag is usable.")
			return TRUE

		if(!contents_count(O))
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
	O.forceMove(src)
	own_add(src, "holdingitems", O)
	// start
	if(istype(O,/obj/item/stack/material/supermatter))
		var/obj/item/stack/material/supermatter/S = O
		set_light(l_range = max(1, S.get_amount()/10), l_power = max(1, S.get_amount()/10), l_color = "#8A8A00")
		om_after(src, 30 SECONDS, PROC_REF(puny_protons))
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
	if(om_busy(src) || user.incapacitated())
		return

	var/list/options = list()

	if(beaker || length(holdingitems))
		options["eject"] = radial_eject

	if(isAI(user))
		if(has_stat(NOPOWER))
			return
		options["examine"] = radial_examine

	// if there is no power or it's broken, the procs will fail but the buttons will still show
	if(length(holdingitems))
		options["grind"] = radial_grind

	om_ask(user, /datum/om/prompt/choice/radial, PROC_REF(radial_option_chosen), choices = options, anchor = src, require_near = !issilicon(user), autopick_single_option = FALSE)

/obj/machinery/reagentgrinder/proc/radial_option_chosen(datum/om/prompt/choice/radial/ask)
	var/mob/user = ask.answerer
	// post choice verification
	if(!user || om_busy(src) || (isAI(user) && has_stat(NOPOWER)) || user.incapacitated())
		return

	switch(ask.choice)
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
		O.forceMove(src.loc)
		own_take_member(src, "holdingitems", O)
	own_take_all(src, "holdingitems")
	if(beaker)
		replace_beaker(user)

/obj/machinery/reagentgrinder/proc/grind()

	power_change()
	if(!operable())
		return

	// Sanity check.
	if (!beaker || (beaker && beaker.reagents.total_volume >= beaker.reagents.maximum_volume))
		return

	play_sfx(src, SFX_MACHINES_BLENDER)
	om_hold_busy(src, 6 SECONDS)

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
		own_take(src, "beaker")
	if(new_beaker)
		new_beaker.forceMove(src) // CONTAINED: in our contents first
		own_set(src, "beaker", new_beaker)
	update_icon()
	return TRUE

OWN(/obj/machinery/reagentgrinder, beaker, OWN_CONTAINED)
