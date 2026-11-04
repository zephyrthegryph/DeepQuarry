/obj/item/clothing/glasses/hud
	name = DEVELOPER_WARNING_NAME
	desc = "A heads-up display that provides important info in (almost) real time."
	flags = NONE //doesn't protect eyes because it's a monocle, duh

/obj/item/clothing/glasses/hud/health
	name = "Health Scanner HUD"
	desc = "A heads-up display that scans the humans in view and provides accurate data about their health status."
	icon_state = "healthhud"
	item_state_slots = list(slot_r_hand_str = "headset", slot_l_hand_str = "headset")
	enables_planes = list(VIS_CH_STATUS,VIS_CH_HEALTH)

CAPABILITIES(/obj/item/clothing/glasses/hud/health)
	configure(item_worn(covers = 0))

/obj/item/clothing/glasses/hud/health/prescription
	desc = "A medical HUD integrated with a set of prescription glasses. \
	These have been equipped with prescription lenses."
	prescription = TRUE
	icon_state = "healthhudpresc"
	item_state_slots = list(slot_r_hand_str = "glasses", slot_l_hand_str = "glasses")

/obj/item/clothing/glasses/hud/security
	name = "Security HUD"
	desc = "A heads-up display that scans the humans in view and provides accurate data about their ID status and security records."
	icon_state = "securityhud"
	item_state_slots = list(slot_r_hand_str = "headset", slot_l_hand_str = "headset")
	enables_planes = list(VIS_CH_ID,VIS_CH_WANTED,VIS_CH_IMPTRACK,VIS_CH_IMPLOYAL,VIS_CH_IMPCHEM)

CAPABILITIES(/obj/item/clothing/glasses/hud/security)
	configure(item_worn(covers = 0))

/obj/item/clothing/glasses/hud/security/prescription
	desc = "A security HUD integrated with a set of prescription glasses. \
	These have been equipped with prescription lenses."
	prescription = TRUE
	icon_state = "sechudpresc"
	item_state_slots = list(slot_r_hand_str = "glasses", slot_l_hand_str = "glasses")

/obj/item/clothing/glasses/hud/security/jensenshades
	name = "Augmented shades"
	desc = "Polarized bioneural eyewear, designed to augment your vision."
	icon_state = "jensenshades"
	item_state_slots = list(slot_r_hand_str = "sunglasses", slot_l_hand_str = "sunglasses")
	vision_flags = SEE_MOBS
	see_invisible = SEE_INVISIBLE_NOLIGHTING

/obj/item/clothing/glasses/hud/janitor
	name = "Contaminant Detector HUD"
	desc = "A heads-up display that scans the environment for contaminations."
	icon_state = "janhud"
	item_state_slots = list(slot_r_hand_str = "headset", slot_l_hand_str = "headset")
	enables_planes = list(VIS_JANHUD)

CAPABILITIES(/obj/item/clothing/glasses/hud/janitor)
	configure(item_worn(covers = 0))

/obj/item/clothing/glasses/hud/janitor/prescription
	desc = "A heads-up display that scans the environment for contaminations. \
	These have been equipped with prescription lenses."
	prescription = TRUE
	icon_state = "janhudpresc"
	item_state_slots = list(slot_r_hand_str = "glasses", slot_l_hand_str = "glasses")
