// Main atom signals. Format:
// When the signal is called: (signal arguments)
// All signals send the source datum of the signal as the first argument

// /atom signals
//from SSatoms InitAtom - Only if the  atom was not deleted or failed initialization
#define COMSIG_ATOM_AFTER_SUCCESSFUL_INITIALIZE "atom_init_success"
//from SSatoms InitAtom - Only if the  atom was not deleted or failed initialization and has a loc
#define COMSIG_ATOM_AFTER_SUCCESSFUL_INITIALIZED_ON "atom_init_success_on"
///from base of atom/examine(): (/mob, list/examine_text)
#define COMSIG_ATOM_EXAMINE "atom_examine"
	//Positions for overrides list
	#define EXAMINE_POSITION_ARTICLE 1
	#define EXAMINE_POSITION_BEFORE 2
	#define EXAMINE_POSITION_NAME 3
///from base of atom/Entered(): (atom/movable/arrived, atom/old_loc, list/atom/old_locs)
#define COMSIG_ATOM_ENTERED "atom_entered"
/// Sent from the atom that just Entered src. From base of atom/Entered(): (/atom/destination, atom/old_loc, list/atom/old_locs)
#define COMSIG_ATOM_ENTERING "atom_entering"
///from base of atom/Exit(): (/atom/movable/leaving, direction)
#define COMSIG_ATOM_EXIT "atom_exit"
	#define COMPONENT_ATOM_BLOCK_EXIT (1<<0)
///from base of atom/Exited(): (atom/movable/gone, direction)
#define COMSIG_ATOM_EXITED "atom_exited"
///from base of atom/Bumped(): (/atom/movable) (the one that gets bumped)
#define COMSIG_ATOM_BUMPED "atom_bumped"
///called when an atom starts orbiting another atom: (atom)
#define COMSIG_ATOM_ORBIT_BEGIN "atom_orbit_begin"
///called when an atom stops orbiting another atom: (atom)
#define COMSIG_ATOM_ORBIT_STOP "atom_orbit_stop"
///from base of atom/set_opacity(): (new_opacity)
#define COMSIG_ATOM_SET_OPACITY "atom_set_opacity"
///from base of atom/hitby(atom/movable/AM, skipcatch, hitpush, blocked, datum/thrownthing/throwingdatum)
#define COMSIG_ATOM_HITBY "atom_hitby"
///when an atom starts playing a song datum (datum/song)
#define COMSIG_ATOM_STARTING_INSTRUMENT "atom_starting_instrument"

///When the transform or an atom is varedited through vv topic.
#define COMSIG_ATOM_VV_MODIFY_TRANSFORM "atom_vv_modify_transform"


/// from internal loop in /atom/proc/propagate_radiation_pulse: (atom/pulse_source)
#define COMSIG_ATOM_PROPAGATE_RAD_PULSE "atom_propagate_radiation_pulse"


/// when atom falls onto the floor and become exposed to germs: (datum/component/germ_exposure)
#define COMSIG_ATOM_GERM_EXPOSED "atom_germ_exposed"
/// when atom is picked up from the floor or moved to an elevated structure: (datum/component/germ_exposure)
#define COMSIG_ATOM_GERM_UNEXPOSED "atom_germ_unexposed"


//Non /TG/ signals:

///from base of atom/CheckParts(): (list/parts_list, datum/crafting_recipe/R)
#define COMSIG_ATOM_CHECKPARTS "atom_checkparts"

///from base atom/Exited(): (mob/user, obj/item/extrapolator/extrapolator, dry_run, list/result)
#define COMSIG_ATOM_EXTRAPOLATOR_ACT "atom_extrapolator_act"

///from base of /obj/item/dice/proc/rollDice(mob/user as mob, var/silent = 0). Has the arguments of 'src, silent, result'
#define COMSIG_MOB_ROLLED_DICE "mob_rolled_dice" //can give a return value if we want it to make the dice roll a specific number!

///from base of /datum/destroy
#define COMSIG_OBSERVER_DESTROYED "observer_destroyed"

#define COMSIG_OBSERVER_APC "observer_apc"

#define COMSIG_OBSERVER_SHUTTLE_ADDED "observer_shuttle_added"

#define COMSIG_OBSERVER_SHUTTLE_PRE_MOVE "observer_shuttle_premove"
#define COMSIG_OBSERVER_SHUTTLE_MOVED "observer_shuttle_moved"
#define COMSIG_OBSERVER_TURF_ENTERED "observer_turf_entered"
#define COMSIG_OBSERVER_TURF_EXITED "observer_turf_exited"
#define COMSIG_OBSERVER_Z_MOVED "observer_z_moved"
#define COMSIG_OBSERVER_GLOBALMOVED "observer_global_move"

///called when teleporting into a protected turf: (channel, turf/origin)
#define COMSIG_ATOM_INTERCEPT_TELEPORT "intercept_teleport"
	#define COMPONENT_BLOCK_TELEPORT (1<<0)
