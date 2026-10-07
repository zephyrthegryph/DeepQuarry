// Mob registries (code/datums/registry_declarations.dm). Every mob is in
// REGISTRY_MOBS while materialized; REGISTRY_LIVING_MOBS / REGISTRY_DEAD_MOBS
// follow its stat and REGISTRY_PLAYERS its client (Login/Logout). All of them
// drop a mob by themselves when it is deleted.
REGISTRY_MEMBERSHIP(/mob, REGISTRY_MOBS)
REGISTRY_MEMBERSHIP(/mob, REGISTRY_LIVING_MOBS)
REGISTRY_MEMBERSHIP(/mob, REGISTRY_DEAD_MOBS)
REGISTRY_MEMBERSHIP(/mob, REGISTRY_PLAYERS)

REGISTRY_MEMBERSHIP(/mob, REGISTRY_ENTOPIC_USERS)

REGISTRY_MEMBERSHIP(/mob/living, REGISTRY_FORCED_AMBIANCE)

/mob/on_materialize()
	. = ..()
	registry_join(stat == DEAD ? REGISTRY_DEAD_MOBS : REGISTRY_LIVING_MOBS, src) // ALLOW(decl): registry picked by stat


/mob/on_destroy(force)//This makes sure that mobs withGLOB.clients/keys are not just deleted from the game.
	publish_mob_chunk(src, FALSE)
	if(client)
		stack_trace("Mob with client has been deleted.")

	persistent_client?.set_mob(null)

	unset_machine()
	clear_fullscreen()
	// The screen objects are ours (rel_set by the HUD setup) and go in teardown.
	if(client)
		client.screen = list()
	if(mind && mind.current == src)
		spellremove(src)
	if(!istype(src,/mob/observer))
		ghostize(FALSE)
	for(var/key in alerts) //clear out alerts
		clear_alert(key)
	if(src?.pulling_target())
		stop_pulling() //TG does this on atom/movable but our stop_pulling proc is here so whatever

	// Our bellies go with us through the declared ownership policy.
	for(var/mob/observer/dead/M in src?.follower_list())
		M.stop_following()
	motiontracker_unsubscribe(TRUE) // Force unsubscribe
	// mind.current / mind.original_character are relation views: they clear as we go.
	..()
	update_client_z(null)
	//return QDEL_HINT_HARDDEL_NOW

/mob/Initialize(mapload)
	PUBLISH_LEGACY(OM_WORLD, /datum/notice/world_mob_created, src)
	lastarea = get_area(src)
	if(speak_emote)
		speak_emote = shared_type_list(type, "speak_emote", speak_emote)
	if(shouldnt_see)
		shouldnt_see = shared_type_list(type, "shouldnt_see", shouldnt_see)
	set_focus(src) // Key Handling
	update_transform() // Some mobs may start bigger or smaller than normal.
	. = ..()
	publish_mob_chunk(src, TRUE)
	log_mob_tag(src, "TAG: [tag] CREATED: [key_name(src)] \[[type]\]")
	//return QDEL_HINT_HARDDEL_NOW Just keep track of mob references. They delete SO much faster now.

/mob/show_message(msg, type, alt, alt_type)

	if(!client && !teleop)	return

	if (type)
		if((type & VISIBLE_MESSAGE) && (is_blind() || has_status(STAT_PARALYZED)) )//Vision related
			if (!( alt ))
				return
			else
				msg = alt
				type = alt_type
		if ((type & AUDIBLE_MESSAGE) && is_deaf())//Hearing related
			if (!( alt ))
				return
			else
				msg = alt
				type = alt_type
				if ((type & VISIBLE_MESSAGE) && (sdisabilities & BLIND))
					return
	// Added voice muffling for Issue 41.
	if(stat == UNCONSCIOUS || has_status(STAT_SLEEPING))
		to_chat(src, span_filter_notice(span_italics("... You can almost hear someone talking ...")))
	else
		if(teleop)
			to_chat(teleop, create_text_tag("body", "BODY:", teleop.client) + "[msg]")
		else
			to_chat(src,msg)
	return

// Show a message to all mobs and objects in sight of this one
// This would be for visible actions by the src mob
// message is the message output to anyone who can see e.g. "[src] does something!"
// self_message (optional) is what the src mob sees  e.g. "You do something!"
// blind_message (optional) is what blind people will hear e.g. "You hear something!"
/mob/visible_message(message, self_message, blind_message, list/exclude_mobs = null, range = world.view, runemessage)
	if(self_message)
		if(LAZYLEN(exclude_mobs))
			exclude_mobs |= src
		else
			exclude_mobs = list(src)
		show_message(self_message, 1, blind_message, 2)
	if(isnull(runemessage))
		runemessage = -1
	. = ..(message, blind_message, exclude_mobs, range, runemessage) // Really not ideal that atom/visible_message has different arg numbering :(

// Returns an amount of power drawn from the object (-1 if it's not viable).
// If drain_check is set it will not actually drain power, just return a value.
// If surge is set, it will destroy/damage the recipient and not return any power.
// Not sure where to define this, so it can sit here for the rest of time.
/atom/proc/drain_power(drain_check,surge, amount = 0)
	return -1

// used for petrification machines
/proc/get_ultimate_mob(atom/source)
	READS_FROM(source)
	var/mob/ultimate_mob
	var/atom/to_check = source.loc // ALLOW(reads): a helper a use condition asks about where the thing is held; the click asks again
	var/n = 0
	while (to_check && !isturf(to_check) && n++ < 16)
		if (ismob(to_check))
			ultimate_mob = to_check
			to_check = to_check.loc // ALLOW(reads): a helper a use condition asks about where the thing is held; the click asks again
	return ultimate_mob

// Show a message to all mobs and objects in earshot of this one
// This would be for audible actions by the src mob
// message is the message output to anyone who can hear.
// self_message (optional) is what the src mob hears.
// deaf_message (optional) is what deaf people will see.
// hearing_distance (optional) is the range, how many tiles away the message can be heard.
/mob/audible_message(message, deaf_message, hearing_distance, self_message, radio_message, runemessage)

	var/range = hearing_distance || world.view
	var/list/hear = get_mobs_and_objs_in_view_fast(get_turf(src),range,remote_ghosts = FALSE)

	var/list/hearing_mobs = hear["mobs"]
	var/list/hearing_objs = hear["objs"]

	if(isnull(runemessage))
		runemessage = -1 // Symmetry with mob/audible_message, despite the fact this one doesn't call parent. Maybe it should!

	if(radio_message)
		for(var/obj/O as anything in hearing_objs)
			O.hear_talk(src, list(new /datum/multilingual_say_piece(GLOB.all_languages["Noise"], radio_message)), null)
	else
		for(var/obj/O as anything in hearing_objs)
			O.show_message(message, AUDIBLE_MESSAGE, deaf_message, VISIBLE_MESSAGE)

	for(var/mob/M as anything in hearing_mobs)
		var/msg = message
		if(self_message && M==src)
			msg = self_message
		M.show_message(msg, AUDIBLE_MESSAGE, deaf_message, VISIBLE_MESSAGE)
		if(runemessage != -1)
			M.create_chat_message(src, "[runemessage || message]", FALSE, list("emote"), audible = FALSE)

/mob/proc/findname(msg)
	for(var/mob/M in REGISTRY_MEMBERS(REGISTRY_MOBS))
		if (M.real_name == text("[]", msg))
			return M
	return 0

#define UNBUCKLED 0
#define PARTIALLY_BUCKLED 1
#define FULLY_BUCKLED 2
/mob/proc/buckled()
	// Preliminary work for a future buckle rewrite,
	// where one might be fully restrained (like an elecrical chair), or merely secured (shuttle chair, keeping you safe but not otherwise restrained from acting)
	if(!src?.buckled_to())
		return UNBUCKLED
	return restrained() ? FULLY_BUCKLED : PARTIALLY_BUCKLED

