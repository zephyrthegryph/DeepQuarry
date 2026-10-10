/// Returns reactions which will contribute to a hotspot's size.
/proc/init_hotspot_reactions()
	var/list/fire_reactions = list()
	for (var/datum/gas_reaction/reaction as anything in subtypesof(/datum/gas_reaction))
		if(initial(reaction.expands_hotspot))
			fire_reactions += reaction

	return fire_reactions

/turf/proc/hotspot_expose(exposed_temperature, exposed_volume, soh = 0)
	return

/**
 * Handles the creation of hotspots and initial activation of turfs.
 * Setting the conditions for the reaction to actually happen for gasmixtures
 * is handled by the hotspot itself, specifically perform_exposure().
 */
/turf/open/hotspot_expose(exposed_temperature, exposed_volume, soh)
	if(exposed_temperature < TCMB)
		exposed_temperature = TCMB
		CRASH("[src].hotspot_expose() called with exposed_temperature < [TCMB]")
	// honor flame-retardant protection (set by firefoam, extinguishers,
	// fire-resistant tile coatings). Protection lasts FIRE_PROTECTION_DURATION
	// after apply_fire_protection() was called.
	if(fire_protection && (ELAPSED(src, fire_protection, CLOCK_WORLD) < FIRE_PROTECTION_DURATION))
		return
	//If the air doesn't exist we just return false
	if(!air)
		return

	var/oxy = air.get_moles(/datum/gas/oxygen)
	if (oxy < 0.5)
		return
	var/plas = air.get_moles(/datum/gas/plasma)
	var/trit = air.get_moles(/datum/gas/tritium)
	var/h2 = air.get_moles(/datum/gas/hydrogen)
	var/freon = air.get_moles(/datum/gas/freon)
	if(active_hotspot)
		if(soh)
			if(plas > 0.5 || trit > 0.5 || h2 > 0.5)
				if(active_hotspot.temperature < exposed_temperature)
					active_hotspot.temperature = exposed_temperature
				if(active_hotspot.volume < exposed_volume)
					active_hotspot.volume = exposed_volume
			else if(freon > 0.5)
				if(active_hotspot.temperature > exposed_temperature)
					active_hotspot.temperature = exposed_temperature
				if(active_hotspot.volume < exposed_volume)
					active_hotspot.volume = exposed_volume
		return

	if(((exposed_temperature > PLASMA_MINIMUM_BURN_TEMPERATURE) && (plas > 0.5 || trit > 0.5 || h2 > 0.5)) || \
		((exposed_temperature < FREON_MAXIMUM_BURN_TEMPERATURE) && (freon > 0.5)))

		new /obj/effect/hotspot(src, exposed_volume * 25, exposed_temperature)
		SSair.add_to_active(src)

/**
 * Hotspot objects interfaces with the temperature of turf gasmixtures while also providing visual effects.
 * One important thing to note about hotspots are that they can roughly be divided into two categories based on the bypassing variable.
 */
/obj/effect/hotspot
	anchored = TRUE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	icon = 'icons/effects/fire.dmi'
	icon_state = "light"
	layer = GASFIRE_LAYER
	plane = ABOVE_GAME_PLANE
	blend_mode = BLEND_ADD
	light_system = OVERLAY_LIGHT
	light_range = LIGHT_RANGE_FIRE
	light_power = 1
	light_color = LIGHT_COLOR_FIRE

	/// base sprite used for our icon states when smoothing
	/// BAAAASICALY the same as icon_state but is helpful to avoid duplicated work
	var/fire_stage = ""
	/**
	 * Volume is the representation of how big and healthy a fire is.
	 * Hotspot volume will be divided by turf volume to get the ratio for temperature setting on non bypassing mode.
	 * Also some visual stuffs for fainter fires.
	 */
	var/volume = 125
	/// Temperature handles the initial ignition and the colouring.
	var/temperature = FIRE_MINIMUM_TEMPERATURE_TO_EXIST
	/// Whether the hotspot is new or not. Used for bypass logic.
	var/just_spawned = TRUE
	/// Whether the hotspot becomes passive and follows the gasmix temp instead of changing it.
	var/bypassing = FALSE
	var/visual_update_tick = 0
	///Are we burning freon?
	var/cold_fire = FALSE
	///the group of hotspots we are a part of
	var/datum/hot_group/our_hot_group

