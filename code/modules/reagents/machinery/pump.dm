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
	on = 0
	var/unlocked = 0
	var/open = 0

/// Pumps every machine frame while on (set_pump_on()).
CAPABILITIES(/obj/machinery/pump)
	reagents(200)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(on), wakes_on = list(nameof(on)))
	climb()

/obj/machinery/pump/Initialize(mapload)
	. = ..()
	default_apply_parts()
	rel_set(src, nameof(cell), default_use_hicell()) // component_parts owns the cell; this is a view onto it

	add_hose_connector(/datum/hose_connector/output)

	RefreshParts()
	update_icon()



/obj/machinery/pump/RefreshParts()
	var/pump_power = get_part_rating(/obj/item/stock_parts/manipulator) // scaling off the manipulator and not motor because motors have no upgrades
	active_power_usage = initial(active_power_usage) / (pump_power / max(1, get_part_count(/obj/item/stock_parts/manipulator)))
	reagents_per_cycle = initial(reagents_per_cycle) * pump_power

	var/bin_size = get_part_rating(/obj/item/stock_parts/matter_bin)

	// New holder might have different volume. Transfer everything to a new holder to account for this.
	var/datum/reagents/R = new(round(initial(reagents.maximum_volume) + 100 * bin_size), src)
	src.reagents.trans_to_holder(R, src.reagents.total_volume)
	rel_set(src, nameof(reagents), R)

	rel_set(src, nameof(cell), locate_in_list(component_parts, /obj/item/cell)) // component_parts owns the cell; this is a view onto it

DECLARE_APPEARANCE_PROC(/obj/machinery/pump, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/pump/appearance_overlays()
	. = list()
	. += ..()
	. += "[icon_state]-tank"
	if(!(cell?.check_charge(active_power_usage)))
		. += "[icon_state]-lowpower"

	if(reagents.total_volume >= 1)
		var/image/I = image(icon, "[icon_state]-volume")
		I.color = reagents.get_color()
		. += I
	. += "[icon_state]-glass"

	if(open)
		. += "[icon_state]-open"
		if(istype(cell))
			. += "[icon_state]-cell"

	icon_state = "[initial(icon_state)][on ? "-running" : ""]"

/// Pumps every machine frame; runs while on (declared).
/obj/machinery/pump/proc/work_step(datum/act/timer/A)
	if(!anchored || !(cell?.use(active_power_usage)))
		set_pump_on(FALSE)
		return

	var/turf/T = get_turf(src)
	if(!istype(T))
		return
	T.pump_reagents(reagents, reagents_per_cycle)
	update_icon()

	OM_EMIT(src, /datum/om/event/hose_forcepump)

// Sets the power state, if possible.
// Returns TRUE/FALSE on power state changing
// var/target = target power state
// var/message = TRUE/FALSE whether to make a message about state change
/obj/machinery/pump/proc/set_pump_on(target, message = TRUE)
	if(target == on)
		return FALSE

	if(!on && (!(cell?.check_charge(active_power_usage)) || !anchored))
		return FALSE

	set_on(!on)
	if(message)
		if(on)
			message = span_notice("\The [src] turns on.")
		else
			message = span_notice("\The [src] shuts down.")
		visible_message(message)
	return TRUE

/obj/machinery/pump
	silicon_use = ROBOT_USE_HAND | SILICON_USE_HAND

/// Old attack_ai: the AI toggles the pump. Cyborgs never reached it (ROBOT_USE_HAND sends
/// their Use to attack_hand), so they fall through to that default.
/obj/machinery/pump/proc/pump_silicon_toggle(mob/user, obj/item/held, datum/interaction/interaction)
	if(isrobot(user))
		return FALSE
	if(!set_pump_on(!on))
		to_chat(user, span_notice("You try to toggle \the [src] but it does not respond."))
	return TRUE

/obj/machinery/pump/declare_interactions(list/into)
	var/static/list/actor_specs = list(
		INTERACT_SILICON("Toggle", PROC_REF(pump_silicon_toggle)),
	)
	for(var/actor_spec in actor_specs)
		into += dq_interaction_from_spec(type, actor_spec)
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
	also_requires = list(REQ_TARGET_STATE(/obj/machinery/pump/proc/can_take_cell))

/// Requirement: TRUE, or why a cell can't go in now.
/obj/machinery/pump/proc/can_take_cell(mob/user, atom/target, obj/item/held)
	if(!open)
		return unlocked ? "the battery panel is screwed shut" : "the battery panel is watertight and cannot be opened without a crowbar"
	if(istype(cell))
		return "there is a power cell already installed"
	return TRUE

/**
 * The old attackby returned early (skipping the trailing RefreshParts()/update_icon()) when the
 * panel was closed or already held a cell; those calls only ran after a successful insert.
 */
/obj/machinery/pump/proc/interaction_insert_cell(mob/user, obj/item/cell/W, datum/interaction/interaction)
	materialize_parts()
	if(!move_into(src, nameof(component_parts), W, user, ledger_slot = CONTAINER_SLOT_INTERNALS))
		return TRUE
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
		var/obj/item/cell/removed = cell
		own_take_member(src, nameof(component_parts), removed)
		rel_clear(src, nameof(cell))
		user.put_in_hands(removed)
		removed.add_fingerprint(user)
		removed.update_icon()
		set_pump_on(FALSE)
		to_chat(user, span_notice("You remove the power cell."))
		return TRUE

	if(!set_pump_on(!on))
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
		if(M.mineral() && prob(40) && M.mineral().reagent) // v
			R.add_reagent(M.mineral().reagent, round(volume / 5, 0.1)) // Was the turf's reagents variable not the R argument, and changed ore_reagent to M.mineral.reagent because of above change. Also nerfed amount to 1/5 instead of 1/2

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
	if(M.mineral() && M.mineral().reagent && prob(40))
		R.add_reagent(M.mineral().reagent, rand(0,volume / 8))
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
