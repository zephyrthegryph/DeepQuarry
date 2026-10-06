/obj/soulgem
	name = "Mind imprintation matrix"
	desc = "A mind storage and processing system capable of capturing and supporting human-level minds in a small VR space."
	var/tmp/mob/living/owner
	var/tmp/datum/own_mind
	var/obj/belly/linked_belly
	var/tmp/taken_over_name

	var/setting_flags = (NIF_SC_ALLOW_EARS|NIF_SC_ALLOW_EYES|NIF_SC_BACKUPS|NIF_SC_PROJECTING)
	var/tmp/mob/selected_soul
	var/tmp/list/brainmobs = list() // ALLOW(instance_list): d: soulgem occupants, edited in place through many paths
	var/inside_flavor = "A small completely white room with a couch, and a window to what seems to be the outside world. A small sign in the corner says 'Configure Me'."
	var/capture_message = "Your vision fades in a haze of static, before returning.\nAround you, you see...\n"
	var/transit_message = "Your surroundings change to..."
	var/release_message = "Release Message"
	var/transfer_message = "Transfer Message"
	var/delete_message = "Delete Message"

CAPABILITIES(/obj/soulgem)
	owns_many(nameof(brainmobs))

// The soulgem's saved state is its saved vars (see code/datums/state/schema.dm);
// the linked belly (a relation view) is saved as the belly's name.
/obj/soulgem/state_codecs()
	return ..() + list("linked_belly" = /datum/state_codec/soulgem_belly)

// v2 saved the linked belly as "linked_belly_handle" (LC-refs); v3 is back to "linked_belly"
// (a relation view). v1 and pre-L1 legacy blobs already carry it as "linked_belly".
/obj/soulgem
	state_version = 3

/obj/soulgem/state_migrate(list/saved, from_version)
	..()
	if(from_version == 2 && ("linked_belly_handle" in saved))
		saved["linked_belly"] = saved["linked_belly_handle"]
		saved -= "linked_belly_handle"

// ALLOW(init/INSTANCE_STATE): binds to the mob it is made inside
/obj/soulgem/Initialize(mapload)
	. = ..()
	if(ismob(loc))
		rel_set(src, nameof(owner), loc)

/// Saves the linked belly by name, and relinks it to the owner's belly of that name.
/datum/state_codec/soulgem_belly

/datum/state_codec/soulgem_belly/encode(datum/owner, var_name, value, datum/state_context/ctx)
	var/obj/belly/belly = value
	return istype(belly) ? belly.name : null

/datum/state_codec/soulgem_belly/decode(datum/owner, var_name, encoded, datum/state_context/ctx)
	var/obj/soulgem/gem = owner
	if(gem.apply_stored_belly(encoded, TRUE))
		return
	rel_clear(gem, nameof(gem.linked_belly))
	gem.owner()?.recalculate_vis()

/obj/soulgem/proc/apply_stored_belly(belly_string, skip_unreg = FALSE)
	for(var/obj/belly in owner().vore_organs)
		if(belly.name == belly_string)
			update_linked_belly(belly, TRUE)
			return TRUE
	return FALSE

// Allows to transfer the soulgem to the given mob
/obj/soulgem/proc/transfer_self(mob/target)
	own_clear(target, nameof(/mob::soulgem), OWN_DELETE)
	var/mob/living/old_owner = owner()
	forceMove(target)
	rel_set(src, nameof(owner), target)
	if(old_owner && old_owner.soulgem == src)
		rel_move(old_owner, nameof(old_owner.soulgem), target, nameof(/mob::soulgem))
	else
		rel_set(target, nameof(/mob::soulgem), src)

// Cleaning up our refs before deletion

// Sends messages to the owner of the soulcatcher
/obj/soulgem/proc/notify_holder(message)
	message = span_nif(span_bold("[name]") + " displays, \"" + span_notice("[message]") + "\"")
	to_chat(owner(), message)

	for(var/mob/living/carbon/brain/caught_soul/CS as anything in brainmobs)
		to_chat(CS, message)

