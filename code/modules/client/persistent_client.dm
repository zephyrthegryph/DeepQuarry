
///assoc list of ckey -> /datum/persistent_client
GLOBAL_LIST_EMPTY_TYPED(persistent_clients_by_ckey, /datum/persistent_client)
/// A flat list of all persistent clients, for her looping pleasure.

/// Tracks information about a client between log in and log outs
/datum/persistent_client
	/// The true client
	var/tmp/client_handle
	/// The mob this persistent client is currently bound to.
	var/tmp/mob_handle

	/// Major version of BYOND this client was last using.
	var/byond_version
	/// Build number of BYOND this client was last using.
	var/byond_build

	/// Action datums assigned to this player
	/// Tracks client action logging
	var/list/logging = list()

	/// Callbacks invoked when this client logs in again
	var/list/datum/action/player_actions
	var/list/post_login_callbacks
	/// Callbacks invoked when this client logs out
	var/list/post_logout_callbacks

	/// List of names this key played under this round
	/// assoc list of name -> mob tag
	var/list/played_names
	/// Lazylist of preference slots this client has joined the round under
	/// Numbers are stored as strings
	var/list/joined_as_slots

	/// Tracks achievements they have earned
	//var/datum/achievement_data/achievements

	/// World.time this player last died
	var/time_of_death = 0

REGISTRY_MEMBERSHIP(/datum/persistent_client, REGISTRY_PERSISTENT_CLIENTS)

/datum/persistent_client/New(ckey)
	//achievements = new(ckey)
	GLOB.persistent_clients_by_ckey[ckey] = src
	join_registries()

// LIFECYCLE: persistent clients refuse deletion.
/datum/persistent_client/Destroy(force)
	SHOULD_CALL_PARENT(FALSE)
	. = QDEL_HINT_LETMELIVE
	CRASH("Who the FUCK tried to delete a persistent client? Get your head checked you leadskull.")

/// Setter for the client var, updates any vars we have that might be dependent on client state
/datum/persistent_client/proc/set_client(client/new_client)
	if(client() == new_client)
		return

	if(client())
		client().persistent_client = null
	client_handle = om_handle(new_client)
	if(client())
		client().persistent_client = src
		byond_build = client().byond_build
		byond_version = client().byond_version

/// Setter for the mob var, handles both references.
/datum/persistent_client/proc/set_mob(mob/new_mob)
	if(mob() == new_mob)
		return

	mob()?.persistent_client = null
	new_mob?.persistent_client?.set_mob(null)

	mob_handle = om_handle(new_mob)
	new_mob?.persistent_client = src

/// Writes all of the `played_names` into an HTML-escaped string.
/datum/persistent_client/proc/get_played_names()
	var/list/previous_names = list()
	for(var/previous_name in played_names)
		previous_names += html_encode("[previous_name] ([LAZYACCESS(played_names, previous_name)])")
	return previous_names.Join("; ")

/// Returns the full version string (i.e 515.1642) of the BYOND version and build.
/datum/persistent_client/proc/full_byond_version()
	if(!byond_version)
		return "Unknown"
	return "[byond_version].[byond_build || "xxx"]"

/// Adds the new names to the player's played_names list on their /datum/persistent_client for use of admins.
/// `ckey` should be their ckey, and `data` should be an associative list with the keys being the names they played under and the values being the unique mob ID tied to that name.
/proc/log_played_names(ckey, data)
	if(!ckey)
		return

	var/datum/persistent_client/writable = GLOB.persistent_clients_by_ckey[ckey]
	if(isnull(writable))
		return

	for(var/name in data)
		if(!name)
			continue
		var/mob_tag = data[name]
		var/encoded_name = html_encode(name)
		if(LAZYFIND(writable.played_names, "[encoded_name]"))
			continue

		LAZYADD(writable.played_names, list("[encoded_name]" = mob_tag))

/// LC-refs: the mob this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/persistent_client/proc/mob() as /mob
	return om_resolve(mob_handle)

/// LC-refs: the client this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/persistent_client/proc/client() as /client
	return om_resolve(client_handle)

/// LC-refs: the actions granted to this player on each login are theirs.
REF_OWNED_LIST(/datum/persistent_client, "player_actions")
