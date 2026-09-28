/obj/item/computer_hardware/card_slot
	name = "RFID card slot"
	desc = "Slot that allows this computer to write data on RFID cards. Necessary for some programs to run properly."
	power_usage = 10 //W
	critical = 0
	icon_state = "cardreader"
	hardware_size = 1

	var/tmp/stored_card_handle

/obj/item/computer_hardware/card_slot/get_slot_var()
	return "card_slot"

DECLARE_REF(/obj/item/modular_computer, "processor_unit", HELD, null)
DECLARE_REF(/obj/item/modular_computer, "network_card", HELD, null)
DECLARE_REF(/obj/item/modular_computer, "hard_drive", HELD, null)
DECLARE_REF(/obj/item/modular_computer, "battery_module", HELD, null)
DECLARE_REF(/obj/item/modular_computer, "card_slot", HELD, null)
DECLARE_REF(/obj/item/modular_computer, "nano_printer", HELD, null)
DECLARE_REF(/obj/item/modular_computer, "portable_drive", HELD, null)
DECLARE_REF(/obj/item/modular_computer, "tesla_link", HELD, null)

// its card drops at the computer's turf.
/obj/item/computer_hardware/card_slot/on_destroy(force)
	var/slot = get_slot_var()
	if(holder2() && (holder2().vars[slot] == src))
		holder2().vars[slot] = null // ALLOW(api): hardware slot cleared by name on removal
	if(stored_card())
		stored_card().forceMove(get_turf(holder2()))
	..()

/// LC-refs: the stored_card this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/computer_hardware/card_slot/proc/stored_card() as /obj/item/card/id
	return om_resolve(stored_card_handle)