// Forwards the speech of captured souls
/obj/soulgem/proc/use_speech(message, mob/living/sender, mob/eyeobj, whisper)
	var/sender_name = eyeobj ? eyeobj.name : sender.name

	//AR Projecting
	if(eyeobj)
		var/speak_verb = "says"
		message = span_game(span_say(span_bold("[sender_name]") + " [speak_verb], \"[message]\""))
		if(whisper)
			speak_verb = "whispers"
			eyeobj.visible_message(span_italics(message), range = 1)
		else
			eyeobj.visible_message(message)

	//Not AR Projecting
	else
		var/speak_verb = "speaks"
		message = span_nif(span_bold("\[SC\] [sender_name]") + " [speak_verb], \"[message]\"")
		to_chat(owner(), message)
		if(whisper)
			speak_verb = "whispers"
			to_chat(sender, span_italics(message))
		else
			for(var/mob/living/carbon/brain/caught_soul/CS as anything in brainmobs)
				to_chat(CS, message)

	sender.log_talk("NSAY (SC:[owner().real_name]): [message]", LOG_SAY, color="#ff006f")

// Forwards the emotes of captured souls
/obj/soulgem/proc/use_emote(message, mob/living/sender, mob/eyeobj, whisper)
	var/sender_name = eyeobj ? eyeobj.name : sender.name

	//AR Projecting
	if(eyeobj)
		message = span_emote("[sender_name] [message]")
		if(whisper)
			eyeobj.visible_message(span_italics(message), range = 1)
		else
			eyeobj.visible_message(message)
	//Not AR Projecting
	else
		message = span_nif(span_bold("[sender_name]") + " [message]")
		to_chat(owner(), message)
		if(whisper)
			to_chat(sender, span_italics(message))
		else
			for(var/mob/living/carbon/brain/caught_soul/CS as anything in brainmobs)
				to_chat(CS, message)

	sender.log_message("NME (SC:[owner().real_name]): [message]", LOG_EMOTE, color="#ff006f")

// The capture function which transfers the given mob's mind into the soulcatcher
/obj/soulgem/proc/catch_mob(mob/M, custom_name)
	if(!(M.soulcatcher_pref_flags & SOULCATCHER_ALLOW_CAPTURE) && !isobserver(M)) return // Bypass pref check for observer join
	if(!M.mind)	return
	if(isbrain(owner())) return
	//Create a new brain mob
	var/mob/living/carbon/brain/caught_soul/vore/brainmob = new(src)
	rel_set(brainmob, nameof(brainmob.gem), src)
	rel_set(brainmob, nameof(brainmob.container), src)
	brainmob.status_set(STAT_MUTED, 0)
	brainmob.ext_deaf = !flag_check(NIF_SC_ALLOW_EARS)
	brainmob.ext_blind = !flag_check(NIF_SC_ALLOW_EYES)
	brainmob.add_language(LANGUAGE_GALCOM)
	rel_add(src, nameof(brainmobs), brainmob)

	//Put the mind and player into the mob
	transfer_mind(M.mind, brainmob, "caught in [src]") // identity (name, DNA, OOC notes) comes by reference
	brainmob.name = custom_name ? custom_name : brainmob.mind.name
	brainmob.real_name = custom_name ? custom_name : brainmob.mind.name

	//If we caught our owner, special settings.
	if(M == owner() && !own_mind()) // Need some more sanity if we allow takeover
		brainmob.ext_deaf = FALSE
		brainmob.ext_blind = FALSE
		brainmob.parent_mob = TRUE
		rel_set(src, nameof(own_mind), brainmob.mind)
		grant(brainmob, granted_verb(/mob/proc/enter_soulcatcher, hidden = TRUE), brainmob) //No recursive self capturing...
		grant(brainmob, granted_verb(/mob/living/carbon/brain/caught_soul/vore/proc/transfer_self), brainmob)
		grant(brainmob, granted_verb(/mob/living/carbon/brain/caught_soul/vore/proc/reenter_body), brainmob)

	if(isliving(M))
		if(ishuman(M))
			SStranscore.m_backup(brainmob.mind,0) //It does ONE, so medical will hear about it.

	//Else maybe they're a joining ghost
	else if(isobserver(M))
		brainmob.transient = TRUE
		spent(M) //Bye ghost

	//Give them a flavortext message
	var/message = span_notice("[capture_message][inside_flavor]")

	to_chat(brainmob, message)

	//Reminder on how this works to host
	if(length(brainmobs) == 1) //Only spam this on the first one
		to_chat(owner(), span_notice("Your occupant's messages/actions can only be seen by you, and you can \
		send messages that only they can hear/see by using the NSay and NMe verbs (or the *nsay and *nme emotes)."))

	//Announce to host and other minds
	notify_holder("New mind loaded: [brainmob.name]")
	show_vore_fx(brainmob)
	brainmob.copy_from_prefs_vr(bellies = FALSE)
	return TRUE

