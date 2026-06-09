/obj/item/computer_hardware/tesla_link
	name = "tesla link"
	desc = "An advanced tesla link that wirelessly recharges connected device from nearby area power controller."
	critical = 0
	enabled = 1
	icon_state = "teslalink"
	hardware_size = 1
	var/passive_charging_rate = 250			// W

/obj/item/computer_hardware/tesla_link/get_slot_var()
	return "tesla_link"

/obj/item/computer_hardware/tesla_link/Destroy()
	var/slot = get_slot_var()
	if(holder2 && (holder2.vars[slot] == src))
		holder2.vars[slot] = null
	return ..()
