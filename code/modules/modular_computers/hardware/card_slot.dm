/obj/item/computer_hardware/card_slot
	name = "RFID card slot"
	desc = "Slot that allows this computer to write data on RFID cards. Necessary for some programs to run properly."
	power_usage = 10 //W
	critical = 0
	icon_state = "cardreader"
	hardware_size = 1

	var/tmp/obj/item/card/id/stored_card

/obj/item/computer_hardware/card_slot/get_slot_var()
	return "card_slot"

OWN(/obj/item/modular_computer, processor_unit, OWN_CONTAINED)
OWN(/obj/item/modular_computer, network_card, OWN_CONTAINED)
OWN(/obj/item/modular_computer, hard_drive, OWN_CONTAINED)
OWN(/obj/item/modular_computer, battery_module, OWN_CONTAINED)
OWN(/obj/item/modular_computer, card_slot, OWN_CONTAINED)
OWN(/obj/item/modular_computer, nano_printer, OWN_CONTAINED)
OWN(/obj/item/modular_computer, portable_drive, OWN_CONTAINED)
OWN(/obj/item/modular_computer, tesla_link, OWN_CONTAINED)

// its card drops at the computer's turf.
/obj/item/computer_hardware/card_slot/on_destroy(force)
	var/slot = get_slot_var()
	if(holder2() && (holder2().vars[slot] == src))
		holder2().vars[slot] = null // ALLOW(api): hardware slot cleared by name on removal
	if(stored_card())
		stored_card().forceMove(get_turf(holder2()))
	..()

/// The stored_card this refers to (a relation view: null once that is deleted).
/obj/item/computer_hardware/card_slot/proc/stored_card() as /obj/item/card/id
	return stored_card
