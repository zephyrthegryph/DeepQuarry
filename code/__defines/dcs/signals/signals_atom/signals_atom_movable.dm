// Atom movable signals. Format:
// When the signal is called: (signal arguments)
// All signals send the source datum of the signal as the first argument

///from base of atom/movable/Moved(): (/atom, newloc, direction)
#define COMSIG_MOVABLE_ATTEMPTED_MOVE "movable_attempted_move"
///from base of atom/movable/Moved(): (/atom)
#define COMSIG_MOVABLE_PRE_MOVE "movable_pre_move"
	#define COMPONENT_MOVABLE_BLOCK_PRE_MOVE (1<<0)
///from base of atom/movable/Moved(): (atom/old_loc, dir, forced, list/old_locs)
#define COMSIG_MOVABLE_MOVED "movable_moved"
///from base of atom/movable/Cross(): (/atom/movable)
#define COMSIG_MOVABLE_CROSS "movable_cross"
	#define COMPONENT_BLOCK_CROSS (1<<0)
///from base of atom/movable/Move(): (/atom/movable)
#define COMSIG_MOVABLE_CROSS_OVER "movable_cross_am"
///from base of atom/movable/Bump(): (/atom)
#define COMSIG_MOVABLE_BUMP "movable_bump"
	#define COMPONENT_INTERCEPT_BUMPED (1<<0)
///from base of atom/movable/throw_impact() after confirming a hit: (/atom/hit_atom, /datum/thrownthing/throwingdatum)
#define COMSIG_MOVABLE_IMPACT "movable_impact"
///from base of atom/movable/buckle_mob(): (mob, force)
#define COMSIG_MOVABLE_BUCKLE "buckle"
///from base of atom/movable/on_changed_z_level(): (turf/old_turf, turf/new_turf, same_z_layer)
#define COMSIG_MOVABLE_Z_CHANGED "movable_ztransit"

///called when space wind can't move a movable. (pressure_difference, pressure_direction)
#define COMSIG_MOVABLE_RESISTED_SPACEWIND "movable_resisted_wind"

// called when movable is expelled from a disposal pipe, bin or outlet on obj/pipe_eject: (direction)
///Called before a movable is being teleported from `check_teleport_valid()`: (destination, channel)
#define COMSIG_MOVABLE_TELEPORTING "movable_teleporting"
///Called after a movable is teleported from `do_teleport()`: ()
#define COMSIG_MOVABLE_POST_TELEPORT "movable_post_teleport"


	// Used to access COMSIG_MOVABLE_SAY_QUOTE argslist
	/// The index of args that corresponds to the actual message
	#define MOVABLE_SAY_QUOTE_MESSAGE 1
	#define MOVABLE_SAY_QUOTE_MESSAGE_SPANS 2
	#define MOVABLE_SAY_QUOTE_MESSAGE_MODS 3

/// From base of area/Exited(): (area/left, direction)
#define COMSIG_MOVABLE_EXITED_AREA "movable_exited_area"


///from base of /atom/movable/point_at: (atom/A, obj/effect/temp_visual/point/point)
#define COMSIG_MOVABLE_POINTED "movable_pointed"


