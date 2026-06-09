/* Paint and crayons */

/datum/reagent/crayon_dust
	name = REAGENT_CRAYONDUST
	id = REAGENT_ID_CRAYONDUST
	description = "Intensely coloured powder obtained by grinding crayons."
	taste_description = "powdered wax"
	reagent_state = SOLID
	dermal_absorption = 0 //no
	color = "#888888"
	overdose = 10
	scannable = SCANNABLE_ADVANCED
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_COSMETIC

/datum/reagent/crayon_dust/red
	name = REAGENT_CRAYONDUSTRED
	id = REAGENT_ID_CRAYONDUSTRED
	color = "#FE191A"

/datum/reagent/crayon_dust/orange
	name = REAGENT_CRAYONDUSTORANGE
	id = REAGENT_ID_CRAYONDUSTORANGE
	color = "#FFBE4F"

/datum/reagent/crayon_dust/yellow
	name = REAGENT_CRAYONDUSTYELLOW
	id = REAGENT_ID_CRAYONDUSTYELLOW
	color = "#FDFE7D"

/datum/reagent/crayon_dust/green
	name = REAGENT_CRAYONDUSTGREEN
	id = REAGENT_ID_CRAYONDUSTGREEN
	color = "#18A31A"

/datum/reagent/crayon_dust/blue
	name = REAGENT_CRAYONDUSTBLUE
	id = REAGENT_ID_CRAYONDUSTBLUE
	color = "#247CFF"

/datum/reagent/crayon_dust/purple
	name = REAGENT_CRAYONDUSTPURPLE
	id = REAGENT_ID_CRAYONDUSTPURPLE
	color = "#CC0099"

/datum/reagent/crayon_dust/grey //Mime
	name = REAGENT_CRAYONDUSTGREY
	id = REAGENT_ID_CRAYONDUSTGREY
	color = "#808080"

/datum/reagent/crayon_dust/brown //Rainbow
	name = REAGENT_CRAYONDUSTBROWN
	id = REAGENT_ID_CRAYONDUSTBROWN
	color = "#846F35"

/datum/reagent/marker_ink
	name = REAGENT_MARKERINK
	id = REAGENT_ID_MARKERINK
	description = "Intensely coloured ink used in markers."
	taste_description = "extremely bitter"
	reagent_state = LIQUID
	dermal_absorption = 0 //NO
	color = "#888888"
	overdose = 10
	scannable = SCANNABLE_ADVANCED
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_COSMETIC

/datum/reagent/marker_ink/black
	name = REAGENT_MARKERINKBLACK
	id = REAGENT_ID_MARKERINKBLACK
	color = "#000000"

/datum/reagent/marker_ink/red
	name = REAGENT_MARKERINKRED
	id = REAGENT_ID_MARKERINKRED
	color = "#FE191A"

/datum/reagent/marker_ink/orange
	name = REAGENT_MARKERINKORANGE
	id = REAGENT_ID_MARKERINKORANGE
	color = "#FFBE4F"

/datum/reagent/marker_ink/yellow
	name = REAGENT_MARKERINKYELLOW
	id = REAGENT_ID_MARKERINKYELLOW
	color = "#FDFE7D"

/datum/reagent/marker_ink/green
	name = REAGENT_MARKERINKGREEN
	id = REAGENT_ID_MARKERINKGREEN
	color = "#18A31A"

/datum/reagent/marker_ink/blue
	name = REAGENT_MARKERINKBLUE
	id = REAGENT_ID_MARKERINKBLUE
	color = "#247CFF"

/datum/reagent/marker_ink/purple
	name = REAGENT_MARKERINKPURPLE
	id = REAGENT_ID_MARKERINKPURPLE
	color = "#CC0099"

/datum/reagent/marker_ink/grey //Mime
	name = REAGENT_MARKERINKGREY
	id = REAGENT_ID_MARKERINKGREY
	color = "#808080"

/datum/reagent/marker_ink/brown //Rainbow
	name = REAGENT_MARKERINKBROWN
	id = REAGENT_ID_MARKERINKBROWN
	color = "#846F35"

/datum/reagent/paint
	name = REAGENT_PAINT
	id = REAGENT_ID_PAINT
	description = "This paint will stick to almost any object."
	taste_description = "chalk"
	reagent_state = LIQUID
	dermal_absorption = 0 //NOOOOOOOOOOO
	color = "#808080"
	overdose = REAGENTS_OVERDOSE * 0.5
	color_weight = 20
	scannable = SCANNABLE_ADVANCED
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_COSMETIC

/datum/reagent/paint/touch_turf(turf/T)
	..()
	if(istype(T) && !istype(T, /turf/space))
		T.color = color

/datum/reagent/paint/touch_obj(obj/O)
	..()
	if(istype(O))
		O.color = color

/datum/reagent/paint/touch_mob(mob/M)
	..()
	if(istype(M) && !istype(M, /mob/observer)) //painting ghosts: not allowed
		M.color = color //maybe someday change this to paint only clothes and exposed body parts for human mobs.

/datum/reagent/paint/get_data()
	return color

/datum/reagent/paint/initialize_data(newdata)
	color = newdata
	return

/datum/reagent/paint/mix_data(newdata, newamount)
	var/list/colors = list(0, 0, 0, 0)
	var/tot_w = 0

	var/hex1 = uppertext(color)
	var/hex2 = uppertext(newdata)
	if(length(hex1) == 7)
		hex1 += "FF"
	if(length(hex2) == 7)
		hex2 += "FF"
	if(length(hex1) != 9 || length(hex2) != 9)
		return
	colors[1] += hex2num(copytext(hex1, 2, 4)) * volume
	colors[2] += hex2num(copytext(hex1, 4, 6)) * volume
	colors[3] += hex2num(copytext(hex1, 6, 8)) * volume
	colors[4] += hex2num(copytext(hex1, 8, 10)) * volume
	tot_w += volume
	colors[1] += hex2num(copytext(hex2, 2, 4)) * newamount
	colors[2] += hex2num(copytext(hex2, 4, 6)) * newamount
	colors[3] += hex2num(copytext(hex2, 6, 8)) * newamount
	colors[4] += hex2num(copytext(hex2, 8, 10)) * newamount
	tot_w += newamount

	color = rgb(colors[1] / tot_w, colors[2] / tot_w, colors[3] / tot_w, colors[4] / tot_w)
	return

