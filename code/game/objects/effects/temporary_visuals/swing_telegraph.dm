// Swing telegraph — the per-tile highlight shown during a melee windup so a target
// can see which tiles the incoming swing will strike (and read what to do about it).
// Spawned by /mob/living/begin_melee_swing on each swing tile and by AI attack behaviors;
// auto-cleans itself when the windup elapses (duration == the weapon's windup time).
//
// Colour + shape encode HOW to answer the attack, so a player learns the language fast:
//   yellow ring  (PARRY) — a normal/heavy swing: parry or block it.
//   red ring     (DODGE) — unblockable: a guard won't save you, step out of the tiles.
//   blue ring    (GRAB)  — a grab/tackle: can't be parried, dodge or get grappled.
/obj/effect/temp_visual/swing_telegraph
	name = "swing telegraph"
	icon = 'icons/effects/Targeted.dmi'
	icon_state = "locking"
	layer = ABOVE_MOB_LAYER
	randomdir = FALSE
	duration = 4	// Overwritten per-spawn to match the weapon windup.
	alpha = 160
	color = "#ff5555"

/obj/effect/temp_visual/swing_telegraph/Initialize(mapload, set_duration, set_color, set_state)
	if(set_duration)
		duration = set_duration	// set before ..() so the auto-qdel timer uses it
	if(set_color)
		color = set_color
	if(set_state)
		icon_state = set_state
	. = ..()

// ---------------------------------------------------------------------------
// Telegraph kinds — the colour/shape vocabulary. Spawn via dq_telegraph().
// ---------------------------------------------------------------------------
#define DQ_TELEGRAPH_PARRY 1 // parryable/blockable swing — yellow
#define DQ_TELEGRAPH_DODGE 2 // unblockable — red, must leave the tiles
#define DQ_TELEGRAPH_GRAB  3 // grab/tackle — blue, dodge or be grappled

/// Spawn a telegraph of the given kind on `T` for `duration` deciseconds. Centralises the
/// colour/state vocabulary so every attack telegraphs consistently.
/proc/dq_telegraph(turf/T, duration, kind = DQ_TELEGRAPH_PARRY)
	if(!T)
		return
	switch(kind)
		if(DQ_TELEGRAPH_DODGE)
			new /obj/effect/temp_visual/swing_telegraph(T, duration, "#ff3030", "locked")
		if(DQ_TELEGRAPH_GRAB)
			new /obj/effect/temp_visual/swing_telegraph(T, duration, "#33aaff", "locking")
		else
			new /obj/effect/temp_visual/swing_telegraph(T, duration, "#ffcc33", "locking")
