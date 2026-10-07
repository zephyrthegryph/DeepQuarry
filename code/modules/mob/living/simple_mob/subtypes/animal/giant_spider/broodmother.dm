/mob/living/simple_mob/animal/giant_spider/broodmother
	name = "giant spider broodmother"
	desc = "Absolutely gigantic, this creature is horror itself. This one seems to have weaponized childbirth!"
	tt_desc = "X Atrax robustus gigantus maximus"
	icon = 'icons/mob/64x64.dmi'
	vis_height = 64
	icon_state = "spider_queen"
	icon_living = "spider_queen"
	icon_dead = "spider_queen_dead"

	endurance = 800

	melee_damage_lower = 25
	melee_damage_upper = 40
	attack_armor_pen = 15

	pixel_x = -16
	pixel_y = 0
	default_pixel_x = -16
	old_x = -16
	old_y = 0

	meat_amount = 20

	projectiletype = /obj/item/projectile/energy/spidertoxin
	projectilesound = SFX_WEAPONS_PIERCE

	var/static/list/possible_brood_types = list(
		/mob/living/simple_mob/animal/giant_spider/frost/broodling,
		/mob/living/simple_mob/animal/giant_spider/electric/broodling,
		/mob/living/simple_mob/animal/giant_spider/hunter/broodling,
		/mob/living/simple_mob/animal/giant_spider/lurker/broodling,
		/mob/living/simple_mob/animal/giant_spider/nurse/broodling,
		/mob/living/simple_mob/animal/giant_spider/pepper/broodling,
		/mob/living/simple_mob/animal/giant_spider/thermic/broodling,
		/mob/living/simple_mob/animal/giant_spider/tunneler/broodling,
		/mob/living/simple_mob/animal/giant_spider/webslinger/broodling,
		/mob/living/simple_mob/animal/giant_spider/broodling)

	var/static/list/possible_death_brood_types = list(
		/mob/living/simple_mob/animal/giant_spider/frost,
		/mob/living/simple_mob/animal/giant_spider/electric,
		/mob/living/simple_mob/animal/giant_spider/hunter,
		/mob/living/simple_mob/animal/giant_spider/lurker,
		/mob/living/simple_mob/animal/giant_spider/pepper,
		/mob/living/simple_mob/animal/giant_spider/thermic,
		/mob/living/simple_mob/animal/giant_spider/tunneler,
		/mob/living/simple_mob/animal/giant_spider/webslinger,
		/mob/living/simple_mob/animal/giant_spider/phorogenic,
		/mob/living/simple_mob/animal/giant_spider/carrier,
		/mob/living/simple_mob/animal/giant_spider)
	var/max_brood = 8
	var/death_brood = 8
	var/brood_per_spawn = 4
	var/brood_per_launch = 2
	special_attack_min_range = 0
	special_attack_max_range = 10
	special_attack_cooldown = 6 SECONDS
	poison_per_bite = 2
	poison_type = REAGENT_ID_CYANIDE

	loot_list = list(/obj/item/royal_spider_egg = 100)

/obj/item/projectile/energy/spidertoxin
	name = "concentrated spidertoxin"
	icon_state = "neurotoxin"
	damage = 35
	injury_kind = INJURY_CORROSIVE
	agony = 15
	armor_penetration = 40

	combustion = FALSE

/mob/living/simple_mob/animal/giant_spider/broodmother
	death_message = "falls over and makes its last twitches as its birthing sack bursts!"

/mob/living/simple_mob/animal/giant_spider/broodmother/on_death(gibbed)
	var/count = 0
	while(count < death_brood)
		var/broodling_type = pick(possible_death_brood_types)
		var/mob/living/simple_mob/animal/giant_spider/broodling = new broodling_type(src.loc)
		broodling.faction = faction
		step_away(broodling, src)
		count++

	return ..()

/mob/living/simple_mob/animal/giant_spider/broodmother/proc/spawn_brood(atom/A)

	var/count = 0
	while(count < brood_per_spawn)
		var/broodling_type = pick(possible_brood_types)
		var/mob/living/simple_mob/animal/giant_spider/broodling = new broodling_type(src.loc)
		broodling.faction = faction
		broodling.ai_brain?.serve(src) // sworn: it joins the mother's pack and never splits off
		step_away(broodling, src)
		count++

	act_message(src, null, null, MSG_OTHERS(span_danger("%U% releases brood from its birthing sack!")))

/mob/living/simple_mob/animal/giant_spider/broodmother/proc/launch_brood(atom/A)

	var/count = 0
	while(count < brood_per_launch)
		var/broodling_type = pick(possible_brood_types)
		var/mob/living/simple_mob/animal/giant_spider/broodling = new broodling_type(src.loc)
		broodling.faction = faction
		broodling.ai_brain?.serve(src)
		step_away(broodling, src)
		broodling.throw_at(A, 10)
		count++

	act_message(src, null, null, MSG_OTHERS(span_danger("%U% launches brood from the distance!")))

/mob/living/simple_mob/animal/giant_spider/broodmother/proc/can_spawn_brood()
	var/brood_amount = 0
	for(var/mob/living/simple_mob/mob in view(7, src))
		if(mob.type in possible_brood_types)
			brood_amount++
	if(brood_amount >= max_brood)
		return FALSE
	return TRUE

/mob/living/simple_mob/animal/giant_spider/broodmother/should_special_attack(atom/A)
	if(!can_spawn_brood())
		return FALSE
	return TRUE

/mob/living/simple_mob/animal/giant_spider/broodmother/do_special_attack(atom/A, stance)
	. = TRUE
	switch(stance)
		if(I_DISARM)
			spawn_brood(A)
		if(I_HURT)
			launch_brood(A)


/obj/item/royal_spider_egg
	name = "royal spider egg"
	desc = "This one is yet to be imprinted!"
	icon = 'icons/obj/egg.dmi'
	icon_state = "egg_slimeglob"


CAPABILITIES(/obj/item/royal_spider_egg)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/royal_spider_egg/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	open_request(src, /datum/prompt/yes_no, PROC_REF(release_confirmed), answerer = user, title = "Royal Spider Egg", question = "Are you sure you want to release the royal spiderling right now? It appears ready to imprint the moment its born.", ask_flags = ASK_CARRIED | ASK_CAPABLE, timeout = 0)
	return TRUE

/obj/item/royal_spider_egg/proc/release_confirmed(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return
	var/mob/user = A.request.answerer
	var/turf/drop_loc = user.loc
	if(istype(drop_loc))
		var/obj/effect/spider/spiderling/princess/royalty = new(drop_loc)
		royalty.faction = user.faction

		consume(src, user)

	else
		to_chat(user, "You need more space to release the egg!")
