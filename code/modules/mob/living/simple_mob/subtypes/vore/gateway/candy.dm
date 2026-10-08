//Cataloguer things
/datum/category_item/catalogue/fauna/livingcandy
	name = "Living Candy"
	desc = "Upon investigation of the strange creatures, a mix of \
	promethean biology alongside various candies can be found. The purpose \
	of such a creation is unknown but it seems to function at a middle ground \
	between slimes and prometheans. Lacking the full sentience of prometheans  \
	but their presence bolstering others of their kind."
	value = CATALOGUER_REWARD_MEDIUM

//Someone remind me to get someone to make actual sprites for this things. //Combat refactor walkback wont touch these, idk the balance and afaik theyre a swarm mob
/mob/living/simple_mob/vore/candy
	name = "candy critter"
	desc = "A creature made of candy"
	icon = 'icons/mob/candy.dmi'
	icon_state = "drone0"
	icon_living = "drone0"
	icon_dead = "drone0"
	catalogue_data = list(/datum/category_item/catalogue/fauna/livingcandy)

	mob_class = MOB_CLASS_ABERRATION

	faction = "candy"

	endurance = 20
	movement_cooldown = 2
	melee_attack_delay = 2 SECOND
	can_be_drop_prey = TRUE
	unsuitable_atoms_damage = 0
	melee_miss_chance = 0

	melee_damage_lower = 8
	melee_damage_upper = 15
	damage_fatigue_mult = 0 //Candy creatures. They will fight to the bitter end unaffected by their wounds. Also they have 25 health, do they really need slowdown?

/mob/living/simple_mob/vore/candy
	vore_active = 1
	vore_capacity = 6
	vore_max_size = RESIZE_HUGE
	vore_min_size = RESIZE_SMALL
	vore_pounce_chance = 0 // Beat them into crit before eating.
	vore_icons = null

	can_be_drop_prey = TRUE

//bluenom
CAPABILITIES(/mob/living/simple_mob/vore/candy/bluecabold)
	verb_entry(/mob/living/simple_mob/proc/animal_mount, login = TRUE) // TGPanel
	verb_entry(/mob/living/proc/toggle_rider_reins, login = TRUE) // TGPanel

/mob/living/simple_mob/vore/candy/bluecabold/Login()
	. = ..()
	if(!riding_datum)
		rel_set(src, nameof(riding_datum), new /datum/riding/simple_mob(src))
	movement_cooldown = 1

/mob/living/simple_mob/vore/candy/bluecabold/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected
	B.name = "stomach"
	B.desc = "The fearsome predator gets a firm grip upon you, before dunking you into it's maw, then with a powerful swift gulp you're sent tumbling into it's stomach."

	B.own_emote_lists()
	B.emote_lists[DM_HOLD] = list(
		"Your surroundings are momentarily filled with your predator's pleased rumbling, its hands stroking over the taut swell you make in its belly.",)

	B.own_emote_lists()
	B.emote_lists[DM_DIGEST] = list(
		"Every clench of the predator's stomach grinds powerful digestive fluids into your body, forcibly churning away your strength!")

//rednom
CAPABILITIES(/mob/living/simple_mob/vore/candy/redcabold)
	verb_entry(/mob/living/simple_mob/proc/animal_mount, login = TRUE) // TGPanel
	verb_entry(/mob/living/proc/toggle_rider_reins, login = TRUE) // TGPanel

/mob/living/simple_mob/vore/candy/redcabold/Login()
	. = ..()
	if(!riding_datum)
		rel_set(src, nameof(riding_datum), new /datum/riding/simple_mob(src))
	movement_cooldown = 1

/mob/living/simple_mob/vore/candy/redcabold/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected
	B.name = "stomach"
	B.desc = "The fearsome predator gets a firm grip upon you, before dunking you into it's maw, then with a powerful swift gulp you're sent tumbling into it's stomach."

	B.own_emote_lists()
	B.emote_lists[DM_HOLD] = list(
		"Your surroundings are momentarily filled with your predator's pleased rumbling, its hands stroking over the taut swell you make in its belly.",)

	B.own_emote_lists()
	B.emote_lists[DM_DIGEST] = list(
		"Every clench of the predator's stomach grinds powerful digestive fluids into your body, forcibly churning away your strength!")