CAPABILITIES(/obj/effect/hotspot)
	links(/obj/effect/hotspot::our_hot_group, /datum/hot_group::spot_list, b_many = TRUE)
	param(nameof(starting_volume), pos = 1)
	param(nameof(starting_temperature), pos = 2)

/// The fire's starting volume and temperature (its constructor params).
/obj/effect/hotspot/var/starting_volume
/obj/effect/hotspot/var/starting_temperature

// ALLOW(init/INSTANCE_STATE): a hotspot joins the air system's hotspots and a hot group, exposes its turf, and faces a random way
/obj/effect/hotspot/Initialize(mapload)
	. = ..()
	SSair.hotspots += src
	if(!isnull(starting_volume))
		volume = starting_volume
	if(!isnull(starting_temperature))
		temperature = starting_temperature
		if(temperature <= FREON_MAXIMUM_BURN_TEMPERATURE)
			cold_fire = TRUE

	var/turf/open/our_turf = loc
	//on creation we check adjacent turfs for hot spot to start grouping, if surrounding do not have hot spots we create our own
	for(var/turf/open/to_check in vg_atmos_adjacent_turfs(our_turf))
		if(!to_check.active_hotspot)
			continue
		var/obj/effect/hotspot/enemy_spot = to_check.active_hotspot
		// Safeguard to prevent infectious init runtimes for hotspots if we somehow end up with a hotspot without a group
		if(!enemy_spot.our_hot_group)
			continue
		if(!our_hot_group)
			enemy_spot.our_hot_group.add_to_group(src)
		else if(our_hot_group != enemy_spot.our_hot_group) //if we belongs to a hot group from prior loop and we encounter another hot spot with a group then we merge
			our_hot_group.merge_hot_groups(enemy_spot.our_hot_group)

	if(QDELETED(our_hot_group))//if after loop through all the adjacents turfs and we havent belong to a group yet, make our own
		rel_set(src, nameof(our_hot_group), new /datum/hot_group)
		our_hot_group.add_to_group(src)

	// If our hotspot gets created on a turf with existing hotspots on it that just got spawned, abort
	if(!perform_exposure())
		if (QDELETED(src))
			return
		return INITIALIZE_HINT_QDEL

	if(QDELETED(src)) // It is actually possible for this hotspot to become qdeleted in perform_exposure() if another hotspot gets created (for example in fire_act() of fuel pools)
		return // In this case, we want to just leave and let the new hotspot take over.

	setDir(pick(GLOB.cardinals))
	air_update_turf(FALSE, FALSE)

	// fire_puff.ogg is a /tg/ asset CHOMP doesn't ship. Sound disabled until vendored.
	if(COOLDOWN_FINISHED(our_turf, fire_puff_cooldown))
		COOLDOWN_START(our_turf, fire_puff_cooldown, 5 SECONDS)

	update_color()

/obj/effect/hotspot/set_smoothed_icon_state(new_junction)

	smoothing_junction = new_junction

	update_color()

/**
 * Perform interactions between the hotspot and the gasmixture.
 *
 * For the first tick, hotspots will take a sample of the air in the turf,
 * set the temperature equal to a certain amount, and then reacts it.
 * In some implementations the ratio comes out to around 1, so all of the air in the turf.
 *
 * Afterwards if the reaction is big enough it mostly just tags along the fire,
 * copying the temperature and handling the colouring.
 * If the reaction is too small it will perform like the first tick.
 *
 * Also heats the tile's contents through their heat nodes (heat_tile()).
 * Returns TRUE if exposed successfully, and FALSE if the hotspot should delete itself
 */
