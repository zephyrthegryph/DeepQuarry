// FIRE
/obj/item/clothing/suit/armor/reactive/fire
	name = "reactive incendiary armor"
	desc = "An experimental suit of armor with a reactive sensor array rigged to a flame emitter. For the stylish pyromaniac."
	cooldown_message = span_danger("The reactive incendiary armor activates, but fails to send out flames as it is still recharging its flame jets!")
	emp_message = span_warning("The reactive incendiary armor's targeting system begins rebooting...")

/obj/item/clothing/suit/armor/reactive/fire/reactive_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", damage = 0)
	owner.visible_message(span_danger("[src] blocks [attack_text], sending out jets of flame!"))
	play_sfx(get_turf(owner), SFX_MAGIC_FIREBALL)
	for(var/mob/living/carbon_victim in range(6, get_turf(src)))
		if(carbon_victim != owner)
			carbon_victim.adjust_fire_stacks(8)
			carbon_victim.ignite_mob()
	owner.set_wet_stacks(20)
	COOLDOWN_START(src, reactivearmor_cooldown, reactivearmor_cooldown_duration)
	return TRUE

/obj/item/clothing/suit/armor/reactive/fire/emp_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", damage = 0)
	act_message(src, owner, others = span_danger("%U% just makes [attack_text] worse by spewing molten death on %T%!"))
	play_sfx(get_turf(owner), SFX_MAGIC_FIREBALL)
	owner.adjust_fire_stacks(12)
	owner.ignite_mob()
	COOLDOWN_START(src, reactivearmor_cooldown, reactivearmor_cooldown_duration)
	return FALSE
