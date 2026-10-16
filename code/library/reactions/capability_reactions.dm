// A capability never declares reactions(): its every(), on_change() and on_notice() are entries of its own entries() list, applied by its
// activation (code/engine/declare/activation.dm). Only a /datum/system declares a reactions() table (the table-proc lint bans it elsewhere).

/atom/reaction_holder_initialized()
	return !!(flags & ATOM_INITIALIZED)
