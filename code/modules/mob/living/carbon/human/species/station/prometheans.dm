// Species definition follows.
/datum/species/shapeshifter/promethean
	name =             SPECIES_PROMETHEAN
	name_plural =      "Prometheans"
	blurb =            "Prometheans (Macrolimus artificialis) are a species of artificially-created gelatinous humanoids, \
	chiefly characterized by their primarily liquid bodies and ability to change their bodily shape and color in order to  \
	mimic many forms of life. Derived from the Aetolian giant slime (Macrolimus vulgaris) inhabiting the warm, tropical planet \
	of Aetolus, they are a relatively new lab-created sapient species, and as such many things about them have yet to be comprehensively studied. \
	What has Science done?"
	wikilink="https://wiki.chompstation13.net/index.php?title=Promethean"
	catalogue_data = list(/datum/category_item/catalogue/fauna/promethean)
	show_ssd =         "totally quiescent"
	death_message =    "rapidly loses cohesion, splattering across the ground..."
	knockout_message = "collapses inwards, forming a disordered puddle of goo."
	remains_type = /obj/effect/decal/cleanable/ash

	blood_color = "#05FF9B"
	flesh_color = "#05FFFB"
	color_mult = 1

	hunger_factor =	0.2
	reagent_tag =	IS_SLIME
	mob_size =		MOB_MEDIUM
	push_flags =	~HEAVY
	swap_flags =	~HEAVY
	flags =			NO_DNA | NO_SLEEVE | NO_SLIP | NO_MINOR_CUT | NO_HALLUCINATION | NO_INFECT | NO_DEFIB
	appearance_flags = HAS_SKIN_COLOR | HAS_EYE_COLOR | HAS_HAIR_COLOR | RADIATION_GLOWS | HAS_UNDERWEAR
	spawn_flags = SPECIES_CAN_JOIN
	health_hud_intensity = 2
	num_alternate_languages = 3
	language = LANGUAGE_PROMETHEAN
	species_language = LANGUAGE_PROMETHEAN
	secondary_langs = list(LANGUAGE_PROMETHEAN, LANGUAGE_SOL_COMMON)	// For some reason, having this as their species language does not allow it to be chosen.
	assisted_langs = list(LANGUAGE_ROOTGLOBAL, LANGUAGE_VOX)	// Prometheans are weird, let's just assume they can use basically any language.

	species_component = list(/datum/component/radiation_effects/promethean, /datum/component/forms/promethean, /datum/component/promethean_biology)

	blood_name = "gelatinous ooze"
	blood_reagents = REAGENT_ID_SLIMEJELLY

	breath_type = null
	poison_type = null

	speech_bubble_appearance = "slime"

	species_sounds = "Slime"

	min_age = 18
	max_age = 80

	economic_modifier = 3

	virus_immune =	1
	blood_volume =	560
	factor_baseline = alist(BF_INCOMING_PHYSICAL = 0.7, BF_INCOMING_THERMAL = 1.6, BF_DEMAND = 0)
	//chompedit Old values of .75 brute and 2 burn were imbalanced. (brute)
	//chompedit (burn)
	flash_mod =		0.5 //No centralized, lensed eyes.
	item_slowdown_mod = 1.33
	throwforce_absorb_threshold = 10

	chem_strength_alcohol = 0.5

	cloning_modifier = /datum/modifier/cloning_sickness/promethean

	cold_level_1 = 280 //Default 260 - Lower is better
	cold_level_2 = 220 //Default 200
	cold_level_3 = 130 //Default 120

	heat_level_1 = 320 //Default 360
	heat_level_2 = 370 //Default 400
	heat_level_3 = 600 //Default 1000

	body_temperature = T20C	// Room temperature

	rarity_value = 5
	siemens_coefficient = 0.8

	water_resistance = 0
	water_damage_mod = 0

	genders = list(MALE, FEMALE, PLURAL, NEUTER)

	unarmed_types = list(/datum/unarmed_attack/slime_glomp)

	has_organ =     list(O_BRAIN = /obj/item/organ/internal/brain/slime,
						O_HEART = /obj/item/organ/internal/heart/grey/colormatch/slime,
						O_REGBRUTE = /obj/item/organ/internal/regennetwork,
						O_REGBURN = /obj/item/organ/internal/regennetwork/burn,
						O_REGOXY = /obj/item/organ/internal/regennetwork/oxy,
						O_REGTOX = /obj/item/organ/internal/regennetwork/tox)

	dispersed_eyes = TRUE

	has_limbs = list(
		BP_TORSO =  list("path" = /obj/item/organ/external/chest/unbreakable/slime),
		BP_GROIN =  list("path" = /obj/item/organ/external/groin/unbreakable/slime),
		BP_HEAD =   list("path" = /obj/item/organ/external/head/unbreakable/slime),
		BP_L_ARM =  list("path" = /obj/item/organ/external/arm/unbreakable/slime),
		BP_R_ARM =  list("path" = /obj/item/organ/external/arm/right/unbreakable/slime),
		BP_L_LEG =  list("path" = /obj/item/organ/external/leg/unbreakable/slime),
		BP_R_LEG =  list("path" = /obj/item/organ/external/leg/right/unbreakable/slime),
		BP_L_HAND = list("path" = /obj/item/organ/external/hand/unbreakable/slime),
		BP_R_HAND = list("path" = /obj/item/organ/external/hand/right/unbreakable/slime),
		BP_L_FOOT = list("path" = /obj/item/organ/external/foot/unbreakable/slime),
		BP_R_FOOT = list("path" = /obj/item/organ/external/foot/right/unbreakable/slime)
		)
	heat_discomfort_strings = list("You feel too warm.")
	cold_discomfort_strings = list("You feel too cool.")

	inherent_verbs = list(
		/mob/living/carbon/human/proc/innate_shapeshifting,
		/mob/living/carbon/human/proc/regenerate,
		/mob/living/carbon/human/proc/prommie_blobform,
		/mob/living/proc/set_size,
		/mob/living/carbon/human/proc/promethean_select_opaqueness,
		/mob/living/carbon/human/proc/shapeshifter_reassemble // reform verb
		)

	valid_transform_species = list(
		SPECIES_HUMAN, SPECIES_UNATHI, SPECIES_TAJARAN, SPECIES_SKRELL,
		SPECIES_DIONA, SPECIES_TESHARI, SPECIES_MONKEY, SPECIES_SERGAL,
		SPECIES_AKULA, SPECIES_NEVREAN, SPECIES_ZORREN_HIGH,
		SPECIES_FENNEC, SPECIES_VULPKANIN, SPECIES_VASILISSAN,
		SPECIES_RAPALA, SPECIES_MONKEY_SKRELL, SPECIES_MONKEY_UNATHI, SPECIES_MONKEY_TAJ, SPECIES_MONKEY_AKULA,
		SPECIES_MONKEY_VULPKANIN, SPECIES_MONKEY_SERGAL, SPECIES_MONKEY_NEVREAN)

	/// Regeneration per tick, per mechanism, while still, warm and pressurised.
	var/heal_rate = 0.5

	default_emotes = list(
		/datum/decl/emote/audible/squish,
		/datum/decl/emote/audible/chirp,
		/datum/decl/emote/visible/bounce,
		/datum/decl/emote/visible/jiggle,
		/datum/decl/emote/visible/lightup,
		/datum/decl/emote/visible/vibrate
	)

	footstep = FOOTSTEP_MOB_SLIME

