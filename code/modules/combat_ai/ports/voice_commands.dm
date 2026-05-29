// Voice command handlers — restores the on_hear_say overrides that lived on
// deleted /datum/ai_holder/.../on_hear_say subtypes.
//
// Each mob type re-opens hear_say to handle its keywords. The brain is not
// involved (voice commands aren't combat decisions); the mob just listens
// for specific phrases and reacts.

// ---------------------------------------------------------------------------
// Helper — delayed say with 1-3 second jitter, mirroring the legacy delayed_say.
// ---------------------------------------------------------------------------
/proc/dq_voice_reply(mob/living/who, list/options, mob/listener)
	if(!who || !length(options))
		return
	addtimer(CALLBACK(who, TYPE_PROC_REF(/mob, say), pick(options)), rand(5, 15))

// ---------------------------------------------------------------------------
// Parrot — repeat-everything mimicry.
// ---------------------------------------------------------------------------
/mob/living/simple_mob/animal/parrot/hear_say(list/message_pieces, verb = "says", italics = 0, mob/speaker = null, sound/speech_sound, sound_vol)
	. = ..()
	if(stat || client || !say_list || !speaker || speaker == src)
		return
	var/message = multilingual_to_message(message_pieces)
	if(!message)
		return
	say_list.speak |= message

// ---------------------------------------------------------------------------
// Cookiegirl — sweet replies to specific food-themed questions.
// ---------------------------------------------------------------------------
/mob/living/simple_mob/vore/cookiegirl/hear_say(list/message_pieces, verb = "says", italics = 0, mob/speaker = null, sound/speech_sound, sound_vol)
	. = ..()
	if(!speaker || !speaker.client || speaker == src)
		return
	var/message = multilingual_to_message(message_pieces)
	if(findtext(message, "Can I eat you?"))
		dq_voice_reply(src, list("Do you really wanna eat someone as sweet as me~?"), speaker)
	if(findtext(message, "You look tasty."))
		dq_voice_reply(src, list("Awww, thank you~!"), speaker)
	if(findtext(message, "Can I serve you to the crew?"))
		dq_voice_reply(src, list("If I have a backup, sure!"), speaker)

// ---------------------------------------------------------------------------
// Wolfgirl — long list of canned responses.
// ---------------------------------------------------------------------------
/mob/living/simple_mob/vore/wolfgirl/hear_say(list/message_pieces, verb = "says", italics = 0, mob/speaker = null, sound/speech_sound, sound_vol)
	. = ..()
	if(!speaker || !speaker.client || speaker == src)
		return
	var/message = multilingual_to_message(message_pieces)
	if(findtext(message, "hello") || findtext(message, "hi") || findtext(message, "greetings"))
		dq_voice_reply(src, list("Heya!", "Hey!"), speaker)
	if(findtext(message, "Are you a dog?"))
		dq_voice_reply(src, list("Who, me?! No! Stop saying that!"), speaker)
	if(findtext(message, "Awoo?"))
		dq_voice_reply(src, list("Awoo."), speaker)
	if(findtext(message, "Awoo!"))
		dq_voice_reply(src, list("AwooooOOOOooo!"), speaker)
	if(findtext(message, "Awoo."))
		dq_voice_reply(src, list("Awoo?"), speaker)
	if(findtext(message, "Nice hat"))
		dq_voice_reply(src, list("Thanks my grandma made it for me."), speaker)
	if(findtext(message, "What's your phone number?"))
		dq_voice_reply(src, list("Five six seven oh nine! Wait, who are you?"), speaker)
	if(findtext(message, "Are you horny?"))
		dq_voice_reply(src, list("No! I'm just hyperactive!"), speaker)
	if(findtext(message, "Good girl"))
		dq_voice_reply(src, list("Aww thanks... Wait, I'm not a dog!"), speaker)
	if(findtext(message, "Fuyu"))
		dq_voice_reply(src, list("You know my sister?!", "Is she causing problems again?"), speaker)

// ---------------------------------------------------------------------------
// Vore-aggressive say_aggro mobs (leaper et al) — getting addressed promotes
// the speaker to a personal HOSTILE entry, triggering the brain to engage.
// Mirrors the legacy say_aggro/on_hear_say give_target/set_stance(STANCE_FIGHT).
// ---------------------------------------------------------------------------
/mob/living/simple_mob/vore/leaper/hear_say(list/message_pieces, verb = "says", italics = 0, mob/speaker = null, sound/speech_sound, sound_vol)
	. = ..()
	if(client || !speaker || !speaker.client)
		return
	if(!isliving(speaker))
		return
	if(!speaker.devourable || !speaker.allowmobvore || !speaker.can_be_drop_prey)
		return
	if(speaker.z != z)
		return
	ai_brain?.give_target(speaker, TRUE)

// ---------------------------------------------------------------------------
// Armadillo "torta" — grow when "grande" is spoken nearby.
// ---------------------------------------------------------------------------
/mob/living/simple_mob/animal/passive/armadillo/torta/hear_say(list/message_pieces, verb = "says", italics = 0, mob/speaker = null, sound/speech_sound, sound_vol)
	. = ..()
	if(!speaker || !speaker.client || speaker == src)
		return
	var/message = lowertext(multilingual_to_message(message_pieces))
	addtimer(CALLBACK(src, PROC_REF(dq_torta_grande), message), 1 SECOND)

/mob/living/simple_mob/animal/passive/armadillo/torta/proc/dq_torta_grande(message)
	if(findtext(message, "grande"))
		resize(size_multiplier + 0.01)

// ---------------------------------------------------------------------------
// Catslug — "psps" triggers a follow; everything else echoes (like parrot).
// ---------------------------------------------------------------------------
/mob/living/simple_mob/vore/alienanimals/catslug/hear_say(list/message_pieces, verb = "says", italics = 0, mob/speaker = null, sound/speech_sound, sound_vol)
	. = ..()
	if(client || !speaker || !speaker.client)
		return
	var/message = multilingual_to_message(message_pieces)
	if(findtext(message, "psps") && ai_brain && !ai_brain.primary_threat)
		ai_brain.set_follow(speaker)
	if(stat || !say_list || !message || speaker == src)
		return
	say_list.speak |= message

// Horrible variant follows on "psps" OR while idle (the original quirk).
/mob/living/simple_mob/vore/alienanimals/catslug/horrible/hear_say(list/message_pieces, verb = "says", italics = 0, mob/speaker = null, sound/speech_sound, sound_vol)
	. = ..()
	if(client || !speaker || !speaker.client)
		return
	var/message = multilingual_to_message(message_pieces)
	if((findtext(message, "psps") || (ai_brain && !ai_brain.primary_threat)) && ai_brain)
		ai_brain.set_follow(speaker)
	if(stat || !say_list || !message || speaker == src)
		return
	say_list.speak |= message
