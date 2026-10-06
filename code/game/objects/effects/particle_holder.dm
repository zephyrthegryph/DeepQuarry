///objects can only have one particle on them at a time, so we use these abstract effects to hold and display the effects. You know, so multiple particle effects can exist at once.
///also because some objects do not display particles due to how their visuals are built
/obj/effect/abstract/particle_holder
	name = "particle holder"
	desc = "How are you reading this? Please make a bug report :)"
	appearance_flags = KEEP_APART|KEEP_TOGETHER|TILE_BOUND|PIXEL_SCALE|LONG_GLIDE|RESET_COLOR //movable appearance_flags plus KEEP_APART and KEEP_TOGETHER
	vis_flags = VIS_INHERIT_PLANE
	layer = ABOVE_MOB_LAYER
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	anchored = TRUE
	/// Holds info about how this particle emitter works
	/// See \code\__DEFINES\particles.dm
	var/particle_flags = NONE

	var/atom/parent

CAPABILITIES(/obj/effect/abstract/particle_holder)
	param(nameof(particle_path), pos = 1)
	param(nameof(particle_flags), pos = 2)

/// The particles a holder shows (its constructor param).
/obj/effect/abstract/particle_holder/var/particle_path = /particles/smoke

// ALLOW(init/INSTANCE_STATE): a particle holder leaves the map for its parent's vis_contents and makes its particles
/obj/effect/abstract/particle_holder/Initialize(mapload)
	. = ..()
	if(!loc)
		stack_trace("particle holder was created with no loc!")
		return INITIALIZE_HINT_QDEL

	if(loc.plane == TURF_PLANE)
		vis_flags &= ~VIS_INHERIT_PLANE // don't yoink the floor plane. we'll just sit on game plane, it's fine

	// We nullspace ourselves because some objects use their contents (e.g. storage) and some items may drop everything in their contents on deconstruct.
	rel_set(src, nameof(parent), loc)
	moveToNullspace()

	// Mouse opacity can get set to opaque by some objects when placed into the object's contents (storage containers).
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	particles = new particle_path()
	// /atom doesn't have vis_contents, /turf and /atom/movable do
	var/atom/movable/lie_about_areas = get_parent()
	lie_about_areas.vis_contents += src
	observe(get_parent(), /datum/notice/qdeleting, src, then(PROC_REF(parent_deleted)))

	if(particle_flags & PARTICLE_ATTACH_MOB)
		observe(get_parent(), /datum/notice/moved, src, then(PROC_REF(on_parent_moved)))
	on_move(get_parent(), null, NORTH)


/// Non movables don't delete contents on destroy, so we gotta do this
/obj/effect/abstract/particle_holder/proc/parent_deleted(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	consume(src)

/// Hooked on the parent's moved event.
/obj/effect/abstract/particle_holder/proc/on_parent_moved(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/atom/movable/attached = A.target
	var/datum/notice/moved/event = A
	on_move(attached, event.old_loc, event.direction)

/// called when a parent that's been hooked into this moves
/// does a variety of checks to ensure overrides work out properly
/obj/effect/abstract/particle_holder/proc/on_move(atom/movable/attached, atom/oldloc, direction)
	SHOULD_NOT_SLEEP(TRUE)

	if(!(particle_flags & PARTICLE_ATTACH_MOB))
		return

	//remove old
	if(ismob(oldloc))
		var/mob/particle_mob = oldloc
		particle_mob.vis_contents -= src

	// If we're sitting in a mob, we want to emit from it too, for vibes and shit
	if(ismob(attached.loc))
		var/mob/particle_mob = attached.loc
		particle_mob.vis_contents += src

/// Sets the particles position to the passed coordinates
/obj/effect/abstract/particle_holder/proc/set_particle_position(x = 0, y = 0, z = 0)
	particles.position = list(x, y, z)

/// Relation view: parent (reads null once it is gone).
/obj/effect/abstract/particle_holder/proc/get_parent() as /atom
	return parent
