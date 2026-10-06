/mob/living/simple_mob/animal/tyr/mineral_ants
	name = "metal ant"
	desc = "A large ant."
	icon_state = "new_ant"
	icon_dead = "dead_new"
	endurance = 15
	pass_flags = PASSTABLE
	movement_cooldown = 1

	melee_miss_chance = 0


	see_in_dark = 3
	melee_damage_lower = 12
	melee_damage_upper = 12
	attack_injury_kind = INJURY_CUT

	meat_amount = 7
	meat_type = /obj/item/reagent_containers/food/snacks/tyrant_shock

	faction = FACTION_TYR_ANT

	butchery_loot = list(\
		/obj/item/stack/material/steel = 6\
		)

	tame_items = list(
	/obj/item/reagent_containers/food/snacks/jellyfishcore = 70
	)

	harvest_tool = /obj/item/weldingtool
	harvest_cooldown = 10 MINUTES
	harvest_delay = 30 SECONDS

	//I know very little of this
	swallowTime = 3 SECONDS
	vore_active = 1
	vore_capacity = 1
	vore_bump_chance = 10
	vore_stomach_name = "Stomach"
	vore_default_item_mode = IM_DIGEST
	vore_pounce_chance = 50
	vore_pounce_cooldown = 10
	vore_pounce_successrate	= 75
	vore_pounce_falloff = 0
	vore_pounce_maxhealth = 100
	vore_standing_too = TRUE
	unacidable = TRUE

/mob/living/simple_mob/animal/tyr/mineral_ants/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected
	B.name = "stomach"
	B.mode_flags = DM_FLAG_THICKBELLY | DM_FLAG_NUMBING
	B.digest_brute = 0
	B.digest_burn = 3
	B.digestchance = 0
	B.absorbchance = 0
	B.escapechance = 25

/mob/living/simple_mob/animal/tyr/mineral_ants/bronze/apply_melee_effects(atom/A)
	..()

	if(isliving(A) && combat_mode)
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
			play_sfx(src, SFX_PUNCH) // Visible/audible feedback for *resisting* the slam.

/mob/living/simple_mob/animal/tyr/mineral_ants/copper //lighting ants
	name = "copper metal ant"
	icon_state = "copper_ant"
	icon_living = "copper_ant"
	butchery_loot = list(\
		/obj/item/stack/material/copper = 18\
		)
	harvest_results = list(
		/obj/item/stack/material/copper = 10
		)
	meat_amount = 3
	meat_type = /obj/item/reagent_containers/food/snacks/tyrant_burn

/mob/living/simple_mob/animal/tyr/mineral_ants/copper/bullet_act(obj/item/projectile/P)
	if(istype(P, /obj/item/projectile/energy) || istype(P, /obj/item/projectile/beam))
		visible_message(span_cult("[P] seems ineffective!."))
	else
		..()

/mob/living/simple_mob/animal/tyr/mineral_ants/agate //rushes at you and explodes
	name = "agate metal ant"
	icon_state = "agate_ant"
	icon_living = "agate_ant"
	movement_cooldown = -3
	butchery_loot = list(\
		/obj/item/stack/material/weathered_agate = 18\
		)
	harvest_results = list(
		/obj/item/stack/material/weathered_agate = 10
		)
	meat_amount = 3
	meat_type = /obj/item/reagent_containers/food/snacks/tyrant_bonus

	special_attack_min_range = 0
	special_attack_max_range = 4
	special_attack_cooldown = 10 SECONDS

	color = "#FF7D51"
	glow_range = 5
	glow_intensity = 2
	glow_toggle = TRUE
	var/exploded = FALSE
	var/explosion_delay_lower	= 3 SECOND	// Lower bound for explosion delay.
	var/explosion_delay_upper	= 4 SECONDS	// Upper bound.

/mob/living/simple_mob/animal/tyr/mineral_ants/agate/proc/explode()
	if(src && !exploded)
		act_message(src, null, null, MSG_OTHERS(span_danger("%U%'s body detonates!")))
		exploded = TRUE
		explosion(src.loc, 0, 3, 0, 0)

