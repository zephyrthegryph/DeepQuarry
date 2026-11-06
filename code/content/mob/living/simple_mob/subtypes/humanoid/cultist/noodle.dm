/mob/living/simple_mob/humanoid/cultist/noodle
	drag_buckle = FALSE
	name = "Converted"
	desc = "An indiuval wrapped up in a makeshift rig, made from fallen cultist."
	icon_state = "cobra-cultist"
	icon_living = "cobra-cultist"
	endurance = 150 //Old 75


	status_flags = 0

	response_help = "pokes"
	response_disarm = "shoves"
	response_harm = "hits"

	harm_intent_damage = 5
	melee_damage_lower = 15 //old 7
	melee_damage_upper = 25 //old 15
	attack_injury_kind = INJURY_CUT
	attacktext = list("slashed", "stabbed")
	attack_sound = SFX_WEAPONS_RAPIDSLICE
	projectiletype = /obj/item/projectile/energy/plasma/vepr
	projectilesound = SFX_WEAPONS_SPIDERLUNGE
	movement_cooldown = 2

/mob/living/simple_mob/humanoid/cultist/noodle
	vore_active = 1
	vore_max_size = RESIZE_HUGE
	vore_min_size = RESIZE_SMALL
	vore_pounce_chance = 0 // Beat them into crit before eating.
	vore_icons = null

CAPABILITIES(/mob/living/simple_mob/humanoid/cultist/noodle)
	configure(atom_rules(armor_spec = "melee=60;bullet=40;laser=60;energy=80;bomb=25;bio=100;rad=100"))
	configure(mob_rules(faction = "cult"))
	configure(living_rules(vore_capacity = 6))
	profile(nameof(vore_prefs), /datum/record/vore_prefs, fields = list("can_be_drop_prey" = FALSE))
	immune_to_incapacitation()
	verb_entry(/mob/living/simple_mob/proc/animal_mount, login = TRUE) // TGPanel
	verb_entry(/mob/living/proc/toggle_rider_reins, login = TRUE) // TGPanel

/mob/living/simple_mob/humanoid/cultist/noodle/Login()
	. = ..()
	if(!riding_datum)
		rel_set(src, nameof(riding_datum), new /datum/riding/simple_mob(src))
	movement_cooldown = 1

/mob/living/simple_mob/humanoid/cultist/noodle/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected_of(src)
	B.name = "stomach"
	B.desc = " Through fire and smoke, you have been grappled and shoved head first into a gapping maw. Rippling powerful red flesh dragging deep into the mage's gullet, your frame causing their stomach is swell out against crimson robes. As you're forced to curl up in the stomach, the walls would ripple, and knead against your flesh. Laughter, and gutteral stomach noises would fill your ears as the cultist firmly kneads their hanging gut, sloshing it  further about before shoving you deeper into their system, descending deep within the serpent."

	B.own_emote_lists()
	B.set_emote_lists_at(DM_HOLD, list(
		"As you're forced to lay down in the gullet, you can feel each swift and strong movement of their tail. the stomach walls forcing your body to shift alongside it.",
		"As you shift around, the dark red flesh would ripple, air rushing past you as the beast lets out a thunderous belch.",
		"As you shift about, the beast lifts their tail and slams it down, trying to encourage you to relax. Your their's.",))

	B.own_emote_lists()
	B.set_emote_lists_at(DM_DIGEST, list(
		"Your squirming and thrasing only causes the serpent to curl their tail around your frame, squeeze down on it in sync with the muscles, pressing you further into the caustic acids.",
		"Your body would swish and slosh in the burbling caustic acid as it nips at your armor and flesh.",
		"The serpent cultist would let out a lazy out, streching, then remebers your exsistance pressing a claw into the you shaped bulge and grumbling." ,))
