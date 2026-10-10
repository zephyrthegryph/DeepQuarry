// The domain snapshot helpers (doc/rewrite/snapshot_pins.md, "The i7 interaction snapshots").

/**
 * Allocates a snapshot subject with what it needs to exist: some types delete themselves while
 * initializing when a partner is missing, and nothing may link to a dying entity (ownership.md
 * 4.1), so the snapshot builds the partner first rather than sampling a deleted object.
 */
/datum/unit_test/proc/dq_snapshot_allocate(type, turf/T)
	if(ispath(type, /obj/machinery/mineral/processing_unit_console))
		allocate(/obj/machinery/mineral/processing_unit, T) // the console finds its machine in range
		return allocate(type, T)
	if(ispath(type, /obj/machinery/shieldwall))
		var/obj/machinery/shieldwallgen/A = allocate(/obj/machinery/shieldwallgen, T)
		var/obj/machinery/shieldwallgen/B = allocate(/obj/machinery/shieldwallgen, T)
		A.set_active(1) // a wall stands only between two running generators
		B.set_active(1)
		return allocate(type, T, A, B)
	if(ispath(type, /obj/item/reagent_containers/food/snacks/grown))
		var/list/seeds = SSplants.seeds
		return allocate(type, T, length(seeds) ? seeds[1] : null) // produce needs a plant name
	if(ispath(type, /obj/structure/blob/core))
		// A core rolls its blob type from the RNG (the random_* cores by difficulty, the rest of the plain ones from every type), so its
		// colour followed whatever the RNG had drawn: the snapshot subject is placed without an overmind and given one of a fixed type
		// (its own, when the core names one).
		var/obj/structure/blob/core/core = allocate(type, T, null, 2, TRUE)
		if(!QDELETED(core))
			core.desired_blob_type ||= /datum/blob_type/classic
			core.create_overmind(null, TRUE)
		return core
	return allocate(type, T)

/// Abstract parent path of the i7 domain snapshots; each is a native pin capture (dq_conversion_pin) with its own rows directory.
/datum/unit_test/dq_interaction_domain_snapshot
	abstract_type = /datum/unit_test/dq_interaction_domain_snapshot