//yellow
CAPABILITIES(/mob/living/simple_mob/vore/candy/yellowcabold)
	verb_entry(/mob/living/simple_mob/proc/animal_mount, login = TRUE) // TGPanel
	verb_entry(/mob/living/proc/toggle_rider_reins, login = TRUE) // TGPanel

/mob/living/simple_mob/vore/candy/yellowcabold/Login()
	. = ..()
	if(!riding_datum)
		rel_set(src, nameof(riding_datum), new /datum/riding/simple_mob(src))
	movement_cooldown = 1

/mob/living/simple_mob/vore/candy/yellowcabold/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected
	B.name = "stomach"
	B.desc = "The fearsome predator gets a firm grip upon you, before dunking you into it's maw, then with a powerful swift gulp you're sent tumbling into it's stomach."

	B.own_emote_lists()
	B.emote_lists[DM_HOLD] = list(
		"Your surroundings are momentarily filled with your predator's pleased rumbling, its hands stroking over the taut swell you make in its belly.",)

	B.own_emote_lists()
	B.emote_lists[DM_DIGEST] = list(
		"Every clench of the predator's stomach grinds powerful digestive fluids into your body, forcibly churning away your strength!")

//orange
CAPABILITIES(/mob/living/simple_mob/vore/candy/orangecabold)
	verb_entry(/mob/living/simple_mob/proc/animal_mount, login = TRUE) // TGPanel
	verb_entry(/mob/living/proc/toggle_rider_reins, login = TRUE) // TGPanel

/mob/living/simple_mob/vore/candy/orangecabold/Login()
	. = ..()
	if(!riding_datum)
		rel_set(src, nameof(riding_datum), new /datum/riding/simple_mob(src))
	movement_cooldown = 1

/mob/living/simple_mob/vore/candy/orangecabold/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected
	B.name = "stomach"
	B.desc = "The fearsome predator gets a firm grip upon you, before dunking you into it's maw, then with a powerful swift gulp you're sent tumbling into it's stomach."

	B.own_emote_lists()
	B.emote_lists[DM_HOLD] = list(
		"Your surroundings are momentarily filled with your predator's pleased rumbling, its hands stroking over the taut swell you make in its belly.",)

	B.own_emote_lists()
	B.emote_lists[DM_DIGEST] = list(
		"Every clench of the predator's stomach grinds powerful digestive fluids into your body, forcibly churning away your strength!")

//purplenom
CAPABILITIES(/mob/living/simple_mob/vore/candy/purplecabold)
	verb_entry(/mob/living/simple_mob/proc/animal_mount, login = TRUE) // TGPanel
	verb_entry(/mob/living/proc/toggle_rider_reins, login = TRUE) // TGPanel

/mob/living/simple_mob/vore/candy/purplecabold/Login()
	. = ..()
	if(!riding_datum)
		rel_set(src, nameof(riding_datum), new /datum/riding/simple_mob(src))
	movement_cooldown = 1

/mob/living/simple_mob/vore/candy/purplecabold/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected
	B.name = "stomach"
	B.desc = "The fearsome predator gets a firm grip upon you, before dunking you into it's maw, then with a powerful swift gulp you're sent tumbling into it's stomach."

	B.own_emote_lists()
	B.emote_lists[DM_HOLD] = list(
		"Your surroundings are momentarily filled with your predator's pleased rumbling, its hands stroking over the taut swell you make in its belly.",)

	B.own_emote_lists()
	B.emote_lists[DM_DIGEST] = list(
		"Every clench of the predator's stomach grinds powerful digestive fluids into your body, forcibly churning away your strength!")

