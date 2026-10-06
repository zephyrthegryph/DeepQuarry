// P2-D7: light-driven nutrition and healing, ONE implementation. The photosynthesis trait,
// diona and alraunes all use this trait state; subtypes only set data. Light is the turf's
// lumcount (0..1) from /mob/living/proc/skin_light_level(), which burninlight shares.
//
// Per life tick (never on a paused stasis frame, never dead: the stage's run_if):
//   - nutrition += light * nutrition_per_light (x (1 + boost * boosted_nutrition_mult)), up to
//     nutrition_max (+ boost * boosted_nutrition_max)
//   - shock relief of light * shock_relief_per_light (through adjust_shock())
//   - at light >= heal_min_light: every heal_per_light tag mends light * rate (x boost when
//     heal_needs_boost; none while toxins load the body when heal_blocked_by_toxins)
//   - without its light organ (light_organ, if set): no light at all, and below
//     starve_below_nutrition the tissue withers (starve_injury blunt, starve_shock).
// "boost" is the mob's photosynthesis_boost (0..1), the CO2 share of its last skin breath.
/datum/trait_state/photosynth
	var/nutrition_per_light = 0.1
	var/nutrition_max = 1000
	var/boosted_nutrition_mult = 0
	var/boosted_nutrition_max = 0
	var/shock_relief_per_light = 0
	/// Light needed before light heals. Null: light never heals.
	var/heal_min_light = null
	/// TREAT_* tag -> amount mended per unit of light.
	var/alist/heal_per_light
	var/heal_needs_boost = FALSE
	var/heal_blocked_by_toxins = FALSE
	/// Light under a sealed suit and helmet is multiplied by this.
	var/sealed_light_mult = 1
	/// Organ type photosynthesis needs, present and unbroken. Null: none.
	var/light_organ
	var/starve_below_nutrition = 0
	var/starve_injury = 0
	var/starve_shock = 0

/// Diona: the nymph node drinks light; without it the gestalt withers.
/datum/trait_state/photosynth/diona
	nutrition_per_light = 10
	nutrition_max = 400
	shock_relief_per_light = 10
	heal_min_light = 0.3
	heal_per_light = alist(TREAT_TISSUE_REPAIR = 5, TREAT_BURN_CARE = 5, TREAT_ANTITOXIN = 10, TREAT_OXYGENATION = 10)
	light_organ = /obj/item/organ/internal/diona/node
	starve_below_nutrition = 200
	starve_injury = 2
	starve_shock = 1

/// Alraunes: light feeds; CO2 from the skin breath multiplies it and lets light heal
/// (half as fast as diona at best). A sealed suit keeps most light off the skin.
/datum/trait_state/photosynth/alraune
	nutrition_per_light = 5
	nutrition_max = 200
	boosted_nutrition_mult = 5
	boosted_nutrition_max = 400
	heal_min_light = 0.02
	heal_per_light = alist(TREAT_TISSUE_REPAIR = 10, TREAT_BURN_CARE = 5)
	heal_needs_boost = TRUE
	heal_blocked_by_toxins = TRUE
	sealed_light_mult = 0.2

/datum/trait_state/photosynth/life_tick()
	if(QDELETED(owner) || owner.is_incorporeal())
		return
	var/light = 0
	if(has_light_organ())
		light = owner.skin_light_level(sealed_light_mult)
	else if(light_organ)
		if(owner.nutrition < starve_below_nutrition)
			wither()
		return
	if(light <= 0)
		return
	var/boost = owner.photosynthesis_boost
	feed(light, boost)
	if(shock_relief_per_light && iscarbon(owner))
		var/mob/living/carbon/C = owner
		C.adjust_shock(-light * shock_relief_per_light, "photosynthesis")
	if(!isnull(heal_min_light) && light >= heal_min_light)
		heal(light, boost)

/datum/trait_state/photosynth/proc/has_light_organ()
	if(!light_organ)
		return TRUE
	if(!ishuman(owner))
		return FALSE
	var/mob/living/carbon/human/H = owner
	var/obj/item/organ/O = locate_in_list(H.internal_organ_list(), light_organ)
	return O && !O.is_broken()

/datum/trait_state/photosynth/proc/feed(light, boost)
	var/cap = nutrition_max + boost * boosted_nutrition_max
	if(owner.nutrition >= cap)
		return
	var/gain = light * nutrition_per_light * (1 + boost * boosted_nutrition_mult)
	owner.adjust_nutrition(min(gain, cap - owner.nutrition))

/datum/trait_state/photosynth/proc/heal(light, boost)
	var/scale = light
	if(heal_needs_boost)
		if(!boost)
			return
		scale *= boost
	if(heal_blocked_by_toxins && owner.injury_load(INJURY_CATEGORY_TOXIC))
		return
	for(var/tag in heal_per_light)
		owner.mend(tag, scale * heal_per_light[tag])

/// Starving tissue withers.
/datum/trait_state/photosynth/proc/wither()
	if(starve_injury)
		owner.injure(INJURY_BLUNT, starve_injury)
	if(starve_shock && iscarbon(owner))
		var/mob/living/carbon/C = owner
		C.adjust_shock(starve_shock, "withering")

/// Light on this mob's skin, 0..1 (the turf's lumcount; none off a turf). `sealed_mult`
/// dims it under a sealed suit and helmet. Shared by photosynthesis and burninlight.
/mob/living/proc/skin_light_level(sealed_mult = 1)
	if(!isturf(loc))
		return 0
	var/turf/T = loc
	. = T.get_lumcount(0, 1)
	if(sealed_mult != 1 && ishuman(src))
		var/mob/living/carbon/human/H = src
		if(H.is_fully_sealed())
			. *= sealed_mult

/// Trait system: photosynthesis. Paused stasis frames and dead bodies skip it (P2-S6).
/// One Life step per cycle while attached (doc/rewrite/om_retirement.md L1).
/datum/trait_state/photosynth/life_steps()
	return list(seq_step(PROC_REF(life_tick), after = list(LIFE_INPUT, "life_type_pre"), key = "life_trait_photosynth", when = list("!in_stasis", "alive")))
