DECLARE_SHARED_CACHE(cliff_overlays, GLOBAL_PROC_REF(build_cliff_overlay), SC_NEVER)

/// Builder for cliff_overlays: the ground above a cliff, cut to the cliff's subtraction mask.
/proc/build_cliff_overlay(cliff_icon, subtraction_icon_state, ground_icon, ground_state, ground_dir, layer)
	var/icon/underlying_ground = icon(ground_icon, ground_state, ground_dir)
	var/icon/subtract = icon(cliff_icon, subtraction_icon_state)
	underlying_ground.Blend(subtract, ICON_SUBTRACT)
	var/image/final = image(underlying_ground)
	final.layer = layer
	return final

/*
Cliffs give a visual illusion of depth by seperating two places while presenting a 'top' and 'bottom' side.

Mobs moving into a cliff from the bottom side will simply bump into it and be denied moving into the tile,
where as mobs moving into a cliff from the top side will 'fall' off the cliff, forcing them to the bottom, causing significant damage and stunning them.

Mobs can climb this while wearing climbing equipment by clickdragging themselves onto a cliff, as if it were a table.

Flying mobs can pass over all cliffs with no risk of falling.

Projectiles and thrown objects can pass, however if moving upwards, there is a chance for it to be stopped by the cliff.
This makes fighting something that is on top of a cliff more challenging.

As a note, dir points upwards, e.g. pointing WEST means the left side is 'up', and the right side is 'down'.

When mapping these in, be sure to give at least a one tile clearance, as NORTH facing cliffs expand to
two tiles on initialization, and which way a cliff is facing may change during maploading.
*/

/obj/structure/cliff
	name = "cliff"
	desc = "A steep rock ledge. You might be able to climb it if you feel bold enough."
	icon = 'icons/obj/flora/rocks.dmi'

	anchored = TRUE
	density = TRUE
	opacity = FALSE
	unacidable = TRUE
	block_turf_edges = TRUE // Don't want turf edges popping up from the cliff edge.
	plane = TURF_PLANE

	var/icon_variant = null // Used to make cliffs less repeative by having a selection of sprites to display.
	var/corner = FALSE // Used for icon things.
	var/ramp = FALSE // Ditto.
	var/bottom = FALSE // Used for 'bottom' typed cliffs, to avoid infinite cliffs, and for icons.

	var/is_double_cliff = FALSE // Set to true when making the two-tile cliffs, used for projectile checks.
	var/uphill_penalty = 30 // Odds of a projectile not making it up the cliff.

/obj/structure/cliff/Initialize(mapload)
	. = ..()
	register_dangerous_to_step()

CAPABILITIES(/obj/structure/cliff)
	on_notice(/datum/notice/bumped, then(PROC_REF(bumped_into)))
	climb(delay = CLIFF_CLIMB_TIME, delay_by = PROC_REF(climb_delay), gate = PROC_REF(climbing_gear_needed))

/// North facing cliffs are two tiles high and take half the time.
/obj/structure/cliff/proc/climb_delay()
	return is_double_cliff ? CLIFF_CLIMB_TIME / 2 : CLIFF_CLIMB_TIME

/// Cliff climbing requires climbing gear: null when the climber has it, else why not.
/obj/structure/cliff/proc/climbing_gear_needed(mob/living/climber)
	if(ishuman(climber))
		var/mob/living/carbon/human/H = climber
		var/obj/item/clothing/shoes/shoes = H.get_equipped_item(SLOT_ID_SHOES)
		if(shoes && shoes.rock_climbing)
			return null
	return "\The [src] is too steep to climb unassisted."

/// Phase 2: leaves the dangerous-to-step index.
/obj/structure/cliff/lifecycle_dematerialize()
	. = ..()
	unregister_dangerous_to_step()

/obj/structure/cliff/Moved(atom/oldloc)
	. = ..()
	if(.)
		var/turf/old_turf = get_turf(oldloc)
		var/turf/new_turf = get_turf(src)
		if(old_turf != new_turf)
			old_turf.unregister_dangerous_object(src)
			new_turf.register_dangerous_object(src)