/obj/effect/hotspot/proc/perform_exposure()
	var/turf/open/location = loc
	var/datum/gas_mixture/reference
	if(!istype(location) || !location.air)
		return FALSE

	if(location.active_hotspot && location.active_hotspot != src)
		// If we're attempting to spawn on a turf which *just* had a hotspot spawned on it, abort and kill ourselves
		if(location.active_hotspot.just_spawned)
			return FALSE
		// When we are spawned from a deletion signal from our previous hotspot, this can happen
		if(!QDELETED(location.active_hotspot))
			own_clear(location, nameof(location.active_hotspot), OWN_DELETE)
	rel_set(location, nameof(location.active_hotspot), src) // the turf owns its fire (deleted with it); the one it replaces was destroyed above

	bypassing = !just_spawned && (volume > CELL_VOLUME*0.95)

	//Passive mode
	if(bypassing || cold_fire)
		reference = location.air // Our color and volume will depend on the turf's gasmix
	//Active mode
	else
		var/datum/gas_mixture/affected = location.air.remove_ratio(volume/location.air.return_volume())
		if(affected) //in case volume is 0
			reference = affected // Our color and volume will depend on this small sparked gasmix
			heat_set(affected, temperature, HEAT_SOURCE_FIRE)
			affected.react(src)
			location.assume_air(affected)

	if(reference)
		volume = 0
		var/list/cached_results = reference.reaction_results
		if(cached_results) // Lazy: null until a reaction fires on the mixture.
			for (var/reaction in SSair.hotspot_reactions)
				volume += cached_results[reaction] * FIRE_GROWTH_RATE
		temperature = reference.return_temperature()

	// Handles the burning of atoms.
	if(cold_fire)
		return TRUE

	// Objects on the tile are heated through their heat nodes (H3).
	heat_tile(location)
	return TRUE

/// Mathematics to be used for color calculation.
/obj/effect/hotspot/proc/gauss_lerp(x, x1, x2)
	var/b = (x1 + x2) * 0.5
	var/c = (x2 - x1) / 6
	return NUM_E ** -((x - b) ** 2 / (2 * c) ** 2)

/obj/effect/hotspot/proc/update_color()
	cut_overlays()

	var/heat_r = heat2colour_r(temperature)
	var/heat_g = heat2colour_g(temperature)
	var/heat_b = heat2colour_b(temperature)
	var/heat_a = 255
	var/greyscale_fire = 1 //This determines how greyscaled the fire is.

	if(cold_fire)
		heat_r = 0
		heat_g = LERP(255, temperature, 1.2)
		heat_b = LERP(255, temperature, 0.9)
		heat_a = 100
	else if(temperature < 5000) //This is where fire is very orange, we turn it into the normal fire texture here.
		var/normal_amt = gauss_lerp(temperature, 1000, 3000)
		heat_r = LERP(heat_r,255,normal_amt)
		heat_g = LERP(heat_g,255,normal_amt)
		heat_b = LERP(heat_b,255,normal_amt)
		heat_a -= gauss_lerp(temperature, -5000, 5000) * 128
		greyscale_fire -= normal_amt
	if(temperature > 40000) //Past this temperature the fire will gradually turn a bright purple
		var/purple_amt = temperature < LERP(40000,200000,0.5) ? gauss_lerp(temperature, 40000, 200000) : 1
		heat_r = LERP(heat_r,255,purple_amt)
	if(temperature > 200000 && temperature < 500000) //Somewhere at this temperature nitryl happens.
		var/sparkle_amt = gauss_lerp(temperature, 200000, 500000)
		var/mutable_appearance/sparkle_overlay = mutable_appearance('icons/effects/effects.dmi', "shieldsparkles")
		sparkle_overlay.blend_mode = BLEND_ADD
		sparkle_overlay.alpha = sparkle_amt * 255
		add_overlay(sparkle_overlay)
	if(temperature > 400000 && temperature < 1500000) //Lightning because very anime.
		var/mutable_appearance/lightning_overlay = mutable_appearance('icons/effects/fire.dmi', "overcharged")
		lightning_overlay.blend_mode = BLEND_ADD
		add_overlay(lightning_overlay)
	if(temperature > 4500000) //This is where noblium happens. Some fusion-y effects.
		var/fusion_amt = temperature < LERP(4500000,12000000,0.5) ? gauss_lerp(temperature, 4500000, 12000000) : 1
		// 'icons/effects/atmospherics.dmi' is a /tg/ asset CHOMP doesn't ship.
		// Reuse the existing fire.dmi as a substitute; less "fusion-y" looking but
		// the hotspot still renders. Replace when the /tg/ asset is vendored.
		var/mutable_appearance/fusion_overlay = mutable_appearance('icons/effects/fire.dmi', "light")
		fusion_overlay.blend_mode = BLEND_ADD
		fusion_overlay.alpha = fusion_amt * 255
		var/mutable_appearance/rainbow_overlay = mutable_appearance('icons/hud/screen_gen.dmi', "druggy")
		rainbow_overlay.blend_mode = BLEND_ADD
		rainbow_overlay.alpha = fusion_amt * 255
		rainbow_overlay.appearance_flags = RESET_COLOR
		heat_r = LERP(heat_r,150,fusion_amt)
		heat_g = LERP(heat_g,150,fusion_amt)
		heat_b = LERP(heat_b,150,fusion_amt)
		add_overlay(fusion_overlay)
		add_overlay(rainbow_overlay)

	set_light_color(rgb(LERP(250, heat_r, greyscale_fire), LERP(160, heat_g, greyscale_fire), LERP(25, heat_b, greyscale_fire)))

	heat_r /= 255
	heat_g /= 255
	heat_b /= 255

	color = list(LERP(0.3, 1, 1-greyscale_fire) * heat_r,0.3 * heat_g * greyscale_fire,0.3 * heat_b * greyscale_fire, 0.59 * heat_r * greyscale_fire,LERP(0.59, 1, 1-greyscale_fire) * heat_g,0.59 * heat_b * greyscale_fire, 0.11 * heat_r * greyscale_fire,0.11 * heat_g * greyscale_fire,LERP(0.11, 1, 1-greyscale_fire) * heat_b, 0,0,0)
	alpha = heat_a

