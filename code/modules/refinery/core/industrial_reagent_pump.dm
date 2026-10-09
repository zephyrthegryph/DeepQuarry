/obj/machinery/reagent_refinery/pump
	name = "Industrial Chemical Pump"
	desc = "Transports large amounts of chemicals between machines, it also has connections for various types of hoses."
	icon_state = "pump"
	density = TRUE
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 0
	active_power_usage = 50
	circuit = /obj/item/circuitboard/industrial_reagent_pump

CAPABILITIES(/obj/machinery/reagent_refinery/pump)
	climb()
	op("reagent_pump_use", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), asks(/datum/prompt/choice, fields = list("question" = "Amount per transfer from this:", "title" = computed(PROC_REF(transfer_amount_title)), "choices" = nameof(possible_transfer_amounts), "timeout" = 0), step = "amount"), then(PROC_REF(interaction_set_transfer_amount)))
	op("reagent_pump_use", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), asks(/datum/prompt/choice, fields = list("question" = "Amount per transfer from this:", "title" = computed(PROC_REF(transfer_amount_title)), "choices" = nameof(possible_transfer_amounts), "timeout" = 0), step = "amount"), then(PROC_REF(interaction_set_transfer_amount)))

/obj/machinery/reagent_refinery/pump/Initialize(mapload)
	. = ..()
	default_apply_parts()

	add_hose_connector(/datum/hose_connector/input)
	add_hose_connector(/datum/hose_connector/input)
	add_hose_connector(/datum/hose_connector/input)
	add_hose_connector(/datum/hose_connector/output)


/obj/machinery/reagent_refinery/pump/refinery_step()
	if(!anchored)
		return

	power_change()
	if(!operable())
		return

	refinery_transfer()

/obj/machinery/reagent_refinery/minimum_reagents_for_transfer(obj/machinery/reagent_refinery/target)
	if(istype(target,/obj/machinery/reagent_refinery/mixer)) // Special handling for mixer. Don't pump unless we can pump at least our transfer amount!
		var/obj/machinery/reagent_refinery/mixer/M = target
		if(M.got_input)
			return INFINITY // block em
		return amount_per_transfer_from_this
	return 0

/obj/machinery/reagent_refinery/pump/draw(datum/look/look)
	..()
	var/datum/reagents/R = reagents
	look.watch(R) // its level and colour are tracked on the holder
	if(R?.total_volume >= 5)
		look.overlay(look_overlay_image(icon, "pump_r", color = R.tint, dir = dir))

/obj/machinery/reagent_refinery/pump/handle_transfer(atom/origin_machine, datum/reagents/RT, source_forward_dir, transfer_rate, filter_id = "")
	// pumps, furnaces, splitters and filters can only be FED in a straight line
	if(source_forward_dir != dir)
		return 0
	. = ..(origin_machine, RT, source_forward_dir, transfer_rate, filter_id)

/obj/machinery/reagent_refinery/pump/examine(mob/user, infix, suffix)
	. = ..()
	. += "The meter shows [reagents.total_volume]u / [reagents.maximum_volume]u. It is pumping chemicals at a rate of [amount_per_transfer_from_this]u."
	tutorial(REFINERY_TUTORIAL_INPUT, .)
