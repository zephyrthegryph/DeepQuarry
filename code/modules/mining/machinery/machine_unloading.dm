/**********************Unloading unit**************************/

/obj/machinery/mineral/unloading_machine
	name = "unloading machine"
	icon = 'icons/obj/machines/mining_machines.dmi'
	icon_state = "unloader"
	density = TRUE
	anchored = TRUE
	var/tmp/obj/machinery/mineral/input
	var/tmp/obj/machinery/mineral/output

/obj/machinery/mineral/unloading_machine/Initialize(mapload)
	. = ..()
	for(var/dir in GLOB.cardinal)
		rel_set(src, nameof(input), locate(/obj/machinery/mineral/input, get_step(src, dir)))
		if(input_marker())
			break
	for(var/dir in GLOB.cardinal)
		rel_set(src, nameof(output), locate(/obj/machinery/mineral/output, get_step(src, dir)))
		if(output_marker())
			break
	watch_input(input_marker())

/// Phase 2: drops the turf watch on its input marker.
/obj/machinery/mineral/unloading_machine/lifecycle_dematerialize()
	. = ..()
	unwatch_input(input_marker())

/obj/machinery/mineral/unloading_machine/proc/toggle_speed(forced)
	if(forced)
		set_speed_process(forced)
	else
		set_speed_process(!speed_process) // switching gears
	// /obj/machinery's speed_process declaration runs the step on the fast lane in high gear; the
	// machine pipeline's step stage idles meanwhile and picks its work back up in low gear.

/// Empties ore boxes and moves items from its input plate while there are any; then it sleeps
/// until something arrives (on_input_entered()).
// Its periodic work: work_step() while it is started (code/library/machine/started_work.dm).
CAPABILITIES(/obj/machinery/mineral/unloading_machine)
	started_work(step = PROC_REF(work_step))

/obj/machinery/mineral/unloading_machine/proc/work_step(datum/act/timer/A)
	if(!output_marker() || !input_marker() || !(locate_within(input_marker().loc, /obj/structure/ore_box)) && !(locate_within(input_marker().loc, /obj/item)))
		return PROCESS_KILL
	if (src.output_marker() && src.input_marker())
		if (locate(/obj/structure/ore_box, input_marker().loc))
			var/obj/structure/ore_box/BOX = locate(/obj/structure/ore_box, input_marker().loc)
			var/i = 0
			for (var/ore in BOX.stored_ore)
				if(BOX.stored_ore[ore] > 0)
					var/obj/item/ore_chunk/ore_chunk = new /obj/item/ore_chunk(src.output_marker().loc)
					var/ore_amount = BOX.stored_ore[ore]
					ore_chunk.stored_ore[ore] += ore_amount
					BOX.stored_ore[ore] = 0

					//Icon code here. Going from most to least common.
					if(ore == ORE_SAND)
						ore_chunk.icon_state = "ore_glass"
					else if(ore == ORE_CARBON)
						ore_chunk.icon_state = "ore_coal"
					else if(ore == ORE_HEMATITE)
						ore_chunk.icon_state = "ore_iron"
					else if(ore == ORE_PHORON)
						ore_chunk.icon_state = "ore_phoron"
					else if(ore == ORE_SILVER)
						ore_chunk.icon_state = "ore_silver"
					else if(ore == ORE_GOLD)
						ore_chunk.icon_state = "ore_gold"
					else if(ore == ORE_URANIUM)
						ore_chunk.icon_state = "ore_uranium"
					else if(ore == ORE_DIAMOND)
						ore_chunk.icon_state = "ore_diamond"
					else if(ore == ORE_PLATINUM)
						ore_chunk.icon_state = "ore_platinum"
					else if(ore == ORE_MARBLE)
						ore_chunk.icon_state = "ore_marble"
					else if(ore == ORE_LEAD)
						ore_chunk.icon_state = "ore_lead"
					else if(ore == ORE_RUTILE)
						ore_chunk.icon_state = "ore_rutile"
					else if(ore == ORE_QUARTZ)
						ore_chunk.icon_state = "ore_quartz"
					else if(ore == ORE_MHYDROGEN)
						ore_chunk.icon_state = "ore_hydrogen"
					else if(ore == ORE_VERDANTIUM)
						ore_chunk.icon_state = "ore_verdantium"
					else if(ore == ORE_COPPER)
						ore_chunk.icon_state = "ore_copper"
					else if(ore == ORE_TIN)
						ore_chunk.icon_state = "ore_tin"
					else if(ore == ORE_VOPAL)
						ore_chunk.icon_state = "ore_void_opal"
					else if(ore == ORE_BAUXITE)
						ore_chunk.icon_state = "ore_bauxite"
					else if(ore == ORE_PAINITE)
						ore_chunk.icon_state = "ore_painite"
					else
						ore_chunk.icon_state = "boulder[rand(1,4)]"

					i++
					if (i>=3) //Let's make it staggered so it looks like a lot is happening.
						break
		if (locate(/obj/item, input_marker().loc))
			var/obj/item/O
			var/i
			for (i = 0; i<10; i++)
				O = locate(/obj/item, input_marker().loc)
				if (O)
					O.forceMove(src.output_marker().loc)
				else
					return
	return

/// Accessor for the input var.
/obj/machinery/mineral/unloading_machine/proc/input_marker() as /obj/machinery/mineral
	return input

/// Accessor for the output var.
/obj/machinery/mineral/unloading_machine/proc/output_marker() as /obj/machinery/mineral
	return output