/mob/living/simple_mob/animal/tyr/mineral_ants/agate/on_death(gibbed)
	act_message(src, null, null, MSG_OTHERS(span_critical("%U%'s body begins to rupture!")))
	var/delay = rand(explosion_delay_lower, explosion_delay_upper)
	animate(src, color = "#000000", time = 0.1 SECONDS, loop = ceil(delay/2))
	animate(color = "#FF0000", time = 0.1 SECONDS)
	after(src, delay, PROC_REF(explode))
	return ..()

/mob/living/simple_mob/animal/tyr/mineral_ants/agate/do_special_attack(atom/A, stance)
	injure(INJURY_BLUNT, 30, source = src)

/mob/living/simple_mob/animal/tyr/mineral_ants/quartz //irl quartz is apparently tough?
	name = "quartz metal ant"
	icon_state = "quartz_ant"
	icon_living = "quartz_ant"
	armor_spec = "melee=80;bullet=80;bio=100;rad=100"
	butchery_loot = list(\
		/obj/item/stack/material/quartz = 18\
		)
	harvest_results = list(
		/obj/item/stack/material/quartz = 10
		)
	meat_amount = 3
	meat_type = /obj/item/reagent_containers/food/snacks/tyrant_radiation

/mob/living/simple_mob/animal/tyr/mineral_ants/diamond //slower, tankier, more damage
	name = "diamond metal ant"
	icon_state = "diamond_ant"
	icon_living = "diamond_ant"
	endurance = 50
	melee_damage_lower = 24
	melee_damage_upper = 24
	movement_cooldown = 3
	meat_type = /obj/item/reagent_containers/food/snacks/tyrant_neoburn
	butchery_loot = list(\
		/obj/item/stack/material/diamond = 18\
		)
	harvest_results = list(
		/obj/item/stack/material/diamond = 10
		)

/mob/living/simple_mob/animal/tyr/mineral_ants/verdantium
	name = "green metal ant"
	evasion = 50
	icon_state = "verdantium_ant"
	icon_living = "verdantium_ant"
	meat_type = /obj/item/reagent_containers/food/snacks/tyrant_radiation
	butchery_loot = list(\
		/obj/item/stack/material/verdantium = 18\
		)
	harvest_results = list(
		/obj/item/stack/material/verdantium = 10
		)

/mob/living/simple_mob/animal/tyr/mineral_ants/uranium //if it melees, it unleashes rads
	name = "glowing metal ant"
	icon_state = "rad_ant"
	icon_living = "rad_ant"
	meat_type = /obj/item/reagent_containers/food/snacks/tyrant_radiation
	butchery_loot = list(\
		/obj/item/stack/material/uranium = 18\
		)
	harvest_results = list(
		/obj/item/stack/material/uranium = 10
		)
	special_attack_min_range = 1
	special_attack_max_range = 2
	special_attack_cooldown = 5 SECONDS

	color = "#91FF91"
	glow_range = 5
	glow_intensity = 2
	glow_toggle = TRUE

/mob/living/simple_mob/animal/tyr/mineral_ants/uranium/do_special_attack(atom/A, stance)
	visible_message(span_bolddanger(span_orange("The ant glows bright green!.")))
	radiation_pulse(
		src,
		max_range = 3,
		threshold = RAD_MEDIUM_INSULATION,
		chance = 100,
		strength = 15
	)

/mob/living/simple_mob/animal/tyr/mineral_ants/mhydro //smol
	name = "mhydro ant"
	icon_state = "mhydro_ant"
	icon_living = "mhydro_ant"
	meat_type = /obj/item/reagent_containers/food/snacks/tyrant_radiation
	butchery_loot = list(\
		/obj/item/stack/material/mhydrogen = 12\
		)
	harvest_results = list(
		/obj/item/stack/material/mhydrogen = 4
		)
	size_multiplier = 0.5
	mob_size = MOB_MINISCULE
	pass_flags = PASSTABLE
	layer = MOB_LAYER
	density = 0
	melee_damage_lower = 6
	melee_damage_upper = 6

