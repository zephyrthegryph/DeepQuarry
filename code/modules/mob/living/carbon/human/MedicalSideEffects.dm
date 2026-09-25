// MEDICAL SIDE EFFECT BASE
// ========================
/datum/medical_effect
	var/name = "None"
	var/strength = 0
	var/start = 0
	var/list/triggers
	var/list/cures
	var/cure_message

/datum/medical_effect/proc/manifest(mob/living/carbon/human/H)
	for(var/R in cures)
		if(H.reagents.has_reagent(R))
			return 0
	for(var/R in triggers)
		if(H.reagents.get_reagent_amount(R) >= triggers[R])
			return 1
	return 0

/datum/medical_effect/proc/on_life(mob/living/carbon/human/H, strength)
	return

/datum/medical_effect/proc/cure(mob/living/carbon/human/H)
	for(var/R in cures)
		if(H.reagents.has_reagent(R))
			if (cure_message)
				to_chat(H, span_blue("[cure_message]"))
			return 1
	return 0


// MOB HELPERS
// ===========
/proc/dq_medical_effect_registry()
	var/static/list/registry
	if(registry)
		return registry
	registry = list()
	// Explicit catalog: adding an effect requires registering it here, making
	// discovery deterministic and eliminating runtime subtype-tree reflection.
	var/static/list/effect_types = list(
		/datum/medical_effect/headache,
		/datum/medical_effect/bad_stomach,
		/datum/medical_effect/cramps,
		/datum/medical_effect/itch
	)
	for(var/effect_type in effect_types)
		var/datum/medical_effect/prototype = new effect_type
		registry[prototype.name] = prototype
	return registry

/mob/living/carbon/human/var/list/datum/medical_effect/side_effects
/mob/proc/add_side_effect(name, strength = 0)
/mob/living/carbon/human/add_side_effect(name, strength = 0)
	for(var/datum/medical_effect/M in side_effects)
		if(M.name == name)
			M.strength = max(M.strength, 10)
			M.start = life_tick
			return
	var/list/registry = dq_medical_effect_registry()
	var/datum/medical_effect/prototype = registry[name]
	if(!prototype)
		return
	var/datum/medical_effect/new_effect = new prototype.type
	new_effect.strength = strength
	new_effect.start = life_tick
	LAZYADD(side_effects, new_effect)

/// Reconcile once per Life cycle, and only when the reagent holder changed
/// (BODY_DIRTY_CHEMS, consumed by dq_process_dirty_medical_conditions). The old architecture
/// allocated every medical-effect subtype for every human every 30 seconds.
/mob/living/carbon/human/proc/reconcile_medical_side_effects()
	for(var/datum/medical_effect/active in side_effects)
		if(active.cure(src))
			LAZYREMOVE(side_effects, active)
			qdel(active)
	var/list/registry = dq_medical_effect_registry()
	for(var/effect_name in registry)
		var/datum/medical_effect/prototype = registry[effect_name]
		if(!prototype.manifest(src))
			continue
		var/already_active = FALSE
		for(var/datum/medical_effect/active in side_effects)
			if(active.type == prototype.type)
				already_active = TRUE
				break
		if(!already_active)
			add_side_effect(effect_name)

/// Medication side effects, every 15 life ticks.
/datum/om/stage/life/medical/proc/side_effects(mob/living/carbon/human/self)
	if(!LAZYLEN(self.side_effects) || self.life_tick % 15 != 0)
		return 0

	// One full cycle(in terms of strength) every 10 minutes
	for (var/datum/medical_effect/M in self.side_effects)
		if (!M) continue
		var/strength_percent = sin((self.life_tick - M.start) / 2)

		// Only do anything if the effect is currently strong enough
		if(strength_percent >= 0.4)
			if (M.cure(self) || M.strength > 50)
				LAZYREMOVE(self.side_effects, M)
				qdel(M)
			else
				if(self.life_tick % 45 == 0)
					M.on_life(self, strength_percent*M.strength)
				// Effect slowly growing stronger
				M.strength+=0.08

// HEADACHE
// ========
/datum/medical_effect/headache
	name = "Headache"
	triggers = list(REAGENT_ID_CRYOXADONE = 10, REAGENT_ID_BICARIDINE = 15, REAGENT_ID_TRICORDRAZINE = 15)
	cures = list(REAGENT_ID_ALKYSINE, REAGENT_ID_TRAMADOL, REAGENT_ID_PARACETAMOL, REAGENT_ID_OXYCODONE)
	cure_message = "Your head stops throbbing..."

/datum/medical_effect/headache/on_life(mob/living/carbon/human/H, strength)
	switch(strength)
		if(1 to 10)
			H.custom_pain("You feel a light pain in your head.",0)
		if(11 to 30)
			H.custom_pain("You feel a throbbing pain in your head!",1)
		if(31 to INFINITY)
			H.custom_pain("You feel an excrutiating pain in your head!",1)

// BAD STOMACH
// ===========
/datum/medical_effect/bad_stomach
	name = "Bad Stomach"
	triggers = list(REAGENT_ID_KELOTANE = 30, REAGENT_ID_DERMALINE = 15)
	cures = list(REAGENT_ID_ANTITOXIN)
	cure_message = "Your stomach feels a little better now..."

/datum/medical_effect/bad_stomach/on_life(mob/living/carbon/human/H, strength)
	switch(strength)
		if(1 to 10)
			H.custom_pain("You feel a bit light around the stomach.",0)
		if(11 to 30)
			H.custom_pain("Your stomach hurts.",0)
		if(31 to INFINITY)
			H.custom_pain("You feel sick.",1)

// CRAMPS
// ======
/datum/medical_effect/cramps
	name = "Cramps"
	triggers = list(REAGENT_ID_ANTITOXIN = 30, REAGENT_ID_TRAMADOL = 15)
	cures = list(REAGENT_ID_INAPROVALINE)
	cure_message = "The cramps let up..."

/datum/medical_effect/cramps/on_life(mob/living/carbon/human/H, strength)
	switch(strength)
		if(1 to 10)
			H.custom_pain("The muscles in your body hurt a little.",0)
		if(11 to 30)
			H.custom_pain("The muscles in your body cramp up painfully.",0)
		if(31 to INFINITY)
			H.automatic_custom_emote(VISIBLE_MESSAGE, "flinches as all the muscles in their body cramp up.", check_stat = TRUE)
			H.custom_pain("There's pain all over your body.",1)

// ITCH
// ====
/datum/medical_effect/itch
	name = "Itch"
	triggers = list(REAGENT_ID_BLISS = 10)
	cures = list(REAGENT_ID_INAPROVALINE)
	cure_message = "The itching stops..."

/datum/medical_effect/itch/on_life(mob/living/carbon/human/H, strength)
	switch(strength)
		if(1 to 10)
			H.custom_pain("You feel a slight itch.",0)
		if(11 to 30)
			H.custom_pain("You want to scratch your itch badly.",0)
		if(31 to INFINITY)
			H.automatic_custom_emote(VISIBLE_MESSAGE, "shivers slightly.", check_stat = TRUE)
			H.custom_pain("This itch makes it really hard to concentrate.",1)
