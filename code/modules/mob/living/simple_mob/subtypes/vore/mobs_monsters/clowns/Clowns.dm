/mob/living/simple_mob/clowns/
	tt_desc = "E Homo sapiens corydon" //this is a clown
	faction = FACTION_CLOWN
	movement_sound = 'sound/effects/clownstep2.ogg'
	attack_sound = 'sound/effects/Whipcrack.ogg'

	faction = FACTION_CLOWN

	maxHealth = 100
	health = 100
	see_in_dark = 8

	has_hands = TRUE
	humanoid_hands = TRUE

	melee_damage_lower = 5
	melee_damage_upper = 30


	loot_list = list(/obj/item/bikehorn = 100)

	min_oxy = 0
	max_oxy = 0
	min_tox = 0
	max_tox = 0
	min_co2 = 0
	max_co2 = 0
	min_n2 = 0
	max_n2 = 0
	minbodytemp = 0
	maxbodytemp = 700