/// Reads a gas's moles from the batched `readings` record (read_gas_mixtures).
#define INSUFFICIENT(gas_id) (readings[GAS_READ_MOLES(gas_id)] < 0.5)

/**
 * One burn step, run by the kernel (burn_tick(), below) every SSair tick while it exists.
 * Handles the calling of perform_exposure() which handles the bulk of temperature processing.
 * Heating the tile's contents is also done by perform_exposure().
 * Also handles the dying and qdeletion of the hotspot and hotspot creations on adjacent cardinal turfs.
 * And some visual stuffs too! Colors and fainter icons for specific conditions.
 */
/obj/effect/hotspot/proc/burn_step()
	if(just_spawned)
		just_spawned = FALSE
		return

	var/turf/open/location = loc
	if(!istype(location))
		destroyed(src)
		return

	// Excited groups live in the Rust arena now; there's no DM group to poke a
	// cooldown reset on. Re-registering the burning turf keeps auxmos processing it.
	SSair.add_to_active(location)

	cold_fire = FALSE
	if(temperature <= FREON_MAXIMUM_BURN_TEMPERATURE)
		cold_fire = TRUE

	if((temperature < FIRE_MINIMUM_TEMPERATURE_TO_EXIST && !cold_fire) || (volume <= 1))
		destroyed(src)
		return

	//Not enough / nothing to burn. One batched read covers every fuel and oxidiser check.
	if(!location.air)
		destroyed(src)
		return
	var/list/readings = read_gas_mixtures(list(location.air))
	if((INSUFFICIENT(GAS_ID_PLASMA) && INSUFFICIENT(GAS_ID_TRITIUM) && INSUFFICIENT(GAS_ID_HYDROGEN) && INSUFFICIENT(GAS_ID_FREON)) || INSUFFICIENT(GAS_ID_OXYGEN))
		destroyed(src)
		return

	perform_exposure()

	if(bypassing)
		set_fire_stage("heavy")
		if(!cold_fire && istype(location, /turf/simulated))
			// burn_tile is on /turf/simulated in CHOMP, not /turf parent.
			var/turf/simulated/sim_loc = location
			sim_loc.burn_tile()

		//Possible spread due to radiated heat.
		var/air_temperature = location.air.return_temperature()
		if(air_temperature > FIRE_MINIMUM_TEMPERATURE_TO_SPREAD || cold_fire)
			var/radiated_temperature = air_temperature*FIRE_SPREAD_RADIOSITY_SCALE
			if(cold_fire)
				radiated_temperature = air_temperature * COLD_FIRE_SPREAD_RADIOSITY_SCALE
			for(var/t in vg_atmos_adjacent_turfs(location))
				var/turf/open/T = t
				if(!T.active_hotspot)
					T.hotspot_expose(radiated_temperature, CELL_VOLUME/4)

	else
		if(volume > CELL_VOLUME*0.4)
			set_fire_stage("medium")
		else
			set_fire_stage("light")

	if((visual_update_tick++ % 7) == 0)
		update_color()

	return TRUE

