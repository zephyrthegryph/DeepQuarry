/datum/reagent/spacomycaze
	treatment_tags = list(TREAT_ANTIMICROBIAL = 0.8)
	factors = alist(STAT_ANALGESIA = 20, STAT_ANTIMICROBIAL = ANTIBIO_NORM)
	name = REAGENT_SPACOMYCAZE
	id = REAGENT_ID_SPACOMYCAZE
	description = "An all-purpose painkilling antibiotic gel."
	taste_description = "oil"
	reagent_state = SOLID
	dermal_absorption = 0
	color = "#C1C1C8"
	metabolism = REM * 0.4
	mrate_static = TRUE
	overdose = REAGENTS_OVERDOSE
	scannable = SCANNABLE_BENEFICIAL
	var/last_message_at = 0 // when the last status message was sent (-1: the effect ended)
	can_overdose_touch = TRUE
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/spacomycaze/affect_blood(mob/living/carbon/M, alien, removed)
	M.injure(INJURY_TOXIN, 3 * removed, source = src)

/datum/reagent/spacomycaze/affect_ingest(mob/living/carbon/M, alien, removed)
	affect_blood(M, alien, removed * 0.8)

/datum/reagent/spacomycaze/affect_touch(mob/living/carbon/M, alien, removed)
	if(alien == IS_SLIME)
		if(volume <= 0.1 && last_message_at != -1)
			last_message_at = -1
			to_chat(M, span_notice("The itching fades..."))
		else
			var/delay = (2 MINUTES)
			if(ELAPSED(src, last_message_at, CLOCK_WORLD) > delay)
				STAMP(src, last_message_at, CLOCK_WORLD)
				to_chat(M, span_warning("Your skin itches."))

/datum/reagent/spacomycaze/touch_obj(obj/O)
	..()
	if(istype(O, /obj/item/stack/medical) && round(volume) >= 1)
		var/obj/item/stack/medical/C = O
		var/packname = C.name
		var/to_produce = min(C.get_amount(), round(volume))

		var/obj/item/stack/medical/M = C.upgrade_stack(to_produce)

		if(M && M.get_amount())
			holder.my_atom.visible_message(span_infoplain(span_bold("\The [packname]") + " bubbles."))
			remove_self(to_produce)