//marshmellownom
CAPABILITIES(/mob/living/simple_mob/vore/candy/marshmellowserpent)
	verb_entry(/mob/living/simple_mob/proc/animal_mount, login = TRUE) // TGPanel
	verb_entry(/mob/living/proc/toggle_rider_reins, login = TRUE) // TGPanel

/mob/living/simple_mob/vore/candy/marshmellowserpent/Login()
	. = ..()
	if(!riding_datum)
		rel_set(src, nameof(riding_datum), new /datum/riding/simple_mob(src))
	movement_cooldown = 1

/mob/living/simple_mob/vore/candy/marshmellowserpent/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected
	B.name = "stomach"
	B.desc = "The fearsome predator gets a firm grip upon you, before dunking you into it's maw, then with a powerful swift gulp you're sent tumbling into it's stomach."

	B.own_emote_lists()
	B.emote_lists[DM_HOLD] = list(
		"Your surroundings are momentarily filled with your predator's pleased rumbling, its hands stroking over the taut swell you make in its belly.",)

	B.own_emote_lists()
	B.emote_lists[DM_DIGEST] = list(
		"Every clench of the predator's stomach grinds powerful digestive fluids into your body, forcibly churning away your strength!")

/mob/living/simple_mob/vore/candy/bluecabold //Adds protection
	name = "gummy kobold"
	desc = "A creature made of candy"
	icon_state = "blue"
	icon_living = "blue"
	icon_dead = "blue_dead"

	melee_damage_lower = 7
	melee_damage_upper = 12

/mob/living/simple_mob/vore/candy/bluecabold/life_special_due()
	return TRUE

/mob/living/simple_mob/vore/candy/bluecabold/life_special(datum/seq_frame/life/F)
	if(src.stat != DEAD)
		src.buff_aura()
	..()

/mob/living/simple_mob/vore/candy/bluecabold/proc/buff_aura()
	for(var/mob/living/L in view(src, 2))
		if(L.stat == DEAD || !IIsAlly(L))
			continue
		L.apply_body_effect(/datum/body_effect/aura/candy_blue, null, src)

/mob/living/simple_mob/vore/candy/redcabold //Tanky boi
	name = "gummy kobold"
	desc = "A creature made of candy"
	icon_state = "red"
	icon_living = "red"
	icon_dead = "red_dead"

	endurance = 50

	melee_damage_lower = 15
	melee_damage_upper = 25

/mob/living/simple_mob/vore/candy/redcabold/apply_melee_effects(atom/A, stance = I_HURT)
	..()

	if(isliving(A) && stance == I_HURT)
		var/mob/living/L = A
		if(L.mob_size <= MOB_MEDIUM)
			act_message(src, L, null, MSG_OTHERS(span_danger("%U% sends %T% flying with the impact!")))
			play_sfx(src, SFX_PUNCH)
			L.status_at_least(STAT_WEAKENED, 1)
			var/throwdir = get_dir(src, L)
			L.throw_at(get_edge_target_turf(L, throwdir), 3, 1, src)
		else
			to_chat(L, span_warning("\The [src] hits you with incredible force, but you remain in place."))
			act_message(src, L, null, MSG_OTHERS(span_danger("%U% hits %T% with incredible force, to no visible effect!"))) // Visible/audible feedback for *resisting* the slam.
			play_sfx(src, SFX_PUNCH)

/mob/living/simple_mob/vore/candy/yellowcabold //Speeds folks
	name = "gummy kobold"
	desc = "A creature made of candy"
	icon_state = "yellow"
	icon_living = "yellow"
	icon_dead = "yellow_dead"

	melee_damage_lower = 8
	melee_damage_upper = 15

/mob/living/simple_mob/vore/candy/yellowcabold/life_special_due()
	return TRUE

/mob/living/simple_mob/vore/candy/yellowcabold/life_special(datum/seq_frame/life/F)
	if(src.stat != DEAD)
		src.buff_aura()
	..()

