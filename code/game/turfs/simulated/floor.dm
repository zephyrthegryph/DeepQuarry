/turf/simulated/floor
	name = "plating"
	desc = "Unfinished flooring."
	icon = 'icons/turf/flooring/plating.dmi'
	icon_state = "plating"

	/// Damage to flooring: null when whole, else the variant of the sprite to show (which may be 0).
	var/broken
	var/burnt
	/// TRUE once the flooring was torn off with no plating to show under it: the tile draws the bare deck (base_icon, base_icon_state).
	var/plating_exposed = FALSE
	/// A sprite burnt into the tile that replaces the one its flooring or damage shows (the scorch a melted wall leaves), until it is covered or welded.
	var/scorch_state

	// Plating data.
	var/base_name = "plating"
	var/base_desc = "The naked hull."
	var/base_icon = 'icons/turf/flooring/plating.dmi'
	var/base_icon_state = "plating"

	var/list/old_decals = null

	// Flooring data.
	/// The icon_state a flooring with a range of variants (has_base_range) was rolled to, rolled once when the flooring is laid; null: the flooring's own.
	var/flooring_override
	/// Which of the four damaged-plating sprites (dmg1-4) this floor shows once broken or burnt, rolled when it is damaged.
	var/plating_damage_state = 1
	var/initial_flooring
	var/datum/decl/flooring/flooring
	var/mineral = DEFAULT_WALL_MATERIAL
	var/can_be_plated = TRUE // This is here for inheritance's sake. Override to FALSE for turfs you don't want someone to simply slap a plating over such as hazards.

	thermal_conductivity = 0.040
	heat_capacity = FLOOR_HEAT_CAPACITY

TRACKED(/turf/simulated/floor, flooring)
TRACKED(/turf/simulated/floor, flooring_override)
TRACKED(/turf/simulated/floor, plating_damage_state)
TRACKED(/turf/simulated/floor, plating_exposed)
TRACKED(/turf/simulated/floor, scorch_state)

TRACKED(/turf/simulated/floor, broken)
TRACKED(/turf/simulated/floor, burnt)

/turf/simulated/floor/is_plating()
	return (!flooring || flooring.is_plating)

/// The flooring a floor is made with (its constructor param), or its initial one.
/turf/simulated/floor/var/floortype_at_make // ALLOW(base_vars): param() carries the constructor's flooring into init through a var of the type it declares

// ALLOW(init/INSTANCE_STATE): a floor lays its flooring and may start dirty
/turf/simulated/floor/Initialize(mapload)
	. = ..()
	var/floortype = floortype_at_make || initial_flooring
	if(floortype)
		install_flooring(get_flooring_data(floortype), TRUE) // the first draw after init shows it
	if(can_dirty && can_start_dirty)
		if(prob(dirty_prob))
			dirt += rand(50,100)
			update_dirt() //5% chance to start with dirt on a floor tile- give the janitor something to do

/// A floor with flooring runs the after-init pass (planet sunlight) wherever it was made.
/turf/simulated/floor/runtime_after_init()
	return !!flooring

/turf/simulated/floor/proc/swap_decals()
	var/current_decals = decals
	set_decals(old_decals)
	old_decals = current_decals

/// The sprite a flooring with a range of variants is laid with: its base (and the season's) with one of its variant numbers.
/turf/simulated/floor/proc/rolled_flooring_state()
	var/state = flooring.icon_base
	if(flooring.check_season)
		state = "[state]-[GLOB.world_time_season]"
	return "[state][rand(0, flooring.has_base_range)]"

/// Lays `newflooring` on the tile (its tracked flooring, the variant it rolls and the decals that go with the surface). The draw follows by itself.
/turf/simulated/floor/proc/install_flooring(datum/decl/flooring/newflooring, initializing)
	if(is_plating() && !initializing) // Plating -> Flooring
		swap_decals()
	set_flooring(newflooring)
	set_plating_exposed(FALSE)
	set_scorch_state(null)
	if(flooring?.has_base_range && !flooring_override)
		set_flooring_override(rolled_flooring_state()) // rolled once here, not on every draw
	if(!initializing)
		restore_floor_integrity()
	levelupdate()

//This proc will set the flooring to its plating (or to nothing) and the draw shows the result.
//The edges of the grass tiles around follow through the adjacency index.
/turf/simulated/floor/proc/make_plating(place_product)
	for(var/obj/effect/decal/writing/W in turf_contents_of_type(src, /obj/effect/decal/writing))
		spent(W)

	name = base_name
	desc = base_desc
	color = null

	if(!is_plating()) // Flooring -> Plating
		swap_decals()
		if(flooring.build_type && place_product)
			new flooring.build_type(src, flooring.build_cost)
		var/newtype = flooring.get_plating_type()
		if(newtype) // Has a custom plating type to become
			install_flooring(get_flooring_data(newtype))
		else
			set_flooring(null)
			set_plating_exposed(TRUE)

	set_light(0)
	set_broken(null)
	set_burnt(null)
	set_flooring_override(null)
	levelupdate()

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
