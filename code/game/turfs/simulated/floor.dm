/turf/simulated/floor
	name = "plating"
	desc = "Unfinished flooring."
	icon = 'icons/turf/flooring/plating.dmi'
	icon_state = "plating"

	// Damage to flooring.
	var/broken
	var/burnt

	// Plating data.
	var/base_name = "plating"
	var/base_desc = "The naked hull."
	var/base_icon = 'icons/turf/flooring/plating.dmi'
	var/base_icon_state = "plating"

	var/list/old_decals = null

	// Flooring data.
	var/flooring_override
	var/initial_flooring
	var/datum/decl/flooring/flooring
	var/mineral = DEFAULT_WALL_MATERIAL
	var/can_be_plated = TRUE // This is here for inheritance's sake. Override to FALSE for turfs you don't want someone to simply slap a plating over such as hazards.

	thermal_conductivity = 0.040
	heat_capacity = FLOOR_HEAT_CAPACITY

/turf/simulated/floor/is_plating()
	return (!flooring || flooring.is_plating)

/// The flooring a floor is made with (its constructor param), or its initial one.
/turf/simulated/floor/var/floortype_at_make // ALLOW(base_vars): param() carries the constructor's flooring into init through a var of the type it declares

// ALLOW(init/INSTANCE_STATE): a floor lays its flooring and may start dirty
/turf/simulated/floor/Initialize(mapload)
	. = ..()
	var/floortype = floortype_at_make || initial_flooring
	if(floortype)
		set_flooring(get_flooring_data(floortype), TRUE) // its icons update after init (sim_after_init())
	if(can_dirty && can_start_dirty)
		if(prob(dirty_prob))
			dirt += rand(50,100)
			update_dirt() //5% chance to start with dirt on a floor tile- give the janitor something to do

/// A floor with flooring updates its icons after init wherever it was made.
/turf/simulated/floor/runtime_after_init()
	return !!flooring

/// Its icons, once its neighbours exist.
/turf/simulated/floor/sim_after_init(datum/act/timer/A)
	..()
	update_icon()

/turf/simulated/floor/proc/swap_decals()
	var/current_decals = decals
	decals = old_decals
	old_decals = current_decals

/turf/simulated/floor/proc/set_flooring(datum/decl/flooring/newflooring, initializing)
	if(is_plating() && !initializing) // Plating -> Flooring
		swap_decals()
	flooring = newflooring
	if(!initializing)
		restore_floor_integrity()
		update_icon()
	levelupdate()

//This proc will set floor_type to null and the update_icon() proc will then change the icon_state of the turf
//This proc auto corrects the grass tiles' siding.
/turf/simulated/floor/proc/make_plating(place_product, defer_icon_update)
	cut_overlays()

	for(var/obj/effect/decal/writing/W in turf_contents_of_type(src, /obj/effect/decal/writing))
		spent(W)

	name = base_name
	desc = base_desc
	icon = base_icon
	icon_state = base_icon_state
	color = null

	if(!is_plating()) // Flooring -> Plating
		swap_decals()
		if(flooring.build_type && place_product)
			new flooring.build_type(src, flooring.build_cost)
		var/newtype = flooring.get_plating_type()
		if(newtype) // Has a custom plating type to become
			set_flooring(get_flooring_data(newtype))
		else
			flooring = null

	set_light(0)
	broken = null
	burnt = null
	flooring_override = null
	levelupdate()

	if(!defer_icon_update)
		update_icon()

/turf/simulated/floor/levelupdate()
	var/floored_over = !is_plating()
	for(var/obj/O in turf_contents_of_type(src, /obj))
		O.hide(O.hides_under_flooring() && floored_over)

/turf/simulated/floor/can_engrave()
	return (!flooring || flooring.can_engrave)

/turf/simulated/floor/proc/cause_slip(mob/living/M)
	PROTECTED_PROC(TRUE)
	return

/turf/simulated/floor/occult_act(mob/living/user)
	to_chat(user, span_cult("You consecrate the floor."))
	ChangeTurf(/turf/simulated/floor/cult, preserve_outdoors = TRUE)
	return TRUE

/// Old click_alt: graffiti with the held item; otherwise the default alt-click.
/turf/simulated/floor/proc/floor_graffiti_alt(datum/act/op/A)
	var/mob/user = A.actor
	if(isliving(user))
		var/mob/living/livingUser = user
		if(try_graffiti(livingUser, livingUser.get_active_hand()))
			return OP_OK
	return OP_DECLINE