/mob/living/simple_mob/animal/tyr/mineral_ants/painite //flames
	name = "painite metal ant"
	icon_state = "painite_ant"
	icon_living = "painite_ant"
	butchery_loot = list(\
		/obj/item/stack/material/painite = 18\
		)
	harvest_results = list(
		/obj/item/stack/material/painite = 10
		)
	meat_amount = 3
	meat_type = /obj/item/reagent_containers/food/snacks/tyrant_neoburn

/mob/living/simple_mob/animal/tyr/mineral_ants/painite/apply_melee_effects(atom/A)
	..()
	if(isliving(A))
		var/mob/living/L = A
		to_chat(L, span_danger("You've been burned by \the [src]!"))
		L.ignite_mob()

/mob/living/simple_mob/animal/tyr/mineral_ants/bronze //spawns a legion
	name = "bronze metal ant"
	icon_state = "bronze_ant"
	icon_living = "bronze_ant"
	butchery_loot = list(\
		/obj/item/stack/material/bronze = 18\
		)
	harvest_results = list(
		/obj/item/stack/material/bronze = 10
		)
	meat_amount = 3

	special_attack_min_range = 1
	special_attack_max_range = 7
	special_attack_cooldown = 10 SECONDS

/mob/living/simple_mob/animal/tyr/mineral_ants/bronze/do_special_attack(atom/A, stance)
	for(var/mob/living/L in orange(src, 7))
		if(IIsAlly(L))
			L.apply_body_effect(/datum/body_effect/technomancer/haste, 3, src)

/mob/living/simple_mob/animal/tyr/mineral_ants/graphite //nothing special here
	name = "graphite ant"
	icon_state = "graphite_ant"
	icon_living = "graphite_ant"
	meat_type = /obj/item/reagent_containers/food/snacks/tyrant_neoburn
	butchery_loot = list(\
		/obj/item/stack/material/graphite = 18\
		)
	harvest_results = list(
		/obj/item/stack/material/graphite = 10
		)

/mob/living/simple_mob/animal/tyr/mineral_ants/builder
	name = "tritium ant"
	icon_state = "builder_ant"
	icon_living = "builder_ant"
	butchery_loot = list(\
		/obj/item/stack/material/tritium = 18\
		)
	harvest_results = list(
		/obj/item/stack/material/tritium = 10
		)
	nutrition = 150
	var/build_type = /obj/random/ant_building

/mob/living/simple_mob/animal/tyr/mineral_ants/builder/life_special_due()
	return TRUE

/mob/living/simple_mob/animal/tyr/mineral_ants/builder/life_special(datum/seq_frame/life/F)
	if((src.ai_brain ? (src.ai_brain.primary_threat ? STANCE_FIGHT : STANCE_IDLE) : STANCE_IDLE) == STANCE_IDLE && !om_busy(src) && isturf(src.loc))
		src.build_tile(src.loc)

/// Starts building on `T`: a 5 s task (stays in place, conscious, one builder per turf).
/mob/living/simple_mob/animal/tyr/mineral_ants/builder/proc/build_tile(turf/T)
	if(nutrition < 75 || !istype(T) || (locate_within(T, /obj/effect/ant_structure)))
		return FALSE
	if(istext(om_task_start(/datum/om/task/mob_work/ant_build, src, T)))
		return FALSE
	act_message(src, null, null, MSG_OTHERS(span_notice("%U% begins to secrete a sticky substance.")))
	return TRUE

/mob/living/simple_mob/animal/tyr/mineral_ants/silver //transparent
	name = "silver ant"
	icon_state = "silver_ant"
	icon_living = "silver_ant"
	meat_type = /obj/item/reagent_containers/food/snacks/tyrant_neoburn
	butchery_loot = list(\
		/obj/item/stack/material/silver = 18\
		)
	harvest_results = list(
		/obj/item/stack/material/silver = 10
		)

