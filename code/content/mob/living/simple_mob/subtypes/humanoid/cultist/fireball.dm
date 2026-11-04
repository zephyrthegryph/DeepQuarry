/mob/living/simple_mob/humanoid/cultist/human/bloodjaunt/fireball //Teleporting Cultists, now with fireballs
	name = "Burning Mage"
	desc = "An indiuval wrapped up in red robes, with orange highlights, their paws glowing.."
	icon_state = "fire-fluff"
	icon_living = "fire-fluff"
	special_attack_min_range = 4
	special_attack_max_range = 7
	special_attack_cooldown = 10 SECONDS
	movement_cooldown = 0

	harm_intent_damage = 5
	melee_damage_lower = 7
	melee_damage_upper = 7
	projectiletype = /obj/item/projectile/energy/fireball

//Nibbler//
/mob/living/simple_mob/humanoid/cultist/human/bloodjaunt/fireball
	drag_buckle = FALSE
	vore_active = 1
	vore_max_size = RESIZE_HUGE
	vore_min_size = RESIZE_SMALL
	vore_pounce_chance = 0 // Beat them into crit before eating.
	vore_icons = null

CAPABILITIES(/mob/living/simple_mob/humanoid/cultist/human/bloodjaunt/fireball)
	configure(living_rules(vore_capacity = 6))
	profile(nameof(vore_prefs), /datum/record/vore_prefs, fields = list("can_be_drop_prey" = FALSE))
	verb_entry(/mob/living/simple_mob/proc/animal_mount, login = TRUE) // TGPanel
	verb_entry(/mob/living/proc/toggle_rider_reins, login = TRUE) // TGPanel

/mob/living/simple_mob/humanoid/cultist/human/bloodjaunt/fireball/Login()
	. = ..()
	if(!riding_datum)
		rel_set(src, nameof(riding_datum), new /datum/riding/simple_mob(src))
	movement_cooldown = 1

/mob/living/simple_mob/humanoid/cultist/human/bloodjaunt/fireball/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected_of(src)
	B.name = "stomach"
	B.desc = " Through fire and smoke, you have been grappled and shoved head first into a gapping maw. Rippling powerful red flesh dragging deep into the mage's gullet, your frame causing their stomach is swell out against crimson robes. As you're forced to curl up in the stomach, the walls would ripple, flickers of orange dancing as they press and knead against your flesh. Laughter, and gutteral stomach noises would fill your ears as the cultist firmly kneads their hanging gutt, sloshing it  further about."

	B.own_emote_lists()
	B.set_emote_lists_at(DM_HOLD, list(
		"Your useless struggling and squirming only causes the cultist to pause, firmly grasping their gut and shoving down on their belly.",
		"As you lay within the gullet, you would be rocked about as the cultist jaunts around the physical and redspace realm.",
		"The bloated organ around you groans and rumbles, the flesh rippling as a wave of heat washes over you.",))

	B.own_emote_lists()
	B.set_emote_lists_at(DM_DIGEST, list(
		"Your useless struggling would seem to just cause pleasured rubblings and cackling. The taunt stomach jostling around even further, as if attempt to encourage your squirming further.",
		"Your body would be ushered upwards, you glimpsing the outside world as it looked as if you're about to be released. The cultist then gulps down, sending you plummet back down into the gullet, their taunt belly jiggling as it's walls squish firmly against you..",
		"Caustic juices splash over to you as the predator's stomach sways, the belly walls rumbling and rippling as they release a loud caustic belch." ,))
