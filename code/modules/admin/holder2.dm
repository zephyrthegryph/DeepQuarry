GLOBAL_LIST_EMPTY(admin_datums)
GLOBAL_PROTECT(admin_datums)
GLOBAL_LIST_EMPTY(protected_admins)
GLOBAL_PROTECT(protected_admins)

GLOBAL_VAR_INIT(href_token, GenerateToken())
GLOBAL_PROTECT(href_token)

/datum/admins
	/// Our ranks (a relation list: ranks live in GLOB.admin_ranks, or in custom_rank). Set with set_ranks().
	var/list/datum/admin_rank/ranks
	/// The client-level click intercept (a relation view); needs to implement InterceptClickOn(user,params,atom).
	var/tmp/datum/click_intercept
	/// A per-admin rank duplicated for this holder (change_admin_flags), owned.
	var/datum/admin_rank/custom_rank

	var/target
	var/name = "nobody's admin datum (no rank)" //Makes for better runtimes
	var/tmp/client/owner
	var/fakekey = null

	var/tmp/datum/marked_datum

	var/admincaster_screen = 0	//See newscaster.dm under machinery for a full description
	var/datum/feed_message/admincaster_feed_message = new /datum/feed_message   //These two will act as holders.
	/// The admin newscaster's working channel: a network channel picked into admincaster_feed_channel_handle,
	/// or while none is picked its own scratch channel (admincaster_feed_channel() reads either).
	var/tmp/datum/admincaster_feed_channel
	var/datum/feed_channel/admincaster_scratch_channel = new /datum/feed_channel
	var/admincaster_signature	//What you'll sign the newsfeeds as

	/// Code security critcal token used for authorizing href topic calls
	var/href_token

	/// Link from the database pointing to the admin's feedback forum
	var/cached_feedback_link
	/// The om_io job fetching cached_feedback_link, while one is in flight.
	var/feedback_link_pending = 0

	var/deadmined

	var/datum/filter_editor/filteriffic
	var/datum/particle_editor/particle_test
	var/datum/whitelist_editor/whitelist_editor
	var/datum/spawn_menu/spawn_menu
	var/datum/spawnpanel/spawn_panel

	var/datum/access_viewer/access_view_menu

	/// A lazylist of tagged datums, for quick reference with the View Tags verb
	var/list/tagged_datums

	var/given_profiling = FALSE

/datum/admins/New(list/datum/admin_rank/ranks, ckey, force_active = FALSE, protected)
	if(IsAdminAdvancedProcCall())
		alert_to_permissions_elevation_attempt(usr)
		if (!target) //only del if this is a true creation (and not just a New() proc call), other wise trialmins/coders could abuse this to deadmin other admins
			om_qdel_after(src, 0)
			CRASH("Admin proc call creation of admin datum")
		return
	if(!ckey)
		om_qdel_after(src, 0)
		CRASH("Admin datum created without a ckey")
	if(!istype(ranks))
		om_qdel_after(src, 0)
		CRASH("Admin datum created with invalid ranks: [ranks] ([json_encode(ranks)])")
	target = ckey
	name = "[ckey]'s admin datum ([join_admin_ranks(ranks)])"
	set_ranks(ranks)
	admincaster_signature = "[using_map.company_name] Officer #[rand(0,9)][rand(0,9)][rand(0,9)]"
	href_token = GenerateToken()
	if(protected)
		GLOB.protected_admins[target] = src
	activate()

// Refuses deletion from advanced proc calls (permission elevation).
/datum/admins/lifecycle_keep(force)
	if(!IsAdminAdvancedProcCall())
		return FALSE
	alert_to_permissions_elevation_attempt(usr)
	return TRUE

/datum/admins/proc/activate()
	if(IsAdminAdvancedProcCall())
		alert_to_permissions_elevation_attempt(usr)
		return
	GLOB.deadmins -= target
	GLOB.admin_datums[target] = src
	deadmined = FALSE
	if (GLOB.directory[target])
		associate(GLOB.directory[target]) //find the client for a ckey if they are connected and associate them with us

/datum/admins/proc/deactivate()
	if(IsAdminAdvancedProcCall())
		alert_to_permissions_elevation_attempt(usr)
		return
	GLOB.deadmins[target] = src
	GLOB.admin_datums -= target
	deadmined = TRUE

	var/client/client = owner() || GLOB.directory[target]

	if (!isnull(client))
		disassociate()
		add_verb(client, /client/proc/readmin)

/datum/admins/proc/associate(client/client)
	if(IsAdminAdvancedProcCall())
		alert_to_permissions_elevation_attempt(usr)
		return

	if(!istype(client))
		return

	if(client?.ckey != target)
		var/msg = " has attempted to associate with [target]'s admin datum"
		message_admins("[key_name_admin(client)][msg]")
		log_admin("[key_name(client)][msg]")
		return

	if (deadmined)
		activate()

	rel_set(src, "owner", client)
	owner().holder = src
	owner().add_admin_verbs()
	remove_verb(owner(), /client/proc/readmin)
	owner().init_verbs() //re-initialize the verb list
	GLOB.admins |= client

	try_give_profiling()

/datum/admins/proc/disassociate()
	if(IsAdminAdvancedProcCall())
		alert_to_permissions_elevation_attempt(usr)
		return
	if(owner())
		GLOB.admins -= owner()
		owner().remove_admin_verbs()
		// owner.init_verbs() //re-initialize the verb list
		owner().holder = null
		rel_clear(src, "owner")

