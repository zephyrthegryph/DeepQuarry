/obj/item/clothing/glasses/omnihud/all
	name = "\improper AR-B glasses"
	desc = "The ARG-62-B AR Glasses are capable of displaying information on individuals. \
	These have been upgraded with (almost) every feature the lesser models have. Now we're talkin'. \
	<br>Offers full protection against bright flashes/welders and full access to system alarm monitoring."
	mode = "best"
	flash_protection = FLASH_PROTECTION_MAJOR
	enables_planes = list(VIS_CH_ID,VIS_CH_HEALTH_VR,VIS_CH_STATUS_R,VIS_CH_BACKUP,VIS_CH_WANTED,VIS_AUGMENTED)
	tgarscreen_path = /datum/tgui_module/alarm_monitor/all/glasses

CAPABILITIES(/obj/item/clothing/glasses/omnihud/all)
	configure(item_rules(actions_types = list(/datum/action/item_action/ar_console_all_alerts)))

/obj/item/clothing/glasses/omnihud/all/ar_interact(mob/living/carbon/human/user)
	if(tgarscreen)
		tgarscreen.tgui_interact(user)
	return 1

/obj/item/clothing/glasses/omnihud/all/prescription
	desc = "The ARG-62-B AR Glasses are capable of displaying information on individuals. \
	These have been upgraded with (almost) every feature the lesser models have. Now we're talkin'. \
	<br>Offers full protection against bright flashes/welders and full access to system alarm monitoring. \
	These have been equipped with prescription lenses."
	prescription = TRUE
