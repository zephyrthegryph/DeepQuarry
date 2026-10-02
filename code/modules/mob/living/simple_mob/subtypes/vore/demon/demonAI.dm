/mob/living/simple_mob/vore/demonAI
	reaction_sound = SFX_MISC_DEMONLAUGH
	name = "Rift Walker"
	desc = "A large bipedal creature, its body has a mixture of dark fur and scales. Marks on the creature's body pulse slowly with red light."

	icon_state = "boxfox"
	icon_living = "boxfox"
	icon_dead = "dead"
	icon_rest = "boxfox_rest"
	icon = 'icons/mob/demon_vr.dmi'
	vis_height = 47
	var/cloaked_alpha = 60			// Lower = Harder to see.
	var/cloaked_bonus_damage = 30	// This is added on top of the normal melee damage.
	var/cloaked_weaken_amount = 3	// How long to stun for.
	var/cloak_cooldown = 10 SECONDS	// Amount of time needed to re-cloak after losing it.
	COOLDOWN_DECLARE(uncloak_cooldown)			// world.time

	faction = "demon"
	endurance = 200
	movement_cooldown = 0

	see_in_dark = 10
	has_hands = TRUE
	seedarkness = FALSE
	attack_sound = SFX_MISC_DEMONATTACK
	has_langs = list(LANGUAGE_GALCOM,LANGUAGE_SHADEKIN,LANGUAGE_CULT)

	melee_damage_lower = 10
	melee_damage_upper = 5
	var/poison_chance = 50
	var/poison_type = REAGENT_ID_MINDBREAKER
	var/poison_per_bite = 3

	min_oxy = 0
	max_oxy = 0
	min_tox = 0
	max_tox = 0
	min_co2 = 0
	max_co2 = 0
	min_n2 = 0
	max_n2 = 0
	minbodytemp = 0
	maxbodytemp = 96669

	response_help = "touches"
	response_disarm = "pushes"
	response_harm = "hits"

	attacktext = list("mauled","slashed","clawed")
	friendly = list("pokes", "scratches", "rurrs softly at", "sniffs on")

	vore_active = 1
	swallowTime = 2 SECOND
	vore_pounce_chance = 15
	vore_icons = SA_ICON_LIVING
	vore_escape_chance = 25

	var/shifted_out = FALSE
	var/shift_state = AB_SHIFT_NONE
	EXPIRY_DECLARE(last_shift)
	EXPIRY_DECLARE(blood_spawn)
	var/is_shifting = FALSE

	can_pain_emote = FALSE
	injury_enrages = TRUE

/mob/living/simple_mob/vore/demonAI/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected
	B.name = "Stomach"
	B.desc = "You slide down the slick, slippery gullet of the creature. It's warm, and the air is thick. You can feel the doughy walls of the creatures gut push and knead into your form! Slimy juices coat your form stinging against your flesh as they waste no time to start digesting you. The creature's heartbeat and the gurgling of their stomach are all you can hear as your jostled about, treated like nothing but food."

/mob/living/simple_mob/vore/demonAI/UnarmedAttack()
	if(shifted_out)
		return FALSE
	. = ..()

/mob/living/simple_mob/vore/demonAI/can_fall()
	if(shifted_out)
		return FALSE
	. = ..()

/mob/living/simple_mob/vore/demonAI/zMove(direction)
	if(shifted_out)
		var/turf/destination = (direction == UP) ? GetAbove(src) : GetBelow(src)
		if(destination)
			forceMove(destination)
		return TRUE
	. = ..()

/datum/om/stage/life/type_post/simple_mob/vore/demonAI
	of = /mob/living/simple_mob/vore/demonAI

/datum/om/stage/life/type_post/simple_mob/vore/demonAI/perform(mob/living/simple_mob/vore/demonAI/self, datum/om/frame/life/ctx)
	..()
	if(self.shifted_out)
		self.set_density(FALSE)

/datum/om/stage/life/environment/simple_mob/vore/demonAI
	of = /mob/living/simple_mob/vore/demonAI

/// TODO - Refactor demons to use is_incorporeal()
/datum/om/stage/life/environment/simple_mob/vore/demonAI/exchange(mob/living/simple_mob/vore/demonAI/self, datum/gas_mixture/environment)
	if(self.shifted_out)
		return
	. = ..()

