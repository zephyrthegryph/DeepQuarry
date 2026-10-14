/mob/living/carbon/brain/caught_soul/vore
	name = "stored soul"
	desc = "A soul stored within the predator."

	var/tmp/obj/soulgem/gem

CAPABILITIES(/mob/living/carbon/brain/caught_soul/vore)
	ref_one(nameof(gem), /obj/soulgem) // the gem that holds this soul: a view, cleared with the mob

// Cleaning up the refs during deletion
// its gem is told the mind unloaded.
/mob/living/carbon/brain/caught_soul/vore/on_destroy(force)
	var/mob/observer/eye/eyeobj = src?.active_eye()
	if(eyeobj)
		QDEL_NULL(eyeobj)
		gem()?.notify_holder("[name] ended SR projection.")
	if(gem())
		gem().notify_holder("Mind unloaded: [name]")
		gem().brainmobs -= src
	..() // the gem and container views are cleared with the mob (CAPABILITIES)

// Handling the automatic transcore backups in a set interval
/mob/living/carbon/brain/caught_soul/vore/life_type_post_due()
	return TRUE

/mob/living/carbon/brain/caught_soul/vore/life_type_post(datum/seq_frame/life/F)
	..()
	if(QDELETED(src))
		return

	if(!src.parent_mob && !src.transient &&(src.life_tick % 150 == 0) && src.gem().setting_flags & NIF_SC_BACKUPS)
		SStranscore.m_backup(src.mind,0) //Passed 0 means "Don't touch the nif fields on the mind record"

	if(!src.client)
		return

	if(src.ext_blind)
		src.status_set(STAT_BLINDED, 5)
		src.client.screen.Remove(GLOB.global_hud.whitense)
		src.overlay_fullscreen("blind", /atom/movable/screen/fullscreen/blind)
	else
		src.status_set(STAT_BLINDED, 0)
		src.clear_fullscreen("blind")
		if(!src.gem().flag_check(SOULGEM_SHOW_VORE_SFX))
			src.client.screen.Add(GLOB.global_hud.whitense)
	if(src.gem().flag_check(SOULGEM_SHOW_VORE_SFX))
		src.client.screen.Remove(GLOB.global_hud.whitense)

// Say proc for captures souls
/mob/living/carbon/brain/caught_soul/vore/say(message, datum/language/speaking = null, whispering = 0)
	var/mob/observer/eye/eyeobj = src?.active_eye()
	if(has_status(STAT_MUTED)) return FALSE
	gem().use_speech(message, src, eyeobj)

// Emote proc for captured souls
/mob/living/carbon/brain/caught_soul/vore/custom_emote(m_type, message)
	var/mob/observer/eye/eyeobj = src?.active_eye()
	if(has_status(STAT_MUTED)) return FALSE
	gem().use_emote(message,src,eyeobj)

/mob/living/carbon/brain/caught_soul/vore/me_verb_subtle(message as message)
	var/mob/observer/eye/eyeobj = src?.active_eye()
	if(has_status(STAT_MUTED)) return FALSE
	gem().use_emote(message,src,eyeobj,TRUE)

/mob/living/carbon/brain/caught_soul/vore/whisper(message as text)
	var/mob/observer/eye/eyeobj = src?.active_eye()
	if(has_status(STAT_MUTED)) return FALSE
	gem().use_speech(message,src,eyeobj,TRUE)

// Resist override, only returning a message that one is stuck for now
/mob/living/carbon/brain/caught_soul/vore/resist()
	set name = "Resist"
	set category = VERB_CAT_IC_GAME

	to_chat(src, span_warning("There's no way out! You're stuck inside your predator."))

// Allows the predator to enter their own soulcatcher
/mob/proc/enter_soulcatcher()
	set name = "Enter Soulcatcher"
	set desc = "Enter your own Soulcatcher."
	set category = VERB_CAT_IC_VORE

	if(!soulgem) // Only sanity...
		return
	if(soulgem && soulgem.flag_check(SOULGEM_ACTIVE))
		var/to_use_custom_name = null
		if(issilicon(src) || isanimal(src))
			to_use_custom_name = src.name
		soulgem.catch_mob(src, to_use_custom_name)

// Speak to the captured souls within the own soulcatcher
/mob/proc/nsay_vore(message as message)
	set name = "NSay Vore"
	set desc = "Speak into your Soulcatcher."

	src.nsay_vore_act(message)

/mob/proc/nsay_vore_ch()
	set name = "NSay Vore CH"
	set desc = "Speak into your Soulcatcher."
	set category = VERB_CAT_IC_VORE

	src.nsay_vore_act()

/mob/proc/nsay_vore_act(message)
	return gem_say_stage(message)

