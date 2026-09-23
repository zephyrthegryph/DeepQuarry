// Atom movement signals. Format:
// When the signal is called: (signal arguments)
// All signals send the source datum of the signal as the first argument

	// Docking turf movement return values - return a combination of these to override the move_mode for the turf containing the atom
	#define COMPONENT_MOVE_TURF MOVE_TURF
	#define COMPONENT_MOVE_AREA MOVE_AREA
	#define COMPONENT_MOVE_CONTENTS MOVE_CONTENTS

///from base of atom/setDir(): (old_dir, new_dir). Called before the direction changes.
#define COMSIG_ATOM_DIR_CHANGE "atom_dir_change"

