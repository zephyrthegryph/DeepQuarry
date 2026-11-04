/obj/item/clothing/suit/armor/reactive/repulse
	name = "reactive repulse armor"
	desc = "An experimental suit of armor that violently throws back attackers."
	cooldown_message = span_danger("The repulse generator is still recharging! It fails to generate a strong enough wave!")
	emp_message = span_warning("The repulse generator is reset to default settings...")

/obj/item/clothing/suit/armor/reactive/repulse/reactive_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", damage = 0)
	play_sfx(get_turf(owner), SFX_EFFECTS_REPULSE)
	owner.visible_message(span_danger("[src] blocks [attack_text], converting the attack into a wave of force!"))
	var/turf/owner_turf = get_turf(owner)
	var/list/thrown_items = list()
	for(var/atom/movable/repulsed in range(owner_turf, 5))
		if(repulsed == owner || repulsed.anchored || thrown_items[repulsed])
			continue
		var/throwtarget = get_edge_target_turf(owner_turf, get_dir(owner_turf, get_step_away(repulsed, owner_turf)))
		repulsed.throw_at(throwtarget, 10, 1)
		thrown_items[repulsed] = repulsed

	COOLDOWN_START(src, reactivearmor_cooldown, reactivearmor_cooldown_duration)
	return TRUE

/obj/item/clothing/suit/armor/reactive/repulse/emp_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", damage = 0)
	play_sfx(get_turf(owner), SFX_EFFECTS_REPULSE)
	owner.visible_message(span_danger("[src] does not block [attack_text], and instead generates an attracting force!"))
	var/turf/owner_turf = get_turf(owner)
	var/list/thrown_items = list()
	for(var/atom/movable/repulsed in range(owner_turf, 5))
		if(repulsed == owner || repulsed.anchored || thrown_items[repulsed])
			continue
		repulsed.throw_at(owner, 10, 1)
		thrown_items[repulsed] = repulsed

	COOLDOWN_START(src, reactivearmor_cooldown, reactivearmor_cooldown_duration)
	return FALSE
