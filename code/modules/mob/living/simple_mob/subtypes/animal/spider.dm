//Now that players will get less overpowered weapons, let mobs have lower HP to compensate. Assume a player has a 10 shot laser rifle doing 40 damage, or a 20 shot smg that does 20
/mob/living/simple_mob/animal/giant_spider/carrier
	endurance = 60

/mob/living/simple_mob/animal/giant_spider/electric
	endurance = 60
	projectiletype = /obj/item/projectile/energy/mob/electric_spider

/mob/living/simple_mob/animal/giant_spider/frost //tank, old 175
	endurance = 75

/mob/living/simple_mob/animal/giant_spider //tank, old 200
	endurance = 80

/mob/living/simple_mob/animal/giant_spider/ion //disrupter, old 90
	endurance = 45

/mob/living/simple_mob/animal/giant_spider/hunter //disrupter, old 120
	endurance = 40

/mob/living/simple_mob/animal/giant_spider/lurker //disrupter, old 100
	endurance = 40

/mob/living/simple_mob/animal/giant_spider/pepper //tank, old 210
	endurance = 80

/mob/living/simple_mob/animal/giant_spider/phorogenic //tank, old 225
	endurance = 200 //Gives people a second to stand back

/mob/living/simple_mob/animal/giant_spider/thermic //tank, old 175
	endurance = 75

/mob/living/simple_mob/animal/giant_spider/tunneler //disrupter, old 120
	endurance = 65

/mob/living/simple_mob/animal/giant_spider/webslinger //disrupter, old 90
	endurance = 40

/obj/effect/spider/eggcluster
	spider_type = /obj/effect/spider/spiderling/varied

/mob/living/simple_mob/animal/giant_spider/broodmother
	endurance = 700

/mob/living/simple_mob/animal/giant_spider/frost/broodling
	endurance = 20

	melee_damage_lower = 5
	melee_damage_upper = 7

/mob/living/simple_mob/animal/giant_spider/electric/broodling
	endurance = 15

/mob/living/simple_mob/animal/giant_spider/hunter/broodling
	endurance = 20

/mob/living/simple_mob/animal/giant_spider/lurker/broodling
	endurance = 20

/mob/living/simple_mob/animal/giant_spider/nurse/broodling
	endurance = 30

/mob/living/simple_mob/animal/giant_spider/pepper/broodling
	endurance = 20

/mob/living/simple_mob/animal/giant_spider/thermic/broodling
	endurance = 20

	melee_damage_lower = 5
	melee_damage_upper = 7

/mob/living/simple_mob/animal/giant_spider/tunneler/broodling
	endurance = 20

/mob/living/simple_mob/animal/giant_spider/webslinger/broodling
	endurance = 15

/mob/living/simple_mob/animal/giant_spider/broodling
	endurance = 30

	melee_damage_lower = 5
	melee_damage_upper = 10


//Hijacking this file to make new event spiders

/mob/living/simple_mob/animal/giant_spider/frost/space
	name = "giant space spider"
	min_oxy = 0
	max_tox = 0
	max_co2 = 0

	/* Use the parent
	endurance = 20
	*/
	melee_damage_lower = 5
	melee_damage_upper = 7

/mob/living/simple_mob/animal/giant_spider/electric/space
	name = "giant space spider"
	min_oxy = 0
	max_tox = 0
	max_co2 = 0

	/* Use the parent
	endurance = 15
	*/

/mob/living/simple_mob/animal/giant_spider/hunter/space
	name = "giant space spider"
	min_oxy = 0
	max_tox = 0
	max_co2 = 0
	/*Use the parent
	endurance = 20
	*/

/mob/living/simple_mob/animal/giant_spider/lurker/space
	endurance = 40

/mob/living/simple_mob/animal/giant_spider/nurse/space
	name = "giant space spider"
	min_oxy = 0
	max_tox = 0
	max_co2 = 0

	egg_type = /obj/effect/spider/eggcluster/royal/space
	/* Use the parent
	endurance = 30
	*/

/mob/living/simple_mob/animal/giant_spider/pepper/space
	name = "giant space spider"
	min_oxy = 0
	max_tox = 0
	max_co2 = 0

	endurance = 20

/mob/living/simple_mob/animal/giant_spider/thermic/space
	name = "giant space spider"
	min_oxy = 0
	max_tox = 0
	max_co2 = 0
	endurance = 20

	melee_damage_lower = 5
	melee_damage_upper = 7

/mob/living/simple_mob/animal/giant_spider/tunneler/space
	name = "giant space spider"
	min_oxy = 0
	max_tox = 0
	max_co2 = 0
	endurance = 20

/mob/living/simple_mob/animal/giant_spider/webslinger/space
	name = "giant space spider"
	min_oxy = 0
	max_tox = 0
	max_co2 = 0
	endurance = 15

/mob/living/simple_mob/animal/giant_spider/space
	name = "giant space spider"
	min_oxy = 0
	max_tox = 0
	max_co2 = 0
