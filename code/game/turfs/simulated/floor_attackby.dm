// Tool work on floors (removing coverings, welding and cutting plating) is the
// floor construction graph: floor_construction.dm.

/turf/simulated/floor/proc/lay_flooring(obj/item/stack/S, datum/decl/flooring/use_flooring)
	if(!is_plating())
		return
	if(S.use(use_flooring.build_cost))
		set_flooring(use_flooring)
		if(S.color)
			color = S.color
		play_sfx(src, SFX_ITEMS_DECONSTRUCT, 1.6)

/turf/simulated/floor/proc/floor_item_help(datum/act/op/act)
	return floor_item(act, I_HELP)

/turf/simulated/floor/proc/floor_item_disarm(datum/act/op/act)
	return floor_item(act, I_DISARM)

/turf/simulated/floor/proc/floor_item_grab(datum/act/op/act)
	return floor_item(act, I_GRAB)

/turf/simulated/floor/proc/floor_item_hurt(datum/act/op/act)
	return floor_item(act, I_HURT)

/// Old attackby: the turf's own handling and signal listeners first, then graffiti, hitting the tile, roofing, and laying or replacing floor.
/turf/simulated/floor/proc/floor_item(datum/act/op/act, stance)
	var/mob/user = act.actor
	var/obj/item/C = act.held

	if(!C || !user)
		return OP_DECLINE
	var/click_parameters = dq_interaction_click_params(user)

	// The turf's own handling (dig, bag pickup) and signal listeners, as the old ..() ran them first.
	if(turf_item(user, C))
		return OP_OK
	if(attackby_stopped(src, C, user, click_parameters))
		return OP_OK

	if(isliving(user) && istype(C, /obj/item))
		var/mob/living/L = user
		if(stance != I_HELP)
			if(stance == I_GRAB)
				try_graffiti(L, C, click_parameters) // back by unpopular demand - Add - Click parameters
				return OP_PASS
			attack_tile(C, L) // Keep combat mode off if you want to decon something.
			return OP_PASS

	// Multi-z roof building
	if(istype(C, /obj/item/stack/tile/roofing))
		var/expended_tile = FALSE // To track the case. If a ceiling is built in a multiz zlevel, it also necessarily roofs it against weather
		var/turf/T = GetAbove(src)
		var/obj/item/stack/tile/roofing/R = C

		// Patch holes in the ceiling
		if(T)
			if(isopenturf(T))
				// Must be build adjacent to an existing floor/wall, no floating floors
				var/list/cardinalTurfs = list() // Up a Z level
				for(var/dir in GLOB.cardinal)
					var/turf/B = get_step(T, dir)
					if(B)
						cardinalTurfs += B

				var/turf/simulated/A = locate_in_list(cardinalTurfs, /turf/simulated/floor)
				if(!A)
					A = locate_in_list(cardinalTurfs, /turf/simulated/wall)
				if(!A)
					to_chat(user, span_warning("There's nothing to attach the ceiling to!"))
					return OP_PASS

				if(R.use(1)) // Cost of roofing tiles is 1:1 with cost to place lattice and plating
					T.ReplaceWithLattice()
					T.ChangeTurf(/turf/simulated/floor, preserve_outdoors = TRUE)
					play_sfx(src, SFX_WEAPONS_GENHIT)
					act_message(user, null, MSG_SELF(span_notice("You patch a hole in the ceiling.")), \
						MSG_OTHERS(span_notice("%U% patches a hole in the ceiling.")))
					expended_tile = TRUE
			else
				to_chat(user, span_warning("There aren't any holes in the ceiling to patch here."))
				return OP_PASS

		// Create a ceiling to shield from the weather
		if(src.is_outdoors())
			for(var/dir in GLOB.cardinal)
				var/turf/A = get_step(src, dir)
				if(A && !A.is_outdoors())
					if(expended_tile || R.use(1))
						make_indoors()
						play_sfx(src, SFX_WEAPONS_GENHIT)
						act_message(user, null, MSG_SELF(span_notice("You roof this tile, shielding it from the elements.")), \
							MSG_OTHERS(span_notice("%U% roofs a tile, shielding it from the elements.")))
					break
		return OP_PASS

	// Floor has flooring set
	if(!is_plating())
		if(istype(C, /obj/item/stack/cable_coil))
			to_chat(user, span_warning("You must remove the [flooring.descriptor] first."))
			return OP_PASS
		else if(istype(C, /obj/item/stack/tile))
			if(try_replace_tile(C, user))
				return OP_PASS
			else if(istype(C, /obj/item/stack/tile/floor)) // While we're at it, let's see if this is a raw patch of natural sand, dirt, or whatever that you're trying to put a plating on.
				if(!flooring.build_type && can_be_plated && !((flooring.flags & TURF_REMOVE_WRENCH) || (flooring.flags & TURF_REMOVE_CROWBAR) || (flooring.flags & TURF_REMOVE_SCREWDRIVER) || (flooring.flags & TURF_REMOVE_SHOVEL)))
					for(var/obj/structure/P in contents)
						if(istype(P, /obj/structure/flora))
							to_chat(user, span_warning("The [P.name] is in the way, you'll have to get rid of it first."))
							return OP_PASS
					var/obj/item/stack/tile/floor/S = C
					if (S.get_amount() < 1)
						return OP_PASS
					S.use(1)
					play_sfx(src, SFX_WEAPONS_GENHIT)
					ChangeTurf(/turf/simulated/floor, preserve_outdoors = TRUE)
					if(S.color)
						color = S.color
					return OP_PASS
		else if(istype(C, /obj/item))
			try_deconstruct_tile(C, user)
			return OP_PASS

	// Floor is plating (or no flooring)
	else
		// Placing wires on plating
		if(istype(C, /obj/item/stack/cable_coil))
			if(broken || burnt)
				to_chat(user, span_warning("This section is too damaged to support anything. Use a welder to fix the damage."))
				return OP_PASS
			var/obj/item/stack/cable_coil/coil = C
			coil.turf_place(src, user)
			return OP_PASS
		// Placing flooring on plating
		else if(istype(C, /obj/item/stack))
			if(broken || burnt)
				to_chat(user, span_warning("This section is too damaged to support anything. Use a welder to fix the damage."))
				return OP_PASS
			var/obj/item/stack/S = C
			var/datum/decl/flooring/use_flooring
			for(var/flooring_type in GLOB.flooring_types)
				var/datum/decl/flooring/F = GLOB.flooring_types[flooring_type]
				if(!F.build_type)
					continue
				if((S.type == F.build_type) || (S.build_type == F.build_type))
					use_flooring = F
					break
			if(!use_flooring)
				return OP_PASS
			// Do we have enough?
			if(use_flooring.build_cost && S.get_amount() < use_flooring.build_cost)
				to_chat(user, span_warning("You require at least [use_flooring.build_cost] [S.name] to complete the [use_flooring.descriptor]."))
				return OP_PASS
			// Stay still and focus...
			task_timed(user, use_flooring.build_time || 0, src, src, PROC_REF(lay_flooring), list(S, use_flooring))
			return OP_PASS
	return OP_PASS

