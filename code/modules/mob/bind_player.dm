// The one native player link (doc/rewrite/proposals/relations.md D13): moving a player's client into a mob by writing mob.key or mob.ckey happens
// here and nowhere else (the player_link lint). BYOND moves the client and runs Login(), which keeps the persistent client relation in step.
// A mind move (move_player(), transfer_mind(), code/datums/character_identity.dm) ends here too when it carries the key.

/// Puts the player `value` names into `M` (or takes the player out with null). `as_ckey` writes mob.ckey instead of mob.key (a ckey, as the
/// caller had it). Returns M.
/proc/bind_player(mob/M, value, as_ckey = FALSE)
	if(!M)
		return null
	if(as_ckey)
		bind_player(M, value, as_ckey = TRUE)
	else
		bind_player(M, value)
	return M
