// Datum signals. Format:
// When the signal is called: (signal arguments)
// All signals send the source datum of the signal as the first argument

// /datum signals

/// just before a datum's Destroy() is called: (force), at this point none of the other components chose to interrupt qdel and Destroy will be called
#define COMSIG_QDELETING "parent_qdeleting"
/// from datum ui_act (usr, action)
#define COMSIG_UI_ACT "COMSIG_UI_ACT"


// Merger datum signals

// Gas mixture signals


