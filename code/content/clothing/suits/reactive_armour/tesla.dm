// Tesla

/obj/item/clothing/suit/armor/reactive/tesla
	name = "reactive tesla armor"
	desc = "An experimental suit of armor with sensitive detectors hooked up to a huge capacitor grid, with emitters strutting out of it. Zap."
	cooldown_message = span_danger("The tesla capacitors on the reactive tesla armor are still recharging! The armor merely emits some sparks.")
	emp_message = span_warning("The tesla capacitors beep ominously for a moment.")
	clothing_traits = list(TRAIT_TESLA_SHOCKIMMUNE)
	/// How strong are the zaps we give off?
	var/zap_power = 2.5e4
	/// How far to the zaps we give off go?
	var/zap_range = 20

CAPABILITIES(/obj/item/clothing/suit/armor/reactive/tesla)
	configure(item_protection(siemens = -1))

/obj/item/clothing/suit/armor/reactive/tesla/cooldown_activation(mob/living/carbon/human/owner)
	fx_sparks(src, 1)
	..()

/obj/item/clothing/suit/armor/reactive/tesla/reactive_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", damage = 0)
	owner.visible_message(span_danger("[src] blocks [attack_text], sending out arcs of lightning!"))
	tesla_zap(owner, zap_range, zap_power, current_jumps = 1)
	COOLDOWN_START(src, reactivearmor_cooldown, reactivearmor_cooldown_duration)
	return TRUE

/obj/item/clothing/suit/armor/reactive/tesla/emp_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", damage = 0)
	act_message(src, owner, others = span_danger("%U% blocks [attack_text], but pulls a massive charge of energy into %T% from the surrounding environment!"))
	REMOVE_CLOTHING_TRAIT(owner, TRAIT_TESLA_SHOCKIMMUNE)
	electrocute_mob(owner, get_area(src), src, 1)
	ADD_CLOTHING_TRAIT(owner, TRAIT_TESLA_SHOCKIMMUNE)
	COOLDOWN_START(src, reactivearmor_cooldown, reactivearmor_cooldown_duration)
	return TRUE
