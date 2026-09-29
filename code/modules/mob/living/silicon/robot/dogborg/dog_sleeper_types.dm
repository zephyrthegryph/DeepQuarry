/obj/item/dogborg/sleeper/K9 //The K9 portabrig
	name = "Brig-Belly"
	desc = "A mounted portable-brig that holds criminals for processing or 'processing'."
	icon_state = "sleeperb"
	stabilizer = TRUE
	medsensor = FALSE
//So they don't have all the same chems as the medihound!
TYPE_TABLE(/obj/item/dogborg/sleeper/K9, sleeper_injection_chems, null)

/obj/item/dogborg/sleeper/compactor //Janihound gut.
	name = "Garbage Processor"
	desc = "A mounted garbage compactor unit with fuel processor, capable of processing any kind of contaminant."
	icon_state = "compactor"
	compactor = TRUE
	recycles = TRUE
	max_item_count = 25
	stabilizer = FALSE
	medsensor = FALSE
//So they don't have all the same chems as the medihound!
TYPE_TABLE(/obj/item/dogborg/sleeper/compactor, sleeper_injection_chems, null)

/obj/item/dogborg/sleeper/compactor/analyzer //sci-borg gut.
	name = "Digestive Analyzer"
	desc = "A mounted destructive analyzer unit with fuel processor, for 'deep scientific analysis'."
	icon_state = "analyzer"
	max_item_count = 10
	startdrain = 100
	analyzer = TRUE
	recycles = FALSE

/obj/item/dogborg/sleeper/compactor/decompiler
	name = "Matter Decompiler"
	desc = "A mounted matter decompiling unit with fuel processor, for recycling anything and everyone."
	icon_state = "decompiler"
	max_item_count = 10
	decompiler = TRUE
	recycles = TRUE

/obj/item/dogborg/sleeper/compactor/supply //Miner borg belly
	name = "Supply Storage"
	desc = "A mounted survival unit with fuel processor, helpful with both deliveries and assisting injured miners."
	icon_state = "sleeperc"
	max_item_count = 20
	ore_storage = TRUE
	medsensor = FALSE
TYPE_TABLE(/obj/item/dogborg/sleeper/compactor/supply, sleeper_injection_chems, list(REAGENT_ID_GLUCOSE,REAGENT_ID_INAPROVALINE,REAGENT_ID_TRICORDRAZINE))

/obj/item/dogborg/sleeper/compactor/supply/afterattack(atom/movable/target, mob/living/silicon/user, proximity_flag, click_parameters)
	if(!proximity_flag)
		return

	if(isturf(target))
		if(ore_bag.gather_all(target, user, TRUE))
			act_message(user, null, MSG_SELF(span_notice("Your [src.name] groans lightly as ore slips inside.")), \
				MSG_OTHERS(span_warning("[hound.name]'s [src.name] groans lightly as ore slips inside.")))
			playsound(src, gulpsound, vol = 60, vary = 1, falloff = 0.1, preference = /datum/preference/toggle/eating_noises)
			return
	if(istype(target, /obj/item/ore) && !istype(target, /obj/item/ore/slag) && !istype(target, /obj/item/ore/archeology_debris))
		var/turf_check = isturf(target.loc) //get_turf intentionally not used here due to clicking ore in a backpack or other weirdness.
		if(turf_check)
			if(ore_bag.gather_all(target.loc, user, TRUE))
				act_message(user, null, MSG_SELF(span_notice("Your [src.name] groans lightly as ore slips inside.")), \
					MSG_OTHERS(span_warning("[hound.name]'s [src.name] groans lightly as ore slips inside.")))
				playsound(src, gulpsound, vol = 60, vary = 1, falloff = 0.1, preference = /datum/preference/toggle/eating_noises)
				return
	. = ..()

/obj/item/dogborg/sleeper/compactor/brewer
	name = "Brew Belly"
	desc = "A mounted drunk tank unit with fuel processor, for putting away particularly rowdy patrons."
	icon_state = "brewer"
	max_item_count = 10
	recycles = FALSE
	stabilizer = TRUE
	medsensor = FALSE
//So they don't have all the same chems as the medihound!
TYPE_TABLE(/obj/item/dogborg/sleeper/compactor/brewer, sleeper_injection_chems, null)

/obj/item/dogborg/sleeper/compactor/generic
	name = "Internal Cache"
	desc = "An internal storage of no particularly specific purpose.."
	icon_state = "sleeperd"
	max_item_count = 10
	recycles = FALSE