/* Things that didn't fit anywhere else */

/datum/reagent/adminordrazine //An OP chemical for admins
	name = REAGENT_ADMINORDRAZINE
	id = REAGENT_ID_ADMINORDRAZINE
	description = "It's magic. We don't have to explain it."
	taste_description = "bwoink"
	reagent_state = LIQUID
	color = "#C8A5DC"
	affects_dead = TRUE //This can even heal dead people.
	metabolism = 0.1
	scannable = SCANNABLE_UNSCANNABLE
	mrate_static = TRUE //Just in case

	glass_name = "liquid gold"
	glass_desc = "It's magic. We don't have to explain it."
	wiki_flag = WIKI_SPOILER

	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = "how did you get this?"

/datum/reagent/adminordrazine/affect_touch(mob/living/carbon/M, alien, removed)
	affect_blood(M, alien, removed)

/datum/reagent/adminordrazine/affect_blood(mob/living/carbon/M, alien, removed)
	M.heal_organ_damage(40,40)
	M.adjustCloneLoss(-40)
	M.adjustToxLoss(-40)
	M.adjustOxyLoss(-300)
	M.hallucination = 0
	M.setBrainLoss(0)
	M.disabilities = 0
	M.sdisabilities = 0
	M.eye_blurry = 0
	M.SetBlinded(0)
	M.SetWeakened(0)
	M.SetStunned(0)
	M.SetParalysis(0)
	M.silent = 0
	M.clear_dizzy()
	M.clear_jittery()
	M.drowsyness = 0
	M.stuttering = 0
	M.SetConfused(0)
	M.SetSleeping(0)
	M.radiation = 0
	M.extinguish_mob()
	M.fire_stacks = 0
	M.add_chemical_effect(CE_ANTIBIOTIC, ANTIBIO_SUPER)
	M.add_chemical_effect(CE_STABLE, 15)
	M.add_chemical_effect(CE_PAINKILLER, 200)
	M.remove_a_modifier_of_type(/datum/modifier/poisoned)
	if(M.bodytemperature > 310)
		M.bodytemperature = max(310, M.bodytemperature - (40 * TEMPERATURE_DAMAGE_COEFFICIENT))
	else if(M.bodytemperature < 311)
		M.bodytemperature = min(310, M.bodytemperature + (40 * TEMPERATURE_DAMAGE_COEFFICIENT))
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/wound_heal = 5
		for(var/obj/item/organ/I in H.internal_organs)
			if(I.damage > 0) //Adminordrazine heals even robits, it is magic
				I.damage = max(I.damage - wound_heal, 0)
		for(var/obj/item/organ/external/O in H.bad_external_organs)
			if(O.status & ORGAN_BROKEN)
				O.mend_fracture()		//Only works if the bone won't rebreak, as usual
			for(var/datum/wound/W in O.wounds)
				if(W.bleeding())
					W.damage = max(W.damage - wound_heal, 0)
					if(W.damage <= 0)
						O.wounds -= W
				if(W.internal)
					W.damage = max(W.damage - wound_heal, 0)
					if(W.damage <= 0)
						O.wounds -= W

/datum/reagent/gold
	name = REAGENT_GOLD
	id = REAGENT_ID_GOLD
	description = "Gold is a dense, soft, shiny metal and the most malleable and ductile metal known."
	taste_description = "metal"
	reagent_state = SOLID
	scannable = SCANNABLE_ADVANCED
	color = "#F7C430"
	supply_conversion_value = 2 SHEET_TO_REAGENT_EQUIVILENT // has sheet value
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/silver
	name = REAGENT_SILVER
	id = REAGENT_ID_SILVER
	description = "A soft, white, lustrous transition metal, it has the highest electrical conductivity of any element and the highest thermal conductivity of any metal."
	taste_description = "metal"
	reagent_state = SOLID
	scannable = SCANNABLE_ADVANCED
	color = "#D0D0D0"
	supply_conversion_value = 1 SHEET_TO_REAGENT_EQUIVILENT // has sheet value
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/platinum
	name = REAGENT_PLATINUM
	id = REAGENT_ID_PLATINUM
	description = "Platinum is a dense, malleable, ductile, highly unreactive, precious, gray-white transition metal.  It is very resistant to corrosion."
	taste_description = "metal"
	reagent_state = SOLID
	scannable = SCANNABLE_ADVANCED
	color = "#777777"
	supply_conversion_value = 5 SHEET_TO_REAGENT_EQUIVILENT // has sheet value
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/uranium
	name = REAGENT_URANIUM
	id = REAGENT_ID_URANIUM
	description = "A silvery-white metallic chemical element in the actinide series, weakly radioactive."
	taste_description = "metal"
	reagent_state = SOLID
	scannable = SCANNABLE_ADVANCED
	color = "#B8B8C0"
	supply_conversion_value = 2 SHEET_TO_REAGENT_EQUIVILENT // has sheet value
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/uranium/affect_touch(mob/living/carbon/M, alien, removed)
	affect_ingest(M, alien, removed)

/datum/reagent/uranium/affect_blood(mob/living/carbon/M, alien, removed)
	M.apply_effect(5 * removed, IRRADIATE, 0)

/datum/reagent/uranium/touch_turf(turf/T)
	..()
	if(volume >= 3)
		if(!istype(T, /turf/space))
			var/obj/effect/decal/cleanable/greenglow/glow = locate(/obj/effect/decal/cleanable/greenglow, T)
			if(!glow)
				new /obj/effect/decal/cleanable/greenglow(T)
			return

/datum/reagent/hydrogen/deuterium
	name = REAGENT_DEUTERIUM
	id = REAGENT_ID_DEUTERIUM
	description = "A isotope of hydrogen. It has one extra neutron, and shares all chemical characteristics with hydrogen."
	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR
	coolant_modifier = 1 // It's ALMOST water

