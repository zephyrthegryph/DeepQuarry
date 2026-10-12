/obj/item/melee/chainofcommand
	name = "chain of command"
	desc = "A tool used by great men to placate the frothing masses."
	icon_state = "chain"
	w_class = ITEMSIZE_NORMAL

CAPABILITIES(/obj/item/melee/chainofcommand)
	configure(item_worn(slots = SLOT_BELT))
	configure(item_thrown(force = 7))
	configure(item_combat(force = 10, attack_verbs = list("flogged", "whipped", "lashed", "disciplined"), reach = 2))
	configure(item_sounds(hit = SFX_WEAPONS_WHIP))

/obj/item/melee/chainofcommand/curator_whip
	name = "leather whip"
	desc = "A fine weapon for some treasure hunting."
	icon_state = "curator_whip"

CAPABILITIES(/obj/item/melee/chainofcommand/curator_whip)
	configure(item_thrown(force = 5))
	configure(item_combat(force = 5))

/obj/item/melee/chainofcommand/curator_whip/toy
	name = "toy whip"
	desc = "A fake whip. Perfect for fake treasure hunting"

CAPABILITIES(/obj/item/melee/chainofcommand/curator_whip/toy)
	configure(item_thrown(force = 2))
	configure(item_combat(force = 2))

/obj/item/melee/umbrella
	name = "umbrella"
	desc = "To keep the rain off you. Use with caution on windy days."
	icon = 'icons/obj/items.dmi'
	icon_state = "umbrella_closed"
	addblends = "umbrella_closed_a"
	w_class = ITEMSIZE_NORMAL
	var/open = FALSE

TRACKED(/obj/item/melee/umbrella, open)

CAPABILITIES(/obj/item/melee/umbrella)
	configure(item_worn(slots = SLOT_BELT))
	configure(item_thrown(force = 5))
	configure(item_combat(force = 5))
	op("toggle", in_hand(), label("Open or close umbrella"), then(PROC_REF(umbrella_toggled)))

/// The native held-item activation preserves the complete equipment change.
/obj/item/melee/umbrella/proc/umbrella_toggled(datum/act/op/A)
	toggle_umbrella()
	return OP_OK

/obj/item/melee/umbrella/proc/toggle_umbrella()
	set_open(!open)
	icon_state = "umbrella_[open ? "open" : "closed"]"
	addblends = icon_state + "_a"
	item_state = icon_state
	if(ishuman(src.loc))
		var/mob/living/carbon/human/H = src.loc
		H.update_inv_l_hand(0)
		H.update_inv_r_hand()

CAPABILITIES(/obj/item/melee/umbrella/random)
	rolls(nameof(color), PROC_REF(roll_color))

/// Rolled before init (rolls()): any colour (get_random_colour()'s distribution).
/obj/item/melee/umbrella/random/proc/roll_color(datum/roller/R)
	return R.hex_colour()

/obj/item/melee/cursedblade
	name = "crystal blade"
	desc = "The red crystal blade's polished surface glints in the light, giving off a faint glow."
	icon_state = "soulblade"
	w_class = ITEMSIZE_NORMAL
	injury_kind = INJURY_CUT
	can_speak = 1
	var/list/voice_mobs //The curse of the sword is that it has someone trapped inside.

CAPABILITIES(/obj/item/melee/cursedblade)
	configure(item_worn(slots = SLOT_BELT | SLOT_BACK))
	configure(item_thrown(force = 10))
	configure(item_combat(force = 30, sharp = TRUE, edge = TRUE, attack_verbs = list("attacked", "slashed", "stabbed", "sliced", "torn", "ripped", "diced", "cut")))
	configure(item_sounds(hit = SFX_WEAPONS_BLADESLICE))
	owns_many(nameof(voice_mobs))


/obj/item/melee/cursedblade/handle_shield(mob/user, damage, atom/damage_source = null, mob/attacker = null, def_zone = null, attack_text = "the attack")
	if(default_parry_check(user, attacker, damage_source) && prob(50))
		act_message(user, src, others = span_danger("%U% parries [attack_text] with %T%!"))
		play_sfx(src, SFX_WEAPONS_PUNCHMISS, 2, extrarange = 0)
		return 1
	return 0

/obj/item/melee/cursedblade/proc/ghost_inhabit(mob/candidate)
	if(!isobserver(candidate))
		return
	//Handle moving the ghost into the new shell.
	announce_ghost_joinleave(candidate, 0, "They are occupying a cursed sword now.")
	var/mob/living/voice/new_voice = new /mob/living/voice(src) 	//Make the voice mob the ghost is going to be.
	new_voice.transfer_identity(candidate) 	//Now make the voice mob load from the ghost's active character in preferences.
	rel_set(new_voice, nameof(new_voice.mind), candidate.mind) //Transfer the mind, if any.
	new_voice.ckey = candidate.ckey			//Finally, bring the client over.
	new_voice.name = "cursed sword"			//Cursed swords shouldn't be known characters.
	new_voice.set_real_name("cursed sword")
	rel_add(src, nameof(voice_mobs), new_voice)
	registry_join(REGISTRY_LISTENING_OBJECTS, src)


/obj/item/melee/rapier
	name = "rapier"
	desc = "A gleaming steel blade with a gold handguard and inlayed with an outstanding red gem."
	icon = 'icons/obj/weapons_vr.dmi'
	icon_state = "rapier"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_melee_vr.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_melee_vr.dmi',
		)
	w_class = ITEMSIZE_NORMAL
	injury_kind = INJURY_PIERCE

CAPABILITIES(/obj/item/melee/rapier)
	configure(item_thrown(force = 10))
	configure(item_combat(force = 15, sharp = TRUE, edge = FALSE, attack_verbs = list("stabbed", "lunged at", "dextrously struck", "sliced", "lacerated", "impaled", "diced", "charioted")))
	configure(item_sounds(hit = SFX_WEAPONS_BLADESLICE))

/obj/item/melee/hammer
	name = "claw hammer"
	desc = "A simple claw hammer for hitting things or people with, and the claw part probably does something too."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "claw_hammer"
	w_class = ITEMSIZE_SMALL
	defend_chance = 0

CAPABILITIES(/obj/item/melee/hammer)
	configure(item_thrown(force = 10))
	configure(item_combat(force = 15, attack_verbs = list("smashed", "swung at", "pummelled", "nailed", "crushed", "bonked", "hammered", "cracked")))

/obj/item/melee/hammer/apply_hit_effect(mob/living/target, mob/living/user, hit_zone, attack_modifier)
	if(ishuman(target))
		var/mob/living/carbon/human/H = target
		if(prob(50))
			var/obj/item/organ/external/affecting = H.get_organ(hit_zone)
			affecting.fracture()
	return ..()

/obj/item/melee/hammer/afterattack(atom/A as mob|obj|turf|area, mob/user as mob, proximity)
	if(!proximity) return
	..()
	if(A)
		if(istype(A,/obj/structure/window))
			var/obj/structure/window/W = A
			if(prob(50))
				W.visible_message(span_warning("\The [W] shatters under the force of the impact!"))
				W.shatter()
		else if(istype(A,/obj/structure/barricade))
			var/obj/structure/barricade/B = A
			if(prob(50))
				B.visible_message(span_warning("\The [B] is broken apart with ease!"))
				B.dismantle()
		else if(istype(A,/obj/structure/grille))
			if(prob(50))
				A.visible_message(span_warning("\The [A] is smashed open!"))
				consumed(A, src)
