/obj/item/clothing/accessory/storage
	name = "load bearing equipment"
	desc = "Used to hold things when you don't have enough hands."
	icon_state = "webbing"
	slot = ACCESSORY_SLOT_UTILITY
	show_messages = 1

	var/slots = 5
	var/obj/item/storage/internal/hold // owned: the internal storage object that holds the webbing's contents
	w_class = ITEMSIZE_NORMAL
	on_rolled = list("down" = "none")
	var/hide_on_roll = FALSE
	special_handling = TRUE

CAPABILITIES(/obj/item/clothing/accessory/storage)
	owns_one(nameof(hold), starts = /obj/item/storage/internal)
	op("storage_accessory_hand", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Storage accessory hand"), then(PROC_REF(storage_accessory_hand)))
	op("storage_accessory_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Storage accessory item"), then(PROC_REF(storage_accessory_item)))
	op("storage_accessory_empty_self", in_hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Empty"), then(PROC_REF(storage_accessory_empty_self)))

/obj/item/clothing/accessory/storage/Initialize(mapload)
	. = ..()
	hold.max_storage_space = slots * 2
	if (!hide_on_roll)
		on_rolled["down"] = icon_state


/// Old attack_hand: open the storage when attached, else handle it as a storage item.
/obj/item/clothing/accessory/storage/proc/storage_accessory_hand(datum/act/op/A)
	var/mob/user = A.actor
	if (has_suit())	//if we are part of a suit
		hold.open(user)
		return OP_OK

	if (hold.handle_attack_hand(user))	//otherwise interact as a regular storage item
		return OP_DECLINE
	return OP_OK

/obj/item/clothing/accessory/storage/MouseDrop(obj/over_object)
	if (has_suit())
		return

	if (hold.handle_mousedrop(usr, over_object))
		..(over_object)

/// Old attackby: the item goes to the internal storage.
/obj/item/clothing/accessory/storage/proc/storage_accessory_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	return hold.attackby(W, user) ? OP_OK : OP_PASS

/// Old attack_self: empty the storage.
/obj/item/clothing/accessory/storage/proc/storage_accessory_empty_self(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("You empty [src]."))
	var/turf/T = get_turf(src)
	hold.hide_from(user)
	for(var/obj/item/I in contents_of(hold))
		hold.remove_from_storage(I, T, user)
	add_fingerprint(user)

/obj/item/clothing/accessory/storage/webbing
	name = "webbing"
	desc = "Sturdy mess of synthcotton belts and buckles, ready to share your burden."
	icon_state = "webbing"
	slots = 3

/obj/item/clothing/accessory/storage/black_vest
	name = "black webbing vest"
	desc = "Robust black synthcotton vest with lots of pockets to hold whatever you need, but cannot hold in hands."
	icon_state = "vest_black"

/obj/item/clothing/accessory/storage/brown_vest
	name = "brown webbing vest"
	desc = "Worn brownish synthcotton vest with lots of pockets to unload your hands."
	icon_state = "vest_brown"

/obj/item/clothing/accessory/storage/white_vest
	name = "white webbing vest"
	desc = "Durable white synthcotton vest with lots of pockets to carry essentials."
	icon_state = "vest_white"

/obj/item/clothing/accessory/storage/black_drop_pouches
	name = "black drop pouches"
	gender = PLURAL
	desc = "Robust black synthcotton bags to hold whatever you need, but cannot hold in hands."
	icon_state = "thigh_black"

/obj/item/clothing/accessory/storage/brown_drop_pouches
	name = "brown drop pouches"
	gender = PLURAL
	desc = "Worn brownish synthcotton bags to hold whatever you need, but cannot hold in hands."
	icon_state = "thigh_brown"

/obj/item/clothing/accessory/storage/white_drop_pouches
	name = "white drop pouches"
	gender = PLURAL
	desc = "Durable white synthcotton bags to hold whatever you need, but cannot hold in hands."
	icon_state = "thigh_white"

/obj/item/clothing/accessory/storage/knifeharness
	name = "decorated harness"
	desc = "A heavily decorated harness of sinew and leather with two knife-loops."
	icon_state = "unathiharness2"
	slots = 2

/obj/item/clothing/accessory/storage/knifeharness/Initialize(mapload)
	. = ..()
	hold.max_storage_space = ITEMSIZE_COST_SMALL * 2
	var/static/list/knives = list(/obj/item/material/knife/machete/hatchet/unathiknife, /obj/item/material/knife, /obj/item/material/knife/plastic)
	hold.restrict_hold(knives)

	new /obj/item/material/knife/machete/hatchet/unathiknife(hold)
	new /obj/item/material/knife/machete/hatchet/unathiknife(hold)

/obj/item/clothing/accessory/storage/bluespace
	name = "bluespace badge"
	desc = "A small, shielded device capable of holding a number of items in it. Used for carrying items discreetly."
	icon_state = "solbadge"
	item_state = "badge"
