/mob/living/simple_mob/humanoid/cultist/tesh
	drag_buckle = FALSE
	name = "cultist"
	desc = "A sinister looking hooded Teshari armed with a curved knife."
	icon_state = "culttesh"
	icon_living = "culttesh"


	status_flags = 0

	response_help = "pokes"
	response_disarm = "shoves"
	response_harm = "hits"

	harm_intent_damage = 5
	attack_armor_pen = 25
	attack_injury_kind = INJURY_CUT
	attacktext = list("slashed", "stabbed")
	attack_sound = SFX_WEAPONS_BLADESLICE

/mob/living/simple_mob/humanoid/cultist/tesh

/mob/living/simple_mob/humanoid/cultist/tesh/on_death(gibbed)
	new /obj/effect/decal/cleanable/ash (src.loc)
	..()
	ghostize()

/mob/living/simple_mob/humanoid/cultist/tesh
	movement_cooldown = -1
	melee_damage_lower = 15 //Old 7
	melee_damage_upper = 15
	endurance = 37

//Thank you Ears for the teshari bellies
/mob/living/simple_mob/humanoid/cultist/tesh
	vore_active = 1
	vore_max_size = RESIZE_HUGE
	vore_min_size = RESIZE_SMALL
	vore_pounce_chance = 0 // Beat them into crit before eating.
	vore_icons = null

CAPABILITIES(/mob/living/simple_mob/humanoid/cultist/tesh)
	configure(atom_rules(armor_spec = "melee=45;bullet=40;laser=30;energy=80;bomb=20;bio=100;rad=100", catalogue_data = list(/datum/category_item/catalogue/fauna/cultist/tesh)))
	configure(mob_rules(faction = "cult"))
	configure(living_rules(vore_capacity = 6, delete_on_death = TRUE))
	profile(nameof(vore_prefs), /datum/record/vore_prefs, fields = list("can_be_drop_prey" = FALSE))
	configure(mob_kind(death_message = "let's out a shrill chirp as his body turns to dust."))
	immune_to_incapacitation()
	verb_entry(/mob/living/simple_mob/proc/animal_mount, login = TRUE) // TGPanel
	verb_entry(/mob/living/proc/toggle_rider_reins, login = TRUE) // TGPanel

/mob/living/simple_mob/humanoid/cultist/tesh/Login()
	. = ..()
	if(!riding_datum)
		rel_set(src, nameof(riding_datum), new /datum/riding/simple_mob(src))
	movement_cooldown = 1

/mob/living/simple_mob/humanoid/cultist/tesh/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected_of(src)
	B.name = "stomach"
	B.desc = "Taking advantage of your weakened state, the %pred makes their pounce! The world going dark as the ravenous Teshari forces your battered frame down their throat. It all coming to a stop as you're packed neatly into their steaming guts. Low and content chuckling barely audible over the rising cacophony of the stomach's activity."

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
