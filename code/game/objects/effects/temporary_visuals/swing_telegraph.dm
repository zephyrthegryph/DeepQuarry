// Swing telegraph — the per-tile highlight shown during a melee windup so a target
// can see which tiles the incoming swing will strike (and step out of them to dodge).
// Spawned by /mob/living/begin_melee_swing on each swing tile; auto-cleans itself when
// the windup elapses (duration == the weapon's windup time).
/obj/effect/temp_visual/swing_telegraph
	name = "swing telegraph"
	icon = 'icons/effects/Targeted.dmi'
	icon_state = "locking"
	layer = ABOVE_MOB_LAYER
	randomdir = FALSE
	duration = 4	// Overwritten per-spawn to match the weapon windup.
	alpha = 160
	color = "#ff5555"

/obj/effect/temp_visual/swing_telegraph/Initialize(mapload, set_duration)
	if(set_duration)
		duration = set_duration	// set before ..() so the auto-qdel timer uses it
	. = ..()
