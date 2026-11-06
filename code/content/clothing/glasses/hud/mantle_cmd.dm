/obj/item/clothing/glasses/omnihud/mantle/cmd
	name = "command AR mantle"
	desc = "A full-face, partially-obscuring visor favoured by certain subcultures and those with sensitive eyes. Covers the face and eyes, but it's not enough to actually hide your identity. The interior has a simple augmented-reality display that aids with daily tasks. It can be toggled in and out of corrective vision mode via integrated subroutine. This version includes extra command-related functions."
	mode = "best"
	flash_protection = FLASH_PROTECTION_MAJOR
	enables_planes = list(VIS_CH_ID,VIS_CH_HEALTH_VR,VIS_CH_STATUS_R,VIS_CH_BACKUP,VIS_CH_WANTED,VIS_AUGMENTED)
	tgarscreen_path = /datum/tgui_module/alarm_monitor/all/glasses

CAPABILITIES(/obj/item/clothing/glasses/omnihud/mantle/cmd)
	configure(item_rules(actions_types = list(/datum/action/item_action/ar_console_all_alerts)))

/obj/item/clothing/glasses/omnihud/mantle/cmd/ar_interact(mob/living/carbon/human/user)
	if(tgarscreen)
		tgarscreen.tgui_interact(user)
	return 1