/mob/proc/gem_say_stage(message, prompted = FALSE)
	if(stat != CONSCIOUS)
		to_chat(src, span_warning("You can't use NSay Vore while unconscious."))
		return
	if(!soulgem) // Only sanity...
		return
	var/obj/soulgem/gem = soulgem
	if(!gem.brainmobs.len)
		to_chat(src, span_warning("You need a devoured soul to use NSay Vore."))
		return

	if(!message)
		if(!prompted)
			open_request(src, /datum/prompt/text/soulcatcher_speech, PROC_REF(gem_say_answered), answerer = src, question = "Type a message to say.", title = "Speak into Soulcatcher", multiline = TRUE, encode = FALSE, max_len = MAX_TGUI_INPUT)
			return
	if(message)
		var/sane_message = sanitize(message)
		gem.use_speech(sane_message, src)

// Emote to the captured souls within the soulcatcher
/mob/proc/nme_vore(message as message)
	set name = "NMe Vore"
	set desc = "Emote into your Soulcatcher."

	src.nme_vore_act(message)

/mob/proc/nme_vore_ch()
	set name = "NMe Vore CH"
	set desc = "Emote into your Soulcatcher."
	set category = VERB_CAT_IC_VORE

	src.nme_vore_act()

/mob/proc/nme_vore_act(message)
	return gem_emote_stage(message)

/mob/proc/gem_emote_stage(message, prompted = FALSE)
	if(stat != CONSCIOUS)
		to_chat(src, span_warning("You can't use NMe Vore while unconscious."))
		return
	if(!soulgem) // Only sanity...
		return
	var/obj/soulgem/gem = soulgem
	if(!gem.brainmobs.len)
		to_chat(src, span_warning("You need a devoured soul to use NMe Vore."))
		return

	if(!message)
		if(!prompted)
			open_request(src, /datum/prompt/text/soulcatcher_speech, PROC_REF(gem_emote_answered), answerer = src, question = "Type an action to perform.", title = "Emote into Soulcatcher", multiline = TRUE, encode = FALSE, max_len = MAX_TGUI_INPUT)
			return
	if(message)
		var/sane_message = sanitize(message)
		gem.use_emote(sane_message, src)

// SR projecting mob
/mob/observer/eye/ar_soul/vore
	plane = PLANE_SOULCATCHER

// SR project as captured soul
/mob/living/carbon/brain/caught_soul/vore/ar_project()
	var/mob/observer/eye/eyeobj = src?.active_eye()
	set name = "AR/SR Project"
	set desc = "Project your form into Augmented Reality for those around your predator with the appearance of your loaded character."
	set category = VERB_CAT_SOULCATCHER

	if(eyeobj)
		to_chat(src, span_warning("You're already projecting in SR!"))
		return

	if(!(gem().setting_flags & NIF_SC_PROJECTING))
		to_chat(src, span_warning("Projecting from this soulcatcher has been disabled!"))
		return

	if(!client || !client.prefs)
		return //Um...

	new /mob/observer/eye/ar_soul/vore(src, gem().owner()) // takes itself as our eye
	gem().notify_holder("[src] now SR projecting.")
	gem().clear_vore_fx(src)

// Jump to the owner as SR projection
/mob/living/carbon/brain/caught_soul/vore/jump_to_owner()
	var/mob/observer/eye/eyeobj = src?.active_eye()
	set name = "Jump to Owner"
	set desc = "Jump your projection back to the owner of the soulcatcher you're inside."
	set category = VERB_CAT_SOULCATCHER

	if(!eyeobj)
		to_chat(src, span_warning("You're not projecting into SR!"))
		return

	eyeobj.forceMove(get_turf(gem()))

// End SR projecting and return to the soulcatcher containing the soul
/mob/living/carbon/brain/caught_soul/vore/reenter_soulcatcher()
	var/mob/observer/eye/eyeobj = src?.active_eye()
	set name = "Re-enter Soulcatcher"
	set desc = "Leave SR projection and drop back into the soulcatcher."
	set category = VERB_CAT_SOULCATCHER

	if(!eyeobj)
		to_chat(src, span_warning("You're not projecting into SR!"))
		return

	QDEL_NULL(eyeobj)
	gem().notify_holder("[src] ended SR projection.")
	gem().show_vore_fx(src)

/mob/living/carbon/brain/caught_soul/vore/nsay_brain()
	set name = "NSay"
	set desc = "Speak to your Soulcatcher (circumventing SR speaking)."
	set category = VERB_CAT_SOULCATCHER

	return gem_brain_say_stage()

/mob/living/carbon/brain/caught_soul/vore/proc/gem_brain_say_stage(message, prompted = FALSE)
	if(!prompted)
		open_request(src, /datum/prompt/text/soulcatcher_speech, PROC_REF(gem_brain_say_answered), answerer = src, question = "Type a message to say.", title = "Speak into Soulcatcher", multiline = TRUE)
		return
	if(message)
		gem().use_speech(message, src)