// Allows to adjust the interior of the soulcatcher
/obj/soulgem/proc/adjust_interior(new_flavor)
	new_flavor = sanitize(new_flavor, VORE_SC_DESC_MAX, FALSE, TRUE, FALSE)
	inside_flavor = new_flavor
	notify_holder("Updating environment...")
	for(var/mob/living/carbon/brain/caught_soul/vore/CS as anything in brainmobs)
		to_chat(CS, span_notice("[transit_message]") + "\n[inside_flavor]")

// Allows to return to the body after being captured by one's own soulcatcher
/obj/soulgem/proc/return_to_body(datum/mind)
	if(own_mind() != mind)
		to_chat(src, span_warning("You aren't in your own soulcatcher!"))
		return
	var/mob/self = null
	for(var/mob/mob in brainmobs)
		if(mob.mind == mind)
			self = mob
			break
	if(!self)
		return
	if(owner().mind)
		catch_mob(owner(), taken_over_name)
	self.mind.transfer_to(owner())
	rel_clear(src, nameof(own_mind))
	taken_over_name = null
	spent(self)

// Sets the custom messages depending on the input
/obj/soulgem/proc/set_custom_message(message, target)
	message = sanitize(message, VORE_SC_MAX, FALSE, TRUE, FALSE)
	switch(target)
		if(SC_CAPTURE_MEESAGE)
			capture_message = message
		if(SC_TRANSIT_MESSAGE)
			transit_message = message
		if(SC_RELEASE_MESSAGE)
			release_message = message
		if(SC_TRANSFERE_MESSAGE)
			transfer_message = message
		if(SC_DELETE_MESSAGE)
			delete_message = message

// Allows to rename the soulgem
/obj/soulgem/proc/rename(new_name)
	if(length(new_name) < 3 || length(new_name) > 60)
		to_chat(owner(), span_warning("Your soulcatcher's name needs to be between 3 and 60 characters long!"))
		return FALSE
	new_name = sanitize(new_name, 60, FALSE, TRUE, FALSE)
	name = new_name
	return TRUE

// Toggles the given flag
/obj/soulgem/proc/toggle_setting(flag)
	setting_flags ^= flag
	if(flag & SOULGEM_SHOW_VORE_SFX)
		soulgem_show_vfx()
		soulgem_vfx()
	if(flag & NIF_SC_BACKUPS)
		soulgem_backup()
	if(flag & NIF_SC_ALLOW_EARS)
		soulgem_hear()
	if(flag & NIF_SC_ALLOW_EYES)
		soulgem_sight()
	if(flag & NIF_SC_PROJECTING)
		soulgem_projecting()
	if(flag & SOULGEM_SEE_SR_SOULS)
		owner().recalculate_vis()

// Checks a single flag, or if all combined flags are true
/obj/soulgem/proc/flag_check(flag, match_all = FALSE)
	if(match_all)
		return (setting_flags & flag) == flag
	return setting_flags & flag

// Updates the selected soul after an interaction which rleased, deleted or transferred the previous one
/obj/soulgem/proc/update_selected_soul()
	if(length(brainmobs) > 1)
		rel_set(src, nameof(selected_soul), brainmobs[1])
	else
		rel_clear(src, nameof(selected_soul))

