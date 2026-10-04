/mob/living/simple_mob/animal/giant_spider/frost/broodling
	endurance = 40

	melee_damage_lower = 10
	melee_damage_upper = 15

	movement_cooldown = 3

TYPE_TABLE(/mob/living/simple_mob/animal/giant_spider/frost/broodling, broodling_initial_scale, 0.75)

/// Vanishes instead of dying.
/mob/living/simple_mob/animal/giant_spider/frost/broodling/replace_death(gibbed)
	var/obj/effect/decal/cleanable/spiderling_remains/remains = new(src.loc)

	if(!QDELETED(src))
		replace_with(src, remains)
	return TRUE

/mob/living/simple_mob/animal/giant_spider/electric/broodling
	endurance = 30

	taser_kill = TRUE
	base_attack_cooldown = 20

	movement_cooldown = -1

TYPE_TABLE(/mob/living/simple_mob/animal/giant_spider/electric/broodling, broodling_initial_scale, 0.75)

/// Vanishes instead of dying.
/mob/living/simple_mob/animal/giant_spider/electric/broodling/replace_death(gibbed)
	var/obj/effect/decal/cleanable/spiderling_remains/remains = new(src.loc)

	if(!QDELETED(src))
		replace_with(src, remains)
	return TRUE

/mob/living/simple_mob/animal/giant_spider/hunter/broodling
	endurance = 40

	movement_cooldown = 0

TYPE_TABLE(/mob/living/simple_mob/animal/giant_spider/hunter/broodling, broodling_initial_scale, 0.75)

/// Vanishes instead of dying.
/mob/living/simple_mob/animal/giant_spider/hunter/broodling/replace_death(gibbed)
	var/obj/effect/decal/cleanable/spiderling_remains/remains = new(src.loc)

	if(!QDELETED(src))
		replace_with(src, remains)
	return TRUE

/mob/living/simple_mob/animal/giant_spider/lurker/broodling
	endurance = 40

	movement_cooldown = 0

TYPE_TABLE(/mob/living/simple_mob/animal/giant_spider/lurker/broodling, broodling_initial_scale, 0.75)

/// Vanishes instead of dying.
/mob/living/simple_mob/animal/giant_spider/lurker/broodling/replace_death(gibbed)
	var/obj/effect/decal/cleanable/spiderling_remains/remains = new(src.loc)

	if(!QDELETED(src))
		replace_with(src, remains)
	return TRUE

/mob/living/simple_mob/animal/giant_spider/nurse/broodling
	endurance = 60

	movement_cooldown = 3

TYPE_TABLE(/mob/living/simple_mob/animal/giant_spider/nurse/broodling, broodling_initial_scale, 0.75)

/// Vanishes instead of dying.
/mob/living/simple_mob/animal/giant_spider/nurse/broodling/replace_death(gibbed)
	var/obj/effect/decal/cleanable/spiderling_remains/remains = new(src.loc)

	if(!QDELETED(src))
		replace_with(src, remains)
	return TRUE

/mob/living/simple_mob/animal/giant_spider/pepper/broodling
	endurance = 40

	movement_cooldown = 3

TYPE_TABLE(/mob/living/simple_mob/animal/giant_spider/pepper/broodling, broodling_initial_scale, 0.75)

/// Vanishes instead of dying.
/mob/living/simple_mob/animal/giant_spider/pepper/broodling/replace_death(gibbed)
	var/obj/effect/decal/cleanable/spiderling_remains/remains = new(src.loc)

	if(!QDELETED(src))
		replace_with(src, remains)
	return TRUE

/mob/living/simple_mob/animal/giant_spider/thermic/broodling
	endurance = 40

	melee_damage_lower = 10
	melee_damage_upper = 15

	movement_cooldown = 1

TYPE_TABLE(/mob/living/simple_mob/animal/giant_spider/thermic/broodling, broodling_initial_scale, 0.75)

