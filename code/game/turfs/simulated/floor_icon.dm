GLOBAL_DATUM_INIT(no_ceiling_image, /image, new)

/proc/cache_no_ceiling_image()
	GLOB.no_ceiling_image = image(icon = 'icons/turf/open_space.dmi', icon_state = "no_ceiling")
	GLOB.no_ceiling_image.plane = PLANE_MESONS

/// The icon_state a floor with flooring shows: the variant it rolled, else the flooring's base (suffixed with the season where it has one).
/turf/simulated/floor/proc/floor_base_state()
	if(flooring_override)
		return flooring_override
	if(flooring.check_season)
		return "[flooring.icon_base]-[GLOB.world_time_season]"
	return flooring.icon_base

/// Whether the tile shows the damaged-plating sprite (bare plating that is broken or burnt).
/turf/simulated/floor/proc/shows_damaged_plating()
	return is_plating() && (!isnull(broken) || !isnull(burnt))

/// The icon_state the floor draws, as a function of the state it draws from (the neighbours compare against it for the edges that spill).
/turf/simulated/floor/edge_look_state()
	if(scorch_state)
		return scorch_state
	if(shows_damaged_plating())
		return "dmg[plating_damage_state]"
	if(flooring)
		return floor_base_state()
	if(plating_exposed)
		return base_icon_state
	return icon_state

/turf/simulated/floor/edge_key()
	return "[flooring?.type]|[edge_look_state()]|[density]"

/// A floor draws its flooring, the edges and corners its neighbours leave it (edge_mask), the edges that spill onto it (edge_spill), its decals,
/// its damage and the open space above it (no_ceiling). The neighbours reach it only through those masks (code/game/turfs/turf_edges.dm).
/turf/simulated/floor/draw(datum/look/look)
	..()
	if(flooring)
		look_flooring(look)
	else if(plating_exposed)
		look.set_icon(base_icon)
		look.state(base_icon_state)

	// Floor decals.
	for(var/image/decal as anything in decals)
		look.overlay(decal)

	if(shows_damaged_plating())
		look.set_icon('icons/turf/flooring/plating.dmi')
		look.state("dmg[plating_damage_state]")
	else if(flooring)
		look_flooring_damage(look)

	if(scorch_state)
		look.state(scorch_state)

	// Show 'ceilingless' overlay.
	if(no_ceiling)
		look.overlay(GLOB.no_ceiling_image)

	// Our 'them-to-us' edges, aka edges from external turfs we feel should spill onto us.
	for(var/image/spill_image as anything in edge_spill)
		look.overlay(spill_image)

/// What the flooring gives the tile: its name and description, its icon and the sprite it was laid with, and its edges, outer corners and inner
/// corners (the border bits of edge_mask are the cardinals, the inner corners sit above them). The flooring is a shared definition that never changes.
/turf/simulated/floor/proc/look_flooring(datum/look/look)
	look.identity(flooring.name, flooring.desc)
	look.set_icon(flooring.icon)
	look.state(floor_base_state())
	var/has_border = edge_mask & ADJ_CARDINAL
	var/inner_corners = edge_mask >> 4
	if(has_border || inner_corners)
		for(var/image/edge_image as anything in flooring.get_edge_overlays(has_border, inner_corners))
			look.overlay(edge_image)

/// The broken and burnt overlays of a flooring that can break or burn.
/turf/simulated/floor/proc/look_flooring_damage(datum/look/look)
	if(!isnull(broken) && (flooring.flags & TURF_CAN_BREAK))
		if(istype(src, /turf/simulated/floor/wood))
			look.overlay(flooring.get_flooring_overlay("[flooring.icon_base]-broken-[broken]","[flooring.icon_base]-broken[broken]"))
		else
			look.overlay(flooring.get_flooring_overlay("[flooring.icon_base]-broken-[broken]","broken[broken]"))
	if(!isnull(burnt) && (flooring.flags & TURF_CAN_BURN))
		look.overlay(flooring.get_flooring_overlay("[flooring.icon_base]-burned-[burnt]","burned[burnt]"))

/// The cardinal borders and inner corners of this tile's flooring (packed as the draw reads them), the edges that spill onto it, and whether the
/// open space above shows through: written by the adjacency index when this tile or a neighbour changed (code/game/turfs/turf_edges.dm).
/turf/simulated/floor/var/edge_mask = 0
/turf/simulated/floor/var/no_ceiling = FALSE
TRACKED(/turf/simulated/floor, edge_mask)
/// The edge overlays the stronger turfs around spill onto this one (null for none): floors and open space draw them.
/turf/simulated/var/list/edge_spill
TRACKED(/turf/simulated, edge_spill)
TRACKED(/turf/simulated/floor, no_ceiling)