// Backup toggling
/obj/soulgem/proc/soulgem_backup()
	if(flag_check(NIF_SC_BACKUPS))
		notify_holder("External backups enabled.")
	else
		notify_holder("External backups disabled.")

// Deaf toggling
/obj/soulgem/proc/soulgem_hear()
	for(var/mob/living/carbon/brain/caught_soul/L in brainmobs)
		L.ext_deaf = !flag_check(NIF_SC_ALLOW_EARS)
	if(flag_check(NIF_SC_ALLOW_EARS))
		notify_holder("External sounds enabled.")
	else
		notify_holder("External sounds disabled.")

// Sight toggling
/obj/soulgem/proc/soulgem_sight()
	for(var/mob/living/carbon/brain/caught_soul/L in brainmobs)
		L.ext_blind = !flag_check(NIF_SC_ALLOW_EYES)
	if(flag_check(NIF_SC_ALLOW_EYES))
		notify_holder("External vision enabled.")
	else
		notify_holder("External vision disabled.")

// Projecting toggling
/obj/soulgem/proc/soulgem_projecting()
	if(flag_check(NIF_SC_PROJECTING))
		notify_holder("AR projecting enabled.")
	else
		notify_holder("AR projecting disabled.")

// VORE FX Section

// Updates the vore FX signal links to the new given belly
/obj/soulgem/proc/update_linked_belly(obj/belly, skip_unreg = FALSE)
	if(!belly && linked_belly())
		unobserve(linked_belly(), /datum/notice/belly_update_vore_fx, src)
		rel_clear(src, nameof(linked_belly))
		return
	if(!isbelly(belly))
		return
	if(!linked_belly())
		rel_set(src, nameof(linked_belly), belly)
		observe(linked_belly(), /datum/notice/belly_update_vore_fx, src, then(PROC_REF(on_belly_vore_fx_event)))
		return
	if(belly != linked_belly())
		if(!skip_unreg)
			unobserve(linked_belly(), /datum/notice/belly_update_vore_fx, src)
		rel_set(src, nameof(linked_belly), belly)
		observe(linked_belly(), /datum/notice/belly_update_vore_fx, src, then(PROC_REF(on_belly_vore_fx_event)))

