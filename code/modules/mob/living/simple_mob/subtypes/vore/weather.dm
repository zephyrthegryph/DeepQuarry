/mob/living/simple_mob/vore/fossiltank //slow but endless hunter
	name = "rolling crematorium"
	desc = "A large metal tank."
	endurance = 200
	armor_spec = "melee=60;bullet=60;laser=60;energy=60;bomb=80;bio=100;rad=100" //High armor, relativly low HP
	icon_state = "rex"
	melee_attack_delay = 2.5 SECONDS
	melee_damage_lower = 50
	melee_damage_upper = 50
	attack_armor_pen = 50
	damage_fatigue_mult = 1 //Does slowly pick up speed.
	injury_enrages = TRUE
	movement_cooldown = 7 //Kind of slow.
	movement_shake_radius = 8
	taser_kill = FALSE
	poison_resist = 1.0
	shock_resist = -0.2
	icon = 'icons/mob/tyr.dmi'
	special_attack_min_range = 1
	special_attack_max_range = 20 //The special attacks are more meant to pin you down or provide a healing to this tank.
	special_attack_cooldown = 8 SECONDS //1 fire ticks a second
	swallowTime = 1.5 SECONDS
	vore_active = 1
	vore_capacity = 1
	vore_bump_chance = 10
	vore_pounce_chance = 50
	vore_pounce_cooldown = 10
	vore_pounce_successrate	= 75
	vore_pounce_falloff = 0
	vore_pounce_maxhealth = 100
	vore_standing_too = TRUE
	unacidable = TRUE
	grab_resist = 100
	devourable = FALSE
	faction = FACTION_ECLIPSE
	size_multiplier = 2
	var/regenration_rate = -15

	loot_list = list(/obj/item/personal_shield_generator/belt/fossiltank  = 100,
		/obj/item/prop/tyrlore/fossiltank = 100,
		)

/mob/living/simple_mob/vore/fossiltank/emp_act
	regenration_rate = 0

/mob/living/simple_mob/vore/fossiltank/life_special_due()
	return TRUE

/mob/living/simple_mob/vore/fossiltank/life_special(datum/seq_frame/life/F)
	if(src.stat != DEAD)
		src.regenration()
	..()

/mob/living/simple_mob/vore/fossiltank/proc/regenration()
	if(regenration_rate < 0) // Negative = healing per tick.
		mend(TREAT_TISSUE_REPAIR, -regenration_rate)
		mend(TREAT_BURN_CARE, -regenration_rate)

/mob/living/simple_mob/vore/fossiltank/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected
	B.name = "furnace"
	B.desc = "Turns out the skull head opens, and you have been consumed into the beast's furnace! Sweltering heat rages around you as your metal confines rumble with the rurr of strange machinery. The chamber jostling you about as you may attempt to escape, or perhaps accept your fate."
	B.digest_brute = 0
	B.digest_burn = 3
	B.digestchance = 0
	B.absorbchance = 0
	B.escapechance = 15

/mob/living/simple_mob/vore/fossiltank/update_health_display()
	. = ..()
	var/wellness = vitality()
	if(wellness < 0.25)
		icon_state = "rex_25"
		set_icon_living("rex_25")
	else if(wellness < 0.5)
		icon_state = "rex_50"
		set_icon_living("rex_50")
	else if (wellness < 0.75)
		icon_state = "rex_75"
		set_icon_living("rex_75")
	else if (wellness > 0.75)
		icon_state = "rex"
		set_icon_living("rex")

/mob/living/simple_mob/vore/fossiltank/do_special_attack(atom/A, stance)
	for(var/mob/living/L in orange(src, 14))
		if(L.stat != DEAD && !IIsAlly(L))
			L.adjust_fire_stacks(9)
			L.ignite_mob()