/obj/effect/hotspot/proc/set_fire_stage(stage)
	if(fire_stage == stage)
		return
	fire_stage = stage
	icon_state = stage
	dir = pick(GLOB.cardinals)
	update_color()

// a dying fire cools its tile and leaves its hot group.
/obj/effect/hotspot/lifecycle_dematerialize()
	..()
	SSair.hotspots -= src

/obj/effect/hotspot/on_destroy(force)
	var/turf/open/cur_turf = loc
	if(istype(cur_turf))
		cool_tile(cur_turf)
	// Leaving the group retires it when we were its last hotspot (remove_from_group()). The
	// turf's active_hotspot var lets go of us by itself (phase 2).
	our_hot_group?.remove_from_group(src)
	..()

/obj/effect/hotspot/Crossed(atom/movable/AM, oldloc)
	. = ..()
	on_entered(loc, AM, oldloc)

/// Something entered our turf: Crossed().
/obj/effect/hotspot/proc/on_entered(datum/source, atom/movable/arrived, atom/old_loc, list/atom/old_locs)
	if(cold_fire)
		return
	if(isliving(arrived))
		var/mob/living/immolated = arrived
		immolated.fire_act(temperature, volume)
	else if(arrived.heats_in_fire())
		arrived.couple_to_fire(loc)

/obj/effect/hotspot/singularity_pull(atom/singularity, current_size)
	return

/datum/looping_sound/fire
	// fireclip1..7.ogg are /tg/ assets CHOMP doesn't ship. Empty
	// mid_sounds list makes the loop silent until vendored.
	mid_sounds = list()
	volume = 30
	mid_length = 2 SECONDS
	// falloff_distance is a /tg/-specific looping_sound var; CHOMP
	// doesn't have it. Removed.

#define MIN_SIZE_SOUND 2
///handle the grouping of hotspot and then determining an average center to play sound in
/datum/hot_group
	/// Member hotspots (two-sided with each hotspot's our_hot_group). The group is kept alive
	/// by its members and retires itself when the last one leaves (remove_from_group()).
	var/list/obj/effect/hotspot/spot_list
	///the sound center turf which the looping sound will play
	var/turf/open/current_sound_loc
	var/datum/looping_sound/fire/sound
	var/tiles_limit = 80 // arbitrary limit so we dont have one giant group
	var/average_x
	var/average_y
	var/average_Z
	///the range for the sound to drop off based on the size of the group
	var/drop_off_dist
	COOLDOWN_DECLARE(update_sound_center)

CAPABILITIES(/datum/hot_group)
	ref_one(nameof(current_sound_loc))
	owns_one(nameof(sound), /datum/looping_sound/fire)


/datum/hot_group/proc/remove_from_group(obj/effect/hotspot/target)
	rel_remove(src, nameof(spot_list), target)
	if(!length(spot_list))
		spent(src)
		return

/datum/hot_group/proc/add_to_group(obj/effect/hotspot/target)
	if(QDELETED(target))
		return
	rel_add(src, nameof(spot_list), target)
	if(COOLDOWN_FINISHED(src, update_sound_center) && length(spot_list) > MIN_SIZE_SOUND)//arbitrary size to start playing the sound
		update_sound()
		COOLDOWN_START(src, update_sound_center, 5 SECONDS)