/mob/proc/is_blind()
	return ((sdisabilities & BLIND) || blinded || incapacitated(INCAPACITATION_KNOCKOUT))

/mob/proc/is_deaf()
	return ((sdisabilities & DEAF) || has_status(STAT_DEAFENED) || incapacitated(INCAPACITATION_KNOCKOUT))

/mob/proc/is_paralyzed()
	return status_units(STAT_PARALYZED)

/mob/proc/is_physically_disabled()
	return incapacitated(INCAPACITATION_DISABLED)

/mob/proc/cannot_stand()
	return incapacitated(INCAPACITATION_KNOCKDOWN)

/mob/proc/incapacitated(incapacitation_flags = INCAPACITATION_DEFAULT)
	if((incapacitation_flags & INCAPACITATION_STUNNED) && has_status(STAT_STUNNED))
		return 1

	if((incapacitation_flags & INCAPACITATION_FORCELYING) && (has_status(STAT_WEAKENED) || resting))
		return 1

	if((incapacitation_flags & INCAPACITATION_KNOCKOUT) && (stat || has_status(STAT_SLEEPING)))
		return 1

	if((incapacitation_flags & INCAPACITATION_RESTRAINED) && restrained())
		return 1

	if((incapacitation_flags & (INCAPACITATION_BUCKLED_PARTIALLY|INCAPACITATION_BUCKLED_FULLY)))
		var/buckling = buckled()
		if(buckling >= PARTIALLY_BUCKLED && (incapacitation_flags & INCAPACITATION_BUCKLED_PARTIALLY))
			return 1
		if(buckling == FULLY_BUCKLED && (incapacitation_flags & INCAPACITATION_BUCKLED_FULLY))
			return 1

	return 0

#undef UNBUCKLED
#undef PARTIALLY_BUCKLED
#undef FULLY_BUCKLED

/mob/proc/restrained()
	return

/**
 * Reset the attached clients perspective (viewpoint)
 *
 * reset_perspective() set eye to common default : mob on turf, loc otherwise. If the client mob is inside an object with REMOTEVIEW_ON_ENTER, it will restart that object's remote view.
 * reset_perspective(thing) set the eye to the thing (if it's equal to current default reset to mob perspective). This ignores REMOTEVIEW_ON_ENTER, and forces focus to the mob.
 */
/mob/proc/reset_perspective(atom/new_eye)
	SHOULD_CALL_PARENT(TRUE)
	if(!client)
		return
	if(!isnull(new_eye) && QDELETED(new_eye))
		new_eye = src // Something has gone terribly wrong

	if(new_eye)
		if(ismovable(new_eye))
			//Set the new eye unless it's us
			if(new_eye != src)
				client.perspective = EYE_PERSPECTIVE
				client.set_eye(new_eye)
			else
				client.set_eye(client.mob)
				client.perspective = MOB_PERSPECTIVE

		else if(isturf(new_eye))
			//Set to the turf unless it's our current turf
			if(new_eye != loc)
				client.perspective = EYE_PERSPECTIVE
				client.set_eye(new_eye)
			else
				client.set_eye(client.mob)
				client.perspective = MOB_PERSPECTIVE
		else
			return TRUE //no setting eye to stupid things like areas or whatever
	else
		//If we return focus to our own mob, but we are still inside something with an inherent remote view. Restart it.
		if(restore_remote_views())
			return TRUE
		//Reset to common defaults: mob if on turf, otherwise current loc. Fallback to mob if we are in nullspace.
		if(isturf(loc) || isnull(loc))
			client.set_eye(client.mob)
			client.perspective = MOB_PERSPECTIVE
		else
			client.perspective = EYE_PERSPECTIVE
			client.set_eye(loc)
	/// Signal sent after the eye has been successfully updated, with the client existing.
	PUBLISH_LEGACY(src, /datum/notice/mob_reset_perspective)
	return TRUE

/// Reapplies remote views based on object type and flags. Returns true if the view was assigned.
/mob/proc/restore_remote_views()
	if(!loc) // Nullspace during respawn
		return FALSE
	if(QDELETED(loc) || QDELETED(src)) // location or ourselves is qdeleted, don't restart remote viewing during destroy
		return FALSE
	if(isturf(loc)) // Cannot be remote if it was a turf, also obj and turf flags overlap so stepping into space triggers remoteview endlessly.
		return FALSE
	// Check if we actually need to drop our current remote view component, as this is expensive to do, and leads to more difficult to understand error prone logic
	var/datum/remote_view/remote_comp = remote_view
	if(remote_comp?.looking_at_target_already(loc))
		return FALSE
	if(isitem(loc) || isbelly(loc) || ismecha(loc)) // Requires more careful handling than structures because they are held by mobs
		begin_remote_view(/datum/remote_view/mob_holding_item, loc, null, /datum/remote_view_config/inside_object)
		return TRUE
	if(loc.flags & REMOTEVIEW_ON_ENTER) // Handle atoms that begin a remote view upon entering them.
		begin_remote_view(/datum/remote_view, loc, null, /datum/remote_view_config/inside_object)
		return TRUE
	return FALSE

/mob/proc/ret_grab(list/L, flag)
	return

/mob/verb/mode()
	set name = "Activate Held Object"
	set category = VERB_CAT_OBJECT
	set src = usr

	return

/mob/verb/memory()
	set name = "Notes"
	set desc = "View notes stored for this round only."
	set category = VERB_CAT_IC_NOTES
	if(mind)
		mind.show_memory(src)
	else
		to_chat(src, "The game appears to have misplaced your mind datum, so we can't show you your notes.")

/mob/verb/add_memory(msg as message)
	set name = "Add Note"
	set desc = "Add notes stored for this round only."
	set category = VERB_CAT_IC_NOTES

	msg = sanitize(msg)

	if(mind)
		mind.store_memory(msg)
	else
		to_chat(src, "The game appears to have misplaced your mind datum, so we can't show you your notes.")

/mob/proc/store_memory(msg as message, popup, sane = 1)
	msg = copytext(msg, 1, MAX_MESSAGE_LEN)

	if (sane)
		msg = sanitize(msg)

	if (length(memory) == 0)
		memory += msg
	else
		memory += "<BR>[msg]"

	if (popup)
		memory()

/mob/proc/update_flavor_text()
	set src in usr
	if(usr != src)
		to_chat(src, "No.")
	open_request(src, /datum/prompt/text, PROC_REF(flavor_text_entered), answerer = src, timeout = 0, title = "Flavor Text", question = "Set the flavor text in your 'examine' verb.", default = html_decode(flavor_text), max_len = MAX_MESSAGE_LEN, multiline = TRUE)

/mob/proc/flavor_text_entered(datum/act/request/A)
	if(!A.answer)
		return
	return flavor_text_apply(A.answer.value)

/mob/proc/flavor_text_apply(new_text)
	flavor_text = new_text

/mob/proc/warn_flavor_changed()
	if(flavor_text && flavor_text != "") // don't spam people that don't use it!
		to_chat(src, span_filter_notice("<h2 class='alert'>OOC Warning:</h2>"))
		to_chat(src, span_filter_notice(span_warning("Your flavor text is likely out of date! <a href='byond://?src=\ref[src];flavor_change=1'>Change</a>")))

/mob/proc/print_flavor_text()
	if (flavor_text && flavor_text != "")
		var/msg = replacetext(flavor_text, "\n", " ")
		if(length(msg) <= 40)
			return span_notice("[msg]")
		else
			return span_notice("[copytext_preserve_html(msg, 1, 37)]... <a href='byond://?src=\ref[src];flavor_more=1'>More...</a>")

