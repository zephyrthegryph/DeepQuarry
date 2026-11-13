// Kernel measurement: movement in the tick ledger (ledger.dm).
//
// A step is the work an AI loop, a thrown item or a pushed mob spends most of its callback on: Exit/Enter, Entered, Moved(), the moved notice,
// light and interest updates. Bracketing Move() charges that time to KM_CAT_MOVEMENT (named by the mover's type) and takes it out of the
// callback or system item that made the step, so "the mouse's AI loop is 5 ms" splits into the loop's own decisions and the steps it took.
// This file compiles after the definition it wraps (atoms_movable.dm): the later definition of a type's proc runs, and its ..() calls the earlier.

/atom/movable/Move(atom/newloc, direct = 0, movetime)
	var/move_ledger = km_ledger_enter(KM_CAT_MOVEMENT, type, "Move")
	. = ..()
	km_ledger_leave(move_ledger)