// These arrange their sprites at runtime, as opposed to being statically placed in the map file.
/obj/structure/cliff/automatic
	icon_state = "cliffbuilder"
	dir = NORTH

/obj/structure/cliff/automatic/corner
	icon_state = "cliffbuilder-corner"
	dir = NORTHEAST
	corner = TRUE

// Tiny part that doesn't block, used for making 'ramps'.
/obj/structure/cliff/automatic/ramp
	icon_state = "cliffbuilder-ramp"
	dir = NORTHEAST
	density = FALSE
	ramp = TRUE

// Made automatically as needed by automatic cliffs.
/obj/structure/cliff/bottom
	bottom = TRUE

CAPABILITIES(/obj/structure/cliff/automatic)
	after_init(0, then(PROC_REF(shape_cliff)))

// Paranoid about the maploader, direction is very important to cliffs, since they may get bigger if initialized while facing NORTH.
/// Picks its look and grows its lower edge, once its neighbours exist.
/obj/structure/cliff/automatic/proc/shape_cliff(datum/act/timer/A)
	if(dir in GLOB.cardinal)
		icon_variant = pick("a", "b", "c")

	if(dir & NORTH && !bottom) // North-facing cliffs require more cliffs to be made.
		make_bottom()

	update_icon()

/obj/structure/cliff/proc/make_bottom()
	// First, make sure there's room to put the bottom side.
	var/turf/T = locate(x, y - 1, z)
	if(!istype(T))
		return FALSE

	// Now make the bottom cliff have mostly the same variables.
	var/obj/structure/cliff/bottom/bottom = new(T)
	is_double_cliff = TRUE
	bottom.set_dir(dir)
	bottom.is_double_cliff = TRUE
	bottom.icon_variant = icon_variant
	bottom.corner = corner
	bottom.ramp = ramp
	bottom.layer = layer - 0.1
	bottom.set_density(density)
	bottom.update_icon()

/obj/structure/cliff/set_dir(new_dir)
	..()
	update_icon()

