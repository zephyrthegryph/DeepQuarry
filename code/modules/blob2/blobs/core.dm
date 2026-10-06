
/obj/structure/blob/core
	name = "blob core"
	base_name = "core"
	icon = 'icons/mob/blob.dmi'
	icon_state = "blank_blob"
	desc = "A huge, pulsating yellow mass."
	density = TRUE //bandaid fix for PolarisSS13/6173
	max_integrity = 150
	point_return = -1
	health_regen = 0 //we regen in Life() instead of when pulsed
	var/desired_blob_type = null // If this is set, the core always creates an overmind possessing this blob type.
	var/difficulty_threshold = null // Otherwise if this is set, it picks a random blob_type that is equal or lower in difficulty.
	var/difficulty_floor = null // Related to the above var, acts as a floor value to the above, inclusive.
	var/core_regen = 2
	var/overmind_get_delay = 0 //we don't want to constantly try to find an overmind, this var tracks when we'll try to get an overmind again
	var/resource_delay = 0
	var/point_rate = 2
	var/ai_controlled = TRUE
	var/datum/ghost_query/Q //This is used so we can unregister ourself.
	var/tmp/client/controller	//Whoever is set to be controlling the blob. Used when the blob is created.

CAPABILITIES(/obj/structure/blob/core)
	after_init(0, then(PROC_REF(make_overmind_after_init)))
	owns_one(nameof(Q), /datum/ghost_query)
	param(nameof(controller), pos = 1)
	param(nameof(point_rate), pos = 2)
	param(nameof(placed_at_make), pos = 3)

// Spawn this if you want a ghost to be able to play as the blob.
/obj/structure/blob/core/player
	ai_controlled = FALSE

// Spawn these if you want a semi-random blob.
// Can give a random easy blob.
/obj/structure/blob/core/random_easy
	difficulty_threshold = BLOB_DIFFICULTY_EASY

// Can give a random easy or medium blob.
/obj/structure/blob/core/random_medium
	difficulty_threshold = BLOB_DIFFICULTY_MEDIUM

// Can give a random medium or hard blob.
/obj/structure/blob/core/random_hard
	difficulty_threshold = BLOB_DIFFICULTY_HARD
	difficulty_floor = BLOB_DIFFICULTY_MEDIUM

// Spawn these if you want a specific blob.
/obj/structure/blob/core/blazing_oil
	desired_blob_type = /datum/blob_type/blazing_oil

/obj/structure/blob/core/grey_goo
	desired_blob_type = /datum/blob_type/grey_goo

/obj/structure/blob/core/fabrication_swarm
	desired_blob_type = /datum/blob_type/fabrication_swarm

/obj/structure/blob/core/electromagnetic_web
	desired_blob_type = /datum/blob_type/electromagnetic_web

/obj/structure/blob/core/fungal_bloom
	desired_blob_type = /datum/blob_type/fungal_bloom

/obj/structure/blob/core/fulminant_organism
	desired_blob_type = /datum/blob_type/fulminant_organism

/obj/structure/blob/core/reactive_spines
	desired_blob_type = /datum/blob_type/reactive_spines

/obj/structure/blob/core/synchronous_mesh
	desired_blob_type = /datum/blob_type/synchronous_mesh

/obj/structure/blob/core/shifting_fragments
	desired_blob_type = /datum/blob_type/shifting_fragments

/obj/structure/blob/core/cryogenic_goo
	desired_blob_type = /datum/blob_type/cryogenic_goo

/obj/structure/blob/core/energized_jelly
	desired_blob_type = /datum/blob_type/energized_jelly

/obj/structure/blob/core/explosive_lattice
	desired_blob_type = /datum/blob_type/explosive_lattice

/obj/structure/blob/core/pressurized_slime
	desired_blob_type = /datum/blob_type/pressurized_slime

/obj/structure/blob/core/radioactive_ooze
	desired_blob_type = /datum/blob_type/radioactive_ooze

/obj/structure/blob/core/volatile_alluvium
	desired_blob_type = /datum/blob_type/volatile_alluvium

/obj/structure/blob/core/ravenous_macrophage
	desired_blob_type = /datum/blob_type/ravenous_macrophage

/obj/structure/blob/core/roiling_mold
	desired_blob_type = /datum/blob_type/roiling_mold

/obj/structure/blob/core/ectoplasmic_horror
	desired_blob_type = /datum/blob_type/ectoplasmic_horror

/obj/structure/blob/core/classic
	desired_blob_type = /datum/blob_type/classic

REGISTRY_MEMBERSHIP(/obj/structure/blob/core, REGISTRY_BLOB_CORES)

DECLARE_PERIODIC(/obj/structure/blob/core, PERIODIC_SLOW)

/obj/structure/blob/core
	/// FALSE when it was placed by an overmind or came with one: then it makes none after init.
	var/tmp/make_overmind = TRUE

