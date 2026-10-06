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
	/// The admin newscaster's working channel: a picked network channel (a relation view), or while
	/// none is picked its own scratch channel (admincaster_feed_channel() reads either).
	var/tmp/datum/feed_channel/admincaster_feed_channel
	var/datum/feed_channel/admincaster_scratch_channel = new /datum/feed_channel
	var/admincaster_signature	//What you'll sign the newsfeeds as

	/// Code security critcal token used for authorizing href topic calls
	var/href_token

	/// Link from the database pointing to the admin's feedback forum
	var/fetched_feedback_link
	/// The io_job job fetching fetched_feedback_link, while one is in flight.
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

CAPABILITIES(/datum/admins)
	owns_one(nameof(access_view_menu), /datum/access_viewer)
	owns_one(nameof(admincaster_feed_message), /datum/feed_message)
	owns_one(nameof(admincaster_scratch_channel), /datum/feed_channel)
	owns_one(nameof(custom_rank), /datum/admin_rank)
	owns_one(nameof(dq_newscaster_panel), /datum/newscaster_panel)
	owns_one(nameof(dq_permissions_panel), /datum/permissions_panel)
	owns_one(nameof(faxreply), /obj/item/paper/admin)
	owns_one(nameof(filteriffic), /datum/filter_editor)
	owns_one(nameof(particle_test), /datum/particle_editor)
	owns_one(nameof(round_status_panel), /datum/round_status_panel)
	owns_one(nameof(spawn_menu), /datum/spawn_menu)
	owns_one(nameof(spawn_panel), /datum/spawnpanel)
	owns_one(nameof(tgui_game_panel), /datum/game_panel)
	owns_one(nameof(tgui_player_panel), /datum/player_panel)

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
		GLOB.protected_admins[target] = src // ALLOW(registry): the admin holder tables are keyed by ckey and outlive the client (deadmin, protected admins); clients are not datums, so the ckey is the identity
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
	GLOB.admin_datums[target] = src // ALLOW(registry): the admin holder tables are keyed by ckey and outlive the client (deadmin, protected admins); clients are not datums, so the ckey is the identity
	deadmined = FALSE
	if (GLOB.directory[target])
		associate(GLOB.directory[target]) //find the client for a ckey if they are connected and associate them with us

/datum/admins/proc/deactivate()
	if(IsAdminAdvancedProcCall())
		alert_to_permissions_elevation_attempt(usr)
		return
	GLOB.deadmins[target] = src // ALLOW(registry): the admin holder tables are keyed by ckey and outlive the client (deadmin, protected admins); clients are not datums, so the ckey is the identity
	GLOB.admin_datums -= target
	deadmined = TRUE

	var/client/client = owner() || GLOB.directory[target]

	if (!isnull(client))
		disassociate()
		grant(client, granted_verb(/client/proc/readmin), src)

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

	rel_set(src, nameof(owner), client)
	owner().holder = src
	owner().add_admin_verbs()
	revoke(owner(), granted_verb(/client/proc/readmin), src)
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
		rel_clear(src, nameof(owner))

/// Returns the feedback forum thread for the admin holder's owner, as according to DB.
/datum/admins/proc/feedback_link()
	// This intentionally does not follow the 10-second maximum TTL rule,
	// as this can be reloaded through the Reload-Admins verb.
	if (fetched_feedback_link == NO_FEEDBACK_LINK)
		return null

	if (!isnull(fetched_feedback_link))
		return fetched_feedback_link

	if (!SSdbcore.IsConnected())
		return FALSE

	// Not known yet: ask (io_job, nothing waits). The answer fills the cache for the next call.
	if(!feedback_link_pending)
		feedback_link_pending = io_job(src, /datum/io_backend/sql, "SELECT feedback FROM [format_table_name("admin")] WHERE ckey = :ckey", list("ckey" = owner()?.ckey), PROC_REF(feedback_link_arrived))
	return null

/// io_job() callback: caches the admin's feedback link (or that there is none).
/datum/admins/proc/feedback_link_arrived(list/result, error)
	feedback_link_pending = 0
	if(error)
		log_sql("Error retrieving feedback link for [src]: [error]")
		return
	var/list/rows = result["rows"]
	if(!length(rows))
		fetched_feedback_link = NO_FEEDBACK_LINK
		return
	var/list/row = rows[1]
	fetched_feedback_link = row[1] || NO_FEEDBACK_LINK

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

