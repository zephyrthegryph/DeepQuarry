// When the wearer gets hit, this armor will push people nearby and spawn some blocking objects.
/obj/item/clothing/suit/armor/reactive/barricade
	name = "reactive barricade armor"
	desc = "An experimental suit of armor that generates barriers from another world when it detects its bearer is in danger."
	emp_message = span_warning("The reactive armor's dimensional coordinates are scrambled!")
	cooldown_message = span_danger("The reactive barrier system is still recharging! It fails to activate!")
	reactivearmor_cooldown_duration = 10 SECONDS

/obj/item/clothing/suit/armor/reactive/barricade/reactive_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", damage = 0)
	play_sfx(get_turf(owner), SFX_EFFECTS_REPULSE)
	owner.visible_message(span_danger("The reactive armor interposes matter from another world between [src] and [attack_text]!"))
	for (var/atom/movable/target in repulse_targets(owner))
		repulse(target, owner)

	var/datum/armour_dimensional_theme/theme = dq_proto(/datum/armour_dimensional_theme)
	theme.apply_random(get_turf(owner), dangerous = FALSE)

	COOLDOWN_START(src, reactivearmor_cooldown, reactivearmor_cooldown_duration)
	return TRUE

/obj/item/clothing/suit/armor/reactive/barricade/proc/repulse_targets(atom/source)
	var/list/push_targets = list()
	for (var/atom/movable/nearby_movable in view(1, source))
		if(nearby_movable == source)
			continue
		if(nearby_movable.anchored)
			continue
		push_targets += nearby_movable
	return push_targets

/obj/item/clothing/suit/armor/reactive/barricade/proc/repulse(atom/movable/victim, atom/source)
	var/dist_from_caster = get_dist(victim, source)

	if(dist_from_caster == 0)
		return

	if (isliving(victim))
		to_chat(victim, span_userdanger("You're thrown back by a wave of pressure!"))
	var/turf/throwtarget = get_edge_target_turf(source, get_dir(source, get_step_away(victim, source, 1)))
	victim.throw_at(throwtarget, 1, 1)

/obj/item/clothing/suit/armor/reactive/barricade/emp_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", damage = 0)
	owner.visible_message(span_danger("The reactive armor shunts matter from an unstable dimension!"))
	var/datum/armour_dimensional_theme/theme = dq_proto(/datum/armour_dimensional_theme)
	theme.apply_random(get_turf(owner), dangerous = TRUE)
	COOLDOWN_START(src, reactivearmor_cooldown, reactivearmor_cooldown_duration)
	return FALSE
