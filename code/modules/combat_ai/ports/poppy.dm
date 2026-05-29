// Poppy possum port — the alarm-word-trigger possum that play-dead'd on
// hearing words like "fire", "breach", "blob", "delaminat", etc.

/mob/living/simple_mob/animal/passive/opossum/poppy
	var/static/list/aaa_words = list(
		"delaminat",
		"meteor",
		"fire",
		"breach",
		"loose",
		"level 7",
		"level seven",
		"biohazard",
		"blob",
		"vine",
	)

/mob/living/simple_mob/animal/passive/opossum/poppy/hear_say(list/message_pieces, verb = "says", italics = 0, mob/speaker = null, sound/speech_sound, sound_vol)
	. = ..()
	if(!speaker || !speaker.client || speaker == src)
		return
	var/message = multilingual_to_message(message_pieces)
	addtimer(CALLBACK(src, PROC_REF(dq_poppy_check_keywords), message), rand(1 SECOND, 3 SECONDS))

/mob/living/simple_mob/animal/passive/opossum/poppy/proc/dq_poppy_check_keywords(message)
	if(client || stat != CONSCIOUS)
		return
	message = lowertext(message)
	for(var/aaa in aaa_words)
		if(findtext(message, aaa))
			respond_to_damage()
			return
