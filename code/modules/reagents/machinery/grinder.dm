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

/// TRUE for the six seconds a grind runs: a timed hold from grind().
STAT(/obj/machinery/reagentgrinder, grinding, ANY)
SOURCE_DEF(grind)

CAPABILITIES(/obj/machinery/reagentgrinder)
	owns_many(nameof(holdingitems))
	owns_one(nameof(beaker), /obj/item/reagent_containers, starts = /obj/item/reagent_containers/glass/beaker/large)
	op("use", item(/obj/item), label("Use"), then(PROC_REF(item_used)))
	op("replace_beaker", hand(), ungated(), gesture(GESTURE_ALT), label("Replace beaker"), needs(req_adjacent()), then(PROC_REF(beaker_replaced)))
	op("interact", hand(), ungated(), label("Use"), needs(req(PROC_REF(menu_available), silent = TRUE)),
		asks(/datum/prompt/choice, fields = list("choices" = computed(PROC_REF(radial_choices)), "radial" = TRUE, "autopick_single_option" = FALSE, "timeout" = 0), step = "choice"),
		then(PROC_REF(radial_chosen)))

// ALLOW(init/INSTANCE_STATE): takes the parts it was built with
/obj/machinery/reagentgrinder/Initialize(mapload)
	. = ..()
	default_apply_parts()

/obj/machinery/reagentgrinder/examine(mob/user)
	. = ..()
	if(!in_range(user, src) && !issilicon(user) && !isobserver(user))
		. += span_warning("You're too far away to examine [src]'s contents and display!")
		return

	if(grinding)
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

/obj/machinery/reagentgrinder/draw(datum/look/look)
	..()
	look.state(beaker ? "juicer1" : "juicer0")

/// The old attackby, kept whole: every branch is handled.
/obj/machinery/reagentgrinder/proc/item_used(datum/act/op/A)
	. = OP_OK
	var/mob/user = A.actor
	var/obj/item/O = A.held
	if (istype(O,/obj/item/reagent_containers/glass) || \
		istype(O,/obj/item/reagent_containers/food/drinks/glass2) || \
		istype(O,/obj/item/reagent_containers/food/drinks/shaker))

		if (beaker)
			return TRUE
		else
			if(!move_into(src, nameof(src.beaker), O, user))
				return TRUE
			return TRUE

	if(holdingitems && length(holdingitems) >= limit)
		to_chat(user, "The machine cannot hold anymore items.")
		return TRUE

	if(!istype(O))
		return TRUE

	if(istype(O,/obj/item/storage/bag/plants))
		var/failed = 1
		for(var/obj/item/G in contents_of(O))
			if(!G.reagents || !G.reagents.total_volume)
				continue
			failed = 0
			rel_add(src, nameof(src.holdingitems), G) // out of the bag: a one-call transfer
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

	if(!move_into(src, nameof(src.holdingitems), O, user))
		return TRUE
	// start
	if(istype(O,/obj/item/stack/material/supermatter))
		var/obj/item/stack/material/supermatter/S = O
		set_light(l_range = max(1, S.get_amount()/10), l_power = max(1, S.get_amount()/10), l_color = "#8A8A00")
		after(src, 30 SECONDS, PROC_REF(puny_protons))
	// end
	return TRUE

/// The old click_alt: the beaker comes out to the hand.
/obj/machinery/reagentgrinder/proc/beaker_replaced(datum/act/op/A)
	var/mob/user = A.actor
	if(user.incapacitated() || !Adjacent(user))
		return OP_OK
	replace_beaker(user)
	return OP_OK

/// Not while it grinds; an AI (a remote hand) not while it is unpowered. The old menu opened silently or not at all. (Otherwise, with no power
/// or broken, the procs fail but the buttons still show.)
/obj/machinery/reagentgrinder/proc/menu_available(datum/act/op/A)
	if(grinding)
		return FALSE
	return !((A.authority & AUTH_REMOTE_ACCESS) && has_stat(NOPOWER))

/// The radial's buttons: eject what it holds, grind it, and an examine for a remote hand.
/obj/machinery/reagentgrinder/proc/radial_choices(datum/act/op/A)
	var/list/options = list()
	if(beaker || length(holdingitems))
		options["eject"] = radial_eject
	if(A.authority & AUTH_REMOTE_ACCESS)
		options["examine"] = radial_examine
	if(length(holdingitems))
		options["grind"] = radial_grind
	return options

/// The old attack_hand (it never called ..()): the radial menu, then what was chosen.
/obj/machinery/reagentgrinder/proc/radial_chosen(datum/act/op/A)
	var/mob/user = A.actor
	if(grinding || user.incapacitated()) // post choice verification
		return OP_OK
	switch(A.step_value("choice"))
		if("eject")
			eject(user)
		if("grind")
			grind(user)
		if("examine")
			examine(user)
	return OP_OK

/obj/machinery/reagentgrinder/proc/eject(mob/user)
	if(user.incapacitated())
		return
	for(var/obj/item/O in holdingitems)
		O.forceMove(src.loc)
		rel_take(src, nameof(holdingitems), member = O)
	rel_take(src, nameof(holdingitems))
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
	hold(src, STAT_GRINDING, TRUE, SRC_GRIND, 6 SECONDS)

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
		rel_take(src, nameof(beaker))
	if(new_beaker)
		move_into(src, nameof(src.beaker), new_beaker, user)
	return TRUE
