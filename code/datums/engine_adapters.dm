// Actual downstream implementations of engine transport interfaces.
/datum/scheduler_presentation_mask()
	return appearance_mask_of(src)

/datum/scheduler_queue_presentation()
	appearance_queue(src)

/datum/time_scheduler/drain_presentation()
	return appearance_drain(src)

/datum/native_watch/bind_native()
	return SSvg.bind_datum(src)

/datum/native_watch/unbind_native(handle)
	SSvg.unbind_datum(src, handle)

/datum/native_watch_provider/lookup(handle)
	return SSvg.entity_lookup(handle)

/atom/movable/place_starting_occupant(atom/holder)
	return forceMove(holder)

/datum/transfer_feedback_provider/send(mob/actor, datum/holder, datum/item, reason, raw = FALSE)
	if(raw)
		refuse(actor, reason)
	else if(ispath(reason, /datum/msg))
		act_message_t(actor, holder, reason, isitem(item) ? item : null)
	else if(istext(reason))
		refuse(actor, "[capitalize(reason)].")

/// The admin verb "List Activations": every activation on an entity with its source, scope and contributions.
ADMIN_VERB_AND_CONTEXT_MENU(e1_list_activations, R_DEBUG, "List Activations", "Every activation on a thing, with its source, scope and contributions.", ADMIN_CATEGORY_DEBUG, atom/target in world)
	to_chat(user, "<b>Activations of [target] ([target.type])</b><br>[replacetext(explain_activations(target) || "none", "\n", "<br>")]")

/mob/living/timer_clock()
	return CLOCK_BIO

/// A driver-built href that no native topic op answered goes to the downstream topic table.
/datum/input_adapter/compatibility_topic(datum/holder, mob/actor, list/href_list)
	return topic_dispatch(holder, actor, href_list)
