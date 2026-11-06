// mob_state(): two facts about a mob that requirements read, kept as capability state keys (a requirement cannot read the builtin `client` or a list).
//
//   MOB_STATE_PLAYED          a player's client is attached; set by /mob/Login() and /mob/Logout(), which every key transfer and ghostize() runs.
//   MOB_STATE_KNOWS_LANGUAGE  the mob knows at least one language; set by sync_language_state() after every write to `languages`.
//
// Read them with req_is(MOB_STATE_PLAYED, FALSE, because = ...) or the accessors mob_state_played() / mob_state_knows_language().

MSG_DEF_SELF(mob_state/no_player, "Nobody is playing it.")
MSG_DEF_SELF(mob_state/no_language, "It knows no languages.")

CAPABILITY_TYPE(mob_state, CAP_MOB_STATE, /datum/capability/lib/mob_state, key = NONE)
cap_keys(CAP_MOB_STATE, PLAYED = MSG(mob_state/no_player), KNOWS_LANGUAGE = MSG(mob_state/no_language))

/datum/capability/lib/mob_state

/datum/capability/lib/mob_state/entries()
	return list()

/// The built-in `ckey` is published from the two places a key arrives or leaves a mob (Login() and Logout(), which every key transfer and ghostize()
/// runs), the way `loc` is published from the move choke point: what reads `ckey` (a requirement asking whether a player's key is on the mob, a
/// disconnected player's included) re-evaluates. Nothing runs while nothing reads it. The readers re-read the var when the drain reaches them, after
/// the transfer that called Login/Logout has finished.
/mob/proc/ckey_changed()
	if(GLOB.stat_input_keys?[nameof(ckey)] || GLOB.derived_read_vars?[nameof(ckey)] || (length(GLOB.generated_reads_table) && READERS(src, nameof(ckey))))
		own_field_changed(src, nameof(ckey))
	// `client` and `key` arrive and leave with the key, at the same two places.
	if(GLOB.stat_input_keys?[nameof(client)] || GLOB.derived_read_vars?[nameof(client)] || (length(GLOB.generated_reads_table) && READERS(src, nameof(client))))
		own_field_changed(src, nameof(client))
	if(GLOB.stat_input_keys?[nameof(key)] || GLOB.derived_read_vars?[nameof(key)] || (length(GLOB.generated_reads_table) && READERS(src, nameof(key))))
		own_field_changed(src, nameof(key))

/// Sets MOB_STATE_PLAYED (nothing is made for a mob that never had a player and still has none).
/mob/proc/mob_state_set_played(played)
	if(mob_state_played(src) != !!played)
		key_set(src, MOB_STATE_PLAYED, !!played)
