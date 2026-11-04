/obj/item/clothing/glasses/omnihud/med
	name = "\improper AR-M glasses"
	desc = "The ARG-62-M AR Glasses are capable of displaying information on individuals. \
	These have been upgraded with medical records access and virus database integration. \
	They can also read data from active suit sensors using the crew monitoring system."
	mode = "med"
	tgarscreen_path = /datum/tgui_module/crew_monitor/glasses
	enables_planes = list(VIS_CH_ID,VIS_CH_HEALTH_VR,VIS_CH_STATUS_R,VIS_CH_BACKUP,VIS_AUGMENTED)

CAPABILITIES(/obj/item/clothing/glasses/omnihud/med)
	configure(item_rules(actions_types = list(/datum/action/item_action/ar_console_crew)))

/obj/item/clothing/glasses/omnihud/med/ar_interact(mob/living/carbon/human/user)
	if(tgarscreen)
		tgarscreen.tgui_interact(user)
	return 1

//Rx Variants
/obj/item/clothing/glasses/omnihud/med/prescription
	desc = "The ARG-62-M AR Glasses are capable of displaying information on individuals. \
	These have been upgraded with medical records access and virus database integration. \
	They can also read data from active suit sensors using the crew monitoring system. \
	These have been equipped with prescription lenses."
	prescription = TRUE