/mob/living/simple_mob/animal/tyr/mineral_ants/gold //emp on death
	name = "gold ant"
	icon_state = "gold_ant"
	icon_living = "gold_ant"
	desc = "A large ant with a metallic golden rear end. Is crackling with lightning."
	meat_type = /obj/item/reagent_containers/food/snacks/tyrant_burn
	butchery_loot = list(\
		/obj/item/stack/material/gold = 18\
		)
	harvest_results = list(
		/obj/item/stack/material/gold = 10
		)
	var/exploded = FALSE
	var/explosion_delay_lower	= 4 SECOND	// Lower bound for explosion delay.
	var/explosion_delay_upper	= 5 SECONDS	// Upper bound.

/mob/living/simple_mob/animal/tyr/mineral_ants/gold/proc/explode()
	if(src && !exploded)
		act_message(src, null, null, MSG_OTHERS(span_danger("%U%'s body detonates!")))
		exploded = TRUE
		empulse(src, 1, 2, 0, 0)

/mob/living/simple_mob/animal/tyr/mineral_ants/gold/on_death(gibbed)
	act_message(src, null, null, MSG_OTHERS(span_critical("%U%'s body begins to rupture!")))
	var/delay = rand(explosion_delay_lower, explosion_delay_upper)
	animate(src, color = "#000000", time = 0.1 SECONDS, loop = ceil(delay/2))
	animate(color = "#FF0000", time = 0.1 SECONDS)
	after(src, delay, PROC_REF(explode))
	return ..()


/mob/living/simple_mob/animal/tyr/mineral_ants/queen //the nurses of the ants
	name = "queen ant"
	icon_state = "queen_ant"
	endurance = 60 //four hits with agate sword, five with spear, two with hammer, eight with bow
	butchery_loot = list(\
		/obj/item/stack/material/valhollide = 4\
		)
	nutrition = 630
	var/build_type = /obj/effect/spider/spiderling/antling


/mob/living/simple_mob/animal/tyr/mineral_ants/queen/life_special_due()
	return TRUE

/mob/living/simple_mob/animal/tyr/mineral_ants/queen/life_special(datum/seq_frame/life/F)
	if((src.ai_brain ? (src.ai_brain.primary_threat ? STANCE_FIGHT : STANCE_IDLE) : STANCE_IDLE) == STANCE_IDLE && !om_busy(src) && isturf(src.loc))
		src.build_tile(src.loc)

/// Starts building on `T`: a 5 s task (stays in place, conscious, one builder per turf).
/mob/living/simple_mob/animal/tyr/mineral_ants/queen/proc/build_tile(turf/T)
	if(nutrition < 75 || !istype(T) || (locate_within(T, /obj/effect/ant_structure)))
		return FALSE
	if(istext(om_task_start(/datum/om/task/mob_work/ant_build, src, T)))
		return FALSE
	act_message(src, null, null, MSG_OTHERS(span_notice("%U% begins to secrete a sticky substance.")))
	return TRUE

/*
ANT STRUCTURES
*/

/obj/structure/mob_spawner/ant_hill
	name = "ant hole"
	desc = "An entrance to the nest of metallic ants."
	icon = 'icons/obj/tribal_gear.dmi'
	icon_state = "hole"
	anchored = TRUE

	spawn_delay = 15 MINUTES


	simultaneous_spawns = 5

	destructible = 1
	max_integrity = 50 //Unsure why you would want to break it but you can