/datum/reagent/hydrogen/tritium
	name = REAGENT_TRITIUM
	id = REAGENT_ID_TRITIUM
	description = "A radioactive isotope of hydrogen. It has two extra neutrons, and shares all other chemical characteristics with hydrogen."
	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR
	coolant_modifier = 1 // It's ALMOST water

/datum/reagent/lithium/lithium6
	name = REAGENT_LITHIUM6
	id = REAGENT_ID_LITHIUM6
	description = "An isotope of lithium. It has 3 neutrons, but shares all chemical characteristics with regular lithium."
	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/helium/helium3
	name = REAGENT_HELIUM3
	id = REAGENT_ID_HELIUM3
	description = "An isotope of helium. It only has one neutron, but shares all chemical characteristics with regular helium."
	taste_mult = 0
	reagent_state = GAS
	color = "#808080"
	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR
	coolant_modifier = 2

/datum/reagent/boron/boron11
	name = REAGENT_BORON11
	id = REAGENT_ID_BORON11
	description = "An isotope of boron. It has 6 neutrons."
	taste_description = "metallic" // Apparently noone on the internet knows what boron tastes like. Or at least they won't share
	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/supermatter
	name = REAGENT_SUPERMATTER
	id = REAGENT_ID_SUPERMATTER
	color = "#fffd6b"
	reagent_state = SOLID
	affects_dead = TRUE
	affects_robots = TRUE
	scannable = SCANNABLE_UNSCANNABLE
	description = "The immense power of a supermatter crystal, in liquid form. You're not entirely sure how that's possible, but it's probably best handled with care."
	taste_description = "taffy" // 0. The supermatter is tasty, tasty taffy.
	wiki_flag = WIKI_SPOILER
	supply_conversion_value = REFINERYEXPORT_VALUE_MASSINDUSTRY
	industrial_use = REFINERYEXPORT_REASON_MATSCI

// Same as if you boop it wrong. It touches you, you die
/datum/reagent/supermatter/affect_touch(mob/living/carbon/M, alien, removed)
	M.ash()

/datum/reagent/supermatter/affect_ingest(mob/living/carbon/M, alien, removed)
	M.ash()

/datum/reagent/supermatter/affect_blood(mob/living/carbon/M, alien, removed)
	M.ash()


/datum/reagent/adrenaline
	name = REAGENT_ADRENALINE
	id = REAGENT_ID_ADRENALINE
	description = "Adrenaline is a hormone used as a drug to treat cardiac arrest and other cardiac dysrhythmias resulting in diminished or absent cardiac output."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	scannable = SCANNABLE_BENEFICIAL
	color = "#C8A5DC"
	mrate_static = TRUE
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/adrenaline/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien == IS_DIONA)
		return
	M.SetParalysis(0)
	M.SetWeakened(0)
	M.adjustToxLoss(rand(3))

/datum/reagent/water/holywater
	name = REAGENT_HOLYWATER
	id = REAGENT_ID_HOLYWATER
	description = "An ashen-obsidian-water mix, this solution will alter certain sections of the brain's rationality."
	taste_description = "water"
	color = "#E0E8EF"
	mrate_static = TRUE
	dermal_absorption = 0.5 //It's so holy it penetrates into your blood.
	scannable = SCANNABLE_BENEFICIAL

	glass_name = "holy water"
	glass_desc = "An ashen-obsidian-water mix, this solution will alter certain sections of the brain's rationality."
	wiki_flag = WIKI_SPOILER

	supply_conversion_value = REFINERYEXPORT_VALUE_NO
	industrial_use = REFINERYEXPORT_REASON_RAW
	coolant_modifier = 1 // It's water
	var/failed_message = FALSE

/datum/reagent/water/holywater/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	if(ishuman(M)) // Any location
		if(M.mind && GLOB.cult.is_antagonist(M.mind) && prob(10))
			GLOB.cult.remove_antagonist(M.mind)
		if(prob(2)) //Get an ACTUAL chaplain for your stuff
			if(M.has_modifier_of_type(/datum/modifier/redspace_corruption))
				M.remove_modifiers_of_type(/datum/modifier/redspace_corruption)
				to_chat(M, span_notice("You feel calmer."))

			if(M.HasDisease(/datum/disease/fleshy_spread))
				for(var/datum/disease/fleshy_spread/disease in M.GetViruses())
					disease.cure()
					break
				to_chat(M, span_notice("Your fever subsides.."))
		if(volume <= max_dose * 0.5 && !failed_message)
			if(M.has_modifier_of_type(/datum/modifier/redspace_corruption) || M.HasDisease(/datum/disease/fleshy_spread))
				to_chat(M, span_notice("The power of the holy water courses through you, but seems to have failed to cure your ailments. Perhaps a larger dose is needed?"))
				failed_message = TRUE

/datum/reagent/water/holywater/affect_blood(mob/living/carbon/M, alien, removed)
	..()
	if(ishuman(M)) // Any location
		if(M.mind && GLOB.cult.is_antagonist(M.mind) && prob(5))
			GLOB.cult.remove_antagonist(M.mind)
		if(prob(1)) //injecting holy water makes it weaker because that's sinful
			if(M.has_modifier_of_type(/datum/modifier/redspace_corruption))
				M.remove_modifiers_of_type(/datum/modifier/redspace_corruption)
				to_chat(M, span_notice("You feel calmer."))

			if(M.HasDisease(/datum/disease/fleshy_spread))
				for(var/datum/disease/fleshy_spread/disease in M.GetViruses())
					disease.cure()
					break
				to_chat(M, span_notice("Your fever subsides.."))
		if(volume <= max_dose * 0.25 && !failed_message)
			if(M.has_modifier_of_type(/datum/modifier/redspace_corruption) || M.HasDisease(/datum/disease/fleshy_spread))
				to_chat(M, span_notice("The power of the holy water courses through you, but seems to have failed to cure your ailments. Perhaps a larger dose is needed?"))
				failed_message = TRUE
	return

/datum/reagent/water/holywater/touch_turf(turf/T)
	..()
	if(volume >= 5)
		T.holy = 1
	return

