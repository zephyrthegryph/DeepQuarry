/mob/living/simple_mob/animal/giant_spider/frost/broodling
	endurance = 40

	melee_damage_lower = 10
	melee_damage_upper = 15

	movement_cooldown = 3

/mob/living/simple_mob/animal/giant_spider/frost/broodling/Initialize(mapload)
	. = ..()
	adjust_scale(0.75)

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

/mob/living/simple_mob/animal/giant_spider/electric/broodling/Initialize(mapload)
	. = ..()
	adjust_scale(0.75)

/// Vanishes instead of dying.
/mob/living/simple_mob/animal/giant_spider/electric/broodling/replace_death(gibbed)
	var/obj/effect/decal/cleanable/spiderling_remains/remains = new(src.loc)

	if(!QDELETED(src))
		replace_with(src, remains)
	return TRUE

/mob/living/simple_mob/animal/giant_spider/hunter/broodling
	endurance = 40

	movement_cooldown = 0

/mob/living/simple_mob/animal/giant_spider/hunter/broodling/Initialize(mapload)
	. = ..()
	adjust_scale(0.75)

/// Vanishes instead of dying.
/mob/living/simple_mob/animal/giant_spider/hunter/broodling/replace_death(gibbed)
	var/obj/effect/decal/cleanable/spiderling_remains/remains = new(src.loc)

	if(!QDELETED(src))
		replace_with(src, remains)
	return TRUE

/mob/living/simple_mob/animal/giant_spider/lurker/broodling
	endurance = 40

	movement_cooldown = 0

/mob/living/simple_mob/animal/giant_spider/lurker/broodling/Initialize(mapload)
	. = ..()
	adjust_scale(0.75)

/// Vanishes instead of dying.
/mob/living/simple_mob/animal/giant_spider/lurker/broodling/replace_death(gibbed)
	var/obj/effect/decal/cleanable/spiderling_remains/remains = new(src.loc)

	if(!QDELETED(src))
		replace_with(src, remains)
	return TRUE

/mob/living/simple_mob/animal/giant_spider/nurse/broodling
	endurance = 60

	movement_cooldown = 3

/mob/living/simple_mob/animal/giant_spider/nurse/broodling/Initialize(mapload)
	. = ..()
	adjust_scale(0.75)

/// Vanishes instead of dying.
/mob/living/simple_mob/animal/giant_spider/nurse/broodling/replace_death(gibbed)
	var/obj/effect/decal/cleanable/spiderling_remains/remains = new(src.loc)

	if(!QDELETED(src))
		replace_with(src, remains)
	return TRUE

/mob/living/simple_mob/animal/giant_spider/pepper/broodling
	endurance = 40

	movement_cooldown = 3

/mob/living/simple_mob/animal/giant_spider/pepper/broodling/Initialize(mapload)
	. = ..()
	adjust_scale(0.75)

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

/mob/living/simple_mob/animal/giant_spider/thermic/broodling/Initialize(mapload)
	. = ..()
	adjust_scale(0.75)

/// Vanishes instead of dying.
/mob/living/simple_mob/animal/giant_spider/thermic/broodling/replace_death(gibbed)
	var/obj/effect/decal/cleanable/spiderling_remains/remains = new(src.loc)

	if(!QDELETED(src))
		replace_with(src, remains)
	return TRUE

/mob/living/simple_mob/animal/giant_spider/tunneler/broodling
	endurance = 40

	movement_cooldown = 1

/mob/living/simple_mob/animal/giant_spider/tunneler/broodling/Initialize(mapload)
	. = ..()
	adjust_scale(0.75)

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

/mob/living/simple_mob/animal/giant_spider/webslinger/broodling/Initialize(mapload)
	. = ..()
	adjust_scale(0.75)

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


/mob/living/simple_mob/animal/giant_spider/broodling/Initialize(mapload)
	. = ..()
	adjust_scale(0.75)
	after_slot(src, "deathtimer", 2 MINUTES, PROC_REF(death))

/// Vanishes instead of dying.
/mob/living/simple_mob/animal/giant_spider/broodling/replace_death(gibbed)
	var/obj/effect/decal/cleanable/spiderling_remains/remains = new(src.loc)

	if(!QDELETED(src))
		replace_with(src, remains)
	return TRUE

DECLARE_START_TIMER(/mob/living/simple_mob/animal/giant_spider/frost/broodling, 2 MINUTES, PROC_REF(death))
DECLARE_START_TIMER(/mob/living/simple_mob/animal/giant_spider/electric/broodling, 2 MINUTES, PROC_REF(death))
DECLARE_START_TIMER(/mob/living/simple_mob/animal/giant_spider/hunter/broodling, 2 MINUTES, PROC_REF(death))
DECLARE_START_TIMER(/mob/living/simple_mob/animal/giant_spider/lurker/broodling, 2 MINUTES, PROC_REF(death))
DECLARE_START_TIMER(/mob/living/simple_mob/animal/giant_spider/nurse/broodling, 2 MINUTES, PROC_REF(death))
DECLARE_START_TIMER(/mob/living/simple_mob/animal/giant_spider/pepper/broodling, 2 MINUTES, PROC_REF(death))
DECLARE_START_TIMER(/mob/living/simple_mob/animal/giant_spider/thermic/broodling, 2 MINUTES, PROC_REF(death))
DECLARE_START_TIMER(/mob/living/simple_mob/animal/giant_spider/tunneler/broodling, 2 MINUTES, PROC_REF(death))
DECLARE_START_TIMER(/mob/living/simple_mob/animal/giant_spider/webslinger/broodling, 2 MINUTES, PROC_REF(death))