/// A core placed by its player rather than spawned (its constructor param).
/obj/structure/blob/core/var/placed_at_make = FALSE

// ALLOW(init/INSTANCE_STATE): a core shows itself at once, and a placed core or one with an overmind makes none of its own
/obj/structure/blob/core/Initialize(mapload)
	. = ..()
	update_icon() //so it atleast appears

	if(placed_at_make || overmind)
		make_overmind = FALSE

/// A core spawned without an overmind (not placed by one) makes its own.
/obj/structure/blob/core/proc/make_overmind_after_init(datum/act/timer/A)
	if(!make_overmind)
		return
	create_overmind(controller())
	if(overmind)
		update_icon()

// leaves a core chunk; its overmind dies with it.
/obj/structure/blob/core/on_destroy(force)
	..()
	new /obj/item/blobcore_chunk(get_turf(src), overmind?.blob_type)
	if(overmind)
		ended_with(overmind, src)

DECLARE_APPEARANCE_PROC(/obj/structure/blob/core, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/structure/blob/core/appearance_overlays()
	. = list()
	color = null
	var/mutable_appearance/blob_overlay = mutable_appearance('icons/mob/blob.dmi', "blob")
	if(overmind)
		blob_overlay.color = overmind.blob_type.color
		name = "[overmind.blob_type.name] [base_name]"
	. += blob_overlay
	. += "blob_core_overlay"

/obj/structure/blob/core/periodic_step()
	if(QDELETED(src))
		return
	if(!overmind)
		create_overmind()
	else
		if(COOLDOWN_FINISHED(src, resource_delay))
			COOLDOWN_START(src, resource_delay, 1 SECOND)
			overmind.add_points(point_rate)
	repair_damage(core_regen)
	pulse_area(overmind, 15, BLOB_CORE_PULSE_RANGE, BLOB_CORE_EXPAND_RANGE)
	for(var/obj/structure/blob/normal/B in range(1, src))
		if(prob(5))
			B.change_to(/obj/structure/blob/shield/core, overmind)

	if(overmind) //Doing this as we might be alive for a bit before a ghost possesses us.
		overmind.blob_type.on_core_process(src)

/obj/structure/blob/core/proc/create_overmind(client/new_overmind, override_delay)
	if(!COOLDOWN_FINISHED(src, overmind_get_delay) && !override_delay)
		return

	if(ai_controlled)
		if(!desired_blob_type && !isnull(difficulty_threshold))
			desired_blob_type = get_random_blob_type()
		var/mob/observer/blob/B = new(loc, TRUE, 60, desired_blob_type)
		rel_set(src, nameof(overmind), B)
		rel_set(B, nameof(B.blob_core), src)
		B.ai_controlled = TRUE
		update_icon()
		return TRUE

	COOLDOWN_START(src, overmind_get_delay, 15 SECONDS) //if this fails, we'll try again in 15 seconds

	if(overmind)
		replaced_by(overmind)

	var/client/C = null
	if(!new_overmind)
		rel_set(src, nameof(Q), new /datum/ghost_query/blob())
		observe(Q, /datum/notice/ghost_query_complete, src, then(PROC_REF(get_winner)))
		Q.query()

	else
		C = new_overmind
		overmind_creation(C)
	rel_clear(src, nameof(controller)) //Controller has been set. Let's null it now.

/obj/structure/blob/core/proc/get_winner(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	if(Q && Q.candidates.len) //Q should NEVER get deleted but...whatever, sanity.
		var/mob/observer/dead/D = Q.candidates[1]
		var/client/C
		C = D.client
		overmind_creation(C)
	unobserve(Q, /datum/notice/ghost_query_complete, src)
	rel_clear(src, nameof(Q)) //get rid of the query

/obj/structure/blob/core/proc/overmind_creation(client/new_overmind)
	if(new_overmind)
		if(!desired_blob_type && !isnull(difficulty_threshold))
			desired_blob_type = get_random_blob_type()
		var/mob/observer/blob/B = new(loc, TRUE, 60, desired_blob_type)
		B.key = new_overmind.key
		rel_set(B, nameof(B.blob_core), src)
		rel_set(src, nameof(overmind), B)
		update_icon()
		if(B.mind && !B.mind.special_role)
			B.mind.special_role = "Blob Overmind"
		return TRUE
	return FALSE

/obj/structure/blob/core/proc/get_random_blob_type()
	if(!difficulty_threshold)
		return
	var/list/valid_types = list()
	for(var/datum/blob_type/BT as anything in subtypesof(/datum/blob_type))
		if(initial(BT.difficulty) > difficulty_threshold) // Too hard.
			continue
		if(initial(BT.difficulty) < difficulty_floor) // Too easy.
			continue
		valid_types += BT
	return pick(valid_types)


/// Whoever is set to be controlling the blob. Used when the blob is created.
/obj/structure/blob/core/proc/controller() as /client
	return controller
