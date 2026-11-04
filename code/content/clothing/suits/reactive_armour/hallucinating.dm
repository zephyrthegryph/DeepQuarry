// Hallucinating

/obj/item/clothing/suit/armor/reactive/hallucinating
	name = "reactive hallucinating armor"
	desc = "An experimental suit of armor with sensitive detectors hooked up to the mind of the wearer, sending mind pulses that causes hallucinations around you."
	cooldown_message = span_danger("The connection is currently out of sync... Recalibrating.")
	emp_message = span_warning("You feel the backsurge of a mind pulse.")
	clothing_traits = list(TRAIT_MADNESS_IMMUNE)

/obj/item/clothing/suit/armor/reactive/hallucinating/cooldown_activation(mob/living/carbon/human/owner)
	fx_sparks(src, 1)
	..()

/obj/item/clothing/suit/armor/reactive/hallucinating/reactive_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", damage = 0)
	owner.visible_message(span_danger("[src] blocks [attack_text], sending out mental pulses!"))
	for(var/mob/living/carbon/human/hallucinator in viewers(5, get_turf(src)))
		if(hallucinator == owner)
			continue
		hallucinator.status_adjust(STAT_HALLUCINATING, 50)
		if(prob(10))
			to_chat(hallucinator, span_danger("Your nose bleeds!"))
			hallucinator.drip(1)
	COOLDOWN_START(src, reactivearmor_cooldown, reactivearmor_cooldown_duration)
	return TRUE

/obj/item/clothing/suit/armor/reactive/hallucinating/emp_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", damage = 0)
	act_message(src, owner, others = span_danger("%U% blocks [attack_text], but pulls a massive charge of mental energy into %T% from the surrounding environment!"))
	owner.status_adjust(STAT_HALLUCINATING, 75)
	to_chat(owner, span_danger("Your nose bleeds!"))
	owner.drip(1)
	COOLDOWN_START(src, reactivearmor_cooldown, reactivearmor_cooldown_duration)
	return TRUE
