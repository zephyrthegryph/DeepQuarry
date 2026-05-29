// Possum port — restores hiss-then-play-dead defensive behavior that lived
// on the deleted /datum/ai_holder/simple_mob/passive/possum subtype.
//
// State lives on the possum mob now. respond_to_damage is the trigger, and
// update_icon reads the angry flag. The play-dead tick logic moves into a
// background behavior that runs on the slow tick.

/mob/living/simple_mob/animal/passive/opossum
	var/is_angry = FALSE
	var/play_dead_until = 0
	var/be_angery_until = 0

/mob/living/simple_mob/animal/passive/opossum/get_ai_behaviors()
	var/static/list/L = list(
		/datum/ai_behavior/possum_play_dead,
		/datum/ai_behavior/idle_wander,
		/datum/ai_behavior/idle_speak,
	)
	return L

/mob/living/simple_mob/animal/passive/opossum/respond_to_damage()
	if(!resting && stat == CONSCIOUS)
		if(!client)
			if(!is_angry)
				visible_message(span_infoplain(span_bold("\The [src]") + " hisses!"))
				is_angry = TRUE
				be_angery_until = world.time + rand(30 SECONDS, 1 MINUTE)
			else
				visible_message(span_infoplain(span_bold("\The [src]") + " dies!"))
				resting = TRUE
				play_dead_until = world.time + rand(1 MINUTE, 2 MINUTES)
		update_icon()

/mob/living/simple_mob/animal/passive/opossum/update_icon()
	// Override to read the local is_angry flag instead of the deleted ai_holder.
	if(stat == DEAD || (resting && is_angry))
		icon_state = icon_dead
	else if(resting || stat == UNCONSCIOUS)
		icon_state = "[icon_living]_sleep"
	else if(is_angry)
		icon_state = "[icon_living]_angry"
	else
		icon_state = icon_living

// Background behavior — ticks the resting / angry state machine the legacy
// ai_holder's handle_special_strategical used to.
/datum/ai_behavior/possum_play_dead
	name = "possum play-dead"
	priority_class = DQ_BEHAVIOR_PRIORITY_BACKGROUND
	target_kind = DQ_TARGET_NONE
	no_threat_required = TRUE

/datum/ai_behavior/possum_play_dead/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/animal/passive/opossum)

/datum/ai_behavior/possum_play_dead/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/animal/passive/opossum/possum = brain.holder
	if(!possum || possum.stat == DEAD || possum.client)
		return null
	if(!isturf(possum.loc))
		return null
	return DQAI_RESULT(3, possum)

/datum/ai_behavior/possum_play_dead/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/animal/passive/opossum/possum = brain.holder
	if(possum.resting && world.time < possum.play_dead_until)
		return DQ_BEHAVIOR_DONE
	var/last_resting = possum.resting
	var/last_angery = possum.is_angry
	possum.resting = (possum.stat == UNCONSCIOUS)
	if(!possum.resting)
		brain.wander = TRUE
		possum.set_stat(CONSCIOUS)
		possum.is_angry = (world.time < possum.be_angery_until) || prob(1)
	else
		brain.wander = FALSE
		possum.set_stat(UNCONSCIOUS)
		possum.is_angry = FALSE
	if(last_resting != possum.resting || last_angery != possum.is_angry)
		possum.update_icon()
	return DQ_BEHAVIOR_DONE