/mob/proc/set_respawn_timer(time)
	// Try to figure out what time to use

	// Special cases, can never respawn
	if(SSticker?.mode?.deny_respawn)
		time = -1
	else if(!CONFIG_GET(flag/abandon_allowed))
		time = -1
	else if(!CONFIG_GET(flag/respawn))
		time = -1

	// Special case for observing before game start
	else if(SSticker?.current_state <= GAME_STATE_SETTING_UP)
		time = 1 MINUTE

	// Wasn't given a time, use the config time
	else if(!time)
		time = CONFIG_GET(number/respawn_time)

	var/keytouse = ckey
	// Try harder to find a key to use
	if(!keytouse && key)
		keytouse = ckey(key)
	else if(!keytouse && mind?.key)
		keytouse = ckey(mind.key)

	GLOB.respawn_timers[keytouse] = EXPIRY_AT(null, CLOCK_WORLD, 0) + time

/mob/observer/dead/set_respawn_timer()
	if(CONFIG_GET(flag/antag_hud_restricted) && has_enabled_antagHUD)
		..(-1)
	else
		return // Don't set it, no need

/mob/verb/abandon_mob()
	set name = "Return to Menu"
	set category = VERB_CAT_OOC_GAME
	if(istype(src, /mob/new_player))
		to_chat(src, span_boldnotice("You are already in the lobby!"))
		return

	if(stat != DEAD || !SSticker)
		to_chat(src, span_boldnotice("You must be dead to use this!"))
		return

	// Final chance to abort "respawning"
	if(mind && timeofdeath) // They had spawned before
		open_request(src, /datum/prompt/choice/abandon_mob, PROC_REF(abandon_mob_confirmed), answerer = src)
		return
	abandon_mob_finish(FALSE)

/// Leaving for the lobby: only while still dead.
/datum/prompt/choice/abandon_mob
	title = "Confirmation"
	question = "Returning to the menu will prevent your character from being revived in-round. Are you sure?"
	choices = list("No, wait", "Yes, leave")
	buttons = TRUE
	timeout = 0

/datum/prompt/choice/abandon_mob/recheck_extra()
	return answerer.stat == DEAD ? null : "not dead"

/// Quitting the round on the way out; no still returns to the lobby.
/datum/prompt/choice/abandon_mob/quit_round
	title = "Quit This Round"
	question = "Do you want to Quit This Round before you return to lobby? This will properly remove you from manifest, as well as prevent resleeving. BEWARE: Pressing 'NO' will STILL return you to lobby!"
	choices = list("Quit Round", "No")

/mob/proc/abandon_mob_confirmed(datum/act/request/A)
	if(A.answer?.value != "Yes, leave")
		return
	if(mind?.assigned_role)
		open_request(src, /datum/prompt/choice/abandon_mob/quit_round, PROC_REF(abandon_mob_quit_answered), answerer = src)
		return
	abandon_mob_finish(FALSE)

/mob/proc/abandon_mob_quit_answered(datum/act/request/A)
	if(!A.answer)
		return
	abandon_mob_finish(A.answer.value == "Quit Round")

/// Leaves the body for the lobby; `quit_round` also frees the job and removes the records.
/mob/proc/abandon_mob_finish(quit_round)
	if(quit_round && mind)
		//Update any existing objectives involving this mob.
		for(var/datum/objective/O in REGISTRY_MEMBERS(REGISTRY_OBJECTIVES))
			if(O.target == mind)
				if(O.owner && O.owner.current)
					to_chat(O.owner.current,span_warning("You get the feeling your target is no longer within your reach..."))
				spent(O)

		//Resleeving cleanup
		if(mind)
			SStranscore.leave_round(src)

		//Job slot cleanup
		var/job = mind.assigned_role
		SSjob.free_role(job)

		//Their objectives cleanup
		if(length(mind.objectives))
			// each dying objective leaves mind.objectives on its own (works for the OWN or pair declaration)
			for(var/datum/objective/O as anything in mind.objectives.Copy())
				spent(O)
			mind.special_role = null

		//Cut the PDA manifest (ugh)
		if(GLOB.PDA_Manifest.len)
			GLOB.PDA_Manifest.Cut()
		for(var/datum/data/record/R in GLOB.data_core.medical)
			if((R.fields["name"] == real_name))
				spent(R)
		for(var/datum/data/record/T in GLOB.data_core.security)
			if((T.fields["name"] == real_name))
				spent(T)
		for(var/datum/data/record/G in GLOB.data_core.general)
			if((G.fields["name"] == real_name))
				spent(G)

		//This removes them from being 'active' list on join screen
		mind.assigned_role = null
		to_chat(src,span_notice("Your job has been free'd up, and you can rejoin as another character or quit. Thanks for properly quitting round, it helps the server!"))

	// Beyond this point, you're going to respawn

	if(!client)
		log_game("[key] AM failed due to disconnect.")
		return
	client.screen.Cut()
	client.screen += client.void
	if(!client)
		log_game("[key] AM failed due to disconnect.")
		return

	announce_ghost_joinleave(client, 0)

	var/mob/new_player/M = new /mob/new_player()
	if(!client)
		log_game("[key] AM failed due to disconnect.")
		spent(M)
		M.key = null
		return

	M.has_respawned = TRUE //When we returned to main menu, send respawn message
	M.key = key

	if(M.mind)
		M.mind.reset()
	return

/client/verb/changes()
	set name = "Changelog"
	set category = VERB_CAT_OOC_RESOURCES

	if(!GLOB.changelog_tgui)
		GLOB.changelog_tgui = new /datum/changelog()
	GLOB.changelog_tgui.tgui_interact(usr)

	if(prefs?.read_preference(/datum/preference/text/lastchangelog) != GLOB.changelog_hash)
		prefs.write_preference_by_type(/datum/preference/text/lastchangelog, GLOB.changelog_hash)

/mob/verb/observe()
	set name = "Observe"
	set category = VERB_CAT_OOC_GAME
	var/is_admin = 0

	if(check_rights_for(client, R_ADMIN|R_EVENT))
		is_admin = 1
	else if(stat != DEAD || isnewplayer(src))
		to_chat(src, span_filter_notice("[span_blue("You must be observing to use this!")]"))
		return

	if(is_admin && stat == DEAD)
		is_admin = 0

	var/list/targets = list()

	targets += observe_list_format(REGISTRY_MEMBERS(REGISTRY_NUKE_DISKS))
	targets += observe_list_format(REGISTRY_MEMBERS(REGISTRY_SINGULARITIES))
	targets += getmobs()
	targets += observe_list_format(sort_names(REGISTRY_MEMBERS(REGISTRY_MECHAS)))
	targets += observe_list_format(SSshuttles.ships)

	client.perspective = EYE_PERSPECTIVE

	var/ok = "[is_admin ? "Admin Observe" : "Observe"]"
	open_request(src, /datum/prompt/choice/observe_target, PROC_REF(observe_target_chosen), answerer = src, question = "Select something to [ok]:", choices = targets, is_admin = is_admin)

/datum/prompt/choice/observe_target
	title = "Select Target"
	timeout = 0
	var/is_admin = FALSE

/mob/proc/observe_target_chosen(datum/act/request/A)
	if(!A.answer)
		return
	return observe_target_apply(A)

/mob/proc/observe_target_apply(datum/act/request/A)
	var/datum/prompt/choice/observe_target/ask = A.answer
	var/is_admin = ask.is_admin
	var/mob/mob_eye = ask.choices[ask.value]

	if(client && mob_eye)
		begin_remote_view(/datum/remote_view, mob_eye)
		if(is_admin)
			client.adminobs = TRUE
			if(mob_eye == client.mob || !is_remote_viewing())
				client.adminobs = FALSE

