/mob/var/suiciding = 0

/mob/living/carbon/human/verb/suicide() /// At best, useful for admins to see if it's being called.
	set hidden = 1

	if (stat == DEAD)
		to_chat(src, "You're already dead!")
		return

	if (!SSticker)
		to_chat(src, "You can't commit suicide before the game starts!")
		return

	to_chat(src, span_warning("No. Adminhelp if there is a legitimate reason, and please review our server rules."))
	message_admins("[ckey] has tried to trigger the suicide verb as human, but it is currently disabled.")

/mob/living/carbon/brain/verb/suicide()
	set hidden = 1
	return brain_suicide_review()

/mob/living/carbon/brain/proc/brain_suicide_review(confirm)

	if (stat == 2)
		to_chat(src, "You're already dead!")
		return

	if (!SSticker)
		to_chat(src, "You can't commit suicide before the game starts!")
		return

	if (suiciding)
		to_chat(src, "You're already committing suicide! Be patient!")
		return

	if(isnull(confirm))
		open_request(src, /datum/prompt/choice/suicide_review, PROC_REF(brain_suicide_answered), answerer = src, question = "Are you sure you want to commit suicide?", title = "Confirm Suicide", choices = list("Yes", "No"))
		return

	if(confirm == "Yes")
		suiciding = 1
		to_chat(viewers(loc),span_danger("[src]'s brain is growing dull and lifeless. It looks like it's lost the will to live."))
		after(src, 5 SECONDS, PROC_REF(brain_suicide_ends))

/mob/living/silicon/ai/verb/suicide()
	set hidden = 1
	return ai_suicide_review()

/mob/living/silicon/ai/proc/ai_suicide_review(confirm)

	if (stat == 2)
		to_chat(src, "You're already dead!")
		return

	if (suiciding)
		to_chat(src, "You're already committing suicide! Be patient!")
		return

	if(isnull(confirm))
		open_request(src, /datum/prompt/choice/suicide_review, PROC_REF(ai_suicide_answered), answerer = src, question = "Are you sure you want to commit suicide?", title = "Confirm Suicide", choices = list("Yes", "No"))
		return

	if(confirm == "Yes")
		suiciding = 1
		to_chat(viewers(src),span_danger("[src] is powering down. It looks like they're trying to commit suicide."))
		death(0)

/mob/living/silicon/robot/verb/suicide()
	set hidden = 1
	return robot_suicide_review()

/mob/living/silicon/robot/proc/robot_suicide_review(confirm)

	if (stat == 2)
		to_chat(src, "You're already dead!")
		return

	if (suiciding)
		to_chat(src, "You're already committing suicide! Be patient!")
		return

	if(isnull(confirm))
		open_request(src, /datum/prompt/choice/suicide_review, PROC_REF(robot_suicide_answered), answerer = src, question = "Are you sure you want to commit suicide?", title = "Confirm Suicide", choices = list("Yes", "No"))
		return

	if(confirm == "Yes")
		suiciding = 1
		to_chat(viewers(src),span_danger("[src] is powering down. It looks like they're trying to commit suicide."))
		death(0)

/*
/mob/living/silicon/pai/verb/suicide()
	set category = VERB_CAT_ABILITIES_PAI_COMMANDS
	set desc = "Kill yourself and become a ghost (You will receive a confirmation prompt)"
	set name = "pAI Suicide"
	var/answer = tgui_alert(src, "REALLY kill yourself? This action can't be undone.", "Suicide", list("Yes","No"))
	if(answer == "Yes")
		var/obj/item/paicard/card = loc
		card.removePersonality()
		var/turf/T = get_turf_or_move(card.loc)
		for (var/mob/M in viewers(T))
			M.show_message(span_notice("[src] flashes a message across its screen, \"Wiping core files. Please acquire a new personality to continue using pAI device functions.\""), 3, span_notice("[src] bleeps electronically."), 2)
		death(0)
	else
		to_chat(src, "Aborting suicide attempt.")
*/

/mob/living/carbon/brain/proc/brain_suicide_ends()
	death(0)
	suiciding = 0

/mob/living/carbon/brain/proc/brain_suicide_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = brain_suicide_apply(A)
	SStgui.update_uis(src)

/mob/living/carbon/brain/proc/brain_suicide_apply(datum/act/request/A)
	var/datum/prompt/choice/suicide_review/ask = A.answer
	return brain_suicide_review(ask.value)

/mob/living/silicon/ai/proc/ai_suicide_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = ai_suicide_apply(A)
	SStgui.update_uis(src)

/mob/living/silicon/ai/proc/ai_suicide_apply(datum/act/request/A)
	var/datum/prompt/choice/suicide_review/ask = A.answer
	return ai_suicide_review(ask.value)

/mob/living/silicon/robot/proc/robot_suicide_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = robot_suicide_apply(A)
	SStgui.update_uis(src)

/mob/living/silicon/robot/proc/robot_suicide_apply(datum/act/request/A)
	var/datum/prompt/choice/suicide_review/ask = A.answer
	return robot_suicide_review(ask.value)

/datum/prompt/choice/suicide_review
	timeout = 0
	buttons = TRUE