/turf/simulated/floor/proc/try_deconstruct_tile(obj/item/W as obj, mob/user as mob)
	if(istype(W, /obj/item/stack/tile) && isliving(user)) //If we're hitting it with a tile, try to check our offhand
		var/mob/living/deconstructor = user
		W = deconstructor.get_inactive_hand()
		if(!W || !istype(W, /obj/item))
			return FALSE
	// A tool in the other hand while laying tiles (try_replace_tile()). Held tools use the graph's edges.
	if(W.has_tool_quality(TOOL_CROWBAR))
		if(!(broken || burnt || (flooring.flags & (TURF_IS_FRAGILE | TURF_REMOVE_CROWBAR))))
			return FALSE
		pry_covering(user)
		playsound(src, W.usesound, 80, 1)
		return TRUE
	else if(W.has_tool_quality(TOOL_SCREWDRIVER) && (flooring.flags & TURF_REMOVE_SCREWDRIVER))
		if(broken || burnt)
			return FALSE
		to_chat(user, span_notice("You unscrew and remove the [flooring.descriptor]."))
		make_plating(TRUE)
		playsound(src, W.usesound, 80, 1)
		return TRUE
	else if(W.has_tool_quality(TOOL_WRENCH) && (flooring.flags & TURF_REMOVE_WRENCH))
		to_chat(user, span_notice("You unwrench and remove the [flooring.descriptor]."))
		make_plating(TRUE)
		playsound(src, W.usesound, 80, 1)
		return TRUE
	else if(istype(W, /obj/item/shovel) && (flooring.flags & TURF_REMOVE_SHOVEL))
		to_chat(user, span_notice("You shovel off the [flooring.descriptor]."))
		make_plating(TRUE)
		play_sfx(src, SFX_ITEMS_DECONSTRUCT, 1.6)
		return TRUE
	return FALSE

/turf/simulated/floor/proc/try_replace_tile(obj/item/stack/tile/T as obj, mob/user as mob)
	if(T.type == flooring.build_type)
		return
	var/obj/item/W = user.is_holding_item_of_type(/obj/item)
	if(!istype(W))
		return
	if(!try_deconstruct_tile(W, user))
		return
	if(flooring && !flooring.is_plating)
		return
	attackby(T, user)

/// Replaces the plating with what lies under it (floor_construction.dm cuts it).
/turf/simulated/floor/proc/do_remove_plating(base_type)
	// Keep in mind, turfs can never actually be deleted in byond, after this line
	// our turf is just 'magically changed' to the new type and src refers to that
	ChangeTurf(base_type, preserve_outdoors = TRUE)

	var/static/list/floors_that_need_lattice = list(
		/turf/space,
		/turf/simulated/open
	)
	if(is_type_in_list(src, floors_that_need_lattice))
		new /obj/structure/lattice(src)