TYPE_TABLE(/obj/structure/mob_spawner/ant_hill, mob_spawner_types, list( \
	/mob/living/simple_mob/animal/tyr/mineral_ants/bronze = 1, \
	/mob/living/simple_mob/animal/tyr/mineral_ants/builder = 1, \
	/mob/living/simple_mob/animal/tyr/mineral_ants/copper = 1, \
	/mob/living/simple_mob/animal/tyr/mineral_ants/quartz = 1, \
	/mob/living/simple_mob/animal/tyr/mineral_ants/agate = 1, \
	/mob/living/simple_mob/animal/tyr/mineral_ants/painite = 1, \
	/mob/living/simple_mob/animal/tyr/mineral_ants/diamond = 1, \
	/mob/living/simple_mob/animal/tyr/mineral_ants/verdantium = 1, \
	/mob/living/simple_mob/animal/tyr/mineral_ants/uranium = 1, \
	/mob/living/simple_mob/animal/tyr/mineral_ants/mhydro = 1, \
	/mob/living/simple_mob/animal/tyr/mineral_ants/graphite = 1, \
	/mob/living/simple_mob/animal/tyr/mineral_ants/silver = 1, \
	/mob/living/simple_mob/animal/tyr/mineral_ants/gold = 1, \
	))

/obj/structure/mob_spawner/ant_hill/creatable
	simultaneous_spawns = 2

/obj/effect/ant_structure
	uses_integrity = TRUE
	name = "organic structure"
	desc = "A creation of metal ants."
	icon = 'icons/obj/tribal_gear.dmi'
	icon_state = "hole"
	anchored = TRUE
	density = FALSE
	max_integrity = 15 //1 thwack with sword, 2 with spear

EXTEND_INTERACTIONS(/obj/effect/ant_structure, \
	INTERACT_ITEM(null, PROC_REF(interaction_hit_ant_structure)), \
)

/// Old attackby: any item hits the structure, welders burn it (afterattack still follows, as before).
/obj/effect/ant_structure/proc/interaction_hit_ant_structure(mob/user, obj/item/held, datum/interaction/interaction)
	var/obj/item/W = held
	user.setClickCooldown(user.get_attack_speed(W))

	if(LAZYLEN(W.attack_verb))
		act_message(src, user, null, MSG_OTHERS(span_warning("%U% has been [pick(W.attack_verb)] with %I%[(user ? " by %T%." : ".")]")), item = W)
	else
		act_message(src, user, null, MSG_OTHERS(span_warning("%U% has been attacked with %I%[(user ? " by %T%." : ".")]")), item = W)

	var/damage = W.force / 4.0

	if(W.has_tool_quality(TOOL_WELDER))
		var/obj/item/weldingtool/WT = W.get_welder()

		if(WT.remove_fuel(0, user))
			damage = 15
			playsound(src, W.usesound, 100, 1)

	take_damage(damage, BRUTE, MELEE, sound_effect = FALSE)
	return INTERACTION_HANDLED_PASS


/obj/effect/ant_structure/proc/die()
	consume(src)

/obj/effect/ant_structure/atom_destruction(damage_flag)
	. = ..()
	die()
/obj/effect/ant_structure/trap
	name = "spore trap"
	var/modifiertype = /datum/body_effect/berserk

/obj/effect/ant_structure/trap/Crossed(atom/movable/source)
	if(source.is_incorporeal())
		return
	if(anchored && isliving(source))
		var/mob/living/L = source
		if(L.faction == FACTION_TYR_ANT)
			return
		else if(L.m_intent == I_RUN)
			act_message(L, src, MSG_SELF(span_danger("You step in %T%!")), MSG_OTHERS(span_danger("%U% steps in %T%.")), MSG_BLIND(span_hear(span_bold("You hear a strange rustling!"))))
			attack_mob(L)
	..()

/obj/effect/ant_structure/trap/proc/attack_mob(mob/living/L)
	L.apply_body_effect(modifiertype, 5 SECONDS)

/obj/effect/ant_structure/trap/burn
	icon_state = "burn_trap"
	//No modifier.

/obj/effect/ant_structure/trap/burn/attack_mob(mob/living/L)
	L.adjust_fire_stacks(5)
	L.ignite_mob()

/obj/effect/ant_structure/trap/slowdown
	icon_state = "slow_trap"
	modifiertype = /datum/body_effect/chilled

/obj/effect/ant_structure/trap/confusion
	icon_state = "confusion_trap"
	//No modifier.