/mob/verb/cancel_camera()
	set name = "Cancel Camera View"
	set category = VERB_CAT_OOC_GAME
	reset_perspective()


/mob/proc/topic_flavor_more(datum/act/op/A)
	var/mob/user = A.actor
	var/examine_text = splittext(flavor_text, "||")
	var/index = 0
	var/rendered_text = ""
	for(var/part in examine_text)
		if(index % 2)
			rendered_text += span_spoiler("[part]")
		else
			rendered_text += "[part]"
		index++
	examine_text = replacetext(rendered_text, "\n", "<BR>")
	// structured TGUI AdminReport.
	dq_admin_report_html(user, "[name]", examine_text)
	return TRUE

/mob/proc/topic_flavor_change(datum/act/op/A, href_flavor_change)
	update_flavor_text()
	return TRUE

///Proc that checks to see if we DO damage via pulling or not.
/mob/proc/pull_damage()
	return FALSE

///Proc that says if it's POSSIBLE to be damaged via pulling or not.
/mob/proc/pull_can_damage()
	return FALSE

/mob/verb/stop_pulling()

	set name = "Stop Pulling"
	set category = VERB_CAT_IC_GAME

	var/atom/movable/pulling = src?.pulling_target()
	if(pulling)
		if(ishuman(pulling))
			var/mob/living/carbon/human/H = pulling
			act_message(src, H, MSG_SELF(span_notice("You let go of %T%.")), MSG_OTHERS(span_warning("%U% lets go of %T%.")), exclude = list(H))
			if(!H.stat)
				to_chat(H, span_warning("\The [src] lets go of you."))
		// The pulling relation's on_unlink() (code/datums/om/library.dm)
		// clears the pull HUD icon; PULLING()/PULLED_BY() (om.dm) are pure
		// graph reads, with no stored field left to clear.
		om_unlink(src, pulling, /datum/om/relation/pulling)

/mob/proc/start_pulling(atom/movable/AM)

	if ( !AM || src==AM || !isturf(loc) )	//if there's no person pulling OR the person is pulling themself OR the object being pulled is inside something: abort!
		return

	if (AM.anchored)
		to_chat(src, span_warning("It won't budge!"))
		return

	if(lying)
		return

	var/mob/M = AM
	if(ismob(AM))

		if(!can_pull_mobs || !can_pull_size)
			to_chat(src, span_warning("They won't budge!"))
			return

		if((mob_size < M.mob_size) && (can_pull_mobs != MOB_PULL_LARGER))
			to_chat(src, span_warning("[M] is too large for you to move!"))
			return

		if((mob_size == M.mob_size) && (can_pull_mobs == MOB_PULL_SMALLER))
			to_chat(src, span_warning("[M] is too heavy for you to move!"))
			return

		// If your size is larger than theirs and you have some
		// kind of mob pull value AT ALL, you will be able to pull
		// them, so don't bother checking that explicitly.

		if(LAZYLEN(M?.grabbed_by_list()))
			// Only start pulling when nobody else has a grab on them
			. = 1
			for(var/obj/item/grab/G in M?.grabbed_by_list())
				if(G?.grab_assailant() != src)
					. = 0
				else
					spent(G)
			if(!.)
				to_chat(src, span_warning("Somebody has a grip on them!"))
				return

		if(!iscarbon(src))
			rel_clear(M, nameof(M.LAssailant))
		else
			rel_set(M, nameof(M.LAssailant), src)

		if(M.no_pull_when_living && !(M.stat == DEAD)) //If it's now allowed to be pulled when living, and it's not dead yet, deny.
			to_chat(src, span_warning("\The [M] won't let you just pull them!"))
			return

	else if(isobj(AM))
		var/obj/I = AM
		if(!can_pull_size || can_pull_size < I.w_class)
			to_chat(src, span_warning("It won't budge!"))
			return

	var/pulling_old = src?.pulling_target()
	if(pulling_old)
		stop_pulling()
		// Are we pulling the same thing twice? Just stop pulling.
		if(pulling_old == AM)
			return

	// The pulling relation (code/datums/om/library.dm) raises the pull HUD
	// icon and the status channel as its on_link() side effects; PULLING()/
	// PULLED_BY() (om.dm) are pure graph reads, nothing to set here.
	// target_single means it also drops AM's previous puller, if any.
	if(!istype(om_link(src, AM, /datum/om/relation/pulling), /datum/om/edge))
		return

	if(ishuman(AM))
		var/mob/living/carbon/human/H = AM
		if(H.lying) // If they're on the ground we're probably dragging their arms to move them
			act_message(src, H, MSG_SELF(span_notice("You lean down and grip %T%'s arms.")), MSG_OTHERS(span_warning("%U% leans down and grips %T%'s arms.")), exclude = list(H))
			if(!H.stat)
				to_chat(H, span_warning("\The [src] leans down and grips your arms."))
		else //Otherwise we're probably just holding their arm to lead them somewhere
			act_message(src, H, MSG_SELF(span_notice("You grip %T%'s arm.")), MSG_OTHERS(span_warning("%U% grips %T%'s arm.")), exclude = list(H))
			if(!H.stat)
				to_chat(H, span_warning("\The [src] grips your arm."))
		play_sfx(loc, SFX_WEAPONS_THUDSWOOSH, 0.5, vary = FALSE, extrarange = 0) //Quieter than hugging/grabbing but we still want some audio feedback

		if(H.pull_can_damage())
			to_chat(src, span_danger(span_large("Pulling \the [H] in their current condition could easily worsen their injuries.")))

// We have pulled something before, so we should be able to safely continue pulling it. This proc is only for portals!
/mob/proc/continue_pulling(atom/movable/AM)

	if ( !AM || src==AM || !isturf(loc) )	//if there's no person pulling OR the person is pulling themself OR the object being pulled is inside something: abort!
		return

	if (AM.anchored)
		return

	// The pulling relation (code/datums/om/library.dm) raises the pull HUD
	// icon as its on_link() side effect, but only the first
	// time this source/target pair links -- re-affirm the inertia reset
	// unconditionally here since continue_pulling() exists specifically for
	// discontinuous jumps (portals, multi-z, redgates) where it matters every time.
	om_link(src, AM, /datum/om/relation/pulling)
	if(ismob(AM))
		var/mob/pulled = AM
		pulled.inertia_dir = 0

/mob/proc/can_use_hands()
	return

/mob/proc/is_active()
	return (0 >= stat)

/// Vital-state predicate: is this mob dead (stat)? See code/modules/body/vital_state.dm.
/mob/proc/is_dead()
	return stat == DEAD

/// Vital-state predicate: is this mob alive (not DEAD)?
/mob/proc/is_alive()
	return stat != DEAD

/mob/proc/is_ready()
	return client && !!mind

/mob/proc/get_gender()
	return gender

/mob/proc/name_gender()
	return gender

/mob/proc/see(message)
	if(!is_active())
		return 0
	to_chat(src,message)
	return 1

/mob/proc/show_viewers(message)
	for(var/mob/M in viewers())
		M.see(message)

/// Adds this list to the output to the stat browser
/mob/proc/get_status_tab_items()
	. = list()

/// Gets all relevant proc holders for the browser statpenl
/mob/proc/get_proc_holders()
	. = list()
	//if(mind)
		//. += get_spells_for_statpanel(mind.spell_list)
	//. += get_spells_for_statpanel(mob_spell_list)

/mob/proc/update_misc_tabs()
	misc_tabs = list() //Reset misc_tabs every Stat() to prevent old shit sticking around

// facing verbs
/mob/proc/canface()
	if(stat)							return 0
	if(anchored)						return 0
	if(transforming)						return 0
	return 1

