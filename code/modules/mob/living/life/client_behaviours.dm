// Client-only Life work uses independent behaviour deadlines. The client
// requirement keeps these behaviours inactive on NPC mobs.
/datum/object_model/requirement/living_client
	failure_message = "This mob has no client"

/datum/object_model/requirement/living_client/check(datum/source, mob/actor, atom/target, obj/item/held)
	var/mob/living/M = source
	return !!M?.client

/datum/object_model/behaviour/living_afk
	requires = list(/datum/object_model/requirement/living_client)
	run_period = 30 SECONDS

/datum/object_model/behaviour/living_afk/on_run(datum/source, seconds, list/config)
	var/mob/living/M = source
	var/client/C = M.client
	if(!C)
		return 0
	var/idle_limit = 10 MINUTES
	if(C.inactivity >= idle_limit && !M.away_from_keyboard && C.prefs?.read_preference(/datum/preference/toggle/auto_afk))
		M.add_status_indicator("afk")
		to_chat(M, span_notice("You have been idle for too long, and automatically marked as AFK."))
		M.away_from_keyboard = TRUE
	else if(M.away_from_keyboard && C.inactivity < idle_limit && !M.manual_afk)
		M.remove_status_indicator("afk")
		to_chat(M, span_notice("You have been automatically un-marked as AFK."))
		M.away_from_keyboard = FALSE
	return null

/// Ambience is due at its own deadline; AFK's shorter timer cannot wake it early.
/datum/object_model/behaviour/living_ambience
	requires = list(/datum/object_model/requirement/living_client)
	run_period = 1 MINUTES

/datum/object_model/behaviour/living_ambience/on_run(datum/source, seconds, list/config)
	var/mob/living/M = source
	if(!M.client)
		return 0
	var/pref = M.read_preference(/datum/preference/numeric/ambience_freq)
	if(!pref)
		return 0
	if(world.time >= M.lastareachange + pref MINUTES)
		var/area/A = get_area(M)
		if(A)
			M.lastareachange = world.time
			A.play_ambience(M, initial = FALSE)
	return max(1 SECONDS, M.lastareachange + pref MINUTES - world.time)

/datum/object_model/declaration/living_afk
	target_type = /mob/living

/datum/object_model/declaration/living_afk/build(datum/object_model/archetype/A)
	A.add(/datum/object_model/behaviour/living_life_frame)
	A.add(/datum/object_model/behaviour/living_afk)
	A.add(/datum/object_model/behaviour/living_ambience)
