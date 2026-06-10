// Goal subtypes used by the floor archetypes.
//
// These extend the base /datum/quarry_goal hooks (quarry_goal.dm) with
// the three new progress sources the archetypes need:
//   - on_layer_tick       -> survive_timer (hold out N seconds)
//   - on_objective_resolved -> neutralize (resolve N objective nodes)
//   - on_delivery         -> deliver_resource (ship N items to surface)
// Exterminate floors reuse the existing kill_mob goal with a large target.


// --- survive_timer ----------------------------------------------------
//
// Hold the floor for `target` seconds. Progress is driven entirely by the
// shaft-assault console (/obj/structure/quarry_siege_console) once the
// crew triggers the assault — NOT by passive presence — and resets to 0
// if the assault is aborted (a hostile breaches the lift). Used by the
// siege gate.
/datum/quarry_goal/survive_timer
	name = "Hold the Shaft"
	description = "Trigger and survive the shaft assault."
	target = 3 MINUTES / 10  // stored in seconds; set by the archetype

/datum/quarry_goal/survive_timer/merge_key()
	return "survive"


// --- neutralize -------------------------------------------------------
//
// Resolve `target` objective nodes of a given kind (gas fissures sealed,
// lava vents cooled, hive cores destroyed, outposts lit, ...). Each
// /obj/structure/quarry_objective that resolves with a matching tag ticks
// the goal by one. The generic backbone of every hazard floor.
/datum/quarry_goal/neutralize
	name = "Neutralize the Hazard"
	/// Must match the resolving objective structure's objective_tag.
	var/objective_tag = "objective"

/datum/quarry_goal/neutralize/on_objective_resolved(tag)
	if(tag != objective_tag)
		return
	progress = min(target, progress + 1)

/datum/quarry_goal/neutralize/merge_key()
	return "neutralize:[objective_tag]"


// --- deliver_resource -------------------------------------------------
//
// Ship `target` ore units off at the surface freight terminal. Credited
// when Cargo ships staged ore from the terminal (SSquarry.on_layer_delivery
// via /obj/structure/quarry_freight_export) — not by ore merely reaching
// the surface bay. This is the logistics/Cargo objective.
/datum/quarry_goal/deliver_resource
	name = "Surface Delivery"
	description = "Ship extracted ore off at the surface freight terminal."

/datum/quarry_goal/deliver_resource/on_delivery(count)
	if(!isnum(count) || count <= 0)
		return
	progress = min(target, progress + count)

/datum/quarry_goal/deliver_resource/merge_key()
	return "deliver"


// --- power_output -----------------------------------------------------
//
// Generate `target` kilowatt-minutes of power on the level from real,
// running generators. Each tick sums the live output of every active
// portable generator on the layer's z and accrues it as kW-min. The
// Overcharge floor — players must anchor, fuel, and run the generators
// (Engineering + Cargo for fuel) to feed the order.
/datum/quarry_goal/power_output
	name = "Feed the Grid"
	description = "Run the generators to feed kilowatt-minutes into the surface relay."

/datum/quarry_goal/power_output/on_layer_tick(datum/quarry_layer/L, seconds)
	if(!isnum(seconds) || seconds <= 0)
		return
	var/watts = 0
	for(var/obj/machinery/power/port_gen/G in GLOB.machines)
		if(G.z != L.z || !G.active)
			continue
		watts += G.power_gen * G.power_output
	if(watts <= 0)
		return
	// kilowatt-minutes accrued this tick.
	progress = min(target, progress + (watts / 1000) * (seconds / 60))

/datum/quarry_goal/power_output/merge_key()
	return "power"
