/obj/item/clothing/suit/armor/reactive
	name = "reactive armor"
	desc = "Doesn't seem to do much for some reason."
	icon_state = "reactiveoff"
	blood_overlay_type = "armor"
	var/hit_reaction_chance = 50
	///Whether the armor will try to react to hits (is it on)
	var/active = FALSE
	///This will be true for 30 seconds after an EMP, it makes the reaction effect dangerous to the user.
	COOLDOWN_DECLARE(bad_effect)
	///Message sent when the armor is emp'd. It is not the message for when the emp effect goes off.
	var/emp_message = span_warning("The reactive armor has been emp'd! Damn, now it's REALLY gonna not do much!")
	///Message sent when the armor is still on cooldown, but activates.
	var/cooldown_message = span_danger("The reactive armor fails to do much, as it is recharging! From what? Only the reactive armor knows.")
	///Duration of the cooldown specific to reactive armor for when it can activate again.
	var/reactivearmor_cooldown_duration = 10 SECONDS
	///The cooldown itself of the reactive armor for when it can activate again.
	var/reactivearmor_cooldown = 0

	special_handling = TRUE

/// The armour shows its state: "reactive" while active, "reactiveoff" when not.
/obj/item/clothing/suit/armor/reactive/draw(datum/look/look)
	..()
	look.state("reactive[active ? "" : "off"]")

CAPABILITIES(/obj/item/clothing/suit/armor/reactive)
	configure(atom_rules(armor_spec = "melee=40;bullet=35;laser=35;energy=10;bomb=10"))
	op("toggle", in_hand(), label("Toggle"), then(PROC_REF(reactive_toggled)))
	on_notice(/datum/notice/hit/emp, then(PROC_REF(reactive_emp_glitch)))

/obj/item/clothing/suit/armor/reactive/proc/reactive_toggled(datum/act/op/A)
	var/mob/user = A.actor
	set_active(!active)
	to_chat(user, span_notice("[src] is now [active ? "active" : "inactive"]."))
	add_fingerprint(user)

/obj/item/clothing/suit/armor/reactive/handle_shield(mob/user, damage, atom/damage_source, mob/attacker, def_zone, attack_text)
	if(!active || !prob(hit_reaction_chance))
		return FALSE
	if(!COOLDOWN_FINISHED(src, reactivearmor_cooldown))
		cooldown_activation(user)
		return FALSE
	if(!COOLDOWN_FINISHED(src, bad_effect))
		return emp_activation(user, damage_source, attack_text, damage)
	else
		return reactive_activation(user, damage_source, attack_text, damage)

/obj/item/clothing/suit/armor/reactive/proc/cooldown_activation(mob/living/carbon/human/owner)
	owner.visible_message(cooldown_message)

/obj/item/clothing/suit/armor/reactive/proc/reactive_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", damage = 0)
	owner.visible_message(span_danger("The reactive armor doesn't do much! No surprises here."))
	return TRUE

/obj/item/clothing/suit/armor/reactive/proc/emp_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", damage = 0)
	owner.visible_message(span_danger("The reactive armor doesn't do much, despite being emp'd! Besides giving off a special message, of course."))
	return TRUE

/// A pulse makes active armour act up (at most once per cooldown).
/obj/item/clothing/suit/armor/reactive/proc/reactive_emp_glitch(datum/act/A)
	if(!COOLDOWN_FINISHED(src, bad_effect) || !active)
		return
	visible_message(emp_message)
	COOLDOWN_START(src, bad_effect, 30 SECONDS)

// Sure we could, but- Not really THAT useful. Give them the stealth one.
/obj/item/clothing/suit/armor/reactive/bioscrambling