// Not sure what to call this. Used to check if humans are wearing an AI-controlled exosuit and hence don't need to fall over yet.
/mob/proc/can_stand_overridden()
	return 0

//Updates canmove, lying and icons. Could perhaps do with a rename but I can't think of anything to describe it.
/mob/proc/update_canmove()
	return canmove

/mob/proc/facedir(ndir)
	if(!canface() || (client && (client.moving || !checkMoveCooldown())))
		DEBUG_INPUT("Denying Facedir for [src] (moving=[client?.moving])")
		return 0
	set_dir(ndir)
	var/obj/buckled = src?.buckled_to()
	if(buckled && buckled.buckle_movable)
		buckled.set_dir(ndir)
	setMoveCooldown(movement_delay())
	return 1

/mob/verb/eastface()
	set hidden = 1
	return facedir(client.client_dir(EAST))

/mob/verb/westface()
	set hidden = 1
	return facedir(client.client_dir(WEST))

/mob/verb/northface()
	set hidden = 1
	return facedir(client.client_dir(NORTH))

/mob/verb/southface()
	set hidden = 1
	return facedir(client.client_dir(SOUTH))

//This might need a rename but it should replace the can this mob use things check
/mob/proc/IsAdvancedToolUser()
	return 0

/mob/proc/Resting(amount)
	facing_dir = null
	set_resting(max(max(resting,amount),0))
	update_canmove()
	return

/mob/proc/SetResting(amount)
	set_resting(max(amount,0))
	update_canmove()
	return

/mob/proc/AdjustResting(amount)
	set_resting(max(resting + amount,0))
	update_canmove()
	return

/mob/proc/AdjustLosebreath(amount)
	losebreath = CLAMP(losebreath + amount, 0, 25)

/mob/proc/SetLosebreath(amount)
	losebreath = CLAMP(amount, 0, 25)

/mob/proc/get_species()
	return ""

/mob/proc/flash_weak_pain()
	flick("weak_pain",pain)

/mob/proc/get_visible_implants(class = 0)
	var/list/visible_implants = list()
	for(var/obj/item/O in embedded)
		if(O.w_class > class)
			visible_implants += O
	return visible_implants

/mob/proc/embedded_needs_process()
	return (LAZYLEN(embedded) > 0)

/datum/task/timed/mob_yank_out
	duration = 3 SECONDS
	complete_proc = /mob/proc/yank_out_done
	var/obj/item/selection
	var/self

/mob/proc/yank_out_done(datum/task/timed/mob_yank_out/task)
	var/mob/U = task.actor
	var/obj/item/selection = task.selection
	var/self = task.self
	var/mob/S = src
	var/list/valid_objects
	if(!selection || !S || !U)
		return

	if(self)
		act_message(src, null, MSG_SELF(span_boldwarning("You rip [selection] out of your body.")), \
			MSG_OTHERS(span_boldwarning("%U% rips [selection] out of their body.")))
	else
		act_message(src, U, MSG_SELF(span_boldwarning("%T% rips [selection] out of your body.")), \
			MSG_OTHERS(span_boldwarning("%T% rips [selection] out of %U%'s body.")))
	valid_objects = get_visible_implants(0)
	if(valid_objects.len == 1) //Yanking out last object - removing verb.
		revoke(src, granted_verb(/mob/proc/yank_out_object), src) // embed() grants it
		clear_alert("embeddedobject")

	if(ishuman(src))
		var/mob/living/carbon/human/H = src
		var/obj/item/organ/external/affected

		for(var/obj/item/organ/external/organ in H.organs) //Grab the organ holding the implant.
			for(var/obj/item/O in organ.implants)
				if(O == selection)
					affected = organ

		rel_remove(affected, nameof(affected.implants), selection)
		H.adjust_shock(20, "implant extraction")
		H.injure(INJURY_CUT, selection.w_class * 3, affected.organ_tag, selection, 0, null, INJURE_IGNORE_RESISTANCE) // Embedded object extraction

		if(prob(selection.w_class * 5) && (!affected.is_robotic())) //I'M SO ANEMIC I COULD JUST -DIE-.
			affected.add_wound(new /datum/affliction/wound/internal_bleeding(affected, min(selection.w_class * 5, 15)))
			affected.update_damages()
			H.custom_pain("Something tears wetly in your [affected] as [selection] is pulled free!", 50)

		if (ishuman(U))
			var/mob/living/carbon/human/human_user = U
			human_user.bloody_hands(H)

	else if(issilicon(src))
		var/mob/living/silicon/robot/R = src
		LAZYREMOVE(R.embedded, selection)
		R.injure(INJURY_CUT, 5, null, selection)
		R.injure(INJURY_ELECTRIC, 10, null, selection) // Torn wiring shorts out.

	selection.forceMove(get_turf(src))
	U.put_in_hands(selection)

	for(var/obj/item/O in pinned)
		if(O == selection)
			rel_remove(src, nameof(pinned), O)
		if(!LAZYLEN(pinned))
			set_anchored(FALSE)
	return 1

/mob/proc/yank_out_object()
	set category = VERB_CAT_OBJECT
	set name = "Yank out object"
	set desc = "Remove an embedded item at the cost of bleeding and pain."
	set src in view(1)

	if(!isliving(usr) || !usr.checkClickCooldown())
		return
	usr.setClickCooldown(20)

	if(usr.stat == 1)
		to_chat(usr, span_filter_notice("You are unconcious and cannot do that!"))
		return

	if(usr.restrained())
		to_chat(usr, span_filter_notice("You are restrained and cannot do that!"))
		return

	var/mob/S = src
	var/mob/U = usr
	var/list/valid_objects = list()
	var/self = null

	if(S == U)
		self = 1 // Removing object from yourself.

	valid_objects = get_visible_implants(0)
	if(!valid_objects.len)
		if(self)
			to_chat(src, span_filter_notice("You have nothing stuck in your body that is large enough to remove."))
		else
			to_chat(U, span_filter_notice("[src] has nothing stuck in their wounds that is large enough to remove."))
		return

	open_request(src, /datum/prompt/choice/yank_object, PROC_REF(yank_object_chosen), answerer = U, choices = valid_objects, self = self)

/// Which embedded object to pull out: the answerer must still be next to the body.
/datum/prompt/choice/yank_object
	title = "Embedded objects"
	question = "What do you want to yank out?"
	timeout = 0
	ask_flags = ASK_ADJACENT | ASK_CAPABLE
	var/self

/datum/prompt/choice/yank_object/recheck_extra()
	if(!isnull(value))
		var/obj/item/selected = value
		if(!istype(selected) || QDELETED(selected))
			return "gone"

/mob/proc/yank_object_chosen(datum/act/request/A)
	if(!A.answer)
		return
	return yank_object_apply(A)

/mob/proc/yank_object_apply(datum/act/request/A)
	var/datum/prompt/choice/yank_object/ask = A.answer
	var/mob/U = ask.answerer
	var/obj/item/selection = ask.value
	var/self = ask.self
	var/mob/S = src
	if(!(selection in get_visible_implants(0)))
		return
	if(self)
		to_chat(src, span_warning("You attempt to get a good grip on [selection] in your body."))
	else
		to_chat(U, span_warning("You attempt to get a good grip on [selection] in [S]'s body."))

	task_start(/datum/task/timed/mob_yank_out, U, src, receiver = src, selection = selection, self = self)

//Check for brain worms in head.
/mob/proc/has_brain_worms()

	for(var/I in contents)
		if(istype(I,/mob/living/simple_mob/animal/borer))
			return I

	return 0

// Please always use this proc, never just set the var directly.
/// A mob's stat: set_stat() is its setter and raises CHANGE_MOB_STAT on a real change.
SETTER(/mob, stat)