/datum/reagent/ammonia
	name = REAGENT_AMMONIA
	id = REAGENT_ID_AMMONIA
	description = "A caustic substance commonly used in fertilizer or household cleaners."
	taste_description = "mordant"
	taste_mult = 2
	reagent_state = GAS
	scannable = SCANNABLE_ADVANCED
	color = "#404030"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_RAW
	coolant_modifier = 1.25

/datum/reagent/diethylamine
	name = REAGENT_DIETHYLAMINE
	id = REAGENT_ID_DIETHYLAMINE
	description = "A secondary amine, mildly corrosive."
	taste_description = REAGENT_ID_IRON
	reagent_state = LIQUID
	scannable = SCANNABLE_ADVANCED
	color = "#604030"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/lye
	name = REAGENT_LYE
	id = REAGENT_ID_LYE
	description = "Also known as sodium hydroxide. As a profession making this is somewhat underwhelming."
	taste_description = "acid"
	reagent_state = LIQUID
	scannable = SCANNABLE_ADVANCED
	color = "#FFFFD6" // very very light yellow"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/fluorosurfactant // Foam precursor
	name = REAGENT_FLUOROSURFACTANT
	id = REAGENT_ID_FLUOROSURFACTANT
	description = "A perfluoronated sulfonic acid that forms a foam when mixed with water."
	taste_description = "metal"
	reagent_state = LIQUID
	scannable = SCANNABLE_ADVANCED
	color = "#9E6B38"
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/foaming_agent // Metal foaming agent. This is lithium hydride. Add other recipes (e.g. LiH + H2O -> LiOH + H2) eventually.
	name = REAGENT_FOAMINGAGENT
	id = REAGENT_ID_FOAMINGAGENT
	description = "A agent that yields metallic foam when mixed with light metal and a strong acid."
	taste_description = "metal"
	reagent_state = SOLID
	scannable = SCANNABLE_ADVANCED
	color = "#664B63"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/thermite
	name = REAGENT_THERMITE
	id = REAGENT_ID_THERMITE
	description = "Thermite produces an aluminothermic reaction known as a thermite reaction. Can be used to melt walls."
	taste_description = "sweet tasting metal"
	reagent_state = SOLID
	dermal_absorption = 0
	scannable = SCANNABLE_ADVANCED
	color = "#673910"
	touch_met = 50
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/thermite/touch_turf(turf/T)
	..()
	if(volume >= 5)
		if(istype(T, /turf/simulated/wall))
			var/turf/simulated/wall/W = T
			W.thermite = 1
			W.add_overlay(image('icons/effects/effects.dmi',icon_state = "#673910")) // What??
			remove_self(5)
	return

/datum/reagent/thermite/touch_mob(mob/living/L, amount)
	..()
	if(istype(L))
		L.adjust_fire_stacks(amount / 5)

/datum/reagent/thermite/affect_blood(mob/living/carbon/M, alien, removed)
	M.adjustFireLoss(3 * removed)

/datum/reagent/space_cleaner
	name = REAGENT_CLEANER
	id = REAGENT_ID_CLEANER
	description = "A compound used to clean things. Now with 50% more sodium hypochlorite!"
	taste_description = "sourness"
	reagent_state = LIQUID
	dermal_absorption = 0
	scannable = SCANNABLE_ADVANCED
	color = "#A5F0EE"
	touch_met = 50
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_CLEAN

/datum/reagent/space_cleaner/touch_obj(obj/O)
	..()
	O.wash(CLEAN_SCRUB)

/datum/reagent/space_cleaner/touch_turf(turf/T)
	..()
	if(volume >= 1)
		if(istype(T, /turf/simulated))
			var/turf/simulated/S = T
			S.dirt = 0
		T.wash(CLEAN_SCRUB)
		for(var/obj/effect/O in T)
			if(istype(O,/obj/effect/rune) || istype(O,/obj/effect/decal/cleanable) || istype(O,/obj/effect/overlay))
				qdel(O)

		for(var/mob/living/simple_mob/slime/M in T)
			M.adjustToxLoss(rand(5, 10))

		for(var/mob/living/simple_mob/vore/aggressive/macrophage/virus in T)
			virus.adjustToxLoss(rand(5, 10))

	T.apply_fire_protection() // Apply fire protection

/datum/reagent/space_cleaner/affect_touch(mob/living/carbon/M, alien, removed)
	if(M.r_hand)
		M.r_hand.wash(CLEAN_SCRUB)
	if(M.l_hand)
		M.l_hand.wash(CLEAN_SCRUB)
	if(M.wear_mask)
		if(M.wear_mask.wash(CLEAN_SCRUB))
			M.update_inv_wear_mask(0)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(alien == IS_SLIME)
			M.adjustToxLoss(rand(5, 10))
		if(H.head)
			if(H.head.wash(CLEAN_SCRUB))
				H.update_inv_head(0)
		if(H.wear_suit)
			if(H.wear_suit.wash(CLEAN_SCRUB))
				H.update_inv_wear_suit(0)
		else if(H.w_uniform)
			if(H.w_uniform.wash(CLEAN_SCRUB))
				H.update_inv_w_uniform(0)
		if(H.shoes)
			if(H.shoes.wash(CLEAN_SCRUB))
				H.update_inv_shoes(0)
		else
			H.wash(CLEAN_SCRUB)
			return
	M.wash(CLEAN_SCRUB)

/datum/reagent/space_cleaner/affect_ingest(mob/living/carbon/M, alien, removed)
	if(alien == IS_SLIME)
		M.adjustToxLoss(6 * removed)
	else
		M.adjustToxLoss(3 * removed)
		if(prob(5))
			M.vomit()

/datum/reagent/space_cleaner/touch_mob(mob/M, amount)
	..()
	if(iscarbon(M))
		var/mob/living/carbon/C = M
		C.wash(CLEAN_SCRUB)

	if(istype(M, /mob/living/simple_mob/vore/aggressive/macrophage)) // Big ouch for viruses
		var/mob/living/simple_mob/macrophage = M
		macrophage.adjustToxLoss(20)

	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(H.wear_mask)
			if(istype(H.wear_mask, /obj/item/clothing/mask/smokable))
				var/obj/item/clothing/mask/smokable/S = H.wear_mask
				if(S.lit)
					S.quench() // No smoking in my medbay!
					H.visible_message(span_notice("[H]\'s [S.name] is put out."))