/mob/living/simple_mob/vore/boss_jellyfish
	name = "expirmental jellyfish"
	desc = "A glowing green jellyfish"
	endurance = 600
	armor_spec = "melee=30;bullet=30;laser=30;energy=30;bomb=50;bio=100;rad=100" //So, it's made of jelly. Bullets and melee bounces off of it. The 20 laser and energy are for a smidge extra tankny because I savour endurance fights
	icon = 'icons/mob/tyr.dmi'
	icon_state = "jellyfish"
	icon_living = "jellyfish"
	icon_dead = "jellyfish_dead"
	movement_cooldown = 1
	damage_fatigue_mult = 0 //It's a mutant jellyfish boss mob.
	melee_attack_delay = 1.5 SECOND
	melee_damage_lower = 17 //designed to deal 17ish damage when wearing explo voidsuit
	melee_damage_upper = 17
	attack_armor_pen = 20
	glow_color = "#14ff20"
	light_color = "#14ff20"
	glow_range = 7
	glow_intensity = 3
	special_attack_min_range = 1
	special_attack_max_range = 7
	special_attack_cooldown = 13 SECONDS


	swallowTime = 1.5 SECONDS
	vore_active = 1
	vore_capacity = 1
	vore_bump_chance = 10
	vore_pounce_chance = 50
	vore_pounce_cooldown = 10
	vore_pounce_successrate	= 75
	vore_pounce_falloff = 0
	vore_pounce_maxhealth = 100
	vore_standing_too = TRUE
	unacidable = TRUE
	grab_resist = 100
	devourable = FALSE

	faction = FACTION_TYR_ANT

	loot_list = list(/obj/item/melee/jellyfishwhip  = 100,
		/obj/item/cell/slime/jellyfish  = 100,
		)

	var/leech = 50

/mob/living/simple_mob/vore/boss_jellyfish
	delete_on_death = TRUE

/// Attacks still to chain after a warp. A field: one chained attack every 4 s while it is non-zero.
/mob/living/simple_mob/vore/boss_jellyfish/var/chain_number = 0
TRACKED_BRIDGED(/mob/living/simple_mob/vore/boss_jellyfish, chain_number, CHANGE_MOB_CONDITIONS)
/// Who the chained attacks go at (a relation view).
/mob/living/simple_mob/vore/boss_jellyfish/var/atom/chain_target

CAPABILITIES(/mob/living/simple_mob/vore/boss_jellyfish)
	every(4 SECONDS, then(PROC_REF(chain_attack)), when = nameof(chain_number))

/// A dash or a puddle summon at the target (its every() runs while attacks remain in the chain).
/mob/living/simple_mob/vore/boss_jellyfish/proc/chain_attack(datum/act/timer_act)
	var/atom/A = chain_target
	if(!A)
		set_chain_number(0)
		icon_state = "jellyfish"
		set_icon_living("jellyfish")
		return
	set_chain_number(chain_number - 1)
	if(prob(50))
		icon_state = "jellyfish_yellow"
		set_icon_living("jellyfish_yellow")
		dash_attack(A)
	else
		icon_state = "jellyfish_red"
		set_icon_living("jellyfish_red")
		summon_puddles(A)

/mob/living/simple_mob/vore/boss_jellyfish/on_death(gibbed)
	..()

/mob/living/simple_mob/vore/boss_jellyfish/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected
	B.name = "internal chamber"
	B.desc = "It's smooth and translucent. You can see the world around you distort and wobble with the movement of the space jellyfish. It floats casually, while the delicate flesh seems to form to you. It's surprisingly cool, and flickers with its own light. You're on display for all to see, trapped within the confines of this strange space alien!"
	B.digest_brute = 1
	B.digest_burn = 1
	B.digestchance = 0
	B.absorbchance = 0
	B.escapechance = 15


/mob/living/simple_mob/vore/boss_jellyfish/apply_melee_effects(atom/A) //Not a real threat unless multiple hits. It acts a timer for special traits.
	if(isliving(A))
		var/mob/living/L = A
		if(L.nutrition)
			L.adjust_nutrition(-leech)
			adjust_nutrition(leech)

/mob/living/simple_mob/vore/boss_jellyfish/do_special_attack(atom/A, stance)
	if(nutrition > 500)
		Beam(A, icon_state = "sat_beam", time = 3.5 SECONDS, maxdistance = INFINITY)
		after(src, 4 SECONDS, PROC_REF(sniper_shot), with = list(A))
	else if(vitality() < 0.25) //phase 4 where it teleports then chains 3 attacks
		rel_set(src, nameof(chain_target), A)
		set_chain_number(3)
		after(src, 3 SECONDS, PROC_REF(astral_sea_warp), with = list(A), keeps_dead = TRUE)
		icon_state = "jellyfish_blue"
		set_icon_living("jellyfish_blue")
	else if(vitality() < 0.5) //teleports then chains 2 attacks
		rel_set(src, nameof(chain_target), A)
		set_chain_number(2)
		after(src, 3 SECONDS, PROC_REF(astral_sea_warp), with = list(A), keeps_dead = TRUE)
		icon_state = "jellyfish_blue"
		set_icon_living("jellyfish_blue")
	else if(vitality() < 0.75) //teleports then attacks
		rel_set(src, nameof(chain_target), A)
		set_chain_number(1)
		icon_state = "jellyfish_blue"
		set_icon_living("jellyfish_blue")
		after(src, 3 SECONDS, PROC_REF(astral_sea_warp), with = list(A), keeps_dead = TRUE)
	else //attacks once
		if(prob(50))
			icon_state = "jellyfish_yellow"
			set_icon_living("jellyfish_yellow")
			after(src, 4 SECONDS, PROC_REF(dash_attack), with = list(A), keeps_dead = TRUE)
		else
			icon_state = "jellyfish_red"
			set_icon_living("jellyfish_red")
			after(src, 4 SECONDS, PROC_REF(summon_puddles), with = list(A))