/datum/hot_group/proc/merge_hot_groups(datum/hot_group/enemy_group)
	if(length(spot_list) >= tiles_limit || length(enemy_group.spot_list) >= tiles_limit)
		return
	var/datum/hot_group/saving_group
	var/datum/hot_group/sacrificial_group
	if(length(spot_list) > length(enemy_group.spot_list) || (length(spot_list) == length(enemy_group.spot_list) && prob(50)))//we're bigger take all of their territory!
		saving_group = src
		sacrificial_group = enemy_group
	else
		saving_group = enemy_group
		sacrificial_group = src
	// Two-sided: re-pointing a hotspot moves it between the groups' spot_lists.
	for(var/obj/effect/hotspot/reference as anything in sacrificial_group.spot_list?.Copy())
		rel_set(reference, nameof(reference.our_hot_group), saving_group)
	consumed(sacrificial_group, src)
	if(COOLDOWN_FINISHED(src, update_sound_center) && length(spot_list) > MIN_SIZE_SOUND)//arbitrary size to start playing the sound
		update_sound()
		COOLDOWN_START(src, update_sound_center, 5 SECONDS)

/datum/hot_group/proc/update_sound()
	//we can draw a cross around the average middle of any globs of group, curves or hollow groups may cause issues with this
	var/min_x = INFINITY
	var/max_x = 0
	var/min_y = INFINITY
	var/max_y = 0
	var/min_z = INFINITY
	var/max_z = 0
	for(var/obj/effect/hotspot/spot as anything in spot_list)
		var/turf/open/spot_turf = spot.loc
		if(!istype(spot_turf))
			continue
		min_x = min(min_x, spot_turf.x)
		max_x = max(max_x, spot_turf.x)
		min_y = min(min_y, spot_turf.y)
		max_y = max(max_y, spot_turf.y)
		min_z = min(min_z, spot_turf.z)
		max_z = max(max_z, spot_turf.z)
	if(min_x == INFINITY)
		return
	average_x = round((max_x + min_x) / 2)
	average_y = round((max_y + min_y) / 2)
	average_Z = round((min_z + max_z) / 2)
	drop_off_dist = max(max_y - min_y, max_x - min_x, 1)// pick the largest value between the width and length of the group to determine sound drop off
	var/turf/open/sound_turf = locate(average_x, average_y, average_Z)
	if(sound)
		sound.falloff_distance = drop_off_dist
		sound.extra_range = drop_off_dist
		if(sound_turf != current_sound_loc)
			rel_set(sound, nameof(sound.parent), sound_turf)
			rel_set(src, nameof(current_sound_loc), sound_turf)
		return
	rel_set(src, nameof(sound), new /datum/looping_sound/fire(sound_turf, TRUE))
	sound.falloff_distance = drop_off_dist
	sound.extra_range = drop_off_dist
	rel_set(src, nameof(current_sound_loc), sound_turf)

#undef MIN_SIZE_SOUND
#undef INSUFFICIENT

// ---------------------------------------------------------------- the hotspot pipeline

/// A hotspot burns as kernel work instead of SSair's hotspot pass: one step every SSair tick (the cadence the pass
/// had) for as long as it exists, in the game and post-game run levels. It never idles -- a hotspot that has nothing
/// left to burn deletes itself, which takes it out of the kernel's membership.
/obj/effect/hotspot/reactions()
	. = ..()
	. += every(0.5 SECONDS, PROC_REF(burn_tick), when = PROC_REF(burn_ready), lane = LANE_SIMULATION)

/// The run levels the burn steps in.
/obj/effect/hotspot/proc/burn_ready()
	return !!((RUNLEVEL_GAME | RUNLEVEL_POSTGAME) & (1 << (Kernel.current_runlevel - 1)))

/// The kernel work item's handler: one burn step.
/obj/effect/hotspot/proc/burn_tick(dt)
	burn_step()