/// Vanishes instead of dying.
/mob/living/simple_mob/animal/giant_spider/thermic/broodling/replace_death(gibbed)
	var/obj/effect/decal/cleanable/spiderling_remains/remains = new(src.loc)

	if(!QDELETED(src))
		replace_with(src, remains)
	return TRUE

/mob/living/simple_mob/animal/giant_spider/tunneler/broodling
	endurance = 40

	movement_cooldown = 1

TYPE_TABLE(/mob/living/simple_mob/animal/giant_spider/tunneler/broodling, broodling_initial_scale, 0.75)

/// Vanishes instead of dying.
/mob/living/simple_mob/animal/giant_spider/tunneler/broodling/replace_death(gibbed)
	var/obj/effect/decal/cleanable/spiderling_remains/remains = new(src.loc)

	if(!QDELETED(src))
		replace_with(src, remains)
	return TRUE

/mob/living/simple_mob/animal/giant_spider/webslinger/broodling
	endurance = 30

	base_attack_cooldown = 20

	movement_cooldown = 1.5

TYPE_TABLE(/mob/living/simple_mob/animal/giant_spider/webslinger/broodling, broodling_initial_scale, 0.75)

/// Vanishes instead of dying.
/mob/living/simple_mob/animal/giant_spider/webslinger/broodling/replace_death(gibbed)
	var/obj/effect/decal/cleanable/spiderling_remains/remains = new(src.loc)

	if(!QDELETED(src))
		replace_with(src, remains)
	return TRUE

/mob/living/simple_mob/animal/giant_spider/broodling
	endurance = 60

	melee_damage_lower = 10
	melee_damage_upper = 20

	movement_cooldown = 3


TYPE_TABLE(/mob/living/simple_mob/animal/giant_spider/broodling, broodling_initial_scale, 0.75)

/mob/living/simple_mob/animal/giant_spider/broodling/Initialize(mapload)
	. = ..()
	after(src, 2 MINUTES, PROC_REF(death), key = "deathtimer")

/// Vanishes instead of dying.
/mob/living/simple_mob/animal/giant_spider/broodling/replace_death(gibbed)
	var/obj/effect/decal/cleanable/spiderling_remains/remains = new(src.loc)

	if(!QDELETED(src))
		replace_with(src, remains)
	return TRUE

/// A broodling lives two minutes.
/mob/living/simple_mob/animal/giant_spider/proc/brood_expire(datum/act/A)
	death()

CAPABILITIES(/mob/living/simple_mob/animal/giant_spider/frost/broodling)
	after_init(2 MINUTES, then(PROC_REF(brood_expire)))
CAPABILITIES(/mob/living/simple_mob/animal/giant_spider/electric/broodling)
	after_init(2 MINUTES, then(PROC_REF(brood_expire)))
CAPABILITIES(/mob/living/simple_mob/animal/giant_spider/hunter/broodling)
	after_init(2 MINUTES, then(PROC_REF(brood_expire)))
CAPABILITIES(/mob/living/simple_mob/animal/giant_spider/lurker/broodling)
	after_init(2 MINUTES, then(PROC_REF(brood_expire)))
CAPABILITIES(/mob/living/simple_mob/animal/giant_spider/nurse/broodling)
	after_init(2 MINUTES, then(PROC_REF(brood_expire)))
CAPABILITIES(/mob/living/simple_mob/animal/giant_spider/pepper/broodling)
	after_init(2 MINUTES, then(PROC_REF(brood_expire)))
CAPABILITIES(/mob/living/simple_mob/animal/giant_spider/thermic/broodling)
	after_init(2 MINUTES, then(PROC_REF(brood_expire)))
CAPABILITIES(/mob/living/simple_mob/animal/giant_spider/tunneler/broodling)
	after_init(2 MINUTES, then(PROC_REF(brood_expire)))
CAPABILITIES(/mob/living/simple_mob/animal/giant_spider/webslinger/broodling)
	after_init(2 MINUTES, then(PROC_REF(brood_expire)))
