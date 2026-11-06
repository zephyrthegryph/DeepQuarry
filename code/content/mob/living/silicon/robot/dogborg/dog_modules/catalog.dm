/obj/item/shockpaddles/robot/hound
	name = "paws of life"
	icon = 'icons/mob/dogborg_vr.dmi'
	icon_state = "defibpaddles0"
	desc = "Zappy paws. For fixing cardiac arrest."
	combat = 1
	chargecost = 500

CAPABILITIES(/obj/item/shockpaddles/robot/hound)
	configure(item_combat(attack_verbs = list("batted", "pawed", "bopped", "whapped")))

/obj/item/shockpaddles/robot/hound/jumper
	name = "jumper paws"
	desc = "Zappy paws. For rebooting a full body prostetic."
	use_on_synthetic = 1

/obj/item/reagent_containers/borghypo/hound
	name = "MediHound hypospray"
	desc = "An advanced chemical synthesizer and injection system utilizing carrier's reserves, designed for heavy-duty medical equipment."
	var/datum/matter_synth/water = null

CAPABILITIES(/obj/item/reagent_containers/borghypo/hound)
	ref_one(nameof(water), /datum/matter_synth)

// More chems for Medihound
TYPE_TABLE(/obj/item/reagent_containers/borghypo/hound, borghypo_reagent_ids, list(REAGENT_ID_INAPROVALINE, REAGENT_ID_TRICORDRAZINE, REAGENT_ID_DEXALIN, REAGENT_ID_BICARIDINE, REAGENT_ID_KELOTANE, REAGENT_ID_ANTITOXIN, REAGENT_ID_SPACEACILLIN, REAGENT_ID_TRAMADOL, REAGENT_ID_ADRANOL))

/obj/item/reagent_containers/borghypo/hound/lost
	name = "Hound hypospray"
	desc = "An advanced chemical synthesizer and injection system utilizing carrier's reserves."

TYPE_TABLE(/obj/item/reagent_containers/borghypo/hound/lost, borghypo_reagent_ids, list(REAGENT_ID_TRICORDRAZINE, REAGENT_ID_INAPROVALINE, REAGENT_ID_BICARIDINE, REAGENT_ID_DEXALIN, REAGENT_ID_ANTITOXIN, REAGENT_ID_TRAMADOL, REAGENT_ID_SPACEACILLIN))

/obj/item/reagent_containers/borghypo/hound/trauma
	name = "Hound hypospray"
	desc = "An advanced chemical synthesizer and injection system utilizing carrier's reserves."

TYPE_TABLE(/obj/item/reagent_containers/borghypo/hound/trauma, borghypo_reagent_ids, list(REAGENT_ID_TRICORDRAZINE, REAGENT_ID_INAPROVALINE, REAGENT_ID_OXYCODONE, REAGENT_ID_DEXALIN ,REAGENT_ID_SPACEACILLIN))