/datum/reagent/lube // TODO: spraying on borgs speeds them up
	name = REAGENT_LUBE
	id = REAGENT_ID_LUBE
	description = "Lubricant is a substance introduced between two moving surfaces to reduce the friction and wear between them. giggity."
	taste_description = "slime"
	reagent_state = LIQUID
	scannable = SCANNABLE_ADVANCED
	color = "#009CA8"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_LUBE

/datum/reagent/lube/touch_turf(turf/simulated/T)
	..()
	if(!istype(T))
		return
	if(volume >= 1)
		T.wet_floor(2)

/datum/reagent/silicate
	name = REAGENT_SILICATE
	id = REAGENT_ID_SILICATE
	description = "A compound that can be used to reinforce glass."
	taste_description = "plastic"
	reagent_state = LIQUID
	scannable = SCANNABLE_ADVANCED
	color = "#C7FFFF"
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/silicate/touch_obj(obj/O)
	..()
	if(istype(O, /obj/structure/window))
		var/obj/structure/window/W = O
		W.apply_silicate(volume)
		remove_self(volume)
	return

/datum/reagent/glycerol
	name = REAGENT_GLYCEROL
	id = REAGENT_ID_GLYCEROL
	description = "Glycerol is a simple polyol compound. Glycerol is sweet-tasting and of low toxicity."
	taste_description = "sweetness"
	reagent_state = LIQUID
	scannable = SCANNABLE_ADVANCED
	color = "#808080"
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR
	coolant_modifier = 0.95

/datum/reagent/nitroglycerin //This immediately explode as soon as it reacts, so you can't actually obtain this.
	name = REAGENT_NITROGLYCERIN
	id = REAGENT_ID_NITROGLYCERIN
	description = "Nitroglycerin is a heavy, colorless, oily, explosive liquid obtained by nitrating glycerol."
	taste_description = "oil"
	reagent_state = LIQUID
	scannable = SCANNABLE_UNSCANNABLE
	color = "#808080"
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/coolant
	name = REAGENT_COOLANT
	id = REAGENT_ID_COOLANT
	description = "Industrial cooling substance."
	taste_description = "sourness"
	taste_mult = 1.1
	reagent_state = LIQUID
	scannable = SCANNABLE_ADVANCED
	color = "#C8A5DC"

	affects_robots = TRUE
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_INDUSTRY
	coolant_modifier = 2 // In the name

/datum/reagent/coolant/affect_blood(mob/living/carbon/M, alien, removed)
	if(M.isSynthetic() && ishuman(M))
		var/mob/living/carbon/human/H = M

		var/datum/reagent/blood/coolant = H.get_blood(H.vessel)

		if(coolant)
			H.vessel.add_reagent(REAGENT_ID_BLOOD, removed, coolant.data)

		else
			H.vessel.add_reagent(REAGENT_ID_BLOOD, removed)
			H.fixblood()

	else
		..()

/datum/reagent/ultraglue
	name = REAGENT_GLUE
	id = REAGENT_ID_GLUE
	scannable = SCANNABLE_ADVANCED
	description = "An extremely powerful bonding agent."
	taste_description = "a special education class"
	color = "#FFFFCC"
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/woodpulp
	name = REAGENT_WOODPULP
	id = REAGENT_ID_WOODPULP
	scannable = SCANNABLE_ADVANCED
	description = "A mass of wood fibers."
	taste_description = "wood"
	reagent_state = LIQUID
	color = "#B97A57"
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/luminol
	name = REAGENT_LUMINOL
	id = REAGENT_ID_LUMINOL
	scannable = SCANNABLE_ADVANCED
	description = "A compound that interacts with blood on the molecular level."
	taste_description = "metal"
	reagent_state = LIQUID
	color = "#F2F3F4"
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/luminol/touch_obj(obj/O)
	..()
	O.reveal_blood()

/datum/reagent/luminol/touch_mob(mob/living/L)
	..()
	L.reveal_blood()

/datum/reagent/nutriment/biomass
	name = REAGENT_BIOMASS
	id = REAGENT_ID_BIOMASS
	description = "A slurry of compounds that contains the basic requirements for life."
	taste_description = "salty meat"
	reagent_state = LIQUID
	color = "#DF9FBF"
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_CLONEDRUG
	coolant_modifier = -2 //Ew

/datum/reagent/mineralfluid
	name = REAGENT_MINERALIZEDFLUID
	id = REAGENT_ID_MINERALIZEDFLUID
	scannable = SCANNABLE_ADVANCED
	description = "A warm, mineral-rich fluid."
	taste_description = "salt"
	reagent_state = LIQUID
	color = "#ff205255"
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_MATSCI
	coolant_modifier = -2.5

// The opposite to healing nanites, exists to make unidentified hypos implied to have nanites not be 100% safe.
/datum/reagent/defective_nanites
	name = REAGENT_DEFECTIVENANITES
	id = REAGENT_ID_DEFECTIVENANITES
	scannable = SCANNABLE_DIFFICULT
	description = "Miniature medical robots that are malfunctioning and cause bodily harm. Fortunately, they cannot self-replicate."
	taste_description = "metal"
	reagent_state = SOLID
	dermal_absorption = 0.1 //Burrow into the skin and get into your bloodstream. This means 60u splashed on someone (with no losses, given splash is lossy) will give them 6u of nanites.
	color = "#333333"
	metabolism = REM * 3 // Broken nanomachines go a bit slower.
	scannable = 1
	wiki_flag = WIKI_SPOILER
	supply_conversion_value = REFINERYEXPORT_VALUE_NO
	industrial_use = REFINERYEXPORT_REASON_BIOHAZARD

/datum/reagent/defective_nanites/affect_blood(mob/living/carbon/M, alien, removed)
	M.take_organ_damage(2 * removed, 2 * removed)
	M.adjustOxyLoss(4 * removed)
	M.adjustToxLoss(2 * removed)
	M.adjustCloneLoss(2 * removed)