/mob/living/simple_mob/vore/boss_jellyfish/proc/dash_attack(atom/A) //spider dash attack
	ai_busy_begin()
	if(!A)
		ai_busy_end()
		return

	set_status_flags(status_flags | LEAPING)
	act_message(src, A, null, MSG_OTHERS(span_danger("%U% leaps at %T%!")))
	throw_at(get_step(get_turf(A), get_turf(src)), special_attack_max_range+1, 1, src)

	after(src, 0.5 SECONDS, PROC_REF(dash_attack_1), with = list(A)) // For the throw to complete. It won't hold up the AI ticker due to waitfor being false.


/mob/living/simple_mob/vore/boss_jellyfish/proc/dash_attack_1(atom/A)

	if(status_flags & LEAPING)
		set_status_flags(status_flags & ~LEAPING) // Revert special passage ability.

	var/turf/T = get_turf(src) // Where we landed. This might be different than A's turf.


	// Now for the stun.
	var/mob/living/victim = null
	for(var/mob/living/L in turf_contents_of_type(T, /mob/living)) // So player-controlled spiders only need to click the tile to stun them.
		if(L == src)
			continue

		if(ishuman(L))
			var/mob/living/carbon/human/H = L
			if(H.check_shields(damage = 0, damage_source = src, attacker = src, def_zone = null, attack_text = "the leap"))
				continue // We were blocked.

		victim = L
		break

	if(victim)
		victim.status_at_least(STAT_WEAKENED, 2)
		act_message(src, victim, null, MSG_OTHERS(span_danger("%U% knocks down %T%!")))
		to_chat(victim, span_critical("\The [src] jumps on you!"))
		. = TRUE

	ai_busy_end()
	if(!chain_number)
		icon_state = "jellyfish"
		set_icon_living("jellyfish")

/mob/living/simple_mob/vore/boss_jellyfish/proc/sniper_shot(atom/target)
	var/obj/item/projectile/P = new /obj/item/projectile/beam/nutrition_gigabeam(get_turf(src))
	P.launch_projectile(target, BP_TORSO, src)

/mob/living/simple_mob/vore/boss_jellyfish/proc/summon_puddles(atom/A)
	for(var/mob/living/L in view(src, 7))
		if(L.stat != DEAD || !IIsAlly(L))
			L.apply_body_effect(/datum/body_effect/mmo_drop/jelly_fish, 3, src)
	if(!chain_number)
		icon_state = "jellyfish"
		set_icon_living("jellyfish")

/obj/item/projectile/beam/nutrition_gigabeam
	damage = 40
	armor_penetration = 90

/mob/living/simple_mob/vore/boss_jellyfish/proc/astral_sea_warp(atom/target)
	if(!target)
		to_chat(src, span_warning("There's nothing to teleport to."))
		return FALSE

	var/list/nearby_things = range(3, target)
	var/list/valid_turfs = list()

	// All this work to just go to a non-dense tile.
	for(var/turf/potential_turf in nearby_things)
		var/valid_turf = TRUE
		if(potential_turf.density)
			continue
		for(var/atom/movable/AM in potential_turf)
			if(AM.density)
				valid_turf = FALSE
		if(valid_turf)
			valid_turfs.Add(potential_turf)

	if(!(valid_turfs.len))
		to_chat(src, span_warning("There wasn't an unoccupied spot to teleport to."))
		return FALSE

	var/turf/target_turf = pick(valid_turfs)
	var/turf/T = get_turf(src)

	var/datum/effect/effect/system/smoke_spread/s1 = new /datum/effect/effect/system/smoke_spread
	s1.set_up(5, 1, T)
	var/datum/effect/effect/system/smoke_spread/s2 = new /datum/effect/effect/system/smoke_spread
	s2.set_up(5, 1, target_turf)


	T.visible_message(span_notice("\The [src] vanishes!"))
	s1.start()

	forceMove(target_turf)
	play_sfx(target_turf, SFX_EFFECTS_PHASEIN, 0.5)
	to_chat(src, span_notice("You teleport to \the [target_turf]."))

	target_turf.visible_message(span_warning("\The [src] appears!"))
	s2.start()