/mob/proc/set_stat(new_stat)
	. = (stat != new_stat)
	stat = new_stat
	if(.)
		changed(src, CHANGE_MOB_STAT)
		PUBLISH_CHANGE(src, nameof(stat))

/mob/verb/face_direction()

	set name = "Face Direction"
	set category = VERB_CAT_IC_GAME
	set src = usr

	set_face_dir()

	if(!facing_dir)
		to_chat(src, span_filter_notice("You are now not facing anything."))
	else
		to_chat(src, span_filter_notice("You are now facing [dir2text(facing_dir)]."))

/mob/proc/set_face_dir(newdir)
	if(newdir == facing_dir)
		facing_dir = null
	else if(newdir)
		set_dir(newdir)
		facing_dir = newdir
	else if(facing_dir)
		facing_dir = null
	else
		set_dir(dir)
		facing_dir = dir

/mob/set_dir()
	if(facing_dir)
		if(!canface() || lying || src?.buckled_to() || restrained())
			facing_dir = null
		else if(dir != facing_dir)
			return ..(facing_dir)
	else
		return ..()

/mob/verb/northfaceperm()
	set hidden = 1
	set_face_dir(client.client_dir(NORTH))

/mob/verb/southfaceperm()
	set hidden = 1
	set_face_dir(client.client_dir(SOUTH))

/mob/verb/eastfaceperm()
	set hidden = 1
	set_face_dir(client.client_dir(EAST))

/mob/verb/westfaceperm()
	set hidden = 1
	set_face_dir(client.client_dir(WEST))

// Begin VOREstation edit
/mob/verb/shiftnorth()
	set hidden = TRUE
	if(!canface())
		return FALSE
	if(pixel_y <= (default_pixel_y + 16))
		pixel_y++
		is_shifted = TRUE

/mob/verb/shiftsouth()
	set hidden = TRUE
	if(!canface())
		return FALSE
	if(pixel_y >= (default_pixel_y - 16))
		pixel_y--
		is_shifted = TRUE

/mob/verb/shiftwest()
	set hidden = TRUE
	if(!canface())
		return FALSE
	if(pixel_x >= (default_pixel_x - 16))
		pixel_x--
		is_shifted = TRUE

/mob/verb/shifteast()
	set hidden = TRUE
	if(!canface())
		return FALSE
	if(pixel_x <= (default_pixel_x + 16))
		pixel_x++
		is_shifted = TRUE

/mob/verb/planeup()
	set hidden = TRUE
	if(!canface())
		return FALSE
	if(plane >= MOB_PLANE + 3)	//Don't bother going too high!
		return
	if(layer == MOB_LAYER)	//Become higher
		layer = ABOVE_MOB_LAYER
	plane += 1		//Increase the plane
	if(plane == MOB_PLANE)	//Return to normal
		layer = MOB_LAYER
	is_shifted = TRUE

/mob/verb/planedown()
	set hidden = TRUE
	if(!canface())
		return FALSE
	if(plane <= MOB_PLANE - 3)	//Don't bother going too low!
		return
	if(layer == MOB_LAYER)	//Become lower
		layer = BELOW_MOB_LAYER
	plane -= 1		//Decrease the plane
	if(plane == MOB_PLANE)	//Return to normal
		layer = MOB_LAYER
	is_shifted = TRUE

// End VOREstation edit

/mob/proc/adjustEarDamage()
	return

/mob/proc/setEarDamage()
	return

// Set client view distance (size of client's screen). Returns TRUE if anything changed.
/mob/proc/set_viewsize(new_view = world.view)
	if (client && new_view != client.view)
		client.view = new_view
		client.attempt_auto_fit_viewport()
		return TRUE
	return FALSE

//Throwing stuff

/mob/proc/toggle_throw_mode()
	if (in_throw_mode)
		throw_mode_off()
	else
		throw_mode_on()

/mob/proc/throw_mode_off()
	in_throw_mode = 0
	if(throw_icon && !issilicon(src)) //in case we don't have the HUD and we use the hotkey. Silicon use this for something else. Do not overwrite their HUD icon
		throw_icon.icon_state = "act_throw_off"

/mob/proc/throw_mode_on()
	in_throw_mode = 1
	if(throw_icon && !issilicon(src)) // Silicon use this for something else. Do not overwrite their HUD icon
		throw_icon.icon_state = "act_throw_on"

/mob/verb/spacebar_throw_on()
	set name = ".throwon"
	set hidden = TRUE
	set instant = TRUE
	throw_mode_on()

/mob/verb/spacebar_throw_off()
	set name = ".throwoff"
	set hidden = TRUE
	set instant = TRUE
	throw_mode_off()

/mob/proc/is_muzzled()
	return 0

/mob/proc/amend_exploitable(obj/item/I)
	if(istype(I))
		rel_add(src, nameof(exploit_addons), I) // pair: sets I.exploit_for too
		var/exploitmsg = html_decode("\n" + "Has " + I.name + ".")
		exploit_record += exploitmsg

/client/proc/check_has_body_select()
	return mob && mob.hud_used && istype(mob.zone_sel, /atom/movable/screen/zone_sel)

/client/verb/body_toggle_head()
	set name = "body-toggle-head"
	set hidden = 1
	toggle_zone_sel(list(BP_HEAD, O_EYES, O_MOUTH))

/client/verb/body_r_arm()
	set name = "body-r-arm"
	set hidden = 1
	toggle_zone_sel(list(BP_R_ARM,BP_R_HAND))

/client/verb/body_l_arm()
	set name = "body-l-arm"
	set hidden = 1
	toggle_zone_sel(list(BP_L_ARM,BP_L_HAND))

/client/verb/body_chest()
	set name = "body-chest"
	set hidden = 1
	toggle_zone_sel(list(BP_TORSO))

/client/verb/body_groin()
	set name = "body-groin"
	set hidden = 1
	toggle_zone_sel(list(BP_GROIN))

/client/verb/body_r_leg()
	set name = "body-r-leg"
	set hidden = 1
	toggle_zone_sel(list(BP_R_LEG,BP_R_FOOT))

/client/verb/body_l_leg()
	set name = "body-l-leg"
	set hidden = 1
	toggle_zone_sel(list(BP_L_LEG,BP_L_FOOT))

/client/proc/toggle_zone_sel(list/zones)
	if(!check_has_body_select())
		return
	var/atom/movable/screen/zone_sel/selector = mob.zone_sel
	selector.set_selected_zone(next_in_list(mob.zone_sel.selecting,zones))

// This handles setting the client's color variable, which makes everything look a specific color.
// This proc is here so it can be called without needing to check if the client exists, or if the client relogs.
// This is for inheritence since /mob/living will serve most cases. If you need ghosts to use this you'll have to implement that yourself.
/mob/proc/update_client_color()
	if(client && client.color)
		animate(client, color = get_location_color_tint(), time = 10)
	return

/mob/proc/get_location_color_tint()
	PROTECTED_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	var/turf/T = get_turf(src)
	var/area/A = get_area(src)
	if(!T || !A)
		return null
	if(T.is_outdoors()) // check weather
		var/datum/planet/P = LAZYACCESS(SSplanets.z_to_planet, T.z)
		var/weather_tint = P?.weather_holder.current_weather.get_color_tint()
		if(weather_tint) // But not if the weather has no blending!
			return weather_tint
	// If not weather based then just area's
	return A.get_color_tint()

/mob/proc/swap_hand()
	return

//Throwing stuff
/// Throws the active item at target; `stance` is the thrower's input stance (the adapter reads it): in help, next to a person, it hands the item over instead.
/mob/proc/throw_item(atom/target, stance = I_HURT)
	return FALSE

/mob/proc/will_show_tooltip()
	if(alpha <= EFFECTIVE_INVIS)
		return FALSE
	return TRUE

