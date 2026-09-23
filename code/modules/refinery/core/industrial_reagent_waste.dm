/obj/machinery/reagent_refinery/waste_processor
	name = "Industrial Chemical Waste Processor"
	desc = "A large chemical processing chamber. Chemicals inside are energized into plasma and collected as raw energy! Unfortunately the process is only 17% efficient, a net loss of power."
	icon_state = "waste"
	density = TRUE
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 0
	active_power_usage = 200
	circuit = /obj/item/circuitboard/industrial_reagent_waste_processor
	default_max_vol = CARGOTANKER_VOLUME

/obj/machinery/reagent_refinery/waste_processor/Initialize(mapload)
	. = ..()
	default_apply_parts()
	// Can't be set on these
	src.verbs -= /obj/machinery/reagent_refinery/verb/set_APTFT
	AddElement(/datum/element/climbable)
	flags |= NOREACT

/obj/machinery/reagent_refinery/waste_processor/process()
	if(!anchored)
		return

	power_change()
	if(stat & (NOPOWER|BROKEN))
		return

	if (reagents.total_volume <= 0)
		return

	if (prob((reagents.total_volume / reagents.maximum_volume) * 100))
		flick("waste_burn",src)
		use_power_oneoff(active_power_usage)
		reagents.clear_reagents()

/obj/machinery/reagent_refinery/waste_processor/update_icon()
	cut_overlays()
	if(anchored)
		update_input_connection_overlays("waste_intakes")

/obj/machinery/reagent_refinery/waste_processor/examine(mob/user, infix, suffix)
	. = ..()
	. += "The meter shows [reagents.total_volume]u / [reagents.maximum_volume]u. It is pumping chemicals at a rate of [amount_per_transfer_from_this]u."
	tutorial(REFINERY_TUTORIAL_ALLIN, .)

/obj/machinery/reagent_refinery/waste_processor/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_drag/waste_processor_drain_trolley,
		/datum/interaction/machine_drag/waste_processor_drain_container,
	)
	..()

/datum/interaction/machine_drag/waste_processor_drain_trolley
	id = "waste_processor_drain_trolley"
	name = "Drain into processor"
	held_type = /obj/vehicle/train/trolley_tank
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_ACTOR, /obj/machinery/reagent_refinery/waste_processor/proc/drag_actor_ok, null))
	effect = /obj/machinery/reagent_refinery/waste_processor/proc/interaction_drain_trolley

/datum/interaction/machine_drag/waste_processor_drain_container
	id = "waste_processor_drain_container"
	name = "Dump into processor"
	held_type = list(/obj/item/reagent_containers/glass, /obj/item/reagent_containers/food/drinks/glass2, /obj/item/reagent_containers/food/drinks/shaker)
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_ACTOR, /obj/machinery/reagent_refinery/waste_processor/proc/drag_actor_ok, null))
	effect = /obj/machinery/reagent_refinery/waste_processor/proc/interaction_drain_container

/// The old MouseDrop_T guard: actor able to act, adjacent to both, and (if dropping themself) able to move.
/obj/machinery/reagent_refinery/waste_processor/proc/drag_actor_ok(mob/actor, atom/target, atom/movable/dropping)
	if(actor.buckled || actor.stat || actor.restrained() || !actor.Adjacent(target) || !actor.Adjacent(dropping) || !istype(dropping) || (actor == dropping && !actor.canmove))
		return FALSE
	return TRUE

/obj/machinery/reagent_refinery/waste_processor/proc/interaction_drain_trolley(mob/user, atom/movable/dropping, datum/interaction/interaction)
	var/obj/vehicle/train/trolley_tank/C = dropping
	// Drain it!
	C.reagents.trans_to_holder( src.reagents, src.reagents.maximum_volume)
	visible_message("\The [user] drains \the [C] into \the [src].")
	update_icon()
	return TRUE

/obj/machinery/reagent_refinery/waste_processor/proc/interaction_drain_container(mob/user, atom/movable/dropping, datum/interaction/interaction)
	var/atom/movable/C = dropping
	// Drain it!
	C.reagents.trans_to_holder( src.reagents, src.reagents.maximum_volume)
	visible_message("\The [user] dumps \the [C] into \the [src].")
	update_icon()
	return TRUE
