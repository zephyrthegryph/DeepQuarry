
/// The persistent client of `ckey`, or null. REGISTRY_PERSISTENT_CLIENTS is keyed by ckey.
/proc/persistent_client_for(ckey)
	var/list/filed = REGISTRY_KEYED(REGISTRY_PERSISTENT_CLIENTS, ckey)
	return length(filed) ? filed[1] : null

/// Every persistent client as ckey -> datum (a new list, for pickers and UIs).
/proc/persistent_clients_by_ckey()
	. = list()
	for(var/datum/persistent_client/P as anything in REGISTRY_MEMBERS(REGISTRY_PERSISTENT_CLIENTS))
		.[P.ckey] = P

/// Tracks information about a client between log in and log outs
/datum/persistent_client
	/// The ckey this record is filed under (the registry key).
	var/ckey
	/// The true client (not a datum: a plain var; BYOND nulls it when the client is deleted)
	var/tmp/client/client
	/// The mob this persistent client is currently bound to (paired with mob.persistent_client).
	var/tmp/mob/mob

	/// Major version of BYOND this client was last using.
	var/byond_version
	/// Build number of BYOND this client was last using.
	var/byond_build

	/// Action datums assigned to this player
	/// Tracks client action logging
	var/list/logging = list() // ALLOW(instance_list): d: one per connected client; logs fill on login

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

	/// World.time this player last died
	var/time_of_death = 0

REGISTRY_MEMBERSHIP(/datum/persistent_client, REGISTRY_PERSISTENT_CLIENTS)

/datum/persistent_client/New(ckey)
	src.ckey = ckey
	join_registries()

/datum/persistent_client/registry_key(registry_id)
	return registry_id == REGISTRY_PERSISTENT_CLIENTS ? ckey : null

// Persistent clients refuse deletion.
/datum/persistent_client/lifecycle_keep(force)
	stack_trace("Something tried to delete a persistent client; refused.")
	return TRUE

/// Setter for the client var, updates any vars we have that might be dependent on client state
/datum/persistent_client/proc/set_client(client/new_client)
	if(client() == new_client)
		return

	if(client())
		client().persistent_client = null
	client = new_client
	if(client())
		client().persistent_client = src
		byond_build = client().byond_build
		byond_version = client().byond_version

/// Setter for the mob var, handles both references.
/datum/persistent_client/proc/set_mob(mob/new_mob)
	if(mob() == new_mob)
		return

	// A pair: setting our side sets new_mob.persistent_client, and unlinks our old mob and
	// new_mob's old persistent client.
	rel_set(src, nameof(mob), new_mob)

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

	var/datum/persistent_client/writable = persistent_client_for(ckey)
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

/// The mob this persistent client is bound to (a relation view).
/datum/persistent_client/proc/mob() as /mob
	return mob

/// The connected client, or null.
/datum/persistent_client/proc/client() as /client
	return client

/// LC-refs: the actions granted to this player on each login are theirs.

/datum/persistent_client/relations()
	. = ..()
	. += rel_one(nameof(mob), back = nameof(/mob::persistent_client))
/mob/relations()
	. = ..()
	. += rel_one(nameof(persistent_client), back = nameof(/datum/persistent_client::mob))
