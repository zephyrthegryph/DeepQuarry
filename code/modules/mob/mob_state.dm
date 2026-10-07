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

/// Sets MOB_STATE_PLAYED (nothing is made for a mob that never had a player and still has none).
/mob/proc/mob_state_set_played(played)
	if(mob_state_played(src) != !!played)
		key_set(src, MOB_STATE_PLAYED, !!played)