/mob/living/carbon/brain/caught_soul/vore/nme_brain()
	set name = "NMe"
	set desc = "Emote to your Soulcatcher (circumventing SR speaking)."
	set category = VERB_CAT_SOULCATCHER

	return gem_brain_emote_stage()

/mob/living/carbon/brain/caught_soul/vore/proc/gem_brain_emote_stage(message, prompted = FALSE)
	if(!prompted)
		open_request(src, /datum/prompt/text/soulcatcher_speech, PROC_REF(gem_brain_emote_answered), answerer = src, question = "Type an action to perform.", title = "Emote into Soulcatcher", multiline = TRUE)
		return
	if(message)
		gem().use_emote(message, src)

// Allows the captured owner to transfer themselves to valid nearby objects
/mob/living/carbon/brain/caught_soul/vore/proc/transfer_self()
	set name = "Transfer Self"
	set desc = "Transfer youself while being in your own soulcatcher into a nearby Sleevemate or MMI."
	set category = VERB_CAT_SOULCATCHER
	return soul_transfer_stage()

/mob/living/carbon/brain/caught_soul/vore/proc/soul_transfer_stage(obj/selected_target, prompted = FALSE)
	var/mob/observer/eye/eyeobj = src?.active_eye()

	if(eyeobj)
		to_chat(src, span_warning("You can't do that while SR projecting!"))
		return
	if(gem().own_mind() != mind)
		to_chat(src, span_warning("You aren't in your own soulcatcher!"))
		return

	var/list/valid_objects = gem().find_transfer_objects()
	if(!valid_objects || !valid_objects.len)
		return

	if(!prompted)
		open_request(src, /datum/prompt/choice/soulcatcher_transfer, PROC_REF(soul_transfer_answered), answerer = src, question = "Select where you want to store your own mind into.", title = "Mind Transfer Target", choices = valid_objects)
		return
	var/obj/target = selected_target
	if(isnull(target))
		return

	gem().transfer_mob_selector(src, target)

// Allows the owner to reenter the body after being caught or having given away control
/mob/living/carbon/brain/caught_soul/vore/proc/reenter_body()
	var/mob/observer/eye/eyeobj = src?.active_eye()
	set name = "Re-enter Body"
	set desc = "Return to your body after self capturing."
	set category = VERB_CAT_SOULCATCHER

	if(eyeobj)
		to_chat(src, span_warning("You can't do that while SR projecting!"))
		return
	gem().return_to_body(mind)

/// the gem this refers to (a relation view: null once it is deleted).
/mob/living/carbon/brain/caught_soul/vore/proc/gem() as /obj/soulgem
	return gem

/mob/proc/gem_say_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = gem_say_apply(A)
	SStgui.update_uis(src)

/mob/proc/gem_say_apply(datum/act/request/A)
	var/datum/prompt/text/soulcatcher_speech/ask = A.answer
	return gem_say_stage(ask.value, TRUE)

/mob/proc/gem_emote_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = gem_emote_apply(A)
	SStgui.update_uis(src)

/mob/proc/gem_emote_apply(datum/act/request/A)
	var/datum/prompt/text/soulcatcher_speech/ask = A.answer
	return gem_emote_stage(ask.value, TRUE)

/mob/living/carbon/brain/caught_soul/vore/proc/gem_brain_say_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = gem_brain_say_apply(A)
	SStgui.update_uis(src)

/mob/living/carbon/brain/caught_soul/vore/proc/gem_brain_say_apply(datum/act/request/A)
	var/datum/prompt/text/soulcatcher_speech/ask = A.answer
	return gem_brain_say_stage(ask.value, TRUE)

/mob/living/carbon/brain/caught_soul/vore/proc/gem_brain_emote_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = gem_brain_emote_apply(A)
	SStgui.update_uis(src)

/mob/living/carbon/brain/caught_soul/vore/proc/gem_brain_emote_apply(datum/act/request/A)
	var/datum/prompt/text/soulcatcher_speech/ask = A.answer
	return gem_brain_emote_stage(ask.value, TRUE)

/mob/living/carbon/brain/caught_soul/vore/proc/soul_transfer_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = soul_transfer_apply(A)
	SStgui.update_uis(src)

/mob/living/carbon/brain/caught_soul/vore/proc/soul_transfer_apply(datum/act/request/A)
	var/datum/prompt/choice/soulcatcher_transfer/ask = A.answer
	return soul_transfer_stage(ask.value, TRUE)

/datum/prompt/choice/soulcatcher_transfer
	timeout = 0

/datum/prompt/choice/soulcatcher_transfer/recheck_extra()
	if(!isnull(value))
		var/obj/selected = value
		if(!istype(selected) || QDELETED(selected))
			return "gone"
