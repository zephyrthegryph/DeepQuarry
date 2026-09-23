/obj/machinery/pump
	maintenance_flags = MACHINE_MAINT_WRENCH
	maintenance_wrench_time = 2 SECONDS
	name = "fluid pump"
	desc = "A fluid pumping machine."

	anchored = TRUE
	density = TRUE

	icon = 'icons/obj/machines/reagent.dmi'
	icon_state = "pump"

	circuit = /obj/item/circuitboard/fluidpump
	active_power_usage = 200 * CELLRATE

	var/obj/item/cell/cell = null
	var/reagents_per_cycle = 5
	var/on = 0
	var/unlocked = 0
	var/open = 0

/obj/machinery/pump/Initialize(mapload)
	create_reagents(200)
	. = ..()
	default_apply_parts()
	cell = default_use_hicell()

	AddComponent(/datum/component/hose_connector/output)

	RefreshParts()
	update_icon()

	AddElement(/datum/element/climbable)

/obj/machinery/pump/Destroy()
	QDEL_NULL(cell)
	. = ..()

/obj/machinery/pump/RefreshParts()
	var/pump_power = get_part_rating(/obj/item/stock_parts/manipulator) // scaling off the manipulator and not motor because motors have no upgrades
	active_power_usage = initial(active_power_usage) / (pump_power / max(1, get_part_count(/obj/item/stock_parts/manipulator)))
	reagents_per_cycle = initial(reagents_per_cycle) * pump_power

	var/bin_size = get_part_rating(/obj/item/stock_parts/matter_bin)

	// New holder might have different volume. Transfer everything to a new holder to account for this.
	var/datum/reagents/R = new(round(initial(reagents.maximum_volume) + 100 * bin_size), src)
	src.reagents.trans_to_holder(R, src.reagents.total_volume)
	qdel(src.reagents)
	src.reagents = R

	cell = locate(/obj/item/cell) in src

/obj/machinery/pump/update_icon()
	..()
	cut_overlays()
	add_overlay("[icon_state]-tank")
	if(!(cell?.check_charge(active_power_usage)))
		add_overlay("[icon_state]-lowpower")

	if(reagents.total_volume >= 1)
		var/image/I = image(icon, "[icon_state]-volume")
		I.color = reagents.get_color()
		add_overlay(I)
	add_overlay("[icon_state]-glass")

	if(open)
		add_overlay("[icon_state]-open")
		if(istype(cell))
			add_overlay("[icon_state]-cell")

	icon_state = "[initial(icon_state)][on ? "-running" : ""]"

/obj/machinery/pump/process()
	if(!on)
		return

	if(!anchored || !(cell?.use(active_power_usage)))
		set_state(FALSE)
		return

	var/turf/T = get_turf(src)
	if(!istype(T))
		return
	T.pump_reagents(reagents, reagents_per_cycle)
	update_icon()

	SEND_SIGNAL(src, COMSIG_HOSE_FORCEPUMP)

// Sets the power state, if possible.
// Returns TRUE/FALSE on power state changing
// var/target = target power state
// var/message = TRUE/FALSE whether to make a message about state change
/obj/machinery/pump/proc/set_state(target, message = TRUE)
	if(target == on)
		return FALSE

	if(!on && (!(cell?.check_charge(active_power_usage)) || !anchored))
		return FALSE

	on = !on
	update_icon()
	if(message)
		if(on)
			message = span_notice("\The [src] turns on.")
		else
			message = span_notice("\The [src] shuts down.")
		visible_message(message)
	return TRUE

/obj/machinery/pump
	silicon_use = ROBOT_USE_HAND | SILICON_USE_HAND

/obj/machinery/pump/attack_ai(mob/user)
	if(!set_state(!on))
		to_chat(user, span_notice("You try to toggle \the [src] but it does not respond."))

/obj/machinery/pump/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/pump_insert_cell,
		/datum/interaction/machine_hand/ungated/pump_use,
	)
	..()

/// Old attackby: insert a power cell into the open battery panel.
/datum/interaction/machine_item/pump_insert_cell
	id = "pump_insert_cell"
	name = "Insert power cell"
	held_type = /obj/item/cell
	effect = /obj/machinery/pump/proc/interaction_insert_cell

/**
 * The old attackby returned early (skipping the trailing RefreshParts()/update_icon()) when the
 * panel was closed or already held a cell; those calls only ran after a successful insert.
 */