/datum/species/shapeshifter/promethean/equip_survival_gear(mob/living/carbon/human/H)
	var/boxtype = pick(list(/obj/item/storage/toolbox/lunchbox,
							/obj/item/storage/toolbox/lunchbox/heart,
							/obj/item/storage/toolbox/lunchbox/cat,
							/obj/item/storage/toolbox/lunchbox/nt,
							/obj/item/storage/toolbox/lunchbox/mars,
							/obj/item/storage/toolbox/lunchbox/cti,
							/obj/item/storage/toolbox/lunchbox/nymph,
							/obj/item/storage/toolbox/lunchbox/syndicate))	//Only pick the empty types
	var/obj/item/storage/toolbox/lunchbox/L = new boxtype(get_turf(H))
	new /obj/item/reagent_containers/food/snacks/candy/proteinbar(L)
	new /obj/item/tool/prybar/red(L)
	if(H.backbag == 1)
		H.equip_to_slot_or_del(L, slot_r_hand)
	else
		H.equip_to_slot_or_del(L, slot_in_backpack)

/datum/species/shapeshifter/promethean/hug(mob/living/carbon/human/H, mob/living/target)
	var/static/list/parent_handles = list("head", "r_hand", "l_hand", "mouth")

	if(H.zone_sel.selecting in parent_handles)
		return ..()

	var/t_him = "them"
	if(ishuman(target))
		var/mob/living/carbon/human/T = target
		switch(T.identifying_gender)
			if(MALE)
				t_him = "him"
			if(FEMALE)
				t_him = "her"
	else
		switch(target.gender)
			if(MALE)
				t_him = "him"
			if(FEMALE)
				t_him = "her"

	H.visible_message(span_infoplain(span_bold("\The [H]") + " glomps [target] to make [t_him] feel better!"), \
					span_notice("You glomp [target] to make [t_him] feel better!"))
	H.apply_stored_shock_to(target)

