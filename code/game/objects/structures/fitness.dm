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

/obj/structure/fitness/punchingbag/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_hand/punchingbag_hand,
	)
	..()

/// Old attack_hand: hit the punching bag (combat mode only).
/datum/interaction/entry_hand/punchingbag_hand
	id = "punchingbag_hand"
	name = "Punch"
	effect = /obj/structure/fitness/punchingbag/proc/interaction_hand
	stance = I_HURT

/obj/structure/fitness/punchingbag/proc/interaction_hand(mob/living/carbon/human/user, obj/item/held, datum/interaction/interaction)
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

/obj/structure/fitness/weightlifter/wrench_act(mob/user, obj/item/W)
	play_sfx(src, SFX_ITEMS_DECONSTRUCT, 1.5)
	weight = ((weight) % qualifiers.len) + 1
	to_chat(user, "You set the machine's weight level to [weight].")
	return TRUE

/obj/structure/fitness/weightlifter/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_hand/weightlifter_hand,
	)
	..()

/// Old attack_hand: use the weightlifting machine.
/datum/interaction/entry_hand/weightlifter_hand
	id = "weightlifter_hand"
	name = "Lift"
	also_requires = list(REQ_TARGET_STATE(/obj/structure/fitness/weightlifter/proc/can_lift))
	effect = /obj/structure/fitness/weightlifter/proc/interaction_hand

/// Requirement: TRUE, or why the user can't lift right now.
/obj/structure/fitness/weightlifter/proc/can_lift(mob/living/carbon/human/user, atom/target, obj/item/held)
	if(!istype(user))
		return TRUE // the effect declines silently
	if(user.loc != loc)
		return "you must be on the weight machine to use it"
	if(user.nutrition < 70) // Set minimum nutrition to be the same as in fitness_machines_vr.dm
		return "you need more energy to lift weights, go eat something"
	if(user.weight < 70) // Add weight loss to old fitness equipment
		return "you're too skinny to risk losing any more weight"
	if(om_busy(src))
		return "the weight machine is already in use by somebody else"
	return TRUE

/obj/structure/fitness/weightlifter/proc/interaction_hand(mob/living/carbon/human/user, obj/item/held, datum/interaction/interaction)
	if(!istype(user))
		return TRUE
	else
		play_sfx(src, SFX_EFFECTS_WEIGHTLIFTER)
		user.set_dir(SOUTH)
		flick("[icon_state]_[weight]", src)
		om_task_timed(user, 3 SECONDS + (weight * 10), target = src, receiver = src, on_done = PROC_REF(attack_hand_timed_done), done_args = list(user), on_fail = PROC_REF(attack_hand_timed_failed), fail_args = list(user), claims = TRUE)
	return TRUE

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

