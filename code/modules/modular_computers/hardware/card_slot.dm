/obj/item/computer_hardware/card_slot
	name = "RFID card slot"
	desc = "Slot that allows this computer to write data on RFID cards. Necessary for some programs to run properly."
	power_usage = 10 //W
	critical = 0
	icon_state = "cardreader"
	hardware_size = 1

	var/obj/item/card/id/stored_card = null

/obj/item/computer_hardware/card_slot/get_slot_var()
	return "card_slot"

/obj/item/computer_hardware/card_slot/Destroy()
	var/slot = get_slot_var()
	if(holder2 && (holder2.vars[slot] == src))
		holder2.vars[slot] = null
	if(stored_card)
		stored_card.forceMove(get_turf(holder2))
	holder2 = null
	return ..()