/datum/species/shapeshifter/promethean/handle_death(mob/living/carbon/human/H)
	if(!H)
		return
	addtimer(CALLBACK(H, TYPE_PROC_REF(/mob, gib)), 1)

/datum/species/shapeshifter/promethean/get_blood_colour(mob/living/carbon/human/H)
	return (H ? rgb(H.r_skin, H.g_skin, H.b_skin) : ..())

/datum/species/shapeshifter/promethean/get_flesh_colour(mob/living/carbon/human/H)
	return (H ? rgb(H.r_skin, H.g_skin, H.b_skin) : ..())

/datum/species/shapeshifter/promethean/get_additional_examine_text(mob/living/carbon/human/H)

	if(!GLOB.stored_shock_by_ref["\ref[H]"])
		return

	var/t_she = "She is"
	if(H.identifying_gender == MALE)
		t_she = "He is"
	else if(H.identifying_gender == PLURAL)
		t_she = "They are"
	else if(H.identifying_gender == NEUTER)
		t_she = "It is"
	else if(H.identifying_gender == HERM)
		t_she = "Shi is"

	switch(GLOB.stored_shock_by_ref["\ref[H]"])
		if(1 to 10)
			return "[t_she] flickering gently with a little electrical activity."
		if(11 to 20)
			return "[t_she] glowing gently with moderate levels of electrical activity.\n"
		if(21 to 35)
			return span_warning("[t_she] glowing brightly with high levels of electrical activity.")
		if(35 to INFINITY)
			return span_danger("[t_she] radiating massive levels of electrical activity!")

/mob/living/carbon/human/proc/innate_shapeshifting()
	set name = "Transform Appearance"
	set category = "Abilities.Superpower"
	var/datum/tgui_module/appearance_changer/innate/I = new(src, src)
	I.tgui_interact(src)

// --- Promethean biology --------------------------------------------------------------
// Everything a promethean body does on its own, driven by events instead of a
// per-tick scan: stillness is a timer reset on Moved, cleaning happens on turf
// entry and on equip, water is a dissolution affliction, and regeneration runs
// only while still, warm, pressurised and dry.

#define PROMETHEAN_STILLNESS_TIME (1 MINUTES)
#define PROMETHEAN_PAIN_CAP 70
#define PROMETHEAN_STARVING_PAIN_CAP 90

/datum/component/promethean_biology
	dupe_mode = COMPONENT_DUPE_UNIQUE
	/// Held still for PROMETHEAN_STILLNESS_TIME.
	var/still = FALSE
	/// Stillness timer id.
	var/still_timer

/datum/component/promethean_biology/Initialize()
	if(!ishuman(parent))
		return COMPONENT_INCOMPATIBLE

