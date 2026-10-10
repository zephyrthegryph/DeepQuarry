/mob/living/simple_mob/vore/aggressive/macrophage
	name = "Germ"
	desc = "A giant virus!"
	icon = 'icons/mob/macrophage.dmi'
	icon_state = "macrophage-1"

	faction = FACTION_MACROBACTERIA
	endurance = 20

	minbodytemp = T0C-30
	heat_damage_per_tick = 40
	cold_damage_per_tick = 40

	min_oxy = 0
	max_oxy = 0
	min_tox = 0
	max_tox = 0
	min_co2 = 0
	max_co2 = 0
	min_n2 = 0
	max_n2 = 0
	unsuitable_atoms_damage = 0
	shock_resist = 0.5
	taser_kill = FALSE
	water_resist = 1

	var/datum/affliction/contagion/base_disease = null
	/// Strains the creature carries (owned copies, lazy).
	var/list/datum/affliction/contagion/infections

	melee_damage_lower = 1
	melee_damage_upper = 5
	grab_resist = 100
	see_in_dark = 8

	response_help = "shoos"
	response_disarm = "swats away"
	response_harm = "squashes"
	attacktext = list("squashed")
	friendly = list("shoos", "rubs")

	vore_bump_chance = "attempts to absorb"

	vore_active = TRUE
	vore_capacity = 1
	vore_pounce_chance = 45

	can_be_drop_prey = FALSE
	allow_mind_transfer = TRUE

	pass_flags = PASSTABLE | PASSMOB
	mob_size = MOB_TINY

CAPABILITIES(/mob/living/simple_mob/vore/aggressive/macrophage)
	every(3 MINUTES, then(PROC_REF(deathcheck)), when = nameof(deathwatch))
	// An extrapolator's probe stabs it (extrapolator_act()): the user works on the germ, next to it, for two seconds.
	op("extrapolate", ai(), takes("extrapolator"), wait(2 SECONDS), then(PROC_REF(extrapolator_act_macrophage_done)))
	owns_one(nameof(base_disease), /datum/affliction/contagion)
	owns_many(nameof(infections), /datum/affliction/contagion)


/mob/living/simple_mob/vore/aggressive/macrophage/giant
	name = "Giant Germ"
	desc = "An incredibly huge virus!"

	size_multiplier = 1.75

	endurance = 40

	pass_flags = PASSTABLE | PASSGRILLE

// ALLOW(init/INSTANCE_STATE): rolls the disease that hardens it
/mob/living/simple_mob/vore/aggressive/macrophage/Initialize(mapload)
	. = ..()
	var/datum/affliction/contagion/engineered/random/macrophage/D = new
	endurance += D.resistance
	melee_damage_lower += max(0, D.resistance)
	melee_damage_upper += max(0, D.resistance)
	rel_set(src, nameof(base_disease), D)

/mob/living/simple_mob/vore/aggressive/macrophage/extrapolator_act(mob/living/user, obj/item/extrapolator/extrapolator, dry_run = FALSE)
	. = ..()
	EXTRAPOLATOR_ACT_ADD_DISEASES(., base_disease)
	// Still no idea why extrapolator == src, but I'll leave this for later if I find out.
	// if(!dry_run && !EXTRAPOLATOR_ACT_CHECK(., EXTRAPOLATOR_ACT_PRIORITY_SPECIAL) && extrapolator.create_culture(user, base_disease))
	if(dry_run)
		return
	perform_op(user, src, "extrapolate", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("extrapolator" = extrapolator))
	EXTRAPOLATOR_ACT_SET(., EXTRAPOLATOR_ACT_PRIORITY_SPECIAL)