/obj/item/dogborg/sleeper/compactor/brewer/inject_chem(mob/user, chem)
	if(patient && patient.reagents)
		if(chem in (TYPE_TABLE_GET(src, sleeper_injection_chems) + REAGENT_ID_INAPROVALINE))
			if(!hound.cell || hound.cell.charge < 200) //This is so borgs don't kill themselves with it.
				to_chat(hound, span_notice("You don't have enough power to synthesize fluids."))
				return
			else if(patient.reagents.get_reagent_amount(chem) + 10 >= 50) //Preventing people from accidentally killing themselves by trying to inject too many chemicals!
				to_chat(hound, span_notice("Your stomach is currently too full of fluids to secrete more fluids of this kind."))
			else if(patient.reagents.get_reagent_amount(chem) + 10 <= 50) //No overdoses for you
				patient.reagents.add_reagent(chem, inject_amount)
				drain(100) //-100 charge per injection
			var/units = round(patient.reagents.get_reagent_amount(chem))
			to_chat(hound, span_notice("Injecting [units] unit\s into occupant.")) //If they were immersed, the reagents wouldn't leave with them.

/obj/item/dogborg/sleeper/K9/ert
	name = "Emergency Storage"
	desc = "A mounted 'emergency containment cell'."
	icon_state = "sleeperert"
// short list
TYPE_TABLE(/obj/item/dogborg/sleeper/K9/ert, sleeper_injection_chems, list(REAGENT_ID_INAPROVALINE, REAGENT_ID_TRAMADOL))

/obj/item/dogborg/sleeper/trauma //Trauma borg belly
	name = "Recovery Belly"
	desc = "A downgraded model of the sleeper belly, intended primarily for post-surgery recovery."
	icon_state = "sleeper"
TYPE_TABLE(/obj/item/dogborg/sleeper/trauma, sleeper_injection_chems, list(REAGENT_ID_INAPROVALINE, REAGENT_ID_DEXALIN, REAGENT_ID_TRICORDRAZINE, REAGENT_ID_SPACEACILLIN, REAGENT_ID_OXYCODONE))

/obj/item/dogborg/sleeper/lost
	name = "Multipurpose Belly"
	desc = "A multipurpose belly, capable of functioning as both sleeper and processor."
	icon_state = "sleeperlost"
	compactor = TRUE
	max_item_count = 25
	stabilizer = TRUE
	medsensor = TRUE
TYPE_TABLE(/obj/item/dogborg/sleeper/lost, sleeper_injection_chems, list(REAGENT_ID_TRICORDRAZINE, REAGENT_ID_BICARIDINE, REAGENT_ID_DEXALIN, REAGENT_ID_ANTITOXIN, REAGENT_ID_TRAMADOL, REAGENT_ID_SPACEACILLIN))

/obj/item/dogborg/sleeper/syndie
	name = "Combat Triage Belly"
	desc = "A mounted sleeper that stabilizes patients and can inject reagents in the borg's reserves. This one is for more extreme combat scenarios."
	icon_state = "sleepersyndiemed"
	digest_multiplier = 2
TYPE_TABLE(/obj/item/dogborg/sleeper/syndie, sleeper_injection_chems, list(REAGENT_ID_HEALINGNANITES, REAGENT_ID_HYPERZINE, REAGENT_ID_TRAMADOL, REAGENT_ID_OXYCODONE, REAGENT_ID_SPACEACILLIN, REAGENT_ID_PERIDAXON, REAGENT_ID_OSTEODAXON, REAGENT_ID_MYELAMINE, REAGENT_ID_SYNTHBLOOD))

/obj/item/dogborg/sleeper/K9/syndie
	name = "Cell-Belly"
	desc = "A mounted portable cell that holds anyone you wish for processing or 'processing'."
	icon_state = "sleepersyndiebrig"
	digest_multiplier = 3

/obj/item/dogborg/sleeper/compactor/syndie
	name = "Advanced Matter Decompiler"
	desc = "A mounted matter decompiling unit with fuel processor, for recycling anything and everyone in your way."
	icon_state = "sleepersyndieeng"
	max_item_count = 35
	digest_multiplier = 3

/obj/item/dogborg/sleeper/command //Command borg belly
	name = "Bluespace Filing Belly"
	desc = "A mounted bluespace storage unit for carrying paperwork"
	icon_state = "sleeperd"
	compactor = TRUE
	recycles = FALSE
	max_item_count = 25
	medsensor = FALSE
TYPE_TABLE(/obj/item/dogborg/sleeper/command, sleeper_injection_chems, null)

/obj/item/dogborg/sleeper/compactor/honkborg
	name = "Jiggles Von Hungertron"
	desc = "You've heard of Giggles Von Honkerton for the back, now get ready for Jiggles Von Hungertron for the front."
	icon_state = "clowngut"
	recycles = FALSE

/obj/item/dogborg/sleeper/exploration
	name = "Store-Belly"
	desc = "Equipment for a ExploreHound unit. A mounted portable-storage device that holds supplies/person."
	icon_state = "sleeperlost"
	compactor = TRUE
	max_item_count = 4
	medsensor = FALSE
	recycles = TRUE
// Only to stabilize during extractions
TYPE_TABLE(/obj/item/dogborg/sleeper/exploration, sleeper_injection_chems, list(REAGENT_ID_INAPROVALINE))