/mob/living/simple_mob/vore/demonAI/update_canmove()
	if(is_shifting)
		canmove = FALSE
		return canmove
	else
		return ..()

/mob/living/simple_mob/vore/demonAI/cloak()
	if(dq_get_cloaked(src))
		return
	set_alpha_source(ALPHA_SOURCE_CREATURE_CLOAK, cloaked_alpha/255, animate_time = 1 SECOND)
	dq_set_cloaked(src, TRUE)


/mob/living/simple_mob/vore/demonAI/uncloak()
	COOLDOWN_START(src, uncloak_cooldown, cloak_cooldown)// This is assigned even if it isn't dq_get_cloaked(src) already, to 'reset' the timer if the spider is continously getting attacked.
	if(!dq_get_cloaked(src))
		return
	clear_alpha_source(ALPHA_SOURCE_CREATURE_CLOAK, animate_time = 1 SECOND)
	dq_set_cloaked(src, FALSE)

// Check if cloaking if possible.
/mob/living/simple_mob/vore/demonAI/proc/can_cloak()
	if(stat)
		return FALSE
	if(!COOLDOWN_FINISHED(src, uncloak_cooldown))
		return FALSE

	return TRUE

// Called by things that break cloaks, like Technomancer wards.
/mob/living/simple_mob/vore/demonAI/break_cloak()
	uncloak()

/mob/living/simple_mob/vore/demonAI/is_cloaked()
	return dq_get_cloaked(src)

// Cloaks the spider automatically, if possible.
/datum/om/stage/life/special/vore/demonAI
	of = /mob/living/simple_mob/vore/demonAI

/datum/om/stage/life/special/vore/demonAI/perform(mob/living/simple_mob/vore/demonAI/self, datum/om/frame/life/ctx)
	if(!dq_get_cloaked(self) && self.can_cloak())
		self.cloak()

// Applies bonus base damage if dq_get_cloaked(src).
/mob/living/simple_mob/vore/demonAI/apply_bonus_melee_damage(atom/A, damage_amount)
	if(dq_get_cloaked(src))
		play_sfx(src.loc, SFX_EFFECTS_BLOBATTACK, volume = 50)
		uncloak()
		return damage_amount + cloaked_bonus_damage
	return ..()

// Force uncloaking if attacked.
DAMAGE_REACTION(/mob/living/simple_mob/vore/demonAI, DAMAGE_PROJECTILE, PROC_REF(laugh_at_hit))
DAMAGE_REACTION_AFTER(/mob/living/simple_mob/vore/demonAI, DAMAGE_PROJECTILE, PROC_REF(break_cloak))

/mob/living/simple_mob/vore/demonAI/proc/laugh_at_hit(datum/damage_packet/packet)
	play_sfx(src, SFX_MISC_DEMONLAUGH)

/mob/living/simple_mob/vore/demonAI/hit_with_weapon(obj/item/O, mob/living/user, effective_force, hit_zone)
	. = ..()
	break_cloak()

/mob/living/simple_mob/vore/demonAI/apply_melee_effects(atom/A)
	if(isliving(A))
		var/mob/living/L = A
		if(L.reagents)
			var/target_zone = pick(BP_TORSO,BP_TORSO,BP_TORSO,BP_L_LEG,BP_R_LEG,BP_L_ARM,BP_R_ARM,BP_HEAD)
			if(L.can_inject(src, null, target_zone))
				inject_poison(L, target_zone)

/mob/living/simple_mob/vore/demonAI/proc/inject_poison(mob/living/L, target_zone)
	if(prob(poison_chance))
		to_chat(L, span_warning("You feel a tiny prick."))
		L.reagents.add_reagent(poison_type, poison_per_bite)


/mob/living/simple_mob/vore/demonAI/on_death(gibbed)
	play_sfx(src, SFX_MISC_DEMONDEATH)
	..()

/mob/living/simple_mob/vore/demonAI/gibspam

/mob/living/simple_mob/vore/demonAI/gibspam/apply_bonus_melee_damage(atom/A, damage_amount)
	var/turf/T = get_turf(src)
	if(dq_get_cloaked(src))
		gibs(T)
	return ..()

// Tracked inputs of the Life presentation reactions (HUD, sight, canmove; living_systems.dm): their setters publish.
TRACKED(/mob/living/simple_mob/vore/demonAI, is_shifting)
