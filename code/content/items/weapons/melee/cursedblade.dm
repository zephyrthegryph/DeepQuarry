/obj/item/melee/cursedblade
	name = "crystal blade"
	desc = "The red crystal blade's polished surface glints in the light, giving off a faint glow."
	icon_state = "soulblade"
	w_class = ITEMSIZE_NORMAL
	var/list/voice_mobs //The curse of the sword is that it has someone trapped inside.

CAPABILITIES(/obj/item/melee/cursedblade)
	configure(item_combat(injury_kind = INJURY_CUT))
	configure(obj_rules(can_speak = TRUE))
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
	bind_player(new_voice, candidate.ckey, as_ckey = TRUE)			//Finally, bring the client over.
	new_voice.name = "cursed sword"			//Cursed swords shouldn't be known characters.
	new_voice.set_real_name("cursed sword")
	rel_add(src, nameof(voice_mobs), new_voice)
	registry_join(REGISTRY_LISTENING_OBJECTS, src)