/turf/simulated/floor/edges_changed(mask)
	..()
	set_edge_mask(floor_edge_mask())
	var/list/spill = (edge_blending_priority && !forbid_turf_edge()) ? edge_spill_overlays() : null
	if(!same_images(edge_spill, spill)) // the cached overlays are shared, so equal lists name the same images
		set_edge_spill(spill)
	var/turf/above = GetAbove(src)
	set_no_ceiling(!is_outdoors() && above && isopenspace(above) ? TRUE : FALSE) // This won't apply to outdoor turfs since its assumed they don't have a ceiling anyways.
	log_edge_trace("[type] at [x],[y],[z]: border/corner mask [edge_mask], [length(edge_spill)] spill, ceiling gap [no_ceiling]")

/// Whether two lists (either may be null) hold the same shared images in the same order.
/proc/same_images(list/a, list/b)
	if(length(a) != length(b))
		return FALSE
	for(var/i in 1 to length(a))
		if(a[i] != b[i])
			return FALSE
	return TRUE

/// The edges and corners the flooring draws against the eight neighbours: the cardinal borders (the neighbour does not link) and the inner
/// corners (linked on both cardinals but not on the diagonal), the corners shifted above the borders.
/turf/simulated/floor/proc/floor_edge_mask()
	if(!flooring || !(flooring.flags & TURF_HAS_EDGES))
		return 0
	var/has_border = 0
	for(var/step_dir in GLOB.cardinal)
		if(!flooring.test_link(src, get_step(src, step_dir)))
			has_border |= step_dir
	//Note: Doesn't actually check northeast, this is bitmath to check if we're edge'd (aka not smoothed) to NORTH and EAST
	//North = 0001, East = 0100, Northeast = 0101, so (North|East) == Northeast, therefore (North|East)&Northeast == Northeast
	var/inner_corners = 0
	if(flooring.flags & TURF_HAS_CORNERS)
		//Like above but checking for NO similar bits rather than both similar bits.
		// One bit per GLOB.cornerdirs index: the diagonals share direction bits, so OR-ing
		// the dirs themselves would turn NE|SW into all four corners.
		for(var/i in 1 to length(GLOB.cornerdirs))
			var/corner_dir = GLOB.cornerdirs[i]
			if((has_border & corner_dir) == 0 && !flooring.test_link(src, get_step(src, corner_dir))) //Connected on both cardinals, but not the diagonal
				inner_corners |= (1 << (i - 1))
	return has_border | (inner_corners << 4)

/// The overlays of the stronger neighbours' edges that spill onto this tile (null for none): a neighbour that is a simulated turf with a higher
/// edge_blending_priority than ours, a different state, and nothing on it that forbids edges.
/turf/simulated/proc/edge_spill_overlays()
	var/list/spill
	var/our_state = edge_look_state()
	for(var/checkdir in GLOB.cardinal) // Check every direction
		var/turf/simulated/T = get_step(src, checkdir) // Get the turf in that direction
		// Our conditions:
		// Has to be a /turf/simulated
		// Has to have it's own edge_blending_priority
		// Has to have a higher priority than us
		// Their state is not our state
		// They don't forbid_turf_edge
		if(istype(T) && T.edge_blending_priority && edge_blending_priority < T.edge_blending_priority && our_state != T.edge_look_state() && !T.forbid_turf_edge())
			var/edge_state = T.get_edge_icon_state()
			LAZYADD(spill, CACHED_KEY(turf_edge_overlays, "[edge_state]-[checkdir]", T.icon_edge, edge_state, checkdir)) // Usually [icon_state]-[dirnum]
	return spill

