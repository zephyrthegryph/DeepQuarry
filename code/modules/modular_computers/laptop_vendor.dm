// A vendor machine for modular computer portable devices - Laptops and Tablets

/obj/machinery/lapvend
	name = "computer vendor"
	desc = "A vending machine with a built-in microfabricator, capable of dispensing various NT-branded computers."
	icon = 'icons/obj/vending.dmi'
	icon_state = "robotics"
	layer = OBJ_LAYER - 0.1
	anchored = TRUE
	density = TRUE

	// The actual laptop/tablet
	var/obj/item/modular_computer/laptop/fabricated_laptop = null
	var/obj/item/modular_computer/tablet/fabricated_tablet = null

	// Utility vars
	state = 0 							// 0: Select device type, 1: Select loadout, 2: Payment, 3: Thankyou screen
	var/devtype = 0 						// 0: None(unselected), 1: Laptop, 2: Tablet
	var/total_price = 0						// Price of currently vended device.

	// Device loadout
	var/dev_cpu = 1							// 1: Default, 2: Upgraded
	var/dev_battery = 1						// 1: Default, 2: Upgraded, 3: Advanced
	var/dev_disk = 1						// 1: Default, 2: Upgraded, 3: Advanced
	var/dev_netcard = 0						// 0: None, 1: Basic, 2: Long-Range
	var/dev_tesla = 0						// 0: None, 1: Standard
	var/dev_nanoprint = 0					// 0: None, 1: Standard
	var/dev_card = 0						// 0: None, 1: Standard

