/obj/item/clothing/suit/armor/shield
	name = "shield projector"
	desc = "This armor has no inherent ability to absorb shock, as normal armor usually does.  Instead, this emits a strong field \
	around the wearer, designed to protect from most forms of harm, from lasers to bullets to close quarters combat.  It appears to \
	require a very potent supply of an energy of some kind in order to function."
	icon_state = "reactive"
	blood_overlay_type = "armor"
	var/active = 0
	var/damage_to_energy_multiplier = 50.0 //Determines how much energy to charge for blocking, e.g. 20 damage attack = 750 energy cost
	var/block_percentage = 75

/obj/item/clothing/suit/armor/shield/handle_shield(mob/user, damage, atom/damage_source = null, mob/attacker = null, def_zone = null, attack_text = "the attack")
	//Since this is a pierce of armor that is passive, we do not need to check if the user is incapacitated.
	if(!active)
		return 0

	var/modified_block_percentage = block_percentage

	if(issmall(user)) // Smaller shield means better protection.
		modified_block_percentage += 15

	var/damage_blocked = damage * (modified_block_percentage / 100)

	var/damage_to_energy_cost = (damage_to_energy_multiplier * damage_blocked)

	if(!user.technomancer_pay_energy(damage_to_energy_cost))
		to_chat(user, span_danger("Your shield fades due to lack of energy!"))
		set_active(FALSE)
		return 0

	damage = damage - damage_blocked

	if(istype(damage_source, /obj/item/projectile))
		var/obj/item/projectile/P = damage_source
		P.set_sharp(FALSE)
		P.set_edge(FALSE)
		P.set_embed_chance(0)
		if(P.agony)
			var/agony_blocked = P.agony * (modified_block_percentage / 100)
			P.agony -= agony_blocked
		P.damage = P.damage - damage_blocked

	act_message(user, src, others = span_danger("%U%'s %T% absorbs [attack_text]!"))
	to_chat(user, span_warning("Your shield has absorbed most of \the [damage_source]."))

	fx_sparks(src, 5, FALSE)
	play_sfx(src, SFX_WEAPONS_BLADE1)
	return 0 // This shield does not block all damage, so returning 0 is needed to tell the game to apply the new damage.

CAPABILITIES(/obj/item/clothing/suit/armor/shield)
	configure(atom_rules(armor_spec = ""))
	configure(item_worn(worn_factors = TRAIT_NONE))
	configure(item_rules(actions_types = list(/datum/action/item_action/toggle_shield_projector)))
	op("shield_armor_toggle_self", in_hand(), label("Toggle"), then(PROC_REF(shield_armor_toggle_self)))

/// Old attack_self.
/obj/item/clothing/suit/armor/shield/proc/shield_armor_toggle_self(datum/act/op/A)
	var/mob/user = A.actor
	set_active(!active)
	to_chat(user, span_notice("You [active ? "" : "de"]activate \the [src]."))
	user.update_mob_action_buttons()


/// Lit while the shield is up; the worn suit follows through the held state.
/obj/item/clothing/suit/armor/shield/draw(datum/look/look)
	..()
	look.state("shield_armor_[active]")
	look.held_state("shield_armor_[active]")
	if(active)
		look.glow(2, 1, "#006AFF")
	else
		look.glow(GLOW_OFF)
