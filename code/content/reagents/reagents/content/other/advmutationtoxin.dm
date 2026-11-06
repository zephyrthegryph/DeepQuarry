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
	if(!(M.vore_prefs.allow_spontaneous_tf))
		return
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(H.species.name != "Promethean")
			to_chat(M, span_danger("Your flesh rapidly mutates!"))

			var/list/backup_implants = list()
			for(var/obj/item/organ/I in H.organs)
				for(var/obj/item/implant/backup/BI in contents_of(I))
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
					rel_add(torso, nameof(torso.implants), BI)