/obj/effect/ant_structure/trap/confusion/attack_mob(mob/living/L)
	play_sfx(src, SFX_EFFECTS_GHOST2)
	if(L.get_ear_protection() == 0)
		L.status_at_least(STAT_CONFUSED, 10)

/obj/effect/ant_structure/trap/poison
	icon_state = "knock_trap"

/obj/effect/ant_structure/trap/poison/attack_mob(mob/living/L)
	to_chat(L, span_warning("You feel a sharp stabbing in your foot."))
	L.reagents.add_reagent(REAGENT_ID_STOXIN, 12)


/obj/effect/ant_structure/trap/trip
	icon_state = "trip_trap"

/obj/effect/ant_structure/trap/trip/attack_mob(mob/living/L)
	L.status_at_least(STAT_WEAKENED, 3)

/obj/effect/ant_structure/wall
	name = "Metant wall"
	icon_state = "wall"
	density = TRUE
	max_integrity = 25 //two hits with sword.

/obj/random/ant_building
	name = "ant stucture"
	desc = "This is a metant build"
	icon_state = "tool"

DECLARE_LOOT(/obj/random/ant_building, LOOT_TABLE(\
	/obj/effect/ant_structure/trap/poison, \
	/obj/effect/ant_structure/trap/burn, \
	/obj/effect/ant_structure/trap/slowdown, \
	/obj/effect/ant_structure/trap/confusion, \
	/obj/effect/ant_structure/trap/trip, \
	/obj/structure/mob_spawner/ant_hill/creatable))


/obj/effect/spider/spiderling/antling
	name = "antling"
	desc = "A tiny ant."
	icon = 'icons/obj/tribal_gear.dmi'
	icon_state = "antling"
	anchored = FALSE
	layer = HIDING_LAYER
	max_integrity = 3
	faction = FACTION_TYR_ANT

TYPE_TABLE(/obj/effect/spider/spiderling/antling, spiderling_grow_as, list(/mob/living/simple_mob/animal/tyr/mineral_ants/bronze, \
	/mob/living/simple_mob/animal/tyr/mineral_ants/builder, \
	/mob/living/simple_mob/animal/tyr/mineral_ants/copper, \
	/mob/living/simple_mob/animal/tyr/mineral_ants/quartz, \
	/mob/living/simple_mob/animal/tyr/mineral_ants/agate, \
	/mob/living/simple_mob/animal/tyr/mineral_ants/painite, \
	/mob/living/simple_mob/animal/tyr/mineral_ants/diamond, \
	/mob/living/simple_mob/animal/tyr/mineral_ants/verdantium, \
	/mob/living/simple_mob/animal/tyr/mineral_ants/uranium, \
	/mob/living/simple_mob/animal/tyr/mineral_ants/mhydro, \
	/mob/living/simple_mob/animal/tyr/mineral_ants/graphite, \
	/mob/living/simple_mob/animal/tyr/mineral_ants/silver, \
	/mob/living/simple_mob/animal/tyr/mineral_ants/gold))

/obj/effect/spider/spiderling/antling/created
	faction = FACTION_TYR

/// What the builder and the queen build (ant_build task).
/mob/living/simple_mob/animal/tyr/mineral_ants/proc/build_product()
	return null

/mob/living/simple_mob/animal/tyr/mineral_ants/builder/build_product()
	return build_type

/mob/living/simple_mob/animal/tyr/mineral_ants/queen/build_product()
	return build_type

/mob/living/simple_mob/animal/tyr/mineral_ants/proc/build_done(datum/om/task/task)
	var/turf/T = task.target
	var/product = build_product()
	if(!product || (locate_within(T, /obj/effect/ant_structure)))
		return
	adjust_nutrition(-30)
	new product(T)

/mob/living/simple_mob/animal/tyr/mineral_ants/proc/build_interrupted(datum/om/task/task)
	to_chat(src, span_warning("You need to stay still to build on \the [task.target]."))
