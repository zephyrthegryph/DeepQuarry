/obj/item/clothing/glasses/omnihud/eng
	name = "\improper AR-E glasses"
	desc = "The ARG-62-E AR Glasses are capable of displaying information on individuals. \
	These have been upgraded with advanced electrochromic lenses to protect your eyes during welding, \
	and can also display a list of atmospheric, fire, and power alarms."
	mode = "eng"
	flash_protection = FLASH_PROTECTION_MAJOR
	tgarscreen_path = /datum/tgui_module/alarm_monitor/engineering/glasses

CAPABILITIES(/obj/item/clothing/glasses/omnihud/eng)
	configure(item_rules(actions_types = list(/datum/action/item_action/ar_console_station_alerts)))

/obj/item/clothing/glasses/omnihud/eng/ar_interact(mob/living/carbon/human/user)
	if(tgarscreen)
		tgarscreen.tgui_interact(user)
	return 1

/obj/item/clothing/glasses/omnihud/eng/prescription
	desc = "The ARG-62-E AR Glasses are capable of displaying information on individuals. \
	These have been upgraded with advanced electrochromic lenses to protect your eyes during welding, \
	and can also display a list of atmospheric, fire, and power alarms. \
	These have been equipped with prescription lenses."
	prescription = TRUE
