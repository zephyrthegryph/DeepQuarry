/obj/item/clothing/glasses/omnihud/sec
	name = "\improper AR-S glasses"
	desc = "The ARG-62-S AR Glasses are capable of displaying information on individuals. \
	These have been upgraded with security records integration and flash protection. \
	They also have access to security alerts such as camera and motion sensor alarms."
	mode = "sec"
	flash_protection = FLASH_PROTECTION_MODERATE //weld protection is a little too widespread
	tgarscreen_path = /datum/tgui_module/alarm_monitor/security/glasses
	enables_planes = list(VIS_CH_ID,VIS_CH_HEALTH_VR,VIS_CH_WANTED,VIS_AUGMENTED)

CAPABILITIES(/obj/item/clothing/glasses/omnihud/sec)
	configure(item_rules(actions_types = list(/datum/action/item_action/ar_console_security_alerts)))

/obj/item/clothing/glasses/omnihud/sec/ar_interact(mob/living/carbon/human/user)
	if(tgarscreen)
		tgarscreen.tgui_interact(user)
	return 1

/obj/item/clothing/glasses/omnihud/sec/prescription
	desc = "The ARG-62-S AR Glasses are capable of displaying information on individuals. \
	These have been upgraded with security records integration and flash protection. \
	They also have access to security alerts such as camera and motion sensor alarms. \
	These have been equipped with prescription lenses."
	prescription = TRUE
