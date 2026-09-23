// Datum signals. Format:
// When the signal is called: (signal arguments)
// All signals send the source datum of the signal as the first argument

// /datum signals

/// just before a datum's Destroy() is called: (force), at this point none of the other components chose to interrupt qdel and Destroy will be called
#define COMSIG_QDELETING "parent_qdeleting"
/// J1 (doc/rewrite/containment.md §2.4): just before qdel() calls pre_destroy()
/// on a datum whose type needs the pre-destroy phase: (force). The datum is
/// still fully valid -- gc_destroyed isn't set yet. Only sent for types that
/// need the phase at all (dq_qdel_needs_pre_destroy()); see DF_PRE_DESTROYING.
#define COMSIG_PRE_QDELETING "parent_pre_qdeleting"
/// from datum ui_act (usr, action)
#define COMSIG_UI_ACT "COMSIG_UI_ACT"


// Merger datum signals

// Gas mixture signals


