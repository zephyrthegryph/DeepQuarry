/mob/living/simple_mob/humanoid/cultist/castertesh
	drag_buckle = FALSE
	name = "Teshari Mage"
	desc = "This Teshari seems to have forsoken weapons for unfanthomable power."
	icon_state = "castertesh"
	icon_living = "castertesh"


	status_flags = 0

	response_help = "pokes"
	response_disarm = "shoves"
	response_harm = "hits"

	harm_intent_damage = 5
	attack_injury_kind = INJURY_CUT
	attacktext = list("slashed", "stabbed")
	attack_sound = SFX_WEAPONS_RAPIDSLICE
	projectilesound = SFX_WEAPONS_SPIDERLUNGE

/mob/living/simple_mob/humanoid/cultist/castertesh

/mob/living/simple_mob/humanoid/cultist/castertesh/on_death(gibbed)
	new /obj/effect/decal/cleanable/ash (src.loc)
	..()
	ghostize()

/mob/living/simple_mob/humanoid/cultist/castertesh
	movement_cooldown = -1
	projectiletype = /obj/item/projectile/energy/inversion
	melee_damage_lower = 15
	melee_damage_upper = 15
	endurance = 50

/mob/living/simple_mob/humanoid/cultist/castertesh
	vore_active = 1
	vore_max_size = RESIZE_HUGE
	vore_min_size = RESIZE_SMALL
	vore_pounce_chance = 0 // Beat them into crit before eating.
	vore_icons = null

CAPABILITIES(/mob/living/simple_mob/humanoid/cultist/castertesh)
	configure(atom_rules(armor_spec = "melee=35;bullet=20;laser=35;energy=60;bomb=20;bio=100;rad=100", catalogue_data = list(/datum/category_item/catalogue/fauna/cultist/castertesh)))
	configure(mob_rules(faction = "cult"))
	configure(living_rules(vore_capacity = 6, delete_on_death = TRUE))
	profile(nameof(vore_prefs), /datum/record/vore_prefs, fields = list("can_be_drop_prey" = FALSE))
	configure(mob_kind(attack_cooldown = 7.5, death_message = "burns away into nothing."))
	immune_to_incapacitation()
	verb_entry(/mob/living/simple_mob/proc/animal_mount, login = TRUE) // TGPanel
	verb_entry(/mob/living/proc/toggle_rider_reins, login = TRUE) // TGPanel

/mob/living/simple_mob/humanoid/cultist/castertesh/Login()
	. = ..()
	if(!riding_datum)
		rel_set(src, nameof(riding_datum), new /datum/riding/simple_mob(src))
	movement_cooldown = 1

/mob/living/simple_mob/humanoid/cultist/castertesh/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected_of(src)
	B.name = "stomach"
	B.desc = "Not too long after you hit the ground the caster makes their way to your fallen self.  The ground below you glows a deep red and you sink through the surface, only to find yourself folded tightly in a cramped, slick, and caustic chamber! The mage's chanting barely audible over the sounds of the stomach walls making their claim."

	B.own_emote_lists()
	B.set_emote_lists_at(DM_HOLD, list(
		"Your body is bounced and jostled as the %pred purses their next prey.  Unimpeded by your weight and eager for more.",
		"The already oprrssive hold of the %belly restrains you with a heavy clench and squeeze from the hands outside. The %pred securing their catch.",
		"You're given a heavy squeeze as the stale air is forced out from the %pred giving a crass belch.  Suspending you in a claustrophobic hold until the organ relaxes with more stale air filling the space.",))

	B.own_emote_lists()
	B.set_emote_lists_at(DM_DIGEST, list(
		"The bubbling of the carnivorous, little predator's belly cuts off the sounds outside, the greedy walls working in and giving you a fresh coat of enzymes.",
		"The %pred traces their claws over your form and sings an incantation, and you feel your strength wane as the walls work in with renewed vigor.",
		"The motion of the %pred's trotting sloshes and sways you from side to side, occasionally coating you in more hot fluids! Eating away your stamina with irragular flexes to allow them to keep eating you away." ,))