//Tests whether this flooring will smooth with the specified turf
//You can override this if you want a flooring to have super special snowflake smoothing behaviour
/datum/decl/flooring/proc/test_link(turf/origin, turf/T, countercheck = FALSE)

	var/is_linked = FALSE
	if (countercheck)
		//If this is a countercheck, we skip all of the above, start off with true, and go straight to the atom lists
		is_linked = TRUE
	else if(T)

		//If it's a wall, use the wall_smooth setting
		if(istype(T, /turf/simulated/wall))
			if(wall_smooth == SMOOTH_ALL)
				is_linked = TRUE

		//If it's space or openspace, use the space_smooth setting
		else if(isspace(T) || isopenspace(T))
			if(space_smooth == SMOOTH_ALL)
				is_linked = TRUE

		//If we get here then its a normal floor
		else if (istype(T, /turf/simulated/floor))
			var/turf/simulated/floor/t = T
			//If the floor is the same as us,then we're linked,
			if (t.flooring?.type == type)
				is_linked = TRUE
				/*
					But there's a caveat. To make atom black/whitelists work correctly, we also need to check that
					they smooth with us. Ill call this counterchecking for simplicity.
					This is needed to make both turfs have the correct borders

					To prevent infinite loops we have a countercheck var, which we'll set true
				*/

				if (smooth_movable_atom != SMOOTH_NONE)
					//We do the countercheck, passing countercheck as true
					is_linked = test_link(T, origin, countercheck = TRUE)

			else if (floor_smooth == SMOOTH_ALL)
				is_linked = TRUE

			else if (floor_smooth != SMOOTH_NONE)
				//If we get here it must be using a whitelist or blacklist
				if (floor_smooth == SMOOTH_WHITELIST)
					for (var/v in flooring_whitelist)
						if (istype(t.flooring, v))
							//Found a match on the list
							is_linked = TRUE
							break
				else if(floor_smooth == SMOOTH_BLACKLIST)
					is_linked = TRUE //Default to true for the blacklist, then make it false if a match comes up
					for (var/v in flooring_blacklist)
						if (istype(t.flooring, v))
							//Found a match on the list
							is_linked = FALSE
							break

	//Alright now we have a preliminary answer about smoothing, however that answer may change with the following
	//Atom lists!
	var/best_priority = -1
	//A white or blacklist entry will only override smoothing if its priority is higher than this
	//And then this value becomes its priority
	if (smooth_movable_atom != SMOOTH_NONE)
		if (smooth_movable_atom == SMOOTH_WHITELIST || smooth_movable_atom == SMOOTH_GREYLIST)
			for (var/list/v in movable_atom_whitelist)
				var/d_type = v[1]
				var/list/d_vars = v[2]
				var/d_priority = v[3]
				//Priority is the quickest thing to check first
				if (d_priority <= best_priority)
					continue

				//Ok, now we start testing all the atoms in the target turf
				FOR_CONTENTS(var/a, T) //No implicit typecasting here, faster

					if (istype(a, d_type))
						//It's the right type, so we're sure it will have the vars we want.

						var/atom/movable/AM = a
						//Typecast it to a movable atom
						//Lets make sure its in the way before we consider it
						if (!AM.is_between_turfs(origin, T))
							continue

						//From here on out, we do dangerous stuff that may runtime if the coder screwed up


						var/match = TRUE
						for (var/d_var in d_vars)
							//For each variable we want to check
							if (AM.vars[d_var] != d_vars[d_var])
								//We get a var of the same name from the atom's vars list.
								//And check if it equals our desired value
								match = FALSE
								break //If any var doesn't match the desired value, then this atom is not a match, move on


						if (match)
							//If we've successfully found an atom which matches a list entry
							best_priority = d_priority //This one is king until a higher priority overrides it

							//And this is a whitelist, so this match forces is_linked to true
							is_linked = TRUE


		if (smooth_movable_atom == SMOOTH_BLACKLIST || smooth_movable_atom == SMOOTH_GREYLIST)
			//All of this blacklist code is copypasted from above, with only minor name changes
			for (var/list/v in movable_atom_blacklist)
				var/d_type = v[1]
				var/list/d_vars = v[2]
				var/d_priority = v[3]
				//Priority is the quickest thing to check first
				if (d_priority <= best_priority)
					continue

				//Ok, now we start testing all the atoms in the target turf
				FOR_CONTENTS(var/a, T) //No implicit typecasting here, faster

					if (istype(a, d_type))
						//It's the right type, so we're sure it will have the vars we want.

						var/atom/movable/AM = a
						//Typecast it to a movable atom
						//Lets make sure its in the way before we consider it
						if (!AM.is_between_turfs(origin, T))
							continue

						//From here on out, we do dangerous stuff that may runtime if the coder screwed up

						var/match = TRUE
						for (var/d_var in d_vars)
							//For each variable we want to check
							if (AM.vars[d_var] != d_vars[d_var])
								//We get a var of the same name from the atom's vars list.
								//And check if it equals our desired value
								match = FALSE
								break //If any var doesn't match the desired value, then this atom is not a match, move on


						if (match)
							//If we've successfully found an atom which matches a list entry
							best_priority = d_priority //This one is king until a higher priority overrides it

							//And this is a blacklist, so this match forces is_linked to false
							is_linked = FALSE

	return is_linked
