// Makes slimes not kill (most) humanoids but still fight spiders/carp/bears/etc.
/obj/item/slimepotion/loyalty/get_mechanics_info(list/additional_information)
	return ..(list("The slime or other animal needs to be alive for this to work. The slime this is applied to will have their 'faction' change to \
	the user's faction, which means the slime will attack things that are hostile to the user's faction, such as carp, spiders, and other slimes.") + additional_information)

/obj/item/slimepotion/loyalty
	name = "slime loyalty agent"
	desc = "A potent chemical mix that makes an animal deeply loyal to the species of whoever applies this, and will attack threats to them."
	icon_state = "potlightpink"

/obj/item/slimepotion/loyalty/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M, /mob/living/simple_mob))
		to_chat(user, span_warning("The agent only works on creatures!"))
		return ..()

	if(!(kind_of(M).mob_class & (MOB_CLASS_SLIME|MOB_CLASS_ANIMAL))) // So you can't use this on Russians/syndies/hivebots/etc.
		to_chat(user, span_warning("\The [M] only works on slimes and animals."))
		return ..()
	if(M.stat == DEAD)
		to_chat(user, span_warning("The animal is dead!"))
		return ..()
	if(mob_rules_of(M).faction == mob_rules_of(user).faction)
		to_chat(user, span_warning("\The [M] is already loyal to your species!"))
		return ..()
	if(!(M.ai_brain != null))
		to_chat(user, span_warning("\The [M] is too strong-willed for this to affect them."))
		return ..()

	var/datum/ai_brain/AI = M.ai_brain

	to_chat(user, span_notice("You feed \the [M] the agent. It will now try to murder things that want to murder you instead."))
	to_chat(M, span_notice("\The [user] feeds you \the [src], and feel that the others will regard you as an outsider now."))
	M.set_faction(mob_rules_of(user).faction)
	AI.remove_target() // So hostile things stop attacking people even if not hostile anymore.
	if(istype(M, /mob/living/simple_mob/slime))
		var/mob/living/simple_mob/slime/slime = M
		slime.update_mood() //Makes them drop-nomable.
	play_sfx(src, SFX_EFFECTS_BUBBLES)
	consume(src, user)
	return ITEM_INTERACT_SUCCESS
