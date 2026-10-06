/mob/living/simple_mob/animal/space/bear
	name = "space bear"
	desc = "A product of Space Russia?"
	tt_desc = "U Ursinae aetherius" //...bearspace? Maybe.
	icon_state = "bear"
	icon_living = "bear"
	icon_dead = "bear_dead"
	icon_gib = "bear_gib"

	faction = FACTION_RUSSIAN

	endurance = 125

	movement_cooldown = -1

	melee_damage_lower = 15
	melee_damage_upper = 35
	attack_armor_pen = 15
	attack_injury_kind = INJURY_CUT
	melee_attack_delay = 1 SECOND
	attacktext = list("mauled")

	meat_type = /obj/item/reagent_containers/food/snacks/bearmeat
	meat_amount = 8

	say_list_type = /datum/say_list/bear

	can_be_drop_prey = FALSE
	allow_mind_transfer = TRUE

/datum/say_list/bear
	speak = list("RAWR!","Rawr!","GRR!","Growl!")
	emote_see = list("stares ferociously", "stomps")
	emote_hear = list("rawrs","grumbles","grawls", "growls", "roars")

// Is it time to be mad?
/mob/living/simple_mob/animal/space/bear/life_special_due()
	return TRUE

/mob/living/simple_mob/animal/space/bear/life_special(datum/seq_frame/life/F)
	if(((src.ai_brain ? (src.ai_brain.primary_threat ? STANCE_FIGHT : STANCE_IDLE) : STANCE_IDLE) in list(STANCE_APPROACH, STANCE_FIGHT)) && !om_busy(src) && isturf(src.loc))
		if(src.vitality() <= 0.5) // At half health, and fighting someone currently.
			src.berserk()

// So players can use it too.
/mob/living/simple_mob/animal/space/bear/verb/berserk()
	set name = "Berserk"
	set desc = "Enrage and become vastly stronger for a period of time, however you will be weaker afterwards."
	set category = VERB_CAT_ABILITIES_BEAR

	apply_body_effect(/datum/body_effect/berserk, 30 SECONDS)