/**
 * The one admin rights primitive: does `subject` hold at least ONE of `rights`? (rights 0 = "is an admin").
 * It never reads usr and never logs, so it is safe in polling (tgui state), callbacks and prompt flows.
 * Declare rights once at the entry point (ADMIN_VERB, ADMIN_STATE, TOPIC_RIGHTS) instead of re-checking inside.
 */
/proc/admin_can(client/subject, rights)
	READS_FROM()
	if(subject?.holder)
		return subject.holder.check_for_rights(rights)
	return FALSE

/**
 * admin_can() that audits a denial: one log line with the key, the entry point and the rights required.
 * Use it where an entry point cannot declare the rights itself (per-action rights inside one UI).
 * `show_msg` also tells the client why.
 */
/proc/admin_require(client/subject, rights, entry, show_msg = TRUE)
	if(admin_can(subject, rights))
		return TRUE
	admin_log_denial(subject, entry, rights, show_msg)
	return FALSE

/// The single denial audit line: "ADMIN DENIED: key entry=<entry> requires=<flags>".
/proc/admin_log_denial(client/subject, entry, rights, show_msg = FALSE)
	log_admin_private("ADMIN DENIED: [subject ? key_name(subject) : "(no client)"] entry=[entry] requires=[rights2text(rights, " ")]")
	if(show_msg && subject)
		to_chat(subject, span_red("Error: You do not have sufficient rights to do that. You require one of the following flags:[rights2text(rights," ")]."), confidential = TRUE)

/**
 * DEPRECATED: reads usr, so it is wrong in a callback or proc chain. Use admin_can(client, rights), or declare
 * the rights on the entry point. Kept as a thin usr wrapper; a shrink-only lint baseline tracks the remaining calls.
 */
/proc/check_rights(rights_required, show_msg=1)
	if(usr?.client && admin_can(usr.client, rights_required))
		return TRUE
	admin_log_denial(usr?.client, "check_rights in [caller?.proc]", rights_required, show_msg)
	return FALSE

//probably a bit iffy - will hopefully figure out a better solution
/proc/check_if_greater_rights_than(client/other)
	if(usr?.client)
		if(check_rights_for(usr.client, R_HOLDER))
			if(!other || !other.holder)
				return TRUE
			return usr.client.holder.check_if_greater_rights_than_holder(other.holder)
	return FALSE

/// Alias of admin_can(): whether subject has at least ONE of the rights specified in rights_required.
/proc/check_rights_for(client/subject, rights_required)
	READS_FROM()
	return admin_can(subject, rights_required)

/proc/GenerateToken()
	. = ""
	for(var/I in 1 to 32)
		. += "[rand(10)]"

/proc/RawHrefToken(forceGlobal = FALSE)
	var/tok = GLOB.href_token
	if(!forceGlobal && usr)
		var/client/C = usr.client
		return RawHrefTokenFor(C)
	return tok

/// Resolve the same admin token for an explicitly supplied current client.
/proc/RawHrefTokenFor(client/C)
	if(!C)
		log_runtime("Attempted to retrieve a HrefToken of an entity with no client.")
		return 0
	var/datum/admins/holder = C.holder
	return holder ? holder.href_token : GLOB.href_token

/// An ordinary synchronous caller supplies its actual actor instead of ambient usr.
/proc/HrefTokenFor(mob/actor)
	return "admin_token=[RawHrefTokenFor(actor?.client)]"

/proc/HrefToken(forceGlobal = FALSE)
	return "admin_token=[RawHrefToken(forceGlobal)]"

/proc/HrefTokenFormField(forceGlobal = FALSE)
	return "<input type='hidden' name='admin_token' value='[RawHrefToken(forceGlobal)]'>"

// Shared admin_rank registry entries.

/// The marked_datum this refers to (a relation view: null once that is deleted).
/datum/admins/proc/marked_datum() as /datum
	return marked_datum

/// The owner this refers to (a relation view: null once that is deleted).
/datum/admins/proc/owner() as /client
	return owner

/// The channel the admin newscaster is working on: a picked network channel (a relation view) or the scratch one.
/datum/admins/proc/admincaster_feed_channel() as /datum/feed_channel
	return admincaster_feed_channel || admincaster_scratch_channel

/// Replaces our ranks (a relation list) with `new_ranks`.
/datum/admins/proc/set_ranks(list/datum/admin_rank/new_ranks)
	rel_clear(src, nameof(ranks))
	for(var/datum/admin_rank/rank as anything in new_ranks)
		rel_add(src, nameof(ranks), rank)

/// The client's admin datum (null for a non-admin). The one read accessor outside modules/admin/holder*; rights
/// questions go through admin_can().
/client/proc/admin_datum() as /datum/admins
	return holder