/// The native mouse-over's actor (hover(), code/engine/lifeforms/input.dm): a hovered mob shows its nametag tooltip.
/mob/proc/hover_input(datum/act/input/A)
	if(A.entered)
		show_mob_hover_tip(A.actor, A.params)
	return INPUT_FALLTHROUGH

/mob/proc/show_mob_hover_tip(mob/user, params)
	if(user != src && will_show_tooltip())
		if(user?.read_preference(/datum/preference/toggle/mob_tooltips))
			openToolTip(user, src, params, title = get_nametag_name(user), content = get_nametag_desc(user))

/mob/MouseDown()
	closeToolTip(usr, src) //No reason not to, really
	. = ..()

/mob/MouseExited()
	closeToolTip(usr, src) //No reason not to, really
	. = ..()

// Manages a global list of mobs with clients attached, indexed by z-level.
/mob/proc/update_client_z(new_z) // +1 to register, null to unregister.
	if(registered_z != new_z)
		if(registered_z)
			GLOB.players_by_zlevel[registered_z] -= src
		if(client)
			if(new_z)
				GLOB.players_by_zlevel[new_z] += src
			registered_z = new_z
		else
			registered_z = null

GLOBAL_LIST_EMPTY_TYPED(living_players_by_zlevel, /list)
/mob/living/update_client_z(new_z)
	var/precall_reg_z = registered_z
	. = ..() // will update registered_z if necessary
	if(precall_reg_z != registered_z) // parent did work, let's do work too
		if(precall_reg_z)
			GLOB.living_players_by_zlevel[precall_reg_z] -= src
			life_z_occupancy_changed(precall_reg_z)
		if(registered_z)
			GLOB.living_players_by_zlevel[registered_z] += src
			life_z_occupancy_changed(registered_z)

/mob/onTransitZ(old_z, new_z)
	..()
	update_client_z(new_z)

/mob/cloak()
	. = ..()
	if(client && dq_get_cloaked_selfimage(src))
		client.images += dq_get_cloaked_selfimage(src)

/mob/uncloak()
	if(client && dq_get_cloaked_selfimage(src))
		client.images -= dq_get_cloaked_selfimage(src)
	return ..()

/mob/get_cloaked_selfimage()
	var/icon/selficon = getCompoundIcon(src)
	selficon.MapColors(0,0,0, 0,0,0, 0,0,0, 1,1,1) //White
	var/image/selfimage = image(selficon)
	selfimage.color = "#0000FF"
	selfimage.alpha = 100
	selfimage.layer = initial(layer)
	selfimage.plane = initial(plane)
	image_anchor(selfimage, src)

	return selfimage

/mob/proc/GetAltName()
	return ""

/mob/proc/get_ghost(even_if_they_cant_reenter = 0)
	if(mind)
		return mind.get_ghost(even_if_they_cant_reenter)

/mob/proc/grab_ghost(force)
	if(mind)
		return mind.grab_ghost(force = force)

/mob/is_incorporeal()
	if(incorporeal_move) // ALLOW(reads): a requirement asks whether the actor is a ghost-like mover when a button is pressed, never from a cached menu
		return 1
	return ..()

/**
 * Get the mob VV dropdown extras
 */
/mob/vv_get_dropdown()
	. = ..()
	VV_DROPDOWN_OPTION("", "---------")
	VV_DROPDOWN_OPTION(VV_HK_GIB, "Gib")
	VV_DROPDOWN_OPTION(VV_HK_GIVE_AI, "Give AI Controller")
	VV_DROPDOWN_OPTION(VV_HK_GIVE_SPELL, "Give Spell")
	VV_DROPDOWN_OPTION(VV_HK_REMOVE_SPELL, "Remove Spell")
	VV_DROPDOWN_OPTION(VV_HK_GIVE_MODIFIER, "Give Modifier")
	VV_DROPDOWN_OPTION(VV_HK_ADDLANGUAGE, "Add Language")
	VV_DROPDOWN_OPTION(VV_HK_REMOVELANGUAGE, "Remove Language")
	VV_DROPDOWN_OPTION(VV_HK_ADDVERB, "Add Verb")
	VV_DROPDOWN_OPTION(VV_HK_REMOVEVERB, "Remove Verb")
	VV_DROPDOWN_OPTION(VV_HK_ADDORGAN, "Add Organ")
	VV_DROPDOWN_OPTION(VV_HK_REMOVEORGAN, "Remove Organ")
	VV_DROPDOWN_OPTION(VV_HK_GODMODE, "Toggle Godmode")
	VV_DROPDOWN_OPTION(VV_HK_DROP_ALL, "Drop Everything")
	VV_DROPDOWN_OPTION(VV_HK_REGEN_ICONS, "Regenerate Icons")
	VV_DROPDOWN_OPTION(VV_HK_REGEN_ICONS_FULL, "Regenerate Icons & Clear Stuck Overlays")
	VV_DROPDOWN_OPTION(VV_HK_PLAYER_PANEL, "Show player panel")
	VV_DROPDOWN_OPTION(VV_HK_BUILDMODE, "Toggle Buildmode")
	VV_DROPDOWN_OPTION(VV_HK_DIRECT_CONTROL, "Assume Direct Control")

/// A variable-edit choice needing +SPAWN.
/datum/prompt/choice/vv_spawn
	timeout = 0
	rights = R_SPAWN

/datum/prompt/choice/vv_spawn/recheck_extra()
	if(isdatum(value))
		var/datum/selected = value
		if(QDELETED(selected))
			return "gone"

/// A variable-edit choice needing +DEBUG.
/datum/prompt/choice/vv_debug
	timeout = 0
	rights = R_DEBUG

/datum/prompt/text/vv_ai_faction
	title = "AI faction"
	question = "Please input AI faction"
	default = "neutral"
	timeout = 0
	rights = R_HOLDER
	recheck_on_open = TRUE

/datum/prompt/choice/vv_ai_stance
	title = "AI combat mode"
	question = "Please choose AI combat mode"
	choices = list(I_HURT, I_HELP)
	timeout = 0
	rights = R_HOLDER
	recheck_on_open = TRUE

/datum/prompt/choice/vv_ai_wake
	title = "Wake mob?"
	question = "Make mob wake up? This is needed for carbon mobs."
	choices = list("Yes", "No")
	buttons = TRUE
	timeout = 0
	rights = R_HOLDER
	recheck_on_open = TRUE

/mob/proc/vv_language_added_apply(datum/act/op/A)
	var/mob/user = A.actor
	var/new_language = A.step_value("language")
	if(add_language(new_language))
		to_chat(user, "Added [new_language] to [src].")
		return
	to_chat(user, "Mob already knows that language.")