DECLARE_APPEARANCE_PROC(/obj/structure/cliff, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/structure/cliff/appearance_overlays()
	. = list()
	icon_state = "cliff-[dir][icon_variant][bottom ? "-bottom" : ""][corner ? "-corner" : ""][ramp ? "-ramp" : ""]"

	// Now for making the top-side look like a different turf.
	var/turf/T = get_step(src, dir)
	if(!istype(T))
		return .

	var/subtraction_icon_state = "[icon_state]-subtract"
	var/cache_string = "[icon_state]_[T.icon]_[T.icon_state]"
	if(T && icon_exists(icon, subtraction_icon_state))
		. += CACHED_KEY(cliff_overlays, cache_string, icon, subtraction_icon_state, T.icon, T.icon_state, T.dir, layer - 0.2)

// Movement-related code.

/obj/structure/cliff/CanPass(atom/movable/mover, turf/target)
	if(isliving(mover))
		var/mob/living/L = mover
		if(dq_get_hovering(L) || L.flying) // Flying mobs can always pass.
			return TRUE
		return ..()

	// Projectiles and objects flying 'upward' have a chance to hit the cliff instead, wasting the shot.
	else if(istype(mover, /obj))
		var/obj/O = mover
		if(check_shield_arc(src, dir, O)) // This is actually for mobs but it will work for our purposes as well.
			if(prob(uphill_penalty / (1 + is_double_cliff) )) // Firing upwards facing NORTH means it will likely have to pass through two cliffs, so the chance is halved.
				return FALSE
		return TRUE

/// Something walked into it (the bump action's notice).
/obj/structure/cliff/proc/bumped_into(datum/act/act)
	var/datum/notice/bumped/N = act
	var/atom/A = N.bumper
	if(isliving(A))
		var/mob/living/L = A
		if(should_fall(L))
			fall_off_cliff(L)
			return

/obj/structure/cliff/proc/should_fall(mob/living/L)
	if(dq_get_hovering(L) || L.flying)
		return FALSE

	var/turf/T = get_turf(L)
	if(T && get_dir(T, loc) & GLOB.reverse_dir[dir]) // dir points 'up' the cliff, e.g. cliff pointing NORTH will cause someone to fall if moving SOUTH into it.
		return TRUE
	return FALSE

/obj/structure/cliff/proc/fall_off_cliff(mob/living/L)
	if(!istype(L))
		return FALSE
	var/turf/T = get_step(src, GLOB.reverse_dir[dir])
	var/displaced = FALSE

	if(dir in list(EAST, WEST)) // Apply an offset if flying sideways, to help maintain the illusion of depth.
		for(var/i = 1 to 2)
			var/turf/new_T = locate(T.x, T.y - i, T.z)
			if(!new_T || locate_on(new_T, /obj/structure/cliff))
				break
			T = new_T
			displaced = TRUE

	if(istype(T))

		var/safe_fall = FALSE
		if(ishuman(L))
			var/mob/living/carbon/human/H = L
			safe_fall = H.species.handle_falling(H, T, silent = TRUE, planetary = FALSE)

		if(safe_fall)
			visible_message(span_notice("\The [L] glides down from \the [src]."))
		else
			visible_message(span_danger("\The [L] falls off \the [src]!"))
		L.forceMove(T)

		var/harm = !is_double_cliff ? 1 : 0.5
		if(!safe_fall)
			// Do the actual hurting. Double cliffs do halved damage due to them most likely hitting twice.
			if(istype(L?.buckled_to(), /obj/vehicle)) // People falling off in vehicles will take less damage, but will damage the vehicle severely.
				var/obj/vehicle/vehicle = L?.buckled_to()
				vehicle.adjust_health(40 * harm)
				to_chat(L, span_warning("\The [vehicle] absorbs some of the impact, damaging it."))
				harm /= 2

			play_sfx(L, SFX_EFFECTS_BREAK_STONE, volume = 70)
			L.status_at_least(STAT_WEAKENED, 5 * harm)

		var/fall_time = 3
		if(displaced) // Make the fall look more natural when falling sideways.
			L.pixel_z = 32 * 2
			animate(L, pixel_z = 0, time = fall_time)
		after(src, fall_time, PROC_REF(fall_land), with = list(L, T, safe_fall, harm)) // A brief delay inbetween the two sounds helps sell the 'ouch' effect.

/obj/structure/cliff/proc/fall_land(mob/living/L, turf/T, safe_fall, harm)
	if(QDELETED(L))
		return

	if(safe_fall)
		visible_message(span_notice("\The [L] lands on \the [T]."))
		play_sfx(L, SFX_RUSTLE, extrarange = 0)
		return

	play_sfx(L, SFX_PUNCH, 1.4)
	shake_camera(L, 1, 1)

	visible_message(span_danger("\The [L] hits \the [T]!"))

	// The bigger they are, the harder they fall.
	// They will take at least 20 damage at the minimum, and tries to scale up to 40% of their endurance.
	// This scaling is capped at 100 total damage, which occurs if the thing that fell has more than 250 endurance.
	var/damage = between(20, L.get_endurance() * 0.4, 100)
	var/target_zone = ran_zone()
	L.injure(INJURY_BLUNT, damage * harm, target_zone, src, flags = INJURE_ARMORED)

	// Now fall off more cliffs below this one if they exist.
	var/obj/structure/cliff/bottom_cliff = locate_on(T, /obj/structure/cliff)
	if(bottom_cliff)
		visible_message(span_danger("\The [L] rolls down towards \the [bottom_cliff]!"))
		after(bottom_cliff, 0.5 SECONDS, TYPE_PROC_REF(/obj/structure/cliff, fall_off_cliff), with = list(L))

// This tells AI mobs to not be dumb and step off cliffs willingly.
/obj/structure/cliff/is_safe_to_step(mob/living/L)
	if(should_fall(L))
		return FALSE
	return ..()

