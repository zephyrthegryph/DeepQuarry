/**
 * # Experi-Scanner
 *
 * Handheld scanning unit to perform scanning experiments
 */
/obj/item/experi_scanner
	name = "Experi-Scanner"
	desc = "A handheld scanner used for completing the many experiments of modern science."
	w_class = ITEMSIZE_SMALL
	icon = 'icons/obj/devices/scanner.dmi'
	icon_state = "experiscanner"
	item_state = "experiscanner"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_devices.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_devices.dmi',
	)

/obj/item/experi_scanner/Initialize(mapload)
	. = ..()
	return INITIALIZE_HINT_LATELOAD

/obj/item/experi_scanner/LateInitialize()
	var/static/list/handheld_events = list(
		/datum/act/pre_attack = TYPE_PROC_REF(/datum/experiment_handler, try_run_handheld_experiment),
	)
	new /datum/experiment_handler(src, \
		allowed_experiments = list(/datum/experiment/scanning, /datum/experiment/physical), \
		disallowed_traits = EXPERIMENT_TRAIT_DESTRUCTIVE, \
		experiment_events = handheld_events, \
	)
