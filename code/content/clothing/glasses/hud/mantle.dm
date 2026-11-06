/obj/item/clothing/glasses/omnihud/mantle
	name = "AR mantle"
	desc = "A full-face, partially-obscuring visor favoured by certain subcultures and those with sensitive eyes. Covers the face and eyes, but it's not enough to actually hide your identity. The interior has a simple augmented-reality display that aids with daily tasks. It can be toggled in and out of corrective vision mode via integrated subroutine."
	icon_state = "mantle_HUD"
	item_state = "mantle_HUD"
	can_shade = FALSE

/obj/item/clothing/glasses/omnihud/mantle/ar_interact(mob/living/carbon/human/user)
	if(tgarscreen)
		tgarscreen.tgui_interact(user)
	return 1

CAPABILITIES(/obj/item/clothing/glasses/omnihud/mantle)
	configure(item_worn(covers = EYES, hides = HIDEFACE))
	op("mantle_switcheye_verb", menu(), label("Toggle Autocorrective Vision"), needs(carried()), then(PROC_REF(mantle_switcheye_verb)))

/// Old verb "Toggle Autocorrective Vision".
/obj/item/clothing/glasses/omnihud/mantle/proc/mantle_switcheye_verb(datum/act/op/A)
	var/mob/user = A.actor
	if(!isliving(user)) return
	if(user.stat) return

	prescription = !prescription
	if(prescription)
		to_chat(user, "You switch the [src] into autocorrective mode.")
	else
		to_chat(user, "You switch the [src] out of autocorrective mode.")

/obj/item/clothing/glasses/omnihud/mantle/eng
	name = "engineering AR mantle"
	desc = "A full-face, partially-obscuring visor favoured by certain subcultures and those with sensitive eyes. Covers the face and eyes, but it's not enough to actually hide your identity. The interior has a simple augmented-reality display that aids with daily tasks. It can be toggled in and out of corrective vision mode via integrated subroutine. This version includes extra engineering-related functions."
	mode = "eng"
	flash_protection = FLASH_PROTECTION_MAJOR
	tgarscreen_path = /datum/tgui_module/alarm_monitor/engineering/glasses

CAPABILITIES(/obj/item/clothing/glasses/omnihud/mantle/eng)
	configure(item_rules(actions_types = list(/datum/action/item_action/ar_console_station_alerts)))
