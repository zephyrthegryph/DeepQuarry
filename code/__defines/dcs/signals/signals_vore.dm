///from /obj/belly/HandleBellyReagents() and /obj/belly/update_internal_overlay()
#define COMSIG_BELLY_UPDATE_VORE_FX "update_vore_fx"

// Spontaneous vore stuff.
		///Something has special handling. Don't continue.
	#define CANCEL_STUMBLED_INTO	(1<<0)
		//Special handling. Cancel the fall chain.
	#define COMSIG_CANCEL_FALL	(1<<0)
		//Special handling. Cancel the hitby proc.
	#define COMSIG_CANCEL_HITBY	(1<<0)