/mob/living/simple_mob/vore/candy/yellowcabold/proc/buff_aura()
	for(var/mob/living/L in view(src, 2))
		if(L.stat == DEAD || !IIsAlly(L))
			continue
		L.apply_body_effect(/datum/body_effect/aura/candy_yellow, null, src)

/mob/living/simple_mob/vore/candy/orangecabold //Increase melee damage
	name = "gummy kobold"
	desc = "A creature made of candy"
	icon_state = "orange"
	icon_living = "orange"
	icon_dead = "orange_dead"

	melee_damage_lower = 7
	melee_damage_upper = 12

/mob/living/simple_mob/vore/candy/orangecabold/life_special_due()
	return TRUE

/mob/living/simple_mob/vore/candy/orangecabold/life_special(datum/seq_frame/life/F)
	if(src.stat != DEAD)
		src.buff_aura()
	..()

/mob/living/simple_mob/vore/candy/orangecabold/proc/buff_aura()
	for(var/mob/living/L in view(src, 2))
		if(L.stat == DEAD || !IIsAlly(L))
			continue
		L.apply_body_effect(/datum/body_effect/aura/candy_orange, null, src)

/mob/living/simple_mob/vore/candy/purplecabold //Heals folks
	name = "gummy kobold"
	desc = "A creature made of candy"
	icon_state = "purple"
	icon_living = "purple"
	icon_dead = "purple_dead"

	melee_damage_lower = 7
	melee_damage_upper = 12

/mob/living/simple_mob/vore/candy/purplecabold/life_special_due()
	return TRUE

/mob/living/simple_mob/vore/candy/purplecabold/life_special(datum/seq_frame/life/F)
	if(src.stat != DEAD)
		src.buff_aura()
	..()

/mob/living/simple_mob/vore/candy/purplecabold/proc/buff_aura()
	for(var/mob/living/L in view(src, 2))
		if(L.stat == DEAD || !IIsAlly(L))
			continue
		L.apply_body_effect(/datum/body_effect/aura/candy_purple, null, src)

/mob/living/simple_mob/vore/candy/greencabold //Nyoooooom
	name = "gummy kobold"
	desc = "A creature made of candy"
	icon_state = "green"
	icon_living = "green"
	icon_dead = "green_dead"

	movement_cooldown = -1

	melee_attack_delay = 1 SECOND
	melee_damage_lower = 7
	melee_damage_upper = 12

/mob/living/simple_mob/vore/candy/greencabold/apply_melee_effects(atom/A)
	if(isliving(A))
		var/mob/living/L = A
		L.apply_body_effect(/datum/body_effect/deep_wounds, 15 SECONDS)


/mob/living/simple_mob/vore/candy/marshmellowserpent //Long range grab
	name = "marshmellow serpent"
	desc = "A creature made of candy"
	icon_state = "marshmellow"
	icon_living = "marshmellow"
	icon_dead = "marshmellow_dead"


	melee_damage_lower = 4
	melee_damage_upper = 8

	special_attack_min_range = 1
	special_attack_max_range = 14
	special_attack_cooldown = 10

	loot_list = list(/obj/item/clothing/head/psy_crown/candycrown = 30,
			/obj/item/clothing/gloves/stamina = 30,
			/obj/item/clothing/suit/armor/buffvest = 30,
			/obj/item/melee/cullingcane = 30
			)

/mob/living/simple_mob/vore/candy/marshmellowserpent/do_special_attack(atom/A, stance)
	ai_busy_begin()
	do_windup_animation(A, 20)
	after(src, 2 SECONDS, PROC_REF(chargeend), with = list(A), keeps_dead = TRUE)

/mob/living/simple_mob/vore/candy/marshmellowserpent/proc/chargeend(atom/A)
	if(stat) //you are dead
		ai_busy_end()
		return
	play_sfx(src, SFX_VORE_SUNESOUND_PRED_SCHLORP)
	var/obj/item/projectile/beam/appendage/appendage_attack = new /obj/item/projectile/beam/appendage(get_turf(loc))
	appendage_attack.old_style_target(A, src)
	appendage_attack.launch_projectile(A, BP_TORSO, src)
	ai_busy_end()
