// Concealment holds on the invisibility stat. `invisibility` is an engine-owned stat (STAT(/atom, invisibility, MAX)): a thing kept out of sight is a
// hold on it, never a write of the var, so the served value stays the composed one and releasing the hold restores the type's own invisibility.

/// A thing under an intact floor (a pipe, a cable, a terminal, a beacon) is out of sight: hold INVISIBILITY_ABSTRACT sourced SRC_UNDER_FLOOR while
/// `hidden`, release it otherwise.
/proc/hide_under_floor(atom/A, hidden)
	if(hidden)
		hold(A, STAT_INVISIBILITY, INVISIBILITY_ABSTRACT, SRC_UNDER_FLOOR)
	else
		release(A, STAT_INVISIBILITY, SRC_UNDER_FLOOR)

/// A thing its owner keeps out of sight at `level` (a component hidden inside its machine, a pipe stub awaiting removal): a hold sourced SRC_CONCEALED.
/proc/conceal(atom/A, level = INVISIBILITY_MAXIMUM)
	hold(A, STAT_INVISIBILITY, level, SRC_CONCEALED)

/// Ends conceal().
/proc/unconceal(atom/A)
	release(A, STAT_INVISIBILITY, SRC_CONCEALED)
