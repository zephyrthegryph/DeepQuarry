// Old style chat inputs, the fallback when TG Say is off. Procs, not verbs: the hidden say wrappers (typing_indicator.dm) call them.

/// Asks for a chat line and hands it to `action` (a proc on the mob taking the message).
/// `typing` shows the typing indicator while the window is open.
/mob/proc/ask_chat_line(message, title, action, multiline = FALSE, typing = TRUE)
	if(typing)
		client?.start_thinking()
		client?.start_typing()
	open_request(src, /datum/prompt/text/chat_line, PROC_REF(chat_line_entered), answerer = src, title = title, question = message, multiline = multiline, action = action)

/// An old-style chat line; `action` is the mob proc the line is handed to.
/datum/prompt/text/chat_line
	encode = FALSE
	timeout = 0
	var/action

/mob/proc/chat_line_entered(datum/act/request/A)
	if(!A.answer)
		if(A.request.outcome == REQ_CANCELLED && isnull(A.request.value) && !QDELETED(A.request.answerer))
			client?.stop_thinking()
		return
	var/datum/prompt/text/chat_line/prompt = A.answer
	client?.stop_thinking()
	if(A.answer.value)
		call(src, prompt.action)(A.answer.value)

/mob/proc/say_verb_old()

	ask_chat_line("Speak to people in sight.\nType your message:", "Say", /mob/verb/say_verb)

/mob/proc/me_verb_old()

	ask_chat_line("Emote to people in sight (and your pred/prey).\nType your message:", "Emote", /mob/verb/me_verb, TRUE)

/mob/proc/whisper_old()

	ask_chat_line("Speak to nearby people.\nType your message:", "Whisper", /mob/verb/whisper, FALSE, client?.prefs?.read_preference(/datum/preference/toggle/show_typing_indicator_subtle))

/mob/proc/me_verb_subtle_old()

	ask_chat_line("Emote to nearby people (and your pred/prey).\nType your message:", "Subtle", /mob/verb/me_verb_subtle, TRUE, client?.prefs?.read_preference(/datum/preference/toggle/show_typing_indicator_subtle))

/mob/proc/me_verb_subtle_custom_old()

	ask_chat_line("Emote to nearby people, with ability to choose which specific portion of people you wish to target.\nType your message:", "Subtle (Custom)", /mob/verb/me_verb_subtle_custom, TRUE, FALSE)

/mob/proc/psay_old()

	ask_chat_line("Talk to people affected by complete absorbed or dominate predator/prey.\nType your message:", "Psay", /mob/verb/psay, FALSE, FALSE)

/mob/proc/pme_old()

	ask_chat_line("Emote to people affected by complete absorbed or dominate predator/prey.\nType your message:", "Pme", /mob/verb/pme, FALSE, FALSE)

/mob/living/proc/player_narrate_ch()

	ask_chat_line("Narrate an action or event! An alternative to emoting, for when your emote shouldn't start with your name!\nType your message:", "Narrate (Player)", /mob/living/verb/player_narrate, FALSE, FALSE)
