/obj/structure/fitness
	icon = 'icons/obj/stationobjs.dmi'
	anchored = TRUE
	var/weightloss_power = 1

/obj/structure/fitness/punchingbag
	name = "punching bag"
	desc = "A punching bag."
	icon_state = "punchingbag"
	density = TRUE
	var/static/list/hit_message = list("hit", "punch", "kick", "robust")

CAPABILITIES(/obj/structure/fitness/punchingbag)
	op("hand", hand(), stance(I_HURT), label("Punch"), then(PROC_REF(interaction_hand)))

/obj/structure/fitness/punchingbag/proc/interaction_hand(datum/act/op/A)
	var/mob/living/carbon/human/user = A.actor
	if(!istype(user))
		return TRUE
	if(user.nutrition < 70) // Set minimum nutrition to be the same as in fitness_machines_vr.dm
		to_chat(user, span_warning("You need more energy to use the punching bag. Go eat something."))
	else if(user.weight < 70) // Add weight loss to old fitness equipment
		to_chat(user, span_notice("You're too skinny to risk losing any more weight!"))
	else
		user.setClickCooldown(user.get_attack_speed())
		flick("[icon_state]_hit", src)
		play_sfx(src, SFX_EFFECTS_WOODHIT)
		user.do_attack_animation(src)
		user.adjust_nutrition(-10) // Set nutrition drain to be the same as in fitness_machines_vr.dm
		user.weight -= 0.25 * weightloss_power * (0.01 * user.weight_loss)
		to_chat(user, span_warning("You [pick(hit_message)] \the [src]."))
	return TRUE

/obj/structure/fitness/weightlifter
	name = "weightlifting machine"
	desc = "A machine used to lift weights."
	icon_state = "weightlifter"
	blocks_emissive = EMISSIVE_BLOCK_UNIQUE
	var/weight = 1
	var/static/list/qualifiers = list("with ease", "without any trouble", "with great effort")

CAPABILITIES(/obj/structure/fitness/weightlifter)
	op("use_wrench", tool(TOOL_WRENCH), wait(0), then(PROC_REF(wrench_used)))
	op("lift", hand(), label("Lift"), when(req_actor_kind(/mob/living/carbon/human)), needs(req(PROC_REF(can_lift), because = PROC_REF(lift_refusal))), then(PROC_REF(interaction_hand)))

/obj/structure/fitness/weightlifter/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	play_sfx(src, SFX_ITEMS_DECONSTRUCT, 1.5)
	weight = ((weight) % qualifiers.len) + 1
	to_chat(user, "You set the machine's weight level to [weight].")
	return OP_OK

/// Requirement: the person can lift right now.
/obj/structure/fitness/weightlifter/proc/can_lift(datum/act/op/A)
	return isnull(weightlift_refusal(A.actor, src))

/obj/structure/fitness/weightlifter/proc/lift_refusal(datum/act/op/A)
	return weightlift_refusal(A.actor, src)

/// Why `user` can't use the weight machine `machine` now, or null: on it, fed, heavy enough, and nobody else on it.
/proc/weightlift_refusal(mob/living/carbon/human/user, obj/structure/fitness/weightlifter/machine)
	READS_FROM() // a body's place, nutrition and weight are asked when the lift starts; the lift itself claims the machine
	if(user.loc != machine.loc)
		return "You must be on the weight machine to use it."
	if(user.nutrition < 70) // Set minimum nutrition to be the same as in fitness_machines_vr.dm
		return "You need more energy to lift weights, go eat something."
	if(user.weight < 70) // Add weight loss to old fitness equipment
		return "You're too skinny to risk losing any more weight."
	if(task_busy(machine))
		return "The weight machine is already in use by somebody else."
	return null

/// Old attack_hand: a person on the machine lifts its weights.
/obj/structure/fitness/weightlifter/proc/interaction_hand(datum/act/op/A)
	var/mob/living/carbon/human/user = A.actor
	play_sfx(src, SFX_EFFECTS_WEIGHTLIFTER)
	user.set_dir(SOUTH)
	flick("[icon_state]_[weight]", src)
	task_timed(user, 3 SECONDS + (weight * 10), target = src, receiver = src, on_done = PROC_REF(attack_hand_timed_done), done_args = list(user), on_fail = PROC_REF(attack_hand_timed_failed), fail_args = list(user), claims = TRUE)
	return OP_OK

/obj/structure/fitness/weightlifter/proc/attack_hand_timed_done(mob/living/carbon/human/user)
	play_sfx(src, SFX_EFFECTS_WEIGHTDROP)
	user.adjust_nutrition(weight * -10)
	var/weightloss_enhanced = weightloss_power * (weight * 0.5)
	user.weight -= 0.25 * weightloss_enhanced * (0.01 * user.weight_loss)
	to_chat(user, span_notice("You lift the weights [qualifiers[weight]]."))

/obj/structure/fitness/weightlifter/proc/attack_hand_timed_failed(mob/living/carbon/human/user)
	to_chat(user, span_notice("Against your previous judgement, perhaps working out is not for you."))

/obj/structure/fitness/boxing_ropes
	name = "ropes"
	desc = "Firm yet springy, perhaps this could be useful!"
	icon = 'icons/obj/fitness.dmi'
	icon_state = "ropes"
	density = TRUE
	throwpass = TRUE
	layer = WINDOW_LAYER
	anchored = TRUE
	flags = ON_BORDER

CAPABILITIES(/obj/structure/fitness/boxing_ropes)
	climb(vaulting = TRUE)

/obj/structure/fitness/boxing_ropes/CanPass(atom/movable/mover, turf/target)
	if(istype(mover) && mover.checkpass(PASSTABLE))
		return TRUE
	if(get_dir(mover, target) == GLOB.reverse_dir[dir]) // From elsewhere to here, can't move against our dir
		return !density
	return TRUE

/obj/structure/fitness/boxing_ropes/Uncross(atom/movable/mover, turf/target)
	if(istype(mover) && mover.checkpass(PASSTABLE))
		return TRUE
	if(get_dir(mover, target) == dir) // From here to elsewhere, can't move in our dir
		return !density
	return TRUE

/obj/structure/fitness/boxing_ropes/bottom
	plane = MOB_PLANE
	layer = ABOVE_MOB_LAYER

/obj/structure/fitness/boxing_ropes/turnbuckle
	name = "turnbuckle"
	desc = "A sturdy post that looks like it could support even the most heaviest of heavy weights!"
	icon = 'icons/obj/fitness.dmi'
	icon_state = "turnbuckle"
	layer = WINDOW_LAYER

