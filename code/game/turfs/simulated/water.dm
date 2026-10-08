// This doesn't inherit from /outdoors/ so that the pool can use it as well.
/turf/simulated/floor/water
	name = "shallow water"
	desc = "A body of water.  It seems shallow enough to walk through, if needed."
	icon = 'icons/turf/outdoors.dmi'
	icon_state = "seashallow" // So it shows up in the map editor as water.
	var/water_icon = 'icons/turf/outdoors.dmi'
	var/water_state = "water_shallow"
	var/under_state = "rock"
	edge_blending_priority = -1
	movement_cost = 4
	can_be_plated = FALSE
	outdoors = OUTDOORS_YES
	flags = TURF_ACID_IMMUNE

	layer = WATER_FLOOR_LAYER

	can_dirty = FALSE	// It's water

	var/depth = 1 // Higher numbers indicates deeper water.

	var/reagent_type = REAGENT_ID_WATER
	// var/datum/looping_sound/water/soundloop Removing soundloop for now.

	var/watercolor = null

TRACKED(/turf/simulated/floor/water, water_state)

/turf/simulated/floor/water/Initialize(mapload)
	. = ..()
	handle_fish()
	// soundloop = new(list(src), FALSE) // Removing soundloop for now.
	// soundloop.start() // Removing soundloop for now.

/// The floor's look, then the water over its bed.
/turf/simulated/floor/water/draw(datum/look/look)
	..()
	look_water(look)

/// The bed shows its state (it is not set at compile time in order for the turf to show as water in the map editor) and the water sprite lies over it.
/turf/simulated/floor/water/proc/look_water(datum/look/look)
	look.state(under_state)
	look.overlay(look_overlay_image(water_icon, water_state, layer = WATER_LAYER))

/turf/simulated/floor/water/edge_look_state()
	return under_state

/turf/simulated/floor/water/get_edge_icon_state()
	return "water_shallow"

CAPABILITIES(/turf/simulated/floor/water)
	op("water_fishing", item(/obj/item/material/fishing_rod), label("Cast a line"), priority(OP_PRIORITY_PART + 1), then(PROC_REF(water_fishing)))
	op("water_fill", item(/obj/item), label("Fill"), then(PROC_REF(water_fill)))
	on_notice(/datum/notice/hit/explosion, then(PROC_REF(explosive_fishing)))