/mob/living/simple_mob/vore/aggressive/macrophage/proc/extrapolator_act_macrophage_done(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/extrapolator/extrapolator = A.arg("extrapolator")
	if(QDELETED(extrapolator))
		return
	act_message(user, src, \
		MSG_SELF(span_danger("You stab %T% with [extrapolator]'s probe, destroying it!")), \
		MSG_OTHERS(span_danger("%U% stabs %T% with [extrapolator], sucking it up!")))
	death()

/// Burst from a host: it dies within 3 minutes unless it is holding a human. A field: the check
/// repeats while it is set.
/mob/living/simple_mob/vore/aggressive/macrophage/var/deathwatch = FALSE
TRACKED_BRIDGED(/mob/living/simple_mob/vore/aggressive/macrophage, deathwatch, CHANGE_MOB_CONDITIONS)

/// Every 3 minutes while deathwatch is set (its every() in the type's CAPABILITIES).
/mob/living/simple_mob/vore/aggressive/macrophage/proc/deathcheck(datum/act/A)
	if(locate_in_list(vore_selected, /mob/living/carbon/human))
		return
	set_deathwatch(FALSE)
	death()

/mob/living/simple_mob/vore/aggressive/macrophage/apply_melee_effects(atom/A)
	if(ishuman(A) && prob(25))
		var/mob/living/carbon/human/H = A
		H.expose_contagion(base_disease)
/*
/mob/living/simple_mob/vore/aggressive/macrophage/do_special_attack(atom/A, stance)
	. = TRUE
	ai_busy_begin()
	do_windup_animation(A, 20)
	after(src, 2 SECONDS, PROC_REF(charge), with = list(A))

/mob/living/simple_mob/vore/aggressive/macrophage/proc/charge(atom/A)
	if(QDELETED(A) || !isturf(get_turf(A)))
		ai_busy_end()
		return
	status_flags |= LEAPING
	flying = TRUE
	dq_set_hovering(src, TRUE)
	act_message(src, A, null, MSG_OTHERS(span_warning("%U% lunges at %T%!")))
	throw_at(A, 7, 2)
	if(status_flags & LEAPING)
		status_flags &= ~LEAPING
	flying = FALSE
	dq_set_hovering(src, FALSE)

	var/mob/living/target = null
	if(Adjacent(A))
		target = A

	if(ishuman(target))
		var/mob/living/carbon/human/H = target
		H.expose_contagion(base_disease)
	ai_busy_end()
*/
/mob/living/simple_mob/vore/aggressive/macrophage
	delete_on_death = TRUE

/mob/living/simple_mob/vore/aggressive/macrophage/on_death(gibbed)
	..()
	if(isbelly(loc))
		var/obj/belly/belly = loc
		if(belly)
			var/mob/living/pred = belly.owner
			pred.force_contagion(base_disease)
	else
		act_message(src, null, null, MSG_OTHERS(span_warning("%U% shrivels up and dies, unable to survive!")))
		var/obj/effect/decal/cleanable/blood/sick = new(loc)
		sick.name = "plasma"
		sick.set_basecolor("#47cbcf")
		sick.pixel_x = rand(-24, 24)
		sick.pixel_y = rand(-24, 24)
		rel_add(sick, nameof(sick.viruses), base_disease.Copy())

/obj/belly/macrophage
	name = "capsid"
	fancy_vore = TRUE
	contamination_color = "green"
	vore_verb = "absorb"
	escapable = B_ESCAPABLE_DEFAULT
	escapechance = 20
	desc = "In an attempt to get away from the giant virus, it's oversized envelope proteins dragged you right past it's matrix, encapsulating you deep inside it's capsid... The strange walls kneading and keeping you tight along within it's nucleoprotein."
	belly_fullscreen = "VBO_gematically_angular"
	belly_fullscreen_color = "#87d8d8"
	digest_mode = DM_ABSORB
	affects_vore_sprites = FALSE

/mob/living/simple_mob/vore/aggressive/macrophage/load_default_bellies()
	var/obj/belly/B = new /obj/belly/macrophage(src)
	rel_set(src, nameof(vore_selected), B)

// The macrophage's own strain (owned); victims and decals get their own copies.