//Modifiers
/datum/body_effect/aura/candy_purple //Healz
	name = "candy_purple"
	desc = "You feel somewhat gooey."
	stacks = MODIFIER_STACK_FORBID
	aura_max_distance = 5

/datum/body_effect/aura/candy_purple/on_tick(mob/living/L)
	if(L.stat == DEAD)
		L.end_body_effect(type)
		return

	if(ishuman(L)) // Every limb, organic or robotic.
		var/mob/living/carbon/human/H = L
		for(var/obj/item/organ/external/E as anything in H.organs)
			H.mend(TREAT_TISSUE_REPAIR, 2, E.organ_tag)
			H.mend(TREAT_BURN_CARE, 2, E.organ_tag)
			H.mend(TREAT_PLATING_REPAIR, 2, E.organ_tag)
			H.mend(TREAT_WIRING_REPAIR, 2, E.organ_tag)
	else
		L.mend(TREAT_TISSUE_REPAIR, 2)
		L.mend(TREAT_BURN_CARE, 2)
		L.mend(TREAT_PLATING_REPAIR, 2)
		L.mend(TREAT_WIRING_REPAIR, 2)

	L.mend(TREAT_ANTITOXIN, 1)

/datum/body_effect/aura/candy_orange //melee+
	name = "candy orange"
	desc = "You feel somewhat gooey."
	stacks = MODIFIER_STACK_FORBID
	aura_max_distance = 5
	factors = alist(BF_MELEE_DAMAGE = 1.5)

/datum/body_effect/aura/candy_yellow //speed
	name = "candy yellow"
	desc = "You feel somewhat gooey."
	stacks = MODIFIER_STACK_FORBID
	aura_max_distance = 5
	factors = alist(BF_SLOWDOWN = -1)

/datum/body_effect/aura/candy_blue //defense
	name = "candy blue"
	desc = "You feel somewhat gooey."
	stacks = MODIFIER_STACK_FORBID
	aura_max_distance = 5
	factors = alist(BF_INCOMING_ALL = 0.9)

//Boss Fight
/mob/living/simple_mob/vore/candy/ouroboros
	name = "candy critter"
	desc = "A creature made of candy"
	icon = 'icons/mob/candy.dmi'
	icon_state = "ouroboros"
	icon_living = "ouroboros"
	icon_dead = "slainouroboros"
	catalogue_data = list(/datum/category_item/catalogue/fauna/livingcandy)

	mob_class = MOB_CLASS_ABERRATION

	faction = "candy"
	icon_state = "ouroboros"
	icon_living = "ouroboros"
	icon_dead = "slainouroboros"

	endurance = 200
	armor_spec = "melee=30;bullet=30;laser=30;energy=30;bomb=20;bio=100;rad=100" //armor cause boss
	movement_cooldown = 0
	melee_attack_delay = 1 SECOND
	can_be_drop_prey = TRUE
	unsuitable_atoms_damage = 0

	melee_damage_lower = 25
	melee_damage_upper = 35
	var/grenade_type = /obj/item/grenade/concussion
	var/grenade_timer = 1

	special_attack_min_range = 1
	special_attack_max_range = 15
	special_attack_cooldown = 7 SECONDS

CAPABILITIES(/mob/living/simple_mob/vore/candy/ouroboros)
	on_notice(/datum/notice/hit/projectile, then(PROC_REF(shed_critter)))

/mob/living/simple_mob/vore/candy/ouroboros/proc/shed_critter(datum/act/A)
	if(prob(50))
		new /obj/random/mob/candycritter (src.loc)

/mob/living/simple_mob/vore/candy/ouroboros/do_special_attack(atom/A, stance)
	switch(stance)
		if(I_GRAB)
			summon_combo(A)
		if(I_HURT)
			barrage_combo(A)
		if(I_DISARM)
			debuff_combo(A)