/mob/proc/vv_language_removed_apply(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/language/rem_language = A.step_value("language")
	if(remove_language(rem_language.name))
		to_chat(user, "Removed [rem_language] from [src].")
		return
	to_chat(user, "Mob doesn't know that language.")

/mob/proc/vv_verb_added_apply(datum/act/op/A)
	var/verb = A.step_value("verb")
	if(verb != "Cancel")
		// An admin's hand edit: lifts that admin hand's hide, grants from the admin source.
		revoke(src, granted_verb(verb, hidden = TRUE), verb_source(VERB_SOURCE_ADMIN))
		grant(src, granted_verb(verb), verb_source(VERB_SOURCE_ADMIN))

/mob/proc/vv_verb_removed_apply(datum/act/op/A)
	var/verb_name = A.step_value("verb")
	// Hidden, not revoked: the verb goes whatever grants it (the type, other sources).
	revoke(src, granted_verb(verb_name), verb_source(VERB_SOURCE_ADMIN))
	grant(src, granted_verb(verb_name, hidden = TRUE), verb_source(VERB_SOURCE_ADMIN))

/mob/proc/vv_organ_added_apply(datum/act/op/A)
	var/mob/user = A.actor
	var/new_organ = A.step_value("organ")
	var/mob/living/carbon/M = src
	if(locate_in_list(M.internal_organ_list(), new_organ))
		to_chat(user, "Mob already has that organ.")
		return
	new new_organ(M)

/mob/proc/vv_organ_removed_apply(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/organ/rem_organ = A.step_value("organ")
	var/mob/living/carbon/M = src
	if(!(locate_in_list(M.internal_organ_list(), rem_organ)))
		to_chat(user, "Mob does not have that organ.")
		return
	to_chat(user, "Removed [rem_organ] from [M].")
	rem_organ.removed()
	spent(rem_organ, src)


/mob/proc/vv_topic_regen_icons(datum/act/op/A)
	regenerate_icons()
	return TRUE

/mob/proc/vv_topic_regen_icons_full(datum/act/op/A)
	cut_overlays()
	regenerate_icons()
	return TRUE

/mob/proc/vv_topic_player_panel(datum/act/op/A)
	var/mob/user = A.actor
	SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/show_player_panel, src)
	return TRUE

/mob/proc/vv_topic_godmode(datum/act/op/A)
	var/mob/user = A.actor
	SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/cmd_admin_godmode, src)
	return TRUE

/// The choices of the VV language questions.
/mob/proc/vv_language_choices(datum/act/op/A)
	return GLOB.all_languages

/mob/proc/vv_known_language_choices(datum/act/op/A)
	return languages



/// The choices of the VV verb questions.
/mob/proc/vv_verb_choices(datum/act/op/A)
	return vv_addable_verbs(src)

/mob/proc/vv_current_verb_choices(datum/act/op/A)
	return verbs

/// The verbs VV can add to `H` (a global proc: typesof(/mob/proc) inside a /mob proc is a cross-reference loop).
/proc/vv_addable_verbs(mob/H)
	var/list/possibleverbs = list()
	possibleverbs += "Cancel" 								// One for the top...
	possibleverbs += typesof(/mob/proc, /mob/verb)
	if(isobserver(H))
		possibleverbs += typesof(/mob/observer/dead/proc,/mob/observer/dead/verb)
	if(isliving(H))
		possibleverbs += typesof(/mob/living/proc,/mob/living/verb)
	if(ishuman(H))
		possibleverbs += typesof(/mob/living/carbon/proc,/mob/living/carbon/verb,/mob/living/carbon/human/verb,/mob/living/carbon/human/proc)
	if(isrobot(H))
		possibleverbs += typesof(/mob/living/silicon/proc,/mob/living/silicon/robot/proc,/mob/living/silicon/robot/verb)
	if(isAI(H))
		possibleverbs += typesof(/mob/living/silicon/proc,/mob/living/silicon/ai/proc,/mob/living/silicon/ai/verb)
	if(isanimal(H))
		possibleverbs += typesof(/mob/living/simple_mob/proc)
	possibleverbs -= H.verbs
	possibleverbs += "Cancel" 								// ...And one for the bottom

	return possibleverbs

/// The choices of the VV organ questions.
/mob/living/carbon/proc/vv_organ_type_choices(datum/act/op/A)
	return subtypesof(/obj/item/organ)

/mob/living/carbon/proc/vv_organ_choices(datum/act/op/A)
	return internal_organ_list()

MSG_DEF_SELF(vv/player_mob, "This cannot be used on player mobs!")
MSG_DEF_SELF(vv/no_languages, "This mob knows no languages.")

/// Requirement: nobody drives the mob by remote control (its teleop is a relation view: null once that is gone).
/mob/proc/vv_not_remote_driven(datum/act/op/A)
	return !teleop

/// A VV AI brain setup, after the faction, the combat mode and the wake question have all been answered.
/mob/living/proc/vv_topic_give_ai(datum/act/op/A)
	if(ai_brain)	//Cleaning up the original ai
		rel_clear(src, nameof(ai_brain))
	initialize_ai_brain()
	if(!ai_brain)
		return
	faction = A.step_value("faction")
	var/stance = A.step_value("stance")
	if(stance)
		set_use_stance(stance)
	if(A.step_value("wake") == "Yes")
		status_adjust(STAT_SLEEPING, -100)

/mob/proc/vv_topic_give_spell(datum/act/op/A)
	var/mob/user = A.actor
	SSadmin_verbs.dynamic_invoke_verb(user, /datum/admin_verb/give_spell, src)
	return TRUE

/mob/proc/vv_topic_remove_spell(datum/act/op/A)
	var/mob/user = A.actor
	SSadmin_verbs.dynamic_invoke_verb(user, /datum/admin_verb/remove_spell, src)
	return TRUE

/mob/proc/vv_topic_give_modifier(datum/act/op/A)
	var/mob/user = A.actor
	SSadmin_verbs.dynamic_invoke_verb(user, /datum/admin_verb/admin_give_modifier, src)
	return TRUE

/mob/proc/vv_topic_gib(datum/act/op/A)
	var/mob/user = A.actor
	SSadmin_verbs.dynamic_invoke_verb(user, /datum/admin_verb/gib_them, src)
	return TRUE

/mob/proc/vv_topic_buildmode(datum/act/op/A)
	togglebuildmode(src)
	return TRUE

/mob/proc/vv_topic_drop_all(datum/act/op/A)
	var/mob/user = A.actor
	SSadmin_verbs.dynamic_invoke_verb(user, /datum/admin_verb/drop_everything, src)
	return TRUE

/mob/proc/vv_topic_direct_control(datum/act/op/A)
	var/mob/user = A.actor
	SSadmin_verbs.dynamic_invoke_verb(user, /datum/admin_verb/cmd_assume_direct_control, src)
	return TRUE


/**
 * extra var handling for the logging var
 */
/mob/vv_get_var(var_name)
	//switch(var_name)
	//	if(NAMEOF(src, logging))
	//		return debug_variable(var_name, logging, 0, src, FALSE)
	. = ..()

/obj/item
	var/tmp/user_vars_to_edit //fun times :3 - pretty much just grabbed from tg immabehonest - list(variable_name = variable_value) eg list("name" = "Wizardly Wizard", "real_name" = "Wizardly Wizard")
	var/tmp/user_vars_remembered //not needed for manual editing, just stores the original vars from the above list to make sure they go back to normal later

/obj/item/dropped(mob/living/user)
	. = ..()
	if (!istype(user))
		return
	if(LAZYLEN(user_vars_remembered))
		for(var/variable in user_vars_remembered)
			if(variable in user.vars)
				if(user.vars[variable] == user_vars_to_edit[variable])
					user.vars[variable] = user_vars_remembered[variable] // ALLOW(api): remembered user vars restored by name (admin possession)
		user_vars_remembered = initial(user_vars_remembered)

/obj/item/equipped(mob/living/user, slot_equipped)
	. = ..()
	if (!istype(user))
		return
	if(dq_item_fits_slot_flags(src, slot_equipped))
		if (LAZYLEN(user_vars_to_edit))
			for(var/variable in user_vars_to_edit)
				if(variable in user.vars)
					LAZYSET(user_vars_remembered, variable, user.vars[variable])
					user.vv_edit_var(variable, user_vars_to_edit[variable])
	else
		if(LAZYLEN(user_vars_remembered))
			for(var/variable in user_vars_remembered)
				if(variable in user.vars)
					if(user.vars[variable] == user_vars_to_edit[variable])
						user.vars[variable] = user_vars_remembered[variable] // ALLOW(api): remembered user vars restored by name (admin possession)
			user_vars_remembered = initial(user_vars_remembered)
