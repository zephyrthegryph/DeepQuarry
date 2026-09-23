/mob/living/simple_mob/animal/giant_spider/frost/broodling
	endurance = 40

	melee_damage_lower = 10
	melee_damage_upper = 15

	movement_cooldown = 3

/mob/living/simple_mob/animal/giant_spider/frost/broodling/Initialize(mapload)
	. = ..()
	adjust_scale(0.75)
	addtimer(CALLBACK(src, PROC_REF(death)), 2 MINUTES)

/mob/living/simple_mob/animal/giant_spider/frost/broodling/death()
	new /obj/effect/decal/cleanable/spiderling_remains(src.loc)

	if(!QDELETED(src))
		qdel(src)

/mob/living/simple_mob/animal/giant_spider/electric/broodling
	endurance = 30

	taser_kill = TRUE
	base_attack_cooldown = 20

	movement_cooldown = -1

/mob/living/simple_mob/animal/giant_spider/electric/broodling/Initialize(mapload)
	. = ..()
	adjust_scale(0.75)
	addtimer(CALLBACK(src, PROC_REF(death)), 2 MINUTES)

/mob/living/simple_mob/animal/giant_spider/electric/broodling/death()
	new /obj/effect/decal/cleanable/spiderling_remains(src.loc)

	if(!QDELETED(src))
		qdel(src)

/mob/living/simple_mob/animal/giant_spider/hunter/broodling
	endurance = 40

	movement_cooldown = 0

/mob/living/simple_mob/animal/giant_spider/hunter/broodling/Initialize(mapload)
	. = ..()
	adjust_scale(0.75)
	addtimer(CALLBACK(src, PROC_REF(death)), 2 MINUTES)

/mob/living/simple_mob/animal/giant_spider/hunter/broodling/death()
	new /obj/effect/decal/cleanable/spiderling_remains(src.loc)

	if(!QDELETED(src))
		qdel(src)

/mob/living/simple_mob/animal/giant_spider/lurker/broodling
	endurance = 40

	movement_cooldown = 0

/mob/living/simple_mob/animal/giant_spider/lurker/broodling/Initialize(mapload)
	. = ..()
	adjust_scale(0.75)
	addtimer(CALLBACK(src, PROC_REF(death)), 2 MINUTES)

/mob/living/simple_mob/animal/giant_spider/lurker/broodling/death()
	new /obj/effect/decal/cleanable/spiderling_remains(src.loc)

	if(!QDELETED(src))
		qdel(src)

/mob/living/simple_mob/animal/giant_spider/nurse/broodling
	endurance = 60

	movement_cooldown = 3

/mob/living/simple_mob/animal/giant_spider/nurse/broodling/Initialize(mapload)
	. = ..()
	adjust_scale(0.75)
	addtimer(CALLBACK(src, PROC_REF(death)), 2 MINUTES)

/mob/living/simple_mob/animal/giant_spider/nurse/broodling/death()
	new /obj/effect/decal/cleanable/spiderling_remains(src.loc)

	if(!QDELETED(src))
		qdel(src)

/mob/living/simple_mob/animal/giant_spider/pepper/broodling
	endurance = 40

	movement_cooldown = 3

/mob/living/simple_mob/animal/giant_spider/pepper/broodling/Initialize(mapload)
	. = ..()
	adjust_scale(0.75)
	addtimer(CALLBACK(src, PROC_REF(death)), 2 MINUTES)

/mob/living/simple_mob/animal/giant_spider/pepper/broodling/death()
	new /obj/effect/decal/cleanable/spiderling_remains(src.loc)

	if(!QDELETED(src))
		qdel(src)

/mob/living/simple_mob/animal/giant_spider/thermic/broodling
	endurance = 40

	melee_damage_lower = 10
	melee_damage_upper = 15

	movement_cooldown = 1

/mob/living/simple_mob/animal/giant_spider/thermic/broodling/Initialize(mapload)
	. = ..()
	adjust_scale(0.75)
	addtimer(CALLBACK(src, PROC_REF(death)), 2 MINUTES)

/mob/living/simple_mob/animal/giant_spider/thermic/broodling/death()
	new /obj/effect/decal/cleanable/spiderling_remains(src.loc)

	if(!QDELETED(src))
		qdel(src)

/mob/living/simple_mob/animal/giant_spider/tunneler/broodling
	endurance = 40

	movement_cooldown = 1

/mob/living/simple_mob/animal/giant_spider/tunneler/broodling/Initialize(mapload)
	. = ..()
	adjust_scale(0.75)
	addtimer(CALLBACK(src, PROC_REF(death)), 2 MINUTES)

/mob/living/simple_mob/animal/giant_spider/tunneler/broodling/death()
	new /obj/effect/decal/cleanable/spiderling_remains(src.loc)

	if(!QDELETED(src))
		qdel(src)

/mob/living/simple_mob/animal/giant_spider/webslinger/broodling
	endurance = 30

	base_attack_cooldown = 20

	movement_cooldown = 1.5

/mob/living/simple_mob/animal/giant_spider/webslinger/broodling/Initialize(mapload)
	. = ..()
	adjust_scale(0.75)
	addtimer(CALLBACK(src, PROC_REF(death)), 2 MINUTES)

/mob/living/simple_mob/animal/giant_spider/webslinger/broodling/death()
	new /obj/effect/decal/cleanable/spiderling_remains(src.loc)

	if(!QDELETED(src))
		qdel(src)

/mob/living/simple_mob/animal/giant_spider/broodling
	endurance = 60

	melee_damage_lower = 10
	melee_damage_upper = 20

	movement_cooldown = 3

	var/deathtimer

/mob/living/simple_mob/animal/giant_spider/broodling/Initialize(mapload)
	. = ..()
	adjust_scale(0.75)
	deathtimer = addtimer(CALLBACK(src, PROC_REF(death)), 2 MINUTES, TIMER_STOPPABLE)

/mob/living/simple_mob/animal/giant_spider/broodling/Destroy()
	if(deathtimer)
		deltimer(deathtimer)
		deathtimer = null
	. = ..()

/mob/living/simple_mob/animal/giant_spider/broodling/death()
	new /obj/effect/decal/cleanable/spiderling_remains(src.loc)

	if(!QDELETED(src))
		qdel(src)