/mob/living/simple_mob/vore/candy/ouroboros/proc/summon_combo(atom/target)
	act_message(src, null, null, MSG_OTHERS(span_warning("%U% calls for help!")))
	new /obj/random/mob/candycritter (src.loc)
	new /obj/random/mob/candycritter (src.loc)
	after(src, 2.0 SECONDS, PROC_REF(summon_combo_1))


/mob/living/simple_mob/vore/candy/ouroboros/proc/summon_combo_1()
	act_message(src, null, null, MSG_OTHERS(span_warning("%U% calls for help!")))
	new /obj/random/mob/candycritter (src.loc)
	new /obj/random/mob/candycritter (src.loc)
	new /obj/random/mob/candycritter (src.loc)
	after(src, 1.5 SECONDS, PROC_REF(summon_combo_2))

/mob/living/simple_mob/vore/candy/ouroboros/proc/summon_combo_2()
	act_message(src, null, null, MSG_OTHERS(span_warning("%U% calls for help!")))
	new /obj/random/mob/candycritter (src.loc)
	new /obj/random/mob/candycritter (src.loc)
	new /obj/random/mob/candycritter (src.loc)
	new /obj/random/mob/candycritter (src.loc)
	after(src, 1.0 SECONDS, PROC_REF(summon_combo_3))

/mob/living/simple_mob/vore/candy/ouroboros/proc/summon_combo_3()
	act_message(src, null, null, MSG_OTHERS(span_warning("%U% calls for help!")))
	new /obj/random/mob/candycritter (src.loc)
	new /obj/random/mob/candycritter (src.loc)
	new /obj/random/mob/candycritter (src.loc)
	new /obj/random/mob/candycritter (src.loc)
	new /obj/random/mob/candycritter (src.loc)
	act_message(src, null, null, MSG_OTHERS(span_warning("%U% begins to heal!")))
	after(src, 3.5 SECONDS, PROC_REF(summon_combo_4))

/mob/living/simple_mob/vore/candy/ouroboros/proc/summon_combo_4()
	mend(TREAT_TISSUE_REPAIR, 35)
	mend(TREAT_BURN_CARE, 35)
	mend(TREAT_ANTITOXIN, 35)
	mend(TREAT_OXYGENATION, 35)
	mend(TREAT_GENETIC_REPAIR, 35)

/mob/living/simple_mob/vore/candy/ouroboros/proc/barrage_combo(atom/target)
	var/first = prob(50) ? /obj/item/projectile/arc/fragmentation/cherrybomb : /obj/item/projectile/bullet/cmblast
	var/second = prob(50) ? "critters" : (first == /obj/item/projectile/bullet/cmblast ? /obj/item/projectile/arc/fragmentation/cherrybomb : /obj/item/projectile/bullet/cmblast)
	after(src, 0.5 SECONDS, PROC_REF(barrage_shot), with = list(target, first, second), keeps_dead = TRUE)

/mob/living/simple_mob/vore/candy/ouroboros/proc/barrage_shot(atom/target, shot, next_shot)
	if(shot == "critters")
		new /obj/random/mob/candycritter (src.loc)
		new /obj/random/mob/candycritter (src.loc)
		new /obj/random/mob/candycritter (src.loc)
	else
		var/obj/item/projectile/P = new shot(get_turf(src))
		P.launch_projectile(target, BP_TORSO, src)
	if(next_shot)
		after(src, 0.5 SECONDS, PROC_REF(barrage_shot), with = list(target, next_shot, null), keeps_dead = TRUE)

/mob/living/simple_mob/vore/candy/ouroboros/proc/debuff_combo(atom/target)
	act_message(src, null, null, MSG_OTHERS(span_warning("%U% prepares to let out a thunderous roar!")))
	after(src, 2.5 SECONDS, PROC_REF(debuff_roar), with = list(target))

