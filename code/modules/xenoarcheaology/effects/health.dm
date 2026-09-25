/// Modified to work with the Artifact Harvester
#define EFFECT_HEAL 1
#define EFFECT_HARM 2
/datum/artifact_effect/health
	name = "Health"
	effect_type = EFFECT_HEALTH
	effect_color = "#4649ff"
	var/health_type = EFFECT_HEAL

/datum/artifact_effect/health/New()
	..()
	health_type = pick(EFFECT_HEAL, EFFECT_HARM)
	if(health_type == EFFECT_HEAL)
		effect_color = "#4649ff"
	else
		effect_color = "#6d1212"

/// Generic regenerative field: mends every organic injury category by `amount`.
/datum/artifact_effect/health/proc/mend_all(mob/living/L, amount, include_neural)
	L.mend(TREAT_TISSUE_REPAIR, amount)
	L.mend(TREAT_BURN_CARE, amount)
	L.mend(TREAT_ANTITOXIN, amount)
	L.mend(TREAT_OXYGENATION, amount)
	if(include_neural)
		L.mend(TREAT_NEURAL_REPAIR, amount)

/datum/artifact_effect/health/DoEffectTouch(mob/toucher)
	var/atom/holder = get_master_holder()
	if(istype(holder, /obj/item/anobattery))
		var/obj/item/anobattery/battery = holder
		battery.stored_charge = max(0, battery.stored_charge-50) //This artifact uses charge at an accelrated rate. It makes you nigh invincvible while it's up OR kills you extremely quickly while it's up.
	if(toucher && iscarbon(toucher))
		var/weakness = GetAnomalySusceptibility(toucher)
		if(prob(weakness * 100))
			var/mob/living/carbon/C = toucher
			if(health_type == EFFECT_HEAL)
				to_chat(C, span_blue("You feel a soothing energy invigorate you."))
				if(ishuman(toucher))
					var/mob/living/carbon/human/H = toucher
					for(var/obj/item/organ/external/affecting in H.organs)
						H.mend(TREAT_TISSUE_REPAIR, 25 * weakness, affecting.organ_tag)
						H.mend(TREAT_BURN_CARE, 25 * weakness, affecting.organ_tag)
					H.vessel.add_reagent(REAGENT_ID_BLOOD,5)
					H.adjust_nutrition(50 * weakness)
					H.mend(TREAT_NEURAL_REPAIR, 25 * weakness)
					H.radiation -= min(H.radiation, 25 * weakness)
					H.bodytemperature = initial(H.bodytemperature)
					H.fixblood()
				mend_all(C, 25 * weakness, FALSE)
				C.regenerate_icons()
			else
				to_chat(C, span_danger("A painful discharge of energy strikes you!"))
				C.add_oxygen_debt(rand(5,25) * weakness, src)
				C.injure(INJURY_TOXIN, rand(5,25) * weakness)
				C.injure(INJURY_BLUNT, rand(5,25) * weakness)
				C.injure(INJURY_BURN, rand(5,25) * weakness)
				C.injure(INJURY_NEURAL, rand(1,5) * weakness)
				C.apply_effect(25 * weakness, IRRADIATE)
				C.adjust_nutrition(-50 * weakness)
				C.nutrition -= min(50 * weakness, C.nutrition)
				C.status_adjust(EFFECT_DIZZY, 6 * weakness)
				C.status_adjust(EFFECT_WEAKENED, 6 * weakness)
			return 1

/datum/artifact_effect/health/DoEffectAura()
	var/atom/holder = get_master_holder()
	//This is where I would make it drain charge at an accelerated rate, but...A passive 1 heal per 2 seconds is weak and fine.
	if(holder)
		var/turf/T = get_turf(holder)
		for (var/mob/living/carbon/C in range(src.effectrange,T))
			var/weakness = GetAnomalySusceptibility(C)
			if(prob(weakness * 100))
				if(health_type == EFFECT_HEAL)
					if(prob(10))
						to_chat(C, span_blue("You feel a soothing energy radiating from something nearby."))
					mend_all(C, 1 * weakness, TRUE)
				else
					if(prob(10))
						to_chat(C, span_danger("You feel a painful force radiating from something nearby."))
					C.injure(INJURY_BLUNT, 1 * weakness, null, null, 0, null, INJURE_SILENT)
					C.injure(INJURY_BURN, 1 * weakness, null, null, 0, null, INJURE_SILENT)
					C.injure(INJURY_TOXIN, 1 * weakness, null, null, 0, null, INJURE_SILENT)
					C.add_oxygen_debt(1 * weakness)
					C.injure(INJURY_NEURAL, 0.1 * weakness, null, null, 0, null, INJURE_SILENT)

/datum/artifact_effect/health/DoEffectPulse()
	var/atom/holder = get_master_holder() //I'm not touching the below line because it's FUNNY that a 'todo:' has been sitting there for 12 years.
	//todo: check over this properly
	//Anyways, this is where you'd put accelerated drain code, but it already drains at 200 a tick, meaning you get 2-3 uses at most before having to recharge.
	if(holder)
		var/turf/T = get_turf(holder)
		for (var/mob/living/carbon/C in range(src.effectrange,T))
			var/weakness = GetAnomalySusceptibility(C)
			if(prob(weakness * 100))
				if(health_type == EFFECT_HEAL)
					to_chat(C, span_blue("A wave of energy invigorates you."))
					mend_all(C, 25 * weakness, TRUE)
				else
					to_chat(C, span_danger("A wave of painful energy strikes you!"))
					C.injure(INJURY_BLUNT, 3 * weakness, null, null, 0, null, INJURE_SILENT)
					C.injure(INJURY_BURN, 3 * weakness, null, null, 0, null, INJURE_SILENT)
					C.injure(INJURY_TOXIN, 3 * weakness, null, null, 0, null, INJURE_SILENT)
					C.add_oxygen_debt(3 * weakness)
					C.injure(INJURY_NEURAL, 0.1 * weakness, null, null, 0, null, INJURE_SILENT)

#undef EFFECT_HEAL
#undef EFFECT_HARM