/// Old attackby: fill an open container or wet a mop.
/turf/simulated/floor/water/proc/water_fill(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	var/obj/item/reagent_containers/RG = O
	if (istype(RG) && RG.is_open_container())
		RG.reagents.add_reagent(reagent_type, min(RG.reagents.get_free_space(), reagent_transfer_amount(RG)))
		act_message(user, src, MSG_SELF(span_notice("You fill %I% using %T%.")), MSG_OTHERS(span_notice("%U% fills %I% using %T%.")), item = RG)
		return TRUE

	else if(istype(O, /obj/item/mop))
		O.reagents.add_reagent(reagent_type, 5)
		to_chat(user, span_notice("You wet \the [O] in \the [src]."))
		play_sfx(src, SFX_EFFECTS_SLOSH)
		return TRUE

	return OP_DECLINE

/turf/simulated/floor/water/return_air_for_internal_lifeform(mob/living/L)
	if(L && L.lying)
		if(L.can_breathe_water()) // For squid.
			var/datum/gas_mixture/water_breath = new()
			var/datum/gas_mixture/above_air = return_air()
			var/amount = 300
			water_breath.adjust_gas(GAS_O2, amount) // Assuming water breathes just extract the oxygen directly from the water.
			heat_set(water_breath, above_air.return_temperature())
			return water_breath
		else
			var/gasid = GAS_CO2
			if(ishuman(L))
				var/mob/living/carbon/human/H = L
				if(H.species && H.species.exhale_type)
					gasid = H.species.exhale_type
			var/datum/gas_mixture/water_breath = new()
			var/datum/gas_mixture/above_air = return_air()
			water_breath.adjust_gas(gasid, BREATH_MOLES) // They have no oxygen, but non-zero moles and temp
			heat_set(water_breath, above_air.return_temperature())
			return water_breath
	if(L && L.is_bad_swimmer() && depth >= 2 && !L.buckled() && !L.flying)
		if(prob(10))
			act_message(L, null, MSG_SELF(span_warning("You struggle to keep your head above the water!")), MSG_OTHERS(span_notice("%U% splashes wildly.")))
		if(L.can_breathe_water())
			var/datum/gas_mixture/water_breath = new()
			var/datum/gas_mixture/above_air = return_air()
			var/amount = 300
			water_breath.adjust_gas(GAS_O2, amount) // Assuming water breathes just extract the oxygen directly from the water.
			heat_set(water_breath, above_air.return_temperature())
			return water_breath
		else
			var/gasid = GAS_CO2
			if(ishuman(L))
				var/mob/living/carbon/human/H = L
				if(H.species && H.species.exhale_type)
					gasid = H.species.exhale_type
			var/datum/gas_mixture/water_breath = new()
			var/datum/gas_mixture/above_air = return_air()
			water_breath.adjust_gas(gasid, BREATH_MOLES) // They have no oxygen, but non-zero moles and temp
			heat_set(water_breath, above_air.return_temperature())
			return water_breath
	return return_air() // Otherwise their head is above the water, so get the air from the atmosphere instead.

/turf/simulated/floor/water/Entered(atom/movable/AM, atom/oldloc)
	if(isliving(AM))
		var/mob/living/L = AM
		if(dq_get_hovering(L) || L.flying || L.is_incorporeal())
			return
		L.update_water()
		if(L.check_submerged() <= 0)
			return
		if(!istype(oldloc, /turf/simulated/floor/water))
			to_chat(L, span_warning("You get drenched in water from entering \the [src]!"))
	AM.water_act(5)
	..()

/turf/simulated/floor/water/Exited(atom/movable/AM, atom/newloc)
	if(isliving(AM))
		var/mob/living/L = AM
		if(dq_get_hovering(L) || L.flying || L.is_incorporeal())
			return
		L.update_water()
		if(L.check_submerged() <= 0)
			return
		if(!istype(newloc, /turf/simulated/floor/water))
			to_chat(L, span_warning("You climb out of \the [src]."))
	..()

/turf/simulated/floor/water/deep
	name = "deep water"
	desc = "A body of water.  It seems quite deep."
	icon_state = "seadeep" // So it shows up in the map editor as water.
	under_state = "abyss"
	edge_blending_priority = -2
	movement_cost = 8
	depth = 2
	special_temperature = T0C - 5.5 //as cool as the atmosphere outside, if someone asks, its the phoron solved in the water that stops the freezing

/turf/simulated/floor/water/pool
	name = "pool"
	desc = "Don't worry, it's not closed."
	under_state = "pool"
	outdoors = OUTDOORS_NO

/turf/simulated/floor/water/deep/pool
	name = "deep pool"
	desc = "Don't worry, it's not closed."
	outdoors = OUTDOORS_NO

/mob/living/proc/can_breathe_water()
	return FALSE

/mob/living/carbon/human/can_breathe_water()
	if(species)
		return species.can_breathe_water()
	return ..()

/mob/living/proc/is_bad_swimmer()
	return FALSE

/mob/living/carbon/human/is_bad_swimmer()
	if(species)
		return species.is_bad_swimmer()
	return ..()

/mob/living/proc/check_submerged()
	if(src?.buckled_to())
		return 0
	if(dq_get_hovering(src) || flying || is_incorporeal())
		if(flying)
			adjust_nutrition(-0.5)
		return 0
	if(locate_within(loc, /obj/structure/catwalk))
		return 0
	var/turf/simulated/floor/water/T = loc
	if(istype(T))
		return T.depth
	return 0

// Use this to have things react to having water applied to them.
/atom/movable/proc/water_act(amount)
	return

/mob/living/water_act(amount)
	adjust_wet_stacks(amount * 5)
	for(var/atom/movable/AM in contents)
		AM.water_act(amount)
	inflict_water_damage(20 * amount) // Only things vulnerable to water will actually be harmed (slimes/prommies).

/turf/simulated/floor/water/is_safe_to_enter(mob/living/L)
	// Aquatic flags simulated water as safe now
	if(istype(L,/mob/living/carbon))
		var /mob/living/carbon/A = L
		if(/datum/trait/positive/aquatic in A.species.traits)
			return TRUE
	// Aquatic flags simulated water as safe now
	if(L.get_water_protection() < 1)
		return FALSE
	return ..()

/turf/simulated/floor/water/blood
	name = REAGENT_ID_BLOOD
	desc = "A body of blood.  It seems shallow enough to walk through, if needed."
	icon = 'icons/turf/outdoors.dmi'
	icon_state = "bloodshallow"
	water_icon = 'icons/turf/outdoors.dmi'
	water_state = "bloodshallow"
	under_state = "rock"
	reagent_type = REAGENT_ID_BLOOD

/turf/simulated/floor/water/blood/get_edge_icon_state()
	return "bloodshallow"

/turf/simulated/floor/water/blood/Entered(atom/movable/AM, atom/oldloc)
	if(isliving(AM))
		var/mob/living/L = AM
		L.update_water()
		if(L.check_submerged() <= 0)
			return
		if(!istype(oldloc, /turf/simulated/floor/water))
			to_chat(L, span_warning("You get drenched in blood from entering \the [src]!"))
	AM.water_act(5)
	..()

/turf/simulated/floor/water/indoors //because it's nice to be able to use these indoors without having a blizzard ignore walls and areas.
	outdoors = OUTDOORS_NO

/turf/simulated/floor/water/deep/indoors
	outdoors = OUTDOORS_NO
