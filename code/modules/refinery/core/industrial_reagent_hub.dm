/obj/machinery/reagent_refinery/hub
	name = "Industrial Chemical Hub"
	desc = "A platform for loading and unloading cargo tug tankers."
	icon_state = "hub"
	density = FALSE
	anchored = TRUE
	use_power = USE_POWER_OFF // Does not require power for pipes
	idle_power_usage = 0
	active_power_usage = 0
	circuit = /obj/item/circuitboard/industrial_reagent_hub
	default_max_vol = 0

CAPABILITIES(/obj/machinery/reagent_refinery/hub)
	after_init(0, then(PROC_REF(apply_default_parts)))

/obj/machinery/reagent_refinery/hub/refinery_step()
	if(!anchored)
		return

	if(broken_now())
		return

	if (amount_per_transfer_from_this <= 0)
		return

	var/obj/machinery/reagent_refinery/target = locate_within(get_step(loc,dir), /obj/machinery/reagent_refinery)
	if(target && target.dir != GLOB.reverse_dir[dir])
		var/obj/vehicle/train/trolley_tank/tanker = locate_within(loc, /obj/vehicle/train/trolley_tank)
		if(tanker && tanker.reagents.total_volume > 0 && COOLDOWN_FINISHED(tanker, settle_cooldown))
			// dump reagents to next refinery machine
			transfer_tank( tanker.reagents, target, dir)

/// The hub's pipe shows whether the machine it faces feeds into it (intake) or the hub feeds that machine. The neighbour is looked for ahead and
/// watched: it appearing, leaving, turning or being unanchored redraws the hub.
/obj/machinery/reagent_refinery/hub/draw(datum/look/look)
	..()
	var/obj/machinery/reagent_refinery/other = look.neighbour(src, dir, /obj/machinery/reagent_refinery)
	var/intake = other?.anchored && other.hub_intake(GLOB.reverse_dir[dir])
	look.overlay(look_overlay_image(icon, intake ? "hub_intakes" : "hub_cons", dir = dir))

/obj/machinery/reagent_refinery/hub/handle_transfer(atom/origin_machine, datum/reagents/RT, source_forward_dir, transfer_rate, filter_id = "")
	if(istype(origin_machine,/obj/machinery/reagent_refinery/hub)) // Hubs cannot send into other hubs
		return 0
	if(dir != GLOB.reverse_dir[source_forward_dir] ) // The hub must be facing into its source to accept input, unlike others
		return 0
	var/obj/vehicle/train/trolley_tank/tanker = locate_within(get_turf(src), /obj/vehicle/train/trolley_tank)
	if(!tanker)
		return 0
	if(COOLDOWN_TIMELEFT(tanker, settle_cooldown) > 0) // await cooldown to avoid spamming moving tanks
		return 0
	// Don't call parent, we're transfering into the holding tank instead
	if(filter_id == "")
		return RT.trans_to_obj(tanker, transfer_rate)
	else
		// Split out reagent...
		return RT.trans_id_to(tanker, filter_id, transfer_rate)

/obj/machinery/reagent_refinery/hub/examine(mob/user, infix, suffix)
	. = ..()
	. += "It is pumping chemicals at a rate of [amount_per_transfer_from_this]u."
	tutorial(REFINERY_TUTORIAL_HUB|REFINERY_TUTORIAL_NOPOWER, .)

/// Busy while a tanker with reagents sits on it; a tanker rolling on wakes it.
/obj/machinery/reagent_refinery/hub/refinery_busy()
	var/obj/vehicle/train/trolley_tank/tanker = locate_within(loc, /obj/vehicle/train/trolley_tank)
	return tanker && tanker.reagents.total_volume > 0

/obj/machinery/reagent_refinery/hub/Crossed(atom/movable/AM)
	. = ..()
	if(istype(AM, /obj/vehicle/train/trolley_tank))
		work_start(src)