/datum/reagent/nutriment/fishbait
	name = REAGENT_FISHBAIT
	id = REAGENT_ID_FISHBAIT
	description = "A natural slurry that particularily appeals to fish."
	taste_description = "slimy dirt"
	reagent_state = LIQUID
	color = "#62764E"
	nutriment_factor = 15
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_FOOD

/datum/reagent/nutriment/paper //Paper is made from cellulose. You can eat it. It doesn't fill you up very much at all.
	name = "Paper"
	id = "paper"
	description = "Soggy, ground up paper"
	taste_description = "paper"
	reagent_state = SOLID
	color = "e6e6e6" //not quite white
	nutriment_factor = 2 // 5 times worse than nutriment

/datum/reagent/carpet
	name = REAGENT_LIQUIDCARPET
	id = REAGENT_ID_LIQUIDCARPET
	scannable = SCANNABLE_ADVANCED
	description = "Liquified carpet fibers, ready for dyeing."
	reagent_state = LIQUID
	color = "#b51d05"
	taste_description = "carpet"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/carpet/black
	name = REAGENT_LIQUIDCARPETB
	id = REAGENT_ID_LIQUIDCARPETB
	description = "Black Carpet Fibers, ready for reinforcement."
	reagent_state = LIQUID
	color = "#000000"
	taste_description = "rare and ashy carpet"

/datum/reagent/carpet/blue
	name = REAGENT_LIQUIDCARPETBLU
	id = REAGENT_ID_LIQUIDCARPETBLU
	description = "Blue Carpet Fibers, ready for reinforcement."
	reagent_state = LIQUID
	color = "#3f4aee"
	taste_description = "commanding carpet"

/datum/reagent/carpet/turquoise
	name = REAGENT_LIQUIDCARPETTUR
	id = REAGENT_ID_LIQUIDCARPETTUR
	description = "Turquoise Carpet Fibers, ready for reinforcement."
	reagent_state = LIQUID
	color = "#0592b5"
	taste_description = "water-logged carpet"

/datum/reagent/carpet/sblue
	name = REAGENT_LIQUIDCARPETSBLU
	id = REAGENT_ID_LIQUIDCARPETSBLU
	description = "Silver Blue Carpet Fibers, ready for reinforcement."
	reagent_state = LIQUID
	color = "#0011ff"
	taste_description = "sterile and medicinal carpet"

/datum/reagent/carpet/clown
	name = REAGENT_LIQUIDCARPETC
	id = REAGENT_ID_LIQUIDCARPETC
	description = "Clown Carpet Fibers.... No clowns were harmed in the making of this."
	reagent_state = LIQUID
	color = "#e925be"
	taste_description = "clown shoes and banana peels"

/datum/reagent/carpet/purple
	name = REAGENT_LIQUIDCARPETP
	id = REAGENT_ID_LIQUIDCARPETP
	description = "Purple Carpet Fibers, ready for reinforcement."
	reagent_state = LIQUID
	color = "#a614d3"
	taste_description = "bleeding edge carpet research"

/datum/reagent/carpet/orange
	name = REAGENT_LIQUIDCARPETO
	id = REAGENT_ID_LIQUIDCARPETO
	description = "Orange Carpet Fibers, ready for reinforcement."
	reagent_state = LIQUID
	color = "#f16e16"
	taste_description = "extremely overengineered carpet"

/datum/reagent/essential_oil
	name = REAGENT_ESSENTIALOIL
	id = REAGENT_ID_ESSENTIALOIL
	scannable = SCANNABLE_ADVANCED
	description = "A slurry of compounds that contains the basic requirements for life."
	taste_description = "a mixture of thick, sweet, salty, salty and spicy flavours that all blend together to not be very nice at all"
	reagent_state = LIQUID
	color = "#e8e2b0"
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/nutriment/pitcher_nectar //Pitcher plant reagent, doubles plant growth speed.
	name = REAGENT_PITCHERNECTAR
	id = REAGENT_ID_PITCHERNECTAR
	description = "An odd, sticky slurry which promotes rapid plant growth."
	taste_description = "pineapple"
	reagent_state = LIQUID
	nutriment_factor = 60
	color = "#a839a2"


// === merged from other_ch.dm during hard-fork de-suffix (verified no override-order change) ===
//Misc stuff.

//LIQUID EGG
/datum/reagent/liquidspideregg
	name = REAGENT_SPIDEREGG
	id = REAGENT_ID_SPIDEREGG
	description = "These are eggs, spiders crawl out of these.. probably not healthy inside of a person."
	taste_description = "SO MANY LEGS"
	reagent_state = LIQUID
	color = "#FFFFFF"
	overdose = REAGENTS_OVERDOSE * 100
	metabolism = REM * 0.1
	scannable = 1
	var/amount_grown = 0
	var/min_growth = 0
	var/max_growth = 2
	var/spiders_min = 6
	var/spiders_max = 24
	var/spider_type = /obj/effect/spider/spiderling
	supply_conversion_value = REFINERYEXPORT_VALUE_NO
	industrial_use = REFINERYEXPORT_REASON_BIOHAZARD

/datum/reagent/liquidspideregg/affect_blood(mob/living/carbon/M, alien, removed)
	if(prob(1))
		M.custom_pain("You can feel movement within your body!",45)
	amount_grown += rand(min_growth,max_growth)
	if(amount_grown >= 100)
		min_growth++
		max_growth++
		amount_grown = 0
		var/num = rand(spiders_min, spiders_max)
		var/obj/item/organ/external/O = null
		if(istype(M.loc, /obj/item/organ/external))
			O = M.loc

		for(var/i=0, i<num, i++)
			var/spiderling = new spider_type(M.loc, M)
			if(O)
				O.implants += spiderling