/obj/machinery/pump/proc/interaction_insert_cell(mob/user, obj/item/cell/W, datum/interaction/interaction)
	if(!open)
		if(unlocked)
			to_chat(user, span_notice("The battery panel is screwed shut."))
		else
			to_chat(user, span_notice("The battery panel is watertight and cannot be opened without a crowbar."))
		return TRUE
	if(istype(cell))
		to_chat(user, span_notice("There is a power cell already installed."))
		return TRUE
	user.drop_from_inventory(W, src)
	cell = W // Link the cell to us
	to_chat(user, span_notice("You insert the power cell."))
	RefreshParts() // Handles cell assignment
	update_icon()
	return TRUE

/// Old attack_hand, which never called ..(): no gate.
/datum/interaction/machine_hand/ungated/pump_use
	id = "pump_use"
	name = "Use"
	effect = /obj/machinery/pump/proc/interaction_use

/obj/machinery/pump/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(open && istype(cell))
		user.put_in_hands(cell)
		cell.add_fingerprint(user)
		cell.update_icon()
		cell = null
		set_state(FALSE)
		to_chat(user, span_notice("You remove the power cell."))
		return TRUE

	if(!set_state(!on))
		to_chat(user, span_notice("You try to toggle \the [src] but it does not respond."))
	return TRUE

/obj/machinery/pump/screwdriver_act(mob/user, obj/item/tool)
	if(open)
		return ITEM_INTERACT_BLOCKING
	to_chat(user, span_notice("You [unlocked ? "screw" : "unscrew"] the battery panel."))
	unlocked = !unlocked
	update_icon()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/pump/crowbar_act(mob/user, obj/item/tool)
	if(!unlocked)
		return ITEM_INTERACT_BLOCKING
	to_chat(user, open ? span_notice("You crowbar the battery panel in place.") : span_notice("You remove the battery panel."))
	open = !open
	update_icon()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/pump/wrench_act(mob/user, obj/item/tool)
	if(on)
		to_chat(user, span_notice("\The [src] is active. Turn it off before trying to move it!"))
		return ITEM_INTERACT_BLOCKING
	return ..()


/turf/proc/pump_reagents()
	return

/turf/simulated/floor/lava/pump_reagents(datum/reagents/R, volume)
	. = ..()
	R.add_reagent(REAGENT_ID_MINERALIZEDFLUID, round(volume / 2, 0.1))


/turf/simulated/floor/water/pump_reagents(datum/reagents/R, volume)
	. = ..()
	R.add_reagent(REAGENT_ID_WATER, round(volume, 0.1))

	var/datum/gas_mixture/air = return_air() // v
	if(air.return_temperature() <= T0C) // Uses the current air temp, instead of the turf starting temp
		R.add_reagent(REAGENT_ID_ICE, round(volume / 2, 0.1))

	for(var/turf/simulated/mineral/M in orange(5,src))
		if(M.mineral && prob(40) && M.mineral.reagent) // v
			R.add_reagent(M.mineral.reagent, round(volume / 5, 0.1)) // Was the turf's reagents variable not the R argument, and changed ore_reagent to M.mineral.reagent because of above change. Also nerfed amount to 1/5 instead of 1/2

/turf/simulated/floor/water/pool/pump_reagents(datum/reagents/R, volume)
	. = ..()
	R.add_reagent(REAGENT_ID_CHLORINE, round(volume / 10, 0.1))

/turf/simulated/floor/water/deep/pool/pump_reagents(datum/reagents/R, volume)
	. = ..()
	R.add_reagent(REAGENT_ID_CHLORINE, round(volume / 10, 0.1))


/turf/simulated/mineral/pump_reagents(datum/reagents/R, volume)
	. = ..()
	if(density)
		return
	if(!sand_dug)
		return
	var/turf/simulated/mineral/M = pick(orange(5,src))
	if(!istype(M))
		return
	// Use nearby ores as well
	if(M.mineral && M.mineral.reagent && prob(40))
		R.add_reagent(M.mineral.reagent, rand(0,volume / 8))
	// Pump deep reagents from deepdrill boreholes
	for(var/metal in GLOB.deepore_fracking_reagents)
		if(!LAZYACCESS(M.resources,metal))
			continue
		var/list/ore_list = GLOB.deepore_fracking_reagents[metal]
		if(!LAZYLEN(ore_list))
			continue
		var/reagent_id = pick(ore_list)
		if(reagent_id && prob(60))
			R.add_reagent(reagent_id, rand(0,volume / 6))
