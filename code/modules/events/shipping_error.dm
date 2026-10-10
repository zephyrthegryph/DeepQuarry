/datum/event/shipping_error/start()
	var/datum/supply_order/O = new /datum/supply_order()
	O.ordernum = supply_ordernum()
	O.supply_pack_static = supply_supply_pack()[pick(supply_supply_pack())]
	O.ordered_by = random_name(pick(MALE,FEMALE), species = SPECIES_HUMAN)
	SSsupply.shoppinglist += O
