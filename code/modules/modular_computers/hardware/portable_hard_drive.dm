// These are basically USB data sticks and may be used to transfer files between devices
/obj/item/computer_hardware/hard_drive/portable
	name = "basic data crystal"
	desc = "Small crystal with imprinted photonic circuits that can be used to store data. Its capacity is 16 GQ."
	power_usage = 10
	icon_state = "flashdrive_basic"
	hardware_size = 1
	max_capacity = 16

/obj/item/computer_hardware/hard_drive/portable/advanced
	name = "advanced data crystal"
	desc = "Small crystal with imprinted high-density photonic circuits that can be used to store data. Its capacity is 64 GQ."
	power_usage = 20
	icon_state = "flashdrive_advanced"
	hardware_size = 1
	max_capacity = 64

/obj/item/computer_hardware/hard_drive/portable/super
	name = "super data crystal"
	desc = "Small crystal with imprinted ultra-density photonic circuits that can be used to store data. Its capacity is 256 GQ."
	power_usage = 40
	icon_state = "flashdrive_super"
	hardware_size = 1
	max_capacity = 256

/// Portable drives use a separate slot var from regular hard drives so both can
/// be installed in the same computer simultaneously.
/obj/item/computer_hardware/hard_drive/portable/get_slot_var()
	return "portable_drive"

/// Portable drives are hot-swappable and do not trigger a computer shutdown.
/obj/item/computer_hardware/hard_drive/portable/is_critical_slot()
	return FALSE

/obj/item/computer_hardware/hard_drive/portable/Initialize(mapload)
	. = ..()
	stored_files = list()
	recalculate_size()

/obj/item/computer_hardware/hard_drive/portable/Destroy()
	var/slot = get_slot_var()
	if(holder2 && (holder2.vars[slot] == src))
		holder2.vars[slot] = null
	return ..()