/datum/component/promethean_biology/RegisterWithParent()
	RegisterSignal(parent, COMSIG_MOVABLE_MOVED, PROC_REF(on_moved))
	RegisterSignal(parent, COMSIG_MOB_EQUIPPED_ITEM, PROC_REF(on_equipped))
	add_trait_life_system(parent, /datum/life_system/trait/promethean_biology)
	restart_stillness()

/datum/component/promethean_biology/UnregisterFromParent()
	UnregisterSignal(parent, list(COMSIG_MOVABLE_MOVED, COMSIG_MOB_EQUIPPED_ITEM))
	remove_trait_life_system(parent, /datum/life_system/trait/promethean_biology)
	if(still_timer)
		deltimer(still_timer)
		still_timer = null

/datum/component/promethean_biology/proc/restart_stillness()
	still = FALSE
	still_timer = addtimer(CALLBACK(src, PROC_REF(became_still)), PROMETHEAN_STILLNESS_TIME, TIMER_UNIQUE | TIMER_OVERRIDE | TIMER_STOPPABLE)

/datum/component/promethean_biology/proc/became_still()
	still = TRUE
	still_timer = null

/datum/component/promethean_biology/proc/on_moved(mob/living/carbon/human/source, atom/old_loc, dir, forced)
	SIGNAL_HANDLER
	restart_stillness()
	if(isturf(source.loc))
		clean_on_entry(source, source.loc)

/// Prometheans clean every surface they touch and feed on the grime.
/datum/component/promethean_biology/proc/clean_on_entry(mob/living/carbon/human/H, turf/T)
	var/gained = 0
	if(!(H.get_equipped_item(SLOT_ID_SHOES) || (H.get_equipped_item(SLOT_ID_SUIT) && (H.get_equipped_item(SLOT_ID_SUIT).body_parts_covered & FEET))))
		for(var/obj/O in T)
			if(O.wash(CLEAN_SCRUB))
				gained += rand(5, 15)
		if(istype(T, /turf/simulated))
			var/turf/simulated/S = T
			if(T.wash(CLEAN_SCRUB))
				gained += rand(10, 20)
			if(S.dirt > 50)
				S.dirt = 0
				gained += rand(10, 20)
	if(H.feet_blood_color || LAZYLEN(H.feet_blood_DNA))
		LAZYCLEARLIST(H.feet_blood_DNA)
		H.feet_blood_DNA = null
		H.feet_blood_color = null
		gained += rand(3, 10)
	if(H.bloody_hands)
		H.forensic_data?.clear_blooddna()
		H.hand_blood_color = null
		H.bloody_hands = 0
		gained += rand(3, 10)
	// Prometheans themselves aren't very safe places for other biota.
	H.germ_level = 0
	if(gained)
		H.adjust_nutrition(gained)
		H.update_bloodied()

/// Whatever a bare-handed promethean picks up gets cleaned too.
/datum/component/promethean_biology/proc/on_equipped(mob/living/carbon/human/source, obj/item/equipped_item, slot)
	SIGNAL_HANDLER
	if(slot != slot_l_hand && slot != slot_r_hand)
		return
	if(source.get_equipped_item(SLOT_ID_GLOVES) || (source.get_equipped_item(SLOT_ID_SUIT) && (source.get_equipped_item(SLOT_ID_SUIT).body_parts_covered & HANDS)))
		return
	if(equipped_item.wash(CLEAN_SCRUB))
		source.adjust_nutrition(rand(5, 15))

/datum/component/promethean_biology/proc/on_life(mob/living/carbon/human/source)
	SIGNAL_HANDLER
	if(source.stat == DEAD)
		return
	if(promethean_is_soaked(source))
		source.body?.afflict(/datum/affliction/dissolution)
	regenerate(source)

