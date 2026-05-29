/mob/living/simple_mob/clowns/big
	tt_desc = "E Homo sapiens corydon horrificus" //this clown is stronk
	faction = FACTION_CLOWN

	maxHealth = 200
	health = 200
	see_in_dark = 8

	melee_damage_lower = 15
	melee_damage_upper = 25
	attack_armor_pen = 5
	attack_sharp = FALSE
	attack_edge = FALSE
	melee_attack_delay = 1 SECOND
	attacktext = list("clowned")


	loot_list = list(/obj/item/bikehorn = 100)

	min_oxy = 0
	max_oxy = 500
	min_tox = 0
	max_tox = 500
	min_co2 = 0
	max_co2 = 500
	min_n2 = 0
	max_n2 = 500
	minbodytemp = 0
	maxbodytemp = 700
