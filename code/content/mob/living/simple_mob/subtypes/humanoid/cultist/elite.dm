/mob/living/simple_mob/humanoid/cultist/elite
	name = "Elite Cultist"
	desc = "A heavily armed cultist with a mirror shield that hurts to look at."
	icon_state = "cult_elite"
	icon_living = "cult_elite"

	status_flags = 0

	response_help = "pokes"
	response_disarm = "shoves"
	response_harm = "hits"

	harm_intent_damage = 5
	attack_injury_kind = INJURY_CUT
	attacktext = list("slashed", "stabbed")
	attack_sound = SFX_WEAPONS_BLADESLICE

CAPABILITIES(/mob/living/simple_mob/humanoid/cultist/elite)
	configure(atom_rules(armor_spec = "melee=60;bullet=50;laser=30;energy=80;bomb=30;bio=100;rad=100", catalogue_data = list(/datum/category_item/catalogue/fauna/cultist/elite)))
	configure(mob_rules(faction = "cult"))
	configure(living_rules(delete_on_death = TRUE))
	configure(mob_kind(death_message = "shatters into bone and blood like pieces like the now shattered mirror."))
	op("cultist_elite_item", item(/obj/item), then(PROC_REF(cultist_elite_interaction_item)))
	immune_to_incapacitation()

/// Old attackby: shield block.
/mob/living/simple_mob/humanoid/cultist/elite/proc/cultist_elite_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	. = OP_OK
	if(combat_of(O).force)
		if(prob(30))
			act_message(src, O, null, MSG_OTHERS(span_danger("%U% blocks %T% with its shield!")))
			if(user)
				ai_brain.react_to_attack(user)
			return
		else
			return OP_DECLINE
	else
		to_chat(user, span_warning("This weapon is ineffective, it does no damage."))
		act_message(user, src, null, MSG_OTHERS(span_warning("%U% gently taps %T% with %I%.")), item = O)

/mob/living/simple_mob/humanoid/cultist/elite/bullet_act(obj/item/projectile/Proj)
	if(!Proj)	return
	if(prob(50))
		visible_message(span_bolddanger("[Proj] disappears into the mirror world as it hits the shield."))
		if(Proj.firer)
			ai_brain.react_to_attack(Proj.firer)
		return
	else
		..()

/mob/living/simple_mob/humanoid/cultist/elite

/mob/living/simple_mob/humanoid/cultist/elite/on_death(gibbed)
	new /obj/effect/decal/remains/human (src.loc)
	new /obj/effect/decal/cleanable/blood/gibs (src.loc)
	new /obj/item/material/shard (src.loc)
	..()
	play_sfx(src, SFX_EFFECTS_GLASSBR2)
	ghostize()

/mob/living/simple_mob/humanoid/cultist/elite
	movement_cooldown = 1
	melee_damage_lower = 20
	melee_damage_upper = 20
