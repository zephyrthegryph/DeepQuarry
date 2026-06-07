// Exotic material smelter.
//
// Standalone machinery that takes /obj/item/exotic_material_sample
// inputs (mined from quarry walls), holds them in a stockpile, and
// produces /obj/item/stack/material/exotic_dynamic sheets on the
// output side. Each sample yields one sheet of the corresponding
// dynamic material.
//
// We're not piggy-backing the upstream /obj/machinery/mineral/
// processing_unit because that pipeline keys off /obj/item/ore subtype
// paths — every exotic sample shares a single typepath and is
// disambiguated only by its `material_id`. A purpose-built machine is
// simpler than convincing the upstream processor to read material_id.
//
// Operation:
//   - Sample dropped on the input turf (north-adjacent) gets pulled in
//     via the standard mineral-machine input pattern.
//   - Each tick the smelter converts up to one queued sample into a
//     sheet on the output turf (south-adjacent), bucketed by
//     material_id so sheets of the same material stack on the conveyor.
//   - Sheets carry the material_id forward; the upstream sheet pipeline
//     looks the material up by name via GLOB.name_to_material and the
//     stack picks up all the upstream-material behavior for free.

#define EXOTIC_SMELTER_RATE 1.0  // samples consumed per tick

/obj/machinery/dq_exotic_smelter
	name = "exotic material smelter"
	desc = "A heavy industrial smelter calibrated for unfamiliar mineral compositions. Drop samples on its input side; sheets emerge from the output."
	icon = 'icons/obj/machines/mining_machines.dmi'
	icon_state = "furnace"
	density = TRUE
	anchored = TRUE
	idle_power_usage = 80
	active_power_usage = 600

	/// Input tile (direction-adjacent). Set on init by walking the
	/// machine's facing direction.
	var/turf/input_turf
	/// Output tile (opposite direction).
	var/turf/output_turf
	/// material_id -> count. Pending samples to convert. Bucketed so
	/// the smelter can output stacks rather than one sheet at a time.
	var/list/queue


/obj/machinery/dq_exotic_smelter/Initialize(mapload)
	. = ..()
	input_turf = get_step(src, dir)
	output_turf = get_step(src, turn(dir, 180))
	queue = list()
	START_PROCESSING(SSobj, src)


/obj/machinery/dq_exotic_smelter/Destroy()
	STOP_PROCESSING(SSobj, src)
	queue = null
	return ..()


/obj/machinery/dq_exotic_smelter/process()
	if(stat & (NOPOWER|BROKEN))
		return
	_collect_input()
	_process_queue()


/// Vacuum any /obj/item/exotic_material_sample sitting on the input
/// turf into the queue. Bucketed by material_id.
/obj/machinery/dq_exotic_smelter/proc/_collect_input()
	if(!input_turf)
		return
	for(var/obj/item/exotic_material_sample/S in input_turf)
		if(!S.material_id)
			continue
		queue["[S.material_id]"] = (queue["[S.material_id]"] || 0) + 1
		qdel(S)


/// Per-tick smelting work. Emit up to EXOTIC_SMELTER_RATE sheets,
/// drawing from the heaviest-stocked material bucket first so a long
/// queue clears in coherent batches.
/obj/machinery/dq_exotic_smelter/proc/_process_queue()
	if(!output_turf || !length(queue))
		return
	var/budget = EXOTIC_SMELTER_RATE
	while(budget > 0 && length(queue))
		// Pick the largest bucket so we ship complete stacks rather
		// than one-offs.
		var/best_key = null
		var/best_count = 0
		for(var/key in queue)
			if(queue[key] > best_count)
				best_count = queue[key]
				best_key = key
		if(!best_key || best_count <= 0)
			return
		var/take = min(best_count, budget)
		queue[best_key] = best_count - take
		if(queue[best_key] <= 0)
			queue -= best_key
		dq_spawn_exotic_sheet(output_turf, text2num(best_key), take)
		use_power(active_power_usage * take)
		budget -= take


/obj/machinery/dq_exotic_smelter/attack_hand(mob/user)
	if(..())
		return
	var/list/lines = list()
	if(!length(queue))
		lines += "Input queue is empty."
	else
		lines += "Input queue:"
		for(var/key in queue)
			var/datum/material/dynamic/M = SSquarry?.get_exotic_material(text2num(key))
			lines += "- [M ? M.pretty_name : "Unknown ([key])"]: [queue[key]] sample(s)"
	to_chat(user, span_notice(jointext(lines, "\n")))


/obj/machinery/dq_exotic_smelter/examine(mob/user)
	. = ..()
	if(input_turf && output_turf)
		. += span_notice("Input from [dir2text(dir)]. Output to [dir2text(turn(dir, 180))].")

#undef EXOTIC_SMELTER_RATE