/mob/living/simple_mob/vore/candy/ouroboros/proc/debuff_roar(atom/target)
	var/obj/item/grenade/G = new grenade_type(get_turf(src))
	if(istype(G))
		G.throw_at(G.throw_range, G.throw_speed, src)
		G.det_time = grenade_timer
		G.activate(src)
	if(prob(25))
		new /obj/random/mob/candycritter (src.loc)
		new /obj/random/mob/candycritter (src.loc)
	else
		var/obj/item/projectile/P = new /obj/item/projectile/bullet/cmblast(get_turf(src))
		P.launch_projectile(target, BP_TORSO, src)
		after(P, 0.05 SECONDS, TYPE_PROC_REF(/obj/item/projectile, launch_projectile), with = list(target, BP_TORSO, src))


/obj/random/mob/candycritter
	name = "Random Gummy Candy Critter"
	desc = "This is a random candy critter."
	overwrite_hostility = 1
	mob_hostile = 1
	mob_retaliate = 1

	mob_faction = "candy"

DECLARE_LOOT(/obj/random/mob/candycritter, LOOT_TABLE(\
	/mob/living/simple_mob/vore/candy/purplecabold, \
	/mob/living/simple_mob/vore/candy/bluecabold, \
	/mob/living/simple_mob/vore/candy/greencabold, \
	/mob/living/simple_mob/vore/candy/yellowcabold, \
	/mob/living/simple_mob/vore/candy/orangecabold, \
	/mob/living/simple_mob/vore/candy/redcabold, \
	/mob/living/simple_mob/vore/candy/peppermint))

/obj/item/projectile/bullet/cmblast
	use_submunitions = 1
	only_submunitions = 1
	range = 0
	embed_chance = 0
	submunition_spread_max = 1800
	submunition_spread_min = 500
	submunitions = list(/obj/item/projectile/energy/chocosphere = 12)

/obj/item/projectile/energy/chocosphere
	name = "choclate sphere"
	icon = 'icons/mob/candy.dmi'
	icon_state = "choclate_sphere"
	damage = 20
	armor_penetration = 30
	speed = 4.0
	flash_strength = 0
	modifier_type_to_apply = /datum/body_effect/chilled
	modifier_duration = 6 SECONDS

/obj/item/projectile/energy/canearrow
	name = "candy cane arrow"
	icon = 'icons/mob/candy.dmi'
	icon_state = "choclate_sphere"
	damage = 15
	armor_penetration = 40
	speed = 2.5
	flash_strength = 0
	modifier_type_to_apply = /datum/body_effect/grievous_wounds
	modifier_duration = 12 SECONDS

/obj/item/projectile/arc/fragmentation/cherrybomb
	name = "cherry bomb"
	icon = 'icons/mob/candy.dmi'
	icon_state = "cherry_bomb"
	fragment_amount = 3
	spread_range = 7
	speed = 1.5
	fragment_types = list(
		/obj/item/projectile/bullet/cherrypit
		)

/obj/item/projectile/bullet/cherrypit
	name = "cherry bomb"
	icon = 'icons/mob/candy.dmi'
	icon_state = "cherry_pit"
	damage = 25
	armor_penetration = 30

//more critters
//antimelee

/mob/living/simple_mob/vore/candy/peppermint
	drag_buckle = FALSE
	name = "peppermint turtle"
	desc = "A creature made of candy, it's peppermint looking shell seeming diffcult to get a good hit on, but fragile if well struck."
	icon = 'icons/mob/candy.dmi'
	icon_state = "peppermint"
	icon_living = "peppermint"
	icon_dead = "peppermint_dead"

	faction = "candy"

	endurance = 10

CAPABILITIES(/mob/living/simple_mob/vore/candy/peppermint)
	op("peppermint_interaction_item", item(/obj/item), then(PROC_REF(peppermint_interaction_item)))
	verb_entry(/mob/living/simple_mob/proc/animal_mount, login = TRUE) // TGPanel
	verb_entry(/mob/living/proc/toggle_rider_reins, login = TRUE) // TGPanel

