// The windows a prompt is shown in (doc/rewrite/final_api.html, section 13 "Requests, prompts and workflows (X3)": "Transport: a tgui window; closing it is a
// cancellation"). Each kind's present() (code/engine/parts/prompts.dm, code/library/prompts/) builds one of these over a tgui input or the radial ring, points
// it at the prompt and shows it; the window answers through prompt_window_answer() and ends through prompt_window_closed(), so an answer meets the same
// normalize() and refusal() the test driver's request_answer() does, and nothing here waits on the player.

/// A window answered: the prompt checks the answer and ends answered, or (a refused answer) stays open.
/proc/prompt_window_answer(datum/prompt/P, answer)
	if(!istype(P) || !P.is_open())
		return
	var/why = request_submit(P, answer)
	if(why)
		var/mob/user = P.answerer
		if(istype(user))
			P.presentation_refused(user, why)
		P.reopen()

/// A window was closed (or timed out) with no answer: the prompt ends cancelled.
/proc/prompt_window_closed(datum/prompt/P)
	if(!istype(P) || !P.is_open())
		return
	request_end(P, REQ_CANCELLED, null)


/datum/prompt/proc/presentation_refused(mob/user, reason)
	return

/datum/prompt/proc/begin_inline(mob/user)
	last_error = "No inline prompt transport is available."
	after(src, 1 TICK, TYPE_PROC_REF(/datum/prompt, nothing_to_ask), key = "request_begin")
	return FALSE

/datum/prompt/proc/dismiss_inline()
	return
