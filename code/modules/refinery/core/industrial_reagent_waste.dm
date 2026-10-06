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

CAPABILITIES(/obj/machinery/reagent_refinery/waste_processor)
	climb()
	op("waste_processor_drain_trolley", item(/obj/vehicle/train/trolley_tank), gesture(GESTURE_DRAG), priority(OP_PRIORITY_DEFAULT - 1), label("Drain into processor"), then(PROC_REF(interaction_drain_trolley)))
	op("waste_processor_drain_container", inputs(item(/obj/item/reagent_containers/glass), item(/obj/item/reagent_containers/food/drinks/glass2), item(/obj/item/reagent_containers/food/drinks/shaker)), gesture(GESTURE_DRAG), priority(OP_PRIORITY_DEFAULT - 1), label("Dump into processor"), then(PROC_REF(interaction_drain_container)))

/obj/machinery/reagent_refinery/waste_processor/Initialize(mapload)
	. = ..()
	default_apply_parts()
	flags |= NOREACT

/obj/machinery/reagent_refinery/waste_processor/refinery_step()
	if(!anchored)
		return

	power_change()
	if(!operable())
		return

	if (reagents.total_volume <= 0)
		return

	if (prob((reagents.total_volume / reagents.maximum_volume) * 100))
		flick("waste_burn",src)
		use_power_oneoff(active_power_usage)
		reagents.clear_reagents()

/obj/machinery/reagent_refinery/waste_processor/draw(datum/look/look)
	..()
	if(anchored)
		look.overlay(update_input_connection_overlays("waste_intakes"))

/obj/machinery/reagent_refinery/waste_processor/examine(mob/user, infix, suffix)
	. = ..()
	. += "The meter shows [reagents.total_volume]u / [reagents.maximum_volume]u. It is pumping chemicals at a rate of [amount_per_transfer_from_this]u."
	tutorial(REFINERY_TUTORIAL_ALLIN, .)

/// The old MouseDrop_T guard: actor able to act, adjacent to both, and (if dropping themself) able to move.
/obj/machinery/reagent_refinery/waste_processor/proc/drag_actor_ok(mob/actor, atom/target, atom/movable/dropping)
	if(actor?.buckled_to() || actor.stat || actor.restrained() || !actor.Adjacent(target) || !actor.Adjacent(dropping) || !istype(dropping) || (actor == dropping && !actor.canmove))
		return FALSE
	return TRUE

/obj/machinery/reagent_refinery/waste_processor/proc/interaction_drain_trolley(datum/act/op/A)
	var/mob/user = A.actor
	var/atom/movable/dropping = A.held
	var/obj/vehicle/train/trolley_tank/C = dropping
	if(!drag_actor_ok(A.actor, src, dropping)) // the old MouseDrop_T's silent guard: the drop goes on to whatever else takes it
		return OP_DECLINE
	// Drain it!
	C.reagents.trans_to_holder( src.reagents, src.reagents.maximum_volume)
	act_message(user, C, others = "%U% drains %T% into \the [src].")
	return OP_OK

/obj/machinery/reagent_refinery/waste_processor/proc/interaction_drain_container(datum/act/op/A)
	var/mob/user = A.actor
	var/atom/movable/dropping = A.held
	var/atom/movable/C = dropping
	if(!drag_actor_ok(A.actor, src, dropping)) // the old MouseDrop_T's silent guard: the drop goes on to whatever else takes it
		return OP_DECLINE
	// Drain it!
	C.reagents.trans_to_holder( src.reagents, src.reagents.maximum_volume)
	act_message(user, C, others = "%U% dumps %T% into \the [src].")
	return OP_OK

/// Busy while it holds waste: it burns it off at random.
/obj/machinery/reagent_refinery/waste_processor/refinery_busy()
	return reagents.total_volume > 0

CAPABILITIES(/obj/machinery/reagent_refinery/waste)
	without("reagent_refinery_set_transfer_amount")
