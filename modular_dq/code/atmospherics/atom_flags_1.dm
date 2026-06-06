// /tg/'s atom-system bitfield. INITIALIZED_1 is set in /atom/Initialize
// (code/game/atom/atoms_initializing_EXPENSIVE.dm) so SSair.add_to_active and
// other LINDA callsites that check `flags_1 & INITIALIZED_1` see a real value
// instead of the all-zeros stub the migration originally left behind.
//
// Additional /tg/ flags_1 bits can be #defined alongside INITIALIZED_1 in
// modular_dq/code/__defines/atmospherics.dm as need arises.

/atom
	var/flags_1 = 0
