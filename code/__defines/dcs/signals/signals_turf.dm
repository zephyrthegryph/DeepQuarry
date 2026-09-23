// Turf signals. Format:
// When the signal is called: (signal arguments)
// All signals send the source datum of the signal as the first argument

/// from base of turf/ChangeTurf(): (path, list/new_baseturfs, flags, list/post_change_callbacks).
/// `post_change_callbacks` is a list that signal handlers can mutate to append `/datum/callback` objects.
/// They will be called with the new turf after the turf has changed.
#define COMSIG_TURF_CHANGE "turf_change"
///from base of turf/multiz_turf_del(): (turf/source, direction)
#define COMSIG_TURF_MULTIZ_DEL "turf_multiz_del"
///from base of turf/multiz_turf_new: (turf/source, direction)
#define COMSIG_TURF_MULTIZ_NEW "turf_multiz_new"


///from /datum/element/footstep/prepare_step(): (list/steps)
#define COMSIG_TURF_PREPARE_STEP_SOUND "turf_prepare_step_sound"
	//stops element/footstep/proc/prepare_step() from returning null if the turf itself has no sound
	#define FOOTSTEP_OVERRIDEN (1<<0)