//New reagent definitions/overrides. If some of these get added upstream and cause a conflict later they might need deleting.
/datum/reagent/toxin/plantbgone/touch_mob(mob/living/L, amount) //Plantbgone override to damage plant mobs. Part of pitcher plants, touch_mob doesn't exist for plantbgone at the time of writing.
	if(istype(L) && L.faction)
		if(L.faction == "plants") //This would be better with a variable but I'm not adding that because upstream conflicts. If you send this upstream please do this.
			L.adjustToxLoss(15 * amount)
			L.visible_message(span_warning("[L] withers rapidly!"), span_danger("The chemical burns you!"))

//////SAP IN UNREFINED FORM////

/datum/reagent/toxin/bluesap //This is the first sap. Blue one.
	name = REAGENT_BLUESAP
	id = REAGENT_ID_BLUESAP
	description = "Glowing blue liquid."
	reagent_state = LIQUID
	color = "#91f9ff" // rgb(145, 249, 255)
	metabolism = 0.01
	strength = 10//Don't drink it
	mrate_static = TRUE
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_RAW

/datum/reagent/purplesap
	name = REAGENT_ID_PURPLESAP
	id = REAGENT_PURPLESAP
	description = "Purple liquid. It is very sticky and smells of ammonia."
	color = "#7a48a0"
	taste_description = "Ammonia"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_RAW

/datum/reagent/orangesap
	name = REAGENT_ORANGESAP
	id = REAGENT_ID_ORANGESAP
	description = "Orange liquid. It wobbles around a bit like jelly."
	color = "#e0962f"
	taste_description = "Ammonia"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_RAW

//YW stuff

/datum/reagent/benzilate
	name = REAGENT_BENZILATE
	id = REAGENT_ID_BENZILATE
	description = "Grey... goo? This smells like hot acid. Consuming this likely wouldn't be good for your health."
	taste_description = "raw iron"
	taste_mult = 0.4
	metabolism = REM * 2.5
	color = "#929292"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_RAW

/datum/reagent/phenethylamine
	name = REAGENT_PHENETHYLAMINE
	id = REAGENT_ID_PHENETHYLAMINE
	description = "Just looking at this makes you feel odd. Whether or not this would be good to consume is likely a gamble."
	color = "#463667"
	data = list("count"=1)
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_RECDRUG
/datum/reagent/phenethylamine/on_mob_life(mob/living/M as mob)
	if(!M) M = holder.my_atom
	if(data)
		switch(data["count"])
			if(1 to 30)
				if(prob(9)) M.visible_emote("blushes")
				if(prob(9)) to_chat(M, span_warning("You feel so needy.."))
			if (30 to INFINITY)
				if(prob(3)) M.visible_emote("blushes")
				if(prob(5)) M.audible_emote("moans out lewdly!")
				if(prob(9)) to_chat(M, span_warning("You can't help but want to touch yourself then and now!"))
		data["count"]++
	holder.remove_reagent(src.id, 0.2)
	//..()
	return

/datum/reagent/benzilate/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien == IS_DIONA)
		return
	var/drug_strength = 12
	if(alien == IS_SKRELL)
		drug_strength = drug_strength * 0.6
	M.make_dizzy(drug_strength)
	M.Confuse(drug_strength * 14)

/obj/item/reagent_containers/pill/benzilate
	name = "Benzilate pill"
	desc = "You probably shouldn't swallow this."
	icon_state = "pill2"

/obj/item/reagent_containers/pill/benzilate/Initialize(mapload)
	. = ..()
	reagents.add_reagent(REAGENT_ID_BENZILATE, 50)
	color = reagents.get_color()


/obj/item/reagent_containers/pill/phenethylamine
	name = "Phenethylamine pill"
	desc = "Smells like... lilacs?"
	icon_state = "pill5"

/obj/item/reagent_containers/pill/phenethylamine/Initialize(mapload)
	. = ..()
	reagents.add_reagent(REAGENT_ID_PHENETHYLAMINE, 50)
	color = reagents.get_color()


// PILLS THAT WE PROBABLY SHOULDN'T HAVE AAAAAAAAAA. The below is only so they can be included through mapping or "spawn " command. -Carl

/obj/item/storage/pill_bottle/benzilate
	name = "bottle of Benzilate pills"
	desc = "This just hurts to look at with how many words of caution are scrawled on the lable. Better eat all of 'em!"

/obj/item/storage/pill_bottle/benzilate/Initialize(mapload)
	. = ..()
	new /obj/item/reagent_containers/pill/benzilate( src )
	new /obj/item/reagent_containers/pill/benzilate( src )
	new /obj/item/reagent_containers/pill/benzilate( src )
	new /obj/item/reagent_containers/pill/benzilate( src )
	new /obj/item/reagent_containers/pill/benzilate( src )
	new /obj/item/reagent_containers/pill/benzilate( src )
	new /obj/item/reagent_containers/pill/benzilate( src )

/obj/item/storage/pill_bottle/phenethylamine
	name = "bottle of Phenethylamine pills"
	desc = "Looks like someone drew a happy face on the label, replacing whatever was previously present."

/obj/item/storage/pill_bottle/phenethylamine/Initialize(mapload)
	. = ..()
	new /obj/item/reagent_containers/pill/phenethylamine( src )
	new /obj/item/reagent_containers/pill/phenethylamine( src )
	new /obj/item/reagent_containers/pill/phenethylamine( src )
	new /obj/item/reagent_containers/pill/phenethylamine( src )
	new /obj/item/reagent_containers/pill/phenethylamine( src )
	new /obj/item/reagent_containers/pill/phenethylamine( src )
	new /obj/item/reagent_containers/pill/phenethylamine( src )


// === merged from other_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/datum/reagent/advmutationtoxin
	name = REAGENT_ADVMUTATIONTOXIN
	id = REAGENT_ID_ADVMUTATIONTOXIN
	description = "A corruptive toxin produced by slimes. Turns the subject of the chemical into a Promethean."
	reagent_state = LIQUID
	dermal_absorption = 0 //Injection only.
	color = "#13BC5E"
	scannable = SCANNABLE_ADVANCED
	supply_conversion_value = REFINERYEXPORT_VALUE_MASSINDUSTRY
	industrial_use = REFINERYEXPORT_REASON_MATSCI

