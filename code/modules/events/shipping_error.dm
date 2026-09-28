/datum/event/shipping_error/start()
	var/datum/supply_order/O = new /datum/supply_order()
	O.ordernum = GLOB.supply_service.ordernum
	O.supply_pack_static = GLOB.supply_service.supply_pack[pick(GLOB.supply_service.supply_pack)]
	O.ordered_by = random_name(pick(MALE,FEMALE), species = SPECIES_HUMAN)
	GLOB.supply_service.shoppinglist += O
