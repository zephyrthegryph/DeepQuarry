//UPDATE TRIGGERS, when the chunk (and the surrounding chunks) should update.

// TURFS

/proc/updateVisibility(atom/A, opacity_check = 1)
	if(SSticker)
		for(var/datum/visualnet/VN in REGISTRY_MEMBERS(REGISTRY_VISUAL_NETS))
			VN.updateVisibility(A, opacity_check)

/turf
	var/list/image/obfuscations

/turf/drain_power()
	return -1

/// Phase 2: freelook nets see the turf go.
/turf/simulated/lifecycle_dematerialize()
	. = ..()
	updateVisibility(src)

/turf/simulated/Initialize(mapload)
	. = ..()
	updateVisibility(src)

// STRUCTURES

/// Phase 2: freelook nets see the structure go.
/obj/structure/lifecycle_dematerialize()
	. = ..()
	updateVisibility(src)

/obj/structure/Initialize(mapload)
	. = ..()
	updateVisibility(src)

/obj/structure/table_initialize()
	..()
	updateVisibility(src)

// EFFECTS

/// Phase 2: freelook nets see the effect go.
/obj/effect/lifecycle_dematerialize()
	if(GLOB.dq_lifecycle_trace_depth)
		log_world("LIFECYCLE_TRACE: [type] /obj/effect dematerialize: calling parent")
	. = ..()
	if(GLOB.dq_lifecycle_trace_depth)
		log_world("LIFECYCLE_TRACE: [type] /obj/effect dematerialize: parent returned, updating visibility")
	updateVisibility(src)

/obj/effect/Initialize(mapload)
	. = ..()
	updateVisibility(src)

/obj/effect/table_initialize()
	..()
	updateVisibility(src)

// DOORS

// Simply updates the visibility of the area when it opens/closes/destroyed.
/obj/machinery/door/update_nearby_tiles(need_rebuild)
	. = ..(need_rebuild)
	// Glass door glass = 1
	// don't check then?
	if(!glass)
		updateVisibility(src, 0)

DECLARE_REF(/turf, "obfuscations", OWNED_LIST, null)
