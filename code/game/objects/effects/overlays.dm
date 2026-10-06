/obj/effect/overlay
	name = "overlay"
	unacidable = TRUE
	var/i_attached //Added for possible image attachments to objects. For hallucinations and the like.

/obj/effect/overlay/beam //Not actually a projectile, just an effect.
	name="beam"
	icon='icons/effects/beam.dmi'
	icon_state="b_beam"
	plane = ABOVE_OBJ_PLANE
	/// Relation view: the atom the beam comes from.
	var/tmp/atom/BeamSource

/obj/effect/overlay/beam/Initialize(mapload)
	. = ..()
	expire(1 SECOND)

/obj/effect/overlay/palmtree_r
	name = "Palm tree"
	icon = 'icons/misc/beach2.dmi'
	icon_state = "palm1"
	density = TRUE
	plane = MOB_PLANE
	layer = ABOVE_MOB_LAYER
	anchored = TRUE

/obj/effect/overlay/palmtree_l
	name = "Palm tree"
	icon = 'icons/misc/beach2.dmi'
	icon_state = "palm2"
	density = TRUE
	plane = MOB_PLANE
	layer = ABOVE_MOB_LAYER
	anchored = TRUE

/obj/effect/overlay/coconut
	name = "Coconuts"
	icon = 'icons/misc/beach.dmi'
	icon_state = "coconuts"

/obj/effect/overlay/bluespacify
	name = "Bluespace"
	icon = 'icons/turf/space_vr.dmi'
	icon_state = "bluespacify"
	plane = ABOVE_PLANE

/obj/effect/overlay/wallrot
	name = "wallrot"
	desc = "Ick..."
	icon = 'icons/effects/wallrot.dmi'
	anchored = TRUE
	density = TRUE
	plane = MOB_PLANE
	layer = ABOVE_MOB_LAYER
	mouse_opacity = 0

CAPABILITIES(/obj/effect/overlay/wallrot)
	rolls(nameof(pixel_x), PROC_REF(roll_pixel_x))
	rolls(nameof(pixel_y), PROC_REF(roll_pixel_y))

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/effect/overlay/wallrot/proc/roll_pixel_x(datum/roller/R)
	return pixel_x + (R.number(-10, 10))

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/effect/overlay/wallrot/proc/roll_pixel_y(datum/roller/R)
	return pixel_y + (R.number(-10, 10))

/obj/effect/overlay/snow
	name = "snow"
	icon = 'icons/turf/overlays.dmi'
	icon_state = "snow"
	anchored = TRUE
	plane = TURF_PLANE

// Todo: Add a version that gradually reaccumulates over time by means of alpha transparency. -Spades
CAPABILITIES(/obj/effect/overlay/snow)
	op("shovel_snow", item(/obj/item/shovel), label("Shovel"), then(PROC_REF(interaction_shovel_snow)))

/// Old attackby: shovel the snow away.
/obj/effect/overlay/snow/proc/interaction_shovel_snow(datum/act/op/A)
	var/mob/user = A.actor
	act_message(user, src, others = span_notice("%U% begins to shovel away %T%."))
	task_timed(user, 4 SECONDS, target = src, receiver = src, on_done = PROC_REF(attackby_timed_done), done_args = list(user))
	return OP_PASS

/obj/effect/overlay/snow/proc/attackby_timed_done(mob/user)
	to_chat(user, span_notice("You have finished shoveling!"))
	consume(src, user)

/obj/effect/overlay/snow/floor
	icon_state = "snowfloor"
	plane = TURF_PLANE
	layer = ABOVE_TURF_LAYER
	mouse_opacity = 0 //Don't block underlying tile interactions

/obj/effect/overlay/snow/floor/edges
	icon_state = "snow_edges"

/obj/effect/overlay/snow/floor/surround
	icon_state = "snow_surround"

/obj/effect/overlay/snow/airlock
	icon_state = "snowairlock"
	layer = DOOR_CLOSED_LAYER+0.01

/obj/effect/overlay/snow/floor/pointy
	icon_state = "snowfloorpointy"

/obj/effect/overlay/snow/wall
	icon_state = "snowwall"
	plane = MOB_PLANE
	layer = ABOVE_MOB_LAYER

/obj/effect/overlay/holographic
	mouse_opacity = FALSE
	anchored = TRUE
	plane = ABOVE_PLANE

// Similar to the tesla ball but doesn't actually do anything and is purely visual.
/obj/effect/overlay/energy_ball
	name = "energy ball"
	desc = "An energy ball."
	icon = 'icons/obj/tesla_engine/energy_ball.dmi'
	icon_state = "energy_ball"
	plane = PLANE_LIGHTING_ABOVE
	pixel_x = -32
	pixel_y = -32

/obj/effect/overlay/vis
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	anchored = TRUE
	vis_flags = VIS_INHERIT_DIR
	///When detected to be unused it gets set to world.time, after a while it gets removed
	EXPIRY_DECLARE(unused)
	///overlays which go unused for this amount of time get cleaned up
	var/cache_expiration = 2 MINUTES

/obj/effect/overlay/light_visible
	name = ""
	icon = 'icons/effects/light_overlays/light_32.dmi'
	icon_state = "light"
	plane = PLANE_O_LIGHTING_VISUAL
	appearance_flags = RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	alpha = 0
	vis_flags = NONE
	blocks_emissive = EMISSIVE_BLOCK_NONE

// Only its light component may delete it (a forced qdel()).
/obj/effect/overlay/light_visible/lifecycle_keep(force)
	if(force)
		return FALSE
	stack_trace("Movable light visible mask deleted, but not by our component")
	return TRUE

/obj/effect/overlay/light_cone
	name = ""
	icon = 'icons/effects/light_overlays/light_cone.dmi'
	icon_state = "light"
	plane = PLANE_O_LIGHTING_VISUAL
	appearance_flags = RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	vis_flags = NONE
	alpha = 110
	blocks_emissive = EMISSIVE_BLOCK_NONE

	var/static/matrix/normal_transform

/obj/effect/overlay/light_cone/Initialize(mapload)
	. = ..()
	apply_standard_transform()

/obj/effect/overlay/light_cone/proc/reset_transform(apply_standard)
	transform = initial(transform)
	if(apply_standard)
		apply_standard_transform()

/obj/effect/overlay/light_cone/proc/apply_standard_transform()
	transform = transform.Translate(-32, -32)

// Only its light component may delete it (a forced qdel()).
/obj/effect/overlay/light_cone/lifecycle_keep(force)
	if(force)
		return FALSE
	stack_trace("Directional light cone deleted, but not by our component")
	return TRUE

/obj/effect/overlay/closet_door
	anchored = TRUE
	plane = FLOAT_PLANE
	layer = FLOAT_LAYER
	vis_flags = VIS_INHERIT_ID
	appearance_flags = KEEP_TOGETHER | LONG_GLIDE | PIXEL_SCALE

/// Relation view: BeamSource (reads null once it is gone).
/obj/effect/overlay/beam/proc/BeamSource() as /atom
	return BeamSource
