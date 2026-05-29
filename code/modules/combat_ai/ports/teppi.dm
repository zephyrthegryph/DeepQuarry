// Teppi voice command port — follows / unfollows based on speaker affinity.
//
// Replaces the deleted /datum/ai_holder/simple_mob/teppi/on_hear_say override.
// The "set_follow with timeout" parameter is gone (brain.set_follow doesn't
// take a follow_for); follows persist until the next stop command or until
// the teppi takes damage from the leader.

/mob/living/simple_mob/vore/alienanimals/teppi/hear_say(list/message_pieces, verb = "says", italics = 0, mob/speaker = null, sound/speech_sound, sound_vol)
	. = ..()
	if(client || !speaker || !speaker.client)
		return
	if(!teppi_adult)
		return
	if(!ai_brain)
		return
	var/message = html_decode(multilingual_to_message(message_pieces))
	if(!message)
		return
	var/speaker_affinity = affinity[speaker.real_name]
	var/mob/leader = ai_brain.get_leader()
	if(findtext(message, "lets go") || findtext(message, "let's go") || findtext(message, "come teppi") || findtext(message, "come [name]"))
		if(speaker == leader)
			return
		if(!leader)
			if(speaker_affinity >= 100)
				ai_brain.set_follow(speaker)
				visible_message(span_notice("\The [src] starts following \the [speaker]"), span_notice("\The [src] starts following you."))
			return
		// Has a different leader currently.
		if(speaker_affinity > affinity[leader.real_name])
			visible_message(span_notice("\The [src] starts following \the [speaker]"), span_notice("\The [src] starts following you."))
			ai_brain.set_follow(speaker)
			return
		if(speaker_affinity == affinity[leader.real_name])
			ai_brain.lose_follow()
			visible_message(span_notice("\The [src] gives off an anxious whine."))
			return
	if(findtext(message, "stop teppi") || findtext(message, "stay here") || findtext(message, "stop [name]"))
		if(leader == speaker)
			ai_brain.lose_follow()
			visible_message(span_notice("\The [src] stops following \the [speaker]"), span_notice("\The [src] stops following you."))