CAPABILITIES(/obj/machinery/lapvend)
	owns_one(nameof(fabricated_laptop), /obj/item/modular_computer/laptop)
	owns_one(nameof(fabricated_tablet), /obj/item/modular_computer/tablet)
	interface("ComputerFabricator")
	without("ui_open")
	op("pick_device", ui_act("pick_device", arg("pick", num())), then(PROC_REF(ui_act_pick_device)))
	op("clean_order", ui_act("clean_order"), then(PROC_REF(ui_act_clean_order)))
	op("confirm_order", ui_act("confirm_order"), then(PROC_REF(ui_act_confirm_order)))
	op("hw_cpu", ui_act("hw_cpu", arg("cpu", num())), then(PROC_REF(ui_act_hw_cpu)))
	op("hw_battery", ui_act("hw_battery", arg("battery", num())), then(PROC_REF(ui_act_hw_battery)))
	op("hw_disk", ui_act("hw_disk", arg("disk", num())), then(PROC_REF(ui_act_hw_disk)))
	op("hw_netcard", ui_act("hw_netcard", arg("netcard", num())), then(PROC_REF(ui_act_hw_netcard)))
	op("hw_tesla", ui_act("hw_tesla", arg("tesla", num())), then(PROC_REF(ui_act_hw_tesla)))
	op("hw_nanoprint", ui_act("hw_nanoprint", arg("print", num())), then(PROC_REF(ui_act_hw_nanoprint)))
	op("hw_card", ui_act("hw_card", arg("card", num())), then(PROC_REF(ui_act_hw_card)))
	op("pay", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Pay"), then(PROC_REF(interaction_pay)))

// Removes all traces of old order and allows you to begin configuration from scratch.
/obj/machinery/lapvend/proc/reset_order()
	set_state(0)
	devtype = 0
	rel_clear(src, nameof(fabricated_laptop))
	rel_clear(src, nameof(fabricated_tablet))
	dev_cpu = 1
	dev_battery = 1
	dev_disk = 1
	dev_netcard = 0
	dev_tesla = 0
	dev_nanoprint = 0
	dev_card = 0

// Recalculates the price and optionally even fabricates the device.
/obj/machinery/lapvend/proc/fabricate_and_recalc_price(fabricate = 0)
	total_price = 0
	if(devtype == 1) 		// Laptop, generally cheaper to make it accessible for most station roles
		if(fabricate)
			rel_set(src, nameof(fabricated_laptop), new /obj/item/modular_computer/laptop(src))
		total_price = 99
		switch(dev_cpu)
			if(1)
				if(fabricate)
					rel_set(fabricated_laptop, nameof(fabricated_laptop.processor_unit), new/obj/item/computer_hardware/processor_unit/small(fabricated_laptop))
			if(2)
				if(fabricate)
					rel_set(fabricated_laptop, nameof(fabricated_laptop.processor_unit), new/obj/item/computer_hardware/processor_unit(fabricated_laptop))
				total_price += 299
		switch(dev_battery)
			if(1) // Basic(750C)
				if(fabricate)
					rel_set(fabricated_laptop, nameof(fabricated_laptop.battery_module), new/obj/item/computer_hardware/battery_module(fabricated_laptop))
			if(2) // Upgraded(1100C)
				if(fabricate)
					rel_set(fabricated_laptop, nameof(fabricated_laptop.battery_module), new/obj/item/computer_hardware/battery_module/advanced(fabricated_laptop))
				total_price += 199
			if(3) // Advanced(1500C)
				if(fabricate)
					rel_set(fabricated_laptop, nameof(fabricated_laptop.battery_module), new/obj/item/computer_hardware/battery_module/super(fabricated_laptop))
				total_price += 499
		switch(dev_disk)
			if(1) // Basic(128GQ)
				if(fabricate)
					rel_set(fabricated_laptop, nameof(fabricated_laptop.hard_drive), new/obj/item/computer_hardware/hard_drive(fabricated_laptop))
			if(2) // Upgraded(256GQ)
				if(fabricate)
					rel_set(fabricated_laptop, nameof(fabricated_laptop.hard_drive), new/obj/item/computer_hardware/hard_drive/advanced(fabricated_laptop))
				total_price += 99
			if(3) // Advanced(512GQ)
				if(fabricate)
					rel_set(fabricated_laptop, nameof(fabricated_laptop.hard_drive), new/obj/item/computer_hardware/hard_drive/super(fabricated_laptop))
				total_price += 299
		switch(dev_netcard)
			if(1) // Basic(Short-Range)
				if(fabricate)
					rel_set(fabricated_laptop, nameof(fabricated_laptop.network_card), new/obj/item/computer_hardware/network_card(fabricated_laptop))
				total_price += 99
			if(2) // Advanced (Long Range)
				if(fabricate)
					rel_set(fabricated_laptop, nameof(fabricated_laptop.network_card), new/obj/item/computer_hardware/network_card/advanced(fabricated_laptop))
				total_price += 299
		if(dev_tesla)
			total_price += 399
			if(fabricate)
				rel_set(fabricated_laptop, nameof(fabricated_laptop.tesla_link), new/obj/item/computer_hardware/tesla_link(fabricated_laptop))
		if(dev_nanoprint)
			total_price += 99
			if(fabricate)
				rel_set(fabricated_laptop, nameof(fabricated_laptop.nano_printer), new/obj/item/computer_hardware/nano_printer(fabricated_laptop))
		if(dev_card)
			total_price += 199
			if(fabricate)
				rel_set(fabricated_laptop, nameof(fabricated_laptop.card_slot), new/obj/item/computer_hardware/card_slot(fabricated_laptop))

		return total_price
	else if(devtype == 2) 	// Tablet, more expensive, not everyone could probably afford this.
		if(fabricate)
			rel_set(src, nameof(fabricated_tablet), new /obj/item/modular_computer/tablet(src))
			rel_set(fabricated_tablet, nameof(fabricated_tablet.processor_unit), new/obj/item/computer_hardware/processor_unit/small(fabricated_tablet))
		total_price = 199
		switch(dev_battery)
			if(1) // Basic(300C)
				if(fabricate)
					rel_set(fabricated_tablet, nameof(fabricated_tablet.battery_module), new/obj/item/computer_hardware/battery_module/nano(fabricated_tablet))
			if(2) // Upgraded(500C)
				if(fabricate)
					rel_set(fabricated_tablet, nameof(fabricated_tablet.battery_module), new/obj/item/computer_hardware/battery_module/micro(fabricated_tablet))
				total_price += 199
			if(3) // Advanced(750C)
				if(fabricate)
					rel_set(fabricated_tablet, nameof(fabricated_tablet.battery_module), new/obj/item/computer_hardware/battery_module(fabricated_tablet))
				total_price += 499
		switch(dev_disk)
			if(1) // Basic(32GQ)
				if(fabricate)
					rel_set(fabricated_tablet, nameof(fabricated_tablet.hard_drive), new/obj/item/computer_hardware/hard_drive/micro(fabricated_tablet))
			if(2) // Upgraded(64GQ)
				if(fabricate)
					rel_set(fabricated_tablet, nameof(fabricated_tablet.hard_drive), new/obj/item/computer_hardware/hard_drive/small(fabricated_tablet))
				total_price += 99
			if(3) // Advanced(128GQ)
				if(fabricate)
					rel_set(fabricated_tablet, nameof(fabricated_tablet.hard_drive), new/obj/item/computer_hardware/hard_drive(fabricated_tablet))
				total_price += 299
		switch(dev_netcard)
			if(1) // Basic(Short-Range)
				if(fabricate)
					rel_set(fabricated_tablet, nameof(fabricated_tablet.network_card), new/obj/item/computer_hardware/network_card(fabricated_tablet))
				total_price += 99
			if(2) // Advanced (Long Range)
				if(fabricate)
					rel_set(fabricated_tablet, nameof(fabricated_tablet.network_card), new/obj/item/computer_hardware/network_card/advanced(fabricated_tablet))
				total_price += 299
		if(dev_nanoprint)
			total_price += 99
			if(fabricate)
				rel_set(fabricated_tablet, nameof(fabricated_tablet.nano_printer), new/obj/item/computer_hardware/nano_printer(fabricated_tablet))
		if(dev_card)
			total_price += 199
			if(fabricate)
				rel_set(fabricated_tablet, nameof(fabricated_tablet.card_slot), new/obj/item/computer_hardware/card_slot(fabricated_tablet))
		if(dev_tesla)
			total_price += 399
			if(fabricate)
				rel_set(fabricated_tablet, nameof(fabricated_tablet.tesla_link), new/obj/item/computer_hardware/tesla_link(fabricated_tablet))
		return total_price
	return 0

/obj/machinery/lapvend/proc/ui_act_pick_device(datum/act/op/A, pick)
	if(state) // We've already picked a device type
		return FALSE
	devtype = pick
	set_state(1)
	fabricate_and_recalc_price(FALSE)
	return TRUE

/obj/machinery/lapvend/proc/ui_act_clean_order(datum/act/op/A)
	reset_order()
	return TRUE

/obj/machinery/lapvend/proc/ui_act_confirm_order(datum/act/op/A)
	if((state != 1) && devtype) // Following IFs should only be usable when in the Select Loadout mode
		return FALSE
	set_state(2) // Wait for ID swipe for payment processing
	fabricate_and_recalc_price(FALSE)
	return TRUE

/obj/machinery/lapvend/proc/ui_act_hw_cpu(datum/act/op/A, cpu)
	if((state != 1) && devtype) // Following IFs should only be usable when in the Select Loadout mode
		return FALSE
	dev_cpu = cpu
	fabricate_and_recalc_price(FALSE)
	return TRUE

/obj/machinery/lapvend/proc/ui_act_hw_battery(datum/act/op/A, battery)
	if((state != 1) && devtype) // Following IFs should only be usable when in the Select Loadout mode
		return FALSE
	dev_battery = battery
	fabricate_and_recalc_price(FALSE)
	return TRUE

/obj/machinery/lapvend/proc/ui_act_hw_disk(datum/act/op/A, disk)
	if((state != 1) && devtype) // Following IFs should only be usable when in the Select Loadout mode
		return FALSE
	dev_disk = disk
	fabricate_and_recalc_price(FALSE)
	return TRUE

/obj/machinery/lapvend/proc/ui_act_hw_netcard(datum/act/op/A, netcard)
	if((state != 1) && devtype) // Following IFs should only be usable when in the Select Loadout mode
		return FALSE
	dev_netcard = netcard
	fabricate_and_recalc_price(FALSE)
	return TRUE

/obj/machinery/lapvend/proc/ui_act_hw_tesla(datum/act/op/A, tesla)
	if((state != 1) && devtype) // Following IFs should only be usable when in the Select Loadout mode
		return FALSE
	dev_tesla = tesla
	fabricate_and_recalc_price(FALSE)
	return TRUE

/obj/machinery/lapvend/proc/ui_act_hw_nanoprint(datum/act/op/A, print)
	if((state != 1) && devtype) // Following IFs should only be usable when in the Select Loadout mode
		return FALSE
	dev_nanoprint = print
	fabricate_and_recalc_price(FALSE)
	return TRUE

/obj/machinery/lapvend/proc/ui_act_hw_card(datum/act/op/A, card)
	if((state != 1) && devtype) // Following IFs should only be usable when in the Select Loadout mode
		return FALSE
	dev_card = card
	fabricate_and_recalc_price(FALSE)
	return TRUE



/obj/machinery/lapvend/ui_prepare(mob/user, datum/tgui/ui)
	if(!operable())
		return FALSE

	return TRUE

/// /obj/machinery/lapvend's window data.
/obj/machinery/lapvend/ui_data(datum/act/eval/A)
	var/list/data = list()

	data["state"] = state
	if(state == 1)
		data["devtype"] = devtype
		data["hw_battery"] = dev_battery
		data["hw_disk"] = dev_disk
		data["hw_netcard"] = dev_netcard
		data["hw_tesla"] = dev_tesla
		data["hw_nanoprint"] = dev_nanoprint
		data["hw_card"] = dev_card
		data["hw_cpu"] = dev_cpu
	if(state == 1 || state == 2)
		data["totalprice"] = total_price

	return data

/obj/machinery/lapvend/proc/interaction_pay(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	var/obj/item/card/id/I = W.GetID()
	// Awaiting payment state
	if(state == 2)
		if(process_payment(user, I,W))
			fabricate_and_recalc_price(1)
			if((devtype == 1) && fabricated_laptop)
				if(fabricated_laptop.battery_module)
					fabricated_laptop.battery_module.charge_to_full()
				fabricated_laptop.forceMove(src.loc)
				fabricated_laptop.screen_on = 0
				fabricated_laptop.set_anchored(FALSE)
				fabricated_laptop.update_icon()
				rel_take(src, nameof(fabricated_laptop))
			else if((devtype == 2) && fabricated_tablet)
				if(fabricated_tablet.battery_module)
					fabricated_tablet.battery_module.charge_to_full()
				fabricated_tablet.forceMove(src.loc)
				rel_take(src, nameof(fabricated_tablet))
			ping("Enjoy your new product!")
			set_state(3)
			return TRUE
		return TRUE
	return OP_DECLINE

// Simplified payment processing, returns 1 on success.
/obj/machinery/lapvend/proc/process_payment(mob/user, obj/item/card/id/I, obj/item/ID_container)
	if(I==ID_container || ID_container == null)
		act_message(user, src, others = span_info("%U% swipes %I% through %T%."), item = I)
	else
		act_message(user, src, others = span_info("%U% swipes %I% through %T%."), item = ID_container)
	var/datum/money_account/customer_account = get_account(I.associated_account_number)
	if (!customer_account || customer_account.suspended)
		ping("Connection error. Unable to connect to account.")
		return 0

	if(customer_account.security_level != 0) //If card requires pin authentication (ie seclevel 1 or 2)
		var/attempt_pin = rerun_ask(user, "k299", PROC_REF(process_payment), args, /datum/prompt/number, question = "Enter pin code", title = "Vendor transaction")
		if(isnull(attempt_pin))
			return
		customer_account = attempt_account_access(I.associated_account_number, attempt_pin, 2)

		if(!customer_account)
			ping("Unable to access account: incorrect credentials.")
			return 0

	if(total_price > customer_account.money)
		ping("Insufficient funds in account.")
		return 0
	else
		return customer_account.debit(total_price, "Computer Manufacturer", "Purchase of [(devtype == 1) ? "laptop computer" : "tablet microcomputer"]", name)

