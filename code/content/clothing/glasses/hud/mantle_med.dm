/obj/item/clothing/glasses/omnihud/mantle/med
	name = "medical AR mantle"
	desc = "A full-face, partially-obscuring visor favoured by certain subcultures and those with sensitive eyes. Covers the face and eyes, but it's not enough to actually hide your identity. The interior has a simple augmented-reality display that aids with daily tasks. It can be toggled in and out of corrective vision mode via integrated subroutine. This version includes extra medical-related functions."
	mode = "med"
	tgarscreen_path = /datum/tgui_module/crew_monitor/glasses
	enables_planes = list(VIS_CH_ID,VIS_CH_HEALTH_VR,VIS_CH_STATUS_R,VIS_CH_BACKUP,VIS_AUGMENTED)

CAPABILITIES(/obj/item/clothing/glasses/omnihud/mantle/med)
	configure(item_rules(actions_types = list(/datum/action/item_action/ar_console_crew)))

/obj/item/clothing/glasses/omnihud/mantle/med/ar_interact(mob/living/carbon/human/user)
	if(tgarscreen)
		tgarscreen.tgui_interact(user)
	return 1