// Handles the vore fx updates for the captured souls
/// Event wrapper: the linked belly refreshed its vore fx.
/obj/soulgem/proc/on_belly_vore_fx_event(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/belly_update_vore_fx/event = N
	soulgem_show_vfx(event.volume)

/obj/soulgem/proc/soulgem_show_vfx(severity = 0)
	if(linked_belly())
		for(var/mob/living/L in brainmobs)
			if(flag_check(SOULGEM_SHOW_VORE_SFX))
				show_vore_fx(L, severity)
			else
				clear_vore_fx(L)

// Function to show the vore fx overlay
/obj/soulgem/proc/show_vore_fx(mob/living/L, severity = 0)
	if(!linked_belly() || !flag_check(SOULGEM_SHOW_VORE_SFX))
		return
	if(!istype(L) || L?.active_eye())
		return
	linked_belly().vore_fx(L, severity)

// Function to clear the vore fx overlay
/obj/soulgem/proc/clear_vore_fx(mob/M)
	M.clear_fullscreen("belly")
	M.belly_overlay_tgui?.hide() // hide TGUI belly overlay
	if(M.hud_used && !M.hud_used.hud_shown)
		M.toggle_hud_vis(TRUE)

// VFX toggling
/obj/soulgem/proc/soulgem_vfx()
	if(flag_check(SOULGEM_SHOW_VORE_SFX))
		notify_holder("Interior simulation enabled.")
	else
		notify_holder("Interior simulation disabled.")

// Takeover section

// Give control of the body to the current selected soul
/obj/soulgem/proc/take_control_selected()
	if(!selected_soul()) return
	take_control(selected_soul())
	if(owner().mind == own_mind())
		rel_clear(src, nameof(own_mind))
		taken_over_name = null

// Give back control of the body to the owner
/obj/soulgem/proc/take_control_owner()
	var/mob/self = null
	for(var/mob/mob in brainmobs)
		if(mob.mind == own_mind())
			self = mob
			break
	if(!self)
		return
	take_control(self)
	rel_clear(src, nameof(own_mind))
	taken_over_name = null

/obj/soulgem/proc/take_control(mob/M)
	if(!(owner().soulcatcher_pref_flags & SOULCATCHER_ALLOW_CAPTURE) || !(owner().soulcatcher_pref_flags & SOULCATCHER_ALLOW_TAKEOVER)) return
	if(!(M.soulcatcher_pref_flags & SOULCATCHER_ALLOW_CAPTURE) || !(M.soulcatcher_pref_flags & SOULCATCHER_ALLOW_TAKEOVER)) return
	if(!own_mind())
		if(issilicon(owner()) || isanimal(owner()))
			taken_over_name = owner().name
	catch_mob(owner(), taken_over_name)
	taken_over_name = M.name
	M.mind.transfer_to(owner())
	own_take_member(src, nameof(brainmobs), M)
	if(M == selected_soul())
		update_selected_soul()
	spent(M)

// Funtion to test if the owner's body has been taken over
/obj/soulgem/proc/is_taken_over()
	return (own_mind() && owner().mind && owner().mind != own_mind())

// Transfer section to transfer captured souls

// Returns nearby,valid transfer locations as a list
/obj/soulgem/proc/find_transfer_objects()
	var/list/valid_trasfer_objects = list(
		/obj/item/sleevemate,
		/obj/item/mmi
	)
	var/list/valid_objects = list()
	if(isrobot(owner()))
		var/mob/living/silicon/robot/R = owner()
		if(istype(R.module_active, /obj/item/sleevemate))
			valid_objects += R.module_active
	if(ishuman(owner()))
		var/mob/living/carbon/human/H = owner()
		if(is_type_in_list(H.get_left_hand(), valid_trasfer_objects))
			valid_objects += H.get_left_hand()
		if(is_type_in_list(H.get_right_hand(), valid_trasfer_objects))
			valid_objects += H.get_right_hand()
	for(var/obj/item/I in range(0, get_turf(owner())))
		if(is_type_in_list(I, valid_trasfer_objects))
			valid_objects += I
	for(var/mob/M in range(1, get_turf(owner())))
		if(M == owner())
			continue
		if(!(M.soulcatcher_pref_flags & SOULCATCHER_ALLOW_TRANSFER))
			continue
		if(M.client && M.soulgem)
			valid_objects += M.soulgem
	if(!valid_objects.len)
		to_chat(owner(), span_warning("No valid objects found!"))
		return
	return valid_objects

// Transfer the selected soul to either a valid object or another soulcatcher
/obj/soulgem/proc/transfer_selected()
	return soulgem_selected_stage()

/obj/soulgem/proc/soulgem_selected_stage(obj/selected_target, prompted = FALSE)
	if(!selected_soul()) return
	if(!(selected_soul().soulcatcher_pref_flags & SOULCATCHER_ALLOW_TRANSFER)) return
	var/list/valid_objects = find_transfer_objects()
	if(!valid_objects || !valid_objects.len)
		return
	if(!prompted)
		open_request(src, /datum/prompt/choice/soulgem_consent, PROC_REF(soulgem_selected_answered), answerer = owner(), question = "Select where you want to store the mind into.", title = "Mind Transfer Target", choices = valid_objects)
		return
	var/obj/target = selected_target
	if(isnull(target))
		return
	transfer_mob_selector(selected_soul(), target)

// Transfer selector proc
/obj/soulgem/proc/transfer_mob_selector(mob/M, obj/target)
	if(!M || !target) return
	if(istype(target, /obj/soulgem))
		transfer_mob_soulcatcher(M, target)
		return
	transfer_mob(M, target)

// Transfers a captured soul to a valid object (sleevemate, mmi)
/obj/soulgem/proc/transfer_mob(mob/M, obj/target)
	if(is_taken_over()) return
	if(!M || !target) return
	if(istype(target, /obj/item/sleevemate))
		var/obj/item/sleevemate/mate = target
		if(!mate.stored_mind())
			to_chat(owner(), span_notice("You scan yourself to transfer the soul into the [target]!"))
			to_chat(M, span_notice("[transfer_message]"))
			if(M.mind == own_mind())
				rel_clear(src, nameof(own_mind))
			mate.get_mind(M)
	else if(istype(target, /obj/item/mmi))
		var/obj/item/mmi/mm = target
		if(!mm.get_occupant()?.mind)
			if(M.mind == own_mind())
				rel_clear(src, nameof(own_mind))
			to_chat(owner(), span_notice("You transfer the soul into the [target]!"))
			to_chat(M, span_notice("[transfer_message]"))
			mm.take_identity(M, TRUE)
	else
		return
	own_take_member(src, nameof(brainmobs), M)
	if(M == selected_soul())
		update_selected_soul()
	consumed(M, src)

// Transfers a captured soul to another soulcatcher
/obj/soulgem/proc/transfer_mob_soulcatcher(mob/living/carbon/brain/caught_soul/vore/M, obj/soulgem/gem)
	return soulgem_transfer_stage(M, gem)

/obj/soulgem/proc/soulgem_transfer_stage(mob/living/carbon/brain/caught_soul/vore/M, obj/soulgem/gem, response, prompted = FALSE)
	if(is_taken_over()) return
	if(!istype(M) || !gem) return
	if(!gem.owner()) return
	if(!prompted)
		open_request(src, /datum/prompt/choice/soulgem_consent, PROC_REF(soulgem_transfer_answered), answerer = gem.owner(), soulgem_mob = M, soulgem_destination = gem, question = "Do you want to allow [owner()] to transfer [selected_soul()] to your soulcatcher?", title = "Allow Transfer", choices = list("No", "Yes"), buttons = TRUE)
		return
	var/_answer_a2 = response
	if(isnull(_answer_a2))
		return
	if((_answer_a2 != "Yes"))
		return
	if(!in_range(gem.owner(), owner()))
		return
	if(!(gem.owner().soulcatcher_pref_flags & SOULCATCHER_ALLOW_TRANSFER))
		return
	if(M.mind == own_mind())
		rel_clear(src, nameof(own_mind))
	own_take_member(src, nameof(brainmobs), M)
	rel_set(M, nameof(M.gem), gem)
	rel_set(M, nameof(M.container), gem)
	rel_add(gem, nameof(gem.brainmobs), M)
	if(M == selected_soul())
		update_selected_soul()

// Release section

// Release the selected soul as a ghost
/obj/soulgem/proc/release_selected()
	if(!selected_soul()) return
	if(release_mob(selected_soul()))
		update_selected_soul()

// Release all captured souls as ghosts
/obj/soulgem/proc/release_mobs()
	rel_clear(src, nameof(selected_soul))
	if(!length(brainmobs)) return
	for(var/mob/M in brainmobs)
		release_mob(M)

// Proc to release the soul as ghost, returns TRUE on success
/obj/soulgem/proc/release_mob(mob/M)
	if(is_taken_over()) return FALSE
	to_chat(M, span_notice("[release_message]"))
	own_take_member(src, nameof(brainmobs), M)
	M.ghostize(FALSE)
	spent(M)
	return TRUE

// Delete section to delete captured souls from the soulcatcher

// Delete the selected mob
/obj/soulgem/proc/delete_selected()
	if(!selected_soul()) return
	if(delete_mob(selected_soul()))
		update_selected_soul()

// Delete all captured mobs
/obj/soulgem/proc/erase_mobs()
	if(!length(brainmobs)) return
	for(var/mob/M in brainmobs)
		delete_mob(M)

// The function handling the actual delete, returns TRUE on success
/obj/soulgem/proc/delete_mob(mob/M)
	return soulgem_delete_stage(M)

/obj/soulgem/proc/soulgem_delete_stage(mob/M, response, prompted = FALSE)
	if(is_taken_over()) return FALSE
	if(!(M.soulcatcher_pref_flags & SOULCATCHER_ALLOW_DELETION))
		return release_mob(M)
	if(!(M.soulcatcher_pref_flags & SOULCATCHER_ALLOW_DELETION_INSTANT))
		if(!prompted)
			open_request(src, /datum/prompt/choice/soulgem_consent, PROC_REF(soulgem_delete_answered), answerer = M, soulgem_mob = M, question = "Do you really want to allow [owner()] to delete you? On decline, you'll be ghosted.", title = "Allow Deletion", choices = list("No", "Yes"), timeout = 1 MINUTES, buttons = TRUE)
			return
		var/_answer_a3 = response
		if(isnull(_answer_a3))
			return
		if(_answer_a3 != "Yes")
			return release_mob(M)
	to_chat(M, span_danger("[delete_message]"))
	own_take_member(src, nameof(brainmobs), M)
	var/mob/observer/dead/ghost = M.ghostize(FALSE)
	ghost.abandon_mob()
	spent(M)
	return TRUE

/// the own_mind this refers to (a relation view: null once it is deleted).
/obj/soulgem/proc/own_mind() as /datum
	return own_mind

/// the linked_belly this refers to (a relation view: null once it is deleted).
/obj/soulgem/proc/linked_belly() as /obj/belly
	return linked_belly

/// the selected_soul this refers to (a relation view: null once it is deleted).
/obj/soulgem/proc/selected_soul() as /mob
	return selected_soul

/// the owner this refers to (a relation view: null once it is deleted).
/obj/soulgem/proc/owner() as /mob/living
	return owner

/obj/soulgem/proc/soulgem_selected_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = soulgem_selected_apply(A)
	SStgui.update_uis(src)

/obj/soulgem/proc/soulgem_selected_apply(datum/act/request/A)
	var/datum/prompt/choice/soulgem_consent/ask = A.answer
	return soulgem_selected_stage(ask.value, TRUE)

/obj/soulgem/proc/soulgem_transfer_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = soulgem_transfer_apply(A)
	SStgui.update_uis(src)

/obj/soulgem/proc/soulgem_transfer_apply(datum/act/request/A)
	var/datum/prompt/choice/soulgem_consent/ask = A.answer
	return soulgem_transfer_stage(ask.soulgem_mob, ask.soulgem_destination, ask.value, TRUE)

/obj/soulgem/proc/soulgem_delete_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = soulgem_delete_apply(A)
	SStgui.update_uis(src)

/obj/soulgem/proc/soulgem_delete_apply(datum/act/request/A)
	var/datum/prompt/choice/soulgem_consent/ask = A.answer
	return soulgem_delete_stage(ask.soulgem_mob, ask.value, TRUE)

/datum/prompt/choice/soulgem_consent
	timeout = 0
	var/mob/soulgem_mob
	var/soulgem_mob_expected = FALSE
	var/obj/soulgem/soulgem_destination
	var/soulgem_destination_expected = FALSE

CAPABILITIES(/datum/prompt/choice/soulgem_consent)
	ref_one(nameof(soulgem_mob), /mob)
	ref_one(nameof(soulgem_destination), /obj/soulgem)

/datum/prompt/choice/soulgem_consent/prepare(datum/act/A)
	. = ..()
	var/mob/captured_mob = soulgem_mob
	soulgem_mob_expected = !isnull(captured_mob)
	rel_clear(src, nameof(soulgem_mob))
	if(captured_mob && !QDELETED(captured_mob))
		rel_set(src, nameof(soulgem_mob), captured_mob)
	var/obj/soulgem/captured_destination = soulgem_destination
	soulgem_destination_expected = !isnull(captured_destination)
	rel_clear(src, nameof(soulgem_destination))
	if(captured_destination && !QDELETED(captured_destination))
		rel_set(src, nameof(soulgem_destination), captured_destination)

/datum/prompt/choice/soulgem_consent/recheck_extra()
	if((soulgem_mob_expected && QDELETED(soulgem_mob)) || (soulgem_destination_expected && QDELETED(soulgem_destination)))
		return "gone"
	if(!isnull(value) && istype(value, /datum))
		var/datum/selected = value
		if(QDELETED(selected))
			return "gone"