/// Regeneration: each mechanism heals by what mend() reports, and that is what
/// the body pays for in nutrition and strains the matching regenerative network.
/datum/component/promethean_biology/proc/regenerate(mob/living/carbon/human/H)
	if(!still || !H.body || H.body.has_affliction(/datum/affliction/dissolution))
		return
	var/datum/species/shapeshifter/promethean/S = H.species
	if(!istype(S))
		return
	if(H.bodytemperature > S.heat_level_1 || H.bodytemperature < S.cold_level_1)
		return
	if(!H.is_injured())
		return
	var/regen_wounds = TRUE
	var/turf/T = get_turf(H)
	if(T)
		var/datum/gas_mixture/environment = T.return_air()
		if(environment && H.calculate_affecting_pressure(environment.return_pressure()) <= S.hazard_low_pressure)
			regen_wounds = FALSE // Low pressure: the body holds wounds together rather than sealing them.

	var/starve_mod = 1
	if(H.nutrition <= 50)
		starve_mod = 0.5 // Severe starvation. Healing past this point hurts badly.
	else if(H.nutrition <= 150)
		starve_mod = 0.75
	var/amount = S.heal_rate * starve_mod

	var/nutrition_cost = 0
	var/strain_negation = 0
	// Mechanism -> the regenerative network that does the work.
	var/static/list/mechanisms = list(TREAT_TISSUE_REPAIR = O_REGBRUTE, TREAT_BURN_CARE = O_REGBURN, TREAT_OXYGENATION = O_REGOXY, TREAT_ANTITOXIN = O_REGTOX)
	for(var/tag in mechanisms)
		if(!regen_wounds && (tag == TREAT_TISSUE_REPAIR || tag == TREAT_BURN_CARE))
			continue
		var/healed = H.mend(tag, amount)
		if(healed <= 0)
			continue
		nutrition_cost += healed
		var/obj/item/organ/internal/regennetwork/network = H.internal_organs_by_name[mechanisms[tag]]
		if(network)
			// Strain rises with the work done (bug 19: it never used to).
			strain_negation += healed * max(0, 1 - network.get_strain_percent(healed))
	if(!nutrition_cost)
		return
	H.adjust_nutrition(-3 * nutrition_cost)
	// Regenerating without healthy networks hurts; small injuries are no issue.
	var/agony = (nutrition_cost - strain_negation) / starve_mod
	if(agony <= 0)
		return
	var/pain_cap = starve_mod <= 0.5 ? PROMETHEAN_STARVING_PAIN_CAP : PROMETHEAN_PAIN_CAP
	if(H.current_pain() + agony <= pain_cap)
		H.injure(INJURY_PAIN, agony)

/// Over half the body soaked through.
/proc/promethean_is_soaked(mob/living/carbon/human/H)
	return H.fire_stacks < 0 && H.get_water_protection() <= 0.5

/// Water dissolves a promethean's gel. Grows while soaked, fades once dry, and
/// stops regeneration while present.
/datum/affliction/dissolution
	name = "gel dissolution"
	category = "Environmental"
	clinical_description = "The patient's gelatinous body is dissolving in water. Dry them off; the gel recovers on its own once dry."
	injury_category = INJURY_CATEGORY_TOXIC
	biology = BIOLOGY_ORGANIC
	body_plans = BODY_PLAN_HUMANOID
	pain_at_max = 60
	consciousness_at_max = 120
	progression_rate = -2
	min_symptoms = 0
	max_symptoms = 0

/datum/affliction/dissolution/tick()
	var/mob/living/carbon/human/H = owner
	var/soaked = istype(H) && promethean_is_soaked(H)
	progression_rate = soaked ? (3 - 3 * H.get_water_protection()) : initial(progression_rate)
	..()
	if(QDELETED(src) || !soaked)
		return
	// Melting: the gel sloughs off the limbs.
	H.injure(INJURY_CORROSIVE, severity / 50, source = src, flags = INJURE_SILENT)

#undef PROMETHEAN_STILLNESS_TIME
#undef PROMETHEAN_PAIN_CAP
#undef PROMETHEAN_STARVING_PAIN_CAP

/// Trait system: promethean biology. Was a COMSIG_LIVING_LIFE listener.
/datum/life_system/trait/promethean_biology
	name = "promethean biology"
	component_type = /datum/component/promethean_biology

/datum/life_system/trait/promethean_biology/tick_component(mob/living/self, datum/component/promethean_biology/component)
	component.on_life(self)