/// Returns the feedback forum thread for the admin holder's owner, as according to DB.
/datum/admins/proc/feedback_link()
	// This intentionally does not follow the 10-second maximum TTL rule,
	// as this can be reloaded through the Reload-Admins verb.
	if (cached_feedback_link == NO_FEEDBACK_LINK)
		return null

	if (!isnull(cached_feedback_link))
		return cached_feedback_link

	if (!SSdbcore.IsConnected())
		return FALSE

	// Not known yet: ask (om_io, nothing waits). The answer fills the cache for the next call.
	if(!feedback_link_pending)
		feedback_link_pending = om_io(src, /datum/om/io/sql, "SELECT feedback FROM [format_table_name("admin")] WHERE ckey = :ckey", list("ckey" = owner()?.ckey), PROC_REF(feedback_link_arrived))
	return null

/// om_io() callback: caches the admin's feedback link (or that there is none).
/datum/admins/proc/feedback_link_arrived(list/result, error)
	feedback_link_pending = 0
	if(error)
		log_sql("Error retrieving feedback link for [src]: [error]")
		return
	var/list/rows = result["rows"]
	if(!length(rows))
		cached_feedback_link = NO_FEEDBACK_LINK
		return
	var/list/row = rows[1]
	cached_feedback_link = row[1] || NO_FEEDBACK_LINK

/datum/admins/proc/check_for_rights(rights_required)
	if(rights_required && !(rights_required & rank_flags()))
		return FALSE
	return TRUE

/datum/admins/proc/check_if_greater_rights_than_holder(datum/admins/other)
	if(!other)
		return TRUE //they have no rights
	if(rank_flags() == R_EVERYTHING)
		return TRUE //we have all the rights
	if(src == other)
		return TRUE //you always have more rights than yourself
	if(rank_flags() != other.rank_flags())
		if( (rank_flags() & other.rank_flags()) == other.rank_flags() )
			return TRUE //we have all the rights they have and more
	return FALSE

/// Get the rank name of the admin
/datum/admins/proc/rank_names()
	return join_admin_ranks(ranks)

/// Get the rank flags of the admin
/datum/admins/proc/rank_flags()
	var/combined_flags = NONE

	for (var/datum/admin_rank/rank as anything in ranks)
		combined_flags |= rank.rights

	return combined_flags

/// Get the permissions this admin is allowed to edit on other ranks
/datum/admins/proc/can_edit_rights_flags()
	var/combined_flags = NONE

	for (var/datum/admin_rank/rank as anything in ranks)
		combined_flags |= rank.can_edit_rights

	return combined_flags

/datum/admins/proc/try_give_profiling()
	if (CONFIG_GET(flag/forbid_admin_profiling))
		return

	if (given_profiling)
		return

	if (!(rank_flags() & R_DEBUG))
		return

	given_profiling = TRUE
	world.SetConfig("APP/admin", owner().ckey, "role=admin")

/datum/admins/vv_edit_var(var_name, var_value)
	return FALSE //nice try trialmin

/*
checks if usr is an admin with at least ONE of the flags in rights_required. (Note, they don't need all the flags)
if rights_required == 0, then it simply checks if they are an admin.
if it doesn't return 1 and show_msg=1 it will prints a message explaining why the check has failed
generally it would be used like so:

/proc/admin_proc()
	if(!check_rights(R_ADMIN))
		return
	to_chat(world, "you have enough rights!", confidential = TRUE)

NOTE: it checks usr! not src! So if you're checking somebody's rank in a proc which they did not call
you will have to do something like if(client.rights & R_ADMIN) yourself.
*/
/proc/check_rights(rights_required, show_msg=1)
	if(usr?.client)
		if (check_rights_for(usr.client, rights_required))
			return TRUE
		else
			if(show_msg)
				to_chat(usr, span_red("Error: You do not have sufficient rights to do that. You require one of the following flags:[rights2text(rights_required," ")]."), confidential = TRUE)
	return FALSE

//probably a bit iffy - will hopefully figure out a better solution
/proc/check_if_greater_rights_than(client/other)
	if(usr?.client)
		if(check_rights_for(usr.client, R_HOLDER))
			if(!other || !other.holder)
				return TRUE
			return usr.client.holder.check_if_greater_rights_than_holder(other.holder)
	return FALSE

//This proc checks whether subject has at least ONE of the rights specified in rights_required.
/proc/check_rights_for(client/subject, rights_required)
	if(subject?.holder)
		return subject.holder.check_for_rights(rights_required)
	return FALSE

/proc/GenerateToken()
	. = ""
	for(var/I in 1 to 32)
		. += "[rand(10)]"

/proc/RawHrefToken(forceGlobal = FALSE)
	var/tok = GLOB.href_token
	if(!forceGlobal && usr)
		var/client/C = usr.client
		if(!C)
			log_runtime("Attempted to retrieve a HrefToken of an entity with no client.")
			return 0
		var/datum/admins/holder = C.holder
		if(holder)
			tok = holder.href_token
	return tok

/proc/HrefToken(forceGlobal = FALSE)
	return "admin_token=[RawHrefToken(forceGlobal)]"

/proc/HrefTokenFormField(forceGlobal = FALSE)
	return "<input type='hidden' name='admin_token' value='[RawHrefToken(forceGlobal)]'>"

// Shared admin_rank registry entries.

/// LC-refs: the marked_datum this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/admins/proc/marked_datum() as /datum
	return marked_datum

/// LC-refs: the owner this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/admins/proc/owner() as /client
	return owner

/// LC-refs: the channel the admin newscaster is working on -- a picked network channel (an OM handle) or the scratch one.
/datum/admins/proc/admincaster_feed_channel() as /datum/feed_channel
	return admincaster_feed_channel || admincaster_scratch_channel

/// Replaces our ranks (a relation list) with `new_ranks`.
/datum/admins/proc/set_ranks(list/datum/admin_rank/new_ranks)
	rel_clear(src, "ranks")
	for(var/datum/admin_rank/rank as anything in new_ranks)
		rel_add(src, "ranks", rank)
