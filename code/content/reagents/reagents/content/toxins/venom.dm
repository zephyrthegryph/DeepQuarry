/datum/reagent/thermite/venom
	name = REAGENT_THERMITEV
	id = REAGENT_ID_THERMITEV
	description = "A biologically produced compound capable of melting steel or other metals, similarly to thermite."
	taste_description = "sweet chalk"
	dermal_absorption = 0 //It's a powder/solid.
	reagent_state = SOLID
	color = "#673910"
	touch_met = 50
	wiki_flag = WIKI_SPOILER
	supply_conversion_value = REFINERYEXPORT_VALUE_UNWANTED
	industrial_use = REFINERYEXPORT_REASON_BIOHAZARD

/datum/reagent/thermite/venom/affect_blood(mob/living/carbon/M, alien, removed)
	M.injure(INJURY_BURN, 3 * removed, source = src)
	if(fire_stacks_of(M) <= 1.5)
		M.adjust_fire_stacks(0.15)
	if(inert_for(M))
		return
	if(prob(10))
		to_chat(M, span_warning("Your veins feel like they're on fire!"))
		M.adjust_fire_stacks(0.1)
	else if(prob(5))
		M.ignite_mob()
		to_chat(M, span_critical("Some of your veins rupture, the exposed blood igniting!"))