/// Old attackby: the shell deflects most hits; forceless items only tap it. FALSE = the hit lands (hit_with_item).
/mob/living/simple_mob/vore/candy/peppermint/proc/peppermint_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	if(O.force)
		if(prob(80))
			act_message(src, O, null, MSG_OTHERS(span_danger("%U% deflects %T% with its shell!")))
			if(user)
				ai_brain.react_to_attack(user)
			return TRUE
		return OP_DECLINE
	to_chat(user, span_warning("This weapon is ineffective, it does no damage."))
	act_message(user, src, null, MSG_OTHERS(span_warning("%U% gently taps %T% with %I%.")), item = O)
	return TRUE

/*
/mob/living/simple_mob/vore/candy/worm
	drag_buckle = FALSE
	name = "hardcandy worm"
	desc = "A creature made of candy."
	icon = 'icons/mob/candy.dmi'
	icon_state = "worm"
	icon_living = "worm"
	icon_dead = "worm_dead"

	faction = "candy"

	endurance = 60


/mob/living/simple_mob/vore/candy/worm/on_death(gibbed)
	. = ..()
	new /obj/random/mob/candycritter (src.loc)
	new /obj/random/mob/candycritter (src.loc)
	new /obj/random/mob/candycritter (src.loc)


CAPABILITIES(/mob/living/simple_mob/vore/candy/worm)
	verb_entry(/mob/living/simple_mob/proc/animal_mount, login = TRUE) // TGPanel
	verb_entry(/mob/living/proc/toggle_rider_reins, login = TRUE) // TGPanel

/mob/living/simple_mob/vore/candy/worm/Login()
	. = ..()
	if(!riding_datum)
		rel_set(src, nameof(riding_datum), new /datum/riding/simple_mob(src))
	movement_cooldown = 1

/mob/living/simple_mob/vore/candy/worm/redcabold/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected
	B.name = "stomach"
	B.desc = "The fearsome predator gets a firm grip upon you, before dunking you into it's maw, then with a powerful swift gulp you're sent tumbling into it's stomach."

	B.own_emote_lists()
	B.emote_lists[DM_HOLD] = list(
		"Your surroundings are momentarily filled with your predator's pleased rumbling, its hands stroking over the taut swell you make in its belly.",)

	B.own_emote_lists()
	B.emote_lists[DM_DIGEST] = list(
		"Every clench of the predator's stomach grinds powerful digestive fluids into your body, forcibly churning away your strength!")
*/

/mob/living/simple_mob/vore/candy/peppermint/Login()
	. = ..()
	if(!riding_datum)
		rel_set(src, nameof(riding_datum), new /datum/riding/simple_mob(src))
	movement_cooldown = 1

/mob/living/simple_mob/vore/candy/peppermint/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected
	B.name = "stomach"
	B.desc = "The fearsome predator gets a firm grip upon you, before dunking you into it's maw, then with a powerful swift gulp you're sent tumbling into it's stomach."

	B.own_emote_lists()
	B.emote_lists[DM_HOLD] = list(
		"Your surroundings are momentarily filled with your predator's pleased rumbling, its hands stroking over the taut swell you make in its belly.",)

	B.own_emote_lists()
	B.emote_lists[DM_DIGEST] = list(
		"Every clench of the predator's stomach grinds powerful digestive fluids into your body, forcibly churning away your strength!")

v


/mob/living/simple_mob/vore/candy/bluecabold
	drag_buckle = FALSE

/mob/living/simple_mob/vore/candy/redcabold
	drag_buckle = FALSE

/mob/living/simple_mob/vore/candy/yellowcabold
	drag_buckle = FALSE

/mob/living/simple_mob/vore/candy/orangecabold
	drag_buckle = FALSE

/mob/living/simple_mob/vore/candy/purplecabold
	drag_buckle = FALSE

/mob/living/simple_mob/vore/candy/marshmellowserpent
	drag_buckle = FALSE
