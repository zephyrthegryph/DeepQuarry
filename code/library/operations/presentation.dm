/// A timed wait starts: its actor sees a progress bar fill over the delay and onlookers a cog, as a legacy timed action showed (silent_wait() opts out).
/datum/pending_op/progress_begin(delay)
	progress_end(TRUE)
	var/mob/user = actor
	if(oplan.silent_wait || !istype(user) || origin == ORIGIN_SYSTEM)
		return
	progress_planned = TRUE
	if(user.client)
		var/atom/where = target
		rel_set(src, nameof(progbar), new /datum/progressbar(user, delay, istype(where) ? where : user))
		progbar.animate_fill(delay)
	if(delay >= 1 SECONDS)
		rel_set(src, nameof(cog), new /datum/cogbar(user, 'icons/effects/progressbar.dmi', "cog"))

/// The bar and the cog go: filled on success, failed when the wait was broken.
/datum/pending_op/progress_end(success)
	// both fade out and delete themselves: handed off, not owned
	var/datum/progressbar/old_bar = own_take(src, nameof(progbar))
	if(!QDELETED(old_bar))
		old_bar.end_progress(success)
	var/datum/cogbar/old_cog = own_take(src, nameof(cog))
	old_cog?.remove()


/datum/tgui/op_window_interactive()
	return !QDELETED(src_object()) && status == STATUS_INTERACTIVE
/atom/op_claim_changed()
	return update_icon()
/mob/op_notify(text)
	return to_chat(src, span_warning(text))
/mob/living/op_uses_actor_stats()
	return TRUE
/mob/living/op_hand_capable()
	return stat == CONSCIOUS && !incapacitated(INCAPACITATION_STUNNED)
/mob/op_feedback_message(atom/target, msg, obj/held)
	return act_message_t(src, target, msg, held)
/atom/op_feedback_sound(sfx)
	return play_sfx(src, sfx)

/atom/op_timer_message(msg)
	return act_message_t(src, src, msg)