/datum/reagent/advmutationtoxin/affect_blood(mob/living/carbon/M, alien, removed)
	if(!(M.allow_spontaneous_tf))
		return
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(H.species.name != "Promethean")
			to_chat(M, span_danger("Your flesh rapidly mutates!"))

			var/list/backup_implants = list()
			for(var/obj/item/organ/I in H.organs)
				for(var/obj/item/implant/backup/BI in I.contents)
					backup_implants += BI
			if(backup_implants.len)
				for(var/obj/item/implant/backup/BI in backup_implants)
					BI.forceMove(src)

			H.set_species("Promethean")
			H.shapeshifter_set_colour("#05FF9B") //They can still change their color.

			if(backup_implants.len)
				var/obj/item/organ/external/torso = H.get_organ(BP_TORSO)
				for(var/obj/item/implant/backup/BI in backup_implants)
					BI.forceMove(torso)
					torso.implants += BI

/datum/reagent/nif_repair_nanites
	name = REAGENT_NIFREPAIRNANITES
	id = REAGENT_ID_NIFREPAIRNANITES
	description = "A thick grey slurry of NIF repair nanomachines."
	taste_description = "metallic"
	reagent_state = LIQUID
	color = "#333333"
	scannable = SCANNABLE_BENEFICIAL
	affects_robots = TRUE
	wiki_flag = WIKI_SPOILER

	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_MATSCI

/datum/reagent/nif_repair_nanites/affect_blood(mob/living/carbon/M, alien, removed)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(H.nif)
			var/obj/item/nif/nif = H.nif //L o c a l
			if(nif.stat == NIF_TEMPFAIL)
				nif.stat = NIF_INSTALLING
			nif.repair(removed)

/datum/reagent/firefighting_foam
	name = REAGENT_FIREFOAM
	id = REAGENT_ID_FIREFOAM
	description = "A historical fire suppressant. Originally believed to simply displace oxygen to starve fires, it actually interferes with the combustion reaction itself. Vastly superior to the cheap water-based extinguishers found on most NT vessels."
	reagent_state = LIQUID
	dermal_absorption = 0 //Custom touch handling. As funny as PFAS poisoning is.
	color = "#A6FAFF"
	scannable = SCANNABLE_ADVANCED
	taste_description = "the inside of a fire extinguisher"
	supply_conversion_value = REFINERYEXPORT_VALUE_UNWANTED
	industrial_use = REFINERYEXPORT_REASON_INDUSTRY

/datum/reagent/firefighting_foam/touch_turf(turf/T, reac_volume)
	if(reac_volume >= 1)
		var/obj/effect/effect/foam/firefighting/F = (locate(/obj/effect/effect/foam/firefighting) in T)
		if(!F)
			F = new(T)
		else if(istype(F))
			F.lifetime = initial(F.lifetime) //reduce object churn a little bit when using smoke by keeping existing foam alive a bit longer

	var/datum/gas_mixture/environment = T.return_air()
	var/min_temperature = T0C + 100 // 100C, the boiling point of water

	var/hotspot = (locate(/obj/fire) in T)
	if(hotspot && !isspace(T))
		var/datum/gas_mixture/lowertemp = T.remove_air(xgm_total_moles(T.return_air())) // XGM T.air → LINDA helper
		lowertemp.temperature = max(min(lowertemp.temperature-2000, lowertemp.temperature / 2), 0)
		lowertemp.react()
		T.assume_air(lowertemp)
		qdel(hotspot)

	if (environment && environment.temperature > min_temperature) // Abstracted as steam or something
		var/removed_heat = between(0, volume * 19000, -environment.get_thermal_energy_change(min_temperature))
		environment.add_thermal_energy(-removed_heat)
		if(prob(5))
			T.visible_message(span_warning("The foam sizzles as it lands on \the [T]!"))

	T.apply_fire_protection() // Apply fire protection to the turf

/datum/reagent/firefighting_foam/touch_obj(obj/O, reac_volume)
	O.water_act(reac_volume / 5)

/datum/reagent/firefighting_foam/touch_mob(mob/living/M, reac_volume)
	if(istype(M, /mob/living/simple_mob/slime)) //I'm sure foam is water-based!
		var/mob/living/simple_mob/slime/S = M
		S.adjustToxLoss(15 * reac_volume)
		S.visible_message(span_warning("[S]'s flesh sizzles where the foam touches it!"), span_danger("Your flesh burns in the foam!"))
	if(istype(M))
		M.adjust_fire_stacks(-reac_volume)
		M.extinguish_mob()

/datum/reagent/liquid_protean
	name = REAGENT_LIQUIDPROTEAN
	id = REAGENT_ID_LIQUIDPROTEAN
	description = "This seems to be a small portion of a Protean creature, still slightly wiggling."
	taste_description = "wiggly peanutbutter"
	reagent_state = LIQUID
	color = "#1d1d1d"
	scannable = SCANNABLE_BENEFICIAL
	metabolism = REM * 0.5
	affects_robots = TRUE
	supply_conversion_value = REFINERYEXPORT_VALUE_UNWANTED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/liquid_protean/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien != IS_DIONA)
		var/chem_effective = 1
		if(alien == IS_SLIME)
			chem_effective = 0.5
		M.adjustOxyLoss(-1 * removed * chem_effective)
		M.heal_organ_damage(0.5 * removed, 0.5 * removed * chem_effective)
		M.adjustToxLoss(-0.5 * removed * chem_effective)

	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(H.nif)
			var/obj/item/nif/nif = H.nif //L o c a l
			if(nif.stat == NIF_TEMPFAIL)
				nif.stat = NIF_INSTALLING
			nif.repair(removed*0.1)

//Special toxins for solargrubs
/datum/reagent/grubshock
	name = REAGENT_SHOCKCHEM //in other words a painful shock
	id = REAGENT_ID_SHOCKCHEM
	description = "A liquid that quickly dissapates to deliver a painful shock."
	reagent_state = LIQUID
	color = "#E4EC2F"
	metabolism = 2.50
	scannable = SCANNABLE_ADVANCED
	var/power = 9
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/grubshock/affect_blood(mob/living/carbon/M, alien, removed)
	M.take_organ_damage(0, removed * power * 0.2)
